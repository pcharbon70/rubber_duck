defmodule RubberDuck.EventMonitoring do
  @moduledoc """
  Comprehensive event monitoring and metrics collection for the distributed system.
  
  This GenServer provides:
  - Real-time event stream monitoring
  - Metrics aggregation and analysis  
  - Event pattern detection and alerting
  - System health monitoring based on events
  - Performance analytics and reporting
  - SLA compliance tracking
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.{EventSchemas}
  alias RubberDuck.EventBroadcasting.EventBroadcaster
  
  @type metric_window :: :minute | :hour | :day
  @type alert_level :: :info | :warning | :critical
  
  @type monitoring_config :: %{
    enabled_patterns: [String.t()],
    alert_thresholds: map(),
    metric_windows: [metric_window()],
    retention_days: non_neg_integer()
  }
  
  # Monitoring intervals
  @metrics_aggregation_interval :timer.minutes(1)
  @health_check_interval :timer.minutes(5)
  @cleanup_interval :timer.hours(6)
  
  # Alert thresholds (per minute)
  @default_thresholds %{
    error_rate: 0.05,          # 5% error rate
    high_latency_ms: 5000,     # 5 second latency
    event_volume: 1000,        # 1000 events per minute
    health_issues: 3           # 3 health issues per minute
  }
  
  # Client API
  
  @doc """
  Start the EventMonitoring GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Get current monitoring metrics.
  """
  def get_metrics(window \\ :minute) do
    GenServer.call(__MODULE__, {:get_metrics, window})
  end
  
  @doc """
  Get system health status based on events.
  """
  def get_health_status do
    GenServer.call(__MODULE__, :get_health_status)
  end
  
  @doc """
  Get active alerts.
  """
  def get_active_alerts do
    GenServer.call(__MODULE__, :get_active_alerts)
  end
  
  @doc """
  Get event statistics by topic pattern.
  """
  def get_topic_stats(topic_pattern, window \\ :minute) do
    GenServer.call(__MODULE__, {:get_topic_stats, topic_pattern, window})
  end
  
  @doc """
  Get performance analytics.
  """
  def get_performance_analytics(opts \\ []) do
    GenServer.call(__MODULE__, {:get_performance_analytics, opts})
  end
  
  @doc """
  Subscribe to monitoring alerts.
  """
  def subscribe_to_alerts(alert_level \\ :warning) do
    GenServer.call(__MODULE__, {:subscribe_alerts, self(), alert_level})
  end
  
  @doc """
  Update monitoring configuration.
  """
  def update_config(config_updates) do
    GenServer.call(__MODULE__, {:update_config, config_updates})
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    # Subscribe to all events for monitoring
    EventBroadcaster.subscribe("*", ack_required: false)
    
    # Schedule periodic tasks
    schedule_metrics_aggregation()
    schedule_health_check()
    schedule_cleanup()
    
    state = %{
      config: build_config(opts),
      metrics: %{
        minute: init_metrics_window(),
        hour: init_metrics_window(),
        day: init_metrics_window()
      },
      alerts: %{},
      alert_subscribers: %{},
      health_status: %{
        overall: :healthy,
        components: %{},
        last_check: DateTime.utc_now()
      },
      event_buffer: :queue.new(),
      performance_data: %{
        latency_buckets: init_latency_buckets(),
        error_patterns: %{},
        throughput_history: []
      }
    }
    
    Logger.info("EventMonitoring started with config: #{inspect(state.config)}")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:get_metrics, window}, _from, state) do
    metrics = Map.get(state.metrics, window, %{})
    {:reply, metrics, state}
  end
  
  @impl true
  def handle_call(:get_health_status, _from, state) do
    {:reply, state.health_status, state}
  end
  
  @impl true
  def handle_call(:get_active_alerts, _from, state) do
    active_alerts = state.alerts
    |> Enum.filter(fn {_id, alert} -> alert.status == :active end)
    |> Map.new()
    
    {:reply, active_alerts, state}
  end
  
  @impl true
  def handle_call({:get_topic_stats, topic_pattern, window}, _from, state) do
    window_metrics = Map.get(state.metrics, window, %{})
    topic_stats = window_metrics
    |> Map.get(:by_topic, %{})
    |> Enum.filter(fn {topic, _stats} -> 
      topic_matches?(topic, topic_pattern)
    end)
    |> Map.new()
    
    {:reply, topic_stats, state}
  end
  
  @impl true
  def handle_call({:get_performance_analytics, opts}, _from, state) do
    analytics = build_performance_analytics(state.performance_data, opts)
    {:reply, analytics, state}
  end
  
  @impl true
  def handle_call({:subscribe_alerts, subscriber, level}, _from, state) do
    monitor_ref = Process.monitor(subscriber)
    subscription = %{
      subscriber: subscriber,
      level: level,
      monitor_ref: monitor_ref
    }
    
    updated_subscribers = Map.put(state.alert_subscribers, subscriber, subscription)
    {:reply, :ok, %{state | alert_subscribers: updated_subscribers}}
  end
  
  @impl true
  def handle_call({:update_config, config_updates}, _from, state) do
    updated_config = Map.merge(state.config, config_updates)
    Logger.info("Updated monitoring config: #{inspect(config_updates)}")
    {:reply, :ok, %{state | config: updated_config}}
  end
  
  @impl true
  def handle_cast({:process_event_batch, events}, state) do
    updated_state = Enum.reduce(events, state, fn event, acc_state ->
      process_single_event(event, acc_state)
    end)
    
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info({:event, event}, state) do
    # Buffer events for batch processing
    updated_buffer = :queue.in(event, state.event_buffer)
    
    # Process immediately if buffer is full or for critical events
    if :queue.len(updated_buffer) >= 50 or event.priority == :critical do
      events = :queue.to_list(updated_buffer)
      GenServer.cast(self(), {:process_event_batch, events})
      {:noreply, %{state | event_buffer: :queue.new()}}
    else
      {:noreply, %{state | event_buffer: updated_buffer}}
    end
  end
  
  @impl true
  def handle_info(:aggregate_metrics, state) do
    updated_state = aggregate_metrics(state)
    schedule_metrics_aggregation()
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info(:health_check, state) do
    updated_state = perform_health_check(state)
    schedule_health_check()
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info(:cleanup_old_data, state) do
    updated_state = cleanup_old_monitoring_data(state)
    schedule_cleanup()
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info(:flush_event_buffer, state) do
    # Process any remaining buffered events
    if not :queue.is_empty(state.event_buffer) do
      events = :queue.to_list(state.event_buffer)
      GenServer.cast(self(), {:process_event_batch, events})
      {:noreply, %{state | event_buffer: :queue.new()}}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove dead alert subscribers
    updated_subscribers = Map.delete(state.alert_subscribers, pid)
    {:noreply, %{state | alert_subscribers: updated_subscribers}}
  end
  
  @impl true
  def terminate(_reason, state) do
    # Process any remaining buffered events
    if not :queue.is_empty(state.event_buffer) do
      events = :queue.to_list(state.event_buffer)
      Enum.each(events, fn event -> process_single_event(event, state) end)
    end
    :ok
  end
  
  # Private Functions
  
  defp build_config(opts) do
    %{
      enabled_patterns: Keyword.get(opts, :enabled_patterns, ["*"]),
      alert_thresholds: Keyword.get(opts, :alert_thresholds, @default_thresholds),
      metric_windows: Keyword.get(opts, :metric_windows, [:minute, :hour, :day]),
      retention_days: Keyword.get(opts, :retention_days, 7)
    }
  end
  
  defp init_metrics_window do
    %{
      total_events: 0,
      by_topic: %{},
      by_priority: %{low: 0, normal: 0, high: 0, critical: 0},
      by_node: %{},
      error_count: 0,
      success_count: 0,
      avg_latency: 0,
      start_time: System.monotonic_time(:millisecond)
    }
  end
  
  defp init_latency_buckets do
    %{
      "0-100ms" => 0,
      "100-500ms" => 0,
      "500ms-1s" => 0,
      "1s-5s" => 0,
      "5s+" => 0
    }
  end
  
  defp process_single_event(event, state) do
    # Update metrics for all configured windows
    updated_metrics = Enum.reduce(state.config.metric_windows, state.metrics, fn window, acc_metrics ->
      Map.update!(acc_metrics, window, fn window_metrics ->
        update_window_metrics(window_metrics, event)
      end)
    end)
    
    # Update performance data
    updated_performance = update_performance_data(state.performance_data, event)
    
    # Check for alerts
    {updated_alerts, new_alerts} = check_event_alerts(event, state.alerts, state.config.alert_thresholds)
    
    # Notify alert subscribers
    if not Enum.empty?(new_alerts) do
      notify_alert_subscribers(new_alerts, state.alert_subscribers)
    end
    
    %{state | 
      metrics: updated_metrics,
      performance_data: updated_performance,
      alerts: updated_alerts
    }
  end
  
  defp update_window_metrics(window_metrics, event) do
    %{window_metrics |
      total_events: window_metrics.total_events + 1,
      by_topic: update_topic_metrics(window_metrics.by_topic, event),
      by_priority: update_priority_metrics(window_metrics.by_priority, event),
      by_node: update_node_metrics(window_metrics.by_node, event)
    }
    |> update_error_success_metrics(event)
    |> update_latency_metrics(event)
  end
  
  defp update_topic_metrics(by_topic, event) do
    Map.update(by_topic, event.topic, %{count: 1, last_seen: event.timestamp}, fn stats ->
      %{stats | count: stats.count + 1, last_seen: event.timestamp}
    end)
  end
  
  defp update_priority_metrics(by_priority, event) do
    Map.update!(by_priority, event.priority, &(&1 + 1))
  end
  
  defp update_node_metrics(by_node, event) do
    node_name = event.source_node
    Map.update(by_node, node_name, %{count: 1, last_seen: event.timestamp}, fn stats ->
      %{stats | count: stats.count + 1, last_seen: event.timestamp}
    end)
  end
  
  defp update_error_success_metrics(window_metrics, event) do
    cond do
      is_error_event?(event) ->
        %{window_metrics | error_count: window_metrics.error_count + 1}
      is_success_event?(event) ->
        %{window_metrics | success_count: window_metrics.success_count + 1}
      true ->
        window_metrics
    end
  end
  
  defp update_latency_metrics(window_metrics, event) do
    case extract_latency_from_event(event) do
      nil -> window_metrics
      latency_ms ->
        current_avg = window_metrics.avg_latency
        total_events = window_metrics.total_events
        new_avg = if total_events > 1 do
          (current_avg * (total_events - 1) + latency_ms) / total_events
        else
          latency_ms
        end
        %{window_metrics | avg_latency: new_avg}
    end
  end
  
  defp update_performance_data(performance_data, event) do
    updated_buckets = case extract_latency_from_event(event) do
      nil -> performance_data.latency_buckets
      latency_ms -> update_latency_bucket(performance_data.latency_buckets, latency_ms)
    end
    
    updated_patterns = if is_error_event?(event) do
      pattern = extract_error_pattern(event)
      Map.update(performance_data.error_patterns, pattern, 1, &(&1 + 1))
    else
      performance_data.error_patterns
    end
    
    %{performance_data |
      latency_buckets: updated_buckets,
      error_patterns: updated_patterns
    }
  end
  
  defp update_latency_bucket(buckets, latency_ms) do
    bucket = cond do
      latency_ms < 100 -> "0-100ms"
      latency_ms < 500 -> "100-500ms"
      latency_ms < 1000 -> "500ms-1s"
      latency_ms < 5000 -> "1s-5s"
      true -> "5s+"
    end
    
    Map.update!(buckets, bucket, &(&1 + 1))
  end
  
  defp check_event_alerts(event, current_alerts, thresholds) do
    new_alerts = []
    
    # Check for high latency
    new_alerts = case extract_latency_from_event(event) do
      nil -> new_alerts
      latency_ms when latency_ms > thresholds.high_latency_ms ->
        alert = create_alert(:high_latency, event, %{latency_ms: latency_ms, threshold: thresholds.high_latency_ms})
        [alert | new_alerts]
      _ -> new_alerts
    end
    
    # Check for health issues
    new_alerts = if is_health_issue_event?(event) do
      alert = create_alert(:health_issue, event, %{component: extract_component_from_event(event)})
      [alert | new_alerts]
    else
      new_alerts
    end
    
    # Check for error patterns
    new_alerts = if is_error_event?(event) do
      error_pattern = extract_error_pattern(event)
      alert = create_alert(:error_pattern, event, %{pattern: error_pattern})
      [alert | new_alerts]
    else
      new_alerts
    end
    
    # Add new alerts to current alerts
    updated_alerts = Enum.reduce(new_alerts, current_alerts, fn alert, acc ->
      Map.put(acc, alert.id, alert)
    end)
    
    {updated_alerts, new_alerts}
  end
  
  defp create_alert(type, event, details) do
    %{
      id: generate_alert_id(),
      type: type,
      level: determine_alert_level(type, event),
      message: build_alert_message(type, event, details),
      details: details,
      event_id: event.id,
      topic: event.topic,
      source_node: event.source_node,
      created_at: DateTime.utc_now(),
      status: :active
    }
  end
  
  defp determine_alert_level(:high_latency, _event), do: :warning
  defp determine_alert_level(:health_issue, event) do
    if event.priority == :critical, do: :critical, else: :warning
  end
  defp determine_alert_level(:error_pattern, _event), do: :warning
  defp determine_alert_level(_, _), do: :info
  
  defp build_alert_message(:high_latency, event, %{latency_ms: latency, threshold: threshold}) do
    "High latency detected in #{event.topic}: #{latency}ms (threshold: #{threshold}ms)"
  end
  defp build_alert_message(:health_issue, event, %{component: component}) do
    "Health issue detected in #{component}: #{event.topic}"
  end
  defp build_alert_message(:error_pattern, event, %{pattern: pattern}) do
    "Error pattern detected: #{pattern} in #{event.topic}"
  end
  
  defp notify_alert_subscribers(alerts, subscribers) do
    Enum.each(alerts, fn alert ->
      Enum.each(subscribers, fn {pid, subscription} ->
        if should_notify_subscriber?(alert, subscription) do
          send(pid, {:monitoring_alert, alert})
        end
      end)
    end)
  end
  
  defp should_notify_subscriber?(alert, subscription) do
    alert_level_priority = get_level_priority(alert.level)
    subscription_level_priority = get_level_priority(subscription.level)
    alert_level_priority >= subscription_level_priority
  end
  
  defp get_level_priority(:info), do: 1
  defp get_level_priority(:warning), do: 2
  defp get_level_priority(:critical), do: 3
  
  defp aggregate_metrics(state) do
    # This could implement more sophisticated aggregation logic
    # For now, we'll just mark the aggregation time
    current_time = System.monotonic_time(:millisecond)
    
    updated_metrics = Enum.reduce(state.metrics, %{}, fn {window, metrics}, acc ->
      aggregated_metrics = Map.put(metrics, :last_aggregation, current_time)
      Map.put(acc, window, aggregated_metrics)
    end)
    
    %{state | metrics: updated_metrics}
  end
  
  defp perform_health_check(state) do
    # Analyze recent events to determine system health
    minute_metrics = Map.get(state.metrics, :minute, %{})
    
    overall_health = cond do
      minute_metrics.error_count > 50 -> :unhealthy
      minute_metrics.error_count > 10 -> :degraded
      true -> :healthy
    end
    
    component_health = analyze_component_health(minute_metrics)
    
    updated_health = %{
      overall: overall_health,
      components: component_health,
      last_check: DateTime.utc_now()
    }
    
    %{state | health_status: updated_health}
  end
  
  defp analyze_component_health(metrics) do
    # Analyze health by topic patterns to determine component health
    %{
      context_manager: analyze_topic_health(metrics, "context.*"),
      model_coordinator: analyze_topic_health(metrics, "model.*"),
      provider_system: analyze_topic_health(metrics, "provider.*"),
      cluster_coordination: analyze_topic_health(metrics, "cluster.*")
    }
  end
  
  defp analyze_topic_health(metrics, topic_pattern) do
    topic_stats = metrics
    |> Map.get(:by_topic, %{})
    |> Enum.filter(fn {topic, _stats} -> topic_matches?(topic, topic_pattern) end)
    
    if Enum.empty?(topic_stats) do
      :unknown
    else
      error_count = count_error_events_in_topics(topic_stats)
      total_count = Enum.sum(Enum.map(topic_stats, fn {_topic, stats} -> stats.count end))
      
      error_rate = if total_count > 0, do: error_count / total_count, else: 0
      
      cond do
        error_rate > 0.1 -> :unhealthy
        error_rate > 0.05 -> :degraded
        true -> :healthy
      end
    end
  end
  
  defp cleanup_old_monitoring_data(state) do
    # Clean up old alerts and metrics based on retention policy
    cutoff_time = DateTime.add(DateTime.utc_now(), -state.config.retention_days, :day)
    
    cleaned_alerts = state.alerts
    |> Enum.reject(fn {_id, alert} -> 
      DateTime.compare(alert.created_at, cutoff_time) == :lt
    end)
    |> Map.new()
    
    %{state | alerts: cleaned_alerts}
  end
  
  defp build_performance_analytics(performance_data, _opts) do
    %{
      latency_distribution: performance_data.latency_buckets,
      error_patterns: performance_data.error_patterns,
      top_error_patterns: performance_data.error_patterns
                         |> Enum.sort_by(fn {_pattern, count} -> count end, :desc)
                         |> Enum.take(10)
    }
  end
  
  # Event Analysis Helpers
  
  defp is_error_event?(event) do
    event.topic =~ ~r/\.(error|failed|unhealthy)/ or 
    event.priority == :critical or
    (is_map(event.payload) and Map.get(event.payload, :status) in [:failed, :error])
  end
  
  defp is_success_event?(event) do
    event.topic =~ ~r/\.(success|completed|healthy)/ or
    (is_map(event.payload) and Map.get(event.payload, :status) in [:success, :completed])
  end
  
  defp is_health_issue_event?(event) do
    event.topic =~ ~r/\.(health|status)\./ and
    (event.priority in [:high, :critical] or 
     (is_map(event.payload) and Map.get(event.payload, :health_status) in [:degraded, :unhealthy]))
  end
  
  defp extract_latency_from_event(event) do
    cond do
      is_map(event.payload) ->
        Map.get(event.payload, :duration_ms) || 
        Map.get(event.payload, :latency_ms) ||
        Map.get(event.payload, :response_time_ms)
      true -> nil
    end
  end
  
  defp extract_component_from_event(event) do
    event.metadata[:component] || 
    String.split(event.topic, ".") |> List.first() ||
    "unknown"
  end
  
  defp extract_error_pattern(event) do
    cond do
      is_map(event.payload) and Map.has_key?(event.payload, :error_details) ->
        "#{event.topic}:#{inspect(event.payload.error_details)}"
      is_map(event.payload) and Map.has_key?(event.payload, :reason) ->
        "#{event.topic}:#{event.payload.reason}"
      true ->
        event.topic
    end
  end
  
  defp count_error_events_in_topics(topic_stats) do
    topic_stats
    |> Enum.filter(fn {topic, _stats} -> 
      topic =~ ~r/\.(error|failed|unhealthy)/
    end)
    |> Enum.sum(fn {_topic, stats} -> stats.count end)
  end
  
  defp topic_matches?(topic, pattern) do
    # Simple wildcard matching
    regex_pattern = pattern
    |> String.replace("*", ".*")
    |> then(&"^#{&1}$")
    
    String.match?(topic, Regex.compile!(regex_pattern))
  end
  
  defp generate_alert_id do
    System.unique_integer([:positive, :monotonic])
    |> Integer.to_string()
  end
  
  defp schedule_metrics_aggregation do
    Process.send_after(self(), :aggregate_metrics, @metrics_aggregation_interval)
  end
  
  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_old_data, @cleanup_interval)
  end
end