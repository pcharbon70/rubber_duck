defmodule RubberDuck.Commands.CommandTelemetry do
  @moduledoc """
  Specialized telemetry for command execution metrics and monitoring.
  
  Provides comprehensive telemetry tracking for command execution including:
  - Execution start, completion, and error events
  - Performance metrics and timing data
  - Success/failure rates and error classification
  - Resource usage and throughput monitoring
  - Integration with existing telemetry infrastructure
  """
  
  alias RubberDuck.LLMAbstraction.Telemetry
  
  @doc """
  Track command execution start.
  """
  def track_execution_start(execution_id, command_module, context) do
    measurements = %{
      start_time: System.monotonic_time(:millisecond),
      count: 1
    }
    
    metadata = %{
      execution_id: execution_id,
      command_module: command_module,
      user_id: Map.get(context, :user_id),
      session_id: Map.get(context, :session_id),
      priority: Map.get(context, :priority, :normal),
      timeout: Map.get(context, :timeout)
    }
    
    execute([:execution, :start], measurements, metadata)
    execution_id
  end
  
  @doc """
  Track successful command execution completion.
  """
  def track_execution_success(execution_id, command_module, execution_time, context) do
    measurements = %{
      duration: execution_time,
      count: 1
    }
    
    metadata = %{
      execution_id: execution_id,
      command_module: command_module,
      user_id: Map.get(context, :user_id),
      session_id: Map.get(context, :session_id),
      result: :success
    }
    
    execute([:execution, :success], measurements, metadata)
  end
  
  @doc """
  Track failed command execution.
  """
  def track_execution_error(execution_id, command_module, error, context) do
    measurements = %{
      count: 1,
      duration: System.monotonic_time(:millisecond) - Map.get(context, :start_time, 0)
    }
    
    metadata = %{
      execution_id: execution_id,
      command_module: command_module,
      user_id: Map.get(context, :user_id),
      session_id: Map.get(context, :session_id),
      result: :error,
      error_type: classify_command_error(error),
      error_message: extract_error_message(error)
    }
    
    execute([:execution, :error], measurements, metadata)
  end
  
  @doc """
  Track cancelled command execution.
  """
  def track_execution_cancelled(execution_id, command_module, context) do
    measurements = %{
      count: 1,
      duration: System.monotonic_time(:millisecond) - Map.get(context, :start_time, 0)
    }
    
    metadata = %{
      execution_id: execution_id,
      command_module: command_module,
      user_id: Map.get(context, :user_id),
      session_id: Map.get(context, :session_id),
      result: :cancelled
    }
    
    execute([:execution, :cancelled], measurements, metadata)
  end
  
  @doc """
  Track command validation failures.
  """
  def track_validation_error(execution_id, command_module, validation_errors, context) do
    measurements = %{
      count: 1,
      error_count: length(validation_errors)
    }
    
    metadata = %{
      execution_id: execution_id,
      command_module: command_module,
      user_id: Map.get(context, :user_id),
      session_id: Map.get(context, :session_id),
      result: :validation_error,
      validation_errors: validation_errors
    }
    
    execute([:execution, :validation_error], measurements, metadata)
  end
  
  @doc """
  Track command timeout events.
  """
  def track_execution_timeout(execution_id, command_module, timeout_ms, context) do
    measurements = %{
      count: 1,
      timeout_duration: timeout_ms
    }
    
    metadata = %{
      execution_id: execution_id,
      command_module: command_module,
      user_id: Map.get(context, :user_id),
      session_id: Map.get(context, :session_id),
      result: :timeout
    }
    
    execute([:execution, :timeout], measurements, metadata)
  end
  
  @doc """
  Track circuit breaker events for commands.
  """
  def track_circuit_breaker_event(command_module, event_type, metadata \\ %{}) do
    measurements = %{count: 1}
    
    metadata = Map.merge(metadata, %{
      command_module: command_module,
      event_type: event_type,
      timestamp: System.system_time(:second)
    })
    
    execute([:circuit_breaker, event_type], measurements, metadata)
  end
  
  @doc """
  Track command handler spawning and termination.
  """
  def track_handler_lifecycle(execution_id, command_module, event_type, metadata \\ %{}) do
    measurements = %{count: 1}
    
    metadata = Map.merge(metadata, %{
      execution_id: execution_id,
      command_module: command_module,
      event_type: event_type,
      timestamp: System.monotonic_time(:millisecond)
    })
    
    execute([:handler, event_type], measurements, metadata)
  end
  
  @doc """
  Track command migration between nodes.
  """
  def track_command_migration(execution_id, command_module, from_node, to_node, result) do
    measurements = %{count: 1}
    
    metadata = %{
      execution_id: execution_id,
      command_module: command_module,
      from_node: from_node,
      to_node: to_node,
      result: result,
      timestamp: System.monotonic_time(:millisecond)
    }
    
    execute([:migration, result], measurements, metadata)
  end
  
  @doc """
  Track command supervisor statistics.
  """
  def track_supervisor_stats(stats, metadata \\ %{}) do
    measurements = %{
      total_commands: stats.total_commands,
      active_commands: stats.active_commands,
      load_balance_score: Map.get(stats.load_distribution, :balance_score, 0.0),
      variance: Map.get(stats.load_distribution, :variance, 0.0)
    }
    
    metadata = Map.merge(metadata, %{
      cluster_nodes: length(stats.cluster_nodes),
      timestamp: System.system_time(:second)
    })
    
    execute([:supervisor, :stats], measurements, metadata)
  end
  
  @doc """
  Track execution manager statistics.
  """
  def track_manager_stats(execution_stats, active_executions) do
    measurements = %{
      total_executions: execution_stats.total_executions,
      successful_executions: execution_stats.successful_executions,
      failed_executions: execution_stats.failed_executions,
      cancelled_executions: execution_stats.cancelled_executions,
      active_executions: active_executions,
      average_execution_time: execution_stats.average_execution_time
    }
    
    metadata = %{
      timestamp: System.system_time(:second)
    }
    
    execute([:manager, :stats], measurements, metadata)
  end
  
  @doc """
  Track command resource usage.
  """
  def track_resource_usage(execution_id, command_module, resource_data, context) do
    measurements = %{
      memory_usage: Map.get(resource_data, :memory_usage, 0),
      cpu_usage: Map.get(resource_data, :cpu_usage, 0.0),
      disk_io: Map.get(resource_data, :disk_io, 0),
      network_io: Map.get(resource_data, :network_io, 0)
    }
    
    metadata = %{
      execution_id: execution_id,
      command_module: command_module,
      user_id: Map.get(context, :user_id),
      session_id: Map.get(context, :session_id),
      timestamp: System.monotonic_time(:millisecond)
    }
    
    execute([:resource, :usage], measurements, metadata)
  end
  
  @doc """
  Track command throughput metrics.
  """
  def track_throughput(command_module, time_window, execution_count, metadata \\ %{}) do
    measurements = %{
      execution_count: execution_count,
      time_window_ms: time_window,
      executions_per_second: execution_count / (time_window / 1000)
    }
    
    metadata = Map.merge(metadata, %{
      command_module: command_module,
      timestamp: System.system_time(:second)
    })
    
    execute([:throughput, :measured], measurements, metadata)
  end
  
  @doc """
  Track command queue metrics.
  """
  def track_queue_metrics(queue_size, wait_time, priority_distribution) do
    measurements = %{
      queue_size: queue_size,
      average_wait_time: wait_time,
      high_priority_count: Map.get(priority_distribution, :high, 0),
      normal_priority_count: Map.get(priority_distribution, :normal, 0),
      low_priority_count: Map.get(priority_distribution, :low, 0)
    }
    
    metadata = %{
      timestamp: System.system_time(:second)
    }
    
    execute([:queue, :metrics], measurements, metadata)
  end
  
  @doc """
  Track command performance benchmarks.
  """
  def track_performance_benchmark(command_module, benchmark_data) do
    measurements = %{
      min_execution_time: benchmark_data.min_time,
      max_execution_time: benchmark_data.max_time,
      avg_execution_time: benchmark_data.avg_time,
      p95_execution_time: benchmark_data.p95_time,
      p99_execution_time: benchmark_data.p99_time,
      sample_count: benchmark_data.sample_count
    }
    
    metadata = %{
      command_module: command_module,
      benchmark_period: benchmark_data.period,
      timestamp: System.system_time(:second)
    }
    
    execute([:performance, :benchmark], measurements, metadata)
  end
  
  # Private Functions
  
  defp execute(event_name, measurements, metadata) do
    full_event_name = [:rubber_duck, :commands] ++ event_name
    Telemetry.execute(full_event_name, measurements, metadata)
  rescue
    _ -> :ok  # Telemetry failures shouldn't crash command execution
  end
  
  defp classify_command_error({:validation_failed, _}), do: :validation_error
  defp classify_command_error({:execution_failed, _}), do: :execution_error
  defp classify_command_error({:process_died, _}), do: :process_error
  defp classify_command_error({:timeout, _}), do: :timeout_error
  defp classify_command_error({:circuit_breaker_open, _}), do: :circuit_breaker_error
  defp classify_command_error(:timeout), do: :timeout_error
  defp classify_command_error(:circuit_breaker_open), do: :circuit_breaker_error
  defp classify_command_error(_), do: :unknown_error
  
  defp extract_error_message({_type, message}) when is_binary(message), do: message
  defp extract_error_message({_type, reason}) when is_atom(reason), do: to_string(reason)
  defp extract_error_message({_type, %{message: message}}) when is_binary(message), do: message
  defp extract_error_message(error) when is_binary(error), do: error
  defp extract_error_message(error) when is_atom(error), do: to_string(error)
  defp extract_error_message(_), do: "unknown_error"
end