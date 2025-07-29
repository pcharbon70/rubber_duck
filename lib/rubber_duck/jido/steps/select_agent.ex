defmodule RubberDuck.Jido.Steps.SelectAgent do
  @moduledoc """
  A Reactor step that selects an agent based on specified criteria.
  
  This step provides various strategies for agent selection, enabling
  load balancing and intelligent routing in workflows.
  
  ## Arguments
  
  - `:criteria` - Selection criteria (tag, capability, or custom function)
  - `:strategy` - Selection strategy (:least_loaded, :round_robin, :random)
  
  ## Options
  
  - `:fallback` - What to do if no agent matches (default: :error)
  - `:spawn_if_needed` - Spawn a new agent if none available (default: false)
  - `:agent_module` - Module to spawn if needed
  
  ## Example
  
      step :select_worker, RubberDuck.Jido.Steps.SelectAgent do
        argument :criteria, value({:tag, :worker})
        argument :strategy, value(:least_loaded)
      end
  """
  
  use Reactor.Step
  
  alias RubberDuck.Jido.Agents.{Registry, Supervisor, PoolManager}
  
  @doc false
  @impl true
  def run(arguments, context, options) do
    strategy = arguments[:strategy] || :least_loaded
    fallback = options[:fallback] || :error
    
    case select_agent(arguments.criteria, strategy, context) do
      {:ok, agent_id} -> 
        {:ok, agent_id}
        
      {:error, :no_agents} ->
        cond do
          options[:spawn_if_needed] ->
            spawn_agent(options[:agent_module], arguments.criteria)
            
          fallback == :wait ->
            # Return a retry signal to Reactor
            {:retry, :no_agents_available}
            
          true ->
            {:error, :no_agents}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc false
  @impl true
  def compensate({:retry, :no_agents_available}, _arguments, _context, _options) do
    # Allow retry when no agents are available
    :retry
  end
  
  def compensate(_error, _arguments, _context, _options) do
    :ok
  end
  
  # Private functions
  
  defp select_agent({:tag, tag}, strategy, _context) do
    agents = Registry.find_by_tag(tag)
    select_from_agents(agents, strategy)
  end
  
  defp select_agent({:capability, capability}, strategy, _context) do
    agents = Registry.find_by_capability(capability)
    select_from_agents(agents, strategy)
  end
  
  defp select_agent({:pool, pool_name}, _strategy, _context) do
    # For pools, use the pool's own selection strategy
    case PoolManager.checkout(pool_name) do
      {:ok, agent_id} -> {:ok, agent_id}
      {:error, _} -> {:error, :no_agents}
    end
  end
  
  defp select_agent({:custom, fun}, strategy, context) when is_function(fun) do
    agents = Registry.list_agents()
    filtered = Enum.filter(agents, &fun.(&1, context))
    select_from_agents(filtered, strategy)
  end
  
  defp select_from_agents([], _strategy), do: {:error, :no_agents}
  
  defp select_from_agents(agents, :least_loaded) do
    case Registry.get_least_loaded(agents) do
      {:ok, agent} -> {:ok, agent.id}
      {:error, reason} -> {:error, reason}
    end
  end
  
  defp select_from_agents(agents, :random) do
    agent = Enum.random(agents)
    {:ok, agent.id}
  end
  
  defp select_from_agents(agents, :round_robin) do
    # Use process dictionary for simple round-robin
    # In production, you'd want a more robust solution
    key = {:round_robin_index, agents}
    index = Process.get(key, 0)
    agent = Enum.at(agents, rem(index, length(agents)))
    Process.put(key, index + 1)
    {:ok, agent.id}
  end
  
  defp spawn_agent(nil, _criteria) do
    {:error, :no_agent_module_specified}
  end
  
  defp spawn_agent(agent_module, {:tag, tag}) do
    case Supervisor.start_agent(agent_module, %{}, tags: [tag]) do
      {:ok, pid} ->
        # Get the agent ID from the pid
        case Registry.list_agents() |> Enum.find(&(&1.pid == pid)) do
          nil -> {:error, :agent_not_registered}
          agent -> {:ok, agent.id}
        end
      {:error, reason} ->
        {:error, {:spawn_failed, reason}}
    end
  end
  
  defp spawn_agent(agent_module, _criteria) do
    spawn_agent(agent_module, {:tag, :default})
  end
end