defmodule RubberDuck.CodingAssistant.EngineRegistry do
  @moduledoc """
  Registry for engine discovery and capability-based routing.
  
  This module provides a distributed registry for coding assistance engines,
  enabling discovery, capability matching, and load balancing across the
  cluster. It integrates with the existing Horde infrastructure for
  distributed operation.
  
  ## Features
  
  - Engine registration and discovery
  - Capability-based engine selection
  - Load balancing and health-aware routing
  - Cross-node engine visibility
  - Performance metrics collection
  - Automatic cleanup of dead engines
  
  ## Usage
  
      # Find engines by capability
      engines = EngineRegistry.find_engines_by_capability(:code_analysis)
      
      # Get best engine for a task
      {:ok, engine_pid} = EngineRegistry.get_best_engine(:refactoring, %{language: "elixir"})
      
      # Register custom engine
      :ok = EngineRegistry.register_engine(MyEngine, %{capabilities: [:custom]})
  """

  use GenServer
  
  alias RubberDuck.CodingAssistant.{EngineBehaviour, EngineSupervisor}

  # Registry name for local process registration
  @registry_name __MODULE__

  # ETS table for engine metadata
  @engines_table :coding_assistant_engines

  # Health check interval (30 seconds)
  @health_check_interval 30_000

  # Engine selection strategies
  @selection_strategies [:round_robin, :least_loaded, :health_weighted, :capability_match]

  @type engine_info :: %{
    engine: module(),
    engine_id: String.t(),
    pid: pid(),
    node: node(),
    capabilities: [atom()],
    health: EngineBehaviour.health_status(),
    statistics: map(),
    last_seen: DateTime.t(),
    load_score: float()
  }

  @type selection_strategy :: :round_robin | :least_loaded | :health_weighted | :capability_match
  @type selection_criteria :: %{
    capabilities: [atom()],
    strategy: selection_strategy(),
    exclude_unhealthy: boolean(),
    preferred_node: node() | nil,
    max_load: float()
  }

  ## Public API

  @doc """
  Start the engine registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @registry_name)
  end

  @doc """
  Register an engine in the registry.
  
  This is typically called automatically by the EngineSupervisor.
  """
  def register_engine(engine_module, engine_id, pid, metadata \\ %{}) do
    GenServer.call(@registry_name, {:register_engine, engine_module, engine_id, pid, metadata})
  end

  @doc """
  Unregister an engine from the registry.
  """
  def unregister_engine(engine_module, engine_id) do
    GenServer.call(@registry_name, {:unregister_engine, engine_module, engine_id})
  end

  @doc """
  Find all engines that support the given capabilities.
  
  ## Parameters
  - `capabilities` - List of required capabilities
  - `opts` - Options for filtering (health, node, etc.)
  
  ## Returns
  List of engine info maps
  """
  def find_engines_by_capability(capabilities, opts \\ []) when is_list(capabilities) do
    GenServer.call(@registry_name, {:find_engines_by_capability, capabilities, opts})
  end

  @doc """
  Get the best engine for a given set of requirements.
  
  ## Parameters
  - `capabilities` - Required capabilities
  - `criteria` - Selection criteria map
  
  ## Returns
  - `{:ok, engine_info}` - Best matching engine
  - `{:error, reason}` - No suitable engine found
  """
  def get_best_engine(capabilities, criteria \\ %{}) when is_list(capabilities) do
    GenServer.call(@registry_name, {:get_best_engine, capabilities, criteria})
  end

  @doc """
  List all registered engines.
  """
  def list_engines(opts \\ []) do
    GenServer.call(@registry_name, {:list_engines, opts})
  end

  @doc """
  Get detailed information about a specific engine.
  """
  def get_engine_info(engine_module, engine_id) do
    GenServer.call(@registry_name, {:get_engine_info, engine_module, engine_id})
  end

  @doc """
  Update engine health and statistics.
  
  This is called periodically by engines to report their status.
  """
  def update_engine_status(engine_module, engine_id, health, statistics) do
    GenServer.cast(@registry_name, {:update_engine_status, engine_module, engine_id, health, statistics})
  end

  @doc """
  Get registry statistics and health.
  """
  def get_registry_stats do
    GenServer.call(@registry_name, :get_registry_stats)
  end

  @doc """
  Force cleanup of dead engines.
  """
  def cleanup_dead_engines do
    GenServer.cast(@registry_name, :cleanup_dead_engines)
  end

  ## GenServer Implementation

  @impl GenServer
  def init(opts) do
    # Create ETS table for engine metadata
    :ets.new(@engines_table, [:set, :public, :named_table, {:read_concurrency, true}])
    
    # Schedule periodic health checks
    schedule_health_check()
    
    state = %{
      engines: %{},
      selection_counters: %{},
      startup_time: DateTime.utc_now(),
      health_check_interval: Keyword.get(opts, :health_check_interval, @health_check_interval)
    }
    
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:register_engine, engine_module, engine_id, pid, metadata}, _from, state) do
    case register_engine_internal(engine_module, engine_id, pid, metadata) do
      :ok ->
        # Monitor the engine process
        Process.monitor(pid)
        
        # Update state
        key = {engine_module, engine_id}
        new_engines = Map.put(state.engines, key, %{
          pid: pid,
          registered_at: DateTime.utc_now()
        })
        
        emit_telemetry([:registry, :engine, :registered], %{}, %{
          engine: engine_module,
          engine_id: engine_id,
          node: node(pid)
        })
        
        {:reply, :ok, %{state | engines: new_engines}}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:unregister_engine, engine_module, engine_id}, _from, state) do
    key = {engine_module, engine_id}
    
    # Remove from ETS
    :ets.delete(@engines_table, key)
    
    # Update state
    new_engines = Map.delete(state.engines, key)
    
    emit_telemetry([:registry, :engine, :unregistered], %{}, %{
      engine: engine_module,
      engine_id: engine_id
    })
    
    {:reply, :ok, %{state | engines: new_engines}}
  end

  @impl GenServer
  def handle_call({:find_engines_by_capability, capabilities, opts}, _from, state) do
    engines = find_engines_by_capability_internal(capabilities, opts)
    {:reply, engines, state}
  end

  @impl GenServer
  def handle_call({:get_best_engine, capabilities, criteria}, _from, state) do
    case get_best_engine_internal(capabilities, criteria, state) do
      {:ok, engine_info} ->
        # Update selection counter for round robin
        strategy = Map.get(criteria, :strategy, :round_robin)
        new_counters = update_selection_counter(state.selection_counters, strategy, capabilities)
        
        {:reply, {:ok, engine_info}, %{state | selection_counters: new_counters}}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:list_engines, opts}, _from, state) do
    engines = list_engines_internal(opts)
    {:reply, engines, state}
  end

  @impl GenServer
  def handle_call({:get_engine_info, engine_module, engine_id}, _from, state) do
    case :ets.lookup(@engines_table, {engine_module, engine_id}) do
      [{_key, engine_info}] ->
        {:reply, {:ok, engine_info}, state}
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_registry_stats, _from, state) do
    stats = %{
      total_engines: :ets.info(@engines_table, :size),
      engines_by_type: get_engines_by_type(),
      engines_by_node: get_engines_by_node(),
      engines_by_health: get_engines_by_health(),
      registry_uptime: DateTime.diff(DateTime.utc_now(), state.startup_time, :second),
      selection_counters: state.selection_counters
    }
    
    {:reply, stats, state}
  end

  @impl GenServer
  def handle_cast({:update_engine_status, engine_module, engine_id, health, statistics}, state) do
    key = {engine_module, engine_id}
    
    case :ets.lookup(@engines_table, key) do
      [{^key, engine_info}] ->
        # Calculate load score based on statistics
        load_score = calculate_load_score(statistics)
        
        # Update engine info
        updated_info = %{engine_info |
          health: health,
          statistics: statistics,
          last_seen: DateTime.utc_now(),
          load_score: load_score
        }
        
        :ets.insert(@engines_table, {key, updated_info})
        
        {:noreply, state}
        
      [] ->
        # Engine not found, ignore update
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast(:cleanup_dead_engines, state) do
    dead_engines = find_dead_engines()
    
    Enum.each(dead_engines, fn {engine_module, engine_id} ->
      :ets.delete(@engines_table, {engine_module, engine_id})
    end)
    
    if length(dead_engines) > 0 do
      emit_telemetry([:registry, :cleanup], %{cleaned_count: length(dead_engines)}, %{})
    end
    
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Find and remove the dead engine
    case find_engine_by_pid(pid) do
      {:ok, {engine_module, engine_id}} ->
        key = {engine_module, engine_id}
        :ets.delete(@engines_table, key)
        
        new_engines = Map.delete(state.engines, key)
        
        emit_telemetry([:registry, :engine, :died], %{}, %{
          engine: engine_module,
          engine_id: engine_id,
          pid: pid
        })
        
        {:noreply, %{state | engines: new_engines}}
        
      {:error, :not_found} ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:health_check, state) do
    # Perform health checks on all engines
    perform_health_checks()
    
    # Schedule next health check
    schedule_health_check(state.health_check_interval)
    
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_message, state) do
    {:noreply, state}
  end

  ## Private Implementation

  defp register_engine_internal(engine_module, engine_id, pid, metadata) do
    # Get capabilities from the engine
    capabilities = try do
      GenServer.call(pid, :capabilities, 5000)
    catch
      :exit, _ -> []
    end
    
    # Get initial health and statistics
    {health, statistics} = try do
      health = GenServer.call(pid, :health_status, 5000)
      stats = GenServer.call(pid, :statistics, 5000)
      {health, stats}
    catch
      :exit, _ -> {:unknown, %{}}
    end
    
    # Create engine info
    engine_info = %{
      engine: engine_module,
      engine_id: engine_id,
      pid: pid,
      node: node(pid),
      capabilities: capabilities,
      health: health,
      statistics: statistics,
      last_seen: DateTime.utc_now(),
      load_score: 0.0,
      metadata: metadata
    }
    
    # Store in ETS
    key = {engine_module, engine_id}
    :ets.insert(@engines_table, {key, engine_info})
    
    :ok
  end

  defp find_engines_by_capability_internal(required_capabilities, opts) do
    exclude_unhealthy = Keyword.get(opts, :exclude_unhealthy, true)
    preferred_node = Keyword.get(opts, :preferred_node)
    max_load = Keyword.get(opts, :max_load, 1.0)
    
    :ets.tab2list(@engines_table)
    |> Enum.map(fn {_key, engine_info} -> engine_info end)
    |> Enum.filter(fn engine_info ->
      has_capabilities?(engine_info.capabilities, required_capabilities) and
      health_filter(engine_info.health, exclude_unhealthy) and
      node_filter(engine_info.node, preferred_node) and
      load_filter(engine_info.load_score, max_load)
    end)
  end

  defp get_best_engine_internal(capabilities, criteria, state) do
    strategy = Map.get(criteria, :strategy, :round_robin)
    
    candidates = find_engines_by_capability_internal(capabilities, Map.to_list(criteria))
    
    case candidates do
      [] ->
        {:error, :no_engines_available}
        
      engines ->
        case select_engine_by_strategy(engines, strategy, capabilities, state) do
          {:ok, engine} -> {:ok, engine}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp list_engines_internal(opts) do
    include_metadata = Keyword.get(opts, :include_metadata, false)
    
    engines = :ets.tab2list(@engines_table)
    |> Enum.map(fn {_key, engine_info} -> engine_info end)
    
    if include_metadata do
      engines
    else
      Enum.map(engines, fn engine_info ->
        Map.drop(engine_info, [:metadata, :statistics])
      end)
    end
  end

  defp select_engine_by_strategy(engines, strategy, capabilities, state) do
    case strategy do
      :round_robin ->
        select_round_robin(engines, capabilities, state)
        
      :least_loaded ->
        select_least_loaded(engines)
        
      :health_weighted ->
        select_health_weighted(engines)
        
      :capability_match ->
        select_capability_match(engines, capabilities)
        
      _ ->
        {:error, :unknown_strategy}
    end
  end

  defp select_round_robin(engines, capabilities, state) do
    key = {:round_robin, capabilities}
    counter = Map.get(state.selection_counters, key, 0)
    index = rem(counter, length(engines))
    
    {:ok, Enum.at(engines, index)}
  end

  defp select_least_loaded(engines) do
    engine = Enum.min_by(engines, & &1.load_score)
    {:ok, engine}
  end

  defp select_health_weighted(engines) do
    healthy_engines = Enum.filter(engines, &(&1.health == :healthy))
    
    case healthy_engines do
      [] ->
        # Fall back to degraded engines if no healthy ones
        degraded_engines = Enum.filter(engines, &(&1.health == :degraded))
        case degraded_engines do
          [] -> {:error, :no_healthy_engines}
          [engine | _] -> {:ok, engine}
        end
        
      [engine | _] ->
        # Select least loaded among healthy engines
        {:ok, Enum.min_by(healthy_engines, & &1.load_score)}
    end
  end

  defp select_capability_match(engines, required_capabilities) do
    # Score engines by capability overlap and select best match
    scored_engines = Enum.map(engines, fn engine ->
      overlap = length(engine.capabilities -- (engine.capabilities -- required_capabilities))
      score = overlap / length(required_capabilities)
      {engine, score}
    end)
    
    {best_engine, _score} = Enum.max_by(scored_engines, fn {_engine, score} -> score end)
    {:ok, best_engine}
  end

  defp has_capabilities?(engine_capabilities, required_capabilities) do
    required_capabilities
    |> Enum.all?(fn cap -> cap in engine_capabilities end)
  end

  defp health_filter(health, exclude_unhealthy) do
    if exclude_unhealthy do
      health in [:healthy, :degraded]
    else
      true
    end
  end

  defp node_filter(engine_node, preferred_node) do
    case preferred_node do
      nil -> true
      node -> engine_node == node
    end
  end

  defp load_filter(load_score, max_load) do
    load_score <= max_load
  end

  defp update_selection_counter(counters, strategy, capabilities) do
    key = {strategy, capabilities}
    Map.update(counters, key, 1, &(&1 + 1))
  end

  defp calculate_load_score(statistics) do
    # Calculate load score based on statistics (0.0 = no load, 1.0 = max load)
    real_time_load = calculate_mode_load(statistics[:real_time] || %{})
    batch_load = calculate_mode_load(statistics[:batch] || %{})
    
    # Weight real-time higher since it's more latency sensitive
    (real_time_load * 0.7) + (batch_load * 0.3)
  end

  defp calculate_mode_load(mode_stats) do
    total = Map.get(mode_stats, :total_requests, 0)
    failed = Map.get(mode_stats, :failed_requests, 0)
    avg_time = Map.get(mode_stats, :average_processing_time, 0.0)
    
    # Base load on request volume and failure rate
    request_load = min(total / 100.0, 1.0)  # Normalize to max 100 requests
    failure_load = if total > 0, do: failed / total, else: 0.0
    time_load = min(avg_time / 100_000.0, 1.0)  # Normalize to 100ms max
    
    (request_load + failure_load + time_load) / 3.0
  end

  defp find_dead_engines do
    cutoff_time = DateTime.add(DateTime.utc_now(), -300, :second)  # 5 minutes ago
    
    :ets.tab2list(@engines_table)
    |> Enum.filter(fn {_key, engine_info} ->
      DateTime.compare(engine_info.last_seen, cutoff_time) == :lt or
      not Process.alive?(engine_info.pid)
    end)
    |> Enum.map(fn {{engine_module, engine_id}, _info} -> {engine_module, engine_id} end)
  end

  defp find_engine_by_pid(pid) do
    case :ets.tab2list(@engines_table) |> Enum.find(fn {_key, info} -> info.pid == pid end) do
      {key, _info} -> {:ok, key}
      nil -> {:error, :not_found}
    end
  end

  defp perform_health_checks do
    :ets.tab2list(@engines_table)
    |> Enum.each(fn {{engine_module, engine_id}, engine_info} ->
      Task.start(fn ->
        case GenServer.call(engine_info.pid, :health_status, 5000) do
          health when health in [:healthy, :degraded, :unhealthy] ->
            update_engine_status(engine_module, engine_id, health, engine_info.statistics)
          _ ->
            :ok
        end
      end)
    end)
  rescue
    _ -> :ok
  end

  defp schedule_health_check(interval \\ @health_check_interval) do
    Process.send_after(self(), :health_check, interval)
  end

  defp get_engines_by_type do
    :ets.tab2list(@engines_table)
    |> Enum.group_by(fn {_key, info} -> info.engine end)
    |> Map.new(fn {engine, engines} -> {engine, length(engines)} end)
  end

  defp get_engines_by_node do
    :ets.tab2list(@engines_table)
    |> Enum.group_by(fn {_key, info} -> info.node end)
    |> Map.new(fn {node, engines} -> {node, length(engines)} end)
  end

  defp get_engines_by_health do
    :ets.tab2list(@engines_table)
    |> Enum.group_by(fn {_key, info} -> info.health end)
    |> Map.new(fn {health, engines} -> {health, length(engines)} end)
  end

  defp emit_telemetry(event_name, measurements, metadata) do
    :telemetry.execute(event_name, measurements, metadata)
  rescue
    _ -> :ok  # Telemetry not available
  end
end