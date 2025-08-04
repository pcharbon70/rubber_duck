defmodule RubberDuck.Jido.Actions.Base.CoordinationAction do
  @moduledoc """
  Base action for multi-agent coordination and workflow orchestration.
  
  This base module provides common patterns for actions that coordinate
  multiple agents, manage workflows, handle distributed operations,
  and ensure consistent state across the system.
  
  ## Usage
  
      defmodule MyApp.Actions.WorkflowCoordinationAction do
        use RubberDuck.Jido.Actions.Base.CoordinationAction,
          name: "workflow_coordination",
          description: "Coordinates multi-step workflow execution",
          schema: [
            workflow_steps: [type: {:list, :map}, required: true],
            execution_mode: [type: :atom, default: :sequential, values: [:sequential, :parallel, :mixed]]
          ]
        
        @impl true
        def coordinate_execution(params, context) do
          case params.execution_mode do
            :sequential -> execute_sequential_workflow(params.workflow_steps, context)
            :parallel -> execute_parallel_workflow(params.workflow_steps, context)
            :mixed -> execute_mixed_workflow(params.workflow_steps, context)
          end
        end
      end
  
  ## Hooks Available
  
  - `before_coordination/2` - Called before starting coordination
  - `coordinate_execution/2` - Main coordination logic (must be implemented)
  - `after_coordination/3` - Called after successful coordination
  - `handle_coordination_error/3` - Called when coordination fails
  - `on_step_completed/3` - Called when individual steps complete
  - `on_agent_failure/4` - Called when coordinated agents fail
  """
  
  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.fetch!(opts, :description)
    schema = Keyword.get(opts, :schema, [])
    
    # Add common coordination parameters to schema
    enhanced_schema = schema ++ [
      coordination_timeout: [
        type: :pos_integer,
        default: 120_000,
        doc: "Maximum time for coordination to complete in milliseconds"
      ],
      max_concurrent_operations: [
        type: :pos_integer,
        default: 10,
        doc: "Maximum number of concurrent operations"
      ],
      failure_strategy: [
        type: :atom,
        default: :fail_fast,
        values: [:fail_fast, :continue_on_error, :retry_failed],
        doc: "How to handle failures in coordinated operations"
      ],
      retry_failed_steps: [
        type: :boolean,
        default: true,
        doc: "Whether to retry failed coordination steps"
      ],
      max_step_retries: [
        type: :non_neg_integer,
        default: 2,
        doc: "Maximum retries per coordination step"
      ],
      enable_rollback: [
        type: :boolean,
        default: false,
        doc: "Whether to enable rollback on coordination failure"
      ],
      coordination_id: [
        type: :string,
        default: nil,
        doc: "Unique identifier for this coordination session"
      ]
    ]
    
    quote do
      use Jido.Action,
        name: unquote(name),
        description: unquote(description),
        schema: unquote(enhanced_schema)
      
      require Logger
      
      @behaviour RubberDuck.Jido.Actions.Base.CoordinationAction
      
      # Generate coordination ID if not provided
      defp ensure_coordination_id(params) do
        coordination_id = params.coordination_id || "coord_#{System.unique_integer([:positive])}"
        Map.put(params, :coordination_id, coordination_id)
      end
      
      @impl true
      def run(params, context) do
        params = ensure_coordination_id(params)
        Logger.info("Starting coordination: #{unquote(name)} [#{params.coordination_id}]")
        start_time = System.monotonic_time(:millisecond)
        
        with {:ok, prepared_params} <- validate_coordination_params(params),
             {:ok, prepared_context} <- before_coordination(prepared_params, context),
             {:ok, result} <- execute_coordination_with_timeout(prepared_params, prepared_context),
             {:ok, final_result} <- after_coordination(result, prepared_params, prepared_context) do
          
          end_time = System.monotonic_time(:millisecond)
          coordination_time = end_time - start_time
          
          Logger.info("Coordination completed successfully: #{unquote(name)} [#{params.coordination_id}] in #{coordination_time}ms")
          
          emit_coordination_event(:coordination_completed, params.coordination_id, %{
            action: unquote(name),
            coordination_time: coordination_time,
            success: true
          })
          
          format_success_response(final_result, prepared_params, coordination_time)
        else
          {:error, reason} = error ->
            end_time = System.monotonic_time(:millisecond)
            coordination_time = end_time - start_time
            
            Logger.error("Coordination failed: #{unquote(name)} [#{params.coordination_id}] after #{coordination_time}ms, reason: #{inspect(reason)}")
            
            emit_coordination_event(:coordination_failed, params.coordination_id, %{
              action: unquote(name),
              coordination_time: coordination_time,
              error: reason,
              success: false
            })
            
            case handle_coordination_error(reason, params, context) do
              {:ok, recovery_result} -> 
                format_success_response(recovery_result, params, coordination_time)
              {:error, final_reason} -> 
                maybe_rollback_and_format_error(final_reason, params, coordination_time)
              :continue -> 
                maybe_rollback_and_format_error(reason, params, coordination_time)
            end
        end
      end
      
      # Default implementations - can be overridden
      
      def before_coordination(params, context), do: {:ok, context}
      
      def after_coordination(result, _params, _context), do: {:ok, result}
      
      def handle_coordination_error(reason, _params, _context), do: {:error, reason}
      
      def on_step_completed(step_id, result, _params) do
        Logger.debug("Coordination step completed: #{step_id}")
        :ok
      end
      
      def on_agent_failure(agent_id, reason, step_id, _params) do
        Logger.warning("Agent failure in coordination: #{agent_id} in step #{step_id}, reason: #{inspect(reason)}")
        :ok
      end
      
      def rollback_coordination(_params, _context) do
        Logger.info("Rollback not implemented for this coordination action")
        {:ok, :no_rollback}
      end
      
      defoverridable before_coordination: 2, after_coordination: 3, handle_coordination_error: 3,
                     on_step_completed: 3, on_agent_failure: 4, rollback_coordination: 2
      
      # Private helper functions
      
      defp validate_coordination_params(params) do
        cond do
          params.coordination_timeout < 5000 ->
            {:error, :invalid_coordination_timeout}
          params.max_concurrent_operations < 1 ->
            {:error, :invalid_max_concurrent_operations}
          true ->
            {:ok, params}
        end
      end
      
      defp execute_coordination_with_timeout(params, context) do
        task = Task.async(fn -> 
          coordinate_execution(params, context)
        end)
        
        case Task.yield(task, params.coordination_timeout) || Task.shutdown(task) do
          {:ok, result} -> result
          nil -> {:error, :coordination_timeout}
        end
      end
      
      defp maybe_rollback_and_format_error(reason, params, coordination_time) do
        if params.enable_rollback do
          Logger.info("Attempting rollback for coordination: #{params.coordination_id}")
          case rollback_coordination(params, %{}) do
            {:ok, _} -> 
              Logger.info("Rollback completed successfully")
            {:error, rollback_reason} -> 
              Logger.error("Rollback failed: #{inspect(rollback_reason)}")
          end
        end
        
        format_error_response(reason, params, coordination_time)
      end
      
      defp emit_coordination_event(event_name, coordination_id, metadata) do
        :telemetry.execute(
          [:rubber_duck, :actions, :coordination, event_name],
          %{count: 1},
          Map.put(metadata, :coordination_id, coordination_id)
        )
      end
      
      defp format_success_response(result, params, coordination_time) do
        response = %{
          success: true,
          data: result,
          metadata: %{
            timestamp: DateTime.utc_now(),
            action: unquote(name),
            coordination_id: params.coordination_id,
            coordination_time: coordination_time,
            failure_strategy: params.failure_strategy,
            rollback_enabled: params.enable_rollback
          }
        }
        {:ok, response}
      end
      
      defp format_error_response(reason, params, coordination_time) do
        error_response = %{
          success: false,
          error: reason,
          metadata: %{
            timestamp: DateTime.utc_now(),
            action: unquote(name),
            coordination_id: params.coordination_id,
            coordination_time: coordination_time,
            failure_strategy: params.failure_strategy,
            rollback_enabled: params.enable_rollback
          }
        }
        {:error, error_response}
      end
      
      # Utility functions for common coordination patterns
      
      defp execute_with_concurrency_limit(operations, max_concurrent) do
        operations
        |> Enum.chunk_every(max_concurrent)
        |> Enum.reduce({:ok, []}, fn batch, {:ok, acc} ->
          case execute_batch_parallel(batch) do
            {:ok, results} -> {:ok, acc ++ results}
            error -> error
          end
        end)
      end
      
      defp execute_batch_parallel(operations) do
        operations
        |> Enum.map(&Task.async/1)
        |> Enum.map(&Task.await/1)
        |> collect_results()
      end
      
      defp collect_results(results) do
        case Enum.find(results, fn result -> match?({:error, _}, result) end) do
          nil -> {:ok, Enum.map(results, fn {:ok, result} -> result end)}
          error -> error
        end
      end
    end
  end
  
  @doc """
  Callback for handling the main coordination logic.
  
  This callback must be implemented by modules using this base action.
  It should contain the core business logic for coordinating operations.
  
  ## Parameters
  - `params` - Validated parameters including coordination configuration
  - `context` - Context including agent state and other relevant data
  
  ## Returns
  - `{:ok, result}` - Coordination succeeded with result data
  - `{:error, reason}` - Coordination failed with error reason
  """
  @callback coordinate_execution(params :: map(), context :: map()) :: 
    {:ok, any()} | {:error, any()}
  
  @doc """
  Optional callback called before starting coordination.
  
  Can be used for setup, resource allocation, or parameter preparation.
  """
  @callback before_coordination(params :: map(), context :: map()) :: 
    {:ok, map()} | {:error, any()}
  
  @doc """
  Optional callback called after successful coordination.
  
  Can be used for cleanup, result aggregation, or side effects.
  """
  @callback after_coordination(result :: any(), params :: map(), context :: map()) :: 
    {:ok, any()} | {:error, any()}
  
  @doc """
  Optional callback called when coordination fails.
  
  Can be used for error recovery, cleanup, or custom error handling.
  
  ## Returns
  - `{:ok, result}` - Error recovered with result
  - `{:error, reason}` - Error handled with new reason
  - `:continue` - Continue with original error
  """
  @callback handle_coordination_error(reason :: any(), params :: map(), context :: map()) :: 
    {:ok, any()} | {:error, any()} | :continue
  
  @doc """
  Optional callback called when individual coordination steps complete.
  """
  @callback on_step_completed(step_id :: String.t(), result :: any(), params :: map()) :: :ok
  
  @doc """
  Optional callback called when coordinated agents fail.
  """
  @callback on_agent_failure(agent_id :: String.t(), reason :: any(), step_id :: String.t(), params :: map()) :: :ok
  
  @doc """
  Optional callback for rolling back coordination changes.
  
  Called when coordination fails and rollback is enabled.
  """
  @callback rollback_coordination(params :: map(), context :: map()) :: 
    {:ok, any()} | {:error, any()}
  
  # Default implementations
  @optional_callbacks before_coordination: 2, after_coordination: 3, handle_coordination_error: 3,
                      on_step_completed: 3, on_agent_failure: 4, rollback_coordination: 2
end