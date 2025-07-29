defmodule RubberDuck.Jido.Agents.HealthMonitor do
  @moduledoc """
  Comprehensive health monitoring system for agents.
  
  Provides:
  - Standardized health check protocol
  - Liveness, readiness, and startup probes
  - Circuit breaker functionality
  - Health aggregation and reporting
  - Alert triggering
  - SLA monitoring
  
  ## Usage
  
      # Start health monitoring
      {:ok, _} = HealthMonitor.start_link()
      
      # Monitor an agent
      HealthMonitor.monitor_agent("agent_123",
        check_interval: 5000,
        timeout: 2000,
        failure_threshold: 3
      )
      
      # Get health status
      {:ok, status} = HealthMonitor.get_health("agent_123")
      
      # Get aggregate health
      health_report = HealthMonitor.health_report()
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Jido.Agents.Registry
  
  @default_config %{
    check_interval: 10_000,      # 10 seconds
    timeout: 5_000,              # 5 seconds
    failure_threshold: 3,        # failures before unhealthy
    recovery_threshold: 2,       # successes before healthy
    startup_grace_period: 30_000, # 30 seconds
    circuit_breaker_enabled: true,
    circuit_open_duration: 60_000, # 1 minute
    circuit_half_open_checks: 3,
    alert_threshold: 5           # consecutive failures before alert
  }
  
  @probe_types [:liveness, :readiness, :startup]
  
  # Client API
  
  @doc """
  Starts the health monitor.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Starts monitoring an agent.
  """
  def monitor_agent(agent_id, opts \\ []) when is_binary(agent_id) do
    GenServer.call(__MODULE__, {:monitor, agent_id, opts})
  end
  
  @doc """
  Stops monitoring an agent.
  """
  def stop_monitoring(agent_id) when is_binary(agent_id) do
    GenServer.call(__MODULE__, {:stop_monitoring, agent_id})
  end
  
  @doc """
  Gets the health status of an agent.
  """
  def get_health(agent_id) when is_binary(agent_id) do
    GenServer.call(__MODULE__, {:get_health, agent_id})
  end
  
  @doc """
  Performs a specific probe on an agent.
  """
  def probe(agent_id, probe_type) when probe_type in @probe_types do
    GenServer.call(__MODULE__, {:probe, agent_id, probe_type})
  end
  
  @doc """
  Gets aggregate health report.
  """
  def health_report do
    GenServer.call(__MODULE__, :health_report)
  end
  
  @doc """
  Updates monitoring configuration for an agent.
  """
  def update_config(agent_id, updates) when is_binary(agent_id) and is_map(updates) do
    GenServer.call(__MODULE__, {:update_config, agent_id, updates})
  end
  
  @doc """
  Manually triggers a circuit breaker.
  """
  def trip_circuit(agent_id) when is_binary(agent_id) do
    GenServer.call(__MODULE__, {:trip_circuit, agent_id})
  end
  
  @doc """
  Resets a circuit breaker.
  """
  def reset_circuit(agent_id) when is_binary(agent_id) do
    GenServer.call(__MODULE__, {:reset_circuit, agent_id})
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # ETS tables for fast lookups (create only if they don't exist)
    ensure_table(:agent_health_status)
    ensure_table(:agent_health_history)
    ensure_table(:circuit_breakers)
    
    state = %{
      monitors: %{},          # agent_id => monitor_ref
      configs: %{},           # agent_id => config
      check_timers: %{},      # agent_id => timer_ref
      startup_timers: %{},    # agent_id => timer_ref
      alert_counts: %{}       # agent_id => consecutive_failures
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:monitor, agent_id, opts}, _from, state) do
    config = Map.merge(@default_config, Map.new(opts))
    
    # Initialize health status
    :ets.insert(:agent_health_status, {agent_id, %{
      status: :unknown,
      liveness: :unknown,
      readiness: :unknown,
      startup: :pending,
      last_check: nil,
      consecutive_failures: 0,
      consecutive_successes: 0,
      circuit_state: :closed,
      details: %{}
    }})
    
    # Initialize history
    :ets.insert(:agent_health_history, {agent_id, []})
    
    # Monitor the agent process
    case Registry.get_agent(agent_id) do
      {:ok, agent_info} ->
        ref = Process.monitor(agent_info.pid)
        
        # Start health check timer
        timer_ref = schedule_health_check(agent_id, config.check_interval)
        
        # Start startup grace period timer
        startup_ref = if config.startup_grace_period > 0 do
          Process.send_after(self(), {:startup_complete, agent_id}, config.startup_grace_period)
        end
        
        new_state = %{state |
          monitors: Map.put(state.monitors, agent_id, ref),
          configs: Map.put(state.configs, agent_id, config),
          check_timers: Map.put(state.check_timers, agent_id, timer_ref),
          startup_timers: Map.put(state.startup_timers, agent_id, startup_ref)
        }
        
        # Perform initial health check
        perform_health_check(agent_id, agent_info.pid, config)
        
        {:reply, :ok, new_state}
        
      {:error, :not_found} ->
        {:reply, {:error, :agent_not_found}, state}
    end
  end
  
  @impl true
  def handle_call({:stop_monitoring, agent_id}, _from, state) do
    # Cancel timers
    if timer_ref = Map.get(state.check_timers, agent_id) do
      Process.cancel_timer(timer_ref)
    end
    
    if startup_ref = Map.get(state.startup_timers, agent_id) do
      Process.cancel_timer(startup_ref)
    end
    
    # Demonitor process
    if ref = Map.get(state.monitors, agent_id) do
      Process.demonitor(ref, [:flush])
    end
    
    # Clean up state
    new_state = %{state |
      monitors: Map.delete(state.monitors, agent_id),
      configs: Map.delete(state.configs, agent_id),
      check_timers: Map.delete(state.check_timers, agent_id),
      startup_timers: Map.delete(state.startup_timers, agent_id),
      alert_counts: Map.delete(state.alert_counts, agent_id)
    }
    
    # Clean up ETS
    :ets.delete(:agent_health_status, agent_id)
    :ets.delete(:agent_health_history, agent_id)
    :ets.delete(:circuit_breakers, agent_id)
    
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call({:get_health, agent_id}, _from, state) do
    case :ets.lookup(:agent_health_status, agent_id) do
      [{^agent_id, status}] -> {:reply, {:ok, status}, state}
      [] -> {:reply, {:error, :not_monitored}, state}
    end
  end
  
  @impl true
  def handle_call({:probe, agent_id, probe_type}, _from, state) do
    case Registry.get_agent(agent_id) do
      {:ok, agent_info} ->
        config = Map.get(state.configs, agent_id, @default_config)
        result = perform_probe(agent_info.pid, probe_type, config)
        {:reply, result, state}
        
      {:error, _} = error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call(:health_report, _from, state) do
    # Collect all health statuses
    all_statuses = :ets.match_object(:agent_health_status, {:_, :_})
    
    report = %{
      total_agents: length(all_statuses),
      healthy: count_by_status(all_statuses, :healthy),
      unhealthy: count_by_status(all_statuses, :unhealthy),
      unknown: count_by_status(all_statuses, :unknown),
      circuit_open: count_circuit_state(all_statuses, :open),
      circuit_half_open: count_circuit_state(all_statuses, :half_open),
      by_agent: Map.new(all_statuses),
      timestamp: DateTime.utc_now()
    }
    
    {:reply, report, state}
  end
  
  @impl true
  def handle_call({:update_config, agent_id, updates}, _from, state) do
    case Map.get(state.configs, agent_id) do
      nil ->
        {:reply, {:error, :not_monitored}, state}
        
      current_config ->
        new_config = Map.merge(current_config, updates)
        new_state = %{state | configs: Map.put(state.configs, agent_id, new_config)}
        
        # Reschedule health check if interval changed
        if updates[:check_interval] && updates.check_interval != current_config.check_interval do
          if timer_ref = Map.get(state.check_timers, agent_id) do
            Process.cancel_timer(timer_ref)
          end
          
          new_timer = schedule_health_check(agent_id, new_config.check_interval)
          %{new_state | check_timers: Map.put(new_state.check_timers, agent_id, new_timer)}
        end
        
        {:reply, :ok, new_state}
    end
  end
  
  @impl true
  def handle_call({:trip_circuit, agent_id}, _from, state) do
    update_circuit_state(agent_id, :open)
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call({:reset_circuit, agent_id}, _from, state) do
    update_circuit_state(agent_id, :closed)
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_info({:check_health, agent_id}, state) do
    case Registry.get_agent(agent_id) do
      {:ok, agent_info} ->
        config = Map.get(state.configs, agent_id, @default_config)
        perform_health_check(agent_id, agent_info.pid, config)
        
        # Schedule next check
        timer_ref = schedule_health_check(agent_id, config.check_interval)
        new_state = %{state | check_timers: Map.put(state.check_timers, agent_id, timer_ref)}
        {:noreply, new_state}
        
      {:error, _} ->
        # Agent no longer exists, stop monitoring
        handle_call({:stop_monitoring, agent_id}, nil, state)
    end
  end
  
  @impl true
  def handle_info({:startup_complete, agent_id}, state) do
    # Mark startup probe as complete
    case :ets.lookup(:agent_health_status, agent_id) do
      [{^agent_id, status}] ->
        updated_status = %{status | startup: :complete}
        :ets.insert(:agent_health_status, {agent_id, updated_status})
        
      [] ->
        :ok
    end
    
    {:noreply, %{state | startup_timers: Map.delete(state.startup_timers, agent_id)}}
  end
  
  @impl true
  def handle_info({:circuit_timeout, agent_id}, state) do
    # Move circuit from open to half-open
    update_circuit_state(agent_id, :half_open)
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    # Find which agent this monitor belongs to
    case Enum.find(state.monitors, fn {_, monitor_ref} -> monitor_ref == ref end) do
      {agent_id, _} ->
        Logger.warning("Monitored agent #{agent_id} died: #{inspect(reason)}")
        
        # Cancel timers first to prevent further health checks
        if timer_ref = Map.get(state.check_timers, agent_id) do
          Process.cancel_timer(timer_ref)
        end
        
        if startup_ref = Map.get(state.startup_timers, agent_id) do
          Process.cancel_timer(startup_ref)
        end
        
        # Update health status to dead
        mark_agent_down(agent_id, reason)
        
        # Clean up state
        new_state = %{state |
          monitors: Map.delete(state.monitors, agent_id),
          configs: Map.delete(state.configs, agent_id),
          check_timers: Map.delete(state.check_timers, agent_id),
          startup_timers: Map.delete(state.startup_timers, agent_id),
          alert_counts: Map.delete(state.alert_counts, agent_id)
        }
        
        {:noreply, new_state}
        
      nil ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Handle Task responses
    Logger.debug("Received task result: #{inspect(result)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("HealthMonitor received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
  
  # Private functions
  
  defp schedule_health_check(agent_id, interval) do
    Process.send_after(self(), {:check_health, agent_id}, interval)
  end
  
  defp perform_health_check(agent_id, pid, config) do
    Task.async(fn ->
      # Check circuit breaker first
      case get_circuit_state(agent_id) do
        :open ->
          # Circuit is open, skip check
          :circuit_open
          
        circuit_state ->
          # Perform all probes
          start_time = System.monotonic_time(:millisecond)
          
          liveness = perform_probe(pid, :liveness, config)
          readiness = perform_probe(pid, :readiness, config)
          startup = get_startup_status(agent_id)
          
          duration = System.monotonic_time(:millisecond) - start_time
          
          # Update status based on results
          update_health_status(agent_id, %{
            liveness: liveness,
            readiness: readiness,
            startup: startup,
            duration: duration,
            circuit_state: circuit_state
          }, config)
      end
    end)
  end
  
  defp perform_probe(pid, probe_type, config) do
    try do
      case GenServer.call(pid, {:health_probe, probe_type}, config.timeout) do
        {:ok, details} -> {:healthy, details}
        {:error, reason} -> {:unhealthy, reason}
        _ -> {:unhealthy, :invalid_response}
      end
    catch
      :exit, {:timeout, _} -> {:unhealthy, :timeout}
      :exit, reason -> {:unhealthy, {:exit, reason}}
      error -> {:unhealthy, {:error, error}}
    end
  end
  
  defp get_startup_status(agent_id) do
    case :ets.lookup(:agent_health_status, agent_id) do
      [{^agent_id, %{startup: status}}] -> status
      _ -> :pending
    end
  end
  
  defp update_health_status(agent_id, probe_results, config) do
    # Get current status
    current = case :ets.lookup(:agent_health_status, agent_id) do
      [{^agent_id, status}] -> status
      [] -> %{consecutive_failures: 0, consecutive_successes: 0}
    end
    
    # Determine overall health
    is_healthy = match?({:healthy, _}, probe_results.liveness) and
                 (match?({:healthy, _}, probe_results.readiness) or probe_results.startup == :pending)
    
    # Update consecutive counts
    {failures, successes} = if is_healthy do
      {0, current.consecutive_successes + 1}
    else
      {current.consecutive_failures + 1, 0}
    end
    
    # Determine status based on thresholds
    status = cond do
      failures >= config.failure_threshold -> :unhealthy
      successes >= config.recovery_threshold -> :healthy
      true -> current[:status] || :unknown
    end
    
    # Handle circuit breaker
    circuit_state = handle_circuit_breaker(
      agent_id,
      probe_results.circuit_state,
      is_healthy,
      failures,
      config
    )
    
    # Check for alerts
    check_alerts(agent_id, failures, config)
    
    # Update status
    updated_status = %{
      status: status,
      liveness: elem(probe_results.liveness, 0),
      readiness: elem(probe_results.readiness, 0),
      startup: probe_results.startup,
      last_check: DateTime.utc_now(),
      consecutive_failures: failures,
      consecutive_successes: successes,
      circuit_state: circuit_state,
      details: %{
        liveness: elem(probe_results.liveness, 1),
        readiness: elem(probe_results.readiness, 1),
        duration_ms: probe_results.duration
      }
    }
    
    :ets.insert(:agent_health_status, {agent_id, updated_status})
    
    # Update history
    update_health_history(agent_id, updated_status)
    
    # Emit telemetry
    :telemetry.execute(
      [:rubber_duck, :agent, :health_check],
      %{duration: probe_results.duration},
      %{agent_id: agent_id, status: status, healthy: is_healthy}
    )
  end
  
  defp handle_circuit_breaker(agent_id, current_state, is_healthy, failures, config) do
    if config.circuit_breaker_enabled do
      case {current_state, is_healthy} do
        {:closed, false} when failures >= config.failure_threshold ->
          # Open the circuit
          Process.send_after(self(), {:circuit_timeout, agent_id}, config.circuit_open_duration)
          update_circuit_state(agent_id, :open)
          :open
          
        {:half_open, true} ->
          # Close the circuit
          update_circuit_state(agent_id, :closed)
          :closed
          
        {:half_open, false} ->
          # Re-open the circuit
          Process.send_after(self(), {:circuit_timeout, agent_id}, config.circuit_open_duration)
          update_circuit_state(agent_id, :open)
          :open
          
        _ ->
          current_state
      end
    else
      :closed
    end
  end
  
  defp get_circuit_state(agent_id) do
    case :ets.lookup(:circuit_breakers, agent_id) do
      [{^agent_id, state}] -> state
      [] -> :closed
    end
  end
  
  defp update_circuit_state(agent_id, state) do
    :ets.insert(:circuit_breakers, {agent_id, state})
    
    # Also update the circuit state in health status
    case :ets.lookup(:agent_health_status, agent_id) do
      [{^agent_id, status}] ->
        updated_status = %{status | circuit_state: state}
        :ets.insert(:agent_health_status, {agent_id, updated_status})
      [] ->
        :ok
    end
    
    :telemetry.execute(
      [:rubber_duck, :agent, :circuit_breaker],
      %{count: 1},
      %{agent_id: agent_id, state: state}
    )
  end
  
  defp check_alerts(agent_id, consecutive_failures, config) do
    if consecutive_failures >= config.alert_threshold do
      Logger.error("Health alert: Agent #{agent_id} has failed #{consecutive_failures} consecutive health checks")
      
      :telemetry.execute(
        [:rubber_duck, :agent, :health_alert],
        %{failures: consecutive_failures},
        %{agent_id: agent_id}
      )
    end
  end
  
  defp update_health_history(agent_id, status) do
    case :ets.lookup(:agent_health_history, agent_id) do
      [{^agent_id, history}] ->
        # Keep last 100 entries
        new_history = [status | Enum.take(history, 99)]
        :ets.insert(:agent_health_history, {agent_id, new_history})
        
      [] ->
        :ets.insert(:agent_health_history, {agent_id, [status]})
    end
  end
  
  defp mark_agent_down(agent_id, reason) do
    status = %{
      status: :unhealthy,
      liveness: :dead,
      readiness: :dead,
      startup: :failed,
      last_check: DateTime.utc_now(),
      consecutive_failures: 999,
      consecutive_successes: 0,
      circuit_state: :open,
      details: %{reason: reason}
    }
    
    :ets.insert(:agent_health_status, {agent_id, status})
  end
  
  defp count_by_status(statuses, target_status) do
    Enum.count(statuses, fn {_, %{status: status}} -> status == target_status end)
  end
  
  defp count_circuit_state(statuses, target_state) do
    Enum.count(statuses, fn {_, %{circuit_state: state}} -> state == target_state end)
  end

  defp ensure_table(name) do
    case :ets.info(name) do
      :undefined ->
        :ets.new(name, [:set, :public, :named_table])
      _ ->
        name
    end
  end
end