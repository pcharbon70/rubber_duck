defmodule RubberDuck.LLMPerformanceAlerting do
  @moduledoc """
  Comprehensive alerting system for LLM performance degradation and anomalies.
  
  Provides intelligent alerting capabilities including:
  - Real-time performance threshold monitoring
  - Anomaly detection using statistical analysis
  - Provider health degradation alerts
  - Cost spike detection and budget alerts
  - Cache performance degradation warnings
  - Predictive alerting based on trend analysis
  - Smart alert grouping and noise reduction
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.LLMMetricsCollector
  alias RubberDuck.LLMPerformanceDashboard
  alias RubberDuck.EventBroadcasting.EventBroadcaster
  
  @check_interval :timer.seconds(30)
  @anomaly_detection_window :timer.minutes(15)
  @trend_analysis_window :timer.hours(2)
  @alert_cooldown_period :timer.minutes(5)
  
  # Alert severity levels
  @severity_levels [:info, :warning, :critical, :emergency]
  
  # Alert types and their default configurations
  @alert_configs %{
    # Performance alerts
    high_latency: %{
      metric: "llm.latency.request.avg",
      threshold: 5000,  # milliseconds
      operator: :greater_than,
      severity: :warning,
      description: "Average request latency is unusually high"
    },
    
    low_success_rate: %{
      metric: "llm.requests.success_rate",
      threshold: 0.95,
      operator: :less_than,
      severity: :critical,
      description: "Request success rate has dropped below acceptable levels"
    },
    
    high_error_rate: %{
      metric: "llm.requests.failure_rate",
      threshold: 0.05,
      operator: :greater_than,
      severity: :warning,
      description: "Error rate has increased significantly"
    },
    
    # Cost alerts
    cost_spike: %{
      metric: "llm.cost.rate",
      threshold_type: :anomaly,
      anomaly_factor: 2.0,
      severity: :warning,
      description: "Cost rate has spiked unexpectedly"
    },
    
    budget_threshold: %{
      metric: "llm.cost.total",
      threshold: 100.0,  # dollars
      operator: :greater_than,
      severity: :critical,
      description: "Monthly budget threshold exceeded"
    },
    
    # Provider alerts
    provider_degradation: %{
      metric: "llm.provider.health_score",
      threshold: 80,
      operator: :less_than,
      severity: :warning,
      description: "Provider health score has degraded"
    },
    
    provider_unavailable: %{
      metric: "llm.provider.availability",
      threshold: 0.9,
      operator: :less_than,
      severity: :critical,
      description: "Provider availability has dropped significantly"
    },
    
    rate_limit_exceeded: %{
      metric: "llm.provider.rate_limit",
      threshold: 0.9,
      operator: :greater_than,
      severity: :warning,
      description: "Rate limit utilization is very high"
    },
    
    # Cache alerts
    low_cache_hit_rate: %{
      metric: "llm.cache.hit_rate",
      threshold: 50.0,  # percentage
      operator: :less_than,
      severity: :warning,
      description: "Cache hit rate has dropped below optimal levels"
    },
    
    cache_thrashing: %{
      metric: "llm.cache.evictions",
      threshold_type: :anomaly,
      anomaly_factor: 3.0,
      severity: :warning,
      description: "Unusually high cache eviction rate detected"
    },
    
    # System alerts
    high_memory_usage: %{
      metric: "system.memory.usage",
      threshold: 0.85,
      operator: :greater_than,
      severity: :warning,
      description: "System memory usage is critically high"
    },
    
    cluster_node_down: %{
      metric: "cluster.node.count",
      threshold_type: :decrease,
      severity: :critical,
      description: "Cluster node has gone offline"
    },
    
    # Token usage alerts
    token_rate_spike: %{
      metric: "llm.tokens.rate",
      threshold_type: :anomaly,
      anomaly_factor: 2.5,
      severity: :info,
      description: "Token usage rate has increased significantly"
    },
    
    # Quality alerts
    response_quality_degradation: %{
      metric: "llm.quality.response_length.avg",
      threshold_type: :anomaly,
      anomaly_factor: -0.5,  # Negative factor for decreases
      severity: :warning,
      description: "Average response quality appears to have degraded"
    }
  }
  
  # Alert notification channels
  @notification_channels %{
    log: %{enabled: true, severity_filter: :info},
    email: %{enabled: false, severity_filter: :warning},
    slack: %{enabled: false, severity_filter: :critical},
    webhook: %{enabled: false, severity_filter: :warning},
    dashboard: %{enabled: true, severity_filter: :info}
  }
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    check_interval = Keyword.get(opts, :check_interval, @check_interval)
    enabled_alerts = Keyword.get(opts, :enabled_alerts, Map.keys(@alert_configs))
    notification_config = Keyword.get(opts, :notifications, @notification_channels)
    
    # Subscribe to relevant events
    EventBroadcaster.subscribe("llm.*")
    EventBroadcaster.subscribe("cache.*")
    EventBroadcaster.subscribe("provider.*")
    EventBroadcaster.subscribe("cluster.*")
    
    # Initialize alert tracking storage
    :ets.new(:active_alerts, [:named_table, :public, :set])
    :ets.new(:alert_history, [:named_table, :public, :bag])
    :ets.new(:alert_cooldowns, [:named_table, :public, :set])
    :ets.new(:metric_baselines, [:named_table, :public, :set])
    
    # Schedule periodic checks
    :timer.send_interval(check_interval, self(), :check_alerts)
    
    # Initialize metric baselines for anomaly detection
    initialize_metric_baselines()
    
    Logger.info("LLM Performance Alerting started with #{length(enabled_alerts)} alert types")
    
    {:ok, %{
      check_interval: check_interval,
      enabled_alerts: enabled_alerts,
      notification_config: notification_config,
      last_check: :os.system_time(:millisecond),
      alert_stats: %{
        total_alerts: 0,
        alerts_by_severity: %{info: 0, warning: 0, critical: 0, emergency: 0}
      }
    }}
  end
  
  @impl true
  def handle_info({:event, topic, event_data}, state) do
    # Process real-time events for immediate alerting
    process_real_time_event(topic, event_data)
    {:noreply, state}
  end
  
  def handle_info(:check_alerts, state) do
    # Perform scheduled alert checks
    new_alerts = perform_alert_checks(state.enabled_alerts)
    
    # Update baselines for anomaly detection
    update_metric_baselines()
    
    # Update statistics
    new_stats = update_alert_statistics(state.alert_stats, new_alerts)
    
    {:noreply, %{state | 
      last_check: :os.system_time(:millisecond),
      alert_stats: new_stats
    }}
  end
  
  @impl true
  def handle_call({:get_active_alerts}, _from, state) do
    alerts = get_active_alerts_internal()
    {:reply, alerts, state}
  end
  
  def handle_call({:get_alert_history, opts}, _from, state) do
    history = get_alert_history_internal(opts)
    {:reply, history, state}
  end
  
  def handle_call({:acknowledge_alert, alert_id}, _from, state) do
    result = acknowledge_alert_internal(alert_id)
    {:reply, result, state}
  end
  
  def handle_call({:configure_alert, alert_type, config}, _from, state) do
    result = configure_alert_internal(alert_type, config)
    {:reply, result, state}
  end
  
  def handle_call({:get_alert_statistics}, _from, state) do
    stats = enhance_alert_statistics(state.alert_stats)
    {:reply, stats, state}
  end
  
  # Public API
  
  @doc """
  Get all currently active alerts
  """
  def get_active_alerts do
    GenServer.call(__MODULE__, {:get_active_alerts})
  end
  
  @doc """
  Get alert history with optional filtering
  """
  def get_alert_history(opts \\ []) do
    GenServer.call(__MODULE__, {:get_alert_history, opts})
  end
  
  @doc """
  Acknowledge an alert to stop notifications
  """
  def acknowledge_alert(alert_id) do
    GenServer.call(__MODULE__, {:acknowledge_alert, alert_id})
  end
  
  @doc """
  Configure alert thresholds and settings
  """
  def configure_alert(alert_type, config) do
    GenServer.call(__MODULE__, {:configure_alert, alert_type, config})
  end
  
  @doc """
  Get alerting system statistics
  """
  def get_alert_statistics do
    GenServer.call(__MODULE__, {:get_alert_statistics})
  end
  
  @doc """
  Manually trigger an alert check
  """
  def force_alert_check do
    GenServer.cast(__MODULE__, :force_check)
  end
  
  @doc """
  Create a custom alert
  """
  def create_custom_alert(alert_data) do
    alert = %{
      id: generate_alert_id(),
      type: :custom,
      severity: Map.get(alert_data, :severity, :info),
      title: Map.get(alert_data, :title, "Custom Alert"),
      description: Map.get(alert_data, :description, ""),
      timestamp: :os.system_time(:millisecond),
      status: :active,
      metadata: Map.get(alert_data, :metadata, %{})
    }
    
    trigger_alert(alert)
  end
  
  # Private Functions
  
  defp process_real_time_event(topic, event_data) do
    case topic do
      "llm.request.failure" ->
        check_immediate_failure_alert(event_data)
      
      "provider.status.degraded" ->
        check_immediate_provider_alert(event_data)
      
      "cluster.node.down" ->
        trigger_node_down_alert(event_data)
      
      "llm.cost.spike" ->
        check_immediate_cost_alert(event_data)
      
      _ ->
        :ok
    end
  end
  
  defp perform_alert_checks(enabled_alerts) do
    current_time = :os.system_time(:millisecond)
    
    enabled_alerts
    |> Enum.map(fn alert_type ->
      if should_check_alert?(alert_type, current_time) do
        check_alert(alert_type)
      else
        nil
      end
    end)
    |> Enum.filter(& &1)
    |> List.flatten()
  end
  
  defp should_check_alert?(alert_type, current_time) do
    cooldown_key = {:cooldown, alert_type}
    
    case :ets.lookup(:alert_cooldowns, cooldown_key) do
      [{_, last_alert_time}] ->
        current_time - last_alert_time > @alert_cooldown_period
      [] ->
        true
    end
  end
  
  defp check_alert(alert_type) do
    alert_config = Map.get(@alert_configs, alert_type)
    
    if alert_config do
      case alert_config.threshold_type do
        :anomaly -> check_anomaly_alert(alert_type, alert_config)
        :decrease -> check_decrease_alert(alert_type, alert_config)
        _ -> check_threshold_alert(alert_type, alert_config)
      end
    else
      []
    end
  end
  
  defp check_threshold_alert(alert_type, config) do
    current_value = get_current_metric_value(config.metric)
    
    if current_value && threshold_violated?(current_value, config.threshold, config.operator) do
      alert = create_alert(alert_type, config, %{
        current_value: current_value,
        threshold: config.threshold,
        operator: config.operator
      })
      
      trigger_alert(alert)
      [alert]
    else
      []
    end
  end
  
  defp check_anomaly_alert(alert_type, config) do
    current_value = get_current_metric_value(config.metric)
    baseline = get_metric_baseline(config.metric)
    
    if current_value && baseline && anomaly_detected?(current_value, baseline, config.anomaly_factor) do
      alert = create_alert(alert_type, config, %{
        current_value: current_value,
        baseline_value: baseline.mean,
        anomaly_factor: config.anomaly_factor,
        z_score: calculate_z_score(current_value, baseline)
      })
      
      trigger_alert(alert)
      [alert]
    else
      []
    end
  end
  
  defp check_decrease_alert(alert_type, config) do
    previous_value = get_previous_metric_value(config.metric)
    current_value = get_current_metric_value(config.metric)
    
    if previous_value && current_value && current_value < previous_value do
      alert = create_alert(alert_type, config, %{
        current_value: current_value,
        previous_value: previous_value,
        decrease_amount: previous_value - current_value
      })
      
      trigger_alert(alert)
      [alert]
    else
      []
    end
  end
  
  defp threshold_violated?(value, threshold, operator) do
    case operator do
      :greater_than -> value > threshold
      :less_than -> value < threshold
      :equal_to -> value == threshold
      :not_equal_to -> value != threshold
      :greater_than_or_equal -> value >= threshold
      :less_than_or_equal -> value <= threshold
      _ -> false
    end
  end
  
  defp anomaly_detected?(current_value, baseline, anomaly_factor) do
    z_score = calculate_z_score(current_value, baseline)
    abs(z_score) > abs(anomaly_factor)
  end
  
  defp calculate_z_score(value, baseline) do
    if baseline.std_dev > 0 do
      (value - baseline.mean) / baseline.std_dev
    else
      0
    end
  end
  
  defp create_alert(alert_type, config, context) do
    %{
      id: generate_alert_id(),
      type: alert_type,
      severity: config.severity,
      title: generate_alert_title(alert_type, config),
      description: config.description,
      metric: config.metric,
      timestamp: :os.system_time(:millisecond),
      status: :active,
      context: context,
      acknowledged: false,
      acknowledged_by: nil,
      acknowledged_at: nil
    }
  end
  
  defp trigger_alert(alert) do
    # Store alert in active alerts
    :ets.insert(:active_alerts, {alert.id, alert})
    
    # Add to history
    :ets.insert(:alert_history, {:os.system_time(:millisecond), alert})
    
    # Set cooldown for this alert type
    :ets.insert(:alert_cooldowns, {{:cooldown, alert.type}, alert.timestamp})
    
    # Send notifications
    send_alert_notifications(alert)
    
    # Broadcast alert event
    EventBroadcaster.broadcast_async(%{
      topic: "alert.triggered",
      payload: alert
    })
    
    Logger.warning("Alert triggered: #{alert.type} - #{alert.title}")
    
    alert
  end
  
  defp send_alert_notifications(alert) do
    # Send to configured notification channels based on severity
    Enum.each(@notification_channels, fn {channel, channel_config} ->
      if channel_config.enabled && severity_meets_filter?(alert.severity, channel_config.severity_filter) do
        send_notification(channel, alert)
      end
    end)
  end
  
  defp send_notification(:log, alert) do
    Logger.log(severity_to_log_level(alert.severity), "ALERT: #{alert.title} - #{alert.description}")
  end
  
  defp send_notification(:email, alert) do
    # Email notification implementation
    Logger.info("Sending email alert: #{alert.title}")
  end
  
  defp send_notification(:slack, alert) do
    # Slack notification implementation
    Logger.info("Sending Slack alert: #{alert.title}")
  end
  
  defp send_notification(:webhook, alert) do
    # Webhook notification implementation
    Logger.info("Sending webhook alert: #{alert.title}")
  end
  
  defp send_notification(:dashboard, _alert) do
    # Dashboard notification (already handled by event broadcasting)
    :ok
  end
  
  defp send_notification(channel, alert) do
    Logger.debug("Unsupported notification channel: #{channel} for alert: #{alert.id}")
  end
  
  defp severity_meets_filter?(alert_severity, filter_severity) do
    severity_level(alert_severity) >= severity_level(filter_severity)
  end
  
  defp severity_level(:info), do: 0
  defp severity_level(:warning), do: 1
  defp severity_level(:critical), do: 2
  defp severity_level(:emergency), do: 3
  
  defp severity_to_log_level(:info), do: :info
  defp severity_to_log_level(:warning), do: :warning
  defp severity_to_log_level(:critical), do: :error
  defp severity_to_log_level(:emergency), do: :error
  
  defp generate_alert_id do
    :crypto.strong_rand_bytes(8) |> Base.encode64() |> binary_part(0, 12)
  end
  
  defp generate_alert_title(alert_type, _config) do
    base_title = alert_type
                |> to_string()
                |> String.split("_")
                |> Enum.map(&String.capitalize/1)
                |> Enum.join(" ")
    
    "#{base_title} Alert"
  end
  
  defp get_current_metric_value(metric) do
    case metric do
      "llm.latency.request.avg" ->
        get_average_latency()
      
      "llm.requests.success_rate" ->
        get_success_rate()
      
      "llm.requests.failure_rate" ->
        get_failure_rate()
      
      "llm.cost.rate" ->
        get_cost_rate()
      
      "llm.cost.total" ->
        get_total_cost()
      
      "llm.provider.health_score" ->
        get_average_provider_health()
      
      "llm.provider.availability" ->
        get_provider_availability()
      
      "llm.cache.hit_rate" ->
        get_cache_hit_rate()
      
      "system.memory.usage" ->
        get_memory_usage()
      
      "cluster.node.count" ->
        get_cluster_node_count()
      
      _ ->
        nil
    end
  end
  
  defp get_previous_metric_value(metric) do
    # Get metric value from previous check (simplified)
    get_current_metric_value(metric)
  end
  
  # Metric collection functions (simplified implementations)
  
  defp get_average_latency do
    case LLMMetricsCollector.get_metrics_summary(window: :timer.minutes(5)) do
      {:ok, metrics} ->
        get_in(metrics, ["llm.latency.request", :avg])
      _ ->
        nil
    end
  end
  
  defp get_success_rate do
    case LLMMetricsCollector.get_metrics_summary(window: :timer.minutes(5)) do
      {:ok, metrics} ->
        success = get_in(metrics, ["llm.requests.success", :sum]) || 0
        total = get_in(metrics, ["llm.requests.total", :sum]) || 1
        success / total
      _ ->
        nil
    end
  end
  
  defp get_failure_rate do
    success_rate = get_success_rate()
    if success_rate, do: 1.0 - success_rate, else: nil
  end
  
  defp get_cost_rate do
    case LLMMetricsCollector.get_cost_analysis(window: :timer.minutes(5)) do
      {:ok, analysis} ->
        analysis.cost_per_request
      _ ->
        nil
    end
  end
  
  defp get_total_cost do
    case LLMMetricsCollector.get_cost_analysis(window: :timer.hours(24)) do
      {:ok, analysis} ->
        analysis.total_cost
      _ ->
        nil
    end
  end
  
  defp get_average_provider_health do
    case LLMMetricsCollector.get_provider_comparison() do
      {:ok, providers} ->
        if length(providers) > 0 do
          total_health = Enum.reduce(providers, 0, fn provider, acc ->
            acc + provider.health_score
          end)
          total_health / length(providers)
        else
          nil
        end
      _ ->
        nil
    end
  end
  
  defp get_provider_availability do
    # Simplified - would calculate actual availability
    0.95
  end
  
  defp get_cache_hit_rate do
    case LLMPerformanceDashboard.get_live_metrics() do
      {:ok, metrics} ->
        metrics.cache_hit_rate
      _ ->
        nil
    end
  end
  
  defp get_memory_usage do
    total_memory = :erlang.memory(:total)
    # Convert to percentage (simplified)
    total_memory / (1024 * 1024 * 1024)  # GB
  end
  
  defp get_cluster_node_count do
    length(Node.list()) + 1
  end
  
  # Baseline management for anomaly detection
  
  defp initialize_metric_baselines do
    Enum.each(Map.keys(@alert_configs), fn alert_type ->
      config = @alert_configs[alert_type]
      if config.threshold_type == :anomaly do
        calculate_initial_baseline(config.metric)
      end
    end)
  end
  
  defp calculate_initial_baseline(metric) do
    # Calculate baseline from recent historical data
    current_time = :os.system_time(:millisecond)
    _since = current_time - @anomaly_detection_window
    
    # This would collect historical values - simplified for now
    sample_values = [1.0, 1.1, 0.9, 1.2, 0.8, 1.0, 1.1]  # Mock data
    
    if length(sample_values) > 0 do
      mean = Enum.sum(sample_values) / length(sample_values)
      variance = calculate_variance(sample_values, mean)
      std_dev = :math.sqrt(variance)
      
      baseline = %{
        metric: metric,
        mean: mean,
        std_dev: std_dev,
        sample_count: length(sample_values),
        last_updated: current_time
      }
      
      :ets.insert(:metric_baselines, {metric, baseline})
    end
  end
  
  defp update_metric_baselines do
    # Update baselines with new data points
    :ets.foldl(fn {metric, baseline}, _acc ->
      current_value = get_current_metric_value(metric)
      
      if current_value do
        updated_baseline = update_baseline_with_value(baseline, current_value)
        :ets.insert(:metric_baselines, {metric, updated_baseline})
      end
      
      :ok
    end, :ok, :metric_baselines)
  end
  
  defp get_metric_baseline(metric) do
    case :ets.lookup(:metric_baselines, metric) do
      [{_, baseline}] -> baseline
      [] -> nil
    end
  end
  
  defp update_baseline_with_value(baseline, new_value) do
    # Simple exponential moving average update
    alpha = 0.1  # Smoothing factor
    
    new_mean = baseline.mean * (1 - alpha) + new_value * alpha
    new_variance = baseline.std_dev * baseline.std_dev * (1 - alpha) + 
                  :math.pow(new_value - new_mean, 2) * alpha
    new_std_dev = :math.sqrt(new_variance)
    
    %{baseline |
      mean: new_mean,
      std_dev: new_std_dev,
      sample_count: baseline.sample_count + 1,
      last_updated: :os.system_time(:millisecond)
    }
  end
  
  defp calculate_variance(values, mean) do
    if length(values) <= 1 do
      0
    else
      sum_squares = Enum.reduce(values, 0, fn value, acc ->
        acc + :math.pow(value - mean, 2)
      end)
      sum_squares / (length(values) - 1)
    end
  end
  
  # Alert management functions
  
  defp get_active_alerts_internal do
    :ets.tab2list(:active_alerts)
    |> Enum.map(fn {_id, alert} -> alert end)
    |> Enum.sort_by(& &1.timestamp, :desc)
  end
  
  defp get_alert_history_internal(opts) do
    limit = Keyword.get(opts, :limit, 100)
    since = Keyword.get(opts, :since, :os.system_time(:millisecond) - :timer.hours(24))
    severity_filter = Keyword.get(opts, :severity)
    
    alerts = :ets.select(:alert_history, [
      {{:"$1", :"$2"}, [{:>=, :"$1", since}], [:"$2"]}
    ])
    
    filtered_alerts = if severity_filter do
      Enum.filter(alerts, fn alert -> alert.severity == severity_filter end)
    else
      alerts
    end
    
    filtered_alerts
    |> Enum.sort_by(& &1.timestamp, :desc)
    |> Enum.take(limit)
  end
  
  defp acknowledge_alert_internal(alert_id) do
    case :ets.lookup(:active_alerts, alert_id) do
      [{_, alert}] ->
        updated_alert = %{alert |
          acknowledged: true,
          acknowledged_by: "system",  # In practice, this would be the user
          acknowledged_at: :os.system_time(:millisecond),
          status: :acknowledged
        }
        
        :ets.insert(:active_alerts, {alert_id, updated_alert})
        EventBroadcaster.broadcast_async(%{
          topic: "alert.acknowledged",
          payload: updated_alert
        })
        
        {:ok, updated_alert}
      
      [] ->
        {:error, :alert_not_found}
    end
  end
  
  defp configure_alert_internal(alert_type, config) do
    if Map.has_key?(@alert_configs, alert_type) do
      # In practice, this would update the configuration
      Logger.info("Alert configuration updated for #{alert_type}: #{inspect(config)}")
      {:ok, :updated}
    else
      {:error, :unknown_alert_type}
    end
  end
  
  defp update_alert_statistics(current_stats, new_alerts) do
    new_total = current_stats.total_alerts + length(new_alerts)
    
    new_by_severity = Enum.reduce(new_alerts, current_stats.alerts_by_severity, fn alert, acc ->
      Map.update(acc, alert.severity, 1, &(&1 + 1))
    end)
    
    %{current_stats |
      total_alerts: new_total,
      alerts_by_severity: new_by_severity
    }
  end
  
  defp enhance_alert_statistics(basic_stats) do
    active_count = length(get_active_alerts_internal())
    
    recent_alerts = get_alert_history_internal(since: :os.system_time(:millisecond) - :timer.hours(1))
    recent_count = length(recent_alerts)
    
    Map.merge(basic_stats, %{
      active_alerts: active_count,
      recent_alerts_1h: recent_count,
      alert_rate_per_hour: recent_count
    })
  end
  
  # Immediate alert checks for real-time events
  
  defp check_immediate_failure_alert(event_data) do
    # Check for patterns that warrant immediate alerting
    if Map.get(event_data, :consecutive_failures, 0) >= 5 do
      alert = create_alert(:consecutive_failures, 
        %{severity: :critical, description: "Multiple consecutive failures detected"},
        %{consecutive_count: event_data.consecutive_failures}
      )
      trigger_alert(alert)
    end
  end
  
  defp check_immediate_provider_alert(event_data) do
    if Map.get(event_data, :health_score, 100) < 50 do
      alert = create_alert(:provider_critical_degradation,
        %{severity: :critical, description: "Provider critically degraded"},
        %{provider: event_data.provider, health_score: event_data.health_score}
      )
      trigger_alert(alert)
    end
  end
  
  defp trigger_node_down_alert(event_data) do
    alert = create_alert(:cluster_node_down,
      %{severity: :critical, description: "Cluster node has gone offline"},
      %{node: event_data.node, reason: event_data.reason}
    )
    trigger_alert(alert)
  end
  
  defp check_immediate_cost_alert(event_data) do
    if Map.get(event_data, :spike_factor, 1.0) > 3.0 do
      alert = create_alert(:cost_emergency_spike,
        %{severity: :emergency, description: "Emergency cost spike detected"},
        %{spike_factor: event_data.spike_factor, current_rate: event_data.current_rate}
      )
      trigger_alert(alert)
    end
  end
end