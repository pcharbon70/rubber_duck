defmodule RubberDuck.Tool.Security.Monitor do
  @moduledoc """
  Security monitoring and alerting system.

  Features:
  - Anomaly detection using statistical analysis
  - Pattern matching for known attack signatures
  - Real-time alerting for security events
  - Integration with telemetry and metrics
  """

  use GenServer

  require Logger

  @type security_event :: %{
          type: atom(),
          severity: :low | :medium | :high | :critical,
          timestamp: DateTime.t(),
          source: map(),
          details: map(),
          matched_patterns: [String.t()]
        }

  @type alert :: %{
          id: String.t(),
          event: security_event(),
          actions_taken: [atom()],
          notified: boolean()
        }

  # Attack patterns
  @attack_patterns %{
    path_traversal: [
      ~r/\.\.\/|\.\.\\/,
      ~r/%2e%2e%2f/i,
      ~r/\x00/
    ],
    command_injection: [
      ~r/;\s*rm\s+-rf/,
      ~r/;\s*cat\s+\/etc\/passwd/,
      ~r/\|\s*nc\s+/,
      ~r/&&\s*wget\s+/
    ],
    sql_injection: [
      ~r/'\s*or\s+'1'\s*=\s*'1/i,
      ~r/union\s+select/i,
      ~r/exec\s*\(/i
    ],
    # Analyzed statistically
    rapid_requests: :dynamic,
    privilege_escalation: :dynamic,
    resource_exhaustion: :dynamic
  }

  # Thresholds for anomaly detection
  @anomaly_thresholds %{
    requests_per_minute: 60,
    failed_auth_attempts: 5,
    error_rate: 0.1,
    # 2x normal
    resource_usage_spike: 2.0
  }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a security-relevant event for monitoring.
  """
  def record_event(type, source, details) do
    GenServer.cast(__MODULE__, {:record_event, type, source, details})
  end

  @doc """
  Checks if a value matches any attack patterns.
  """
  def check_patterns(value, pattern_type \\ :all) do
    GenServer.call(__MODULE__, {:check_patterns, value, pattern_type})
  end

  @doc """
  Gets recent security alerts.
  """
  def get_alerts(filter \\ %{}) do
    GenServer.call(__MODULE__, {:get_alerts, filter})
  end

  @doc """
  Gets security statistics and metrics.
  """
  def get_stats(time_range \\ :hour) do
    GenServer.call(__MODULE__, {:get_stats, time_range})
  end

  @doc """
  Registers a custom alert handler.
  """
  def register_alert_handler(handler_fun) when is_function(handler_fun, 1) do
    GenServer.call(__MODULE__, {:register_handler, handler_fun})
  end

  @doc """
  Updates anomaly detection thresholds.
  """
  def update_thresholds(new_thresholds) do
    GenServer.call(__MODULE__, {:update_thresholds, new_thresholds})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    # Create ETS tables
    :ets.new(:security_events, [:ordered_set, :public, :named_table])
    :ets.new(:security_alerts, [:set, :public, :named_table])
    :ets.new(:security_stats, [:set, :public, :named_table])
    :ets.new(:user_behavior, [:set, :public, :named_table])

    state = %{
      thresholds: Keyword.get(opts, :thresholds, @anomaly_thresholds),
      alert_handlers: Keyword.get(opts, :alert_handlers, []),
      monitoring_enabled: Keyword.get(opts, :enabled, true),
      # 1 hour
      baseline_window: Keyword.get(opts, :baseline_window, 3_600_000),
      # 5 minutes
      alert_cooldown: Keyword.get(opts, :alert_cooldown, 300_000)
    }

    # Schedule periodic analysis
    if state.monitoring_enabled do
      Process.send_after(self(), :analyze_patterns, 10_000)
      Process.send_after(self(), :update_baselines, 60_000)
    end

    {:ok, state}
  end

  @impl true
  def handle_cast({:record_event, type, source, details}, state) do
    if state.monitoring_enabled do
      event = build_event(type, source, details)

      # Store event
      store_event(event)

      # Update user behavior tracking
      update_user_behavior(event)

      # Check for attack patterns
      patterns = check_event_patterns(event)
      event = %{event | matched_patterns: patterns}

      # Determine severity
      severity = calculate_severity(event)
      event = %{event | severity: severity}

      # Check if alert needed
      if should_alert?(event, state) do
        create_alert(event, state)
      end

      # Update statistics
      update_stats(event)
    end

    {:noreply, state}
  end

  @impl true
  def handle_call({:check_patterns, value, pattern_type}, _from, state) do
    patterns =
      if pattern_type == :all do
        @attack_patterns
      else
        Map.get(@attack_patterns, pattern_type, %{})
      end

    matched = check_value_patterns(value, patterns)
    {:reply, matched, state}
  end

  @impl true
  def handle_call({:get_alerts, filter}, _from, state) do
    alerts = get_filtered_alerts(filter)
    {:reply, {:ok, alerts}, state}
  end

  @impl true
  def handle_call({:get_stats, time_range}, _from, state) do
    stats = compile_stats(time_range)
    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_call({:register_handler, handler}, _from, state) do
    updated_state = %{state | alert_handlers: [handler | state.alert_handlers]}
    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call({:update_thresholds, new_thresholds}, _from, state) do
    updated_thresholds = Map.merge(state.thresholds, new_thresholds)
    {:reply, :ok, %{state | thresholds: updated_thresholds}}
  end

  @impl true
  def handle_info(:analyze_patterns, state) do
    # Analyze recent events for anomalies
    analyze_anomalies(state)

    # Schedule next analysis
    Process.send_after(self(), :analyze_patterns, 10_000)

    {:noreply, state}
  end

  @impl true
  def handle_info(:update_baselines, state) do
    # Update behavior baselines
    update_behavior_baselines(state)

    # Schedule next update
    Process.send_after(self(), :update_baselines, 60_000)

    {:noreply, state}
  end

  # Private functions

  defp build_event(type, source, details) do
    %{
      id: generate_event_id(),
      type: type,
      # Will be updated
      severity: :low,
      timestamp: DateTime.utc_now(),
      source: source,
      details: details,
      matched_patterns: []
    }
  end

  defp store_event(event) do
    key = {event.timestamp, event.id}
    :ets.insert(:security_events, {key, event})

    # Telemetry
    :telemetry.execute(
      [:rubber_duck, :security, :event],
      %{count: 1},
      %{type: event.type, severity: event.severity}
    )
  end

  defp update_user_behavior(event) do
    user_id = get_in(event.source, [:user_id]) || "anonymous"

    behavior =
      case :ets.lookup(:user_behavior, user_id) do
        [{^user_id, data}] ->
          data

        [] ->
          %{
            request_times: [],
            error_count: 0,
            success_count: 0,
            tools_used: MapSet.new(),
            first_seen: event.timestamp
          }
      end

    # Update behavior data
    updated = %{
      behavior
      | request_times: [event.timestamp | Enum.take(behavior.request_times, 99)],
        error_count: behavior.error_count + if(event.type == :error, do: 1, else: 0),
        success_count: behavior.success_count + if(event.type == :success, do: 1, else: 0),
        tools_used: MapSet.put(behavior.tools_used, event.source[:tool])
    }

    :ets.insert(:user_behavior, {user_id, updated})
  end

  defp check_event_patterns(event) do
    # Check various fields for patterns
    fields_to_check = [
      get_in(event.details, [:params]),
      get_in(event.details, [:error_message]),
      get_in(event.details, [:command]),
      get_in(event.details, [:query])
    ]

    Enum.flat_map(fields_to_check, fn field ->
      if field do
        check_value_patterns(field, @attack_patterns)
      else
        []
      end
    end)
    |> Enum.uniq()
  end

  defp check_value_patterns(value, patterns) when is_binary(value) do
    Enum.flat_map(patterns, fn
      {pattern_name, pattern_list} when is_list(pattern_list) ->
        if Enum.any?(pattern_list, &Regex.match?(&1, value)) do
          [pattern_name]
        else
          []
        end

      _ ->
        []
    end)
  end

  defp check_value_patterns(value, patterns) when is_map(value) do
    value
    |> Map.values()
    |> Enum.flat_map(&check_value_patterns(&1, patterns))
    |> Enum.uniq()
  end

  defp check_value_patterns(_, _), do: []

  defp calculate_severity(event) do
    cond do
      # Critical patterns
      :command_injection in event.matched_patterns -> :critical
      :sql_injection in event.matched_patterns -> :critical
      # High severity patterns
      :path_traversal in event.matched_patterns -> :high
      event.type == :unauthorized_access -> :high
      # Medium severity
      event.type == :rate_limit_exceeded -> :medium
      event.type == :invalid_input -> :medium
      # Default
      true -> :low
    end
  end

  defp should_alert?(event, state) do
    # Check severity threshold
    severity_score = severity_to_score(event.severity)

    # Check for cooldown
    last_alert = get_last_alert_time(event.type, event.source[:user_id])

    cooldown_passed =
      is_nil(last_alert) or
        DateTime.diff(event.timestamp, last_alert, :millisecond) > state.alert_cooldown

    severity_score >= 2 and cooldown_passed
  end

  defp severity_to_score(:critical), do: 4
  defp severity_to_score(:high), do: 3
  defp severity_to_score(:medium), do: 2
  defp severity_to_score(:low), do: 1

  defp create_alert(event, state) do
    alert = %{
      id: generate_alert_id(),
      event: event,
      actions_taken: [],
      notified: false,
      created_at: DateTime.utc_now()
    }

    # Take automatic actions based on severity
    actions = determine_actions(event)
    alert = %{alert | actions_taken: actions}

    # Store alert
    :ets.insert(:security_alerts, {alert.id, alert})

    # Notify handlers
    Enum.each(state.alert_handlers, fn handler ->
      Task.start(fn -> handler.(alert) end)
    end)

    # Log alert
    Logger.warning("Security alert: #{inspect(alert)}")

    # Update alert with notification status
    :ets.insert(:security_alerts, {alert.id, %{alert | notified: true}})
  end

  defp determine_actions(event) do
    case event.severity do
      :critical ->
        [:block_user, :notify_admin, :log_detailed]

      :high ->
        [:rate_limit, :notify_admin, :log_detailed]

      :medium ->
        [:log_detailed, :increment_counter]

      :low ->
        [:log_basic]
    end
  end

  defp get_last_alert_time(type, user_id) do
    recent_alerts =
      :ets.tab2list(:security_alerts)
      |> Enum.map(fn {_, alert} -> alert end)
      |> Enum.filter(fn alert ->
        alert.event.type == type and
          get_in(alert.event.source, [:user_id]) == user_id
      end)
      |> Enum.sort_by(& &1.created_at, {:desc, DateTime})

    case recent_alerts do
      [latest | _] -> latest.created_at
      [] -> nil
    end
  end

  defp analyze_anomalies(state) do
    # Get recent events
    # Last 10 minutes
    cutoff = DateTime.add(DateTime.utc_now(), -600, :second)
    recent_events = get_recent_events(cutoff)

    # Group by user
    by_user = Enum.group_by(recent_events, &get_in(&1.source, [:user_id]))

    # Check each user for anomalies
    Enum.each(by_user, fn {user_id, events} ->
      check_user_anomalies(user_id, events, state)
    end)
  end

  defp check_user_anomalies(user_id, events, state) do
    # Request rate anomaly
    request_count = length(events)

    if request_count > state.thresholds.requests_per_minute * 10 do
      record_event(:anomaly_detected, %{user_id: user_id}, %{
        type: :rapid_requests,
        count: request_count,
        threshold: state.thresholds.requests_per_minute * 10
      })
    end

    # Error rate anomaly
    errors = Enum.count(events, &(&1.type == :error))

    if errors > 0 do
      error_rate = errors / request_count

      if error_rate > state.thresholds.error_rate do
        record_event(:anomaly_detected, %{user_id: user_id}, %{
          type: :high_error_rate,
          rate: error_rate,
          threshold: state.thresholds.error_rate
        })
      end
    end

    # Pattern anomaly - multiple different attack patterns from same user
    all_patterns =
      events
      |> Enum.flat_map(& &1.matched_patterns)
      |> Enum.uniq()

    if length(all_patterns) > 2 do
      record_event(:anomaly_detected, %{user_id: user_id}, %{
        type: :multiple_attack_patterns,
        patterns: all_patterns
      })
    end
  end

  defp update_behavior_baselines(_state) do
    # Calculate baselines from historical data
    all_users = :ets.tab2list(:user_behavior)

    global_stats =
      Enum.reduce(
        all_users,
        %{
          avg_request_rate: 0,
          avg_error_rate: 0,
          common_tools: MapSet.new()
        },
        fn {_, behavior}, acc ->
          request_rate = calculate_request_rate(behavior.request_times)

          error_rate =
            if behavior.success_count > 0 do
              behavior.error_count / (behavior.error_count + behavior.success_count)
            else
              0
            end

          %{
            acc
            | avg_request_rate: acc.avg_request_rate + request_rate,
              avg_error_rate: acc.avg_error_rate + error_rate,
              common_tools: MapSet.union(acc.common_tools, behavior.tools_used)
          }
        end
      )

    # Store baselines
    if length(all_users) > 0 do
      :ets.insert(
        :security_stats,
        {:baselines,
         %{
           avg_request_rate: global_stats.avg_request_rate / length(all_users),
           avg_error_rate: global_stats.avg_error_rate / length(all_users),
           common_tools: MapSet.to_list(global_stats.common_tools),
           updated_at: DateTime.utc_now()
         }}
      )
    end
  end

  defp calculate_request_rate([]), do: 0
  defp calculate_request_rate([_]), do: 1

  defp calculate_request_rate(timestamps) do
    # Calculate average requests per minute
    sorted = Enum.sort(timestamps, {:asc, DateTime})
    first = List.first(sorted)
    last = List.last(sorted)

    duration_minutes = DateTime.diff(last, first, :second) / 60

    if duration_minutes > 0 do
      length(timestamps) / duration_minutes
    else
      length(timestamps)
    end
  end

  defp get_recent_events(cutoff) do
    :ets.foldl(
      fn
        {{timestamp, _}, event}, acc ->
          if DateTime.compare(timestamp, cutoff) == :gt do
            [event | acc]
          else
            acc
          end
      end,
      [],
      :security_events
    )
  end

  defp get_filtered_alerts(filter) do
    all_alerts =
      :ets.tab2list(:security_alerts)
      |> Enum.map(fn {_, alert} -> alert end)

    all_alerts
    |> filter_by_severity(filter[:severity])
    |> filter_by_time(filter[:from], filter[:to])
    |> filter_by_user(filter[:user_id])
    |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
    |> Enum.take(filter[:limit] || 100)
  end

  defp filter_by_severity(alerts, nil), do: alerts

  defp filter_by_severity(alerts, severity) do
    Enum.filter(alerts, &(&1.event.severity == severity))
  end

  defp filter_by_time(alerts, nil, nil), do: alerts

  defp filter_by_time(alerts, from, to) do
    Enum.filter(alerts, fn alert ->
      (is_nil(from) or DateTime.compare(alert.created_at, from) != :lt) and
        (is_nil(to) or DateTime.compare(alert.created_at, to) != :gt)
    end)
  end

  defp filter_by_user(alerts, nil), do: alerts

  defp filter_by_user(alerts, user_id) do
    Enum.filter(alerts, &(get_in(&1.event.source, [:user_id]) == user_id))
  end

  defp compile_stats(time_range) do
    cutoff =
      case time_range do
        :minute -> DateTime.add(DateTime.utc_now(), -60, :second)
        :hour -> DateTime.add(DateTime.utc_now(), -3600, :second)
        :day -> DateTime.add(DateTime.utc_now(), -86400, :second)
        _ -> DateTime.add(DateTime.utc_now(), -3600, :second)
      end

    recent_events = get_recent_events(cutoff)

    recent_alerts =
      :ets.tab2list(:security_alerts)
      |> Enum.map(fn {_, alert} -> alert end)
      |> Enum.filter(&(DateTime.compare(&1.created_at, cutoff) == :gt))

    %{
      total_events: length(recent_events),
      total_alerts: length(recent_alerts),
      events_by_type: Enum.frequencies_by(recent_events, & &1.type),
      events_by_severity: Enum.frequencies_by(recent_events, & &1.severity),
      alerts_by_severity: Enum.frequencies_by(recent_alerts, & &1.event.severity),
      top_patterns: top_patterns(recent_events),
      active_users: count_active_users(recent_events)
    }
  end

  defp top_patterns(events) do
    events
    |> Enum.flat_map(& &1.matched_patterns)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(10)
  end

  defp count_active_users(events) do
    events
    |> Enum.map(&get_in(&1.source, [:user_id]))
    |> Enum.uniq()
    |> length()
  end

  defp update_stats(event) do
    # Update hourly stats
    hour_key = DateTime.utc_now() |> DateTime.truncate(:hour)

    stats =
      case :ets.lookup(:security_stats, {:hourly, hour_key}) do
        [{_, s}] -> s
        [] -> %{events: 0, alerts: 0, by_type: %{}, by_severity: %{}}
      end

    updated = %{
      stats
      | events: stats.events + 1,
        by_type: Map.update(stats.by_type, event.type, 1, &(&1 + 1)),
        by_severity: Map.update(stats.by_severity, event.severity, 1, &(&1 + 1))
    }

    :ets.insert(:security_stats, {{:hourly, hour_key}, updated})
  end

  defp generate_event_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end

  defp generate_alert_id do
    "alert_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16())
  end
end
