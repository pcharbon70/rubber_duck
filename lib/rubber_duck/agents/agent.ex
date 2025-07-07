defmodule RubberDuck.Agents.Agent do
  @moduledoc """
  Base GenServer implementation for all RubberDuck agents.

  Provides the common GenServer scaffolding and infrastructure that all
  agents need, while delegating agent-specific logic to behavior modules.
  This allows agents to focus on their core functionality while getting
  consistent lifecycle management, error handling, and monitoring.

  ## Features

  - Standard GenServer lifecycle with agent behavior integration
  - Task queue management with priority handling
  - Health monitoring and metrics collection
  - Error handling and recovery mechanisms
  - Inter-agent communication support
  - Configuration management and updates

  ## Usage

  Agents are typically started through the Agent Supervisor, but can also
  be started directly for testing:

      # Start through supervisor (recommended)
      {:ok, pid} = Agents.Supervisor.start_agent(:research, config)

      # Start directly (testing)
      {:ok, pid} = Agent.start_link(
        agent_type: :research,
        agent_id: "test_agent",
        config: config
      )

  ## State Structure

  The agent maintains internal state separate from the behavior state:

      %{
        agent_type: :research,
        agent_id: "research_12345",
        behavior_module: RubberDuck.Agents.ResearchAgent,
        behavior_state: behavior_specific_state,
        config: agent_configuration,
        registry: registry_name,
        task_queue: priority_queue,
        current_task: current_task_or_nil,
        metrics: performance_metrics,
        status: :idle | :busy | :error,
        started_at: datetime,
        last_activity: datetime
      }
  """

  use GenServer

  alias RubberDuck.Agents.{Registry, Behavior}

  require Logger

  @type agent_type :: :research | :analysis | :generation | :review
  @type agent_id :: String.t()
  @type agent_state :: map()

  # Client API

  @doc """
  Starts an agent process.

  ## Options

  - `:agent_type` - Type of agent to start (required)
  - `:agent_id` - Unique agent identifier (required)
  - `:config` - Agent configuration map (required)
  - `:registry` - Registry name for registration (required)
  - `:name` - Process name (optional)
  """
  def start_link(opts) do
    agent_type = Keyword.fetch!(opts, :agent_type)
    agent_id = Keyword.fetch!(opts, :agent_id)
    
    name = Keyword.get(opts, :name, {:via, Registry, {opts[:registry], agent_id}})
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Assigns a task to the agent.

  ## Parameters

  - `agent` - Agent PID or name
  - `task` - Task specification map
  - `context` - Execution context (optional)
  - `timeout` - Task timeout in milliseconds (default: 30s)

  ## Returns

  - `{:ok, result}` - Task completed successfully
  - `{:error, reason}` - Task failed
  """
  def assign_task(agent, task, context \\ %{}, timeout \\ 30_000) do
    GenServer.call(agent, {:assign_task, task, context}, timeout)
  end

  @doc """
  Sends a message to the agent.

  ## Parameters

  - `agent` - Agent PID or name
  - `message` - Message content
  - `from` - Sender information (optional)

  ## Returns

  - `:ok` - Message sent successfully
  """
  def send_message(agent, message, from \\ nil) do
    GenServer.cast(agent, {:message, message, from})
  end

  @doc """
  Gets the agent's current status.

  ## Parameters

  - `agent` - Agent PID or name

  ## Returns

  Status map with current state, metrics, and health information.
  """
  def get_status(agent) do
    GenServer.call(agent, :get_status)
  end

  @doc """
  Gets the agent's capabilities.

  ## Parameters

  - `agent` - Agent PID or name

  ## Returns

  List of capability atoms.
  """
  def get_capabilities(agent) do
    GenServer.call(agent, :get_capabilities)
  end

  @doc """
  Updates the agent's configuration.

  ## Parameters

  - `agent` - Agent PID or name
  - `new_config` - Updated configuration map

  ## Returns

  - `:ok` - Configuration updated successfully
  - `{:error, reason}` - Configuration update failed
  """
  def update_config(agent, new_config) do
    GenServer.call(agent, {:update_config, new_config})
  end

  @doc """
  Gracefully stops the agent.

  ## Parameters

  - `agent` - Agent PID or name
  - `reason` - Shutdown reason (optional)
  """
  def stop(agent, reason \\ :normal) do
    GenServer.stop(agent, reason)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    # Extract required options
    agent_type = Keyword.fetch!(opts, :agent_type)
    agent_id = Keyword.fetch!(opts, :agent_id)
    config = Keyword.fetch!(opts, :config)
    registry = Keyword.fetch!(opts, :registry)

    # Determine behavior module
    behavior_module = get_behavior_module(agent_type)

    # Initialize behavior-specific state
    case behavior_module.init(config) do
      {:ok, behavior_state} ->
        state = %{
          agent_type: agent_type,
          agent_id: agent_id,
          behavior_module: behavior_module,
          behavior_state: behavior_state,
          config: config,
          registry: registry,
          task_queue: :queue.new(),
          current_task: nil,
          metrics: initialize_metrics(),
          status: :idle,
          started_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now()
        }

        # Update registry status
        update_registry_status(state, :running)

        Logger.info("Started #{agent_type} agent #{agent_id}")
        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to initialize #{agent_type} agent #{agent_id}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:assign_task, task, context}, from, state) do
    case state.status do
      :idle ->
        # Process task immediately
        handle_task_execution(task, context, from, state)

      :busy ->
        # Queue the task
        task_with_context = %{task: task, context: context, from: from}
        new_queue = :queue.in(task_with_context, state.task_queue)
        new_state = %{state | task_queue: new_queue}
        
        {:noreply, new_state}

      :error ->
        {:reply, {:error, :agent_in_error_state}, state}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = build_status_response(state)
    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_capabilities, _from, state) do
    capabilities = state.behavior_module.get_capabilities(state.behavior_state)
    {:reply, capabilities, state}
  end

  @impl true
  def handle_call({:update_config, new_config}, _from, state) do
    case state.behavior_module.handle_config_update(new_config, state.behavior_state) do
      {:ok, new_behavior_state} ->
        new_state = %{
          state 
          | config: new_config,
            behavior_state: new_behavior_state,
            last_activity: DateTime.utc_now()
        }
        
        update_registry_status(new_state, state.status)
        {:reply, :ok, new_state}

      {:error, reason, behavior_state} ->
        new_state = %{state | behavior_state: behavior_state}
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_cast({:message, message, from}, state) do
    case state.behavior_module.handle_message(message, from, state.behavior_state) do
      {:ok, new_behavior_state} ->
        new_state = %{
          state 
          | behavior_state: new_behavior_state,
            last_activity: DateTime.utc_now()
        }
        {:noreply, new_state}

      {:noreply, new_behavior_state} ->
        new_state = %{
          state 
          | behavior_state: new_behavior_state,
            last_activity: DateTime.utc_now()
        }
        {:noreply, new_state}

      {:error, reason, new_behavior_state} ->
        Logger.warning("Agent #{state.agent_id} message handling failed: #{inspect(reason)}")
        new_state = %{
          state 
          | behavior_state: new_behavior_state,
            status: :error,
            last_activity: DateTime.utc_now()
        }
        
        update_registry_status(new_state, :error)
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(:process_next_task, state) do
    case :queue.out(state.task_queue) do
      {{:value, %{task: task, context: context, from: from}}, new_queue} ->
        new_state = %{state | task_queue: new_queue}
        handle_task_execution(task, context, from, new_state)

      {:empty, _queue} ->
        # No more tasks, go idle
        new_state = %{state | status: :idle, current_task: nil}
        update_registry_status(new_state, :idle)
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Agent #{state.agent_id} received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    # Call behavior terminate
    case state.behavior_module.terminate(reason, state.behavior_state) do
      :ok ->
        Logger.info("Agent #{state.agent_id} terminated normally")
      
      {:error, cleanup_reason} ->
        Logger.warning("Agent #{state.agent_id} cleanup failed: #{inspect(cleanup_reason)}")
    end

    # Update registry
    Registry.update_agent(state.registry, state.agent_id, %{
      status: :terminated,
      terminated_at: DateTime.utc_now()
    })

    :ok
  end

  # Private Functions

  defp get_behavior_module(:research), do: RubberDuck.Agents.ResearchAgent
  defp get_behavior_module(:analysis), do: RubberDuck.Agents.AnalysisAgent
  defp get_behavior_module(:generation), do: RubberDuck.Agents.GenerationAgent
  defp get_behavior_module(:review), do: RubberDuck.Agents.ReviewAgent

  defp handle_task_execution(task, context, from, state) do
    # Update status to busy
    new_state = %{
      state 
      | status: :busy,
        current_task: task,
        last_activity: DateTime.utc_now()
    }
    
    update_registry_status(new_state, :busy)

    # Execute task in behavior module
    case new_state.behavior_module.handle_task(task, context, new_state.behavior_state) do
      {:ok, result, new_behavior_state} ->
        # Task completed successfully
        final_state = %{
          new_state
          | behavior_state: new_behavior_state,
            metrics: update_task_metrics(new_state.metrics, :success)
        }

        # Reply to caller
        GenServer.reply(from, {:ok, result})

        # Process next task if any
        send(self(), :process_next_task)
        
        {:noreply, final_state}

      {:error, reason, new_behavior_state} ->
        # Task failed
        final_state = %{
          new_state
          | behavior_state: new_behavior_state,
            status: :error,
            metrics: update_task_metrics(new_state.metrics, :error)
        }

        # Reply to caller
        GenServer.reply(from, {:error, reason})

        # Update registry
        update_registry_status(final_state, :error)
        
        {:noreply, final_state}
    end
  end

  defp initialize_metrics do
    %{
      tasks_completed: 0,
      tasks_failed: 0,
      total_execution_time: 0,
      average_task_duration: 0.0,
      last_task_duration: 0,
      memory_usage: :erlang.memory(:process),
      message_count: 0
    }
  end

  defp update_task_metrics(metrics, :success) do
    %{
      metrics
      | tasks_completed: metrics.tasks_completed + 1,
        message_count: metrics.message_count + 1
    }
  end

  defp update_task_metrics(metrics, :error) do
    %{
      metrics
      | tasks_failed: metrics.tasks_failed + 1,
        message_count: metrics.message_count + 1
    }
  end

  defp build_status_response(state) do
    behavior_status = state.behavior_module.get_status(state.behavior_state)
    
    Map.merge(behavior_status, %{
      agent_id: state.agent_id,
      agent_type: state.agent_type,
      system_status: state.status,
      current_task: state.current_task,
      queue_length: :queue.len(state.task_queue),
      started_at: state.started_at,
      last_activity: state.last_activity,
      system_metrics: state.metrics
    })
  end

  defp update_registry_status(state, status) do
    Registry.update_agent(state.registry, state.agent_id, %{
      status: status,
      last_activity: state.last_activity,
      metrics: state.metrics
    })
  end
end