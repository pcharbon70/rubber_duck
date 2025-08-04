defmodule RubberDuck.Jido.Actions.Workflow.SagaAction do
  @moduledoc """
  Saga action for distributed transactions with compensation and rollback.
  
  This action implements the Saga pattern for managing distributed transactions
  across multiple actions. Each step has an associated compensation action that
  is executed in reverse order if a failure occurs.
  
  ## Example
  
      params = %{
        steps: [
          %{
            action: CreateOrderAction,
            params: %{order_data: order},
            compensate: CancelOrderAction
          },
          %{
            action: ChargePaymentAction,
            params: %{amount: 100.00},
            compensate: RefundPaymentAction
          },
          %{
            action: ShipItemAction,
            params: %{item_id: "123"},
            compensate: CancelShipmentAction
          }
        ],
        transaction_data: %{order_id: "order_123"}
      }
      
      {:ok, result} = SagaAction.run(params, context)
  """
  
  use Jido.Action,
    name: "saga",
    description: "Manages distributed transactions with compensation",
    schema: [
      steps: [
        type: {:list, :map},
        required: true,
        doc: "List of saga steps with actions and compensation actions"
      ],
      transaction_data: [
        type: :any,
        default: %{},
        doc: "Initial transaction data passed to steps"
      ],
      isolation_level: [
        type: :atom,
        default: :read_committed,
        values: [:read_uncommitted, :read_committed, :repeatable_read, :serializable],
        doc: "Transaction isolation level"
      ],
      compensation_strategy: [
        type: :atom,
        default: :reverse_order,
        values: [:reverse_order, :parallel, :custom],
        doc: "How to execute compensation actions"
      ],
      save_checkpoints: [
        type: :boolean,
        default: true,
        doc: "Whether to save state after each step for recovery"
      ],
      saga_id: [
        type: :string,
        default: nil,
        doc: "Unique identifier for this saga execution"
      ]
    ]
  
  require Logger
  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  
  @impl true
  def run(params, context) do
    saga_id = params.saga_id || "saga_#{System.unique_integer([:positive])}"
    
    Logger.info("Starting saga transaction: #{saga_id}")
    
    # Initialize saga state
    saga_state = %{
      saga_id: saga_id,
      completed_steps: [],
      transaction_data: params.transaction_data,
      checkpoints: [],
      agent: context.agent
    }
    
    # Emit saga start signal
    emit_saga_signal("saga.started", saga_id, %{
      steps_count: length(params.steps),
      isolation_level: params.isolation_level
    }, context.agent)
    
    # Execute saga steps
    case execute_saga_steps(params.steps, saga_state, context, params) do
      {:ok, final_state} ->
        # Saga completed successfully
        emit_saga_signal("saga.completed", saga_id, %{
          steps_completed: length(final_state.completed_steps),
          final_data: final_state.transaction_data
        }, final_state.agent)
        
        {:ok, %{
          saga_id: saga_id,
          steps_completed: length(final_state.completed_steps),
          transaction_data: final_state.transaction_data,
          checkpoints: final_state.checkpoints
        }, %{agent: final_state.agent}}
        
      {:error, reason, failed_state} ->
        # Saga failed, initiate compensation
        Logger.warning("Saga #{saga_id} failed at step #{length(failed_state.completed_steps) + 1}, initiating compensation")
        
        emit_saga_signal("saga.compensating", saga_id, %{
          failed_at_step: length(failed_state.completed_steps) + 1,
          error: reason,
          steps_to_compensate: length(failed_state.completed_steps)
        }, failed_state.agent)
        
        # Execute compensation
        case execute_compensation(failed_state, params) do
          {:ok, compensated_state} ->
            emit_saga_signal("saga.compensated", saga_id, %{
              steps_compensated: length(failed_state.completed_steps),
              original_error: reason
            }, compensated_state.agent)
            
            {:error, %{
              saga_id: saga_id,
              compensated: true,
              original_error: reason,
              steps_compensated: length(failed_state.completed_steps)
            }}
            
          {:error, compensation_error} ->
            emit_saga_signal("saga.compensation_failed", saga_id, %{
              original_error: reason,
              compensation_error: compensation_error,
              partial_compensation: true
            }, failed_state.agent)
            
            {:error, %{
              saga_id: saga_id,
              compensated: false,
              original_error: reason,
              compensation_error: compensation_error
            }}
        end
    end
  end
  
  # Private functions
  
  defp execute_saga_steps([], state, _context, _params) do
    {:ok, state}
  end
  
  defp execute_saga_steps([step | rest], state, context, params) do
    step_index = length(state.completed_steps) + 1
    step_id = "#{state.saga_id}_step_#{step_index}"
    
    Logger.debug("Executing saga step #{step_index}: #{inspect(step.action)}")
    
    # Merge transaction data with step params
    step_params = Map.merge(
      Map.get(step, :params, %{}),
      %{transaction_data: state.transaction_data}
    )
    
    # Execute the step action
    start_time = System.monotonic_time(:millisecond)
    
    case execute_step_action(step.action, step_params, %{context | agent: state.agent}) do
      {:ok, result, %{agent: updated_agent}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        
        # Update transaction data with step results
        updated_transaction_data = merge_transaction_data(state.transaction_data, result)
        
        # Record completed step
        completed_step = %{
          index: step_index,
          action: step.action,
          compensate: Map.get(step, :compensate),
          result: result,
          duration: duration,
          params: step_params
        }
        
        # Update state
        new_state = %{state |
          completed_steps: [completed_step | state.completed_steps],
          transaction_data: updated_transaction_data,
          agent: updated_agent
        }
        
        # Save checkpoint if enabled
        new_state = if params.save_checkpoints do
          save_checkpoint(new_state, step_index)
        else
          new_state
        end
        
        # Emit step completion signal
        emit_step_signal("saga.step.completed", step_id, %{
          step_index: step_index,
          action: step.action,
          duration: duration
        }, updated_agent)
        
        # Continue with next step
        execute_saga_steps(rest, new_state, context, params)
        
      {:error, reason} ->
        # Step failed
        emit_step_signal("saga.step.failed", step_id, %{
          step_index: step_index,
          action: step.action,
          error: reason
        }, state.agent)
        
        {:error, reason, state}
    end
  end
  
  defp execute_step_action(action_module, params, context) do
    try do
      action_module.run(params, context)
    rescue
      error ->
        Logger.error("Saga step crashed: #{inspect(error)}")
        {:error, {:step_crashed, error}}
    end
  end
  
  defp execute_compensation(state, params) do
    case params.compensation_strategy do
      :reverse_order ->
        compensate_reverse_order(state.completed_steps, state, params)
      :parallel ->
        compensate_parallel(state.completed_steps, state, params)
      :custom ->
        # Allow custom compensation logic via callback
        compensate_custom(state.completed_steps, state, params)
    end
  end
  
  defp compensate_reverse_order([], state, _params) do
    {:ok, state}
  end
  
  defp compensate_reverse_order([step | rest], state, params) do
    if step.compensate do
      comp_id = "#{state.saga_id}_comp_#{step.index}"
      
      Logger.debug("Compensating step #{step.index} with #{inspect(step.compensate)}")
      
      # Build compensation params from original step results
      comp_params = Map.merge(
        step.params,
        %{
          original_result: step.result,
          transaction_data: state.transaction_data
        }
      )
      
      case execute_step_action(step.compensate, comp_params, %{agent: state.agent}) do
        {:ok, _result, %{agent: updated_agent}} ->
          emit_step_signal("saga.compensation.completed", comp_id, %{
            step_index: step.index,
            compensate_action: step.compensate
          }, updated_agent)
          
          compensate_reverse_order(rest, %{state | agent: updated_agent}, params)
          
        {:error, comp_error} ->
          emit_step_signal("saga.compensation.failed", comp_id, %{
            step_index: step.index,
            compensate_action: step.compensate,
            error: comp_error
          }, state.agent)
          
          {:error, {:compensation_failed, step.index, comp_error}}
      end
    else
      # No compensation for this step
      compensate_reverse_order(rest, state, params)
    end
  end
  
  defp compensate_parallel(steps, state, _params) do
    # Execute all compensations in parallel
    tasks = steps
      |> Enum.filter(fn step -> step.compensate != nil end)
      |> Enum.map(fn step ->
        Task.async(fn ->
          comp_params = Map.merge(
            step.params,
            %{
              original_result: step.result,
              transaction_data: state.transaction_data
            }
          )
          
          case execute_step_action(step.compensate, comp_params, %{agent: state.agent}) do
            {:ok, result, _} -> {:ok, step.index, result}
            {:error, reason} -> {:error, step.index, reason}
          end
        end)
      end)
    
    results = Task.await_many(tasks, 30_000)
    
    errors = Enum.filter(results, fn r -> match?({:error, _, _}, r) end)
    
    if Enum.empty?(errors) do
      {:ok, state}
    else
      {:error, {:parallel_compensation_errors, errors}}
    end
  end
  
  defp compensate_custom(_steps, _state, _params) do
    # Placeholder for custom compensation strategies
    {:error, :custom_compensation_not_implemented}
  end
  
  defp merge_transaction_data(current_data, step_result) when is_map(step_result) do
    Map.merge(current_data, step_result)
  end
  
  defp merge_transaction_data(current_data, _step_result) do
    current_data
  end
  
  defp save_checkpoint(state, step_index) do
    checkpoint = %{
      step: step_index,
      timestamp: DateTime.utc_now(),
      transaction_data: state.transaction_data,
      completed_steps: Enum.map(state.completed_steps, fn s -> s.index end)
    }
    
    %{state | checkpoints: [checkpoint | state.checkpoints]}
  end
  
  defp emit_saga_signal(type, saga_id, data, agent) do
    EmitSignalAction.run(%{
      signal_type: type,
      data: Map.put(data, :saga_id, saga_id),
      source: "saga:#{saga_id}"
    }, %{agent: agent})
  end
  
  defp emit_step_signal(type, step_id, data, agent) do
    EmitSignalAction.run(%{
      signal_type: type,
      data: Map.put(data, :step_id, step_id),
      source: "saga_step:#{step_id}"
    }, %{agent: agent})
  end
end