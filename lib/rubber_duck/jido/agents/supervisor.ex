defmodule RubberDuck.Jido.Agents.Supervisor do
  @moduledoc """
  Enhanced supervisor for managing Jido agents with advanced lifecycle management.
  
  This supervisor provides:
  - Dynamic agent lifecycle management with Jido integration
  - Configurable supervision strategies
  - Restart policies with exponential backoff
  - Graceful shutdown coordination
  - Integration with health monitoring and telemetry
  
  Agents are supervised as GenServer processes (Agent.Server) that hold the agent's state,
  maintaining compatibility with Jido's data-structure approach.
  """
  
  use Supervisor
  require Logger
  
  @type supervision_strategy :: :one_for_one | :one_for_all | :rest_for_one
  @type restart_policy :: :permanent | :temporary | :transient
  
  @type agent_spec :: %{
    id: any(),
    module: module(),
    args: list(),
    restart: restart_policy(),
    shutdown: timeout() | :brutal_kill,
    type: :worker | :supervisor,
    metadata: map()
  }
  
  @doc """
  Starts the main agent supervisor.
  
  ## Options
  - `:name` - The name to register the supervisor under
  - `:strategy` - The supervision strategy (:one_for_one by default)
  - `:max_restarts` - Maximum number of restarts in the time period (default: 3)
  - `:max_seconds` - Time period for max_restarts (default: 5)
  - `:auto_shutdown` - Auto-shutdown strategy (default: :never)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end
  
  @impl true
  def init(opts) do
    strategy = Keyword.get(opts, :strategy, :one_for_one)
    max_restarts = Keyword.get(opts, :max_restarts, 3)
    max_seconds = Keyword.get(opts, :max_seconds, 5)
    auto_shutdown = Keyword.get(opts, :auto_shutdown, :never)
    
    Logger.info("Starting Jido Agent Supervisor with strategy: #{strategy}")
    
    children = [
      # Agent registry for discovery and metadata
      {RubberDuck.Jido.Agents.Registry, []},
      
      # Dynamic supervisor for runtime agent creation
      {DynamicSupervisor, 
        name: RubberDuck.Jido.Agents.DynamicSupervisor,
        strategy: :one_for_one,
        max_restarts: max_restarts,
        max_seconds: max_seconds
      },
      
      # Restart tracker for exponential backoff
      {RubberDuck.Jido.Agents.RestartTracker, []},
      
      # Shutdown coordinator for graceful termination
      {RubberDuck.Jido.Agents.ShutdownCoordinator, []}
    ]
    
    Supervisor.init(children, 
      strategy: strategy,
      max_restarts: max_restarts,
      max_seconds: max_seconds,
      auto_shutdown: auto_shutdown
    )
  end
  
  @doc """
  Starts a new agent under supervision.
  
  ## Parameters
  - `agent_module` - The Jido agent module to start
  - `initial_state` - Initial state for the agent
  - `opts` - Options for the agent process
  
  ## Options
  - `:id` - Unique identifier for the agent (defaults to generated ID)
  - `:restart` - Restart policy (:temporary, :transient, :permanent)
  - `:shutdown` - Shutdown timeout in milliseconds
  - `:metadata` - Additional metadata to store with the agent
  """
  def start_agent(agent_module, initial_state \\ %{}, opts \\ []) do
    id = Keyword.get_lazy(opts, :id, fn -> generate_agent_id(agent_module) end)
    restart = Keyword.get(opts, :restart, :permanent)
    shutdown = Keyword.get(opts, :shutdown, 5000)
    metadata = Keyword.get(opts, :metadata, %{})
    
    # Check restart tracker for backoff
    case RubberDuck.Jido.Agents.RestartTracker.check_restart(id) do
      :ok ->
        child_spec = build_child_spec(id, agent_module, initial_state, restart, shutdown, metadata)
        
        case DynamicSupervisor.start_child(RubberDuck.Jido.Agents.DynamicSupervisor, child_spec) do
          {:ok, pid} ->
            # Register agent in the registry
            registry_metadata = Map.merge(metadata, %{
              module: agent_module,
              tags: Keyword.get(opts, :tags, []),
              capabilities: Keyword.get(opts, :capabilities, []),
              node: node()
            })
            
            case RubberDuck.Jido.Agents.Registry.register(id, pid, registry_metadata) do
              :ok ->
                Logger.info("Started and registered Jido agent #{inspect(agent_module)} with id #{id} and pid #{inspect(pid)}")
              {:error, reason} ->
                Logger.warning("Agent started but registry failed: #{inspect(reason)}")
            end
            
            :telemetry.execute(
              [:rubber_duck, :jido, :agent, :started],
              %{count: 1},
              %{agent_module: agent_module, agent_id: id, pid: pid}
            )
            {:ok, pid}
            
          {:error, reason} = error ->
            Logger.error("Failed to start Jido agent #{inspect(agent_module)}: #{inspect(reason)}")
            :telemetry.execute(
              [:rubber_duck, :jido, :agent, :start_failed],
              %{count: 1},
              %{agent_module: agent_module, agent_id: id, reason: reason}
            )
            error
        end
        
      {:error, :backoff} = error ->
        Logger.warning("Agent #{id} is in backoff period, refusing to start")
        error
    end
  end
  
  @doc """
  Stops an agent gracefully.
  """
  def stop_agent(agent_id, timeout \\ 5000) do
    case find_agent_pid(agent_id) do
      {:ok, pid} ->
        Logger.info("Initiating graceful shutdown for agent #{agent_id}")
        
        # Unregister from registry first
        RubberDuck.Jido.Agents.Registry.unregister(agent_id)
        
        # Coordinate shutdown
        RubberDuck.Jido.Agents.ShutdownCoordinator.coordinate_shutdown(agent_id, pid, timeout)
        
      {:error, :not_found} ->
        {:error, :agent_not_found}
    end
  end
  
  @doc """
  Lists all supervised agents with their metadata.
  """
  def list_agents do
    # Use Registry as the source of truth
    RubberDuck.Jido.Agents.Registry.list_agents()
  end
  
  @doc """
  Gets detailed agent info by ID.
  """
  def get_agent(agent_id) do
    # Use Registry as the source of truth
    RubberDuck.Jido.Agents.Registry.get_agent(agent_id)
  end
  
  @doc """
  Updates agent restart policy at runtime.
  """
  def update_restart_policy(agent_id, new_policy) when new_policy in [:permanent, :temporary, :transient] do
    # Store policy updates in ETS for next restart
    :ets.insert(:agent_restart_policies, {agent_id, new_policy})
    Logger.info("Updated restart policy for #{agent_id} to #{new_policy} (effective on next restart)")
    :ok
  end
  
  @doc """
  Performs a rolling restart of agents matching the filter.
  """
  def rolling_restart(filter_fn \\ fn _ -> true end, opts \\ []) do
    delay = Keyword.get(opts, :delay, 1000)
    batch_size = Keyword.get(opts, :batch_size, 1)
    
    agents = list_agents() |> Enum.filter(filter_fn)
    total = length(agents)
    
    Logger.info("Starting rolling restart of #{total} agents (batch size: #{batch_size})")
    
    agents
    |> Enum.chunk_every(batch_size)
    |> Enum.with_index()
    |> Enum.each(fn {batch, index} ->
      Logger.info("Restarting batch #{index + 1}")
      
      Enum.each(batch, fn agent_info ->
        restart_agent(agent_info)
      end)
      
      if index < div(total, batch_size), do: Process.sleep(delay)
    end)
    
    Logger.info("Rolling restart completed")
    :ok
  end
  
  @doc """
  Finds agents by tag.
  """
  defdelegate find_by_tag(tag), to: RubberDuck.Jido.Agents.Registry
  
  @doc """
  Finds agents by capability.
  """
  defdelegate find_by_capability(capability), to: RubberDuck.Jido.Agents.Registry
  
  @doc """
  Finds agents by module.
  """
  defdelegate find_by_module(module), to: RubberDuck.Jido.Agents.Registry
  
  @doc """
  Gets the least loaded agent.
  """
  defdelegate get_least_loaded(tag \\ nil), to: RubberDuck.Jido.Agents.Registry
  
  @doc """
  Queries agents with criteria.
  """
  defdelegate query(criteria), to: RubberDuck.Jido.Agents.Registry
  
  @doc """
  Gets supervision tree statistics.
  """
  def stats do
    children = DynamicSupervisor.which_children(RubberDuck.Jido.Agents.DynamicSupervisor)
    agents = list_agents()
    
    %{
      total_agents: length(children),
      active_agents: length(agents),
      agents_by_module: group_by_module(agents),
      agents_by_restart_policy: group_by_restart_policy(agents),
      supervision_strategy: get_supervision_strategy(),
      restart_stats: RubberDuck.Jido.Agents.RestartTracker.get_stats()
    }
  end
  
  @doc """
  Enables or disables restart backoff for testing.
  """
  def set_backoff_enabled(enabled) when is_boolean(enabled) do
    RubberDuck.Jido.Agents.RestartTracker.set_enabled(enabled)
  end
  
  # Private functions
  
  defp generate_agent_id(agent_module) do
    timestamp = System.system_time(:microsecond)
    random = :rand.uniform(999999)
    module_name = agent_module |> Module.split() |> List.last() |> String.downcase()
    "#{module_name}_#{timestamp}_#{random}"
  end
  
  defp build_child_spec(id, agent_module, initial_state, restart, shutdown, metadata) do
    # Check for stored restart policy override
    restart = case :ets.lookup(:agent_restart_policies, id) do
      [{^id, policy}] -> policy
      [] -> restart
    end
    
    %{
      id: {:agent, id},
      start: {RubberDuck.Jido.Agents.Server, :start_link, [
        [
          agent_module: agent_module,
          agent_id: id,
          initial_state: initial_state,
          metadata: metadata
        ]
      ]},
      restart: restart,
      shutdown: shutdown,
      type: :worker
    }
  end
  
  defp find_agent_pid(agent_id) do
    case RubberDuck.Jido.Agents.Registry.get_agent(agent_id) do
      {:ok, agent_info} -> {:ok, agent_info.pid}
      {:error, :not_found} -> {:error, :not_found}
    end
  end
  
  
  defp restart_agent(%{id: agent_id, pid: pid}) do
    Logger.info("Restarting agent #{agent_id}")
    
    # Record restart
    RubberDuck.Jido.Agents.RestartTracker.record_restart(agent_id)
    
    # Terminate the child
    DynamicSupervisor.terminate_child(RubberDuck.Jido.Agents.DynamicSupervisor, pid)
    
    :telemetry.execute(
      [:rubber_duck, :jido, :agent, :restarted],
      %{count: 1},
      %{agent_id: agent_id}
    )
  end
  
  defp group_by_module(agents) do
    agents
    |> Enum.group_by(& &1.module)
    |> Map.new(fn {module, list} -> {module, length(list)} end)
  end
  
  defp group_by_restart_policy(agents) do
    agents
    |> Enum.group_by(fn agent -> Map.get(agent.metadata, :restart_policy, :permanent) end)
    |> Map.new(fn {policy, list} -> {policy, length(list)} end)
  end
  
  defp get_supervision_strategy do
    # Would query actual supervisor state in production
    :one_for_one
  end
end