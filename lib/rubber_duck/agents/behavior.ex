defmodule RubberDuck.Agents.Behavior do
  @moduledoc """
  Behavior defining the standard interface for all RubberDuck agents.

  All agent implementations must implement this behavior to ensure
  consistent lifecycle management, communication protocols, and
  integration with the agent supervision tree.

  ## Callbacks

  Agents must implement the following callbacks:

  - `init/1` - Initialize agent state and configuration
  - `handle_task/3` - Process assigned tasks with context
  - `handle_message/3` - Handle inter-agent messages
  - `get_capabilities/1` - Return agent capabilities
  - `get_status/1` - Return current agent status and metrics
  - `terminate/2` - Cleanup on agent shutdown

  ## Example Implementation

      defmodule MyAgent do
        use RubberDuck.Agents.Behavior

        @impl true
        def init(config) do
          state = %{
            config: config,
            tasks: [],
            metrics: %{tasks_completed: 0}
          }
          {:ok, state}
        end

        @impl true
        def handle_task(task, context, state) do
          # Process the task
          result = process_task(task, context)
          
          # Update metrics
          new_state = update_metrics(state)
          
          {:ok, result, new_state}
        end

        # ... implement other callbacks
      end
  """

  @type agent_state :: term()
  @type task :: map()
  @type task_context :: map()
  @type task_result :: term()
  @type message :: term()
  @type capabilities :: [atom()]
  @type status :: map()
  @type init_result :: {:ok, agent_state} | {:error, term()}
  @type handle_result :: {:ok, task_result, agent_state} | {:error, term(), agent_state}
  @type message_result :: {:ok, agent_state} | {:noreply, agent_state} | {:error, term(), agent_state}

  @doc """
  Initialize the agent with the given configuration.

  Called when the agent process starts. Should set up initial state,
  validate configuration, and perform any necessary initialization.

  ## Parameters

  - `config` - Agent configuration map

  ## Returns

  - `{:ok, state}` - Success with initial state
  - `{:error, reason}` - Initialization failure

  ## Example

      def init(config) do
        case validate_config(config) do
          :ok ->
            state = %{
              config: config,
              workspace: setup_workspace(),
              metrics: initialize_metrics()
            }
            {:ok, state}
          
          {:error, reason} ->
            {:error, reason}
        end
      end
  """
  @callback init(config :: map()) :: init_result()

  @doc """
  Handle a task assigned to this agent.

  Tasks are the primary unit of work for agents. They contain the work
  to be performed and any necessary context or parameters.

  ## Parameters

  - `task` - Task specification map
  - `context` - Execution context (memory, user preferences, etc.)
  - `state` - Current agent state

  ## Task Format

  Tasks should contain:
  - `:id` - Unique task identifier
  - `:type` - Task type (specific to agent)
  - `:priority` - Task priority (:low, :medium, :high, :critical)
  - `:deadline` - Optional deadline for completion
  - `:payload` - Task-specific data and parameters
  - `:requester` - Who/what requested this task

  ## Returns

  - `{:ok, result, new_state}` - Success with result and updated state
  - `{:error, reason, new_state}` - Failure with reason and updated state

  ## Example

      def handle_task(%{type: :analyze_code} = task, context, state) do
        case perform_analysis(task.payload, context) do
          {:ok, analysis} ->
            result = %{
              task_id: task.id,
              analysis: analysis,
              completed_at: DateTime.utc_now()
            }
            new_state = update_task_metrics(state)
            {:ok, result, new_state}
          
          {:error, reason} ->
            {:error, reason, state}
        end
      end
  """
  @callback handle_task(task(), task_context(), agent_state()) :: handle_result()

  @doc """
  Handle inter-agent messages.

  Agents can communicate with each other through messages. This callback
  handles incoming messages from other agents or system components.

  ## Parameters

  - `message` - Message content
  - `from` - Sender information (PID, agent ID, etc.)
  - `state` - Current agent state

  ## Message Types

  Common message types include:
  - `:request` - Request for information or action
  - `:response` - Response to a previous request
  - `:notification` - Informational message
  - `:coordination` - Coordination and synchronization
  - `:broadcast` - Broadcast message to multiple agents

  ## Returns

  - `{:ok, new_state}` - Message handled successfully
  - `{:noreply, new_state}` - Message handled, no response needed
  - `{:error, reason, new_state}` - Message handling failed

  ## Example

      def handle_message({:request, :status}, from, state) do
        status = get_current_status(state)
        send_response(from, {:status, status})
        {:ok, state}
      end

      def handle_message({:coordination, :pause}, _from, state) do
        new_state = pause_current_tasks(state)
        {:ok, new_state}
      end
  """
  @callback handle_message(message(), term(), agent_state()) :: message_result()

  @doc """
  Return the agent's capabilities.

  Capabilities describe what the agent can do and are used for task
  routing and coordination. Should return a list of capability atoms.

  ## Parameters

  - `state` - Current agent state

  ## Returns

  List of capability atoms that this agent supports.

  ## Example Capabilities

  - `:code_analysis` - Can analyze source code
  - `:semantic_search` - Can perform semantic searches
  - `:code_generation` - Can generate code
  - `:documentation` - Can generate documentation
  - `:refactoring` - Can suggest refactorings
  - `:security_review` - Can perform security analysis

  ## Example

      def get_capabilities(_state) do
        [:code_analysis, :semantic_search, :documentation]
      end
  """
  @callback get_capabilities(agent_state()) :: capabilities()

  @doc """
  Return the agent's current status and metrics.

  Provides detailed information about the agent's current state,
  performance metrics, and health status for monitoring and debugging.

  ## Parameters

  - `state` - Current agent state

  ## Returns

  Status map containing:
  - `:status` - Current status (:idle, :busy, :error, :stopping)
  - `:current_task` - Currently executing task (if any)
  - `:metrics` - Performance and usage metrics
  - `:health` - Health indicators
  - `:last_activity` - Timestamp of last activity

  ## Example

      def get_status(state) do
        %{
          status: determine_status(state),
          current_task: state.current_task,
          metrics: %{
            tasks_completed: state.metrics.tasks_completed,
            average_task_duration: calculate_avg_duration(state),
            memory_usage: get_memory_usage(),
            uptime: get_uptime(state)
          },
          health: %{
            healthy: true,
            last_error: state.last_error,
            error_count: state.error_count
          },
          last_activity: state.last_activity
        }
      end
  """
  @callback get_status(agent_state()) :: status()

  @doc """
  Handle agent termination and cleanup.

  Called when the agent is shutting down. Should perform any necessary
  cleanup, save state, and release resources.

  ## Parameters

  - `reason` - Shutdown reason (:normal, :shutdown, {:shutdown, term()}, term())
  - `state` - Current agent state

  ## Returns

  - `:ok` - Cleanup completed successfully
  - `{:error, reason}` - Cleanup failed

  ## Example

      def terminate(reason, state) do
        # Save important state
        save_agent_state(state)
        
        # Clean up resources
        cleanup_workspace(state.workspace)
        
        # Log shutdown
        Logger.info("Agent terminating: \#{inspect(reason)}")
        
        :ok
      end
  """
  @callback terminate(reason :: term(), agent_state()) :: :ok | {:error, term()}

  @doc """
  Optional callback for handling agent configuration updates.

  This callback is called when the agent's configuration is updated
  at runtime. Not all agents need to support dynamic reconfiguration.

  ## Parameters

  - `new_config` - Updated configuration map
  - `state` - Current agent state

  ## Returns

  - `{:ok, new_state}` - Configuration updated successfully
  - `{:error, reason, state}` - Configuration update failed

  ## Example

      def handle_config_update(new_config, state) do
        case validate_config(new_config) do
          :ok ->
            new_state = %{state | config: new_config}
            {:ok, new_state}
          
          {:error, reason} ->
            {:error, reason, state}
        end
      end
  """
  @callback handle_config_update(config :: map(), agent_state()) ::
              {:ok, agent_state()} | {:error, term(), agent_state()}

  @optional_callbacks [handle_config_update: 2]

  @doc """
  Use this behavior in an agent module to get the default implementation.

  ## Example

      defmodule MyAgent do
        use RubberDuck.Agents.Behavior

        # Implement required callbacks...
      end
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour RubberDuck.Agents.Behavior

      # Provide default implementation for optional callbacks
      def handle_config_update(_new_config, state) do
        {:error, :not_supported, state}
      end

      defoverridable handle_config_update: 2
    end
  end
end
