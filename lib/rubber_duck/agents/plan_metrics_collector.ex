defmodule RubberDuck.Agents.PlanMetricsCollector do
  @moduledoc """
  Comprehensive metrics collection and analysis for plan management.
  
  This module provides:
  - Real-time metrics collection via telemetry
  - Performance tracking and trend analysis
  - Resource utilization monitoring
  - Success/failure rate calculations
  - Custom metric definitions
  - Alerting and threshold monitoring
  """
  
  use GenServer
  require Logger
  
  # Metric types (commented out - not currently used)
  # @metric_types %{
  #   counter: %{aggregation: :sum, reset: :never},
  #   gauge: %{aggregation: :last, reset: :never},
  #   histogram: %{aggregation: :distribution, reset: :interval},
  #   summary: %{aggregation: :percentiles, reset: :interval},
  #   rate: %{aggregation: :per_second, reset: :interval}
  # }
  
  # Default metrics to track
  @default_metrics [
    # Plan lifecycle metrics
    {:counter, [:plan, :created], "Total plans created"},
    {:counter, [:plan, :completed], "Total plans completed"},
    {:counter, [:plan, :failed], "Total plans failed"},
    {:gauge, [:plan, :active], "Currently active plans"},
    {:gauge, [:plan, :queued], "Plans waiting to start"},
    
    # Performance metrics
    {:histogram, [:plan, :duration], "Plan execution duration", unit: :millisecond},
    {:histogram, [:plan, :creation_time], "Plan creation time", unit: :millisecond},
    {:rate, [:plan, :creation_rate], "Plans created per second"},
    {:summary, [:plan, :phase_duration], "Phase execution duration", unit: :millisecond},
    
    # State transition metrics
    {:counter, [:plan, :transitions], "Total state transitions"},
    {:histogram, [:plan, :transition_time], "State transition duration", unit: :microsecond},
    {:counter, [:plan, :rollbacks], "Total plan rollbacks"},
    
    # Resource metrics
    {:gauge, [:plan, :memory_usage], "Memory used by plans", unit: :byte},
    {:gauge, [:plan, :lock_count], "Active plan locks"},
    {:histogram, [:plan, :lock_wait_time], "Lock acquisition wait time", unit: :millisecond},
    
    # Query metrics
    {:counter, [:plan, :queries], "Total plan queries executed"},
    {:histogram, [:plan, :query_time], "Query execution time", unit: :millisecond},
    {:counter, [:plan, :cache_hits], "Query cache hits"},
    {:counter, [:plan, :cache_misses], "Query cache misses"},
    
    # Error metrics
    {:counter, [:plan, :errors], "Total plan errors"},
    {:counter, [:plan, :validation_failures], "Plan validation failures"},
    {:counter, [:plan, :timeout_errors], "Plan timeout errors"}
  ]
  
  # Metric aggregation intervals
  @aggregation_intervals %{
    realtime: :timer.seconds(1),
    minute: :timer.minutes(1),
    hour: :timer.hours(1),
    day: :timer.hours(24)
  }
  
  # Alert thresholds
  @default_thresholds %{
    plan_failure_rate: %{max: 0.1, window: :timer.minutes(5)},
    active_plans: %{max: 1000},
    creation_rate: %{max: 100, window: :timer.seconds(1)},
    query_time_p99: %{max: 1000, window: :timer.minutes(1)},
    lock_wait_time_p95: %{max: 5000, window: :timer.minutes(5)}
  }
  
  ## Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Records a metric value.
  """
  def record(metric_name, value, tags \\ %{}) do
    GenServer.cast(__MODULE__, {:record, metric_name, value, tags, System.monotonic_time()})
  end
  
  @doc """
  Increments a counter metric.
  """
  def increment(metric_name, tags \\ %{}, amount \\ 1) do
    record(metric_name, amount, tags)
  end
  
  @doc """
  Sets a gauge metric.
  """
  def gauge(metric_name, value, tags \\ %{}) do
    record(metric_name, value, tags)
  end
  
  @doc """
  Records a timing metric.
  """
  def timing(metric_name, duration, tags \\ %{}) do
    record(metric_name, duration, tags)
  end
  
  @doc """
  Times a function execution and records the duration.
  """
  def time(metric_name, tags \\ %{}, fun) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      result = fun.()
      duration = System.monotonic_time(:millisecond) - start_time
      timing(metric_name, duration, tags)
      result
    rescue
      e ->
        duration = System.monotonic_time(:millisecond) - start_time
        timing(metric_name, duration, Map.put(tags, :error, true))
        reraise e, __STACKTRACE__
    end
  end
  
  @doc """
  Gets current metric values.
  """
  def get_metrics(filters \\ %{}) do
    GenServer.call(__MODULE__, {:get_metrics, filters})
  end
  
  @doc """
  Gets metric trends over time.
  """
  def get_trends(metric_name, time_range, opts \\ []) do
    GenServer.call(__MODULE__, {:get_trends, metric_name, time_range, opts})
  end
  
  @doc """
  Registers a custom metric.
  """
  def register_metric(name, type, description, opts \\ []) do
    GenServer.call(__MODULE__, {:register_metric, name, type, description, opts})
  end
  
  @doc """
  Sets an alert threshold.
  """
  def set_threshold(metric_name, threshold_spec) do
    GenServer.call(__MODULE__, {:set_threshold, metric_name, threshold_spec})
  end
  
  @doc """
  Gets a report of all metrics.
  """
  def generate_report(opts \\ []) do
    GenServer.call(__MODULE__, {:generate_report, opts})
  end
  
  ## Server Implementation
  
  @impl true
  def init(opts) do
    # Set up telemetry handlers
    setup_telemetry_handlers()
    
    # Initialize state
    state = %{
      metrics: %{},
      metric_definitions: build_metric_definitions(),
      thresholds: Map.merge(@default_thresholds, Keyword.get(opts, :thresholds, %{})),
      time_series: %{},
      alerts: %{},
      aggregation_timers: start_aggregation_timers(),
      start_time: System.monotonic_time(:millisecond)
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:record, metric_name, value, tags, timestamp}, state) do
    state = 
      state
      |> update_metric(metric_name, value, tags, timestamp)
      |> update_time_series(metric_name, value, tags, timestamp)
      |> check_thresholds(metric_name)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_call({:get_metrics, filters}, _from, state) do
    metrics = filter_metrics(state.metrics, filters)
    {:reply, {:ok, metrics}, state}
  end
  
  @impl true
  def handle_call({:get_trends, metric_name, time_range, opts}, _from, state) do
    trends = calculate_trends(state.time_series, metric_name, time_range, opts)
    {:reply, {:ok, trends}, state}
  end
  
  @impl true
  def handle_call({:register_metric, name, type, description, opts}, _from, state) do
    metric_def = %{
      name: name,
      type: type,
      description: description,
      unit: Keyword.get(opts, :unit),
      tags: Keyword.get(opts, :tags, [])
    }
    
    updated_definitions = Map.put(state.metric_definitions, name, metric_def)
    state = %{state | metric_definitions: updated_definitions}
    
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call({:set_threshold, metric_name, threshold_spec}, _from, state) do
    updated_thresholds = Map.put(state.thresholds, metric_name, threshold_spec)
    state = %{state | thresholds: updated_thresholds}
    
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call({:generate_report, opts}, _from, state) do
    report = build_report(state, opts)
    {:reply, {:ok, report}, state}
  end
  
  @impl true
  def handle_info({:aggregate, interval}, state) do
    state = perform_aggregation(state, interval)
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:cleanup_old_data}, state) do
    state = cleanup_time_series(state)
    schedule_cleanup()
    {:noreply, state}
  end
  
  ## Private Functions
  
  defp setup_telemetry_handlers do
    events = [
      # Plan events
      [:plan, :created],
      [:plan, :completed],
      [:plan, :failed],
      [:plan, :state, :transitioned],
      
      # Performance events
      [:plan, :execution, :start],
      [:plan, :execution, :stop],
      [:plan, :phase, :start],
      [:plan, :phase, :stop],
      
      # Query events
      [:plan, :query, :executed],
      [:plan, :cache, :hit],
      [:plan, :cache, :miss],
      
      # Lock events
      [:plan, :lock, :acquired],
      [:plan, :lock, :released],
      [:plan, :lock, :timeout],
      
      # Error events
      [:plan, :error, :raised],
      [:plan, :validation, :failed]
    ]
    
    Enum.each(events, fn event ->
      :telemetry.attach(
        "metrics_#{Enum.join(event, "_")}",
        event,
        &handle_telemetry_event/4,
        nil
      )
    end)
  end
  
  defp handle_telemetry_event(event, measurements, metadata, _config) do
    metric_name = event_to_metric_name(event)
    
    case determine_metric_type(event) do
      :counter ->
        increment(metric_name, metadata)
        
      :gauge ->
        value = Map.get(measurements, :value, 1)
        gauge(metric_name, value, metadata)
        
      :histogram ->
        duration = Map.get(measurements, :duration, 0)
        timing(metric_name, duration, metadata)
    end
  end
  
  defp event_to_metric_name(event) do
    Enum.join(event, ".")
  end
  
  defp determine_metric_type(event) do
    case List.last(event) do
      :created -> :counter
      :completed -> :counter
      :failed -> :counter
      :transitioned -> :counter
      :executed -> :counter
      :hit -> :counter
      :miss -> :counter
      :raised -> :counter
      :start -> :histogram
      :stop -> :histogram
      :acquired -> :histogram
      :released -> :histogram
      _ -> :gauge
    end
  end
  
  defp build_metric_definitions do
    @default_metrics
    |> Enum.map(fn
      {type, name, description} ->
        {name, %{type: type, name: name, description: description}}
        
      {type, name, description, opts} ->
        {name, Map.merge(%{type: type, name: name, description: description}, opts)}
    end)
    |> Enum.into(%{})
  end
  
  defp start_aggregation_timers do
    Enum.map(@aggregation_intervals, fn {name, interval} ->
      timer_ref = Process.send_after(self(), {:aggregate, name}, interval)
      {name, timer_ref}
    end)
    |> Enum.into(%{})
  end
  
  defp update_metric(state, metric_name, value, tags, timestamp) do
    metric_key = {metric_name, tags}
    metric_def = Map.get(state.metric_definitions, metric_name, %{type: :gauge})
    
    current_metric = Map.get(state.metrics, metric_key, %{
      name: metric_name,
      tags: tags,
      type: metric_def.type,
      values: []
    })
    
    updated_metric = update_metric_value(current_metric, value, timestamp)
    updated_metrics = Map.put(state.metrics, metric_key, updated_metric)
    
    %{state | metrics: updated_metrics}
  end
  
  defp update_metric_value(metric, value, timestamp) do
    case metric.type do
      :counter ->
        current_value = Map.get(metric, :value, 0)
        Map.put(metric, :value, current_value + value)
        
      :gauge ->
        Map.put(metric, :value, value)
        
      :histogram ->
        values = [value | Map.get(metric, :values, [])]
        metric
        |> Map.put(:values, Enum.take(values, 1000))
        |> calculate_histogram_stats()
        
      :summary ->
        values = [value | Map.get(metric, :values, [])]
        metric
        |> Map.put(:values, Enum.take(values, 1000))
        |> calculate_summary_stats()
        
      :rate ->
        update_rate_metric(metric, value, timestamp)
    end
  end
  
  defp calculate_histogram_stats(metric) do
    values = metric.values
    
    if length(values) > 0 do
      sorted = Enum.sort(values)
      count = length(sorted)
      
      stats = %{
        min: List.first(sorted),
        max: List.last(sorted),
        mean: Enum.sum(sorted) / count,
        p50: percentile(sorted, 0.5),
        p95: percentile(sorted, 0.95),
        p99: percentile(sorted, 0.99),
        count: count
      }
      
      Map.put(metric, :stats, stats)
    else
      metric
    end
  end
  
  defp calculate_summary_stats(metric) do
    calculate_histogram_stats(metric)
  end
  
  defp update_rate_metric(metric, value, _timestamp) do
    window = :timer.seconds(60)
    now = System.monotonic_time(:millisecond)
    
    # Add new value with timestamp
    values = [{now, value} | Map.get(metric, :timed_values, [])]
    
    # Remove old values outside window
    cutoff = now - window
    recent_values = Enum.filter(values, fn {ts, _} -> ts > cutoff end)
    
    # Calculate rate
    total = recent_values |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    duration = if length(recent_values) > 1 do
      newest = recent_values |> List.first() |> elem(0)
      oldest = recent_values |> List.last() |> elem(0)
      max(newest - oldest, 1)
    else
      1
    end
    
    rate = total / (duration / 1000.0)
    
    metric
    |> Map.put(:timed_values, recent_values)
    |> Map.put(:value, rate)
  end
  
  defp percentile(sorted_values, p) do
    index = round(p * (length(sorted_values) - 1))
    Enum.at(sorted_values, index)
  end
  
  defp update_time_series(state, metric_name, value, tags, timestamp) do
    series_key = {metric_name, tags}
    series = Map.get(state.time_series, series_key, [])
    
    # Add new data point
    updated_series = [{timestamp, value} | series]
    |> Enum.take(1000) # Keep last 1000 points
    
    updated_time_series = Map.put(state.time_series, series_key, updated_series)
    %{state | time_series: updated_time_series}
  end
  
  defp check_thresholds(state, metric_name) do
    case Map.get(state.thresholds, metric_name) do
      nil -> state
      threshold -> check_metric_threshold(state, metric_name, threshold)
    end
  end
  
  defp check_metric_threshold(state, metric_name, threshold) do
    # Get metric value
    metric_value = get_metric_value(state, metric_name)
    
    # Check against threshold
    violation = cond do
      Map.has_key?(threshold, :max) and metric_value > threshold.max ->
        {:max_exceeded, metric_value, threshold.max}
        
      Map.has_key?(threshold, :min) and metric_value < threshold.min ->
        {:min_exceeded, metric_value, threshold.min}
        
      true -> nil
    end
    
    if violation do
      handle_threshold_violation(state, metric_name, violation)
    else
      state
    end
  end
  
  defp get_metric_value(state, metric_name) do
    state.metrics
    |> Enum.find(fn {{name, _tags}, _metric} -> name == metric_name end)
    |> case do
      {_key, metric} -> Map.get(metric, :value, 0)
      nil -> 0
    end
  end
  
  defp handle_threshold_violation(state, metric_name, violation) do
    alert = %{
      metric: metric_name,
      violation: violation,
      timestamp: DateTime.utc_now(),
      id: generate_alert_id()
    }
    
    # Store alert
    updated_alerts = Map.put(state.alerts, alert.id, alert)
    
    # Emit alert event
    emit_alert(alert)
    
    %{state | alerts: updated_alerts}
  end
  
  defp emit_alert(alert) do
    :telemetry.execute(
      [:plan, :metrics, :alert],
      %{count: 1},
      alert
    )
    
    Logger.warning("Metric threshold violation: #{inspect(alert)}")
  end
  
  defp filter_metrics(metrics, filters) do
    metrics
    |> Enum.filter(fn {{name, tags}, _metric} ->
      matches_filters?(name, tags, filters)
    end)
    |> Enum.map(fn {_key, metric} -> metric end)
  end
  
  defp matches_filters?(name, tags, filters) do
    name_match = case Map.get(filters, :name) do
      nil -> true
      filter_name -> name == filter_name
    end
    
    tag_match = case Map.get(filters, :tags) do
      nil -> true
      filter_tags ->
        Enum.all?(filter_tags, fn {k, v} ->
          Map.get(tags, k) == v
        end)
    end
    
    name_match and tag_match
  end
  
  defp calculate_trends(time_series, metric_name, time_range, opts) do
    resolution = Keyword.get(opts, :resolution, :minute)
    
    time_series
    |> Enum.filter(fn {{name, _tags}, _} -> name == metric_name end)
    |> Enum.map(fn {_key, series} ->
      aggregate_time_series(series, time_range, resolution)
    end)
  end
  
  defp aggregate_time_series(series, _time_range, _resolution) do
    # Group by time bucket and aggregate
    # Simplified implementation
    series
  end
  
  defp perform_aggregation(state, interval) do
    # Perform interval-specific aggregations
    # Reset counters if needed
    # Calculate derived metrics
    
    # Reschedule timer
    timer_ref = Process.send_after(self(), {:aggregate, interval}, @aggregation_intervals[interval])
    updated_timers = Map.put(state.aggregation_timers, interval, timer_ref)
    
    %{state | aggregation_timers: updated_timers}
  end
  
  defp cleanup_time_series(state) do
    cutoff = System.monotonic_time(:millisecond) - :timer.hours(24)
    
    updated_time_series = state.time_series
    |> Enum.map(fn {key, series} ->
      cleaned = Enum.filter(series, fn {ts, _} -> ts > cutoff end)
      {key, cleaned}
    end)
    |> Enum.into(%{})
    
    %{state | time_series: updated_time_series}
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), {:cleanup_old_data}, :timer.hours(1))
  end
  
  defp build_report(state, opts) do
    include_time_series = Keyword.get(opts, :include_time_series, false)
    
    %{
      summary: build_summary(state),
      metrics: format_metrics(state.metrics),
      alerts: format_alerts(state.alerts),
      trends: if include_time_series do
        build_trend_summary(state.time_series)
      else
        nil
      end,
      uptime: System.monotonic_time(:millisecond) - state.start_time,
      generated_at: DateTime.utc_now()
    }
  end
  
  defp build_summary(state) do
    %{
      total_metrics: map_size(state.metrics),
      active_alerts: map_size(state.alerts),
      metric_types: count_by_type(state.metrics),
      collection_rate: calculate_collection_rate(state)
    }
  end
  
  defp format_metrics(metrics) do
    Enum.map(metrics, fn {_key, metric} ->
      Map.take(metric, [:name, :type, :value, :stats, :tags])
    end)
  end
  
  defp format_alerts(alerts) do
    alerts
    |> Map.values()
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end
  
  defp build_trend_summary(time_series) do
    # Build summary of trends
    %{series_count: map_size(time_series)}
  end
  
  defp count_by_type(metrics) do
    metrics
    |> Enum.group_by(fn {_, m} -> m.type end)
    |> Enum.map(fn {type, list} -> {type, length(list)} end)
    |> Enum.into(%{})
  end
  
  defp calculate_collection_rate(_state) do
    # Calculate metrics collection rate
    0.0
  end
  
  defp generate_alert_id do
    "alert_#{:erlang.unique_integer([:positive, :monotonic])}"
  end
end