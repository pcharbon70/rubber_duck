defmodule RubberDuck.Jido.Actions.Base.UtilityAction do
  @moduledoc """
  Base action for common utility operations with standardized patterns.
  
  This base module provides common patterns for actions that perform
  utility operations like data transformation, validation, caching,
  file operations, and other helper functions.
  
  ## Usage
  
      defmodule MyApp.Actions.DataTransformAction do
        use RubberDuck.Jido.Actions.Base.UtilityAction,
          name: "data_transform",
          description: "Transforms data from one format to another",
          schema: [
            input_data: [type: :any, required: true],
            transform_type: [type: :atom, required: true, values: [:json_to_map, :csv_to_list, :xml_to_map]],
            validation_rules: [type: :map, default: %{}]
          ]
        
        @impl true
        def execute_utility(params, context) do
          case params.transform_type do
            :json_to_map -> transform_json_to_map(params.input_data)
            :csv_to_list -> transform_csv_to_list(params.input_data)
            :xml_to_map -> transform_xml_to_map(params.input_data)
          end
        end
      end
  
  ## Hooks Available
  
  - `before_utility/2` - Called before executing utility operation
  - `execute_utility/2` - Main utility logic (must be implemented)
  - `after_utility/3` - Called after successful utility execution
  - `handle_utility_error/3` - Called when utility operation fails
  - `validate_input/2` - Called to validate input parameters
  - `validate_output/3` - Called to validate output results
  """
  
  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.fetch!(opts, :description)
    schema = Keyword.get(opts, :schema, [])
    
    # Add common utility parameters to schema
    enhanced_schema = schema ++ [
      cache_result: [
        type: :boolean,
        default: false,
        doc: "Whether to cache the operation result"
      ],
      cache_ttl: [
        type: :pos_integer,
        default: 300_000,
        doc: "Cache time-to-live in milliseconds"
      ],
      validate_input: [
        type: :boolean,
        default: true,
        doc: "Whether to validate input parameters"
      ],
      validate_output: [
        type: :boolean,
        default: true,
        doc: "Whether to validate output results"
      ],
      operation_timeout: [
        type: :pos_integer,
        default: 30_000,
        doc: "Maximum time for utility operation in milliseconds"
      ],
      enable_metrics: [
        type: :boolean,
        default: true,
        doc: "Whether to collect operation metrics"
      ],
      idempotent: [
        type: :boolean,
        default: true,
        doc: "Whether this operation is idempotent"
      ],
      operation_id: [
        type: :string,
        default: nil,
        doc: "Unique identifier for this operation instance"
      ]
    ]
    
    quote do
      use Jido.Action,
        name: unquote(name),
        description: unquote(description),
        schema: unquote(enhanced_schema)
      
      require Logger
      
      @behaviour RubberDuck.Jido.Actions.Base.UtilityAction
      
      # Generate operation ID if not provided
      defp ensure_operation_id(params) do
        operation_id = params.operation_id || "op_#{System.unique_integer([:positive])}"
        Map.put(params, :operation_id, operation_id)
      end
      
      @impl true
      def run(params, context) do
        params = ensure_operation_id(params)
        Logger.debug("Starting utility operation: #{unquote(name)} [#{params.operation_id}]")
        start_time = System.monotonic_time(:millisecond)
        
        with {:ok, prepared_params} <- validate_utility_params(params),
             {:ok, cache_result} <- check_cache(prepared_params, context),
             {:ok, prepared_context} <- before_utility(prepared_params, context),
             {:ok, result} <- maybe_execute_or_return_cached(cache_result, prepared_params, prepared_context),
             {:ok, validated_result} <- validate_result_if_enabled(result, prepared_params, prepared_context),
             {:ok, final_result} <- after_utility(validated_result, prepared_params, prepared_context) do
          
          end_time = System.monotonic_time(:millisecond)
          operation_time = end_time - start_time
          
          # Cache result if enabled and not from cache
          if prepared_params.cache_result and cache_result == :cache_miss do
            cache_operation_result(final_result, prepared_params, operation_time)
          end
          
          Logger.debug("Utility operation completed: #{unquote(name)} [#{params.operation_id}] in #{operation_time}ms")
          
          if prepared_params.enable_metrics do
            emit_utility_event(:utility_completed, params.operation_id, %{
              action: unquote(name),
              operation_time: operation_time,
              from_cache: cache_result != :cache_miss,
              success: true
            })
          end
          
          format_success_response(final_result, prepared_params, operation_time, cache_result != :cache_miss)
        else
          {:error, reason} = error ->
            end_time = System.monotonic_time(:millisecond)
            operation_time = end_time - start_time
            
            Logger.error("Utility operation failed: #{unquote(name)} [#{params.operation_id}] after #{operation_time}ms, reason: #{inspect(reason)}")
            
            if params.enable_metrics do
              emit_utility_event(:utility_failed, params.operation_id, %{
                action: unquote(name),
                operation_time: operation_time,
                error: reason,
                success: false
              })
            end
            
            case handle_utility_error(reason, params, context) do
              {:ok, recovery_result} -> 
                format_success_response(recovery_result, params, operation_time, false)
              {:error, final_reason} -> 
                format_error_response(final_reason, params, operation_time)
              :continue -> 
                format_error_response(reason, params, operation_time)
            end
        end
      end
      
      # Default implementations - can be overridden
      
      def before_utility(params, context), do: {:ok, context}
      
      def after_utility(result, _params, _context), do: {:ok, result}
      
      def handle_utility_error(reason, _params, _context), do: {:error, reason}
      
      def validate_input(params, _context) do
        # Basic validation - can be overridden for specific validation logic
        if is_map(params) do
          {:ok, params}
        else
          {:error, :invalid_input_format}
        end
      end
      
      def validate_output(result, _params, _context) do
        # Basic validation - can be overridden for specific validation logic
        {:ok, result}
      end
      
      defoverridable before_utility: 2, after_utility: 3, handle_utility_error: 3,
                     validate_input: 2, validate_output: 3
      
      # Private helper functions
      
      defp validate_utility_params(params) do
        cond do
          params.operation_timeout < 1000 ->
            {:error, :invalid_operation_timeout}
          params.cache_ttl < 1000 ->
            {:error, :invalid_cache_ttl}
          true ->
            validated_params = if params.validate_input do
              case validate_input(params, %{}) do
                {:ok, _} -> params
                {:error, reason} -> throw({:validation_error, reason})
              end
            else
              params
            end
            {:ok, validated_params}
        end
      rescue
        {:validation_error, reason} -> {:error, {:input_validation_failed, reason}}
      end
      
      defp check_cache(params, context) do
        if params.cache_result do
          cache_key = generate_cache_key(params)
          case get_from_cache(cache_key, context) do
            {:hit, cached_result} -> {:ok, {:cache_hit, cached_result}}
            :miss -> {:ok, :cache_miss}
          end
        else
          {:ok, :cache_miss}
        end
      end
      
      defp maybe_execute_or_return_cached({:cache_hit, cached_result}, _params, _context) do
        {:ok, cached_result}
      end
      
      defp maybe_execute_or_return_cached(:cache_miss, params, context) do
        execute_utility_with_timeout(params, context)
      end
      
      defp execute_utility_with_timeout(params, context) do
        task = Task.async(fn -> 
          execute_utility(params, context)
        end)
        
        case Task.yield(task, params.operation_timeout) || Task.shutdown(task) do
          {:ok, result} -> result
          nil -> {:error, :operation_timeout}
        end
      end
      
      defp validate_result_if_enabled(result, params, context) do
        if params.validate_output do
          validate_output(result, params, context)
        else
          {:ok, result}
        end
      end
      
      defp generate_cache_key(params) do
        # Generate a cache key based on operation and parameters
        key_data = %{
          action: unquote(name),
          params: Map.drop(params, [:cache_result, :cache_ttl, :operation_id])
        }
        :crypto.hash(:md5, :erlang.term_to_binary(key_data)) |> Base.encode16()
      end
      
      defp get_from_cache(cache_key, context) do
        # Simple in-memory cache implementation
        # In production, this could use Redis, ETS, or other caching solutions
        cache = Map.get(context, :cache, %{})
        case Map.get(cache, cache_key) do
          nil -> :miss
          %{expires_at: expires_at, data: data} ->
            if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
              {:hit, data}
            else
              :miss
            end
        end
      end
      
      defp cache_operation_result(result, params, operation_time) do
        Logger.debug("Caching utility operation result for #{params.cache_ttl}ms")
        # In production, implement actual caching logic here
        :ok
      end
      
      defp emit_utility_event(event_name, operation_id, metadata) do
        :telemetry.execute(
          [:rubber_duck, :actions, :utility, event_name],
          %{count: 1},
          Map.put(metadata, :operation_id, operation_id)
        )
      end
      
      defp format_success_response(result, params, operation_time, from_cache) do
        response = %{
          success: true,
          data: result,
          metadata: %{
            timestamp: DateTime.utc_now(),
            action: unquote(name),
            operation_id: params.operation_id,
            operation_time: operation_time,
            from_cache: from_cache,
            idempotent: params.idempotent,
            cache_enabled: params.cache_result
          }
        }
        {:ok, response}
      end
      
      defp format_error_response(reason, params, operation_time) do
        error_response = %{
          success: false,
          error: reason,
          metadata: %{
            timestamp: DateTime.utc_now(),
            action: unquote(name),
            operation_id: params.operation_id,
            operation_time: operation_time,
            idempotent: params.idempotent,
            cache_enabled: params.cache_result
          }
        }
        {:error, error_response}
      end
    end
  end
  
  @doc """
  Callback for executing the main utility operation.
  
  This callback must be implemented by modules using this base action.
  It should contain the core logic for the utility operation.
  
  ## Parameters
  - `params` - Validated parameters including utility configuration
  - `context` - Context including agent state and other relevant data
  
  ## Returns
  - `{:ok, result}` - Operation succeeded with result data
  - `{:error, reason}` - Operation failed with error reason
  """
  @callback execute_utility(params :: map(), context :: map()) :: 
    {:ok, any()} | {:error, any()}
  
  @doc """
  Optional callback called before executing utility operation.
  
  Can be used for setup, resource allocation, or parameter preparation.
  """
  @callback before_utility(params :: map(), context :: map()) :: 
    {:ok, map()} | {:error, any()}
  
  @doc """
  Optional callback called after successful utility execution.
  
  Can be used for cleanup, result transformation, or side effects.
  """
  @callback after_utility(result :: any(), params :: map(), context :: map()) :: 
    {:ok, any()} | {:error, any()}
  
  @doc """
  Optional callback called when utility operation fails.
  
  Can be used for error recovery, fallback behavior, or custom error handling.
  
  ## Returns
  - `{:ok, result}` - Error recovered with result
  - `{:error, reason}` - Error handled with new reason
  - `:continue` - Continue with original error
  """
  @callback handle_utility_error(reason :: any(), params :: map(), context :: map()) :: 
    {:ok, any()} | {:error, any()} | :continue
  
  @doc """
  Optional callback for validating input parameters.
  
  Can be used for custom input validation beyond schema validation.
  """
  @callback validate_input(params :: map(), context :: map()) :: 
    {:ok, map()} | {:error, any()}
  
  @doc """
  Optional callback for validating output results.
  
  Can be used for custom output validation and transformation.
  """
  @callback validate_output(result :: any(), params :: map(), context :: map()) :: 
    {:ok, any()} | {:error, any()}
  
  # Default implementations
  @optional_callbacks before_utility: 2, after_utility: 3, handle_utility_error: 3,
                      validate_input: 2, validate_output: 3
end