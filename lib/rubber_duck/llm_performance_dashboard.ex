defmodule RubberDuck.LLMPerformanceDashboard do
  @moduledoc """
  Real-time performance monitoring dashboard for LLM operations.
  
  Provides a comprehensive web-based interface for monitoring:
  - Live LLM performance metrics
  - Provider comparison analytics
  - Cost tracking and optimization
  - Cache performance visualization
  - System health monitoring
  - Historical trend analysis
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.LLMMetricsCollector
  alias RubberDuck.LLMQueryOptimizer
  alias RubberDuck.EventBroadcasting.EventBroadcaster
  
  @dashboard_refresh_interval :timer.seconds(5)
  @metric_history_window :timer.hours(24)
  @real_time_window :timer.minutes(15)
  
  # Dashboard widget configurations
  @dashboard_widgets %{
    # Real-time metrics widgets
    live_requests: %{
      title: "Live Request Rate",
      type: :line_chart,
      refresh_rate: :timer.seconds(1),
      data_source: :live_metrics,
      metrics: ["llm.requests.total"]
    },
    
    provider_health: %{
      title: "Provider Health",
      type: :gauge_chart,
      refresh_rate: :timer.seconds(5),
      data_source: :provider_status,
      metrics: ["llm.provider.health_score", "llm.provider.availability"]
    },
    
    cost_tracker: %{
      title: "Cost Tracking",
      type: :area_chart,
      refresh_rate: :timer.seconds(10),
      data_source: :cost_analysis,
      metrics: ["llm.cost.total", "llm.cost.rate"]
    },
    
    latency_distribution: %{
      title: "Response Latency",
      type: :histogram,
      refresh_rate: :timer.seconds(5),
      data_source: :latency_stats,
      metrics: ["llm.latency.request"]
    },
    
    cache_performance: %{
      title: "Cache Performance",
      type: :donut_chart,
      refresh_rate: :timer.seconds(5),
      data_source: :cache_stats,
      metrics: ["llm.cache.hit_rate", "llm.cache.hits", "llm.cache.misses"]
    },
    
    token_usage: %{
      title: "Token Usage",
      type: :stacked_bar,
      refresh_rate: :timer.seconds(10),
      data_source: :token_analysis,
      metrics: ["llm.tokens.input", "llm.tokens.output"]
    },
    
    # Comparative widgets
    provider_comparison: %{
      title: "Provider Comparison",
      type: :radar_chart,
      refresh_rate: :timer.seconds(30),
      data_source: :provider_comparison,
      metrics: ["health_score", "average_latency", "success_rate", "cost_efficiency"]
    },
    
    # Historical widgets
    performance_trends: %{
      title: "Performance Trends",
      type: :multi_line_chart,
      refresh_rate: :timer.minutes(1),
      data_source: :historical_trends,
      metrics: ["llm.requests.success", "llm.latency.request.avg", "llm.cost.rate"]
    },
    
    # System health widgets
    system_overview: %{
      title: "System Overview",
      type: :status_grid,
      refresh_rate: :timer.seconds(5),
      data_source: :system_health,
      metrics: ["node_count", "cluster_health", "mnesia_status", "cache_status"]
    }
  }
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    refresh_interval = Keyword.get(opts, :refresh_interval, @dashboard_refresh_interval)
    
    # Subscribe to relevant events for real-time updates
    EventBroadcaster.subscribe("llm.*")
    EventBroadcaster.subscribe("cache.llm.*")
    EventBroadcaster.subscribe("provider.*")
    EventBroadcaster.subscribe("cluster.*")
    
    # Initialize dashboard data storage
    :ets.new(:dashboard_data, [:named_table, :public, :set])
    :ets.new(:dashboard_history, [:named_table, :public, :bag])
    
    # Schedule periodic updates
    :timer.send_interval(refresh_interval, self(), :update_dashboard)
    
    # Initialize widgets
    initialize_dashboard_widgets()
    
    Logger.info("LLM Performance Dashboard started")
    
    {:ok, %{
      refresh_interval: refresh_interval,
      last_update: :os.system_time(:millisecond),
      active_connections: %{},
      widget_subscriptions: %{}
    }}
  end
  
  @impl true
  def handle_info({:event, topic, event_data}, state) do
    process_real_time_event(topic, event_data)
    {:noreply, state}
  end
  
  def handle_info(:update_dashboard, state) do
    update_all_widgets()
    cleanup_old_history()
    {:noreply, %{state | last_update: :os.system_time(:millisecond)}}
  end
  
  @impl true
  def handle_call({:get_widget_data, widget_id}, _from, state) do
    data = get_widget_data_internal(widget_id)
    {:reply, data, state}
  end
  
  def handle_call({:get_dashboard_summary}, _from, state) do
    summary = generate_dashboard_summary()
    {:reply, summary, state}
  end
  
  def handle_call({:subscribe_widget, widget_id, pid}, _from, state) do
    new_subscriptions = Map.update(state.widget_subscriptions, widget_id, [pid], fn pids ->
      [pid | pids] |> Enum.uniq()
    end)
    
    {:reply, :ok, %{state | widget_subscriptions: new_subscriptions}}
  end
  
  # Public API
  
  @doc """
  Get current dashboard summary data
  """
  def get_dashboard_summary do
    GenServer.call(__MODULE__, {:get_dashboard_summary})
  end
  
  @doc """
  Get data for a specific widget
  """
  def get_widget_data(widget_id) do
    GenServer.call(__MODULE__, {:get_widget_data, widget_id})
  end
  
  @doc """
  Subscribe to real-time widget updates
  """
  def subscribe_widget_updates(widget_id) do
    GenServer.call(__MODULE__, {:subscribe_widget, widget_id, self()})
  end
  
  @doc """
  Get live performance metrics for the dashboard
  """
  def get_live_metrics(opts \\ []) do
    window = Keyword.get(opts, :window, @real_time_window)
    
    %{
      timestamp: :os.system_time(:millisecond),
      request_rate: get_current_request_rate(window),
      success_rate: get_current_success_rate(window),
      average_latency: get_current_average_latency(window),
      active_providers: get_active_provider_count(),
      cache_hit_rate: get_current_cache_hit_rate(window),
      cost_per_minute: get_current_cost_rate(window),
      total_tokens_per_minute: get_current_token_rate(window)
    }
  end
  
  @doc """
  Get provider comparison data for dashboard
  """
  def get_provider_comparison_data(opts \\ []) do
    window = Keyword.get(opts, :window, @real_time_window)
    LLMMetricsCollector.get_provider_comparison(window: window)
  end
  
  @doc """
  Get cost analysis data for dashboard
  """
  def get_cost_analysis_data(opts \\ []) do
    window = Keyword.get(opts, :window, @metric_history_window)
    LLMMetricsCollector.get_cost_analysis(window: window, breakdown_by: :provider)
  end
  
  @doc """
  Get system health status for dashboard
  """
  def get_system_health_data do
    %{
      timestamp: :os.system_time(:millisecond),
      cluster_status: get_cluster_health(),
      mnesia_status: get_mnesia_health(),
      cache_status: get_cache_health(),
      node_count: get_cluster_node_count(),
      total_memory_usage: get_memory_usage(),
      cpu_utilization: get_cpu_utilization()
    }
  end
  
  @doc """
  Get historical trend data for charts
  """
  def get_historical_trends(metric, opts \\ []) do
    window = Keyword.get(opts, :window, @metric_history_window)
    interval = Keyword.get(opts, :interval, :timer.minutes(5))
    
    current_time = :os.system_time(:millisecond)
    since = current_time - window
    
    # Generate time series data points
    point_count = div(window, interval)
    
    Enum.map(0..(point_count - 1), fn i ->
      point_time = since + (i * interval)
      point_end = point_time + interval
      
      value = get_metric_value_in_window(metric, point_time, point_end)
      
      %{
        timestamp: point_time,
        value: value
      }
    end)
  end
  
  # Private Functions
  
  defp initialize_dashboard_widgets do
    Enum.each(@dashboard_widgets, fn {widget_id, widget_config} ->
      :ets.insert(:dashboard_data, {{:widget_config, widget_id}, widget_config})
      
      # Initialize with empty data
      initial_data = %{
        timestamp: :os.system_time(:millisecond),
        data: [],
        status: :initializing
      }
      
      :ets.insert(:dashboard_data, {{:widget_data, widget_id}, initial_data})
    end)
  end
  
  defp process_real_time_event(topic, event_data) do
    # Update relevant widgets based on event type
    case topic do
      "llm.request." <> _status ->
        update_widget_real_time(:live_requests, event_data)
        update_widget_real_time(:latency_distribution, event_data)
      
      "llm.tokens.usage" ->
        update_widget_real_time(:token_usage, event_data)
        update_widget_real_time(:cost_tracker, event_data)
      
      "cache.llm." <> _operation ->
        update_widget_real_time(:cache_performance, event_data)
      
      "provider.status.update" ->
        update_widget_real_time(:provider_health, event_data)
        update_widget_real_time(:provider_comparison, event_data)
      
      "cluster." <> _event ->
        update_widget_real_time(:system_overview, event_data)
      
      _ ->
        :ok
    end
  end
  
  defp update_all_widgets do
    Enum.each(@dashboard_widgets, fn {widget_id, _config} ->
      update_widget_data(widget_id)
    end)
  end
  
  defp update_widget_data(widget_id) do
    widget_config = get_widget_config(widget_id)
    
    new_data = case widget_config.data_source do
      :live_metrics -> get_live_metrics()
      :provider_status -> get_provider_status_data()
      :cost_analysis -> get_cost_analysis_data()
      :latency_stats -> get_latency_statistics()
      :cache_stats -> get_cache_statistics()
      :token_analysis -> get_token_analysis_data()
      :provider_comparison -> get_provider_comparison_data()
      :historical_trends -> get_historical_trends_data(widget_config.metrics)
      :system_health -> get_system_health_data()
      _ -> %{}
    end
    
    widget_data = %{
      timestamp: :os.system_time(:millisecond),
      data: new_data,
      status: :active
    }
    
    :ets.insert(:dashboard_data, {{:widget_data, widget_id}, widget_data})
    
    # Store in history for trend analysis
    :ets.insert(:dashboard_history, {{widget_id, :os.system_time(:millisecond)}, widget_data})
    
    # Notify subscribers
    notify_widget_subscribers(widget_id, widget_data)
  end
  
  defp update_widget_real_time(widget_id, event_data) do
    # For real-time updates, we update immediately without waiting for the scheduled refresh
    case get_widget_config(widget_id) do
      nil -> :ok
      widget_config ->
        if should_update_real_time?(widget_config, event_data) do
          update_widget_data(widget_id)
        end
    end
  end
  
  defp get_widget_config(widget_id) do
    case :ets.lookup(:dashboard_data, {:widget_config, widget_id}) do
      [{_, config}] -> config
      [] -> nil
    end
  end
  
  defp get_widget_data_internal(widget_id) do
    case :ets.lookup(:dashboard_data, {:widget_data, widget_id}) do
      [{_, data}] -> data
      [] -> %{timestamp: :os.system_time(:millisecond), data: [], status: :no_data}
    end
  end
  
  defp should_update_real_time?(widget_config, _event_data) do
    # Check if enough time has passed since last update based on widget refresh rate
    last_update = get_widget_last_update(widget_config)
    current_time = :os.system_time(:millisecond)
    
    current_time - last_update >= widget_config.refresh_rate
  end
  
  defp get_widget_last_update(widget_config) do
    # Simplified - in practice you'd track per-widget update times
    :os.system_time(:millisecond) - widget_config.refresh_rate
  end
  
  defp notify_widget_subscribers(widget_id, _widget_data) do
    # This would notify WebSocket connections or LiveView processes
    # For now, we'll just log the update
    Logger.debug("Widget #{widget_id} updated with new data")
  end
  
  defp cleanup_old_history do
    cutoff = :os.system_time(:millisecond) - @metric_history_window
    
    :ets.select_delete(:dashboard_history, [
      {{{:_, :"$1"}, :_}, [{:<, :"$1", cutoff}], [true]}
    ])
  end
  
  defp generate_dashboard_summary do
    live_metrics = get_live_metrics()
    system_health = get_system_health_data()
    cost_data = get_cost_analysis_data(window: :timer.hours(1))
    
    %{
      timestamp: :os.system_time(:millisecond),
      status: determine_overall_status(live_metrics, system_health),
      key_metrics: %{
        requests_per_minute: live_metrics.request_rate,
        success_rate: live_metrics.success_rate,
        average_latency: live_metrics.average_latency,
        cost_per_hour: cost_data.cost_per_request * live_metrics.request_rate * 60,
        cache_hit_rate: live_metrics.cache_hit_rate,
        active_providers: live_metrics.active_providers
      },
      alerts: generate_alert_summary(),
      performance_score: calculate_overall_performance_score(live_metrics)
    }
  end
  
  defp determine_overall_status(live_metrics, system_health) do
    cond do
      live_metrics.success_rate < 0.90 -> :degraded
      live_metrics.average_latency > 5000 -> :slow
      system_health.cluster_status != :healthy -> :unstable
      true -> :healthy
    end
  end
  
  defp generate_alert_summary do
    # This would check various thresholds and return active alerts
    []
  end
  
  defp calculate_overall_performance_score(live_metrics) do
    # Calculate a 0-100 performance score based on key metrics
    success_score = live_metrics.success_rate * 100
    latency_score = max(0, 100 - (live_metrics.average_latency / 50))
    cache_score = live_metrics.cache_hit_rate
    
    (success_score + latency_score + cache_score) / 3
  end
  
  # Data source functions
  
  defp get_current_request_rate(window) do
    metrics = LLMMetricsCollector.get_metrics_summary(window: window)
    total_requests = Map.get(metrics, "llm.requests.total", %{sum: 0}).sum
    minutes = window / (1000 * 60)
    total_requests / minutes
  end
  
  defp get_current_success_rate(window) do
    metrics = LLMMetricsCollector.get_metrics_summary(window: window)
    success = Map.get(metrics, "llm.requests.success", %{sum: 0}).sum
    total = Map.get(metrics, "llm.requests.total", %{sum: 1}).sum
    if total > 0, do: (success / total) * 100, else: 0
  end
  
  defp get_current_average_latency(window) do
    metrics = LLMMetricsCollector.get_metrics_summary(window: window)
    latency_data = Map.get(metrics, "llm.latency.request", %{avg: 0})
    latency_data.avg
  end
  
  defp get_active_provider_count do
    # This would query the current active provider count
    length(LLMMetricsCollector.get_provider_comparison())
  end
  
  defp get_current_cache_hit_rate(window) do
    metrics = LLMMetricsCollector.get_metrics_summary(window: window)
    hit_rate_data = Map.get(metrics, "llm.cache.hit_rate", %{avg: 0})
    hit_rate_data.avg
  end
  
  defp get_current_cost_rate(window) do
    cost_data = get_cost_analysis_data(window: window)
    minutes = window / (1000 * 60)
    cost_data.total_cost / minutes
  end
  
  defp get_current_token_rate(window) do
    metrics = LLMMetricsCollector.get_metrics_summary(window: window)
    total_tokens = Map.get(metrics, "llm.tokens.total", %{sum: 0}).sum
    minutes = window / (1000 * 60)
    total_tokens / minutes
  end
  
  defp get_provider_status_data do
    LLMMetricsCollector.get_provider_comparison()
  end
  
  defp get_latency_statistics do
    metrics = LLMMetricsCollector.get_metrics_summary()
    Map.get(metrics, "llm.latency.request", %{})
  end
  
  defp get_cache_statistics do
    metrics = LLMMetricsCollector.get_metrics_summary()
    
    %{
      hit_rate: Map.get(metrics, "llm.cache.hit_rate", %{avg: 0}).avg,
      hits: Map.get(metrics, "llm.cache.hits", %{sum: 0}).sum,
      misses: Map.get(metrics, "llm.cache.misses", %{sum: 0}).sum,
      evictions: Map.get(metrics, "llm.cache.evictions", %{sum: 0}).sum
    }
  end
  
  defp get_token_analysis_data do
    LLMQueryOptimizer.optimized_token_analysis()
  end
  
  defp get_historical_trends_data(metrics) do
    Enum.map(metrics, fn metric ->
      {metric, get_historical_trends(metric)}
    end)
    |> Map.new()
  end
  
  defp get_cluster_health do
    # This would check cluster node status
    :healthy
  end
  
  defp get_mnesia_health do
    # This would check Mnesia status
    :healthy
  end
  
  defp get_cache_health do
    # This would check cache system status
    :healthy
  end
  
  defp get_cluster_node_count do
    # This would return the number of active cluster nodes
    length(Node.list()) + 1
  end
  
  defp get_memory_usage do
    # This would return current memory usage
    :erlang.memory(:total)
  end
  
  defp get_cpu_utilization do
    # This would return current CPU utilization
    0.0
  end
  
  defp get_metric_value_in_window(_metric, _since, _until) do
    # This would get the metric value for a specific time window
    # For now, return a sample value
    :rand.uniform(100)
  end
end