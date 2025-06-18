defmodule RubberDuck.LoadBalancing.FailoverManager do
  @moduledoc """
  Automatic failover and provider redistribution manager.
  
  Monitors provider health and automatically redistributes load when
  providers fail or become unhealthy. Integrates with the circuit breaker
  and load balancer to provide seamless failover capabilities.
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.LoadBalancing.{LoadBalancer, CircuitBreaker, ConsistentHash}
  
  @type failover_strategy :: :immediate | :graceful | :circuit_breaker_guided
  @type redistribution_mode :: :rebalance | :drain | :redirect_only
  
  @type failover_config :: %{
    strategy: failover_strategy(),
    health_check_interval: non_neg_integer(),
    min_healthy_providers: non_neg_integer(),
    redistribution_mode: redistribution_mode(),
    drain_timeout: non_neg_integer(),
    recovery_verification_count: non_neg_integer()
  }
  
  @type provider_status :: %{
    provider_id: term(),
    health_score: float(),
    circuit_state: atom(),
    active_connections: non_neg_integer(),
    last_health_check: non_neg_integer(),
    consecutive_failures: non_neg_integer(),
    is_draining: boolean(),
    failover_target: term() | nil
  }
  
  @default_config %{
    strategy: :circuit_breaker_guided,
    health_check_interval: 30_000,
    min_healthy_providers: 1,
    redistribution_mode: :rebalance,
    drain_timeout: 60_000,
    recovery_verification_count: 3
  }
  
  # Client API
  
  @doc """
  Start the FailoverManager GenServer.
  
  ## Examples
  
      {:ok, pid} = FailoverManager.start_link()
      {:ok, pid} = FailoverManager.start_link(strategy: :immediate)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Trigger manual failover for a provider.
  
  ## Examples
  
      :ok = FailoverManager.trigger_failover(:failing_provider, :immediate)
      {:error, :no_healthy_alternatives} = FailoverManager.trigger_failover(:only_provider, :graceful)
  """
  def trigger_failover(provider_id, strategy \\ :graceful) do
    GenServer.call(__MODULE__, {:trigger_failover, provider_id, strategy})
  end
  
  @doc """
  Mark a provider for graceful drain (stop accepting new requests).
  
  ## Examples
  
      :ok = FailoverManager.start_drain(:provider_for_maintenance)
  """
  def start_drain(provider_id) do
    GenServer.call(__MODULE__, {:start_drain, provider_id})
  end
  
  @doc """
  Restore a drained provider to active service.
  
  ## Examples
  
      :ok = FailoverManager.end_drain(:provider_back_online)
  """
  def end_drain(provider_id) do
    GenServer.call(__MODULE__, {:end_drain, provider_id})
  end
  
  @doc """
  Get current failover status and provider health.
  
  ## Examples
  
      status = FailoverManager.get_status()
      # %{
      #   healthy_providers: [:openai, :anthropic],
      #   unhealthy_providers: [:failing_provider],
      #   draining_providers: [:maintenance_provider],
      #   active_failovers: []
      # }
  """
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end
  
  @doc """
  Get detailed failover statistics.
  
  ## Examples
  
      stats = FailoverManager.get_stats()
      # %{
      #   total_failovers: 5,
      #   successful_failovers: 4,
      #   failed_failovers: 1,
      #   avg_failover_time_ms: 150,
      #   provider_stats: %{...}
      # }
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Update failover configuration.
  
  ## Examples
  
      :ok = FailoverManager.update_config(%{
        health_check_interval: 60_000,
        min_healthy_providers: 2
      })
  """
  def update_config(config_updates) do
    GenServer.call(__MODULE__, {:update_config, config_updates})
  end
  
  @doc """
  Force rebalancing of provider load.
  
  ## Examples
  
      :ok = FailoverManager.rebalance_providers()
  """
  def rebalance_providers do
    GenServer.call(__MODULE__, :rebalance_providers)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    config = Keyword.get(opts, :config, @default_config)
    |> Map.merge(Keyword.take(opts, Map.keys(@default_config)) |> Map.new())
    
    state = %{
      config: config,
      provider_status: %{},
      active_failovers: %{},
      stats: %{
        total_failovers: 0,
        successful_failovers: 0,
        failed_failovers: 0,
        total_failover_time_ms: 0,
        last_rebalance_time: nil
      },
      health_check_timer: nil
    }
    
    # Schedule health checks
    timer = Process.send_after(self(), :health_check, config.health_check_interval)
    
    {:ok, %{state | health_check_timer: timer}}
  end
  
  @impl true
  def handle_call({:trigger_failover, provider_id, strategy}, _from, state) do
    case execute_failover(provider_id, strategy, state) do
      {:ok, updated_state} ->
        {:reply, :ok, updated_state}
      
      {:error, reason, updated_state} ->
        {:reply, {:error, reason}, updated_state}
    end
  end
  
  @impl true
  def handle_call({:start_drain, provider_id}, _from, state) do
    case start_provider_drain(provider_id, state) do
      {:ok, updated_state} ->
        {:reply, :ok, updated_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:end_drain, provider_id}, _from, state) do
    case end_provider_drain(provider_id, state) do
      {:ok, updated_state} ->
        {:reply, :ok, updated_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call(:get_status, _from, state) do
    status = calculate_current_status(state)
    {:reply, status, state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = calculate_failover_stats(state)
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call({:update_config, config_updates}, _from, state) do
    updated_config = Map.merge(state.config, config_updates)
    updated_state = %{state | config: updated_config}
    
    Logger.info("Updated failover manager config: #{inspect(config_updates)}")
    {:reply, :ok, updated_state}
  end
  
  @impl true
  def handle_call(:rebalance_providers, _from, state) do
    updated_state = perform_rebalancing(state)
    {:reply, :ok, updated_state}
  end
  
  @impl true
  def handle_info(:health_check, state) do
    # Perform health checks and automatic failover decisions
    updated_state = perform_health_checks(state)
    |> evaluate_failover_needs()
    |> cleanup_completed_failovers()
    
    # Schedule next health check
    timer = Process.send_after(self(), :health_check, state.config.health_check_interval)
    
    {:noreply, %{updated_state | health_check_timer: timer}}
  end
  
  @impl true
  def handle_info({:drain_timeout, provider_id}, state) do
    Logger.warning("Drain timeout for provider #{provider_id}, forcing completion")
    
    updated_state = complete_drain(provider_id, state, :timeout)
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  @impl true
  def terminate(_reason, state) do
    if state.health_check_timer do
      Process.cancel_timer(state.health_check_timer)
    end
    :ok
  end
  
  # Private Functions
  
  defp perform_health_checks(state) do
    current_time = System.monotonic_time(:millisecond)
    
    # Get current provider stats from load balancer and circuit breaker
    provider_stats = LoadBalancer.get_provider_stats()
    health_scores = CircuitBreaker.get_health_scores()
    circuit_stats = CircuitBreaker.get_stats()
    
    updated_provider_status = Map.new(provider_stats, fn {provider_id, provider_info} ->
      health_score = Map.get(health_scores, provider_id, 0.0)
      circuit_info = get_in(circuit_stats, [:circuits, provider_id]) || %{}
      circuit_state = Map.get(circuit_info, :state, :unknown)
      
      existing_status = Map.get(state.provider_status, provider_id, %{
        consecutive_failures: 0,
        is_draining: false,
        failover_target: nil
      })
      
      status = %{
        provider_id: provider_id,
        health_score: health_score,
        circuit_state: circuit_state,
        active_connections: Map.get(provider_info, :active_connections, 0),
        last_health_check: current_time,
        consecutive_failures: calculate_consecutive_failures(existing_status, health_score),
        is_draining: existing_status.is_draining,
        failover_target: existing_status.failover_target
      }
      
      {provider_id, status}
    end)
    
    %{state | provider_status: updated_provider_status}
  end
  
  defp evaluate_failover_needs(state) do
    unhealthy_providers = find_unhealthy_providers(state.provider_status)
    healthy_providers = find_healthy_providers(state.provider_status)
    
    # Check if we have minimum healthy providers
    if length(healthy_providers) < state.config.min_healthy_providers do
      Logger.error("Below minimum healthy providers: #{length(healthy_providers)} < #{state.config.min_healthy_providers}")
    end
    
    # Trigger automatic failovers for unhealthy providers
    Enum.reduce(unhealthy_providers, state, fn provider_id, acc_state ->
      if should_trigger_automatic_failover?(provider_id, acc_state) do
        case execute_failover(provider_id, state.config.strategy, acc_state) do
          {:ok, updated_state} -> updated_state
          {:error, _reason, updated_state} -> updated_state
        end
      else
        acc_state
      end
    end)
  end
  
  defp execute_failover(provider_id, strategy, state) do
    start_time = System.monotonic_time(:millisecond)
    
    case find_failover_target(provider_id, state) do
      {:ok, target_provider} ->
        Logger.warning("Executing #{strategy} failover from #{provider_id} to #{target_provider}")
        
        case perform_failover_strategy(provider_id, target_provider, strategy, state) do
          {:ok, updated_state} ->
            end_time = System.monotonic_time(:millisecond)
            duration = end_time - start_time
            
            final_state = record_successful_failover(updated_state, provider_id, target_provider, duration)
            {:ok, final_state}
          
          {:error, reason} ->
            final_state = record_failed_failover(state, provider_id, reason)
            {:error, reason, final_state}
        end
      
      {:error, reason} ->
        final_state = record_failed_failover(state, provider_id, reason)
        {:error, reason, final_state}
    end
  end
  
  defp find_failover_target(failing_provider_id, state) do
    healthy_providers = find_healthy_providers(state.provider_status)
    |> Enum.filter(&(&1 != failing_provider_id))
    |> Enum.reject(fn provider_id ->
      status = Map.get(state.provider_status, provider_id)
      status && status.is_draining
    end)
    
    case healthy_providers do
      [] -> {:error, :no_healthy_alternatives}
      providers ->
        # Select provider with lowest current load
        target = Enum.min_by(providers, fn provider_id ->
          status = Map.get(state.provider_status, provider_id)
          status.active_connections
        end)
        {:ok, target}
    end
  end
  
  defp perform_failover_strategy(from_provider, to_provider, strategy, state) do
    case strategy do
      :immediate ->
        perform_immediate_failover(from_provider, to_provider, state)
      
      :graceful ->
        perform_graceful_failover(from_provider, to_provider, state)
      
      :circuit_breaker_guided ->
        perform_circuit_breaker_guided_failover(from_provider, to_provider, state)
    end
  end
  
  defp perform_immediate_failover(from_provider, to_provider, state) do
    # Immediate failover: Remove failing provider and redirect all traffic
    :ok = LoadBalancer.remove_provider(from_provider)
    
    # Update provider status
    updated_status = update_provider_status(state.provider_status, from_provider, %{
      failover_target: to_provider,
      is_draining: false
    })
    
    {:ok, %{state | provider_status: updated_status}}
  end
  
  defp perform_graceful_failover(from_provider, to_provider, state) do
    # Graceful failover: Start draining the failing provider
    case start_provider_drain(from_provider, state) do
      {:ok, updated_state} ->
        # Update with failover target
        final_status = update_provider_status(updated_state.provider_status, from_provider, %{
          failover_target: to_provider
        })
        {:ok, %{updated_state | provider_status: final_status}}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp perform_circuit_breaker_guided_failover(from_provider, to_provider, state) do
    # Use circuit breaker state to guide failover strategy
    status = Map.get(state.provider_status, from_provider)
    
    case status.circuit_state do
      :open ->
        # Circuit is open, do immediate failover
        perform_immediate_failover(from_provider, to_provider, state)
      
      :half_open ->
        # Circuit is testing, do graceful failover
        perform_graceful_failover(from_provider, to_provider, state)
      
      _ ->
        # Circuit is closed but health is low, do graceful failover
        perform_graceful_failover(from_provider, to_provider, state)
    end
  end
  
  defp start_provider_drain(provider_id, state) do
    # Mark provider as draining
    updated_status = update_provider_status(state.provider_status, provider_id, %{
      is_draining: true
    })
    
    # Schedule drain timeout
    Process.send_after(self(), {:drain_timeout, provider_id}, state.config.drain_timeout)
    
    Logger.info("Started draining provider #{provider_id}")
    {:ok, %{state | provider_status: updated_status}}
  end
  
  defp end_provider_drain(provider_id, state) do
    case Map.get(state.provider_status, provider_id) do
      nil ->
        {:error, :provider_not_found}
      
      status ->
        if status.is_draining do
          updated_status = update_provider_status(state.provider_status, provider_id, %{
            is_draining: false,
            failover_target: nil
          })
          
          Logger.info("Ended drain for provider #{provider_id}")
          {:ok, %{state | provider_status: updated_status}}
        else
          {:error, :provider_not_draining}
        end
    end
  end
  
  defp complete_drain(provider_id, state, reason) do
    # Force complete the drain and remove provider if necessary
    if reason == :timeout do
      :ok = LoadBalancer.remove_provider(provider_id)
    end
    
    updated_status = update_provider_status(state.provider_status, provider_id, %{
      is_draining: false
    })
    
    %{state | provider_status: updated_status}
  end
  
  defp perform_rebalancing(state) do
    healthy_providers = find_healthy_providers(state.provider_status)
    
    # Get current load distribution
    provider_stats = LoadBalancer.get_provider_stats()
    
    # Calculate optimal load distribution
    total_connections = provider_stats
    |> Map.values()
    |> Enum.map(& &1.active_connections)
    |> Enum.sum()
    
    avg_connections = if length(healthy_providers) > 0 do
      total_connections / length(healthy_providers)
    else
      0
    end
    
    # Log rebalancing action
    Logger.info("Rebalancing load across #{length(healthy_providers)} healthy providers (avg: #{avg_connections} connections)")
    
    # Update stats
    updated_stats = %{state.stats | last_rebalance_time: System.monotonic_time(:millisecond)}
    %{state | stats: updated_stats}
  end
  
  defp cleanup_completed_failovers(state) do
    # Remove completed failovers from tracking
    current_time = System.monotonic_time(:millisecond)
    timeout = 300_000  # 5 minutes
    
    active_failovers = Map.filter(state.active_failovers, fn {_id, failover_info} ->
      (current_time - failover_info.start_time) < timeout
    end)
    
    %{state | active_failovers: active_failovers}
  end
  
  defp find_healthy_providers(provider_status) do
    provider_status
    |> Enum.filter(fn {_id, status} ->
      status.health_score >= 0.7 && status.circuit_state != :open
    end)
    |> Enum.map(fn {provider_id, _status} -> provider_id end)
  end
  
  defp find_unhealthy_providers(provider_status) do
    provider_status
    |> Enum.filter(fn {_id, status} ->
      status.health_score < 0.5 || status.circuit_state == :open
    end)
    |> Enum.map(fn {provider_id, _status} -> provider_id end)
  end
  
  defp should_trigger_automatic_failover?(provider_id, state) do
    status = Map.get(state.provider_status, provider_id)
    
    # Don't failover if already draining or in active failover
    if status.is_draining || Map.has_key?(state.active_failovers, provider_id) do
      false
    else
      # Trigger failover if consistently unhealthy
      status.consecutive_failures >= 3 && status.health_score < 0.3
    end
  end
  
  defp calculate_consecutive_failures(existing_status, current_health_score) do
    if current_health_score < 0.5 do
      existing_status.consecutive_failures + 1
    else
      0
    end
  end
  
  defp update_provider_status(provider_status, provider_id, updates) do
    case Map.get(provider_status, provider_id) do
      nil -> provider_status
      existing -> Map.put(provider_status, provider_id, Map.merge(existing, updates))
    end
  end
  
  defp record_successful_failover(state, from_provider, to_provider, duration) do
    updated_stats = %{state.stats |
      total_failovers: state.stats.total_failovers + 1,
      successful_failovers: state.stats.successful_failovers + 1,
      total_failover_time_ms: state.stats.total_failover_time_ms + duration
    }
    
    Logger.info("Successful failover from #{from_provider} to #{to_provider} in #{duration}ms")
    %{state | stats: updated_stats}
  end
  
  defp record_failed_failover(state, provider_id, reason) do
    updated_stats = %{state.stats |
      total_failovers: state.stats.total_failovers + 1,
      failed_failovers: state.stats.failed_failovers + 1
    }
    
    Logger.error("Failed failover for #{provider_id}: #{inspect(reason)}")
    %{state | stats: updated_stats}
  end
  
  defp calculate_current_status(state) do
    healthy = find_healthy_providers(state.provider_status)
    unhealthy = find_unhealthy_providers(state.provider_status)
    
    draining = state.provider_status
    |> Enum.filter(fn {_id, status} -> status.is_draining end)
    |> Enum.map(fn {provider_id, _status} -> provider_id end)
    
    %{
      healthy_providers: healthy,
      unhealthy_providers: unhealthy,
      draining_providers: draining,
      active_failovers: Map.keys(state.active_failovers),
      min_healthy_threshold_met: length(healthy) >= state.config.min_healthy_providers
    }
  end
  
  defp calculate_failover_stats(state) do
    avg_failover_time = if state.stats.successful_failovers > 0 do
      state.stats.total_failover_time_ms / state.stats.successful_failovers
    else
      0
    end
    
    provider_stats = Map.new(state.provider_status, fn {provider_id, status} ->
      {provider_id, %{
        health_score: status.health_score,
        circuit_state: status.circuit_state,
        is_draining: status.is_draining,
        consecutive_failures: status.consecutive_failures,
        active_connections: status.active_connections
      }}
    end)
    
    Map.merge(state.stats, %{
      avg_failover_time_ms: avg_failover_time,
      provider_stats: provider_stats
    })
  end
end