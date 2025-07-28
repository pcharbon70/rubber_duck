defmodule RubberDuck.Jido do
  @moduledoc """
  Main interface for the Jido autonomous agent framework integration.

  This module provides the entry point for creating and managing Jido agents
  within the RubberDuck system. It acts as a facade to the underlying Jido
  infrastructure while maintaining compatibility with the existing agent system.

  ## Features

  - Agent creation and lifecycle management
  - Signal-based communication using CloudEvents
  - Workflow orchestration
  - Integration with RubberDuck's telemetry system

  ## Usage

      # Create a basic agent
      {:ok, agent} = RubberDuck.Jido.create_agent(:analyzer, %{
        name: "code_analyzer",
        capabilities: [:ast_analysis, :pattern_detection]
      })

      # Send a signal to an agent
      RubberDuck.Jido.emit_signal(agent, %{
        type: "analyze.request",
        data: %{file_path: "lib/my_module.ex"}
      })

  ## Architecture

  The Jido integration is designed to coexist with the existing Agent system
  during the transition period. It uses separate namespaces and registries
  to avoid conflicts while providing a path for gradual migration.
  """

  alias RubberDuck.Jido.{Supervisor, SignalDispatcher}

  require Logger

  @doc """
  Creates a new Jido agent with the specified type and configuration.

  ## Parameters

  - `agent_type` - The type of agent to create (atom)
  - `config` - Configuration map for the agent

  ## Returns

  - `{:ok, agent_pid}` - Success with the agent process ID
  - `{:error, reason}` - Failure with error reason

  ## Examples

      {:ok, agent} = RubberDuck.Jido.create_agent(:planner, %{
        name: "task_planner",
        workflow_engine: true
      })
  """
  @spec create_agent(atom(), map()) :: {:ok, pid()} | {:error, term()}
  def create_agent(agent_type, config) do
    case Supervisor.start_agent(agent_type, config) do
      {:ok, pid} ->
        Logger.info("Created Jido agent #{inspect(agent_type)} with PID #{inspect(pid)}")
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to create Jido agent: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Emits a signal to a specific agent or broadcast to multiple agents.

  Signals follow the CloudEvents specification for standardized messaging.

  ## Parameters

  - `target` - The target agent PID, agent ID, or `:broadcast` for all agents
  - `signal` - Signal data as a map (will be converted to CloudEvent)

  ## Returns

  - `:ok` - Signal emitted successfully
  - `{:error, reason}` - Failure with error reason

  ## Examples

      # Send to specific agent
      RubberDuck.Jido.emit_signal(agent_pid, %{
        type: "task.complete",
        data: %{task_id: "123", status: "success"}
      })

      # Broadcast to all agents
      RubberDuck.Jido.emit_signal(:broadcast, %{
        type: "system.shutdown",
        data: %{reason: "maintenance"}
      })
  """
  @spec emit_signal(pid() | atom() | String.t(), map()) :: :ok | {:error, term()}
  def emit_signal(target, signal) do
    SignalDispatcher.emit(target, signal)
  end

  @doc """
  Starts a workflow with the given definition and initial context.

  ## Parameters

  - `workflow_def` - Workflow definition (module or map)
  - `context` - Initial workflow context

  ## Returns

  - `{:ok, workflow_id}` - Success with workflow ID
  - `{:error, reason}` - Failure with error reason
  """
  @spec start_workflow(module() | map(), map()) :: {:ok, String.t()} | {:error, term()}
  def start_workflow(_workflow_def, _context) do
    # This will be implemented when we add the workflow engine
    {:error, :not_implemented}
  end

  @doc """
  Lists all active Jido agents.

  ## Returns

  A list of agent information maps containing:
  - `:id` - Agent ID
  - `:type` - Agent type
  - `:pid` - Process ID
  - `:status` - Current status
  - `:started_at` - Start timestamp
  """
  @spec list_agents() :: [map()]
  def list_agents do
    Supervisor.list_agents()
  end

  @doc """
  Gets the current status of the Jido system.

  ## Returns

  A map containing:
  - `:agents` - Number of active agents
  - `:signals_processed` - Total signals processed
  - `:workflows_active` - Active workflows
  - `:uptime` - System uptime in seconds
  """
  @spec system_status() :: map()
  def system_status do
    %{
      agents: length(list_agents()),
      signals_processed: SignalDispatcher.get_stats().processed,
      workflows_active: 0,  # TODO: Implement when workflow engine is added
      uptime: get_uptime()
    }
  end

  # Private functions

  defp get_uptime do
    case Process.whereis(Supervisor) do
      nil -> 0
      pid ->
        case Process.info(pid, :start_time) do
          nil -> 0
          {:start_time, start_time} ->
            current_time = :erlang.monotonic_time(:microsecond)
            div(current_time - start_time, 1_000_000)
        end
    end
  end
end