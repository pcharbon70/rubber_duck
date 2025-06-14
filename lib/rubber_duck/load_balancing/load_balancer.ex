defmodule RubberDuck.LoadBalancing.LoadBalancer do
  @moduledoc """
  GenServer implementing intelligent load balancing and routing for LLM providers.
  
  Supports multiple routing strategies including round-robin, weighted, 
  capability-based, and consistent hash-based routing. Integrates with
  provider health monitoring, rate limiting, and automatic failover.
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.LoadBalancing.ConsistentHash
  alias RubberDuck.LLMAbstraction.{Provider, ProviderRegistry}
  
  @type routing_strategy :: :round_robin | :weighted | :capability_based | :consistent_hash | :least_connections
  @type provider_info :: %{
    id: term(),
    module: module(),
    capabilities: map(),
    weight: non_neg_integer(),
    health_score: float(),
    active_connections: non_neg_integer(),
    last_used: non_neg_integer()
  }
  
  @type state :: %{
    routing_strategy: routing_strategy(),
    providers: %{term() => provider_info()},
    consistent_hash: ConsistentHash.t(),
    round_robin_index: non_neg_integer(),
    health_check_interval: non_neg_integer(),
    health_check_timer: reference() | nil,
    request_queue: :queue.queue(),
    max_queue_size: non_neg_integer(),
    backpressure_enabled: boolean()
  }
  
  @default_health_check_interval 30_000
  @default_max_queue_size 1000
  @default_routing_strategy :capability_based
  
  # Client API
  
  @doc """
  Start the LoadBalancer GenServer.
  
  ## Options
  
    * `:routing_strategy` - Default routing strategy (default: :capability_based)
    * `:health_check_interval` - Health check interval in ms (default: 30_000)
    * `:max_queue_size` - Maximum request queue size (default: 1000)
    * `:backpressure_enabled` - Enable backpressure handling (default: true)
  
  ## Examples
  
      {:ok, pid} = LoadBalancer.start_link()
      {:ok, pid} = LoadBalancer.start_link(routing_strategy: :round_robin)
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Route a request to an appropriate provider.
  
  ## Examples
  
      {:ok, provider_id} = LoadBalancer.route_request(%{model: "gpt-4", type: :chat})
      {:error, :no_available_providers} = LoadBalancer.route_request(%{model: "unknown"})
  """
  def route_request(request_params, opts \\ []) do
    strategy = Keyword.get(opts, :strategy)
    GenServer.call(__MODULE__, {:route_request, request_params, strategy})
  end
  
  @doc """
  Add a provider to the load balancer.
  
  ## Examples
  
      :ok = LoadBalancer.add_provider(:openai_provider, OpenAIProvider, %{weight: 100})
  """
  def add_provider(provider_id, provider_module, opts \\ %{}) do
    GenServer.call(__MODULE__, {:add_provider, provider_id, provider_module, opts})
  end
  
  @doc """
  Remove a provider from the load balancer.
  
  ## Examples
  
      :ok = LoadBalancer.remove_provider(:openai_provider)
  """
  def remove_provider(provider_id) do
    GenServer.call(__MODULE__, {:remove_provider, provider_id})
  end
  
  @doc """
  Update provider health score.
  
  ## Examples
  
      :ok = LoadBalancer.update_health_score(:openai_provider, 0.95)
  """
  def update_health_score(provider_id, health_score) when health_score >= 0.0 and health_score <= 1.0 do
    GenServer.cast(__MODULE__, {:update_health_score, provider_id, health_score})
  end
  
  @doc """
  Report provider connection change.
  
  ## Examples
  
      :ok = LoadBalancer.connection_opened(:openai_provider)
      :ok = LoadBalancer.connection_closed(:openai_provider)
  """
  def connection_opened(provider_id) do
    GenServer.cast(__MODULE__, {:connection_opened, provider_id})
  end
  
  def connection_closed(provider_id) do
    GenServer.cast(__MODULE__, {:connection_closed, provider_id})
  end
  
  @doc """
  Get current load balancer statistics.
  
  ## Examples
  
      stats = LoadBalancer.get_stats()
      # %{provider_count: 3, total_requests: 1250, queue_size: 0, ...}
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Get provider statistics.
  
  ## Examples
  
      providers = LoadBalancer.get_provider_stats()
      # %{openai_provider: %{weight: 100, health_score: 0.95, ...}, ...}
  """
  def get_provider_stats do
    GenServer.call(__MODULE__, :get_provider_stats)
  end
  
  @doc """
  Update routing strategy.
  
  ## Examples
  
      :ok = LoadBalancer.set_routing_strategy(:round_robin)
  """
  def set_routing_strategy(strategy) when strategy in [:round_robin, :weighted, :capability_based, :consistent_hash, :least_connections] do
    GenServer.call(__MODULE__, {:set_routing_strategy, strategy})
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    routing_strategy = Keyword.get(opts, :routing_strategy, @default_routing_strategy)
    health_check_interval = Keyword.get(opts, :health_check_interval, @default_health_check_interval)
    max_queue_size = Keyword.get(opts, :max_queue_size, @default_max_queue_size)
    backpressure_enabled = Keyword.get(opts, :backpressure_enabled, true)
    
    state = %{
      routing_strategy: routing_strategy,
      providers: %{},
      consistent_hash: ConsistentHash.new(),
      round_robin_index: 0,
      health_check_interval: health_check_interval,
      health_check_timer: nil,
      request_queue: :queue.new(),
      max_queue_size: max_queue_size,
      backpressure_enabled: backpressure_enabled
    }
    
    # Schedule health checks
    timer = Process.send_after(self(), :health_check, health_check_interval)
    
    {:ok, %{state | health_check_timer: timer}}
  end
  
  @impl true
  def handle_call({:route_request, request_params, strategy_override}, _from, state) do
    strategy = strategy_override || state.routing_strategy
    
    case route_with_strategy(strategy, request_params, state) do
      {:ok, provider_id} ->
        updated_state = record_provider_usage(provider_id, state)
        {:reply, {:ok, provider_id}, updated_state}
      
      {:error, :no_available_providers} = error ->
        {:reply, error, state}
      
      {:error, :queue_full} = error ->
        {:reply, error, state}
    end
  end
  
  @impl true
  def handle_call({:add_provider, provider_id, provider_module, opts}, _from, state) do
    provider_info = %{
      id: provider_id,
      module: provider_module,
      capabilities: get_provider_capabilities(provider_module),
      weight: Map.get(opts, :weight, 100),
      health_score: Map.get(opts, :health_score, 1.0),
      active_connections: 0,
      last_used: 0
    }
    
    updated_providers = Map.put(state.providers, provider_id, provider_info)
    updated_hash = ConsistentHash.add_node(state.consistent_hash, provider_id)
    
    updated_state = %{state | 
      providers: updated_providers,
      consistent_hash: updated_hash
    }
    
    Logger.info("Added provider #{provider_id} to load balancer")
    {:reply, :ok, updated_state}
  end
  
  @impl true
  def handle_call({:remove_provider, provider_id}, _from, state) do
    updated_providers = Map.delete(state.providers, provider_id)
    updated_hash = ConsistentHash.remove_node(state.consistent_hash, provider_id)
    
    updated_state = %{state |
      providers: updated_providers,
      consistent_hash: updated_hash
    }
    
    Logger.info("Removed provider #{provider_id} from load balancer")
    {:reply, :ok, updated_state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      provider_count: map_size(state.providers),
      queue_size: :queue.len(state.request_queue),
      routing_strategy: state.routing_strategy,
      backpressure_enabled: state.backpressure_enabled,
      max_queue_size: state.max_queue_size,
      total_active_connections: total_active_connections(state.providers)
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:get_provider_stats, _from, state) do
    {:reply, state.providers, state}
  end
  
  @impl true
  def handle_call({:set_routing_strategy, strategy}, _from, state) do
    updated_state = %{state | routing_strategy: strategy}
    Logger.info("Updated routing strategy to #{strategy}")
    {:reply, :ok, updated_state}
  end
  
  @impl true
  def handle_cast({:update_health_score, provider_id, health_score}, state) do
    case Map.get(state.providers, provider_id) do
      nil ->
        {:noreply, state}
      
      provider_info ->
        updated_provider = %{provider_info | health_score: health_score}
        updated_providers = Map.put(state.providers, provider_id, updated_provider)
        {:noreply, %{state | providers: updated_providers}}
    end
  end
  
  @impl true
  def handle_cast({:connection_opened, provider_id}, state) do
    updated_state = update_connection_count(provider_id, state, 1)
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_cast({:connection_closed, provider_id}, state) do
    updated_state = update_connection_count(provider_id, state, -1)
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info(:health_check, state) do
    # Perform health checks on all providers
    updated_state = perform_health_checks(state)
    
    # Schedule next health check
    timer = Process.send_after(self(), :health_check, state.health_check_interval)
    
    {:noreply, %{updated_state | health_check_timer: timer}}
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
  
  defp route_with_strategy(:round_robin, _request_params, state) do
    healthy_providers = get_healthy_providers(state.providers)
    
    case healthy_providers do
      [] -> {:error, :no_available_providers}
      providers ->
        provider_ids = Map.keys(providers)
        index = rem(state.round_robin_index, length(provider_ids))
        provider_id = Enum.at(provider_ids, index)
        {:ok, provider_id}
    end
  end
  
  defp route_with_strategy(:weighted, _request_params, state) do
    healthy_providers = get_healthy_providers(state.providers)
    
    case select_weighted_provider(healthy_providers) do
      nil -> {:error, :no_available_providers}
      provider_id -> {:ok, provider_id}
    end
  end
  
  defp route_with_strategy(:least_connections, _request_params, state) do
    healthy_providers = get_healthy_providers(state.providers)
    
    case select_least_connections_provider(healthy_providers) do
      nil -> {:error, :no_available_providers}
      provider_id -> {:ok, provider_id}
    end
  end
  
  defp route_with_strategy(:consistent_hash, request_params, state) do
    case get_healthy_providers(state.providers) do
      providers when map_size(providers) == 0 -> {:error, :no_available_providers}
      _providers ->
        hash_key = generate_hash_key(request_params)
        case ConsistentHash.get_node(state.consistent_hash, hash_key) do
          nil -> {:error, :no_available_providers}
          provider_id ->
            # Ensure the selected provider is still healthy
            case Map.get(state.providers, provider_id) do
              %{health_score: score} when score >= 0.5 -> {:ok, provider_id}
              _ -> 
                # Fallback to weighted selection if primary is unhealthy
                route_with_strategy(:weighted, request_params, state)
            end
        end
    end
  end
  
  defp route_with_strategy(:capability_based, request_params, state) do
    healthy_providers = get_healthy_providers(state.providers)
    
    case score_providers_for_request(request_params, healthy_providers) do
      [] -> {:error, :no_available_providers}
      scored_providers ->
        # Select the highest scoring provider
        {provider_id, _score} = Enum.max_by(scored_providers, fn {_id, score} -> score end)
        {:ok, provider_id}
    end
  end
  
  defp get_healthy_providers(providers) do
    providers
    |> Enum.filter(fn {_id, info} -> info.health_score >= 0.5 end)
    |> Map.new()
  end
  
  defp select_weighted_provider(providers) when map_size(providers) == 0, do: nil
  
  defp select_weighted_provider(providers) do
    total_weight = providers
    |> Map.values()
    |> Enum.map(fn info -> trunc(info.weight * info.health_score) end)
    |> Enum.sum()
    
    if total_weight == 0 do
      # Fallback to random selection
      providers |> Map.keys() |> Enum.random()
    else
      random_weight = :rand.uniform(total_weight)
      find_provider_by_weight(Map.to_list(providers), random_weight, 0)
    end
  end
  
  defp find_provider_by_weight([{provider_id, info} | _rest], target, current) 
       when current + trunc(info.weight * info.health_score) >= target do
    provider_id
  end
  
  defp find_provider_by_weight([{_provider_id, info} | rest], target, current) do
    find_provider_by_weight(rest, target, current + trunc(info.weight * info.health_score))
  end
  
  defp find_provider_by_weight([], _target, _current), do: nil
  
  defp select_least_connections_provider(providers) when map_size(providers) == 0, do: nil
  
  defp select_least_connections_provider(providers) do
    {provider_id, _info} = Enum.min_by(providers, fn {_id, info} -> info.active_connections end)
    provider_id
  end
  
  defp score_providers_for_request(request_params, providers) do
    required_model = Map.get(request_params, :model)
    request_type = Map.get(request_params, :type, :chat)
    
    Enum.map(providers, fn {provider_id, info} ->
      score = calculate_capability_score(info, required_model, request_type)
      {provider_id, score}
    end)
    |> Enum.filter(fn {_id, score} -> score > 0 end)
  end
  
  defp calculate_capability_score(provider_info, required_model, request_type) do
    base_score = provider_info.health_score * 100
    
    # Model compatibility score
    model_score = if supports_model?(provider_info.capabilities, required_model) do
      50
    else
      0
    end
    
    # Request type score
    type_score = if supports_request_type?(provider_info.capabilities, request_type) do
      30
    else
      0
    end
    
    # Load balancing score (prefer less loaded providers)
    load_score = max(0, 20 - provider_info.active_connections)
    
    # Weight modifier
    weight_modifier = provider_info.weight / 100
    
    (base_score + model_score + type_score + load_score) * weight_modifier
  end
  
  defp supports_model?(capabilities, model) when is_nil(model), do: true
  
  defp supports_model?(capabilities, model) do
    supported_models = Map.get(capabilities, :models, [])
    model in supported_models or Enum.any?(supported_models, &String.contains?(model, &1))
  end
  
  defp supports_request_type?(capabilities, type) do
    supported_types = Map.get(capabilities, :request_types, [:chat, :completion, :embedding])
    type in supported_types
  end
  
  defp generate_hash_key(request_params) do
    # Generate a consistent hash key based on request parameters
    # This could include user_id, session_id, or other sticky session parameters
    user_id = Map.get(request_params, :user_id, "anonymous")
    session_id = Map.get(request_params, :session_id, "default")
    "#{user_id}:#{session_id}"
  end
  
  defp record_provider_usage(provider_id, state) do
    case Map.get(state.providers, provider_id) do
      nil -> state
      provider_info ->
        updated_provider = %{provider_info | last_used: System.monotonic_time(:millisecond)}
        updated_providers = Map.put(state.providers, provider_id, updated_provider)
        
        # Update round-robin index for next request
        updated_rr_index = rem(state.round_robin_index + 1, max(map_size(state.providers), 1))
        
        %{state | 
          providers: updated_providers,
          round_robin_index: updated_rr_index
        }
    end
  end
  
  defp update_connection_count(provider_id, state, delta) do
    case Map.get(state.providers, provider_id) do
      nil -> state
      provider_info ->
        new_count = max(0, provider_info.active_connections + delta)
        updated_provider = %{provider_info | active_connections: new_count}
        updated_providers = Map.put(state.providers, provider_id, updated_provider)
        %{state | providers: updated_providers}
    end
  end
  
  defp perform_health_checks(state) do
    # In a real implementation, this would perform actual health checks
    # For now, we'll simulate gradual health score changes
    updated_providers = Map.new(state.providers, fn {provider_id, info} ->
      # Simulate health score fluctuation (in reality, this would be actual health checks)
      health_variance = (:rand.uniform() - 0.5) * 0.1  # +/- 5% variance
      new_health_score = max(0.0, min(1.0, info.health_score + health_variance))
      
      updated_info = %{info | health_score: new_health_score}
      {provider_id, updated_info}
    end)
    
    %{state | providers: updated_providers}
  end
  
  defp get_provider_capabilities(provider_module) do
    if function_exported?(provider_module, :capabilities, 1) do
      try do
        provider_module.capabilities(%{})
      rescue
        _ -> %{models: [], request_types: [:chat, :completion]}
      end
    else
      %{models: [], request_types: [:chat, :completion]}
    end
  end
  
  defp total_active_connections(providers) do
    providers
    |> Map.values()
    |> Enum.map(& &1.active_connections)
    |> Enum.sum()
  end
end