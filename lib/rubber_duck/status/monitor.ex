defmodule RubberDuck.Status.Monitor do
  @moduledoc """
  Monitoring and alerting system for the Status Broadcasting System.

  Tracks system health, performance metrics, and triggers alerts when
  thresholds are exceeded.

  ## Features

  - Real-time metric tracking
  - Threshold-based alerting
  - Performance analysis
  - System health indicators
  - Historical metric storage
  """

  use GenServer
  require Logger

  @type metric_type :: :queue_depth | :throughput | :latency | :error_rate
  @type alert_level :: :info | :warning | :critical

  @type state :: %{
          metrics: %{metric_type() => list(float())},
          thresholds: %{metric_type() => %{warning: float(), critical: float()}},
          alerts: list(map()),
          health_status: :healthy | :degraded | :unhealthy,
          started_at: DateTime.t()
        }

  # Default thresholds
  @default_thresholds %{
    queue_depth: %{warning: 1000, critical: 5000},
    # messages/second (lower is bad)
    throughput: %{warning: 100, critical: 50},
    # milliseconds
    latency: %{warning: 100, critical: 500},
    # 1% and 5%
    error_rate: %{warning: 0.01, critical: 0.05}
  }

  # Metric window size (number of samples to keep)
  @metric_window 100

  # Alert cooldown period (milliseconds)
  @alert_cooldown 60_000

  # Client API

  @doc """
  Starts the status monitor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a metric value.
  """
  def record_metric(metric_type, value) do
    GenServer.cast(__MODULE__, {:record_metric, metric_type, value})
  end

  @doc """
  Gets the current health status.
  """
  def health_status do
    GenServer.call(__MODULE__, :health_status)
  end

  @doc """
  Gets current metrics summary.
  """
  def metrics_summary do
    GenServer.call(__MODULE__, :metrics_summary)
  end

  @doc """
  Gets recent alerts.
  """
  def recent_alerts(limit \\ 10) do
    GenServer.call(__MODULE__, {:recent_alerts, limit})
  end

  @doc """
  Updates alert thresholds.
  """
  def update_thresholds(metric_type, warning, critical) do
    GenServer.call(__MODULE__, {:update_thresholds, metric_type, warning, critical})
  end

  @doc """
  Clears all alerts.
  """
  def clear_alerts do
    GenServer.cast(__MODULE__, :clear_alerts)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    # Subscribe to telemetry events
    attach_telemetry_handlers()

    # Schedule periodic health checks
    schedule_health_check()

    state = %{
      metrics: %{
        queue_depth: [],
        throughput: [],
        latency: [],
        error_rate: []
      },
      thresholds: Keyword.get(opts, :thresholds, @default_thresholds),
      alerts: [],
      health_status: :healthy,
      started_at: DateTime.utc_now(),
      last_alert_times: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:record_metric, metric_type, value}, state) do
    new_state =
      state
      |> update_metric(metric_type, value)
      |> check_thresholds(metric_type)
      |> update_health_status()

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:clear_alerts, state) do
    {:noreply, %{state | alerts: []}}
  end

  @impl true
  def handle_call(:health_status, _from, state) do
    status = %{
      status: state.health_status,
      uptime: DateTime.diff(DateTime.utc_now(), state.started_at, :second),
      active_alerts: length(state.alerts),
      metrics: get_current_metrics(state)
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:metrics_summary, _from, state) do
    summary =
      state.metrics
      |> Enum.map(fn {metric, values} ->
        {metric, calculate_statistics(values)}
      end)
      |> Map.new()

    {:reply, summary, state}
  end

  @impl true
  def handle_call({:recent_alerts, limit}, _from, state) do
    alerts = Enum.take(state.alerts, limit)
    {:reply, alerts, state}
  end

  @impl true
  def handle_call({:update_thresholds, metric_type, warning, critical}, _from, state) do
    new_thresholds =
      Map.put(state.thresholds, metric_type, %{
        warning: warning,
        critical: critical
      })

    {:reply, :ok, %{state | thresholds: new_thresholds}}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Perform periodic health check
    new_state =
      state
      |> collect_system_metrics()
      |> update_health_status()

    # Emit health status telemetry
    :telemetry.execute(
      [:rubber_duck, :status, :monitor, :health],
      %{health_score: calculate_health_score(new_state)},
      %{status: new_state.health_status}
    )

    schedule_health_check()
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:telemetry_event, measurements, metadata}, state) do
    # Handle telemetry events from status system
    new_state = process_telemetry_event(state, measurements, metadata)
    {:noreply, new_state}
  end

  # Private Functions

  defp attach_telemetry_handlers do
    # Telemetry is handled elsewhere
  end

  defp process_telemetry_event(state, measurements, metadata) do
    cond do
      Map.has_key?(measurements, :batch_size) ->
        # Calculate throughput from batch processing
        throughput = Map.get(measurements, :throughput, 0)
        update_metric(state, :throughput, throughput)

      Map.has_key?(measurements, :latency_ms) ->
        # Record broadcast latency
        update_metric(state, :latency, measurements.latency_ms)

      Map.has_key?(measurements, :depth) ->
        # Record queue depth
        update_metric(state, :queue_depth, measurements.depth)

      Map.get(metadata, :error_type) ->
        # Increment error count
        update_error_rate(state)

      true ->
        state
    end
  end

  defp update_metric(state, metric_type, value) do
    current_values = Map.get(state.metrics, metric_type, [])

    # Keep only the most recent values (sliding window)
    new_values =
      [value | current_values]
      |> Enum.take(@metric_window)

    put_in(state.metrics[metric_type], new_values)
  end

  defp update_error_rate(state) do
    # Simple error rate tracking - could be enhanced
    current_rate = List.first(state.metrics.error_rate, 0)
    # Increment by 0.1%
    new_rate = current_rate + 0.001

    update_metric(state, :error_rate, new_rate)
  end

  defp check_thresholds(state, metric_type) do
    values = Map.get(state.metrics, metric_type, [])

    case values do
      [] ->
        state

      [current | _] ->
        thresholds = Map.get(state.thresholds, metric_type)

        cond do
          exceeds_threshold?(metric_type, current, thresholds.critical) ->
            maybe_create_alert(state, metric_type, :critical, current)

          exceeds_threshold?(metric_type, current, thresholds.warning) ->
            maybe_create_alert(state, metric_type, :warning, current)

          true ->
            state
        end
    end
  end

  defp exceeds_threshold?(:throughput, value, threshold), do: value < threshold
  defp exceeds_threshold?(_metric_type, value, threshold), do: value > threshold

  defp maybe_create_alert(state, metric_type, level, value) do
    # Check if we're in cooldown period for this alert
    last_alert_time = get_in(state.last_alert_times, [metric_type, level])
    now = System.monotonic_time(:millisecond)

    if is_nil(last_alert_time) || now - last_alert_time > @alert_cooldown do
      alert = %{
        id: generate_alert_id(),
        metric_type: metric_type,
        level: level,
        value: value,
        threshold: get_in(state.thresholds, [metric_type, level]),
        timestamp: DateTime.utc_now(),
        message: format_alert_message(metric_type, level, value)
      }

      # Log the alert
      log_alert(alert)

      # Emit alert telemetry
      :telemetry.execute(
        [:rubber_duck, :status, :monitor, :alert],
        %{count: 1},
        alert
      )

      state
      |> update_in([:alerts], &[alert | &1])
      |> put_in([:last_alert_times, metric_type, level], now)
    else
      state
    end
  end

  defp update_health_status(state) do
    # Determine overall health based on active alerts
    critical_alerts = Enum.count(state.alerts, &(&1.level == :critical))
    warning_alerts = Enum.count(state.alerts, &(&1.level == :warning))

    health_status =
      cond do
        critical_alerts > 0 -> :unhealthy
        warning_alerts > 2 -> :degraded
        true -> :healthy
      end

    %{state | health_status: health_status}
  end

  defp collect_system_metrics(state) do
    # Collect current system metrics
    # This could be expanded to collect more system-level metrics
    state
  end

  defp calculate_statistics([]), do: %{count: 0}

  defp calculate_statistics(values) do
    %{
      count: length(values),
      current: List.first(values),
      average: Enum.sum(values) / length(values),
      min: Enum.min(values),
      max: Enum.max(values),
      p95: calculate_percentile(values, 0.95),
      p99: calculate_percentile(values, 0.99)
    }
  end

  defp calculate_percentile(values, percentile) do
    sorted = Enum.sort(values)
    index = round(percentile * (length(sorted) - 1))
    Enum.at(sorted, index)
  end

  defp calculate_health_score(state) do
    # Simple health score calculation (0-100)
    base_score = 100
    critical_penalty = Enum.count(state.alerts, &(&1.level == :critical)) * 30
    warning_penalty = Enum.count(state.alerts, &(&1.level == :warning)) * 10

    max(0, base_score - critical_penalty - warning_penalty)
  end

  defp get_current_metrics(state) do
    state.metrics
    |> Enum.map(fn {metric, values} ->
      {metric, List.first(values)}
    end)
    |> Enum.filter(fn {_, value} -> not is_nil(value) end)
    |> Map.new()
  end

  defp format_alert_message(:queue_depth, level, value) do
    "Status queue depth #{level}: #{value} messages"
  end

  defp format_alert_message(:throughput, level, value) do
    "Status throughput #{level}: #{Float.round(value, 2)} msg/s"
  end

  defp format_alert_message(:latency, level, value) do
    "Status broadcast latency #{level}: #{value}ms"
  end

  defp format_alert_message(:error_rate, level, value) do
    "Status error rate #{level}: #{Float.round(value * 100, 2)}%"
  end

  defp log_alert(%{level: :critical} = alert) do
    Logger.error("Status monitor alert: #{alert.message}")
  end

  defp log_alert(%{level: :warning} = alert) do
    Logger.warning("Status monitor alert: #{alert.message}")
  end

  defp log_alert(alert) do
    Logger.info("Status monitor alert: #{alert.message}")
  end

  defp generate_alert_id do
    "alert_#{System.unique_integer([:positive])}_#{System.monotonic_time(:microsecond)}"
  end

  defp schedule_health_check do
    # Every 30 seconds
    Process.send_after(self(), :health_check, 30_000)
  end
end
