defmodule RubberDuck.Jido do
  @moduledoc """
  Main interface for Jido agent framework integration in RubberDuck.
  
  This module provides proper integration with Jido following official patterns:
  - Agents are data structures, not processes
  - Actions are the primary work units
  - State management through Jido.Runtime
  - CloudEvents-based signal routing
  
  ## Architecture
  
  Unlike traditional GenServer-based agents, Jido agents are:
  1. Data structures with schema and behavior
  2. Executed by worker processes from a pool
  3. Stateless between executions (state is persisted)
  4. Communicate through actions and signals
  
  ## Core Components
  
  - **AgentRegistry**: ETS-based storage for agent data
  - **Runtime**: Executes actions with lifecycle management
  - **SignalRouter**: Maps CloudEvents to actions
  - **Actions**: Discrete, composable work units
  
  ## Usage Examples
  
      # Create an agent
      {:ok, agent} = RubberDuck.Jido.create_agent(MyAgent, %{name: "agent1"})
      
      # Execute an action directly
      {:ok, result, agent} = RubberDuck.Jido.execute_action(agent, MyAction, %{param: "value"})
      
      # Send a signal (converts to action via SignalRouter)
      :ok = RubberDuck.Jido.send_signal(agent.id, %{
        "type" => "my_signal", 
        "data" => %{"param" => "value"}
      })
      
      # List all agents
      agents = RubberDuck.Jido.list_agents()
      
      # Get system status
      status = RubberDuck.Jido.system_status()
  
  ## Implementation Notes
  
  This implementation follows the official Jido patterns where agents are data
  structures that are acted upon by a runtime system, rather than being 
  long-running processes. This provides better scalability, fault tolerance,
  and testability.
  
  See `lib/rubber_duck/jido/refactoring_docs.md` for migration guide.
  """
  
  alias RubberDuck.Jido.{AgentRegistry, Runtime, SignalRouter}
  require Logger
  
  @doc """
  Creates a new agent instance.
  
  Agents are data structures stored in the registry, not processes.
  """
  @spec create_agent(module(), map()) :: {:ok, map()} | {:error, term()}
  def create_agent(agent_module, initial_state \\ %{}) do
    agent_id = generate_agent_id()
    
    # Build agent data structure
    agent = %{
      id: agent_id,
      module: agent_module,
      state: build_initial_state(agent_module, initial_state),
      metadata: %{
        created_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now(),
        version: 1
      }
    }
    
    # Validate against schema
    case validate_agent_state(agent_module, agent.state) do
      :ok ->
        # Store in registry
        :ok = AgentRegistry.register(agent)
        
        # Emit telemetry
        :telemetry.execute(
          [:rubber_duck, :jido, :agent, :created],
          %{count: 1},
          %{agent_id: agent_id, module: agent_module}
        )
        
        Logger.info("Created Jido agent #{agent_id} of type #{inspect(agent_module)}")
        {:ok, agent}
        
      {:error, errors} ->
        {:error, {:validation_failed, errors}}
    end
  end
  
  @doc """
  Executes an action on an agent.
  
  This is the primary way to interact with agents.
  """
  @spec execute_action(map() | String.t(), module(), map()) :: 
    {:ok, term(), map()} | {:error, term()}
  def execute_action(agent_or_id, action_module, params \\ %{}) do
    with {:ok, agent} <- get_agent(agent_or_id),
         {:ok, result, updated_agent} <- Runtime.execute(agent, action_module, params) do
      # Update registry
      :ok = AgentRegistry.update(updated_agent)
      
      # Emit telemetry
      :telemetry.execute(
        [:rubber_duck, :jido, :action, :executed],
        %{count: 1},
        %{
          agent_id: agent.id,
          action: action_module,
          success: true
        }
      )
      
      {:ok, result, updated_agent}
    end
  end
  
  @doc """
  Sends a signal to an agent.
  
  Signals are converted to appropriate actions by the SignalRouter.
  """
  @spec send_signal(String.t() | map(), map()) :: :ok | {:error, term()}
  def send_signal(agent_or_id, signal) do
    with {:ok, agent} <- get_agent(agent_or_id) do
      SignalRouter.route(agent, signal)
    end
  end
  
  @doc """
  Broadcasts a signal to all agents matching a pattern.
  """
  @spec broadcast_signal(map(), keyword()) :: :ok
  def broadcast_signal(signal, opts \\ []) do
    SignalRouter.broadcast(signal, opts)
  end
  
  @doc """
  Gets an agent by ID.
  """
  @spec get_agent(String.t() | map()) :: {:ok, map()} | {:error, :not_found}
  def get_agent(%{id: id}), do: get_agent(id)
  def get_agent(agent_id) when is_binary(agent_id) do
    AgentRegistry.get(agent_id)
  end
  
  @doc """
  Lists all agents with optional filtering.
  """
  @spec list_agents(keyword()) :: [map()]
  def list_agents(opts \\ []) do
    AgentRegistry.list(opts)
  end
  
  @doc """
  Deletes an agent.
  """
  @spec delete_agent(String.t() | map()) :: :ok | {:error, term()}
  def delete_agent(agent_or_id) do
    with {:ok, agent} <- get_agent(agent_or_id) do
      AgentRegistry.unregister(agent.id)
      
      # Emit telemetry
      :telemetry.execute(
        [:rubber_duck, :jido, :agent, :deleted],
        %{count: 1},
        %{agent_id: agent.id, module: agent.module}
      )
      
      :ok
    end
  end
  
  @doc """
  Gets system status and metrics.
  """
  @spec system_status() :: map()
  def system_status do
    %{
      agents: %{
        total: length(list_agents()),
        by_type: count_by_type()
      },
      runtime: Runtime.status(),
      signals: SignalRouter.stats(),
      uptime: get_uptime()
    }
  end
  
  # Private functions
  
  defp generate_agent_id do
    "agent_#{Uniq.UUID.uuid4()}"
  end
  
  defp build_initial_state(agent_module, overrides) do
    # Get default state from schema
    default_state = get_default_state(agent_module)
    
    # Merge with overrides
    Map.merge(default_state, overrides)
  end
  
  defp get_default_state(agent_module) do
    # Get schema from module options if available
    # Since we're using `use Jido.Agent`, the schema is stored differently
    # For now, let's manually check for known agents
    cond do
      agent_module == RubberDuck.Jido.Agents.ExampleAgent ->
        %{
          counter: 0,
          messages: [],
          status: :idle,
          last_action: nil
        }
        
      # Default case - empty state
      true ->
        %{}
    end
  end
  
  defp validate_agent_state(_agent_module, _state) do
    # For now, basic validation
    # TODO: Integrate with NimbleOptions or similar
    :ok
  end
  
  defp count_by_type do
    list_agents()
    |> Enum.group_by(& &1.module)
    |> Enum.map(fn {module, agents} -> {module, length(agents)} end)
    |> Map.new()
  end
  
  defp get_uptime do
    # Calculate uptime based on supervisor start
    case Process.whereis(RubberDuck.Jido.Supervisor) do
      nil -> 0
      pid when is_pid(pid) ->
        # Use a different approach for uptime
        # For now, return a placeholder
        0
    end
  end
end