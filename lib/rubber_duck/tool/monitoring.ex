defmodule RubberDuck.Tool.Monitoring do
  @moduledoc """
  Monitoring and observability system for tool execution.
  
  Provides comprehensive monitoring capabilities including:
  - Real-time execution metrics
  - Performance tracking
  - Error rate monitoring
  - Resource usage tracking
  - Execution history
  - Health checks
  """
  
  use GenServer
  require Logger
  
  @table_name :tool_monitoring_data
  @metrics_interval 60_000 # 1 minute
  @history_retention 24 * 60 * 60 # 24 hours in seconds
  
  @type metric_type :: :counter | :gauge | :histogram | :summary
  
  @type metric :: %{
    name: String.t(),
    type: metric_type(),
    value: number(),
    labels: map(),
    timestamp: integer()
  }
  
  @type health_status :: :healthy | :degraded | :unhealthy
  
  @type health_check :: %{
    component: atom(),
    status: health_status(),
    message: String.t() | nil,
    checked_at: DateTime.t()
  }
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Records a tool execution event.
  """
  @spec record_execution(atom(), atom(), map(), map()) :: :ok
  def record_execution(event, tool_name, metadata, measurements) do
    timestamp = System.system_time(:microsecond)
    
    execution_record = %{
      event: event,
      tool_name: tool_name,
      metadata: metadata,
      measurements: measurements,
      timestamp: timestamp
    }
    
    GenServer.cast(__MODULE__, {:record_execution, execution_record})
  end
  
  @doc """
  Records a metric.
  """
  @spec record_metric(String.t(), metric_type(), number(), map()) :: :ok
  def record_metric(name, type, value, labels \\ %{}) do
    metric = %{
      name: name,
      type: type,
      value: value,
      labels: labels,
      timestamp: System.system_time(:microsecond)
    }
    
    GenServer.cast(__MODULE__, {:record_metric, metric})
  end
  
  @doc """
  Increments a counter metric.
  """
  @spec increment_counter(String.t(), map()) :: :ok
  def increment_counter(name, labels \\ %{}) do
    record_metric(name, :counter, 1, labels)
  end
  
  @doc """
  Records a gauge metric.
  """
  @spec set_gauge(String.t(), number(), map()) :: :ok
  def set_gauge(name, value, labels \\ %{}) do
    record_metric(name, :gauge, value, labels)
  end
  
  @doc """
  Records a histogram observation.
  """
  @spec observe_histogram(String.t(), number(), map()) :: :ok
  def observe_histogram(name, value, labels \\ %{}) do
    record_metric(name, :histogram, value, labels)
  end
  
  @doc """
  Gets current metrics.
  """
  @spec get_metrics() :: %{String.t() => map()}
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end
  
  @doc """
  Gets execution statistics for a time range.
  """
  @spec get_execution_stats(integer(), integer()) :: map()
  def get_execution_stats(from_timestamp, to_timestamp) do
    GenServer.call(__MODULE__, {:get_execution_stats, from_timestamp, to_timestamp})
  end
  
  @doc """
  Gets execution history for a specific tool.
  """
  @spec get_tool_history(atom(), keyword()) :: [map()]
  def get_tool_history(tool_name, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    GenServer.call(__MODULE__, {:get_tool_history, tool_name, limit})
  end
  
  @doc """
  Gets system health status.
  """
  @spec get_health_status() :: %{overall: health_status(), checks: [health_check()]}
  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end
  
  @doc """
  Gets error statistics.
  """
  @spec get_error_stats(keyword()) :: map()
  def get_error_stats(opts \\ []) do
    time_window = Keyword.get(opts, :time_window, 3600) # 1 hour default
    GenServer.call(__MODULE__, {:get_error_stats, time_window})
  end
  
  @doc """
  Exports metrics in Prometheus format.
  """
  @spec export_prometheus_metrics() :: String.t()
  def export_prometheus_metrics do
    GenServer.call(__MODULE__, :export_prometheus_metrics)
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Create ETS tables for storing metrics and history
    :ets.new(@table_name, [:set, :public, :named_table, {:read_concurrency, true}])
    :ets.new(:tool_execution_history, [:ordered_set, :public, :named_table])
    :ets.new(:tool_metrics_aggregates, [:set, :public, :named_table])
    
    # Initialize telemetry handlers
    setup_telemetry_handlers()
    
    # Schedule periodic tasks
    schedule_metrics_aggregation()
    schedule_history_cleanup()
    
    state = %{
      start_time: System.system_time(:second),
      metrics: %{},
      health_checks: %{}
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:record_execution, record}, state) do
    # Store in execution history
    store_execution_record(record)
    
    # Update metrics based on execution
    update_execution_metrics(record)
    
    # Emit telemetry event
    emit_execution_telemetry(record)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_cast({:record_metric, metric}, state) do
    # Store metric
    store_metric(metric)
    
    # Update aggregates
    update_metric_aggregates(metric)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = collect_current_metrics()
    {:reply, metrics, state}
  end
  
  @impl true
  def handle_call({:get_execution_stats, from_timestamp, to_timestamp}, _from, state) do
    stats = calculate_execution_stats(from_timestamp, to_timestamp)
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call({:get_tool_history, tool_name, limit}, _from, state) do
    history = fetch_tool_history(tool_name, limit)
    {:reply, history, state}
  end
  
  @impl true
  def handle_call(:get_health_status, _from, state) do
    health_status = perform_health_checks(state)
    {:reply, health_status, state}
  end
  
  @impl true
  def handle_call({:get_error_stats, time_window}, _from, state) do
    error_stats = calculate_error_stats(time_window)
    {:reply, error_stats, state}
  end
  
  @impl true
  def handle_call(:export_prometheus_metrics, _from, state) do
    prometheus_output = format_prometheus_metrics()
    {:reply, prometheus_output, state}
  end
  
  @impl true
  def handle_info(:aggregate_metrics, state) do
    aggregate_metrics()
    schedule_metrics_aggregation()
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:cleanup_history, state) do
    cleanup_old_history()
    schedule_history_cleanup()
    {:noreply, state}
  end
  
  # Private functions
  
  defp setup_telemetry_handlers do
    # Tool execution events
    :telemetry.attach_many(
      "tool-monitoring-execution",
      [
        [:rubber_duck, :tool, :execution, :start],
        [:rubber_duck, :tool, :execution, :stop],
        [:rubber_duck, :tool, :execution, :exception]
      ],
      &handle_telemetry_event/4,
      nil
    )
    
    # Validation events
    :telemetry.attach_many(
      "tool-monitoring-validation",
      [
        [:rubber_duck, :tool, :validation, :start],
        [:rubber_duck, :tool, :validation, :stop]
      ],
      &handle_telemetry_event/4,
      nil
    )
    
    # Authorization events
    :telemetry.attach_many(
      "tool-monitoring-authorization",
      [
        [:rubber_duck, :tool, :authorization, :start],
        [:rubber_duck, :tool, :authorization, :stop]
      ],
      &handle_telemetry_event/4,
      nil
    )
    
    # Sandbox events
    :telemetry.attach_many(
      "tool-monitoring-sandbox",
      [
        [:rubber_duck, :tool, :sandbox, :execution],
        [:rubber_duck, :tool, :sandbox, :violation]
      ],
      &handle_telemetry_event/4,
      nil
    )
    
    # Result processing events
    :telemetry.attach_many(
      "tool-monitoring-result",
      [
        [:rubber_duck, :tool, :result, :processed],
        [:rubber_duck, :tool, :result, :cached]
      ],
      &handle_telemetry_event/4,
      nil
    )
  end
  
  defp handle_telemetry_event(event_name, measurements, metadata, _config) do
    case event_name do
      [:rubber_duck, :tool, :execution, :start] ->
        increment_counter("tool_executions_total", %{tool: metadata.tool})
        set_gauge("tool_executions_active", get_active_executions() + 1, %{})
      
      [:rubber_duck, :tool, :execution, :stop] ->
        observe_histogram("tool_execution_duration_ms", measurements.duration, %{tool: metadata.tool})
        set_gauge("tool_executions_active", max(0, get_active_executions() - 1), %{})
        
        if metadata[:status] == :success do
          increment_counter("tool_executions_success_total", %{tool: metadata.tool})
        else
          increment_counter("tool_executions_failure_total", %{tool: metadata.tool, reason: metadata[:reason]})
        end
      
      [:rubber_duck, :tool, :execution, :exception] ->
        increment_counter("tool_executions_exception_total", %{tool: metadata.tool, kind: metadata.kind})
        set_gauge("tool_executions_active", max(0, get_active_executions() - 1), %{})
      
      [:rubber_duck, :tool, :validation, :stop] ->
        observe_histogram("tool_validation_duration_ms", measurements.duration, %{tool: metadata.tool})
        if metadata[:valid] do
          increment_counter("tool_validations_success_total", %{tool: metadata.tool})
        else
          increment_counter("tool_validations_failure_total", %{tool: metadata.tool})
        end
      
      [:rubber_duck, :tool, :authorization, :stop] ->
        observe_histogram("tool_authorization_duration_ms", measurements.duration, %{tool: metadata.tool})
        if metadata[:authorized] do
          increment_counter("tool_authorizations_success_total", %{tool: metadata.tool})
        else
          increment_counter("tool_authorizations_denied_total", %{tool: metadata.tool, reason: metadata[:reason]})
        end
      
      [:rubber_duck, :tool, :sandbox, :execution] ->
        observe_histogram("tool_sandbox_execution_duration_ms", measurements.duration, %{
          tool: metadata.tool,
          sandbox_level: metadata.sandbox_level
        })
      
      [:rubber_duck, :tool, :sandbox, :violation] ->
        increment_counter("tool_sandbox_violations_total", %{
          tool: metadata.tool,
          violation_type: metadata.violation_type
        })
      
      [:rubber_duck, :tool, :result, :processed] ->
        observe_histogram("tool_result_processing_duration_ms", measurements.processing_time, %{
          tool: metadata.tool,
          format: metadata.format
        })
        observe_histogram("tool_result_size_bytes", measurements.output_size, %{tool: metadata.tool})
      
      [:rubber_duck, :tool, :result, :cached] ->
        increment_counter("tool_result_cache_operations_total", %{
          tool: metadata.tool,
          operation: metadata.operation,
          status: metadata.status
        })
      
      _ ->
        Logger.debug("Unhandled telemetry event: #{inspect(event_name)}")
    end
  end
  
  defp store_execution_record(record) do
    key = {record.timestamp, record.tool_name, :rand.uniform(1000)}
    :ets.insert(:tool_execution_history, {key, record})
  end
  
  defp update_execution_metrics(record) do
    case record.event do
      :started ->
        increment_counter("tool.executions.started", %{tool: record.tool_name})
      
      :completed ->
        increment_counter("tool.executions.completed", %{tool: record.tool_name})
        if record.measurements[:execution_time] do
          observe_histogram("tool.execution.duration", record.measurements.execution_time, %{tool: record.tool_name})
        end
      
      :failed ->
        increment_counter("tool.executions.failed", %{tool: record.tool_name, reason: record.metadata[:reason]})
      
      _ ->
        :ok
    end
  end
  
  defp emit_execution_telemetry(record) do
    Phoenix.PubSub.broadcast(
      RubberDuck.PubSub,
      "tool_monitoring",
      {:tool_execution_event, record}
    )
  end
  
  defp store_metric(metric) do
    key = {metric.name, metric.labels}
    
    case metric.type do
      :counter ->
        current = case :ets.lookup(@table_name, key) do
          [{^key, data}] -> data.value
          [] -> 0
        end
        :ets.insert(@table_name, {key, %{metric | value: current + metric.value}})
      
      :gauge ->
        :ets.insert(@table_name, {key, metric})
      
      :histogram ->
        store_histogram_observation(key, metric)
      
      :summary ->
        store_summary_observation(key, metric)
    end
  end
  
  defp store_histogram_observation(key, metric) do
    hist_key = {:histogram, key}
    
    observations = case :ets.lookup(@table_name, hist_key) do
      [{^hist_key, obs}] -> obs
      [] -> []
    end
    
    updated = [metric.value | observations] |> Enum.take(1000) # Keep last 1000 observations
    :ets.insert(@table_name, {hist_key, updated})
  end
  
  defp store_summary_observation(key, metric) do
    summary_key = {:summary, key}
    
    summary = case :ets.lookup(@table_name, summary_key) do
      [{^summary_key, data}] -> data
      [] -> %{count: 0, sum: 0, min: nil, max: nil}
    end
    
    updated = %{
      count: summary.count + 1,
      sum: summary.sum + metric.value,
      min: min(summary.min || metric.value, metric.value),
      max: max(summary.max || metric.value, metric.value)
    }
    
    :ets.insert(@table_name, {summary_key, updated})
  end
  
  defp update_metric_aggregates(metric) do
    # Update aggregates for reporting
    aggregate_key = {metric.name, :aggregate}
    
    aggregate = case :ets.lookup(:tool_metrics_aggregates, aggregate_key) do
      [{^aggregate_key, agg}] -> agg
      [] -> %{
        type: metric.type,
        labels: MapSet.new(),
        first_seen: metric.timestamp,
        last_updated: metric.timestamp
      }
    end
    
    updated = %{aggregate |
      labels: MapSet.put(aggregate.labels, metric.labels),
      last_updated: metric.timestamp
    }
    
    :ets.insert(:tool_metrics_aggregates, {aggregate_key, updated})
  end
  
  defp collect_current_metrics do
    # Collect all current metric values
    :ets.tab2list(@table_name)
    |> Enum.reduce(%{}, fn {{name, labels}, value}, acc ->
      metric_key = "#{name}#{format_labels(labels)}"
      Map.put(acc, metric_key, value)
    end)
  end
  
  defp calculate_execution_stats(from_timestamp, to_timestamp) do
    # Query execution history
    executions = :ets.select(:tool_execution_history, [
      {{{:"$1", :"$2", :"$3"}, :"$4"},
       [{:andalso, {:>=, :"$1", from_timestamp}, {:"=<", :"$1", to_timestamp}}],
       [:"$4"]}
    ])
    
    # Calculate statistics
    stats = Enum.reduce(executions, %{
      total_executions: 0,
      successful_executions: 0,
      failed_executions: 0,
      tools: %{},
      error_reasons: %{},
      avg_execution_time: 0,
      max_execution_time: 0
    }, fn execution, acc ->
      acc
      |> Map.update!(:total_executions, & &1 + 1)
      |> update_execution_success_stats(execution)
      |> update_tool_stats(execution)
      |> update_timing_stats(execution)
    end)
    
    # Calculate derived metrics
    Map.put(stats, :success_rate, calculate_success_rate(stats))
    |> Map.put(:error_rate, calculate_error_rate(stats))
  end
  
  defp update_execution_success_stats(stats, execution) do
    case execution.event do
      :completed -> Map.update!(stats, :successful_executions, & &1 + 1)
      :failed -> 
        stats
        |> Map.update!(:failed_executions, & &1 + 1)
        |> Map.update(:error_reasons, %{}, fn reasons ->
          reason = get_in(execution, [:metadata, :reason]) || :unknown
          Map.update(reasons, reason, 1, & &1 + 1)
        end)
      _ -> stats
    end
  end
  
  defp update_tool_stats(stats, execution) do
    Map.update(stats, :tools, %{}, fn tools ->
      Map.update(tools, execution.tool_name, %{executions: 0, failures: 0}, fn tool_stats ->
        tool_stats
        |> Map.update!(:executions, & &1 + 1)
        |> then(fn ts ->
          if execution.event == :failed do
            Map.update!(ts, :failures, & &1 + 1)
          else
            ts
          end
        end)
      end)
    end)
  end
  
  defp update_timing_stats(stats, execution) do
    if execution_time = get_in(execution, [:measurements, :execution_time]) do
      current_avg = stats.avg_execution_time
      current_count = stats.successful_executions
      
      new_avg = if current_count > 0 do
        (current_avg * (current_count - 1) + execution_time) / current_count
      else
        execution_time
      end
      
      stats
      |> Map.put(:avg_execution_time, new_avg)
      |> Map.put(:max_execution_time, max(stats.max_execution_time, execution_time))
    else
      stats
    end
  end
  
  defp calculate_success_rate(%{total_executions: 0}), do: 0.0
  defp calculate_success_rate(%{total_executions: total, successful_executions: successful}) do
    Float.round(successful / total * 100, 2)
  end
  
  defp calculate_error_rate(%{total_executions: 0}), do: 0.0
  defp calculate_error_rate(%{total_executions: total, failed_executions: failed}) do
    Float.round(failed / total * 100, 2)
  end
  
  defp fetch_tool_history(tool_name, limit) do
    # Get recent executions for a specific tool
    :ets.select(:tool_execution_history, [
      {{{:"$1", :"$2", :"$3"}, :"$4"},
       [{:"==", :"$2", tool_name}],
       [:"$4"]}
    ])
    |> Enum.sort_by(& &1.timestamp, :desc)
    |> Enum.take(limit)
  end
  
  defp perform_health_checks(state) do
    checks = [
      check_execution_health(),
      check_error_rate_health(),
      check_resource_health(),
      check_cache_health(),
      check_storage_health()
    ]
    
    overall_status = determine_overall_health(checks)
    
    %{
      overall: overall_status,
      checks: checks,
      uptime_seconds: System.system_time(:second) - state.start_time
    }
  end
  
  defp check_execution_health do
    # Check if executions are happening
    recent_executions = count_recent_executions(300) # Last 5 minutes
    
    status = cond do
      recent_executions == 0 -> :unhealthy
      recent_executions < 10 -> :degraded
      true -> :healthy
    end
    
    %{
      component: :execution,
      status: status,
      message: "#{recent_executions} executions in last 5 minutes",
      checked_at: DateTime.utc_now()
    }
  end
  
  defp check_error_rate_health do
    # Check error rate
    stats = calculate_execution_stats(
      System.system_time(:microsecond) - 300_000_000, # Last 5 minutes
      System.system_time(:microsecond)
    )
    
    error_rate = stats.error_rate
    
    status = cond do
      error_rate > 50.0 -> :unhealthy
      error_rate > 10.0 -> :degraded
      true -> :healthy
    end
    
    %{
      component: :error_rate,
      status: status,
      message: "Error rate: #{error_rate}%",
      checked_at: DateTime.utc_now()
    }
  end
  
  defp check_resource_health do
    # Check system resources
    memory_usage = :erlang.memory(:total) / 1_000_000 # MB
    
    status = cond do
      memory_usage > 1000 -> :unhealthy
      memory_usage > 500 -> :degraded
      true -> :healthy
    end
    
    %{
      component: :resources,
      status: status,
      message: "Memory usage: #{Float.round(memory_usage, 2)} MB",
      checked_at: DateTime.utc_now()
    }
  end
  
  defp check_cache_health do
    # Check cache status
    cache_stats = RubberDuck.Cache.ETS.stats()
    
    status = if cache_stats[:error] do
      :unhealthy
    else
      :healthy
    end
    
    message = if cache_stats[:error] do
      "Cache error: #{cache_stats.error}"
    else
      "Cache entries: #{cache_stats.total_entries}"
    end
    
    %{
      component: :cache,
      status: status,
      message: message,
      checked_at: DateTime.utc_now()
    }
  end
  
  defp check_storage_health do
    # Check storage status
    storage_stats = RubberDuck.Storage.FileSystem.stats()
    
    status = if storage_stats[:error] do
      :unhealthy
    else
      :healthy
    end
    
    message = if storage_stats[:error] do
      "Storage error: #{storage_stats.error}"
    else
      "Storage files: #{storage_stats.total_files}"
    end
    
    %{
      component: :storage,
      status: status,
      message: message,
      checked_at: DateTime.utc_now()
    }
  end
  
  defp determine_overall_health(checks) do
    cond do
      Enum.any?(checks, & &1.status == :unhealthy) -> :unhealthy
      Enum.any?(checks, & &1.status == :degraded) -> :degraded
      true -> :healthy
    end
  end
  
  defp count_recent_executions(seconds_ago) do
    since = System.system_time(:microsecond) - (seconds_ago * 1_000_000)
    
    :ets.select(:tool_execution_history, [
      {{{:"$1", :"$2", :"$3"}, :"$4"},
       [{:>, :"$1", since}],
       [true]}
    ])
    |> length()
  end
  
  defp calculate_error_stats(time_window_seconds) do
    since = System.system_time(:microsecond) - (time_window_seconds * 1_000_000)
    
    errors = :ets.select(:tool_execution_history, [
      {{{:"$1", :"$2", :"$3"}, :"$4"},
       [{:andalso, {:>, :"$1", since}, {:==, {:map_get, :event, :"$4"}, :failed}}],
       [:"$4"]}
    ])
    
    errors
    |> Enum.reduce(%{total_errors: 0, by_tool: %{}, by_reason: %{}}, fn error, acc ->
      acc
      |> Map.update!(:total_errors, & &1 + 1)
      |> Map.update(:by_tool, %{}, fn tools ->
        Map.update(tools, error.tool_name, 1, & &1 + 1)
      end)
      |> Map.update(:by_reason, %{}, fn reasons ->
        reason = get_in(error, [:metadata, :reason]) || :unknown
        Map.update(reasons, reason, 1, & &1 + 1)
      end)
    end)
  end
  
  defp format_prometheus_metrics do
    metrics = collect_all_metrics()
    
    Enum.map(metrics, fn {metric_name, metric_data} ->
      format_prometheus_metric(metric_name, metric_data)
    end)
    |> Enum.join("\n\n")
  end
  
  defp collect_all_metrics do
    # Collect metrics from ETS
    counters = collect_metrics_by_type(:counter)
    gauges = collect_metrics_by_type(:gauge)
    histograms = collect_histogram_metrics()
    
    Map.merge(counters, gauges)
    |> Map.merge(histograms)
  end
  
  defp collect_metrics_by_type(type) do
    :ets.tab2list(@table_name)
    |> Enum.filter(fn {{_name, _labels}, data} -> 
      is_map(data) and Map.get(data, :type) == type
    end)
    |> Enum.reduce(%{}, fn {{name, labels}, data}, acc ->
      Map.put(acc, {name, labels}, data)
    end)
  end
  
  defp collect_histogram_metrics do
    :ets.tab2list(@table_name)
    |> Enum.filter(fn {key, _data} -> 
      match?({:histogram, _}, key)
    end)
    |> Enum.reduce(%{}, fn {{:histogram, {name, labels}}, observations}, acc ->
      Map.put(acc, {name, labels}, %{
        type: :histogram,
        observations: observations,
        name: name,
        labels: labels
      })
    end)
  end
  
  defp format_prometheus_metric({name, labels}, data) do
    metric_name = String.replace(name, ".", "_")
    labels_str = format_labels(labels)
    
    case data.type do
      :counter ->
        "# TYPE #{metric_name} counter\n#{metric_name}#{labels_str} #{data.value}"
      
      :gauge ->
        "# TYPE #{metric_name} gauge\n#{metric_name}#{labels_str} #{data.value}"
      
      :histogram ->
        format_prometheus_histogram(metric_name, labels_str, data.observations)
      
      _ ->
        ""
    end
  end
  
  defp format_prometheus_histogram(name, labels_str, observations) do
    buckets = [0.1, 0.5, 1, 5, 10, 50, 100, 500, 1000, 5000]
    
    bucket_counts = calculate_bucket_counts(observations, buckets)
    sum = Enum.sum(observations)
    count = length(observations)
    
    bucket_lines = Enum.map(buckets, fn bucket ->
      "#{name}_bucket{le=\"#{bucket}\"#{labels_str}} #{Map.get(bucket_counts, bucket, 0)}"
    end)
    
    all_lines = bucket_lines ++ [
      "#{name}_bucket{le=\"+Inf\"#{labels_str}} #{count}",
      "#{name}_sum#{labels_str} #{sum}",
      "#{name}_count#{labels_str} #{count}"
    ]
    
    "# TYPE #{name} histogram\n" <> Enum.join(all_lines, "\n")
  end
  
  defp calculate_bucket_counts(observations, buckets) do
    Enum.reduce(buckets, %{}, fn bucket, acc ->
      count = Enum.count(observations, & &1 <= bucket)
      Map.put(acc, bucket, count)
    end)
  end
  
  defp format_labels(labels) when labels == %{}, do: ""
  defp format_labels(labels) do
    label_pairs = Enum.map(labels, fn {k, v} ->
      "#{k}=\"#{v}\""
    end)
    |> Enum.join(",")
    
    "{#{label_pairs}}"
  end
  
  defp get_active_executions do
    case :ets.lookup(@table_name, {"tool_executions_active", %{}}) do
      [{{_, _}, %{value: value}}] -> value
      [] -> 0
    end
  end
  
  defp aggregate_metrics do
    # Perform periodic aggregation of metrics
    Logger.debug("Aggregating metrics...")
    
    # Aggregate histograms
    aggregate_histograms()
    
    # Clean up old metrics
    cleanup_old_metrics()
  end
  
  defp aggregate_histograms do
    # Calculate percentiles for histograms
    :ets.tab2list(@table_name)
    |> Enum.filter(fn {key, _} -> match?({:histogram, _}, key) end)
    |> Enum.each(fn {{:histogram, {name, labels}}, observations} ->
      if length(observations) > 0 do
        sorted = Enum.sort(observations)
        
        percentiles = %{
          p50: percentile(sorted, 0.5),
          p90: percentile(sorted, 0.9),
          p95: percentile(sorted, 0.95),
          p99: percentile(sorted, 0.99)
        }
        
        # Store percentiles
        Enum.each(percentiles, fn {p, value} ->
          gauge_name = "#{name}_#{p}"
          set_gauge(gauge_name, value, labels)
        end)
      end
    end)
  end
  
  defp percentile(sorted_list, p) do
    index = round(p * (length(sorted_list) - 1))
    Enum.at(sorted_list, index)
  end
  
  defp cleanup_old_metrics do
    # Remove metrics older than retention period
    cutoff = System.system_time(:microsecond) - (@history_retention * 1_000_000)
    
    :ets.tab2list(@table_name)
    |> Enum.filter(fn {_key, data} ->
      is_map(data) and Map.get(data, :timestamp, 0) < cutoff
    end)
    |> Enum.each(fn {key, _data} ->
      :ets.delete(@table_name, key)
    end)
  end
  
  defp cleanup_old_history do
    cutoff = System.system_time(:microsecond) - (@history_retention * 1_000_000)
    
    :ets.select_delete(:tool_execution_history, [
      {{{:"$1", :"$2", :"$3"}, :"$4"},
       [{:<, :"$1", cutoff}],
       [true]}
    ])
  end
  
  defp schedule_metrics_aggregation do
    Process.send_after(self(), :aggregate_metrics, @metrics_interval)
  end
  
  defp schedule_history_cleanup do
    Process.send_after(self(), :cleanup_history, @metrics_interval * 10) # Every 10 minutes
  end
end