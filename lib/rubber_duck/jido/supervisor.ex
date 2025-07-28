defmodule RubberDuck.Jido.Supervisor do
  @moduledoc """
  Main supervisor for the Jido agent framework integration.

  This supervisor manages all Jido-related processes including:
  - Agent supervisor (DynamicSupervisor for agents)
  - Signal router and dispatcher
  - Workflow engine
  - Registry for agent discovery

  The supervisor is configured to use a one-for-one strategy with
  configurable restart intensity based on the application configuration.
  """

  use Supervisor

  require Logger

  @doc """
  Starts the Jido supervisor.
  """
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Starts a new agent under the agent supervisor.

  Delegates to the AgentSupervisor for actual agent creation.
  """
  @spec start_agent(atom(), map()) :: {:ok, pid()} | {:error, term()}
  def start_agent(agent_type, config) do
    RubberDuck.Jido.AgentSupervisor.start_agent(agent_type, config)
  end

  @doc """
  Lists all active agents.

  Delegates to the AgentSupervisor.
  """
  @spec list_agents() :: [map()]
  def list_agents do
    RubberDuck.Jido.AgentSupervisor.list_agents()
  end

  @impl true
  def init(_init_arg) do
    # Get configuration
    config = Application.get_env(:rubber_duck, :jido, [])
    
    # Extract supervisor configuration
    supervisor_config = Keyword.get(config, :agent_supervisor, [])
    max_restarts = Keyword.get(supervisor_config, :max_restarts, 3)
    max_seconds = Keyword.get(supervisor_config, :max_seconds, 5)

    children = [
      # Registry for agent discovery
      {Registry, 
       keys: :unique, 
       name: RubberDuck.Jido.Registry,
       partitions: System.schedulers_online()},
      
      # Signal dispatcher for CloudEvents messaging
      {RubberDuck.Jido.SignalDispatcher, []},
      
      # Dynamic supervisor for agents
      {RubberDuck.Jido.AgentSupervisor, []},
      
      # Workflow engine (if enabled)
      workflow_child_spec(config)
    ]
    |> Enum.filter(& &1)  # Remove nil entries

    Logger.info("Starting Jido supervisor with max_restarts=#{max_restarts}, max_seconds=#{max_seconds}")

    Supervisor.init(children, 
      strategy: :one_for_one,
      max_restarts: max_restarts,
      max_seconds: max_seconds
    )
  end

  # Private functions

  defp workflow_child_spec(config) do
    workflow_config = Keyword.get(config, :workflow_engine, [])
    
    if Keyword.get(workflow_config, :enabled, true) do
      {RubberDuck.Jido.WorkflowEngine, workflow_config}
    else
      nil
    end
  end
end