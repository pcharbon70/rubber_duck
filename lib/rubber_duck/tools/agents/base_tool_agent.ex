defmodule RubberDuck.Tools.Agents.BaseToolAgent do
  @moduledoc """
  Base module for tool-specific agents that orchestrate RubberDuck tools.
  
  This module provides common functionality for agents that wrap individual tools,
  including:
  - Action-based tool execution with parameter validation
  - Integration with the Tool System Executor
  - Result caching and metrics tracking
  - Rate limiting and error handling
  - Signal-based communication
  
  ## Usage
  
      defmodule MyToolAgent do
        use RubberDuck.Tools.Agents.BaseToolAgent,
          tool: :my_tool,
          name: "my_tool_agent",
          description: "Agent for MyTool",
          cache_ttl: 300_000  # 5 minutes
      end
  
  This will automatically create:
  - MyToolAgent.ExecuteToolAction - Main tool execution action
  - MyToolAgent.ClearCacheAction - Cache management action
  - MyToolAgent.GetMetricsAction - Metrics reporting action
  """
  
  @doc """
  Callback for validating tool parameters before execution.
  """
  @callback validate_params(params :: map()) :: {:ok, map()} | {:error, term()}
  
  @doc """
  Callback for processing tool results before sending signals.
  """
  @callback process_result(result :: map(), context :: map()) :: map()
  
  @doc """
  Callback for handling tool-specific signals.
  """
  @callback handle_tool_signal(agent :: map(), signal :: map()) :: {:ok, map()} | {:error, term()}
  
  @doc """
  Callback for defining additional tool-specific actions.
  Returns a list of action modules that the agent should register.
  """
  @callback additional_actions() :: [module()]
  
  @optional_callbacks [
    validate_params: 1,
    process_result: 2,
    handle_tool_signal: 2,
    additional_actions: 0
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
    
    quote do
      # First define the action modules
      defmodule ExecuteToolAction do
        @moduledoc false
        use Jido.Action,
          name: "execute_tool",
          description: "Execute the #{unquote(tool_name)} tool",
          schema: [
            params: [type: :map, default: %{}],
            priority: [type: :atom, values: [:low, :normal, :high], default: :normal],
            cache_key: [type: :string, required: false]
          ]
        
        alias RubberDuck.ToolSystem.Executor
        
        @impl true
        def run(params, context) do
          tool_name = unquote(tool_name)
          agent = context.agent
          
          # Check cache first if cache_key provided
          cached_result = if params[:cache_key] && agent do
            case get_cached_result(agent, params.cache_key) do
              {:ok, result} -> result
              :not_found -> nil
            end
          end
          
          if cached_result do
            {:ok, %{result: cached_result, from_cache: true, tool: tool_name}}
          else
            # Validate params if parent module has validator
            validated_params = if function_exported?(context.parent_module, :validate_params, 1) do
              case context.parent_module.validate_params(params.params) do
                {:ok, validated} -> validated
                {:error, reason} -> {:error, {:validation_failed, reason}}
              end
            else
              params.params
            end
            
            case validated_params do
              {:error, _} = error -> error
              _ ->
                # Execute tool
                start_time = System.monotonic_time(:millisecond)
                
                case Executor.execute(tool_name, validated_params) do
                  {:ok, result} ->
                    execution_time = System.monotonic_time(:millisecond) - start_time
                    
                    # Process result if callback exists
                    processed_result = if function_exported?(context.parent_module, :process_result, 2) do
                      context.parent_module.process_result(result, context)
                    else
                      result
                    end
                    
                    {:ok, %{
                      result: processed_result,
                      execution_time: execution_time,
                      tool: tool_name,
                      from_cache: false
                    }}
                    
                  {:error, reason} ->
                    {:error, reason}
                end
            end
          end
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
      end
      
      defmodule ClearCacheAction do
        @moduledoc false
        use Jido.Action,
          name: "clear_cache",
          description: "Clear the results cache",
          schema: []
        
        @impl true
        def run(_params, context) do
          {:ok, %{cleared_at: DateTime.utc_now(), tool: unquote(tool_name)}}
        end
      end
      
      defmodule GetMetricsAction do
        @moduledoc false
        use Jido.Action,
          name: "get_metrics",
          description: "Get current agent metrics",
          schema: []
        
        @impl true
        def run(_params, context) do
          agent = context.agent
          metrics = Map.merge(agent.state.metrics, %{
            cache_size: map_size(agent.state.results_cache),
            queue_length: length(agent.state.request_queue),
            active_requests: map_size(agent.state.active_requests)
          })
          
          {:ok, metrics}
        end
      end
      
      # Now define the agent module
      @behaviour RubberDuck.Tools.Agents.BaseToolAgent
      
      alias RubberDuck.ToolSystem.Executor
      require Logger
      
      # Build base actions list
      @base_actions [__MODULE__.ExecuteToolAction, __MODULE__.ClearCacheAction, __MODULE__.GetMetricsAction]
      
      # Build complete options for use macro
      def __base_tool_agent_opts__ do
        # Get additional actions dynamically
        additional = if function_exported?(__MODULE__, :additional_actions, 0) do
          __MODULE__.additional_actions()
        else
          []
        end
        
        unquote(opts)
        |> Keyword.put(:schema, unquote(combined_schema))
        |> Keyword.put(:actions, @base_actions ++ additional)
      end
      
      use RubberDuck.Agents.BaseAgent, __base_tool_agent_opts__()
      
      # Handler for action results
      @impl true
      def handle_action_result(agent, action, result, metadata) do
        case action do
          ExecuteToolAction ->
            handle_execute_tool_result(agent, result, metadata)
            
          ClearCacheAction ->
            # Clear cache and emit signal
            agent = put_in(agent.state.results_cache, %{})
            signal = Jido.Signal.new!(%{
              type: "tool.cache.cleared",
              source: "agent:#{agent.id}",
              data: result
            })
            emit_signal(agent, signal)
            {:ok, agent}
            
          GetMetricsAction ->
            # Emit metrics signal
            signal = Jido.Signal.new!(%{
              type: "tool.metrics.report",
              source: "agent:#{agent.id}",
              data: result
            })
            emit_signal(agent, signal)
            {:ok, agent}
            
          _ ->
            # Let parent handle unknown actions
            super(agent, action, result, metadata)
        end
      end
      
      defp handle_execute_tool_result(agent, {:ok, result}, metadata) do
        request_id = metadata[:request_id]
        
        # Update cache if not from cache
        agent = if result[:from_cache] == false && metadata[:cache_key] do
          cache_entry = %{
            result: result.result,
            cached_at: System.monotonic_time(:millisecond)
          }
          put_in(agent.state.results_cache[metadata[:cache_key]], cache_entry)
        else
          agent
        end
        
        # Update metrics
        agent = if result[:from_cache] do
          update_metrics(agent, :cache_hit)
        else
          update_metrics(agent, {:execution_complete, result[:execution_time] || 0, true})
        end
        
        # Remove from active requests
        agent = if request_id do
          update_in(agent.state.active_requests, &Map.delete(&1, request_id))
        else
          agent
        end
        
        # Emit result signal
        signal = Jido.Signal.new!(%{
          type: "tool.result",
          source: "agent:#{agent.id}",
          data: Map.merge(result, %{request_id: request_id})
        })
        emit_signal(agent, signal)
        
        # Process next request
        process_next_request(agent)
      end
      
      defp handle_execute_tool_result(agent, {:error, reason}, metadata) do
        request_id = metadata[:request_id]
        
        # Update metrics
        agent = update_metrics(agent, {:execution_complete, 0, false})
        
        # Remove from active requests
        agent = if request_id do
          update_in(agent.state.active_requests, &Map.delete(&1, request_id))
        else
          agent
        end
        
        # Emit error signal
        signal = Jido.Signal.new!(%{
          type: "tool.error",
          source: "agent:#{agent.id}",
          data: %{
            request_id: request_id,
            error: format_error(reason),
            tool: unquote(tool_name)
          }
        })
        emit_signal(agent, signal)
        
        # Process next request
        process_next_request(agent)
      end
      
      # Standard signal handlers for backwards compatibility and signal-based communication
      
      @impl true
      def handle_signal(agent, %{"type" => "tool_request"} = signal) do
        %{"data" => data} = signal
        request_id = data["request_id"] || generate_request_id()
        
        # Check rate limit
        case check_rate_limit(agent) do
          {:ok, agent} ->
            # Build action params
            cache_key = generate_cache_key(data["params"] || %{})
            params = %{
              params: data["params"] || %{},
              priority: data["priority"] || :normal,
              cache_key: cache_key
            }
            
            # Add request to active tracking
            request = %{
              id: request_id,
              params: data["params"] || %{},
              priority: data["priority"] || :normal,
              created_at: System.monotonic_time(:millisecond),
              cache_key: cache_key
            }
            
            agent = add_request_to_queue(agent, request)
            
            # Process if no active requests
            if map_size(agent.state.active_requests) == 0 do
              agent = agent
              |> update_in([:state, :request_queue], fn [_ | rest] -> rest end)
              |> put_in([:state, :active_requests, request_id], request)
              
              # Execute action with context
              context = %{
                agent: agent,
                parent_module: __MODULE__,
                request_id: request_id
              }
              
              # Use async execution
              {:ok, _ref} = __MODULE__.cmd_async(agent, ExecuteToolAction, params, 
                context: context,
                metadata: %{request_id: request_id, cache_key: cache_key}
              )
              
              # Emit progress signal
              signal = Jido.Signal.new!(%{
                type: "tool.progress",
                source: "agent:#{agent.id}",
                data: %{
                  request_id: request_id,
                  status: "started",
                  tool: unquote(tool_name)
                }
              })
              emit_signal(agent, signal)
              
              {:ok, agent}
            else
              {:ok, agent}
            end
            
          {:error, :rate_limited} ->
            signal = Jido.Signal.new!(%{
              type: "tool.error",
              source: "agent:#{agent.id}",
              data: %{
                request_id: request_id,
                error: "Rate limit exceeded",
                retry_after: calculate_retry_after(agent)
              }
            })
            emit_signal(agent, signal)
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
        
        signal = Jido.Signal.new!(%{
          type: "tool.request.cancelled",
          source: "agent:#{agent.id}",
          data: %{
            request_id: request_id
          }
        })
        emit_signal(agent, signal)
        
        {:ok, agent}
      end
      
      def handle_signal(agent, %{"type" => "get_metrics"} = _signal) do
        # Execute metrics action
        {:ok, _ref} = __MODULE__.cmd_async(agent, GetMetricsAction, %{}, 
          context: %{agent: agent}
        )
        {:ok, agent}
      end
      
      def handle_signal(agent, %{"type" => "clear_cache"} = _signal) do
        # Execute clear cache action
        {:ok, _ref} = __MODULE__.cmd_async(agent, ClearCacheAction, %{},
          context: %{agent: agent}
        )
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
            
            # Build action params
            params = %{
              params: request.params,
              priority: request.priority,
              cache_key: request.cache_key
            }
            
            # Execute action with context
            context = %{
              agent: agent,
              parent_module: __MODULE__,
              request_id: request.id
            }
            
            # Use async execution
            {:ok, _ref} = __MODULE__.cmd_async(agent, ExecuteToolAction, params,
              context: context,
              metadata: %{request_id: request.id, cache_key: request.cache_key}
            )
            
            # Emit progress signal
            signal = Jido.Signal.new!(%{
              type: "tool.progress",
              source: "agent:#{agent.id}",
              data: %{
                request_id: request.id,
                status: "started",
                tool: unquote(tool_name)
              }
            })
            emit_signal(agent, signal)
            
            {:ok, agent}
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
      
      # Add overridable flag for handle_action_result
      defoverridable [handle_action_result: 4]
      
      # Default implementations for optional callbacks
      def validate_params(params), do: {:ok, params}
      def process_result(result, _context), do: result
      def handle_tool_signal(_agent, _signal), do: {:error, :not_implemented}
      def additional_actions(), do: []
      
      # Allow overriding these functions
      defoverridable [
        handle_signal: 2,
        validate_params: 1,
        process_result: 2,
        handle_tool_signal: 2,
        additional_actions: 0
      ]
    end
  end
end