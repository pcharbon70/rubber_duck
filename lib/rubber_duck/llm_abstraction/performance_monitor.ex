defmodule RubberDuck.LLMAbstraction.PerformanceMonitor do
  @moduledoc """
  Performance monitoring and alerting system for LLM operations.
  
  This module provides real-time monitoring of LLM provider performance,
  automated alerting based on configurable thresholds, and performance
  optimization recommendations.
  """

  use GenServer
  require Logger

  alias RubberDuck.LLMAbstraction.{MetricsCollector, Telemetry}

  defstruct [
    :config,
    :alert_thresholds,
    :performance_baselines,
    :alert_history,
    :monitoring_state
  ]

  @check_interval 30_000  # 30 seconds
  @baseline_window 300_000  # 5 minutes for baseline calculations

  ## Public API

  @doc """
  Start the performance monitor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current performance status for all providers.
  """
  def get_performance_status do
    GenServer.call(__MODULE__, :get_performance_status)
  end

  @doc """
  Get performance alerts.
  """
  def get_alerts(filter \\ %{}) do
    GenServer.call(__MODULE__, {:get_alerts, filter})
  end

  @doc """
  Update alert thresholds.
  """
  def update_thresholds(new_thresholds) do
    GenServer.call(__MODULE__, {:update_thresholds, new_thresholds})
  end

  @doc """
  Force performance check.
  """
  def force_check do
    GenServer.cast(__MODULE__, :force_check)
  end

  @doc """
  Get performance recommendations.
  """
  def get_recommendations do
    GenServer.call(__MODULE__, :get_recommendations)
  end

  ## GenServer Implementation

  @impl GenServer
  def init(opts) do
    # Schedule initial performance check
    schedule_performance_check()
    
    state = %__MODULE__{
      config: Keyword.get(opts, :config, %{}),
      alert_thresholds: initialize_alert_thresholds(opts),
      performance_baselines: %{},
      alert_history: [],
      monitoring_state: %{
        last_check: 0,
        check_count: 0,
        alerts_sent: 0
      }
    }
    
    Logger.info("LLM Performance Monitor started")
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_performance_status, _from, state) do
    status = generate_performance_status(state)
    {:reply, status, state}
  end

  @impl GenServer
  def handle_call({:get_alerts, filter}, _from, state) do
    filtered_alerts = filter_alerts(state.alert_history, filter)
    {:reply, filtered_alerts, state}
  end

  @impl GenServer
  def handle_call({:update_thresholds, new_thresholds}, _from, state) do
    updated_thresholds = Map.merge(state.alert_thresholds, new_thresholds)
    new_state = %{state | alert_thresholds: updated_thresholds}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:get_recommendations, _from, state) do
    recommendations = generate_performance_recommendations(state)
    {:reply, recommendations, state}
  end

  @impl GenServer
  def handle_cast(:force_check, state) do
    new_state = perform_performance_check(state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:performance_check, state) do
    new_state = perform_performance_check(state)
    schedule_performance_check()
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Performance Monitoring Functions

  defp perform_performance_check(state) do
    current_time = System.system_time(:millisecond)
    
    # Get current metrics from all providers
    aggregate_metrics = MetricsCollector.get_aggregate_metrics()
    performance_stats = MetricsCollector.get_performance_stats()
    
    # Update performance baselines
    new_baselines = update_performance_baselines(state.performance_baselines, performance_stats, current_time)
    
    # Check for performance issues
    alerts = check_performance_thresholds(performance_stats, state.alert_thresholds, new_baselines)
    
    # Update alert history
    new_alert_history = add_alerts_to_history(state.alert_history, alerts, current_time)
    
    # Send alerts if any
    if not Enum.empty?(alerts) do
      send_performance_alerts(alerts)
    end
    
    # Update monitoring state
    new_monitoring_state = %{state.monitoring_state |
      last_check: current_time,
      check_count: state.monitoring_state.check_count + 1,
      alerts_sent: state.monitoring_state.alerts_sent + length(alerts)
    }
    
    %{state |
      performance_baselines: new_baselines,
      alert_history: new_alert_history,
      monitoring_state: new_monitoring_state
    }
  end

  defp update_performance_baselines(baselines, current_stats, current_time) do
    # Update rolling averages for performance baselines
    window_start = current_time - @baseline_window
    
    # Calculate new baselines based on recent performance
    new_baseline = %{
      average_response_time: Map.get(current_stats, :average_response_time, 0),
      error_rate: Map.get(current_stats, :average_error_rate, 0),
      requests_per_second: Map.get(current_stats, :requests_per_second, 0),
      updated_at: current_time,
      window_start: window_start
    }
    
    Map.put(baselines, :global, new_baseline)
  end

  defp check_performance_thresholds(stats, thresholds, baselines) do
    alerts = []
    
    # Check response time threshold
    alerts = check_response_time_threshold(stats, thresholds, baselines, alerts)
    
    # Check error rate threshold
    alerts = check_error_rate_threshold(stats, thresholds, baselines, alerts)
    
    # Check throughput threshold
    alerts = check_throughput_threshold(stats, thresholds, baselines, alerts)
    
    # Check cost threshold
    alerts = check_cost_threshold(stats, thresholds, alerts)
    
    alerts
  end

  defp check_response_time_threshold(stats, thresholds, baselines, alerts) do
    current_response_time = Map.get(stats, :average_response_time, 0)
    threshold = Map.get(thresholds, :max_response_time, 10000)  # 10 seconds default
    baseline = get_in(baselines, [:global, :average_response_time]) || 0
    
    cond do
      current_response_time > threshold ->
        alert = create_alert(:response_time_exceeded, :critical, %{
          current_value: current_response_time,
          threshold: threshold,
          message: "Response time exceeded threshold: #{current_response_time}ms > #{threshold}ms"
        })
        [alert | alerts]
      
      baseline > 0 and current_response_time > baseline * 2 ->
        alert = create_alert(:response_time_degraded, :warning, %{
          current_value: current_response_time,
          baseline: baseline,
          message: "Response time degraded significantly: #{current_response_time}ms vs baseline #{baseline}ms"
        })
        [alert | alerts]
      
      true ->
        alerts
    end
  end

  defp check_error_rate_threshold(stats, thresholds, baselines, alerts) do
    current_error_rate = Map.get(stats, :average_error_rate, 0)
    threshold = Map.get(thresholds, :max_error_rate, 0.1)  # 10% default
    baseline = get_in(baselines, [:global, :error_rate]) || 0
    
    cond do
      current_error_rate > threshold ->
        alert = create_alert(:error_rate_exceeded, :critical, %{
          current_value: current_error_rate,
          threshold: threshold,
          message: "Error rate exceeded threshold: #{Float.round(current_error_rate * 100, 2)}% > #{Float.round(threshold * 100, 2)}%"
        })
        [alert | alerts]
      
      baseline >= 0 and current_error_rate > baseline * 3 ->
        alert = create_alert(:error_rate_increased, :warning, %{
          current_value: current_error_rate,
          baseline: baseline,
          message: "Error rate increased significantly: #{Float.round(current_error_rate * 100, 2)}% vs baseline #{Float.round(baseline * 100, 2)}%"
        })
        [alert | alerts]
      
      true ->
        alerts
    end
  end

  defp check_throughput_threshold(stats, thresholds, baselines, alerts) do
    current_rps = Map.get(stats, :requests_per_second, 0)
    min_threshold = Map.get(thresholds, :min_requests_per_second, 0.1)
    baseline = get_in(baselines, [:global, :requests_per_second]) || 0
    
    cond do
      current_rps < min_threshold ->
        alert = create_alert(:throughput_too_low, :warning, %{
          current_value: current_rps,
          threshold: min_threshold,
          message: "Throughput below minimum threshold: #{current_rps} RPS < #{min_threshold} RPS"
        })
        [alert | alerts]
      
      baseline > 0 and current_rps < baseline * 0.5 ->
        alert = create_alert(:throughput_degraded, :warning, %{
          current_value: current_rps,
          baseline: baseline,
          message: "Throughput degraded significantly: #{current_rps} RPS vs baseline #{baseline} RPS"
        })
        [alert | alerts]
      
      true ->
        alerts
    end
  end

  defp check_cost_threshold(stats, thresholds, alerts) do
    current_cost = Map.get(stats, :total_cost, 0)
    max_cost = Map.get(thresholds, :max_hourly_cost, 100.0)  # $100/hour default
    
    # Calculate hourly cost rate
    uptime_hours = Map.get(stats, :uptime_seconds, 0) / 3600
    hourly_cost = if uptime_hours > 0, do: current_cost / uptime_hours, else: 0
    
    if hourly_cost > max_cost do
      alert = create_alert(:cost_exceeded, :critical, %{
        current_value: hourly_cost,
        threshold: max_cost,
        message: "Hourly cost exceeded threshold: $#{Float.round(hourly_cost, 2)}/h > $#{max_cost}/h"
      })
      [alert | alerts]
    else
      alerts
    end
  end

  defp create_alert(type, severity, data) do
    %{
      type: type,
      severity: severity,
      timestamp: System.system_time(:second),
      data: data,
      id: generate_alert_id()
    }
  end

  defp generate_alert_id do
    "alert_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp add_alerts_to_history(history, new_alerts, current_time) do
    # Add new alerts and keep last 1000 alerts
    updated_history = new_alerts ++ history
    
    # Remove alerts older than 24 hours
    cutoff_time = current_time - 86_400_000
    recent_alerts = Enum.filter(updated_history, fn alert ->
      alert.timestamp * 1000 > cutoff_time
    end)
    
    Enum.take(recent_alerts, 1000)
  end

  defp send_performance_alerts(alerts) do
    Enum.each(alerts, fn alert ->
      Logger.warning("LLM Performance Alert [#{alert.severity}]: #{alert.data.message}")
      
      # Send telemetry event for alert
      Telemetry.execute([:performance, :alert], %{count: 1}, %{
        alert_type: alert.type,
        severity: alert.severity,
        alert_id: alert.id
      })
    end)
  end

  defp generate_performance_status(state) do
    current_stats = MetricsCollector.get_performance_stats()
    recent_alerts = Enum.take(state.alert_history, 10)
    
    %{
      overall_health: calculate_overall_health(current_stats, recent_alerts),
      performance_stats: current_stats,
      recent_alerts: recent_alerts,
      monitoring_info: state.monitoring_state,
      baselines: state.performance_baselines,
      alert_thresholds: state.alert_thresholds
    }
  end

  defp calculate_overall_health(stats, recent_alerts) do
    # Calculate health score based on metrics and recent alerts
    error_rate = Map.get(stats, :average_error_rate, 0)
    critical_alerts = Enum.count(recent_alerts, &(&1.severity == :critical))
    
    cond do
      critical_alerts > 0 -> :critical
      error_rate > 0.1 -> :degraded
      error_rate > 0.05 -> :warning
      true -> :healthy
    end
  end

  defp generate_performance_recommendations(state) do
    current_stats = MetricsCollector.get_performance_stats()
    recommendations = []
    
    # Check for high error rates
    recommendations = if Map.get(current_stats, :average_error_rate, 0) > 0.05 do
      [%{
        type: :high_error_rate,
        priority: :high,
        description: "High error rate detected. Consider checking provider health and configuration.",
        action: "Review provider configurations and API status"
      } | recommendations]
    else
      recommendations
    end
    
    # Check for slow response times
    recommendations = if Map.get(current_stats, :average_response_time, 0) > 5000 do
      [%{
        type: :slow_response,
        priority: :medium,
        description: "Slow response times detected. Consider optimizing requests or switching providers.",
        action: "Review request optimization and provider selection"
      } | recommendations]
    else
      recommendations
    end
    
    # Check for high costs
    recommendations = if Map.get(current_stats, :total_cost, 0) > 50 do
      [%{
        type: :high_cost,
        priority: :medium,
        description: "High costs detected. Consider cost optimization strategies.",
        action: "Review cost optimization settings and provider pricing"
      } | recommendations]
    else
      recommendations
    end
    
    recommendations
  end

  defp filter_alerts(alerts, filter) do
    severity_filter = Map.get(filter, :severity)
    type_filter = Map.get(filter, :type)
    limit = Map.get(filter, :limit, 100)
    
    alerts
    |> Enum.filter(fn alert ->
      (severity_filter == nil or alert.severity == severity_filter) and
      (type_filter == nil or alert.type == type_filter)
    end)
    |> Enum.take(limit)
  end

  defp initialize_alert_thresholds(opts) do
    %{
      max_response_time: Keyword.get(opts, :max_response_time, 10_000),     # 10 seconds
      max_error_rate: Keyword.get(opts, :max_error_rate, 0.1),             # 10%
      min_requests_per_second: Keyword.get(opts, :min_rps, 0.1),           # 0.1 RPS
      max_hourly_cost: Keyword.get(opts, :max_hourly_cost, 100.0)          # $100/hour
    }
  end

  defp schedule_performance_check do
    Process.send_after(self(), :performance_check, @check_interval)
  end
end