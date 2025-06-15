defmodule RubberDuck.CodingAssistant.ProcessingStateMachine do
  @moduledoc """
  State machine for managing dual-mode processing in coding assistance engines.
  
  This module implements a sophisticated state machine that manages the transition
  between different processing modes based on load, request characteristics, and
  engine health. It ensures optimal resource utilization while maintaining
  performance guarantees.
  
  ## Processing Modes
  
  - `:idle` - Engine is not processing any requests
  - `:real_time` - Processing individual requests with <100ms constraint
  - `:batch` - Processing multiple requests efficiently
  - `:overloaded` - Engine is overloaded, prioritizing essential requests only
  - `:degraded` - Engine is unhealthy, limited processing capability
  - `:recovery` - Engine is recovering from failure
  
  ## State Transitions
  
  The state machine considers:
  - Current load and queue depth
  - Request urgency and type
  - Engine health status
  - Processing time trends
  - System resource availability
  
  ## Usage
  
      # Initialize state machine
      {:ok, state} = ProcessingStateMachine.init(%{engine: MyEngine})
      
      # Process state transition
      {:ok, new_state, actions} = ProcessingStateMachine.handle_request(state, request)
      
      # Update with processing results
      state = ProcessingStateMachine.update_metrics(state, processing_result)
  """

  @type processing_mode :: :idle | :real_time | :batch | :overloaded | :degraded | :recovery
  @type request_type :: :real_time | :batch | :background
  @type request_priority :: :urgent | :normal | :low
  
  @type request_info :: %{
    type: request_type(),
    priority: request_priority(),
    estimated_complexity: float(),
    deadline: DateTime.t() | nil,
    data_size: integer()
  }
  
  @type processing_metrics :: %{
    average_response_time: float(),
    success_rate: float(),
    queue_depth: integer(),
    cpu_usage: float(),
    memory_usage: float(),
    error_rate: float()
  }
  
  @type state_machine :: %{
    current_mode: processing_mode(),
    previous_mode: processing_mode(),
    mode_start_time: DateTime.t(),
    transition_count: integer(),
    request_queue: [request_info()],
    processing_metrics: processing_metrics(),
    health_status: :healthy | :degraded | :unhealthy,
    overload_threshold: float(),
    recovery_threshold: float(),
    mode_history: [{processing_mode(), DateTime.t()}]
  }
  
  @type transition_result :: {:ok, state_machine(), [action()]}
  @type action :: {:switch_mode, processing_mode()} | 
                  {:shed_load, integer()} | 
                  {:increase_concurrency, integer()} | 
                  {:decrease_concurrency, integer()} |
                  {:alert, atom(), String.t()}

  # Configuration constants
  @max_queue_depth 100
  @overload_threshold 0.8
  @recovery_threshold 0.5
  @mode_switch_cooldown 5_000  # 5 seconds
  @max_mode_history 50

  @doc """
  Initialize the processing state machine.
  """
  def init(config \\ %{}) do
    state = %{
      current_mode: :idle,
      previous_mode: :idle,
      mode_start_time: DateTime.utc_now(),
      transition_count: 0,
      request_queue: [],
      processing_metrics: init_metrics(),
      health_status: :healthy,
      overload_threshold: Map.get(config, :overload_threshold, @overload_threshold),
      recovery_threshold: Map.get(config, :recovery_threshold, @recovery_threshold),
      mode_history: [{:idle, DateTime.utc_now()}]
    }
    
    {:ok, state}
  end

  @doc """
  Handle an incoming request and determine processing strategy.
  
  Returns updated state and list of actions to take.
  """
  def handle_request(state, request_info) do
    # Add request to queue
    updated_state = add_to_queue(state, request_info)
    
    # Determine optimal processing mode
    target_mode = determine_target_mode(updated_state, request_info)
    
    # Check if mode transition is needed
    case should_transition_to(updated_state, target_mode) do
      {:yes, reason} ->
        transition_to_mode(updated_state, target_mode, reason)
        
      {:no, reason} ->
        {:ok, updated_state, [{:maintain_mode, updated_state.current_mode, reason}]}
    end
  end

  @doc """
  Update the state machine with processing results and metrics.
  """
  def update_metrics(state, processing_result) do
    updated_metrics = update_processing_metrics(state.processing_metrics, processing_result)
    updated_state = %{state | processing_metrics: updated_metrics}
    
    # Check if current mode is still appropriate
    case evaluate_mode_effectiveness(updated_state) do
      {:effective, _} ->
        updated_state
        
      {:ineffective, reason} ->
        # Suggest mode change in next request handling
        %{updated_state | 
          processing_metrics: Map.put(updated_metrics, :mode_effectiveness, reason)
        }
    end
  end

  @doc """
  Update health status and trigger recovery if needed.
  """
  def update_health(state, health_status) do
    old_health = state.health_status
    updated_state = %{state | health_status: health_status}
    
    # Check if health-based mode transition is needed
    case {old_health, health_status} do
      {:healthy, :degraded} ->
        transition_to_mode(updated_state, :degraded, :health_degradation)
        
      {:healthy, :unhealthy} ->
        transition_to_mode(updated_state, :recovery, :health_failure)
        
      {:degraded, :unhealthy} ->
        transition_to_mode(updated_state, :recovery, :health_failure)
        
      {:unhealthy, :degraded} ->
        transition_to_mode(updated_state, :degraded, :health_improvement)
        
      {:degraded, :healthy} ->
        transition_to_mode(updated_state, :idle, :health_recovery)
        
      {:unhealthy, :healthy} ->
        transition_to_mode(updated_state, :idle, :health_recovery)
        
      _ ->
        {:ok, updated_state, []}
    end
  end

  @doc """
  Get current state summary for monitoring.
  """
  def get_state_summary(state) do
    %{
      current_mode: state.current_mode,
      mode_duration: DateTime.diff(DateTime.utc_now(), state.mode_start_time, :second),
      queue_depth: length(state.request_queue),
      health_status: state.health_status,
      processing_metrics: state.processing_metrics,
      transition_count: state.transition_count,
      effectiveness: calculate_mode_effectiveness(state)
    }
  end

  @doc """
  Force a mode transition (for testing or administrative purposes).
  """
  def force_mode_transition(state, target_mode, reason \\ :manual) do
    transition_to_mode(state, target_mode, reason)
  end

  # Private implementation

  defp init_metrics do
    %{
      average_response_time: 0.0,
      success_rate: 1.0,
      queue_depth: 0,
      cpu_usage: 0.0,
      memory_usage: 0.0,
      error_rate: 0.0,
      throughput: 0.0,
      mode_effectiveness: :unknown
    }
  end

  defp add_to_queue(state, request_info) do
    new_queue = [request_info | state.request_queue]
    
    # Limit queue size to prevent memory issues
    limited_queue = if length(new_queue) > @max_queue_depth do
      # Drop oldest low-priority requests first
      new_queue
      |> Enum.sort_by(&{&1.priority, &1.deadline || DateTime.utc_now()})
      |> Enum.take(@max_queue_depth)
    else
      new_queue
    end
    
    %{state | 
      request_queue: limited_queue,
      processing_metrics: %{state.processing_metrics | queue_depth: length(limited_queue)}
    }
  end

  defp determine_target_mode(state, request_info) do
    cond do
      # Health-based decisions first
      state.health_status == :unhealthy ->
        :recovery
        
      state.health_status == :degraded ->
        :degraded
        
      # Load-based decisions
      is_overloaded?(state) ->
        :overloaded
        
      # Request type and priority
      request_info.type == :real_time and request_info.priority == :urgent ->
        :real_time
        
      # Batch mode for multiple requests
      length(state.request_queue) > 5 and 
      has_batchable_requests?(state.request_queue) ->
        :batch
        
      # Default to real-time for single requests
      request_info.type == :real_time ->
        :real_time
        
      # Background processing
      true ->
        :batch
    end
  end

  defp should_transition_to(state, target_mode) do
    current_mode = state.current_mode
    
    cond do
      # Already in target mode
      current_mode == target_mode ->
        {:no, :already_in_mode}
        
      # Cooldown period not met
      not cooldown_expired?(state) ->
        {:no, :cooldown_active}
        
      # Health-based transitions are always allowed
      target_mode in [:recovery, :degraded] ->
        {:yes, :health_override}
        
      # Urgent transitions
      target_mode == :overloaded ->
        {:yes, :overload_protection}
        
      # Normal transitions
      mode_transition_beneficial?(state, current_mode, target_mode) ->
        {:yes, :performance_optimization}
        
      true ->
        {:no, :no_benefit}
    end
  end

  defp transition_to_mode(state, target_mode, reason) do
    now = DateTime.utc_now()
    
    # Update mode history
    new_history = [{target_mode, now} | state.mode_history]
    |> Enum.take(@max_mode_history)
    
    new_state = %{state |
      previous_mode: state.current_mode,
      current_mode: target_mode,
      mode_start_time: now,
      transition_count: state.transition_count + 1,
      mode_history: new_history
    }
    
    # Generate actions based on target mode
    actions = generate_mode_actions(state.current_mode, target_mode, reason)
    
    {:ok, new_state, actions}
  end

  defp generate_mode_actions(from_mode, to_mode, reason) do
    base_action = {:switch_mode, to_mode}
    
    additional_actions = case to_mode do
      :overloaded ->
        [{:shed_load, 20}, {:alert, :overload, "Engine entering overload mode: #{reason}"}]
        
      :recovery ->
        [{:decrease_concurrency, 50}, {:alert, :recovery, "Engine entering recovery mode: #{reason}"}]
        
      :degraded ->
        [{:decrease_concurrency, 25}, {:alert, :degraded, "Engine performance degraded: #{reason}"}]
        
      :batch ->
        [{:increase_concurrency, 10}]
        
      :real_time ->
        [{:decrease_concurrency, 5}]
        
      :idle ->
        []
    end
    
    [base_action | additional_actions]
  end

  defp is_overloaded?(state) do
    metrics = state.processing_metrics
    
    metrics.cpu_usage > state.overload_threshold or
    metrics.memory_usage > state.overload_threshold or
    metrics.error_rate > 0.1 or
    metrics.queue_depth > (@max_queue_depth * 0.8) or
    metrics.average_response_time > 200_000  # 200ms
  end

  defp has_batchable_requests?(queue) do
    batch_requests = Enum.count(queue, &(&1.type == :batch or &1.priority == :low))
    batch_requests >= 3
  end

  defp cooldown_expired?(state) do
    time_since_transition = DateTime.diff(DateTime.utc_now(), state.mode_start_time, :millisecond)
    time_since_transition >= @mode_switch_cooldown
  end

  defp mode_transition_beneficial?(state, current_mode, target_mode) do
    # Simple heuristic based on current metrics
    metrics = state.processing_metrics
    
    case {current_mode, target_mode} do
      {:idle, :real_time} ->
        true  # Always beneficial to start processing
        
      {:real_time, :batch} ->
        metrics.queue_depth > 3 and metrics.average_response_time > 50_000
        
      {:batch, :real_time} ->
        metrics.queue_depth <= 2 or has_urgent_requests?(state.request_queue)
        
      {:overloaded, _} ->
        metrics.cpu_usage < state.recovery_threshold and 
        metrics.error_rate < 0.05
        
      {_, :idle} ->
        metrics.queue_depth == 0
        
      _ ->
        false
    end
  end

  defp has_urgent_requests?(queue) do
    Enum.any?(queue, &(&1.priority == :urgent))
  end

  defp evaluate_mode_effectiveness(state) do
    effectiveness = calculate_mode_effectiveness(state)
    
    if effectiveness > 0.7 do
      {:effective, effectiveness}
    else
      {:ineffective, :low_effectiveness}
    end
  end

  defp calculate_mode_effectiveness(state) do
    metrics = state.processing_metrics
    
    # Combine various effectiveness indicators
    response_time_score = case metrics.average_response_time do
      time when time < 50_000 -> 1.0
      time when time < 100_000 -> 0.8
      time when time < 200_000 -> 0.6
      _ -> 0.3
    end
    
    success_rate_score = metrics.success_rate
    
    queue_score = case metrics.queue_depth do
      depth when depth < 5 -> 1.0
      depth when depth < 10 -> 0.8
      depth when depth < 20 -> 0.6
      _ -> 0.3
    end
    
    error_rate_score = max(0.0, 1.0 - (metrics.error_rate * 5))
    
    # Weighted average
    (response_time_score * 0.3) +
    (success_rate_score * 0.3) +
    (queue_score * 0.2) +
    (error_rate_score * 0.2)
  end

  defp update_processing_metrics(metrics, processing_result) do
    # Update metrics based on processing result
    # This would be called after each request is processed
    
    new_response_time = Map.get(processing_result, :processing_time, 0)
    success = Map.get(processing_result, :success, true)
    
    # Update average response time (exponential moving average)
    alpha = 0.1
    new_avg_time = (alpha * new_response_time) + ((1 - alpha) * metrics.average_response_time)
    
    # Update success rate (exponential moving average)
    new_success_rate = if success do
      (alpha * 1.0) + ((1 - alpha) * metrics.success_rate)
    else
      (alpha * 0.0) + ((1 - alpha) * metrics.success_rate)
    end
    
    # Update error rate
    new_error_rate = if success do
      (alpha * 0.0) + ((1 - alpha) * metrics.error_rate)
    else
      (alpha * 1.0) + ((1 - alpha) * metrics.error_rate)
    end
    
    %{metrics |
      average_response_time: new_avg_time,
      success_rate: new_success_rate,
      error_rate: new_error_rate,
      queue_depth: max(0, metrics.queue_depth - 1)  # Assume one request processed
    }
  end
end