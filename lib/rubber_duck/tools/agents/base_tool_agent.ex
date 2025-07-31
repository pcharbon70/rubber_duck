defmodule RubberDuck.Tools.Agents.BaseToolAgent do
  @moduledoc """
  Base module for tool-specific agents that orchestrate RubberDuck tools.
  
  This module provides common functionality for agents that wrap individual tools,
  including:
  - Standard signal patterns for tool execution
  - Integration with the Tool System Executor
  - Result caching and metrics tracking
  - Rate limiting and error handling
  
  ## Usage
  
      defmodule MyToolAgent do
        use RubberDuck.Tools.Agents.BaseToolAgent,
          tool: :my_tool,
          name: "my_tool_agent",
          description: "Agent for MyTool",
          cache_ttl: 300_000  # 5 minutes
      end
  """
  
  @doc """
  Callback for validating tool parameters before execution.
  """
  @callback validate_params(params :: map()) :: {:ok, map()} | {:error, term()}
  
  @doc """
  Callback for processing tool results before sending signals.
  """
  @callback process_result(result :: map(), request :: map()) :: map()
  
  @doc """
  Callback for handling tool-specific signals.
  """
  @callback handle_tool_signal(agent :: map(), signal :: map()) :: {:ok, map()} | {:error, term()}
  
  @optional_callbacks [
    validate_params: 1,
    process_result: 2,
    handle_tool_signal: 2
  ]
  
  defmacro __using__(opts) do
    tool_name = Keyword.fetch!(opts, :tool)
    cache_ttl = Keyword.get(opts, :cache_ttl, 300_000) # 5 minutes default
    
    # Merge default schema with any provided schema
    default_schema = [
      # Request tracking
      active_requests: [type: :map, default: %{}],
      request_queue: [type: {:list, :map}, default: []],
      
      # Caching
      results_cache: [type: :map, default: %{}],
      cache_ttl: [type: :integer, default: cache_ttl],
      
      # Metrics
      metrics: [type: :map, default: %{
        total_requests: 0,
        successful_requests: 0,
        failed_requests: 0,
        cache_hits: 0,
        average_execution_time: 0,
        last_request_at: nil
      }],
      
      # Rate limiting
      rate_limit_window: [type: :integer, default: 60_000], # 1 minute
      rate_limit_max: [type: :integer, default: 100],
      rate_limit_requests: [type: {:list, :integer}, default: []],
      
      # Tool configuration
      tool_name: [type: :atom, default: tool_name],
      tool_timeout: [type: :integer, default: 30_000]
    ]
    
    user_schema = Keyword.get(opts, :schema, [])
    combined_schema = Keyword.merge(default_schema, user_schema)
    
    # Update opts with combined schema
    updated_opts = Keyword.put(opts, :schema, combined_schema)
    
    quote do
      use RubberDuck.Agents.BaseAgent, unquote(updated_opts)
      
      @behaviour RubberDuck.Tools.Agents.BaseToolAgent
      
      alias RubberDuck.ToolSystem.Executor
      require Logger
      
      # Standard signal handlers
      
      @impl true
      def handle_signal(agent, %{"type" => "tool_request"} = signal) do
        %{"data" => data} = signal
        request_id = data["request_id"] || generate_request_id()
        
        # Check rate limit
        case check_rate_limit(agent) do
          {:ok, agent} ->
            # Check cache first
            cache_key = generate_cache_key(data["params"] || %{})
            
            case get_cached_result(agent, cache_key) do
              {:ok, cached_result} ->
                # Send cached result
                emit_signal("tool_result", %{
                  "request_id" => request_id,
                  "result" => cached_result,
                  "from_cache" => true,
                  "tool" => unquote(tool_name)
                })
                
                # Update metrics
                agent = update_metrics(agent, :cache_hit)
                {:ok, agent}
                
              :not_found ->
                # Add to queue and process
                request = %{
                  id: request_id,
                  params: data["params"] || %{},
                  priority: data["priority"] || :normal,
                  created_at: System.monotonic_time(:millisecond),
                  cache_key: cache_key
                }
                
                agent = add_request_to_queue(agent, request)
                
                # Process immediately if no active requests
                if map_size(agent.state.active_requests) == 0 do
                  process_next_request(agent)
                else
                  {:ok, agent}
                end
            end
            
          {:error, :rate_limited} ->
            emit_signal("tool_error", %{
              "request_id" => request_id,
              "error" => "Rate limit exceeded",
              "retry_after" => calculate_retry_after(agent)
            })
            {:ok, agent}
        end
      end
      
      def handle_signal(agent, %{"type" => "cancel_request"} = signal) do
        request_id = get_in(signal, ["data", "request_id"])
        
        # Remove from queue if present
        agent = update_in(agent.state.request_queue, fn queue ->
          Enum.reject(queue, &(&1.id == request_id))
        end)
        
        # Mark as cancelled if active
        agent = if Map.has_key?(agent.state.active_requests, request_id) do
          put_in(agent.state.active_requests[request_id][:cancelled], true)
        else
          agent
        end
        
        emit_signal("request_cancelled", %{
          "request_id" => request_id
        })
        
        {:ok, agent}
      end
      
      def handle_signal(agent, %{"type" => "get_metrics"} = _signal) do
        emit_signal("metrics_report", %{
          "metrics" => agent.state.metrics,
          "cache_size" => map_size(agent.state.results_cache),
          "queue_length" => length(agent.state.request_queue),
          "active_requests" => map_size(agent.state.active_requests)
        })
        
        {:ok, agent}
      end
      
      def handle_signal(agent, %{"type" => "clear_cache"} = _signal) do
        agent = put_in(agent.state.results_cache, %{})
        
        emit_signal("cache_cleared", %{
          "tool" => unquote(tool_name)
        })
        
        {:ok, agent}
      end
      
      def handle_signal(agent, signal) do
        # Try tool-specific handler if implemented
        if function_exported?(__MODULE__, :handle_tool_signal, 2) do
          __MODULE__.handle_tool_signal(agent, signal)
        else
          Logger.warning("#{__MODULE__} received unknown signal: #{inspect(signal["type"])}")
          {:ok, agent}
        end
      end
      
      # Private helpers
      
      defp generate_request_id do
        "#{unquote(tool_name)}_#{System.unique_integer([:positive, :monotonic])}"
      end
      
      defp check_rate_limit(agent) do
        now = System.monotonic_time(:millisecond)
        window_start = now - agent.state.rate_limit_window
        
        # Filter requests within window
        recent_requests = agent.state.rate_limit_requests
        |> Enum.filter(&(&1 > window_start))
        
        if length(recent_requests) < agent.state.rate_limit_max do
          agent = put_in(agent.state.rate_limit_requests, [now | recent_requests])
          {:ok, agent}
        else
          {:error, :rate_limited}
        end
      end
      
      defp calculate_retry_after(agent) do
        if length(agent.state.rate_limit_requests) > 0 do
          oldest = Enum.min(agent.state.rate_limit_requests)
          window_end = oldest + agent.state.rate_limit_window
          now = System.monotonic_time(:millisecond)
          max(0, div(window_end - now, 1000)) # Convert to seconds
        else
          60 # Default to 60 seconds
        end
      end
      
      defp generate_cache_key(params) do
        params
        |> :erlang.term_to_binary()
        |> :crypto.hash(:sha256)
        |> Base.encode16(case: :lower)
      end
      
      defp get_cached_result(agent, cache_key) do
        case agent.state.results_cache[cache_key] do
          nil -> 
            :not_found
            
          %{result: result, cached_at: cached_at} ->
            age = System.monotonic_time(:millisecond) - cached_at
            if age < agent.state.cache_ttl do
              {:ok, result}
            else
              :not_found
            end
        end
      end
      
      defp add_request_to_queue(agent, request) do
        # Add to queue sorted by priority
        update_in(agent.state.request_queue, fn queue ->
          [request | queue]
          |> Enum.sort_by(& &1.priority, fn
            :high, :high -> :eq
            :high, _ -> :lt
            :normal, :high -> :gt
            :normal, :normal -> :eq
            :normal, :low -> :lt
            :low, :low -> :eq
            :low, _ -> :gt
          end)
        end)
      end
      
      defp process_next_request(agent) do
        case agent.state.request_queue do
          [] ->
            {:ok, agent}
            
          [request | rest] ->
            # Move to active requests
            agent = agent
            |> put_in([:state, :request_queue], rest)
            |> put_in([:state, :active_requests, request.id], request)
            
            # Emit progress signal
            emit_signal("tool_progress", %{
              "request_id" => request.id,
              "status" => "started",
              "tool" => unquote(tool_name)
            })
            
            # Start async execution
            Task.start(fn ->
              execute_tool_request(request, unquote(tool_name))
            end)
            
            {:ok, agent}
        end
      end
      
      defp execute_tool_request(request, tool_name) do
        start_time = System.monotonic_time(:millisecond)
        
        try do
          # Validate params if callback implemented
          validated_params = if function_exported?(__MODULE__, :validate_params, 1) do
            case __MODULE__.validate_params(request.params) do
              {:ok, params} -> params
              {:error, reason} -> throw({:validation_error, reason})
            end
          else
            request.params
          end
          
          # Execute tool
          case Executor.execute(tool_name, validated_params) do
            {:ok, result} ->
              # Process result if callback implemented
              processed_result = if function_exported?(__MODULE__, :process_result, 2) do
                __MODULE__.process_result(result, request)
              else
                result
              end
              
              # Calculate execution time
              execution_time = System.monotonic_time(:millisecond) - start_time
              
              # Emit success signal
              emit_signal("tool_result", %{
                "request_id" => request.id,
                "result" => processed_result,
                "execution_time" => execution_time,
                "tool" => tool_name
              })
              
              # Update metrics (agent will handle in signal)
              emit_signal("_internal_tool_complete", %{
                "request_id" => request.id,
                "cache_key" => request.cache_key,
                "result" => processed_result,
                "execution_time" => execution_time,
                "success" => true
              })
              
            {:error, reason} ->
              emit_signal("tool_error", %{
                "request_id" => request.id,
                "error" => format_error(reason),
                "tool" => tool_name
              })
              
              emit_signal("_internal_tool_complete", %{
                "request_id" => request.id,
                "success" => false
              })
          end
        catch
          {:validation_error, reason} ->
            emit_signal("tool_error", %{
              "request_id" => request.id,
              "error" => "Validation failed: #{inspect(reason)}",
              "tool" => tool_name
            })
            
            emit_signal("_internal_tool_complete", %{
              "request_id" => request.id,
              "success" => false
            })
        rescue
          error ->
            emit_signal("tool_error", %{
              "request_id" => request.id,
              "error" => Exception.message(error),
              "tool" => tool_name
            })
            
            emit_signal("_internal_tool_complete", %{
              "request_id" => request.id,
              "success" => false
            })
        end
      end
      
      defp format_error(reason) when is_binary(reason), do: reason
      defp format_error(reason), do: inspect(reason)
      
      defp update_metrics(agent, :cache_hit) do
        update_in(agent.state.metrics.cache_hits, &(&1 + 1))
      end
      
      defp update_metrics(agent, {:execution_complete, execution_time, success}) do
        agent
        |> update_in([:state, :metrics, :total_requests], &(&1 + 1))
        |> update_in([:state, :metrics, if(success, do: :successful_requests, else: :failed_requests)], &(&1 + 1))
        |> update_in([:state, :metrics], fn metrics ->
          # Update average execution time
          current_avg = metrics.average_execution_time || 0
          total = metrics.successful_requests
          new_avg = if total > 0 do
            ((current_avg * (total - 1)) + execution_time) / total
          else
            execution_time
          end
          
          metrics
          |> Map.put(:average_execution_time, new_avg)
          |> Map.put(:last_request_at, DateTime.utc_now())
        end)
      end
      
      # Override handle_signal to include internal completion handling
      def handle_signal(agent, %{"type" => "_internal_tool_complete"} = signal) do
        %{"data" => data} = signal
        request_id = data["request_id"]
        
        # Remove from active requests
        agent = update_in(agent.state.active_requests, &Map.delete(&1, request_id))
        
        # Cache result if successful
        agent = if data["success"] && data["result"] do
          cache_entry = %{
            result: data["result"],
            cached_at: System.monotonic_time(:millisecond)
          }
          put_in(agent.state.results_cache[data["cache_key"]], cache_entry)
        else
          agent
        end
        
        # Update metrics
        agent = if data["execution_time"] do
          update_metrics(agent, {:execution_complete, data["execution_time"], data["success"]})
        else
          agent
        end
        
        # Process next request
        process_next_request(agent)
      end
      
      # Default implementations for optional callbacks
      def validate_params(params), do: {:ok, params}
      def process_result(result, _request), do: result
      def handle_tool_signal(_agent, _signal), do: {:error, :not_implemented}
      
      # Allow overriding these functions
      defoverridable [
        handle_signal: 2,
        validate_params: 1,
        process_result: 2,
        handle_tool_signal: 2
      ]
    end
  end
end