defmodule RubberDuck.Interface.Adapters.Base do
  @moduledoc """
  Provides common functionality for all interface adapters via a `use` macro.
  
  This module injects shared behavior, helper functions, and default
  implementations to reduce boilerplate in adapter implementations.
  
  ## Usage
  
      defmodule MyAdapter do
        use RubberDuck.Interface.Adapters.Base
        
        @impl true
        def handle_request(request, context, state) do
          # Your adapter-specific logic here
        end
      end
  """

  @doc """
  Injects common functionality into adapter modules.
  
  ## Options
  
  - `:default_timeout` - Default request timeout in milliseconds (default: 30_000)
  - `:max_retries` - Maximum retry attempts for failed requests (default: 3)
  - `:log_requests` - Whether to log all requests (default: true)
  - `:collect_metrics` - Whether to collect metrics (default: true)
  """
  defmacro __using__(opts \\ []) do
    quote do
      @behaviour RubberDuck.Interface.Behaviour
      
      alias RubberDuck.Interface.{Behaviour, ErrorHandler, Transformer}
      alias RubberDuck.EventBroadcasting.EventBroadcaster
      alias RubberDuck.EventSchemas
      
      require Logger
      
      # Configuration from use options
      @default_timeout unquote(Keyword.get(opts, :default_timeout, 30_000))
      @max_retries unquote(Keyword.get(opts, :max_retries, 3))
      @log_requests unquote(Keyword.get(opts, :log_requests, true))
      @collect_metrics unquote(Keyword.get(opts, :collect_metrics, true))
      
      # Default implementations that can be overridden
      
      @impl true
      def init(opts) do
        state = %{
          config: Keyword.get(opts, :config, %{}),
          start_time: System.monotonic_time(:millisecond),
          request_count: 0,
          error_count: 0,
          metrics: %{},
          circuit_breaker: %{
            failure_count: 0,
            last_failure: nil,
            state: :closed
          }
        }
        
        {:ok, state}
      end
      
      @impl true
      def validate_request(request) do
        # Basic validation that can be extended
        cond do
          not is_map(request) ->
            {:error, ["Request must be a map"]}
            
          not Map.has_key?(request, :operation) ->
            {:error, ["Request must have an operation field"]}
            
          not Map.has_key?(request, :params) ->
            {:error, ["Request must have a params field"]}
            
          true ->
            :ok
        end
      end
      
      @impl true
      def shutdown(_reason, state) do
        # Log final metrics
        if @collect_metrics do
          Logger.info("Adapter shutdown - Total requests: #{state.request_count}, Errors: #{state.error_count}")
        end
        :ok
      end
      
      @impl true
      def handle_stream(_chunk, _stream_ref, state) do
        # Default implementation returns unsupported error
        {:error, Behaviour.error(:unsupported_operation, "Streaming not supported"), state}
      end
      
      @impl true
      def handle_event(_event, state) do
        # Default implementation ignores events
        {:ok, state}
      end
      
      @impl true
      def health_check(state) do
        status = case state.circuit_breaker.state do
          :closed -> :healthy
          :half_open -> :degraded
          :open -> :unhealthy
        end
        
        metadata = %{
          uptime_ms: System.monotonic_time(:millisecond) - state.start_time,
          request_count: state.request_count,
          error_count: state.error_count,
          error_rate: calculate_error_rate(state),
          circuit_breaker: state.circuit_breaker.state
        }
        
        {status, metadata}
      end
      
      # Helper functions available to all adapters
      
      @doc """
      Wraps request handling with common functionality like logging,
      metrics, and error handling.
      """
      def handle_request_with_middleware(request, context, state, handler_fn) do
        request_id = ensure_request_id(request)
        start_time = System.monotonic_time(:millisecond)
        
        # Log request if enabled
        if @log_requests do
          Logger.debug("Handling request", request_id: request_id, operation: request[:operation])
        end
        
        # Update state
        state = %{state | request_count: state.request_count + 1}
        
        # Check circuit breaker
        case check_circuit_breaker(state) do
          {:error, reason} ->
            error = Behaviour.error(:unavailable, reason)
            {:error, error, state}
            
          :ok ->
            # Execute handler
            result = handler_fn.(request, context, state)
            
            # Process result
            case result do
              {:ok, response, new_state} ->
                duration = System.monotonic_time(:millisecond) - start_time
                new_state = update_metrics(new_state, :success, duration)
                new_state = reset_circuit_breaker(new_state)
                
                if @log_requests do
                  Logger.debug("Request completed successfully", 
                    request_id: request_id, 
                    duration_ms: duration
                  )
                end
                
                # Broadcast success event
                broadcast_request_event(request_id, request, :success, duration)
                
                {:ok, response, new_state}
                
              {:error, error, new_state} ->
                duration = System.monotonic_time(:millisecond) - start_time
                new_state = %{new_state | error_count: new_state.error_count + 1}
                new_state = update_metrics(new_state, :error, duration)
                new_state = trip_circuit_breaker(new_state)
                
                if @log_requests do
                  Logger.error("Request failed", 
                    request_id: request_id,
                    error: inspect(error),
                    duration_ms: duration
                  )
                end
                
                # Broadcast error event
                broadcast_request_event(request_id, request, :error, duration)
                
                {:error, error, new_state}
                
              {:async, ref, new_state} ->
                # For async operations, metrics will be updated when complete
                {:async, ref, new_state}
            end
        end
      end
      
      @doc """
      Ensures the request has a unique ID.
      """
      def ensure_request_id(request) do
        Map.get(request, :id) || Behaviour.generate_request_id()
      end
      
      @doc """
      Updates adapter metrics.
      """
      def update_metrics(state, status, duration) do
        if @collect_metrics do
          update_in(state, [:metrics, status], fn count ->
            (count || 0) + 1
          end)
          |> update_in([:metrics, :total_duration], fn total ->
            (total || 0) + duration
          end)
        else
          state
        end
      end
      
      @doc """
      Calculates the current error rate.
      """
      def calculate_error_rate(%{request_count: 0}), do: 0.0
      def calculate_error_rate(%{request_count: total, error_count: errors}) do
        errors / total * 100
      end
      
      @doc """
      Checks if the circuit breaker allows requests.
      """
      def check_circuit_breaker(%{circuit_breaker: %{state: :closed}}), do: :ok
      def check_circuit_breaker(%{circuit_breaker: %{state: :half_open}}), do: :ok
      def check_circuit_breaker(%{circuit_breaker: %{state: :open, last_failure: last}}) do
        # Check if enough time has passed to try again
        if System.monotonic_time(:millisecond) - last > 60_000 do
          :ok
        else
          {:error, "Circuit breaker is open"}
        end
      end
      
      @doc """
      Resets the circuit breaker after a successful request.
      """
      def reset_circuit_breaker(state) do
        put_in(state, [:circuit_breaker], %{
          failure_count: 0,
          last_failure: nil,
          state: :closed
        })
      end
      
      @doc """
      Updates circuit breaker state after a failure.
      """
      def trip_circuit_breaker(state) do
        breaker = state.circuit_breaker
        failure_count = breaker.failure_count + 1
        
        new_breaker = if failure_count >= 5 do
          %{breaker | 
            failure_count: failure_count,
            last_failure: System.monotonic_time(:millisecond),
            state: :open
          }
        else
          %{breaker | failure_count: failure_count}
        end
        
        %{state | circuit_breaker: new_breaker}
      end
      
      @doc """
      Broadcasts request lifecycle events.
      """
      def broadcast_request_event(request_id, request, status, duration) do
        event_payload = %{
          request_id: request_id,
          interface: __MODULE__ |> Module.split() |> List.last() |> String.downcase() |> String.to_atom(),
          operation: request[:operation],
          status: status,
          duration_ms: duration,
          timestamp: DateTime.utc_now()
        }
        
        EventBroadcaster.broadcast_async(%{
          topic: "interface.request.#{status}",
          payload: event_payload,
          priority: :low,
          metadata: %{component: "interface_adapter"}
        })
      end
      
      @doc """
      Validates request parameters against a schema.
      """
      def validate_params(params, schema) when is_map(params) and is_map(schema) do
        errors = Enum.reduce(schema, [], fn {field, rules}, acc ->
          case validate_field(params[field], rules) do
            :ok -> acc
            {:error, reason} -> [{field, reason} | acc]
          end
        end)
        
        case errors do
          [] -> :ok
          errors -> {:error, Enum.reverse(errors)}
        end
      end
      
      defp validate_field(nil, %{required: true}), do: {:error, "is required"}
      defp validate_field(nil, _), do: :ok
      defp validate_field(value, %{type: type}) when is_atom(type) do
        if valid_type?(value, type) do
          :ok
        else
          {:error, "must be of type #{type}"}
        end
      end
      defp validate_field(_, _), do: :ok
      
      defp valid_type?(value, :string) when is_binary(value), do: true
      defp valid_type?(value, :integer) when is_integer(value), do: true
      defp valid_type?(value, :float) when is_float(value), do: true
      defp valid_type?(value, :boolean) when is_boolean(value), do: true
      defp valid_type?(value, :atom) when is_atom(value), do: true
      defp valid_type?(value, :map) when is_map(value), do: true
      defp valid_type?(value, :list) when is_list(value), do: true
      defp valid_type?(_, _), do: false
      
      @doc """
      Enriches context with adapter-specific metadata.
      """
      def enrich_context(context, adapter_metadata) do
        Map.merge(context, %{
          adapter: __MODULE__,
          adapter_metadata: adapter_metadata,
          timestamp: DateTime.utc_now()
        })
      end
      
      @doc """
      Helper for rate limiting.
      """
      def check_rate_limit(key, limit, window_ms) do
        # This is a simple in-memory rate limiter
        # In production, use Redis or similar
        case Process.get({:rate_limit, key}) do
          nil ->
            Process.put({:rate_limit, key}, {1, System.monotonic_time(:millisecond)})
            :ok
            
          {count, start_time} ->
            now = System.monotonic_time(:millisecond)
            if now - start_time > window_ms do
              Process.put({:rate_limit, key}, {1, now})
              :ok
            else
              if count >= limit do
                {:error, :rate_limit_exceeded}
              else
                Process.put({:rate_limit, key}, {count + 1, start_time})
                :ok
              end
            end
        end
      end
      
      # Allow adapters to override these defaults
      defoverridable [
        init: 1,
        validate_request: 1,
        shutdown: 2,
        handle_stream: 3,
        handle_event: 2,
        health_check: 1
      ]
    end
  end
end