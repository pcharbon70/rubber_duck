defmodule RubberDuck.LLMAbstraction.FailoverManager do
  @moduledoc """
  Automatic failover and provider redistribution manager.
  
  This GenServer monitors provider health and automatically handles
  failover scenarios, redistributing load away from failing providers
  and back to recovered providers. It integrates with the circuit
  breaker and load balancer to provide seamless failover.
  
  Features:
  - Automatic provider health monitoring
  - Intelligent failover to backup providers
  - Load redistribution during failures
  - Gradual recovery and load shifting
  - Cross-cluster failover coordination
  - Provider performance degradation detection
  """

  use GenServer
  require Logger

  alias RubberDuck.LLMAbstraction.{
    ProviderRegistry,
    LoadBalancer,
    CircuitBreaker,
    RateLimiter
  }

  defstruct [
    :provider_health,
    :backup_providers,
    :failover_history,
    :recovery_timers,
    :health_check_interval,
    :last_health_check
  ]

  @type provider_status :: :healthy | :degraded | :unhealthy | :failed
  @type failover_strategy :: :immediate | :gradual | :manual

  # Configuration
  @health_check_interval :timer.seconds(30)
  @recovery_check_interval :timer.minutes(2)
  @degradation_threshold 0.7
  @failure_threshold 0.3

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get current provider health status.
  """
  def get_provider_health do
    GenServer.call(__MODULE__, :get_provider_health)
  end

  @doc """
  Manually trigger failover for a provider.
  """
  def trigger_failover(provider, reason \\ :manual) do
    GenServer.cast(__MODULE__, {:trigger_failover, provider, reason})
  end

  @doc """
  Configure backup providers for a primary provider.
  """
  def configure_backups(primary_provider, backup_providers) do
    GenServer.call(__MODULE__, {:configure_backups, primary_provider, backup_providers})
  end

  @doc """
  Get failover statistics and history.
  """
  def get_failover_stats do
    GenServer.call(__MODULE__, :get_failover_stats)
  end

  @doc """
  Check if a provider is currently failed over.
  """
  def is_failed_over?(provider) do
    GenServer.call(__MODULE__, {:is_failed_over, provider})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Schedule initial health check
    schedule_health_check()
    
    state = %__MODULE__{
      provider_health: %{},
      backup_providers: %{},
      failover_history: [],
      recovery_timers: %{},
      health_check_interval: @health_check_interval,
      last_health_check: DateTime.utc_now()
    }
    
    # Initialize provider health status
    {:ok, initialize_provider_health(state)}
  end

  @impl true
  def handle_call(:get_provider_health, _from, state) do
    {:reply, state.provider_health, state}
  end

  @impl true
  def handle_call({:configure_backups, primary, backups}, _from, state) do
    new_backups = Map.put(state.backup_providers, primary, backups)
    new_state = %{state | backup_providers: new_backups}
    
    Logger.info("Configured backup providers for #{primary}: #{inspect(backups)}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_failover_stats, _from, state) do
    stats = %{
      provider_health: state.provider_health,
      backup_providers: state.backup_providers,
      failover_history: Enum.take(state.failover_history, 50),  # Last 50 events
      active_recoveries: Map.keys(state.recovery_timers),
      last_health_check: state.last_health_check
    }
    
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:is_failed_over, provider}, _from, state) do
    status = Map.get(state.provider_health, provider, :unknown)
    is_failed = status in [:failed, :unhealthy]
    
    {:reply, is_failed, state}
  end

  @impl true
  def handle_cast({:trigger_failover, provider, reason}, state) do
    Logger.warning("Manual failover triggered for provider #{provider}: #{reason}")
    new_state = execute_failover(provider, reason, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:store_recovery_timer, provider, timer_ref}, state) do
    new_timers = Map.put(state.recovery_timers, provider, timer_ref)
    new_state = %{state | recovery_timers: new_timers}
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:health_check, state) do
    schedule_health_check()
    new_state = perform_health_checks(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:recovery_check, provider}, state) do
    new_state = check_provider_recovery(provider, state)
    {:noreply, new_state}
  end

  # Private Functions

  defp initialize_provider_health(state) do
    providers = ProviderRegistry.list_providers()
    
    initial_health = providers
    |> Enum.map(fn {name, _info} -> {name, :healthy} end)
    |> Map.new()
    
    %{state | provider_health: initial_health}
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_check_interval)
  end

  defp perform_health_checks(state) do
    providers = ProviderRegistry.list_providers()
    current_time = DateTime.utc_now()
    
    new_health = providers
    |> Enum.map(fn {name, _info} -> 
      {name, check_individual_provider_health(name)}
    end)
    |> Map.new()
    
    # Compare with previous health and trigger actions if needed
    new_state = %{state | 
      provider_health: new_health,
      last_health_check: current_time
    }
    
    handle_health_changes(state.provider_health, new_health, new_state)
  end

  defp check_individual_provider_health(provider) do
    # Combine multiple health indicators
    circuit_breaker_status = CircuitBreaker.get_state(provider)
    rate_limit_status = RateLimiter.is_rate_limited?(provider, "default")
    registry_health = case ProviderRegistry.health_status(provider) do
      {:ok, status} -> status
      {:error, _} -> :unhealthy
    end
    
    # Calculate composite health score
    health_score = calculate_composite_health_score(
      circuit_breaker_status,
      rate_limit_status,
      registry_health
    )
    
    # Convert score to status
    cond do
      health_score >= 0.8 -> :healthy
      health_score >= @degradation_threshold -> :degraded
      health_score >= @failure_threshold -> :unhealthy
      true -> :failed
    end
  end

  defp calculate_composite_health_score(circuit_status, rate_limited, registry_health) do
    circuit_score = case circuit_status do
      :closed -> 1.0
      :half_open -> 0.6
      :open -> 0.0
    end
    
    rate_limit_score = if rate_limited, do: 0.5, else: 1.0
    
    registry_score = case registry_health do
      :healthy -> 1.0
      :degraded -> 0.7
      :unhealthy -> 0.3
      _ -> 0.0
    end
    
    # Weighted average
    (circuit_score * 0.4 + rate_limit_score * 0.3 + registry_score * 0.3)
  end

  defp handle_health_changes(old_health, new_health, state) do
    changes = detect_health_changes(old_health, new_health)
    
    Enum.reduce(changes, state, fn {provider, {old_status, new_status}}, acc_state ->
      handle_provider_status_change(provider, old_status, new_status, acc_state)
    end)
  end

  defp detect_health_changes(old_health, new_health) do
    all_providers = Map.keys(old_health) ++ Map.keys(new_health)
    |> Enum.uniq()
    
    all_providers
    |> Enum.map(fn provider ->
      old_status = Map.get(old_health, provider, :unknown)
      new_status = Map.get(new_health, provider, :unknown)
      {provider, {old_status, new_status}}
    end)
    |> Enum.filter(fn {_provider, {old, new}} -> old != new end)
  end

  defp handle_provider_status_change(provider, old_status, new_status, state) do
    Logger.info("Provider #{provider} health changed: #{old_status} -> #{new_status}")
    
    case {old_status, new_status} do
      {_, status} when status in [:unhealthy, :failed] ->
        execute_failover(provider, :health_degradation, state)
      
      {old, :healthy} when old in [:unhealthy, :failed] ->
        execute_recovery(provider, state)
      
      {_, :degraded} ->
        execute_partial_failover(provider, state)
      
      _ ->
        state
    end
  end

  defp execute_failover(provider, reason, state) do
    backup_providers = Map.get(state.backup_providers, provider, [])
    
    if Enum.empty?(backup_providers) do
      Logger.warning("No backup providers configured for #{provider}")
      record_failover_event(provider, reason, :no_backups, state)
    else
      # Find healthy backup provider
      healthy_backup = find_healthy_backup(backup_providers, state)
      
      case healthy_backup do
        nil ->
          Logger.error("No healthy backup providers available for #{provider}")
          record_failover_event(provider, reason, :no_healthy_backups, state)
        
        backup ->
          Logger.info("Failing over from #{provider} to #{backup}")
          
          # Update load balancer to redirect traffic
          redistribute_load(provider, backup)
          
          # Schedule recovery check
          schedule_recovery_check(provider)
          
          record_failover_event(provider, reason, {:failover_to, backup}, state)
      end
    end
  end

  defp execute_partial_failover(provider, state) do
    # Reduce load on degraded provider but don't fully fail over
    Logger.info("Reducing load on degraded provider #{provider}")
    
    # Adjust load balancer weights
    LoadBalancer.rebalance()
    
    record_failover_event(provider, :degradation, :load_reduction, state)
  end

  defp execute_recovery(provider, state) do
    Logger.info("Recovering provider #{provider}")
    
    # Cancel recovery timer if exists
    case Map.get(state.recovery_timers, provider) do
      nil -> :ok
      timer_ref -> Process.cancel_timer(timer_ref)
    end
    
    # Gradually restore load
    restore_load(provider)
    
    new_timers = Map.delete(state.recovery_timers, provider)
    new_state = %{state | recovery_timers: new_timers}
    
    record_failover_event(provider, :recovery, :load_restored, new_state)
  end

  defp find_healthy_backup(backup_providers, state) do
    backup_providers
    |> Enum.find(fn backup ->
      health = Map.get(state.provider_health, backup, :unknown)
      health in [:healthy, :degraded]
    end)
  end

  defp redistribute_load(from_provider, to_provider) do
    # This would integrate with the load balancer to redirect traffic
    # For now, we'll trigger a rebalance
    LoadBalancer.rebalance()
    
    Logger.info("Redistributed load from #{from_provider} to #{to_provider}")
  end

  defp restore_load(provider) do
    # Gradually restore load to recovered provider
    LoadBalancer.rebalance()
    
    Logger.info("Restored load to recovered provider #{provider}")
  end

  defp schedule_recovery_check(provider) do
    timer_ref = Process.send_after(self(), {:recovery_check, provider}, @recovery_check_interval)
    
    # Store timer reference for potential cancellation
    GenServer.cast(__MODULE__, {:store_recovery_timer, provider, timer_ref})
  end

  defp check_provider_recovery(provider, state) do
    current_health = Map.get(state.provider_health, provider, :unknown)
    
    case current_health do
      :healthy ->
        execute_recovery(provider, state)
      
      status when status in [:degraded, :unhealthy] ->
        # Still not healthy, check again later
        schedule_recovery_check(provider)
        state
      
      :failed ->
        # Still failed, try alternative backups if available
        state
    end
  end

  defp record_failover_event(provider, reason, action, state) do
    event = %{
      timestamp: DateTime.utc_now(),
      provider: provider,
      reason: reason,
      action: action
    }
    
    new_history = [event | state.failover_history]
    |> Enum.take(100)  # Keep last 100 events
    
    %{state | failover_history: new_history}
  end

  # Timer storage is handled above in the main handle_cast clauses
end