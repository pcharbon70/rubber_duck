defmodule RubberDuck.Agents.PlanStateManager do
  @moduledoc """
  Advanced state management for plans with concurrency control and conflict resolution.
  
  This module provides:
  - State transition validation and enforcement
  - Distributed locking mechanisms
  - Conflict resolution strategies
  - State history tracking
  - Rollback capabilities
  """
  
  require Logger
  
  # State definitions
  @states %{
    draft: %{
      name: :draft,
      description: "Plan is being created or edited",
      allowed_transitions: [:active, :archived],
      terminal: false
    },
    active: %{
      name: :active,
      description: "Plan is actively being executed",
      allowed_transitions: [:paused, :completed, :failed],
      terminal: false
    },
    paused: %{
      name: :paused,
      description: "Plan execution is temporarily halted",
      allowed_transitions: [:active, :failed, :archived],
      terminal: false
    },
    completed: %{
      name: :completed,
      description: "Plan has been successfully completed",
      allowed_transitions: [:archived],
      terminal: true
    },
    failed: %{
      name: :failed,
      description: "Plan execution has failed",
      allowed_transitions: [:archived],
      terminal: true
    },
    archived: %{
      name: :archived,
      description: "Plan has been archived",
      allowed_transitions: [],
      terminal: true
    }
  }
  
  # Lock types
  @lock_types %{
    exclusive: %{
      name: :exclusive,
      description: "Exclusive write lock",
      max_holders: 1,
      timeout: :timer.minutes(5)
    },
    shared: %{
      name: :shared,
      description: "Shared read lock",
      max_holders: 10,
      timeout: :timer.minutes(15)
    },
    transition: %{
      name: :transition,
      description: "State transition lock",
      max_holders: 1,
      timeout: :timer.minutes(2)
    }
  }
  
  # Conflict resolution strategies will be populated at runtime
  @resolution_strategies %{
    last_write_wins: :last_write_wins,
    first_write_wins: :first_write_wins,
    merge: :merge_changes,
    manual: :require_manual_resolution
  }
  
  @doc """
  Validates if a state transition is allowed.
  """
  def validate_transition(from_state, to_state) when is_atom(from_state) and is_atom(to_state) do
    case Map.get(@states, from_state) do
      nil ->
        {:error, {:invalid_state, from_state}}
        
      state_config ->
        if to_state in state_config.allowed_transitions do
          {:ok, %{
            from: from_state,
            to: to_state,
            terminal: @states[to_state].terminal
          }}
        else
          {:error, {:invalid_transition, from_state, to_state}}
        end
    end
  end
  
  @doc """
  Performs a state transition with proper locking and validation.
  """
  def transition_state(plan_id, from_state, to_state, metadata \\ %{}) do
    with {:ok, transition_info} <- validate_transition(from_state, to_state),
         {:ok, lock} <- acquire_transition_lock(plan_id),
         {:ok, current_state} <- get_current_state(plan_id),
         :ok <- verify_state_match(current_state, from_state),
         {:ok, history_entry} <- record_state_change(plan_id, transition_info, metadata),
         :ok <- apply_state_change(plan_id, to_state, history_entry),
         :ok <- release_lock(plan_id, lock) do
      
      emit_transition_event(plan_id, transition_info, metadata)
      {:ok, %{
        plan_id: plan_id,
        transition: transition_info,
        history_id: history_entry.id,
        timestamp: DateTime.utc_now()
      }}
    else
      error ->
        Logger.error("State transition failed for plan #{plan_id}: #{inspect(error)}")
        error
    end
  end
  
  @doc """
  Acquires a lock for plan operations.
  """
  def acquire_lock(plan_id, lock_type \\ :exclusive, opts \\ []) do
    lock_config = Map.get(@lock_types, lock_type, @lock_types.exclusive)
    timeout = Keyword.get(opts, :timeout, lock_config.timeout)
    requester = Keyword.get(opts, :requester, self())
    
    lock_data = %{
      id: generate_lock_id(),
      plan_id: plan_id,
      type: lock_type,
      holder: requester,
      acquired_at: DateTime.utc_now(),
      expires_at: DateTime.add(DateTime.utc_now(), timeout, :millisecond),
      metadata: Keyword.get(opts, :metadata, %{})
    }
    
    case check_lock_availability(plan_id, lock_type) do
      :available ->
        store_lock(lock_data)
        {:ok, lock_data}
        
      # TODO: Implement unavailable case when distributed lock store is added
      # {:unavailable, existing_locks} ->
      #   if Keyword.get(opts, :wait, false) do
      #     wait_for_lock(plan_id, lock_type, timeout)
      #   else
      #     {:error, {:lock_unavailable, existing_locks}}
      #   end
    end
  end
  
  @doc """
  Releases a previously acquired lock.
  """
  def release_lock(plan_id, lock) do
    remove_lock(lock.id)
    emit_lock_released(plan_id, lock)
    :ok
  end
  
  @doc """
  Handles concurrent modifications with conflict resolution.
  """
  def handle_concurrent_update(plan_id, update1, update2, strategy \\ :last_write_wins) do
    resolver_name = Map.get(@resolution_strategies, strategy, :last_write_wins)
    
    result = case resolver_name do
      :last_write_wins -> last_write_wins(update1, update2)
      :first_write_wins -> first_write_wins(update1, update2)
      :merge_changes -> merge_changes(update1, update2)
      :require_manual_resolution -> require_manual_resolution(update1, update2)
      _ -> last_write_wins(update1, update2)
    end
    
    case result do
      {:ok, resolved_update} ->
        apply_resolved_update(plan_id, resolved_update)
        
      {:conflict, conflict_data} ->
        store_conflict(plan_id, conflict_data)
        {:error, {:conflict_stored, conflict_data.id}}
    end
  end
  
  @doc """
  Gets the complete state history for a plan.
  """
  def get_state_history(plan_id, opts \\ []) do
    _limit = Keyword.get(opts, :limit, 100)
    _since = Keyword.get(opts, :since)
    
    # In a real implementation, this would query a persistence layer
    {:ok, [
      %{
        id: "history_1",
        plan_id: plan_id,
        from_state: :draft,
        to_state: :active,
        timestamp: DateTime.utc_now(),
        actor: "user_123",
        metadata: %{}
      }
    ]}
  end
  
  @doc """
  Rolls back a plan to a previous state.
  """
  def rollback_state(plan_id, to_history_id, reason) do
    with {:ok, history_entry} <- get_history_entry(to_history_id),
         {:ok, current_state} <- get_current_state(plan_id),
         {:ok, rollback_path} <- calculate_rollback_path(current_state, history_entry.to_state),
         {:ok, lock} <- acquire_transition_lock(plan_id) do
      
      # Apply rollback transitions
      result = Enum.reduce_while(rollback_path, {:ok, current_state}, fn next_state, {:ok, _prev} ->
        case apply_state_change(plan_id, next_state, %{rollback: true, reason: reason}) do
          :ok -> {:cont, {:ok, next_state}}
          error -> {:halt, error}
        end
      end)
      
      release_lock(plan_id, lock)
      
      case result do
        {:ok, final_state} ->
          emit_rollback_completed(plan_id, current_state, final_state, reason)
          {:ok, %{
            plan_id: plan_id,
            rolled_back_to: final_state,
            from_state: current_state,
            reason: reason
          }}
          
        error -> error
      end
    end
  end
  
  @doc """
  Checks if a plan is in a terminal state.
  """
  def terminal_state?(state) when is_atom(state) do
    case Map.get(@states, state) do
      nil -> false
      state_config -> state_config.terminal
    end
  end
  
  @doc """
  Gets all valid states.
  """
  def valid_states do
    Map.keys(@states)
  end
  
  @doc """
  Gets state configuration.
  """
  def get_state_config(state) when is_atom(state) do
    Map.get(@states, state)
  end
  
  ## Private Functions
  
  defp acquire_transition_lock(plan_id) do
    acquire_lock(plan_id, :transition, wait: true, timeout: :timer.minutes(1))
  end
  
  defp get_current_state(_plan_id) do
    # In a real implementation, this would query the Plan Manager Agent
    {:ok, :draft}
  end
  
  defp verify_state_match(current_state, expected_state) do
    if current_state == expected_state do
      :ok
    else
      {:error, {:state_mismatch, current_state, expected_state}}
    end
  end
  
  defp record_state_change(plan_id, transition_info, metadata) do
    history_entry = %{
      id: generate_history_id(),
      plan_id: plan_id,
      from_state: transition_info.from,
      to_state: transition_info.to,
      timestamp: DateTime.utc_now(),
      actor: get_actor_id(),
      metadata: metadata
    }
    
    # Store in persistence layer
    {:ok, history_entry}
  end
  
  defp apply_state_change(plan_id, new_state, _history_entry) do
    # In a real implementation, this would update the Plan Manager Agent
    emit_state_changed(plan_id, new_state)
    :ok
  end
  
  defp check_lock_availability(_plan_id, _lock_type) do
    # In a real implementation, this would check a distributed lock store
    :available
  end
  
  defp store_lock(_lock_data) do
    # Store in distributed lock store
    :ok
  end
  
  defp remove_lock(_lock_id) do
    # Remove from distributed lock store
    :ok
  end
  
  # TODO: Implement when distributed lock store is added
  # defp wait_for_lock(_plan_id, _lock_type, _timeout) do
  #   # Implement lock waiting logic with timeout
  #   {:error, :lock_timeout}
  # end
  
  defp get_history_entry(history_id) do
    # Query history store
    {:ok, %{
      id: history_id,
      to_state: :active
    }}
  end
  
  defp calculate_rollback_path(_from_state, to_state) do
    # Calculate valid state path for rollback
    # This is simplified - real implementation would use graph algorithms
    {:ok, [to_state]}
  end
  
  defp apply_resolved_update(_plan_id, update) do
    # Apply the resolved update
    {:ok, update}
  end
  
  defp store_conflict(_plan_id, _conflict_data) do
    # Store conflict for manual resolution
    :ok
  end
  
  ## Conflict Resolution Strategies
  
  defp last_write_wins(update1, update2) do
    if DateTime.compare(update1.timestamp, update2.timestamp) == :gt do
      {:ok, update1}
    else
      {:ok, update2}
    end
  end
  
  defp first_write_wins(update1, update2) do
    if DateTime.compare(update1.timestamp, update2.timestamp) == :lt do
      {:ok, update1}
    else
      {:ok, update2}
    end
  end
  
  defp merge_changes(update1, update2) do
    # Attempt to merge non-conflicting changes
    merged = Map.merge(update1.changes, update2.changes)
    {:ok, %{changes: merged, timestamp: DateTime.utc_now()}}
  end
  
  defp require_manual_resolution(update1, update2) do
    {:conflict, %{
      id: generate_conflict_id(),
      update1: update1,
      update2: update2,
      detected_at: DateTime.utc_now()
    }}
  end
  
  ## Helper Functions
  
  defp generate_lock_id do
    "lock_#{:erlang.unique_integer([:positive, :monotonic])}"
  end
  
  defp generate_history_id do
    "history_#{:erlang.unique_integer([:positive, :monotonic])}"
  end
  
  defp generate_conflict_id do
    "conflict_#{:erlang.unique_integer([:positive, :monotonic])}"
  end
  
  defp get_actor_id do
    # Get current actor/user ID from process dictionary or context
    Process.get(:current_user_id, "system")
  end
  
  ## Event Emission
  
  defp emit_transition_event(plan_id, transition_info, metadata) do
    :telemetry.execute(
      [:plan, :state, :transitioned],
      %{count: 1},
      %{
        plan_id: plan_id,
        from: transition_info.from,
        to: transition_info.to,
        metadata: metadata
      }
    )
  end
  
  defp emit_state_changed(plan_id, new_state) do
    :telemetry.execute(
      [:plan, :state, :changed],
      %{count: 1},
      %{plan_id: plan_id, state: new_state}
    )
  end
  
  defp emit_lock_released(plan_id, lock) do
    :telemetry.execute(
      [:plan, :lock, :released],
      %{duration: calculate_lock_duration(lock)},
      %{plan_id: plan_id, lock_type: lock.type}
    )
  end
  
  defp emit_rollback_completed(plan_id, from_state, to_state, reason) do
    :telemetry.execute(
      [:plan, :state, :rolled_back],
      %{count: 1},
      %{
        plan_id: plan_id,
        from: from_state,
        to: to_state,
        reason: reason
      }
    )
  end
  
  defp calculate_lock_duration(lock) do
    DateTime.diff(DateTime.utc_now(), lock.acquired_at, :millisecond)
  end
end