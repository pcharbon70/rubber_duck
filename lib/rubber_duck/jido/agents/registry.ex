defmodule RubberDuck.Jido.Agents.Registry do
  @moduledoc """
  Agent registry for discovery and metadata management.
  
  Provides:
  - ETS-based registry for fast local lookups
  - Agent metadata storage and querying
  - Tag-based discovery
  - Load-based selection
  - Automatic registration/deregistration
  - Distributed registry support (via Registry)
  
  ## Usage
  
      # Register an agent
      Registry.register("my_agent", pid, %{
        module: MyAgent,
        tags: [:worker, :compute],
        capabilities: [:process_data],
        node: node()
      })
      
      # Find agents by tag
      agents = Registry.find_by_tag(:worker)
      
      # Find agents by capability
      agents = Registry.find_by_capability(:process_data)
      
      # Get least loaded agent
      {:ok, agent} = Registry.get_least_loaded(:worker)
  """
  
  use GenServer
  require Logger
  
  @table_name :rubber_duck_agent_registry
  
  # Client API
  
  @doc """
  Starts the registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers an agent with metadata.
  """
  @spec register(String.t(), pid(), map()) :: :ok | {:error, term()}
  def register(agent_id, pid, metadata \\ %{}) when is_binary(agent_id) and is_pid(pid) do
    GenServer.call(__MODULE__, {:register, agent_id, pid, metadata})
  end
  
  @doc """
  Unregisters an agent.
  """
  @spec unregister(String.t()) :: :ok
  def unregister(agent_id) when is_binary(agent_id) do
    GenServer.call(__MODULE__, {:unregister, agent_id})
  end
  
  @doc """
  Updates agent metadata.
  """
  @spec update_metadata(String.t(), map()) :: :ok | {:error, :not_found}
  def update_metadata(agent_id, metadata) when is_binary(agent_id) and is_map(metadata) do
    GenServer.call(__MODULE__, {:update_metadata, agent_id, metadata})
  end
  
  @doc """
  Gets agent information.
  """
  @spec get_agent(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_agent(agent_id) when is_binary(agent_id) do
    case :ets.lookup(@table_name, agent_id) do
      [{^agent_id, info}] -> {:ok, info}
      [] -> {:error, :not_found}
    end
  end
  
  @doc """
  Lists all registered agents.
  """
  @spec list_agents() :: [map()]
  def list_agents do
    :ets.match_object(@table_name, {:_, :_})
    |> Enum.map(fn {_id, info} -> info end)
  end
  
  @doc """
  Finds agents by tag.
  """
  @spec find_by_tag(atom()) :: [map()]
  def find_by_tag(tag) when is_atom(tag) do
    :ets.match_object(@table_name, {:_, %{tags: :_}})
    |> Enum.filter(fn {_id, info} ->
      tag in Map.get(info, :tags, [])
    end)
    |> Enum.map(fn {_id, info} -> info end)
  end
  
  @doc """
  Finds agents by capability.
  """
  @spec find_by_capability(atom()) :: [map()]
  def find_by_capability(capability) when is_atom(capability) do
    :ets.match_object(@table_name, {:_, %{capabilities: :_}})
    |> Enum.filter(fn {_id, info} ->
      capability in Map.get(info, :capabilities, [])
    end)
    |> Enum.map(fn {_id, info} -> info end)
  end
  
  @doc """
  Finds agents by module.
  """
  @spec find_by_module(module()) :: [map()]
  def find_by_module(module) when is_atom(module) do
    :ets.match_object(@table_name, {:_, %{module: module}})
    |> Enum.map(fn {_id, info} -> info end)
  end
  
  @doc """
  Finds agents on a specific node.
  """
  @spec find_by_node(node()) :: [map()]
  def find_by_node(node) when is_atom(node) do
    :ets.match_object(@table_name, {:_, %{node: node}})
    |> Enum.map(fn {_id, info} -> info end)
  end
  
  @doc """
  Gets the least loaded agent matching criteria.
  """
  @spec get_least_loaded(atom() | nil) :: {:ok, map()} | {:error, :no_agents}
  def get_least_loaded(tag \\ nil) do
    agents = if tag, do: find_by_tag(tag), else: list_agents()
    
    case agents do
      [] -> 
        {:error, :no_agents}
      
      agents ->
        # Sort by load (default to 0 if not present)
        least_loaded = 
          agents
          |> Enum.sort_by(fn agent -> Map.get(agent.metadata, :load, 0) end)
          |> List.first()
          
        {:ok, least_loaded}
    end
  end
  
  @doc """
  Updates agent load metric.
  """
  @spec update_load(String.t(), number()) :: :ok | {:error, :not_found}
  def update_load(agent_id, load) when is_binary(agent_id) and is_number(load) do
    GenServer.call(__MODULE__, {:update_load, agent_id, load})
  end
  
  @doc """
  Queries agents with a match specification.
  """
  @spec query(map()) :: [map()]
  def query(criteria) when is_map(criteria) do
    list_agents()
    |> Enum.filter(fn agent ->
      Enum.all?(criteria, fn {key, value} ->
        case Map.get(agent, key) do
          nil -> false
          agent_value when is_list(agent_value) and is_atom(value) ->
            value in agent_value
          agent_value ->
            agent_value == value
        end
      end)
    end)
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Create ETS table
    :ets.new(@table_name, [
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])
    
    # Monitor registered processes
    Process.flag(:trap_exit, true)
    
    state = %{
      monitors: %{},
      registrations: %{}
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:register, agent_id, pid, metadata}, _from, state) do
    # Check for duplicate registration
    case :ets.lookup(@table_name, agent_id) do
      [{^agent_id, existing}] ->
        if existing.pid == pid do
          # Same process, replace with new metadata completely
          updated = %{
            id: agent_id,
            pid: pid,
            module: metadata[:module] || existing.module,
            tags: metadata[:tags] || existing.tags,
            capabilities: metadata[:capabilities] || existing.capabilities,
            node: metadata[:node] || existing.node,
            registered_at: existing.registered_at,
            metadata: metadata
          }
          :ets.insert(@table_name, {agent_id, updated})
          {:reply, :ok, state}
        else
          {:reply, {:error, :already_registered}, state}
        end
        
      [] ->
        # New registration
        ref = Process.monitor(pid)
        
        info = %{
          id: agent_id,
          pid: pid,
          module: metadata[:module],
          tags: metadata[:tags] || [],
          capabilities: metadata[:capabilities] || [],
          node: metadata[:node] || node(),
          registered_at: DateTime.utc_now(),
          metadata: metadata
        }
        
        :ets.insert(@table_name, {agent_id, info})
        
        # Update state
        monitors = Map.put(state.monitors, ref, agent_id)
        registrations = Map.put(state.registrations, agent_id, ref)
        
        # Emit telemetry
        :telemetry.execute(
          [:rubber_duck, :agent, :registry, :registered],
          %{count: 1},
          %{agent_id: agent_id, module: metadata[:module]}
        )
        
        {:reply, :ok, %{state | monitors: monitors, registrations: registrations}}
    end
  end
  
  @impl true
  def handle_call({:unregister, agent_id}, _from, state) do
    case Map.get(state.registrations, agent_id) do
      nil ->
        {:reply, :ok, state}
        
      ref ->
        # Remove from ETS
        :ets.delete(@table_name, agent_id)
        
        # Stop monitoring
        Process.demonitor(ref, [:flush])
        
        # Update state
        monitors = Map.delete(state.monitors, ref)
        registrations = Map.delete(state.registrations, agent_id)
        
        # Emit telemetry
        :telemetry.execute(
          [:rubber_duck, :agent, :registry, :unregistered],
          %{count: 1},
          %{agent_id: agent_id}
        )
        
        {:reply, :ok, %{state | monitors: monitors, registrations: registrations}}
    end
  end
  
  @impl true
  def handle_call({:update_metadata, agent_id, metadata}, _from, state) do
    case :ets.lookup(@table_name, agent_id) do
      [{^agent_id, info}] ->
        updated = Map.merge(info, %{metadata: Map.merge(info.metadata, metadata)})
        :ets.insert(@table_name, {agent_id, updated})
        {:reply, :ok, state}
        
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_call({:update_load, agent_id, load}, _from, state) do
    case :ets.lookup(@table_name, agent_id) do
      [{^agent_id, info}] ->
        updated_metadata = Map.put(info.metadata, :load, load)
        updated_info = Map.put(info, :metadata, updated_metadata)
        :ets.insert(@table_name, {agent_id, updated_info})
        {:reply, :ok, state}
        
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.get(state.monitors, ref) do
      nil ->
        {:noreply, state}
        
      agent_id ->
        # Remove from ETS
        :ets.delete(@table_name, agent_id)
        
        # Update state
        monitors = Map.delete(state.monitors, ref)
        registrations = Map.delete(state.registrations, agent_id)
        
        # Emit telemetry
        :telemetry.execute(
          [:rubber_duck, :agent, :registry, :process_down],
          %{count: 1},
          %{agent_id: agent_id}
        )
        
        {:noreply, %{state | monitors: monitors, registrations: registrations}}
    end
  end
  
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  @impl true
  def terminate(_reason, _state) do
    :ok
  end
end