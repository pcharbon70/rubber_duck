defmodule RubberDuck.Jido.AgentRegistry do
  @moduledoc """
  Registry for Jido agents.
  
  Stores agents as data structures in ETS, providing fast lookup
  and concurrent access. Agents are not processes, just data.
  """
  
  use GenServer
  require Logger
  
  @table_name :rubber_duck_jido_agents
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Registers a new agent.
  """
  @spec register(map()) :: :ok | {:error, :already_exists}
  def register(agent) do
    GenServer.call(__MODULE__, {:register, agent})
  end
  
  @doc """
  Updates an existing agent.
  """
  @spec update(map()) :: :ok | {:error, :not_found}
  def update(agent) do
    GenServer.call(__MODULE__, {:update, agent})
  end
  
  @doc """
  Gets an agent by ID.
  """
  @spec get(String.t()) :: {:ok, map()} | {:error, :not_found}
  def get(agent_id) do
    case :ets.lookup(@table_name, agent_id) do
      [{^agent_id, agent}] -> {:ok, agent}
      [] -> {:error, :not_found}
    end
  end
  
  @doc """
  Lists all agents with optional filtering.
  """
  @spec list(keyword()) :: [map()]
  def list(opts \\ []) do
    agents = :ets.tab2list(@table_name)
    |> Enum.map(fn {_id, agent} -> agent end)
    
    # Apply filters
    agents
    |> filter_by_module(opts[:module])
    |> filter_by_state(opts[:state_match])
    |> sort_agents(opts[:sort_by])
  end
  
  @doc """
  Unregisters an agent.
  """
  @spec unregister(String.t()) :: :ok | {:error, :not_found}
  def unregister(agent_id) do
    GenServer.call(__MODULE__, {:unregister, agent_id})
  end
  
  @doc """
  Counts agents by module type.
  """
  @spec count_by_module() :: map()
  def count_by_module do
    :ets.foldl(
      fn {_id, agent}, acc ->
        Map.update(acc, agent.module, 1, &(&1 + 1))
      end,
      %{},
      @table_name
    )
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Create ETS table for agents
    :ets.new(@table_name, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])
    
    Logger.info("Jido AgentRegistry started")
    
    {:ok, %{}}
  end
  
  @impl true
  def handle_call({:register, agent}, _from, state) do
    case :ets.lookup(@table_name, agent.id) do
      [] ->
        # Set initial version
        true
        
        :ets.insert(@table_name, {agent.id, agent})
        {:reply, :ok, state}
        
      [_] ->
        {:reply, {:error, :already_exists}, state}
    end
  end
  
  @impl true
  def handle_call({:update, agent}, _from, state) do
    case :ets.lookup(@table_name, agent.id) do
      [{_id, existing}] ->
        # Increment version and update timestamp
        agent = put_in(agent.metadata.version, existing.metadata.version + 1)
        agent = put_in(agent.metadata.updated_at, DateTime.utc_now())
        
        :ets.insert(@table_name, {agent.id, agent})
        {:reply, :ok, state}
        
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_call({:unregister, agent_id}, _from, state) do
    case :ets.lookup(@table_name, agent_id) do
      [{_id, _agent}] ->
        :ets.delete(@table_name, agent_id)
        {:reply, :ok, state}
        
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  # Private functions
  
  defp filter_by_module(agents, nil), do: agents
  defp filter_by_module(agents, module) do
    Enum.filter(agents, &(&1.module == module))
  end
  
  defp filter_by_state(agents, nil), do: agents
  defp filter_by_state(agents, state_match) do
    Enum.filter(agents, fn agent ->
      Enum.all?(state_match, fn {key, value} ->
        Map.get(agent.state, key) == value
      end)
    end)
  end
  
  defp sort_agents(agents, nil), do: agents
  defp sort_agents(agents, :created_at) do
    Enum.sort_by(agents, & &1.metadata.created_at, DateTime)
  end
  defp sort_agents(agents, :updated_at) do
    Enum.sort_by(agents, & &1.metadata.updated_at, {:desc, DateTime})
  end
  defp sort_agents(agents, field) when is_atom(field) do
    Enum.sort_by(agents, & &1.state[field])
  end
end