defmodule RubberDuck.LLMAbstraction.LoadBalancer do
  @moduledoc """
  Distributed load balancer for LLM providers with multi-level routing strategies.
  
  This GenServer manages intelligent request routing across multiple providers
  and API keys using various strategies including round-robin, weighted routing,
  capability-based selection, and consistent hashing for API key distribution.
  
  The load balancer supports:
  - Multi-level routing: Provider -> Model -> API Key
  - Capability-based provider selection
  - Performance-weighted routing
  - Cost optimization
  - Health-aware routing
  - Automatic failover
  """

  use GenServer
  require Logger

  alias RubberDuck.LLMAbstraction.{ProviderRegistry, Capability, CapabilityMatcher}
  alias RubberDuck.LLMAbstraction.LoadBalancer.{RoutingStrategy, ConsistentHash, ProviderScorer}

  defstruct [
    :routing_strategy,
    :provider_weights,
    :provider_health,
    :request_counts,
    :performance_metrics,
    :api_key_rotator,
    :circuit_breakers,
    :last_rebalance
  ]

  @type routing_strategy :: :round_robin | :weighted | :capability_based | :cost_optimized | :performance_based
  @type provider_weight :: %{provider_name: atom(), weight: float()}
  @type provider_health :: %{provider_name: atom(), status: :healthy | :degraded | :unhealthy}

  # Configuration
  @default_strategy :capability_based
  @rebalance_interval :timer.minutes(5)
  @performance_window_ms :timer.minutes(15)

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Route a request to the best available provider based on requirements.
  
  ## Parameters
    - requirements: List of capability requirements
    - request_opts: Request options including priority, cost_limit, latency_target
    
  ## Returns
    - {:ok, provider_name, api_key} | {:error, reason}
  """
  def route_request(requirements, request_opts \\ []) do
    GenServer.call(__MODULE__, {:route_request, requirements, request_opts})
  end

  @doc """
  Get current routing statistics and provider health.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Update provider performance metrics.
  """
  def record_performance(provider_name, metrics) do
    GenServer.cast(__MODULE__, {:record_performance, provider_name, metrics})
  end

  @doc """
  Manually trigger load balancer rebalancing.
  """
  def rebalance do
    GenServer.cast(__MODULE__, :rebalance)
  end

  @doc """
  Update routing strategy.
  """
  def set_strategy(strategy) when strategy in [:round_robin, :weighted, :capability_based, :cost_optimized, :performance_based] do
    GenServer.call(__MODULE__, {:set_strategy, strategy})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    # Schedule periodic rebalancing
    schedule_rebalance()
    
    state = %__MODULE__{
      routing_strategy: Keyword.get(opts, :strategy, @default_strategy),
      provider_weights: %{},
      provider_health: %{},
      request_counts: %{},
      performance_metrics: %{},
      api_key_rotator: ConsistentHash.new(),
      circuit_breakers: %{},
      last_rebalance: DateTime.utc_now()
    }
    
    # Initialize with current providers
    {:ok, initialize_providers(state)}
  end

  @impl true
  def handle_call({:route_request, requirements, request_opts}, _from, state) do
    case select_provider(requirements, request_opts, state) do
      {:ok, provider_name, api_key} ->
        # Update request counts
        new_counts = Map.update(state.request_counts, provider_name, 1, &(&1 + 1))
        new_state = %{state | request_counts: new_counts}
        
        {:reply, {:ok, provider_name, api_key}, new_state}
        
      {:error, reason} = error ->
        Logger.warning("Failed to route request: #{inspect(reason)}")
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      strategy: state.routing_strategy,
      provider_weights: state.provider_weights,
      provider_health: state.provider_health,
      request_counts: state.request_counts,
      performance_metrics: state.performance_metrics,
      circuit_breakers: state.circuit_breakers,
      last_rebalance: state.last_rebalance
    }
    
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:set_strategy, strategy}, _from, state) do
    Logger.info("Switching routing strategy from #{state.routing_strategy} to #{strategy}")
    new_state = %{state | routing_strategy: strategy}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:record_performance, provider_name, metrics}, state) do
    # Update performance metrics with sliding window
    current_time = DateTime.utc_now()
    
    provider_metrics = Map.get(state.performance_metrics, provider_name, [])
    |> add_metric(current_time, metrics)
    |> cleanup_old_metrics(current_time)
    
    new_metrics = Map.put(state.performance_metrics, provider_name, provider_metrics)
    new_state = %{state | performance_metrics: new_metrics}
    
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:rebalance, state) do
    {:noreply, perform_rebalancing(state)}
  end

  @impl true
  def handle_info(:rebalance, state) do
    schedule_rebalance()
    {:noreply, perform_rebalancing(state)}
  end

  # Private Functions

  defp select_provider(requirements, request_opts, state) do
    case state.routing_strategy do
      :round_robin ->
        select_round_robin(requirements, state)
        
      :weighted ->
        select_weighted(requirements, state)
        
      :capability_based ->
        select_capability_based(requirements, request_opts, state)
        
      :cost_optimized ->
        select_cost_optimized(requirements, request_opts, state)
        
      :performance_based ->
        select_performance_based(requirements, request_opts, state)
    end
  end

  defp select_round_robin(requirements, state) do
    case get_healthy_providers(requirements, state) do
      [] ->
        {:error, :no_healthy_providers}
        
      providers ->
        # Simple round-robin based on request counts
        provider_name = providers
        |> Enum.min_by(fn name -> Map.get(state.request_counts, name, 0) end)
        
        get_api_key_for_provider(provider_name, state)
    end
  end

  defp select_weighted(requirements, state) do
    case get_healthy_providers(requirements, state) do
      [] ->
        {:error, :no_healthy_providers}
        
      providers ->
        # Weighted selection based on provider weights
        weighted_providers = providers
        |> Enum.map(fn name -> 
          weight = Map.get(state.provider_weights, name, 1.0)
          {name, weight}
        end)
        
        provider_name = RoutingStrategy.weighted_selection(weighted_providers)
        get_api_key_for_provider(provider_name, state)
    end
  end

  defp select_capability_based(requirements, request_opts, state) do
    # Get all providers and score them based on capabilities
    providers = ProviderRegistry.list_providers()
    
    scored_providers = providers
    |> Enum.map(fn {name, info} -> 
      score = ProviderScorer.score_provider(info, requirements, request_opts)
      {name, score, info}
    end)
    |> Enum.filter(fn {_name, score, _info} -> score > 0 end)
    |> Enum.filter(fn {name, _score, _info} -> is_provider_healthy?(name, state) end)
    |> Enum.sort_by(fn {_name, score, _info} -> score end, :desc)
    
    case scored_providers do
      [] ->
        {:error, :no_suitable_providers}
        
      [{provider_name, _score, _info} | _] ->
        get_api_key_for_provider(provider_name, state)
    end
  end

  defp select_cost_optimized(requirements, request_opts, state) do
    cost_limit = Keyword.get(request_opts, :cost_limit)
    
    providers = ProviderRegistry.list_providers()
    |> Enum.map(fn {name, info} -> 
      cost_score = ProviderScorer.cost_score(info, requirements)
      capability_score = ProviderScorer.capability_score(info, requirements)
      
      # Combine cost and capability scores
      combined_score = if cost_limit do
        if cost_score <= cost_limit do
          capability_score / cost_score  # Better capability per cost
        else
          0  # Exceeds cost limit
        end
      else
        capability_score / max(cost_score, 0.001)  # Avoid division by zero
      end
      
      {name, combined_score, info}
    end)
    |> Enum.filter(fn {_name, score, _info} -> score > 0 end)
    |> Enum.filter(fn {name, _score, _info} -> is_provider_healthy?(name, state) end)
    |> Enum.sort_by(fn {_name, score, _info} -> score end, :desc)
    
    case providers do
      [] ->
        {:error, :no_cost_effective_providers}
        
      [{provider_name, _score, _info} | _] ->
        get_api_key_for_provider(provider_name, state)
    end
  end

  defp select_performance_based(requirements, request_opts, state) do
    latency_target = Keyword.get(request_opts, :latency_target)
    
    providers = ProviderRegistry.list_providers()
    |> Enum.map(fn {name, info} -> 
      performance_score = calculate_performance_score(name, latency_target, state)
      capability_score = ProviderScorer.capability_score(info, requirements)
      
      # Combine performance and capability scores
      combined_score = performance_score * capability_score
      
      {name, combined_score, info}
    end)
    |> Enum.filter(fn {_name, score, _info} -> score > 0 end)
    |> Enum.filter(fn {name, _score, _info} -> is_provider_healthy?(name, state) end)
    |> Enum.sort_by(fn {_name, score, _info} -> score end, :desc)
    
    case providers do
      [] ->
        {:error, :no_performant_providers}
        
      [{provider_name, _score, _info} | _] ->
        get_api_key_for_provider(provider_name, state)
    end
  end

  defp get_healthy_providers(requirements, state) do
    ProviderRegistry.find_providers(requirements)
    |> Enum.filter(fn name -> is_provider_healthy?(name, state) end)
  end

  defp is_provider_healthy?(provider_name, state) do
    case Map.get(state.provider_health, provider_name) do
      nil -> true  # Assume healthy if no data
      :healthy -> true
      :degraded -> true  # Still usable
      :unhealthy -> false
    end
  end

  defp get_api_key_for_provider(provider_name, state) do
    # Use consistent hashing to select API key
    case ConsistentHash.get_key(state.api_key_rotator, provider_name) do
      nil ->
        {:error, :no_api_key_available}
        
      api_key ->
        {:ok, provider_name, api_key}
    end
  end

  defp calculate_performance_score(provider_name, latency_target, state) do
    metrics = Map.get(state.performance_metrics, provider_name, [])
    
    if Enum.empty?(metrics) do
      0.5  # Neutral score for unknown performance
    else
      avg_latency = metrics
      |> Enum.map(fn {_time, metric} -> metric.latency_ms end)
      |> Enum.sum()
      |> div(length(metrics))
      
      success_rate = metrics
      |> Enum.map(fn {_time, metric} -> if metric.success, do: 1, else: 0 end)
      |> Enum.sum()
      |> div(length(metrics))
      
      latency_score = if latency_target do
        max(0, 1.0 - (avg_latency / latency_target))
      else
        1.0 / max(avg_latency, 1)  # Inverse of latency
      end
      
      # Combine latency and success rate
      latency_score * success_rate
    end
  end

  defp add_metric(metrics, timestamp, new_metric) do
    [{timestamp, new_metric} | metrics]
  end

  defp cleanup_old_metrics(metrics, current_time) do
    cutoff_time = DateTime.add(current_time, -@performance_window_ms, :millisecond)
    
    Enum.filter(metrics, fn {timestamp, _metric} ->
      DateTime.compare(timestamp, cutoff_time) != :lt
    end)
  end

  defp initialize_providers(state) do
    # Get current providers from registry
    providers = ProviderRegistry.list_providers()
    
    # Initialize health status for all providers
    provider_health = providers
    |> Enum.map(fn {name, _info} -> {name, :healthy} end)
    |> Map.new()
    
    # Initialize weights (equal by default)
    provider_weights = providers
    |> Enum.map(fn {name, _info} -> {name, 1.0} end)
    |> Map.new()
    
    %{state | 
      provider_health: provider_health,
      provider_weights: provider_weights
    }
  end

  defp perform_rebalancing(state) do
    Logger.debug("Performing load balancer rebalancing")
    
    # Update provider health from registry
    new_health = update_provider_health(state)
    
    # Recalculate weights based on performance
    new_weights = calculate_dynamic_weights(state)
    
    # Update API key rotation
    new_rotator = update_api_key_rotation(state)
    
    %{state |
      provider_health: new_health,
      provider_weights: new_weights,
      api_key_rotator: new_rotator,
      last_rebalance: DateTime.utc_now()
    }
  end

  defp update_provider_health(state) do
    providers = ProviderRegistry.list_providers()
    
    providers
    |> Enum.map(fn {name, _info} ->
      health = case ProviderRegistry.health_status(name) do
        {:ok, status} -> status
        {:error, _} -> :unhealthy
      end
      
      {name, health}
    end)
    |> Map.new()
  end

  defp calculate_dynamic_weights(state) do
    # Calculate weights based on recent performance
    state.provider_health
    |> Enum.map(fn {provider_name, health} ->
      base_weight = case health do
        :healthy -> 1.0
        :degraded -> 0.5
        :unhealthy -> 0.0
      end
      
      # Adjust based on performance metrics
      performance_multiplier = calculate_performance_score(provider_name, nil, state)
      final_weight = base_weight * max(performance_multiplier, 0.1)
      
      {provider_name, final_weight}
    end)
    |> Map.new()
  end

  defp update_api_key_rotation(state) do
    # This would integrate with API key management
    # For now, return existing rotator
    state.api_key_rotator
  end

  defp schedule_rebalance do
    Process.send_after(self(), :rebalance, @rebalance_interval)
  end
end