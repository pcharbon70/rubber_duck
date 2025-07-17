defmodule RubberDuck.Tool.Monitoring.Dashboard do
  @moduledoc """
  Real-time monitoring dashboard for tool execution.
  
  Provides a web-based dashboard for monitoring tool execution metrics,
  health status, and performance analytics.
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Tool.Monitoring
  
  @refresh_interval 5_000 # 5 seconds
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Gets the current dashboard data.
  """
  @spec get_dashboard_data() :: map()
  def get_dashboard_data do
    GenServer.call(__MODULE__, :get_dashboard_data)
  end
  
  @doc """
  Gets real-time metrics stream.
  """
  @spec get_metrics_stream(keyword()) :: map()
  def get_metrics_stream(opts \\ []) do
    window = Keyword.get(opts, :window, 300) # 5 minutes default
    GenServer.call(__MODULE__, {:get_metrics_stream, window})
  end
  
  @doc """
  Gets tool performance analytics.
  """
  @spec get_tool_analytics(atom(), keyword()) :: map()
  def get_tool_analytics(tool_name, opts \\ []) do
    GenServer.call(__MODULE__, {:get_tool_analytics, tool_name, opts})
  end
  
  @doc """
  Gets system overview.
  """
  @spec get_system_overview() :: map()
  def get_system_overview do
    GenServer.call(__MODULE__, :get_system_overview)
  end
  
  @doc """
  Subscribes to real-time dashboard updates.
  """
  @spec subscribe() :: :ok
  def subscribe do
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "monitoring_dashboard")
  end
  
  @doc """
  Unsubscribes from dashboard updates.
  """
  @spec unsubscribe() :: :ok
  def unsubscribe do
    Phoenix.PubSub.unsubscribe(RubberDuck.PubSub, "monitoring_dashboard")
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Subscribe to monitoring events
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "tool_monitoring")
    
    # Schedule periodic updates
    schedule_refresh()
    
    state = %{
      metrics_buffer: [],
      last_update: System.system_time(:second),
      cached_data: %{}
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:get_dashboard_data, _from, state) do
    dashboard_data = compile_dashboard_data(state)
    {:reply, dashboard_data, state}
  end
  
  @impl true
  def handle_call({:get_metrics_stream, window}, _from, state) do
    metrics_stream = compile_metrics_stream(state, window)
    {:reply, metrics_stream, state}
  end
  
  @impl true
  def handle_call({:get_tool_analytics, tool_name, opts}, _from, state) do
    analytics = compile_tool_analytics(tool_name, opts, state)
    {:reply, analytics, state}
  end
  
  @impl true
  def handle_call(:get_system_overview, _from, state) do
    overview = compile_system_overview(state)
    {:reply, overview, state}
  end
  
  @impl true
  def handle_info(:refresh, state) do
    # Update cached data
    new_state = refresh_dashboard_data(state)
    
    # Broadcast updates
    broadcast_dashboard_update(new_state)
    
    # Schedule next refresh
    schedule_refresh()
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info({:tool_execution_event, event}, state) do
    # Buffer real-time events
    new_state = buffer_event(event, state)
    
    # Broadcast real-time update
    broadcast_real_time_event(event)
    
    {:noreply, new_state}
  end
  
  # Private functions
  
  defp compile_dashboard_data(_state) do
    current_time = System.system_time(:microsecond)
    
    # Get various time windows
    last_minute = current_time - 60_000_000
    last_hour = current_time - 3_600_000_000
    last_day = current_time - 86_400_000_000
    
    %{
      overview: %{
        health: Monitoring.get_health_status(),
        active_executions: get_active_executions_count(),
        total_tools: get_total_tools_count(),
        uptime: get_uptime()
      },
      metrics: %{
        last_minute: Monitoring.get_execution_stats(last_minute, current_time),
        last_hour: Monitoring.get_execution_stats(last_hour, current_time),
        last_day: Monitoring.get_execution_stats(last_day, current_time)
      },
      top_tools: get_top_tools(10),
      recent_errors: get_recent_errors(20),
      performance_trends: calculate_performance_trends(),
      resource_usage: get_resource_usage(),
      timestamp: DateTime.utc_now()
    }
  end
  
  defp compile_metrics_stream(state, window_seconds) do
    current_time = System.system_time(:microsecond)
    start_time = current_time - (window_seconds * 1_000_000)
    
    # Get buffered events and historical data
    recent_events = filter_buffered_events(state.metrics_buffer, start_time)
    historical_data = get_historical_metrics(start_time, current_time)
    
    %{
      time_series: build_time_series(recent_events ++ historical_data),
      aggregates: calculate_stream_aggregates(recent_events ++ historical_data),
      window: %{
        start: DateTime.from_unix!(start_time, :microsecond),
        end: DateTime.from_unix!(current_time, :microsecond),
        duration_seconds: window_seconds
      }
    }
  end
  
  defp compile_tool_analytics(tool_name, opts, _state) do
    time_range = Keyword.get(opts, :time_range, :last_day)
    
    {start_time, end_time} = get_time_range(time_range)
    
    # Get tool-specific data
    history = Monitoring.get_tool_history(tool_name, limit: 1000)
    stats = calculate_tool_stats(history)
    
    %{
      tool_name: tool_name,
      time_range: time_range,
      statistics: stats,
      execution_history: format_execution_history(history),
      performance_metrics: calculate_tool_performance(tool_name, start_time, end_time),
      error_analysis: analyze_tool_errors(tool_name, start_time, end_time),
      usage_patterns: analyze_usage_patterns(history)
    }
  end
  
  defp compile_system_overview(state) do
    %{
      system_health: get_detailed_health_status(),
      execution_summary: get_execution_summary(),
      performance_summary: get_performance_summary(),
      resource_utilization: get_detailed_resource_usage(),
      tool_registry: get_tool_registry_info(),
      cache_statistics: get_cache_statistics(),
      storage_statistics: get_storage_statistics(),
      monitoring_status: %{
        uptime_seconds: System.system_time(:second) - state.last_update,
        events_buffered: length(state.metrics_buffer),
        last_refresh: DateTime.from_unix!(state.last_update)
      }
    }
  end
  
  defp refresh_dashboard_data(state) do
    # Refresh cached data
    %{state | 
      last_update: System.system_time(:second),
      cached_data: %{
        dashboard: compile_dashboard_data(state),
        overview: compile_system_overview(state)
      }
    }
  end
  
  defp buffer_event(event, state) do
    # Keep only recent events (last 1000)
    new_buffer = [event | state.metrics_buffer] |> Enum.take(1000)
    %{state | metrics_buffer: new_buffer}
  end
  
  defp broadcast_dashboard_update(state) do
    Phoenix.PubSub.broadcast(
      RubberDuck.PubSub,
      "monitoring_dashboard",
      {:dashboard_update, state.cached_data.dashboard}
    )
  end
  
  defp broadcast_real_time_event(event) do
    Phoenix.PubSub.broadcast(
      RubberDuck.PubSub,
      "monitoring_dashboard",
      {:real_time_event, event}
    )
  end
  
  defp get_active_executions_count do
    # This would query the executor for active executions
    :rand.uniform(10)
  end
  
  defp get_total_tools_count do
    # This would query the tool registry
    length(RubberDuck.Tool.Registry.list())
  rescue
    _ -> 0
  end
  
  defp get_uptime do
    # Get application uptime
    case :application.get_key(:rubber_duck, :started_at) do
      {:ok, started_at} ->
        System.system_time(:second) - started_at
      _ ->
        0
    end
  end
  
  defp get_top_tools(limit) do
    current_time = System.system_time(:microsecond)
    last_hour = current_time - 3_600_000_000
    
    stats = Monitoring.get_execution_stats(last_hour, current_time)
    
    stats.tools
    |> Enum.map(fn {tool_name, tool_stats} ->
      %{
        name: tool_name,
        executions: tool_stats.executions,
        failures: tool_stats.failures,
        success_rate: calculate_tool_success_rate(tool_stats)
      }
    end)
    |> Enum.sort_by(& &1.executions, :desc)
    |> Enum.take(limit)
  end
  
  defp calculate_tool_success_rate(%{executions: 0}), do: 0.0
  defp calculate_tool_success_rate(%{executions: total, failures: failures}) do
    Float.round((total - failures) / total * 100, 2)
  end
  
  defp get_recent_errors(limit) do
    Monitoring.get_error_stats(time_window: 3600)
    |> Map.get(:by_reason, %{})
    |> Enum.map(fn {reason, count} ->
      %{reason: reason, count: count}
    end)
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(limit)
  end
  
  defp calculate_performance_trends do
    # Calculate performance trends over different time windows
    current_time = System.system_time(:microsecond)
    
    windows = [
      {:last_5_min, 300},
      {:last_15_min, 900},
      {:last_hour, 3600},
      {:last_6_hours, 21600},
      {:last_day, 86400}
    ]
    
    Enum.map(windows, fn {label, seconds} ->
      start_time = current_time - (seconds * 1_000_000)
      stats = Monitoring.get_execution_stats(start_time, current_time)
      
      %{
        label: label,
        avg_execution_time: stats.avg_execution_time,
        success_rate: stats.success_rate,
        error_rate: stats.error_rate,
        total_executions: stats.total_executions
      }
    end)
  end
  
  defp get_resource_usage do
    memory_info = :erlang.memory()
    
    %{
      memory: %{
        total_mb: memory_info[:total] / 1_048_576,
        processes_mb: memory_info[:processes] / 1_048_576,
        ets_mb: memory_info[:ets] / 1_048_576,
        binary_mb: memory_info[:binary] / 1_048_576
      },
      processes: %{
        count: length(:erlang.processes()),
        limit: :erlang.system_info(:process_limit)
      },
      io: get_io_statistics(),
      scheduler_usage: get_scheduler_usage()
    }
  end
  
  defp get_io_statistics do
    {{:input, input}, {:output, output}} = :erlang.statistics(:io)
    
    %{
      input_mb: input / 1_048_576,
      output_mb: output / 1_048_576
    }
  end
  
  defp get_scheduler_usage do
    # Scheduler utilization is not available in standard OTP
    # Would require additional dependencies
    []
  end
  
  defp filter_buffered_events(buffer, start_time) do
    Enum.filter(buffer, fn event ->
      event.timestamp >= start_time
    end)
  end
  
  defp get_historical_metrics(_start_time, _end_time) do
    # Query historical metrics from monitoring
    []
  end
  
  defp build_time_series(events) do
    # Group events by time bucket (1 minute buckets)
    events
    |> Enum.group_by(fn event ->
      div(event.timestamp, 60_000_000) * 60_000_000
    end)
    |> Enum.map(fn {bucket, bucket_events} ->
      %{
        timestamp: DateTime.from_unix!(bucket, :microsecond),
        executions: length(bucket_events),
        failures: Enum.count(bucket_events, & &1.event == :failed),
        avg_duration: calculate_avg_duration(bucket_events)
      }
    end)
    |> Enum.sort_by(& &1.timestamp)
  end
  
  defp calculate_avg_duration(events) do
    durations = events
    |> Enum.filter(& &1.measurements[:execution_time])
    |> Enum.map(& &1.measurements.execution_time)
    
    if length(durations) > 0 do
      Enum.sum(durations) / length(durations)
    else
      0
    end
  end
  
  defp calculate_stream_aggregates(events) do
    %{
      total_events: length(events),
      execution_events: Enum.count(events, & &1.event in [:started, :completed, :failed]),
      error_events: Enum.count(events, & &1.event == :failed),
      avg_execution_time: calculate_avg_duration(events),
      unique_tools: events |> Enum.map(& &1.tool_name) |> Enum.uniq() |> length()
    }
  end
  
  defp get_time_range(:last_hour) do
    current = System.system_time(:microsecond)
    {current - 3_600_000_000, current}
  end
  
  defp get_time_range(:last_day) do
    current = System.system_time(:microsecond)
    {current - 86_400_000_000, current}
  end
  
  defp get_time_range(:last_week) do
    current = System.system_time(:microsecond)
    {current - 604_800_000_000, current}
  end
  
  defp get_time_range({:custom, start_time, end_time}) do
    {start_time, end_time}
  end
  
  defp calculate_tool_stats(history) do
    Enum.reduce(history, %{
      total_executions: 0,
      successful: 0,
      failed: 0,
      total_duration: 0,
      min_duration: nil,
      max_duration: nil
    }, fn execution, stats ->
      stats
      |> Map.update!(:total_executions, & &1 + 1)
      |> update_success_stats(execution)
      |> update_duration_stats(execution)
    end)
  end
  
  defp update_success_stats(stats, execution) do
    case execution.event do
      :completed -> Map.update!(stats, :successful, & &1 + 1)
      :failed -> Map.update!(stats, :failed, & &1 + 1)
      _ -> stats
    end
  end
  
  defp update_duration_stats(stats, execution) do
    if duration = get_in(execution, [:measurements, :execution_time]) do
      stats
      |> Map.update!(:total_duration, & &1 + duration)
      |> Map.update(:min_duration, duration, &min(&1, duration))
      |> Map.update(:max_duration, duration, &max(&1, duration))
    else
      stats
    end
  end
  
  defp format_execution_history(history) do
    Enum.map(history, fn execution ->
      %{
        timestamp: DateTime.from_unix!(execution.timestamp, :microsecond),
        event: execution.event,
        duration: get_in(execution, [:measurements, :execution_time]),
        metadata: execution.metadata
      }
    end)
  end
  
  defp calculate_tool_performance(tool_name, start_time, end_time) do
    # Calculate detailed performance metrics
    %{
      execution_time_distribution: calculate_execution_distribution(tool_name, start_time, end_time),
      throughput: calculate_throughput(tool_name, start_time, end_time),
      concurrency: calculate_concurrency_metrics(tool_name, start_time, end_time)
    }
  end
  
  defp calculate_execution_distribution(_tool_name, _start_time, _end_time) do
    # Would calculate percentiles and distribution
    %{
      p50: 50,
      p90: 100,
      p95: 150,
      p99: 200
    }
  end
  
  defp calculate_throughput(_tool_name, start_time, end_time) do
    _duration_seconds = (end_time - start_time) / 1_000_000
    # Would calculate actual throughput
    %{
      executions_per_second: 2.5,
      executions_per_minute: 150
    }
  end
  
  defp calculate_concurrency_metrics(_tool_name, _start_time, _end_time) do
    %{
      max_concurrent: 5,
      avg_concurrent: 2.3
    }
  end
  
  defp analyze_tool_errors(_tool_name, _start_time, _end_time) do
    # Analyze error patterns
    %{
      error_types: %{
        timeout: 5,
        validation_failed: 3,
        execution_failed: 2
      },
      error_timeline: [],
      error_rate_trend: :decreasing
    }
  end
  
  defp analyze_usage_patterns(_history) do
    # Analyze when the tool is used most
    %{
      peak_hours: [14, 15, 16], # 2-5 PM
      peak_days: [:tuesday, :wednesday, :thursday],
      usage_trend: :increasing
    }
  end
  
  defp get_detailed_health_status do
    health = Monitoring.get_health_status()
    
    # Add more detailed information
    Map.put(health, :recommendations, generate_health_recommendations(health))
  end
  
  defp generate_health_recommendations(health) do
    recommendations = []
    
    recommendations = if health.overall == :unhealthy do
      ["System is unhealthy. Immediate attention required." | recommendations]
    else
      recommendations
    end
    
    # Check specific components
    Enum.reduce(health.checks, recommendations, fn check, recs ->
      case {check.component, check.status} do
        {:error_rate, :unhealthy} ->
          ["High error rate detected. Review recent failures." | recs]
        {:error_rate, :degraded} ->
          ["Elevated error rate. Monitor closely." | recs]
        {:resources, :unhealthy} ->
          ["High resource usage. Consider scaling." | recs]
        {:resources, :degraded} ->
          ["Resource usage is elevated." | recs]
        _ ->
          recs
      end
    end)
  end
  
  defp get_execution_summary do
    current_time = System.system_time(:microsecond)
    last_hour = current_time - 3_600_000_000
    
    stats = Monitoring.get_execution_stats(last_hour, current_time)
    
    %{
      last_hour: stats,
      trends: %{
        execution_rate: :stable,
        error_rate: :decreasing,
        performance: :improving
      }
    }
  end
  
  defp get_performance_summary do
    %{
      avg_execution_time_ms: 125,
      p95_execution_time_ms: 250,
      slowest_tools: get_slowest_tools(5),
      fastest_tools: get_fastest_tools(5)
    }
  end
  
  defp get_slowest_tools(_limit) do
    # Would query actual data
    [
      %{name: :complex_tool, avg_time: 500},
      %{name: :data_processor, avg_time: 350}
    ]
  end
  
  defp get_fastest_tools(_limit) do
    # Would query actual data
    [
      %{name: :simple_tool, avg_time: 10},
      %{name: :echo_tool, avg_time: 15}
    ]
  end
  
  defp get_detailed_resource_usage do
    %{
      memory: get_memory_breakdown(),
      cpu: get_cpu_usage(),
      io: get_io_usage(),
      network: get_network_usage()
    }
  end
  
  defp get_memory_breakdown do
    memory = :erlang.memory()
    
    %{
      total_mb: memory[:total] / 1_048_576,
      breakdown: %{
        processes: memory[:processes] / 1_048_576,
        ets: memory[:ets] / 1_048_576,
        binary: memory[:binary] / 1_048_576,
        code: memory[:code] / 1_048_576,
        atom: memory[:atom] / 1_048_576
      }
    }
  end
  
  defp get_cpu_usage do
    %{
      scheduler_usage: [],
      load_average: 0.0
    }
  rescue
    _ -> %{scheduler_usage: [], load_average: 0}
  end
  
  defp get_io_usage do
    {{:input, input}, {:output, output}} = :erlang.statistics(:io)
    
    %{
      input_rate_mb_per_sec: 0.0, # Would calculate rate
      output_rate_mb_per_sec: 0.0,
      total_input_mb: input / 1_048_576,
      total_output_mb: output / 1_048_576
    }
  end
  
  defp get_network_usage do
    %{
      connections: 0, # Would get actual connection count
      bandwidth_in_mbps: 0.0,
      bandwidth_out_mbps: 0.0
    }
  end
  
  defp get_tool_registry_info do
    try do
      tools = RubberDuck.Tool.Registry.list()
      
      %{
        total_tools: length(tools),
        by_category: group_tools_by_category(tools),
        recently_updated: [] # Would track updates
      }
    rescue
      _ -> %{total_tools: 0, by_category: %{}, recently_updated: []}
    end
  end
  
  defp group_tools_by_category(tools) do
    Enum.group_by(tools, fn tool ->
      try do
        metadata = tool.metadata()
        metadata.category || :uncategorized
      rescue
        _ -> :uncategorized
      end
    end)
    |> Enum.map(fn {category, category_tools} ->
      {category, length(category_tools)}
    end)
    |> Enum.into(%{})
  end
  
  defp get_cache_statistics do
    RubberDuck.Cache.ETS.stats()
  rescue
    _ -> %{error: "Cache unavailable"}
  end
  
  defp get_storage_statistics do
    RubberDuck.Storage.FileSystem.stats()
  rescue
    _ -> %{error: "Storage unavailable"}
  end
  
  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end
end