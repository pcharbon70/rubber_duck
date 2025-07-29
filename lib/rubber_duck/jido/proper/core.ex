defmodule RubberDuck.Jido.Proper.Core do
  @moduledoc """
  Proper Jido integration following official patterns.
  
  This module demonstrates how Jido should be integrated according to
  the official documentation, using agents as data structures and
  actions as the primary work units.
  """
  
  require Logger
  
  @doc """
  Creates a new Jido agent instance.
  
  Unlike the GenServer approach, this creates a data structure
  that represents the agent, not a process.
  """
  def create_agent(agent_module, initial_state \\ %{}) do
    agent_id = generate_agent_id()
    
    agent = %{
      id: agent_id,
      module: agent_module,
      state: Map.merge(get_default_state(agent_module), initial_state),
      created_at: DateTime.utc_now(),
      metadata: %{}
    }
    
    # Store agent in registry (ETS or similar)
    store_agent(agent)
    
    {:ok, agent}
  end
  
  @doc """
  Executes an action on an agent.
  
  This is the primary way to interact with Jido agents.
  """
  def execute_action(agent, action_module, params \\ %{}) do
    context = %{
      agent: agent,
      timestamp: DateTime.utc_now()
    }
    
    case action_module.run(params, context) do
      {:ok, result, %{agent: updated_agent}} ->
        # Update stored agent
        store_agent(updated_agent)
        
        # Emit telemetry
        :telemetry.execute(
          [:rubber_duck, :jido, :action, :executed],
          %{duration: 0}, # Would calculate actual duration
          %{
            agent_id: agent.id,
            action: action_module,
            success: true
          }
        )
        
        {:ok, result, updated_agent}
        
      {:error, reason} = error ->
        # Emit telemetry for error
        :telemetry.execute(
          [:rubber_duck, :jido, :action, :failed],
          %{count: 1},
          %{
            agent_id: agent.id,
            action: action_module,
            error: reason
          }
        )
        
        error
    end
  end
  
  @doc """
  Enqueues an instruction for later execution.
  
  This demonstrates how to queue actions for async processing.
  """
  def enqueue_instruction(agent, instruction) do
    # In a real implementation, this would use Jido.Runtime
    # For now, we'll just execute immediately
    action = instruction[:action]
    params = instruction[:params] || %{}
    
    execute_action(agent, action, params)
  end
  
  @doc """
  Gets an agent by ID.
  """
  def get_agent(agent_id) do
    case :ets.lookup(agent_table(), agent_id) do
      [{^agent_id, agent}] -> {:ok, agent}
      [] -> {:error, :not_found}
    end
  end
  
  @doc """
  Lists all agents.
  """
  def list_agents do
    :ets.tab2list(agent_table())
    |> Enum.map(fn {_id, agent} -> agent end)
  end
  
  # Private functions
  
  defp generate_agent_id do
    "agent_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
  
  defp get_default_state(agent_module) do
    # Get schema from agent module and build default state
    if function_exported?(agent_module, :__schema__, 0) do
      agent_module.__schema__()
      |> Enum.reduce(%{}, fn {key, opts}, acc ->
        Map.put(acc, key, opts[:default])
      end)
    else
      %{}
    end
  end
  
  defp store_agent(agent) do
    :ets.insert(agent_table(), {agent.id, agent})
  end
  
  defp agent_table do
    table_name = :rubber_duck_jido_agents
    
    case :ets.whereis(table_name) do
      :undefined ->
        :ets.new(table_name, [:named_table, :public, :set])
      ref ->
        ref
    end
  end
end