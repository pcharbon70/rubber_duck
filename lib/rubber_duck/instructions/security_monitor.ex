defmodule RubberDuck.Instructions.SecurityMonitor do
  @moduledoc """
  Real-time security monitoring and threat detection.
  
  Monitors template processing for:
  - Attack patterns
  - Anomalous behavior
  - Security violations
  - User threat levels
  
  Implements sliding window analysis and adaptive threat scoring.
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Instructions.SecurityConfig
  
  ## Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Records a security event for monitoring.
  """
  def record_event(event_type, metadata) do
    GenServer.cast(__MODULE__, {:record_event, event_type, metadata})
  end
  
  @doc """
  Assesses the threat level for a user.
  """
  def assess_threat(user_id) do
    GenServer.call(__MODULE__, {:assess_threat, user_id})
  end
  
  @doc """
  Checks for anomalies in user behavior.
  """
  def check_anomalies(user_id) do
    GenServer.call(__MODULE__, {:check_anomalies, user_id})
  end
  
  @doc """
  Gets active security alerts.
  """
  def get_active_alerts do
    GenServer.call(__MODULE__, :get_active_alerts)
  end
  
  @doc """
  Configures alert thresholds.
  """
  def configure_alerts(config) do
    GenServer.call(__MODULE__, {:configure_alerts, config})
  end
  
  @doc """
  Counts recent events of a specific type.
  """
  def count_recent_events(event_type, opts \\ []) do
    GenServer.call(__MODULE__, {:count_recent_events, event_type, opts})
  end
  
  ## Server Implementation
  
  def init(opts) do
    # Initialize ETS tables
    ensure_table(:security_events, [:bag, :public, :named_table])
    ensure_table(:user_profiles, [:set, :public, :named_table])
    ensure_table(:anomaly_baselines, [:set, :public, :named_table])
    ensure_table(:active_alerts, [:set, :public, :named_table])
    
    # Schedule cleanup
    schedule_cleanup()
    
    # Load configuration
    monitoring_config = SecurityConfig.get_monitoring_config()
    alert_thresholds = SecurityConfig.get_alert_thresholds()
    
    state = %{
      config: %{
        injection_threshold: Keyword.get(opts, :injection_threshold, Map.get(alert_thresholds, :injection_threshold, 3)),
        anomaly_sensitivity: Keyword.get(opts, :anomaly_sensitivity, Map.get(alert_thresholds, :anomaly_sensitivity, :medium)),
        alert_cooldown: Keyword.get(opts, :alert_cooldown, Map.get(alert_thresholds, :alert_cooldown, 300))
      },
      monitoring_config: monitoring_config,
      started_at: System.system_time(:second)
    }
    
    {:ok, state}
  end
  
  def handle_cast({:record_event, event_type, metadata}, state) do
    timestamp = System.system_time(:second)
    user_id = Map.get(metadata, :user_id, "anonymous")
    
    # Store event
    event = {timestamp, user_id, event_type, metadata}
    :ets.insert(:security_events, event)
    
    # Update user profile
    update_user_profile(user_id, event_type, metadata)
    
    # Check for immediate threats
    check_immediate_threats(user_id, event_type, state)
    
    # Update anomaly baseline
    update_anomaly_baseline(user_id, event_type, metadata)
    
    # Emit telemetry
    emit_security_event(event_type, metadata)
    
    {:noreply, state}
  end
  
  def handle_call({:assess_threat, user_id}, _from, state) do
    threat_score = calculate_threat_score(user_id)
    threat_level = determine_threat_level(threat_score)
    
    assessment = case threat_level do
      :blocked -> {:blocked, "User has been blocked due to excessive security violations"}
      :critical -> {:critical, "Critical threat level - immediate action required"}
      :high -> {:high_risk, "High risk user - monitor closely"}
      :medium -> {:medium_risk, "Elevated risk - additional monitoring recommended"}
      :low -> {:low_risk, "Normal behavior patterns"}
    end
    
    {:reply, {:ok, assessment}, state}
  end
  
  def handle_call({:check_anomalies, user_id}, _from, state) do
    case detect_anomalies(user_id, state.config.anomaly_sensitivity) do
      {:anomaly, details} ->
        {:reply, {:anomaly_detected, details}, state}
      :normal ->
        {:reply, {:ok, :normal}, state}
    end
  end
  
  def handle_call(:get_active_alerts, _from, state) do
    alerts = :ets.tab2list(:active_alerts)
    |> Enum.map(fn {_alert_id, alert} -> alert end)
    |> Enum.filter(fn alert -> 
      alert.expires_at > System.system_time(:second)
    end)
    
    {:reply, {:ok, alerts}, state}
  end
  
  def handle_call({:configure_alerts, config}, _from, state) do
    new_config = Map.merge(state.config, config)
    {:reply, :ok, %{state | config: new_config}}
  end
  
  def handle_call({:count_recent_events, event_type, opts}, _from, state) do
    monitoring_config = SecurityConfig.get_monitoring_config()
    default_window = Map.get(monitoring_config, :window_size, 3600)
    window = Keyword.get(opts, :window, default_window)
    cutoff = System.system_time(:second) - window
    
    count = :ets.select_count(:security_events, [
      {
        {:"$1", :"$2", :"$3", :"$4"},
        [{:andalso, {:==, :"$3", event_type}, {:>, :"$1", cutoff}}],
        [true]
      }
    ])
    
    {:reply, count, state}
  end
  
  def handle_info(:cleanup, state) do
    cleanup_old_data()
    schedule_cleanup()
    {:noreply, state}
  end
  
  ## Private Functions
  
  defp update_user_profile(user_id, event_type, _metadata) do
    threat_weights = SecurityConfig.get_threat_weights()
    weight = Map.get(threat_weights, event_type, 0)
    
    case :ets.lookup(:user_profiles, user_id) do
      [{^user_id, profile}] ->
        updated_profile = %{profile |
          threat_score: max(0, profile.threat_score + weight),
          event_count: Map.update(profile.event_count, event_type, 1, &(&1 + 1)),
          last_seen: System.system_time(:second)
        }
        :ets.insert(:user_profiles, {user_id, updated_profile})
        
      [] ->
        profile = %{
          user_id: user_id,
          threat_score: max(0, weight),
          event_count: %{event_type => 1},
          first_seen: System.system_time(:second),
          last_seen: System.system_time(:second)
        }
        :ets.insert(:user_profiles, {user_id, profile})
    end
  end
  
  defp check_immediate_threats(user_id, event_type, state) do
    # Check injection attempt threshold
    if event_type == :injection_attempt do
      recent_attempts = count_user_events(user_id, :injection_attempt, 300)  # 5 minutes
      
      if recent_attempts >= state.config.injection_threshold do
        create_alert(:multiple_injection_attempts, %{
          user_id: user_id,
          count: recent_attempts,
          severity: :high
        })
        
        # Auto-block user if too many attempts
        if recent_attempts >= state.config.injection_threshold * 2 do
          block_user(user_id)
        end
      end
    end
  end
  
  defp update_anomaly_baseline(user_id, event_type, metadata) do
    # Simple baseline tracking - in production, use more sophisticated algorithms
    duration = Map.get(metadata, :duration, 0)
    
    case :ets.lookup(:anomaly_baselines, {user_id, event_type}) do
      [{key, baseline}] ->
        # Update running average and standard deviation
        new_count = baseline.count + 1
        new_mean = baseline.mean + (duration - baseline.mean) / new_count
        new_variance = baseline.variance + (duration - baseline.mean) * (duration - new_mean)
        
        updated_baseline = %{baseline |
          count: new_count,
          mean: new_mean,
          variance: new_variance,
          std_dev: :math.sqrt(new_variance / new_count)
        }
        :ets.insert(:anomaly_baselines, {key, updated_baseline})
        
      [] ->
        baseline = %{
          count: 1,
          mean: duration,
          variance: 0,
          std_dev: 0
        }
        :ets.insert(:anomaly_baselines, {{user_id, event_type}, baseline})
    end
  end
  
  defp detect_anomalies(user_id, sensitivity) do
    threshold = case sensitivity do
      :high -> 2.0
      :medium -> 3.0
      :low -> 4.0
    end
    
    # Check recent events for anomalies
    recent_events = get_user_recent_events(user_id, 300)  # Last 5 minutes
    
    anomalies = Enum.filter(recent_events, fn {_timestamp, _user, event_type, metadata} ->
      case :ets.lookup(:anomaly_baselines, {user_id, event_type}) do
        [{_key, baseline}] when baseline.count > 10 ->
          duration = Map.get(metadata, :duration, 0)
          deviation = abs(duration - baseline.mean) / max(baseline.std_dev, 1)
          deviation > threshold
          
        _ -> false
      end
    end)
    
    if length(anomalies) > 0 do
      {:anomaly, %{
        count: length(anomalies),
        events: Enum.map(anomalies, fn {_, _, type, _} -> type end)
      }}
    else
      :normal
    end
  end
  
  defp calculate_threat_score(user_id) do
    case :ets.lookup(:user_profiles, user_id) do
      [{^user_id, profile}] ->
        # Decay threat score over time
        time_since_last = System.system_time(:second) - profile.last_seen
        decay_factor = :math.exp(-time_since_last / 3600.0)  # 1 hour half-life
        
        round(profile.threat_score * decay_factor)
        
      [] -> 0
    end
  end
  
  defp determine_threat_level(score) do
    threat_levels = SecurityConfig.get_threat_levels()
    Enum.find_value(threat_levels, fn {level, range} ->
      if score in range, do: level
    end) || :low
  end
  
  defp count_user_events(user_id, event_type, window) do
    cutoff = System.system_time(:second) - window
    
    :ets.select_count(:security_events, [
      {
        {:"$1", :"$2", :"$3", :"$4"},
        [{:andalso, 
          {:andalso, {:==, :"$2", user_id}, {:==, :"$3", event_type}},
          {:>, :"$1", cutoff}
        }],
        [true]
      }
    ])
  end
  
  defp get_user_recent_events(user_id, window) do
    cutoff = System.system_time(:second) - window
    
    :ets.select(:security_events, [
      {
        {:"$1", :"$2", :"$3", :"$4"},
        [{:andalso, {:==, :"$2", user_id}, {:>, :"$1", cutoff}}],
        [:"$_"]
      }
    ])
  end
  
  defp create_alert(type, details) do
    alert_id = :crypto.strong_rand_bytes(16) |> Base.encode16()
    
    alert = %{
      id: alert_id,
      type: type,
      details: details,
      created_at: System.system_time(:second),
      expires_at: System.system_time(:second) + 3600  # 1 hour
    }
    
    :ets.insert(:active_alerts, {alert_id, alert})
    
    # Log alert
    Logger.warning("Security alert created: #{type} - #{inspect(details)}")
    
    # Emit telemetry
    :telemetry.execute(
      [:rubber_duck, :instructions, :security, :alert],
      %{count: 1},
      %{type: type, severity: Map.get(details, :severity, :medium)}
    )
  end
  
  defp block_user(user_id) do
    case :ets.lookup(:user_profiles, user_id) do
      [{^user_id, profile}] ->
        updated_profile = %{profile | threat_score: 1000}  # Max threat score
        :ets.insert(:user_profiles, {user_id, updated_profile})
        
        create_alert(:user_blocked, %{
          user_id: user_id,
          reason: "Excessive security violations",
          severity: :critical
        })
        
      [] -> :ok
    end
  end
  
  def cleanup_old_data do
    monitoring_config = SecurityConfig.get_monitoring_config()
    window_size = Map.get(monitoring_config, :window_size, 3600)
    cutoff = System.system_time(:second) - window_size
    
    # Clean old events
    :ets.select_delete(:security_events, [
      {
        {:"$1", :"$2", :"$3", :"$4"},
        [{:<, :"$1", cutoff}],
        [true]
      }
    ])
    
    # Clean expired alerts
    :ets.select_delete(:active_alerts, [
      {
        {:"$1", :"$2"},
        [{:<, {:map_get, :expires_at, :"$2"}, System.system_time(:second)}],
        [true]
      }
    ])
  end
  
  defp schedule_cleanup do
    monitoring_config = SecurityConfig.get_monitoring_config()
    cleanup_interval = Map.get(monitoring_config, :cleanup_interval, 300_000)
    Process.send_after(self(), :cleanup, cleanup_interval)
  end
  
  defp ensure_table(name, opts) do
    case :ets.whereis(name) do
      :undefined -> :ets.new(name, opts)
      _tid -> name
    end
  end

  defp emit_security_event(event_type, metadata) do
    :telemetry.execute(
      [:rubber_duck, :instructions, :security, :event],
      %{count: 1},
      Map.merge(metadata, %{event_type: event_type})
    )
  end
end