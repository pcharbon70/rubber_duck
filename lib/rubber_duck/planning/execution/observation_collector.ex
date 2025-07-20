defmodule RubberDuck.Planning.Execution.ObservationCollector do
  @moduledoc """
  Collects and analyzes observations from action executions in the ReAct framework.
  
  The ObservationCollector gathers results, side effects, and metrics from
  executed actions to inform future decisions and potential plan adjustments.
  """
  
  
  require Logger
  
  @type observation :: %{
    task_id: String.t(),
    result: term(),
    status: atom(),
    metrics: map(),
    side_effects: [map()],
    anomalies: [map()],
    insights: [String.t()],
    timestamp: DateTime.t()
  }
  
  @doc """
  Collects observations from a completed task execution.
  """
  @spec collect_observation(String.t(), term(), map()) :: observation()
  def collect_observation(task_id, result, execution_state) do
    Logger.debug("Collecting observations for task #{task_id}")
    
    # Extract basic result information
    {status, processed_result} = process_result(result)
    
    # Collect various metrics
    metrics = collect_metrics(task_id, result, execution_state)
    
    # Detect side effects
    side_effects = detect_side_effects(task_id, result, execution_state)
    
    # Identify anomalies
    anomalies = detect_anomalies(task_id, result, metrics, execution_state)
    
    # Generate insights
    insights = generate_insights(task_id, status, metrics, anomalies)
    
    %{
      task_id: task_id,
      result: processed_result,
      status: status,
      metrics: metrics,
      side_effects: side_effects,
      anomalies: anomalies,
      insights: insights,
      timestamp: DateTime.utc_now()
    }
  end
  
  defp process_result({:ok, data}), do: {:success, data}
  defp process_result({:error, reason}), do: {:failure, reason}
  defp process_result(%{status: status} = result), do: {status, result}
  defp process_result(result), do: {:unknown, result}
  
  defp collect_metrics(task_id, result, execution_state) do
    %{
      execution_time: calculate_execution_time(task_id, execution_state),
      memory_usage: collect_memory_metrics(),
      cpu_usage: collect_cpu_metrics(),
      io_operations: collect_io_metrics(task_id),
      result_size: calculate_result_size(result),
      custom_metrics: extract_custom_metrics(result)
    }
  end
  
  defp calculate_execution_time(task_id, execution_state) do
    case get_task_timing(execution_state, task_id) do
      %{start: start, end: end_time} ->
        DateTime.diff(end_time, start, :millisecond)
        
      _ ->
        nil
    end
  end
  
  defp get_task_timing(execution_state, task_id) do
    execution_state.history
    |> Map.get(:timings, %{})
    |> Map.get(task_id)
  end
  
  defp collect_memory_metrics do
    memory_info = :erlang.memory()
    
    %{
      total: memory_info[:total],
      processes: memory_info[:processes],
      binary: memory_info[:binary],
      ets: memory_info[:ets]
    }
  end
  
  defp collect_cpu_metrics do
    # Get scheduler utilization
    schedulers = :erlang.system_info(:schedulers_online)
    
    # Mock utilization data since :scheduler module not available
    avg_utilization = 0.5  # Default to 50% utilization
    
    %{
      scheduler_count: schedulers,
      average_utilization: Float.round(avg_utilization, 2),
      reductions: :erlang.statistics(:reductions) |> elem(1)
    }
  rescue
    _ ->
      # Fallback if scheduler statistics unavailable
      %{
        scheduler_count: :erlang.system_info(:schedulers_online),
        average_utilization: nil,
        reductions: :erlang.statistics(:reductions) |> elem(1)
      }
  end
  
  defp collect_io_metrics(_task_id) do
    # Collect telemetry events for the task
    # events = Telemetry.get_events_for_task(task_id)
    events = []  # Mock empty events for now
    
    %{
      database_queries: count_events(events, :database_query),
      api_calls: count_events(events, :api_call),
      file_operations: count_events(events, :file_operation),
      cache_hits: count_events(events, :cache_hit),
      cache_misses: count_events(events, :cache_miss)
    }
  end
  
  defp count_events(events, type) do
    Enum.count(events, fn event -> event.type == type end)
  end
  
  defp calculate_result_size(result) do
    # Estimate the size of the result in bytes
    result
    |> :erlang.term_to_binary()
    |> byte_size()
  rescue
    _ -> nil
  end
  
  defp extract_custom_metrics(%{metrics: metrics}), do: metrics
  defp extract_custom_metrics(_), do: %{}
  
  defp detect_side_effects(task_id, result, execution_state) do
    effects = []
    
    # Check for state changes
    effects = effects ++ detect_state_changes(task_id, execution_state)
    
    # Check for external system interactions
    effects = effects ++ detect_external_interactions(task_id, result)
    
    # Check for resource consumption
    effects = effects ++ detect_resource_effects(task_id, execution_state)
    
    effects
  end
  
  defp detect_state_changes(task_id, execution_state) do
    # Compare before/after states
    before_state = get_before_state(execution_state, task_id)
    after_state = get_current_state(execution_state)
    
    changes = compare_states(before_state, after_state)
    
    Enum.map(changes, fn {key, {old, new}} ->
      %{
        type: :state_change,
        key: key,
        old_value: old,
        new_value: new,
        task_id: task_id
      }
    end)
  end
  
  defp detect_external_interactions(task_id, result) do
    # Look for evidence of external system interactions
    interactions = []
    
    # Check for HTTP calls
    if contains_http_evidence?(result) do
      interactions ++ [%{type: :http_call, task_id: task_id}]
    else
      interactions
    end
  end
  
  defp detect_resource_effects(task_id, execution_state) do
    # Check for significant resource usage
    effects = []
    
    memory_delta = calculate_memory_delta(execution_state, task_id)
    if memory_delta > 10_000_000 do  # 10MB threshold
      effects ++ [%{
        type: :high_memory_usage,
        task_id: task_id,
        delta_bytes: memory_delta
      }]
    else
      effects
    end
  end
  
  defp detect_anomalies(task_id, result, metrics, execution_state) do
    anomalies = []
    
    # Check execution time anomaly
    anomalies = anomalies ++ check_execution_time_anomaly(task_id, metrics, execution_state)
    
    # Check result size anomaly
    anomalies = anomalies ++ check_result_size_anomaly(task_id, metrics)
    
    # Check error pattern anomaly
    anomalies = anomalies ++ check_error_pattern_anomaly(task_id, result, execution_state)
    
    # Check resource usage anomaly
    anomalies = anomalies ++ check_resource_anomaly(metrics)
    
    anomalies
  end
  
  defp check_execution_time_anomaly(task_id, %{execution_time: time}, execution_state) when is_integer(time) do
    avg_time = get_average_execution_time(execution_state, task_id)
    
    if avg_time && time > avg_time * 2 do
      [%{
        type: :slow_execution,
        task_id: task_id,
        execution_time: time,
        average_time: avg_time,
        severity: :warning
      }]
    else
      []
    end
  end
  defp check_execution_time_anomaly(_, _, _), do: []
  
  defp check_result_size_anomaly(_task_id, %{result_size: size}) when is_integer(size) do
    if size > 1_000_000 do  # 1MB threshold
      [%{
        type: :large_result,
        size_bytes: size,
        severity: :info
      }]
    else
      []
    end
  end
  defp check_result_size_anomaly(_, _), do: []
  
  defp check_error_pattern_anomaly(task_id, {:failure, _reason}, execution_state) do
    failure_count = get_consecutive_failures(execution_state, task_id)
    
    if failure_count >= 3 do
      [%{
        type: :repeated_failures,
        task_id: task_id,
        failure_count: failure_count,
        severity: :error
      }]
    else
      []
    end
  end
  defp check_error_pattern_anomaly(_, _, _), do: []
  
  defp check_resource_anomaly(%{cpu_usage: %{average_utilization: util}}) when is_float(util) do
    if util > 0.8 do  # 80% CPU threshold
      [%{
        type: :high_cpu_usage,
        utilization: util,
        severity: :warning
      }]
    else
      []
    end
  end
  defp check_resource_anomaly(_), do: []
  
  defp generate_insights(task_id, status, metrics, anomalies) do
    insights = []
    
    # Status-based insights
    insights = insights ++ generate_status_insights(status)
    
    # Performance insights
    insights = insights ++ generate_performance_insights(metrics)
    
    # Anomaly-based insights
    insights = insights ++ generate_anomaly_insights(anomalies)
    
    # Task-specific insights
    insights = insights ++ generate_task_insights(task_id, status, metrics)
    
    Enum.uniq(insights)
  end
  
  defp generate_status_insights(:success) do
    ["Task completed successfully"]
  end
  defp generate_status_insights(:failure) do
    ["Task failed - consider retry or alternative approach"]
  end
  defp generate_status_insights(_) do
    []
  end
  
  defp generate_performance_insights(%{execution_time: time}) when is_integer(time) and time > 10000 do
    ["Long execution time (#{time}ms) - consider optimization"]
  end
  defp generate_performance_insights(%{result_size: size}) when is_integer(size) and size > 500_000 do
    ["Large result size - consider pagination or streaming"]
  end
  defp generate_performance_insights(_) do
    []
  end
  
  defp generate_anomaly_insights(anomalies) do
    Enum.map(anomalies, fn
      %{type: :slow_execution} ->
        "Execution slower than average - investigate performance"
        
      %{type: :repeated_failures, failure_count: count} ->
        "Task failed #{count} times consecutively - review approach"
        
      %{type: :high_cpu_usage} ->
        "High CPU usage detected - monitor system resources"
        
      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end
  
  defp generate_task_insights(_task_id, :success, %{io_operations: io_ops}) do
    insights = []
    
    if io_ops[:database_queries] > 100 do
      insights ++ ["High number of database queries - consider batching"]
    else
      insights
    end
  end
  defp generate_task_insights(_, _, _), do: []
  
  # Helper functions
  
  defp get_before_state(execution_state, task_id) do
    execution_state.history
    |> Map.get(:snapshots, %{})
    |> Map.get({task_id, :before}, %{})
  end
  
  defp get_current_state(execution_state) do
    %{
      completed_count: MapSet.size(execution_state.completed_tasks),
      failed_count: MapSet.size(execution_state.failed_tasks),
      memory_used: :erlang.memory(:total)
    }
  end
  
  defp compare_states(before, after_state) do
    Map.keys(after_state)
    |> Enum.reduce(%{}, fn key, acc ->
      before_val = Map.get(before, key)
      after_val = Map.get(after_state, key)
      
      if before_val != after_val do
        Map.put(acc, key, {before_val, after_val})
      else
        acc
      end
    end)
  end
  
  defp contains_http_evidence?(result) do
    result_string = inspect(result)
    String.contains?(result_string, ["http", "request", "response", "status_code"])
  end
  
  defp calculate_memory_delta(execution_state, task_id) do
    before = get_memory_before(execution_state, task_id)
    after_memory = :erlang.memory(:total)
    
    if before do
      after_memory - before
    else
      0
    end
  end
  
  defp get_memory_before(execution_state, task_id) do
    execution_state.history
    |> Map.get(:memory_snapshots, %{})
    |> Map.get(task_id)
  end
  
  defp get_average_execution_time(execution_state, task_id) do
    execution_state.history
    |> Map.get(:execution_times, %{})
    |> Map.get(task_id, [])
    |> case do
      [] -> nil
      times -> Enum.sum(times) / length(times)
    end
  end
  
  defp get_consecutive_failures(execution_state, task_id) do
    execution_state.history
    |> Map.get(:attempts, %{})
    |> Map.get(task_id, [])
    |> Enum.take_while(fn attempt -> attempt.status == :failure end)
    |> length()
  end
end