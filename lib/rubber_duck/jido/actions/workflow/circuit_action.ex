defmodule RubberDuck.Jido.Actions.Workflow.CircuitAction do
  @moduledoc """
  Circuit breaker action for fault tolerance and resilience.
  
  This action implements the circuit breaker pattern to prevent cascading failures
  and provide graceful degradation when calling unreliable actions. The circuit
  has three states: closed (normal), open (failing), and half-open (testing).
  
  ## Example
  
      params = %{
        protected_action: DatabaseQueryAction,
        action_params: %{query: "SELECT * FROM users"},
        failure_threshold: 5,        # Open circuit after 5 failures
        recovery_timeout: 60_000,     # Try half-open after 60 seconds
        fallback_action: CachedDataAction  # Optional fallback when open
      }
      
      {:ok, result} = CircuitAction.run(params, context)
  """
  
  use Jido.Action,
    name: "circuit",
    description: "Circuit breaker for fault tolerance",
    schema: [
      protected_action: [
        type: :atom,
        required: true,
        doc: "The action to protect with circuit breaker"
      ],
      action_params: [
        type: :map,
        default: %{},
        doc: "Parameters to pass to the protected action"
      ],
      failure_threshold: [
        type: :pos_integer,
        default: 5,
        doc: "Number of failures before opening circuit"
      ],
      success_threshold: [
        type: :pos_integer,
        default: 2,
        doc: "Number of successes in half-open before closing circuit"
      ],
      recovery_timeout: [
        type: :pos_integer,
        default: 60_000,
        doc: "Time in milliseconds before attempting recovery"
      ],
      call_timeout: [
        type: :pos_integer,
        default: 5_000,
        doc: "Timeout for individual calls in milliseconds"
      ],
      fallback_action: [
        type: :atom,
        default: nil,
        doc: "Optional fallback action when circuit is open"
      ],
      fallback_params: [
        type: :map,
        default: %{},
        doc: "Parameters for fallback action"
      ],
      circuit_id: [
        type: :string,
        default: nil,
        doc: "Unique identifier for this circuit instance"
      ],
      store_metrics: [
        type: :boolean,
        default: true,
        doc: "Whether to store circuit metrics"
      ]
    ]
  
  require Logger
  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  
  # Circuit states stored in ETS
  @circuit_table :circuit_breaker_states
  
  @impl true
  def run(params, context) do
    circuit_id = params.circuit_id || "circuit_#{params.protected_action}_#{System.unique_integer([:positive])}"
    
    # Ensure ETS table exists
    ensure_circuit_table()
    
    # Get current circuit state
    circuit_state = get_circuit_state(circuit_id, params)
    
    Logger.debug("Circuit #{circuit_id} state: #{circuit_state.state}")
    
    case circuit_state.state do
      :closed ->
        execute_closed_circuit(params, context, circuit_id, circuit_state)
        
      :open ->
        execute_open_circuit(params, context, circuit_id, circuit_state)
        
      :half_open ->
        execute_half_open_circuit(params, context, circuit_id, circuit_state)
    end
  end
  
  # Private functions
  
  defp ensure_circuit_table do
    case :ets.whereis(@circuit_table) do
      :undefined ->
        :ets.new(@circuit_table, [:set, :public, :named_table, {:read_concurrency, true}])
      _ ->
        :ok
    end
  end
  
  defp get_circuit_state(circuit_id, params) do
    case :ets.lookup(@circuit_table, circuit_id) do
      [{^circuit_id, state}] ->
        # Check if circuit should transition from open to half-open
        if state.state == :open && should_attempt_recovery?(state, params) do
          %{state | state: :half_open, half_open_attempts: 0}
        else
          state
        end
        
      [] ->
        # Initialize new circuit state
        %{
          state: :closed,
          failure_count: 0,
          success_count: 0,
          last_failure_time: nil,
          opened_at: nil,
          half_open_attempts: 0,
          metrics: %{
            total_calls: 0,
            successful_calls: 0,
            failed_calls: 0,
            fallback_calls: 0
          }
        }
    end
  end
  
  defp execute_closed_circuit(params, context, circuit_id, circuit_state) do
    # Circuit is closed, execute normally
    start_time = System.monotonic_time(:millisecond)
    
    case execute_protected_action(params, context, params.call_timeout) do
      {:ok, result, updated_context} ->
        duration = System.monotonic_time(:millisecond) - start_time
        
        # Reset failure count on success
        new_state = %{circuit_state |
          failure_count: 0,
          success_count: circuit_state.success_count + 1
        }
        
        new_state = update_metrics(new_state, :success, duration)
        save_circuit_state(circuit_id, new_state)
        
        emit_circuit_signal("circuit.call.success", circuit_id, %{
          state: :closed,
          duration: duration
        }, context.agent)
        
        {:ok, %{
          circuit_id: circuit_id,
          circuit_state: :closed,
          result: result,
          duration: duration
        }, updated_context}
        
      {:error, reason} ->
        duration = System.monotonic_time(:millisecond) - start_time
        
        # Increment failure count
        new_failure_count = circuit_state.failure_count + 1
        
        new_state = if new_failure_count >= params.failure_threshold do
          # Open the circuit
          Logger.warning("Opening circuit #{circuit_id} after #{new_failure_count} failures")
          
          emit_circuit_signal("circuit.opened", circuit_id, %{
            failure_count: new_failure_count,
            threshold: params.failure_threshold
          }, context.agent)
          
          %{circuit_state |
            state: :open,
            failure_count: new_failure_count,
            last_failure_time: System.monotonic_time(:millisecond),
            opened_at: System.monotonic_time(:millisecond)
          }
        else
          %{circuit_state |
            failure_count: new_failure_count,
            last_failure_time: System.monotonic_time(:millisecond)
          }
        end
        
        new_state = update_metrics(new_state, :failure, duration)
        save_circuit_state(circuit_id, new_state)
        
        emit_circuit_signal("circuit.call.failed", circuit_id, %{
          state: new_state.state,
          failure_count: new_failure_count,
          error: reason
        }, context.agent)
        
        # Try fallback if circuit just opened
        if new_state.state == :open && params.fallback_action do
          execute_fallback(params, context, circuit_id, reason)
        else
          {:error, %{
            circuit_id: circuit_id,
            circuit_state: new_state.state,
            error: reason,
            failure_count: new_failure_count
          }}
        end
    end
  end
  
  defp execute_open_circuit(params, context, circuit_id, circuit_state) do
    # Circuit is open, use fallback or fail fast
    
    emit_circuit_signal("circuit.rejected", circuit_id, %{
      state: :open,
      opened_duration: System.monotonic_time(:millisecond) - circuit_state.opened_at
    }, context.agent)
    
    if params.fallback_action do
      execute_fallback(params, context, circuit_id, :circuit_open)
    else
      {:error, %{
        circuit_id: circuit_id,
        circuit_state: :open,
        error: :circuit_open,
        message: "Circuit breaker is open"
      }}
    end
  end
  
  defp execute_half_open_circuit(params, context, circuit_id, circuit_state) do
    # Circuit is half-open, testing recovery
    Logger.debug("Circuit #{circuit_id} attempting recovery (half-open)")
    
    start_time = System.monotonic_time(:millisecond)
    
    case execute_protected_action(params, context, params.call_timeout) do
      {:ok, result, updated_context} ->
        duration = System.monotonic_time(:millisecond) - start_time
        
        new_success_count = circuit_state.half_open_attempts + 1
        
        new_state = if new_success_count >= params.success_threshold do
          # Close the circuit
          Logger.info("Closing circuit #{circuit_id} after #{new_success_count} successful attempts")
          
          emit_circuit_signal("circuit.closed", circuit_id, %{
            recovery_attempts: new_success_count
          }, context.agent)
          
          %{circuit_state |
            state: :closed,
            failure_count: 0,
            success_count: 0,
            half_open_attempts: 0,
            opened_at: nil
          }
        else
          %{circuit_state |
            half_open_attempts: new_success_count
          }
        end
        
        new_state = update_metrics(new_state, :success, duration)
        save_circuit_state(circuit_id, new_state)
        
        {:ok, %{
          circuit_id: circuit_id,
          circuit_state: new_state.state,
          result: result,
          duration: duration
        }, updated_context}
        
      {:error, reason} ->
        # Failed in half-open, reopen circuit
        Logger.warning("Circuit #{circuit_id} recovery failed, reopening")
        
        new_state = %{circuit_state |
          state: :open,
          failure_count: circuit_state.failure_count + 1,
          last_failure_time: System.monotonic_time(:millisecond),
          opened_at: System.monotonic_time(:millisecond),
          half_open_attempts: 0
        }
        
        new_state = update_metrics(new_state, :failure, 0)
        save_circuit_state(circuit_id, new_state)
        
        emit_circuit_signal("circuit.recovery_failed", circuit_id, %{
          error: reason
        }, context.agent)
        
        if params.fallback_action do
          execute_fallback(params, context, circuit_id, reason)
        else
          {:error, %{
            circuit_id: circuit_id,
            circuit_state: :open,
            error: reason,
            message: "Recovery attempt failed"
          }}
        end
    end
  end
  
  defp execute_protected_action(params, context, timeout) do
    task = Task.async(fn ->
      try do
        params.protected_action.run(params.action_params, context)
      rescue
        error ->
          {:error, {:action_crashed, error}}
      end
    end)
    
    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
      {:exit, reason} -> {:error, {:exit, reason}}
    end
  end
  
  defp execute_fallback(params, context, circuit_id, original_error) do
    Logger.debug("Executing fallback action for circuit #{circuit_id}")
    
    case params.fallback_action.run(params.fallback_params, context) do
      {:ok, result, updated_context} ->
        # Update fallback metrics
        state = get_circuit_state(circuit_id, params)
        new_state = update_metrics(state, :fallback, 0)
        save_circuit_state(circuit_id, new_state)
        
        emit_circuit_signal("circuit.fallback.success", circuit_id, %{
          original_error: original_error
        }, context.agent)
        
        {:ok, %{
          circuit_id: circuit_id,
          circuit_state: state.state,
          result: result,
          fallback_used: true,
          original_error: original_error
        }, updated_context}
        
      {:error, fallback_error} ->
        emit_circuit_signal("circuit.fallback.failed", circuit_id, %{
          original_error: original_error,
          fallback_error: fallback_error
        }, context.agent)
        
        {:error, %{
          circuit_id: circuit_id,
          circuit_state: :open,
          error: original_error,
          fallback_error: fallback_error
        }}
    end
  end
  
  defp should_attempt_recovery?(state, params) do
    state.opened_at != nil && 
      (System.monotonic_time(:millisecond) - state.opened_at) >= params.recovery_timeout
  end
  
  defp update_metrics(state, type, duration) do
    if Map.get(state, :metrics) do
      metrics = state.metrics
      
      new_metrics = case type do
        :success ->
          %{metrics |
            total_calls: metrics.total_calls + 1,
            successful_calls: metrics.successful_calls + 1
          }
        :failure ->
          %{metrics |
            total_calls: metrics.total_calls + 1,
            failed_calls: metrics.failed_calls + 1
          }
        :fallback ->
          %{metrics |
            fallback_calls: metrics.fallback_calls + 1
          }
      end
      
      %{state | metrics: new_metrics}
    else
      state
    end
  end
  
  defp save_circuit_state(circuit_id, state) do
    :ets.insert(@circuit_table, {circuit_id, state})
  end
  
  defp emit_circuit_signal(type, circuit_id, data, agent) do
    EmitSignalAction.run(%{
      signal_type: type,
      data: Map.put(data, :circuit_id, circuit_id),
      source: "circuit:#{circuit_id}"
    }, %{agent: agent})
  end
end