defmodule RubberDuck.Agents.Coordinator do
  @moduledoc """
  Central coordinator for managing agent interactions, task delegation, and workflow orchestration.

  The Coordinator serves as the central brain for the agentic system, responsible for:
  - Intelligent task routing to appropriate agents
  - Multi-agent collaboration and workflow execution
  - Resource management and load balancing
  - Conflict resolution and result aggregation
  - Health monitoring and recovery

  ## Features

  - **Smart Task Routing**: Analyzes tasks and routes to best-suited agents
  - **Workflow Orchestration**: Coordinates multi-agent workflows
  - **Load Balancing**: Distributes work across available agents
  - **Result Aggregation**: Combines results from multiple agents
  - **Conflict Resolution**: Handles disagreements between agents
  - **Health Monitoring**: Tracks agent health and performance

  ## Usage

      # Start the coordinator
      {:ok, pid} = Coordinator.start_link()

      # Execute a complex workflow
      {:ok, result} = Coordinator.execute_workflow(workflow_spec, context)

      # Route a single task
      {:ok, result} = Coordinator.route_task(task, context)

      # Get system status
      status = Coordinator.get_system_status()
  """

  use GenServer

  alias RubberDuck.Agents.{Supervisor, Registry, Agent}
  # alias RubberDuck.Memory.Manager, as: MemoryManager
  # alias RubberDuck.MessageBus

  require Logger

  @registry_name RubberDuck.Agents.Registry

  @type workflow_spec :: map()
  @type task_spec :: map()
  @type context :: map()
  @type coordination_result :: {:ok, term()} | {:error, term()}

  # Client API

  @doc """
  Starts the agent coordinator.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Executes a complex workflow involving multiple agents.

  ## Parameters

  - `workflow_spec` - Workflow specification map
  - `context` - Execution context with user preferences and memory
  - `opts` - Additional options

  ## Workflow Spec Format

      %{
        id: "unique_workflow_id",
        type: :code_analysis | :code_generation | :research | :review,
        steps: [
          %{
            id: "step_1",
            agent_type: :research,
            task: %{...},
            depends_on: [],
            parallel: false
          },
          %{
            id: "step_2", 
            agent_type: :analysis,
            task: %{...},
            depends_on: ["step_1"],
            parallel: true
          }
        ],
        aggregation: :merge | :reduce | :custom,
        timeout: 60_000
      }

  ## Returns

  - `{:ok, result}` - Workflow completed successfully
  - `{:error, reason}` - Workflow failed
  """
  @spec execute_workflow(workflow_spec(), context(), keyword()) :: coordination_result()
  def execute_workflow(workflow_spec, context \\ %{}, opts \\ []) do
    GenServer.call(__MODULE__, {:execute_workflow, workflow_spec, context, opts}, Keyword.get(opts, :timeout, 60_000))
  end

  @doc """
  Routes a single task to the most appropriate agent.

  ## Parameters

  - `task` - Task specification
  - `context` - Execution context
  - `opts` - Routing options

  ## Task Spec Format

      %{
        id: "unique_task_id",
        type: :analyze_code | :generate_code | :research_topic | :review_changes,
        priority: :low | :medium | :high | :critical,
        payload: %{...},
        requirements: [:semantic_search, :code_analysis],
        deadline: ~U[2024-01-01 12:00:00Z]
      }

  ## Returns

  - `{:ok, result}` - Task completed successfully
  - `{:error, reason}` - Task failed or no suitable agent
  """
  @spec route_task(task_spec(), context(), keyword()) :: coordination_result()
  def route_task(task, context \\ %{}, opts \\ []) do
    GenServer.call(__MODULE__, {:route_task, task, context, opts}, Keyword.get(opts, :timeout, 30_000))
  end

  @doc """
  Gets comprehensive system status including all agents and workflows.

  ## Returns

  Status map containing:
  - `:agents` - Status of all agents
  - `:active_workflows` - Currently executing workflows
  - `:system_health` - Overall system health
  - `:performance_metrics` - System-wide metrics
  - `:resource_usage` - Resource utilization
  """
  @spec get_system_status() :: map()
  def get_system_status do
    GenServer.call(__MODULE__, :get_system_status)
  end

  @doc """
  Starts a new agent of the specified type.

  ## Parameters

  - `agent_type` - Type of agent to start
  - `config` - Agent configuration
  - `opts` - Additional options

  ## Returns

  - `{:ok, agent_id}` - Agent started successfully
  - `{:error, reason}` - Failed to start agent
  """
  @spec start_agent(atom(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def start_agent(agent_type, config \\ %{}, opts \\ []) do
    GenServer.call(__MODULE__, {:start_agent, agent_type, config, opts})
  end

  @doc """
  Stops an agent by ID.

  ## Parameters

  - `agent_id` - Agent identifier

  ## Returns

  - `:ok` - Agent stopped successfully
  - `{:error, reason}` - Failed to stop agent
  """
  @spec stop_agent(String.t()) :: :ok | {:error, term()}
  def stop_agent(agent_id) do
    GenServer.call(__MODULE__, {:stop_agent, agent_id})
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    # Subscribe to agent events
    # MessageBus.subscribe("agents.events")

    state = %{
      active_workflows: %{},
      workflow_counter: 0,
      agent_pools: %{
        research: [],
        analysis: [],
        generation: [],
        review: []
      },
      system_metrics: initialize_system_metrics(),
      config: Keyword.get(opts, :config, %{}),
      started_at: DateTime.utc_now()
    }

    # Start initial agent pool
    start_initial_agents(state)

    Logger.info("Agent Coordinator started")
    {:ok, state}
  end

  @impl true
  def handle_call({:execute_workflow, workflow_spec, context, _opts}, from, state) do
    workflow_id = generate_workflow_id(state)

    case validate_workflow_spec(workflow_spec) do
      :ok ->
        # Start workflow execution
        workflow_state = %{
          id: workflow_id,
          spec: workflow_spec,
          context: context,
          from: from,
          started_at: DateTime.utc_now(),
          status: :running,
          completed_steps: [],
          pending_steps: workflow_spec.steps,
          results: %{}
        }

        new_active_workflows = Map.put(state.active_workflows, workflow_id, workflow_state)
        new_state = %{state | active_workflows: new_active_workflows}

        # Start executing workflow
        send(self(), {:execute_workflow_steps, workflow_id})

        {:noreply, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:route_task, task, context, _opts}, from, state) do
    case find_best_agent(task, state) do
      {:ok, agent_id} ->
        # Execute task on selected agent
        execute_task_on_agent(agent_id, task, context, from, state)

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_system_status, _from, state) do
    status = build_system_status(state)
    {:reply, status, state}
  end

  @impl true
  def handle_call({:start_agent, agent_type, config, opts}, _from, state) do
    case Supervisor.start_agent(agent_type, config, opts) do
      {:ok, pid} ->
        # Get agent ID from registry
        case Registry.find_agent_by_pid(@registry_name, pid) do
          {:ok, agent_id, _metadata} ->
            # Add to agent pool
            new_pools = update_agent_pool(state.agent_pools, agent_type, agent_id, :add)
            new_state = %{state | agent_pools: new_pools}

            {:reply, {:ok, agent_id}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:stop_agent, agent_id}, _from, state) do
    case Supervisor.stop_agent(agent_id) do
      :ok ->
        # Remove from agent pools
        new_pools = remove_agent_from_pools(state.agent_pools, agent_id)
        new_state = %{state | agent_pools: new_pools}

        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:execute_workflow_steps, workflow_id}, state) do
    case Map.get(state.active_workflows, workflow_id) do
      nil ->
        Logger.warning("Workflow #{workflow_id} not found")
        {:noreply, state}

      workflow_state ->
        new_state = execute_next_workflow_steps(workflow_state, state)
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info({:task_completed, workflow_id, step_id, result}, state) do
    new_state = handle_workflow_step_completion(workflow_id, step_id, result, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:task_failed, workflow_id, step_id, reason}, state) do
    new_state = handle_workflow_step_failure(workflow_id, step_id, reason, state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:message_bus, topic, message}, state) do
    case topic do
      "agents.events" ->
        handle_agent_event(message, state)

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Coordinator received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp start_initial_agents(_state) do
    # Start one agent of each type by default
    agent_types = [:research, :analysis, :generation, :review]

    Enum.each(agent_types, fn agent_type ->
      config = %{
        name: "default_#{agent_type}",
        pool: :default
      }

      case Supervisor.start_agent(agent_type, config) do
        {:ok, _pid} ->
          Logger.info("Started default #{agent_type} agent")

        {:error, reason} ->
          Logger.error("Failed to start default #{agent_type} agent: #{inspect(reason)}")
      end
    end)
  end

  defp validate_workflow_spec(spec) do
    required_fields = [:id, :type, :steps]

    case Enum.all?(required_fields, &Map.has_key?(spec, &1)) do
      true -> :ok
      false -> {:error, :invalid_workflow_spec}
    end
  end

  defp generate_workflow_id(state) do
    new_counter = state.workflow_counter + 1
    "workflow_#{new_counter}_#{System.system_time(:millisecond)}"
  end

  defp find_best_agent(task, state) do
    required_capabilities = Map.get(task, :requirements, [])
    agent_type = determine_agent_type(task)

    # Find agents of the appropriate type with required capabilities
    available_agents = Map.get(state.agent_pools, agent_type, [])

    case find_capable_agent(available_agents, required_capabilities) do
      nil ->
        # Try to start a new agent if none available
        case start_agent_for_task(agent_type, task) do
          {:ok, agent_id} -> {:ok, agent_id}
          error -> error
        end

      agent_id ->
        {:ok, agent_id}
    end
  end

  defp determine_agent_type(%{type: type}) do
    case type do
      t when t in [:analyze_code, :security_review, :code_analysis] -> :analysis
      t when t in [:generate_code, :refactor_code, :code_generation] -> :generation
      t when t in [:research_topic, :gather_context, :semantic_search] -> :research
      t when t in [:review_changes, :quality_review, :code_review] -> :review
      # Default to analysis
      _ -> :analysis
    end
  end

  defp find_capable_agent(agent_ids, required_capabilities) do
    Enum.find(agent_ids, fn agent_id ->
      case Registry.lookup_agent(@registry_name, agent_id) do
        {:ok, %{status: :running, capabilities: capabilities}} ->
          required_capabilities
          |> Enum.all?(fn cap -> cap in (capabilities || []) end)

        _ ->
          false
      end
    end)
  end

  defp start_agent_for_task(agent_type, task) do
    config = %{
      name: "task_#{task.id}",
      task_specific: true,
      requirements: Map.get(task, :requirements, [])
    }

    Supervisor.start_agent(agent_type, config)
  end

  defp execute_task_on_agent(agent_id, task, context, from, state) do
    # Get agent PID from registry
    case Registry.lookup_agent(@registry_name, agent_id) do
      {:ok, %{pid: pid}} ->
        # Execute task asynchronously
        Task.start(fn ->
          case Agent.assign_task(pid, task, context) do
            {:ok, result} ->
              GenServer.reply(from, {:ok, result})

            {:error, reason} ->
              GenServer.reply(from, {:error, reason})
          end
        end)

        {:noreply, state}

      {:error, :not_found} ->
        {:reply, {:error, :agent_not_found}, state}
    end
  end

  defp execute_next_workflow_steps(workflow_state, state) do
    # Find steps that can be executed (dependencies satisfied)
    executable_steps = find_executable_steps(workflow_state)

    case executable_steps do
      [] ->
        # No more steps to execute, check if workflow is complete
        if Enum.empty?(workflow_state.pending_steps) do
          complete_workflow(workflow_state, state)
        else
          # Waiting for dependencies
          state
        end

      steps ->
        # Execute the steps
        Enum.reduce(steps, state, fn step, acc_state ->
          execute_workflow_step(workflow_state.id, step, workflow_state.context, acc_state)
        end)
    end
  end

  defp find_executable_steps(workflow_state) do
    completed_step_ids = MapSet.new(workflow_state.completed_steps)

    Enum.filter(workflow_state.pending_steps, fn step ->
      dependencies = Map.get(step, :depends_on, [])
      Enum.all?(dependencies, fn dep -> dep in completed_step_ids end)
    end)
  end

  defp execute_workflow_step(workflow_id, step, context, state) do
    # agent_type = step.agent_type

    case find_best_agent(%{type: step.task.type, requirements: []}, state) do
      {:ok, agent_id} ->
        # Execute step on agent
        Task.start(fn ->
          case Registry.lookup_agent(@registry_name, agent_id) do
            {:ok, %{pid: pid}} ->
              case Agent.assign_task(pid, step.task, context) do
                {:ok, result} ->
                  send(__MODULE__, {:task_completed, workflow_id, step.id, result})

                {:error, reason} ->
                  send(__MODULE__, {:task_failed, workflow_id, step.id, reason})
              end

            {:error, reason} ->
              send(__MODULE__, {:task_failed, workflow_id, step.id, reason})
          end
        end)

        state

      {:error, reason} ->
        # Step failed to start
        send(self(), {:task_failed, workflow_id, step.id, reason})
        state
    end
  end

  defp handle_workflow_step_completion(workflow_id, step_id, result, state) do
    case Map.get(state.active_workflows, workflow_id) do
      nil ->
        state

      workflow_state ->
        # Update workflow state
        new_workflow_state = %{
          workflow_state
          | completed_steps: [step_id | workflow_state.completed_steps],
            pending_steps: Enum.reject(workflow_state.pending_steps, &(&1.id == step_id)),
            results: Map.put(workflow_state.results, step_id, result)
        }

        new_active_workflows = Map.put(state.active_workflows, workflow_id, new_workflow_state)
        new_state = %{state | active_workflows: new_active_workflows}

        # Continue workflow execution
        send(self(), {:execute_workflow_steps, workflow_id})

        new_state
    end
  end

  defp handle_workflow_step_failure(workflow_id, step_id, reason, state) do
    case Map.get(state.active_workflows, workflow_id) do
      nil ->
        state

      workflow_state ->
        # Mark workflow as failed
        GenServer.reply(workflow_state.from, {:error, {step_id, reason}})

        # Remove from active workflows
        new_active_workflows = Map.delete(state.active_workflows, workflow_id)
        %{state | active_workflows: new_active_workflows}
    end
  end

  defp complete_workflow(workflow_state, state) do
    # Aggregate results
    final_result = aggregate_workflow_results(workflow_state)

    # Reply to caller
    GenServer.reply(workflow_state.from, {:ok, final_result})

    # Remove from active workflows
    new_active_workflows = Map.delete(state.active_workflows, workflow_state.id)
    %{state | active_workflows: new_active_workflows}
  end

  defp aggregate_workflow_results(workflow_state) do
    # Simple aggregation - in production this would be more sophisticated
    %{
      workflow_id: workflow_state.id,
      results: workflow_state.results,
      completed_at: DateTime.utc_now(),
      execution_time: DateTime.diff(DateTime.utc_now(), workflow_state.started_at, :millisecond)
    }
  end

  defp build_system_status(state) do
    agent_stats = Registry.get_stats(@registry_name)

    %{
      coordinator: %{
        started_at: state.started_at,
        active_workflows: map_size(state.active_workflows),
        system_metrics: state.system_metrics
      },
      agents: agent_stats,
      workflows: Map.keys(state.active_workflows),
      agent_pools:
        Map.new(state.agent_pools, fn {type, agents} ->
          {type, length(agents)}
        end)
    }
  end

  defp initialize_system_metrics do
    %{
      workflows_executed: 0,
      tasks_routed: 0,
      agents_started: 0,
      total_execution_time: 0
    }
  end

  defp update_agent_pool(pools, agent_type, agent_id, :add) do
    current_pool = Map.get(pools, agent_type, [])
    Map.put(pools, agent_type, [agent_id | current_pool])
  end

  defp remove_agent_from_pools(pools, agent_id) do
    Map.new(pools, fn {type, agent_list} ->
      {type, Enum.reject(agent_list, &(&1 == agent_id))}
    end)
  end

  defp handle_agent_event(message, state) do
    # Handle agent lifecycle events
    case message do
      %{event: :agent_started, agent_id: agent_id, agent_type: agent_type} ->
        new_pools = update_agent_pool(state.agent_pools, agent_type, agent_id, :add)
        {:noreply, %{state | agent_pools: new_pools}}

      %{event: :agent_stopped, agent_id: agent_id} ->
        new_pools = remove_agent_from_pools(state.agent_pools, agent_id)
        {:noreply, %{state | agent_pools: new_pools}}

      _ ->
        {:noreply, state}
    end
  end
end
