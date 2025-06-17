defmodule RubberDuck.CodingAssistant.EngineSupervisor do
  @moduledoc """
  Distributed supervisor for coding assistance engines using Horde.
  
  This supervisor manages the lifecycle of coding assistance engines across
  the distributed RubberDuck cluster. It leverages Horde for distributed
  supervision, ensuring engines are automatically distributed across nodes
  and restarted on failure.
  
  ## Features
  
  - Distributed engine supervision with Horde
  - Automatic engine distribution across cluster nodes
  - Failover and recovery of engines
  - Dynamic engine registration and spawning
  - Health monitoring integration
  - Load balancing across available nodes
  
  ## Engine Types
  
  The supervisor can manage different types of engines:
  - CodeAnalyser: Code analysis and understanding
  - ExplanationEngine: Code explanation and documentation
  - RefactoringEngine: Code refactoring suggestions
  - TestGenerator: Test generation and validation
  
  ## Usage
  
      # Start an engine
      {:ok, pid} = EngineSupervisor.start_engine(CodeAnalyser, %{model: "gpt-4"})
      
      # Stop an engine
      :ok = EngineSupervisor.stop_engine(CodeAnalyser)
      
      # List all engines
      engines = EngineSupervisor.list_engines()
  """

  use Horde.DynamicSupervisor

  alias RubberDuck.CodingAssistant.EngineRegistry

  @doc """
  Start the engine supervisor.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Horde.DynamicSupervisor.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Initialize the supervisor with Horde configuration.
  """
  def init(opts) do
    strategy = Keyword.get(opts, :strategy, :one_for_one)
    max_restarts = Keyword.get(opts, :max_restarts, 10)
    max_seconds = Keyword.get(opts, :max_seconds, 60)
    
    # Get distributed strategy configuration
    distribution_strategy = get_distribution_strategy(opts)
    
    Horde.DynamicSupervisor.init(
      strategy: strategy,
      max_restarts: max_restarts,
      max_seconds: max_seconds,
      distribution_strategy: distribution_strategy,
      members: get_cluster_members()
    )
  end

  @doc """
  Start a coding assistance engine with the given configuration.
  
  ## Parameters
  - `engine_module` - The engine module to start (must implement EngineBehaviour)
  - `config` - Configuration map for the engine
  - `opts` - Additional options (name, restart strategy, etc.)
  
  ## Returns
  - `{:ok, pid}` - Engine started successfully
  - `{:error, reason}` - Failed to start engine
  """
  def start_engine(engine_module, config \\ %{}, opts \\ []) do
    validate_engine_module!(engine_module)
    
    # Generate unique ID for this engine instance
    engine_id = generate_engine_id(engine_module, config)
    
    # Prepare child specification
    child_spec = build_engine_child_spec(engine_module, config, engine_id, opts)
    
    # Start the engine using Horde
    case Horde.DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        # Register the engine for discovery
        register_engine(engine_module, engine_id, pid, config)
        
        # Emit telemetry
        emit_telemetry([:engine, :supervisor, :started], %{}, %{
          engine: engine_module,
          engine_id: engine_id,
          node: Node.self()
        })
        
        {:ok, pid}
        
      {:error, {:already_started, pid}} ->
        {:ok, pid}
        
      {:error, reason} ->
        emit_telemetry([:engine, :supervisor, :start_failed], %{}, %{
          engine: engine_module,
          engine_id: engine_id,
          reason: reason
        })
        
        {:error, reason}
    end
  end

  @doc """
  Stop a running engine.
  
  ## Parameters
  - `engine_module` - The engine module to stop
  - `engine_id` - Optional specific engine ID (if multiple instances)
  
  ## Returns
  - `:ok` - Engine stopped successfully
  - `{:error, reason}` - Failed to stop engine
  """
  def stop_engine(engine_module, engine_id \\ nil) do
    case find_engine_pid(engine_module, engine_id) do
      {:ok, pid} ->
        # Unregister from discovery
        unregister_engine(engine_module, engine_id)
        
        # Stop the engine
        case Horde.DynamicSupervisor.terminate_child(__MODULE__, pid) do
          :ok ->
            emit_telemetry([:engine, :supervisor, :stopped], %{}, %{
              engine: engine_module,
              engine_id: engine_id
            })
            :ok
            
          {:error, reason} ->
            {:error, reason}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Restart an engine (stop and start with same configuration).
  """
  def restart_engine(engine_module, engine_id \\ nil) do
    case get_engine_config(engine_module, engine_id) do
      {:ok, config} ->
        case stop_engine(engine_module, engine_id) do
          :ok ->
            start_engine(engine_module, config)
          {:error, reason} ->
            {:error, {:stop_failed, reason}}
        end
        
      {:error, reason} ->
        {:error, {:config_not_found, reason}}
    end
  end

  @doc """
  List all running engines in the cluster.
  
  ## Returns
  List of engine information maps containing:
  - `:engine` - Engine module
  - `:engine_id` - Engine instance ID
  - `:pid` - Process ID
  - `:node` - Node where engine is running
  - `:config` - Engine configuration
  - `:started_at` - Start timestamp
  """
  def list_engines do
    __MODULE__
    |> Horde.DynamicSupervisor.which_children()
    |> Enum.map(&extract_engine_info/1)
    |> Enum.filter(& &1)
  end

  @doc """
  List engines by type/module.
  """
  def list_engines(engine_module) do
    list_engines()
    |> Enum.filter(fn info -> info.engine == engine_module end)
  end

  @doc """
  Get detailed information about a specific engine.
  """
  def get_engine_info(engine_module, engine_id \\ nil) do
    case find_engine_pid(engine_module, engine_id) do
      {:ok, pid} ->
        try do
          capabilities = GenServer.call(pid, :capabilities, 5000)
          health = GenServer.call(pid, :health_status, 5000)
          statistics = GenServer.call(pid, :statistics, 5000)
          
          {:ok, %{
            engine: engine_module,
            engine_id: engine_id,
            pid: pid,
            node: node_of_pid(pid),
            capabilities: capabilities,
            health: health,
            statistics: statistics
          }}
        catch
          :exit, {:timeout, _} ->
            {:error, :timeout}
          :exit, reason ->
            {:error, {:engine_dead, reason}}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Ensure a specific engine type is running.
  
  If the engine is not running, it will be started with the given configuration.
  If it's already running, returns the existing PID.
  """
  def ensure_engine(engine_module, config \\ %{}) do
    case find_engine_pid(engine_module) do
      {:ok, pid} when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          start_engine(engine_module, config)
        end
        
      {:error, :not_found} ->
        start_engine(engine_module, config)
    end
  end

  @doc """
  Get cluster health for engine distribution.
  """
  def cluster_health do
    nodes = get_cluster_members()
    engines_per_node = get_engines_per_node()
    
    %{
      total_nodes: length(nodes),
      active_nodes: length(Map.keys(engines_per_node)),
      total_engines: Enum.sum(Map.values(engines_per_node)),
      engines_per_node: engines_per_node,
      distribution_balance: calculate_distribution_balance(engines_per_node)
    }
  end

  # Private implementation

  defp validate_engine_module!(engine_module) do
    unless function_exported?(engine_module, :behaviour_info, 1) do
      raise ArgumentError, "#{engine_module} does not implement EngineBehaviour"
    end
    
    required_callbacks = RubberDuck.CodingAssistant.EngineBehaviour.behaviour_info(:callbacks)
    module_callbacks = engine_module.behaviour_info(:callbacks)
    
    missing_callbacks = required_callbacks -- module_callbacks
    unless Enum.empty?(missing_callbacks) do
      raise ArgumentError, 
        "#{engine_module} is missing required callbacks: #{inspect(missing_callbacks)}"
    end
  end

  defp generate_engine_id(engine_module, config) do
    base_id = engine_module |> Module.split() |> List.last()
    config_hash = :crypto.hash(:md5, :erlang.term_to_binary(config)) |> Base.encode16()
    timestamp = System.system_time(:microsecond)
    
    "#{base_id}_#{String.slice(config_hash, 0, 8)}_#{timestamp}"
  end

  defp build_engine_child_spec(engine_module, config, engine_id, opts) do
    restart_strategy = Keyword.get(opts, :restart, :permanent)
    shutdown_timeout = Keyword.get(opts, :shutdown, 5_000)
    
    %{
      id: {:engine, engine_module, engine_id},
      start: {engine_module, :start_link, [Map.put(config, :engine_id, engine_id)]},
      restart: restart_strategy,
      shutdown: shutdown_timeout,
      type: :worker,
      modules: [engine_module]
    }
  end

  defp get_distribution_strategy(opts) do
    case Keyword.get(opts, :distribution, :balanced) do
      :balanced -> Horde.UniformDistribution
      :random -> Horde.UniformRandomDistribution  
      :local -> Horde.UniformQuorumDistribution
      custom when is_atom(custom) -> custom
    end
  end

  defp get_cluster_members do
    # Get members from existing Horde registry or supervisor
    case Process.whereis(RubberDuck.DistributedState.HordeRegistry) do
      nil -> [Node.self()]
      _pid -> 
        Horde.Registry.members(RubberDuck.DistributedState.HordeRegistry)
        |> Enum.map(fn {_, node_id} -> node_id end)
        |> Enum.uniq()
    end
  rescue
    _ -> [Node.self()]
  end

  defp register_engine(engine_module, engine_id, pid, config) do
    Registry.register(EngineRegistry, {engine_module, engine_id}, %{
      pid: pid,
      config: config,
      started_at: DateTime.utc_now(),
      node: Node.self()
    })
  end

  defp unregister_engine(engine_module, engine_id) do
    Registry.unregister(EngineRegistry, {engine_module, engine_id})
  end

  defp find_engine_pid(engine_module, engine_id \\ nil) do
    pattern = case engine_id do
      nil -> {engine_module, :_}
      id -> {engine_module, id}
    end
    
    case Registry.match(EngineRegistry, pattern, :_) do
      [] ->
        {:error, :not_found}
      [{key, pid, _meta}] ->
        {:ok, pid}
      matches when length(matches) > 1 and is_nil(engine_id) ->
        # If multiple engines and no specific ID, return first
        [{key, pid, _meta} | _] = matches
        {:ok, pid}
      matches ->
        {:error, {:multiple_matches, length(matches)}}
    end
  end

  defp get_engine_config(engine_module, engine_id) do
    pattern = case engine_id do
      nil -> {engine_module, :_}
      id -> {engine_module, id}
    end
    
    case Registry.match(EngineRegistry, pattern, :_) do
      [] ->
        {:error, :not_found}
      [{key, _pid, meta}] ->
        {:ok, meta.config}
      _matches ->
        {:error, :multiple_matches}
    end
  end

  defp extract_engine_info({:undefined, pid, :worker, [engine_module]}) when is_pid(pid) do
    case Registry.keys(EngineRegistry, pid) do
      [{engine_module, engine_id}] ->
        case Registry.lookup(EngineRegistry, {engine_module, engine_id}) do
          [{_pid, meta}] ->
            %{
              engine: engine_module,
              engine_id: engine_id,
              pid: pid,
              node: node_of_pid(pid),
              config: meta.config,
              started_at: meta.started_at
            }
          _ ->
            nil
        end
      _ ->
        nil
    end
  end
  defp extract_engine_info(_), do: nil

  defp node_of_pid(pid) when is_pid(pid) do
    case :rpc.call(node(pid), Process, :alive?, [pid]) do
      true -> node(pid)
      _ -> :unknown
    end
  end

  defp get_engines_per_node do
    list_engines()
    |> Enum.group_by(& &1.node)
    |> Map.new(fn {node, engines} -> {node, length(engines)} end)
  end

  defp calculate_distribution_balance(engines_per_node) when map_size(engines_per_node) <= 1 do
    1.0  # Perfect balance with 0 or 1 nodes
  end
  defp calculate_distribution_balance(engines_per_node) do
    counts = Map.values(engines_per_node)
    total = Enum.sum(counts)
    avg = total / length(counts)
    
    # Calculate coefficient of variation (lower is better balance)
    variance = Enum.reduce(counts, 0, fn count, acc ->
      acc + :math.pow(count - avg, 2)
    end) / length(counts)
    
    std_dev = :math.sqrt(variance)
    cv = if avg > 0, do: std_dev / avg, else: 0
    
    # Convert to balance score (1.0 is perfect, 0.0 is worst)
    max(0.0, 1.0 - cv)
  end

  defp emit_telemetry(event_name, measurements, metadata) do
    :telemetry.execute(event_name, measurements, metadata)
  rescue
    _ -> :ok  # Telemetry not available
  end
end