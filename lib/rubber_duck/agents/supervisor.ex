defmodule RubberDuck.Agents.Supervisor do
  @moduledoc """
  DynamicSupervisor for managing agent processes with fault tolerance.

  Provides the supervision tree for all agent types including Research,
  Analysis, Generation, and Review agents. Implements the same proven
  pattern as Engine.Supervisor with appropriate restart strategies.

  ## Features

  - Dynamic agent spawning and lifecycle management
  - Fault tolerance with configurable restart strategies
  - Integration with Agent Registry for process discovery
  - Health monitoring and metrics collection
  - Graceful shutdown and cleanup

  ## Usage

      # Start an agent
      {:ok, pid} = Agents.Supervisor.start_agent(:research, agent_config)

      # Stop an agent
      :ok = Agents.Supervisor.stop_agent(pid)

      # List all running agents
      agents = Agents.Supervisor.list_agents()
  """

  use DynamicSupervisor

  alias RubberDuck.Agents.{Registry, Agent, AgentRegistry}

  require Logger

  @registry_name RubberDuck.Agents.Registry

  @doc """
  Starts the agent supervisor.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Starts a new agent of the specified type with the given configuration.

  ## Parameters

  - `agent_type` - The type of agent to start (:research, :analysis, :generation, :review)
  - `agent_config` - Configuration map for the agent
  - `opts` - Additional options (optional)

  ## Returns

  - `{:ok, pid}` - Success with agent process ID
  - `{:error, reason}` - Failure with error reason

  ## Examples

      # Start a research agent
      {:ok, pid} = Agents.Supervisor.start_agent(:research, %{
        name: "code_researcher",
        capabilities: [:semantic_search, :context_building],
        memory_tier: :mid_term
      })

      # Start an analysis agent with custom config
      {:ok, pid} = Agents.Supervisor.start_agent(:analysis, %{
        name: "security_analyzer", 
        engines: [:security, :semantic],
        severity_threshold: :medium
      })
  """
  @spec start_agent(atom(), map(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_agent(agent_type, agent_config, opts \\ []) do
    agent_id = generate_agent_id(agent_type)

    child_spec = {
      Agent,
      [
        agent_type: agent_type,
        agent_id: agent_id,
        config: agent_config,
        registry: @registry_name
      ] ++ opts
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} = result ->
        Logger.info("Started #{agent_type} agent #{agent_id} with PID #{inspect(pid)}")

        # Register agent in both registries for compatibility
        # Use AgentRegistry for advanced features
        AgentRegistry.register_agent(agent_id, pid, %{
          type: agent_type,
          capabilities: get_agent_capabilities(agent_type, agent_config),
          config: agent_config,
          started_at: DateTime.utc_now(),
          status: :running
        })

        # Also register in standard Registry for backward compatibility
        Registry.register_agent(@registry_name, agent_id, %{
          type: agent_type,
          pid: pid,
          config: agent_config,
          started_at: DateTime.utc_now(),
          status: :running
        })

        result

      {:error, reason} = error ->
        Logger.error("Failed to start #{agent_type} agent: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Stops an agent by PID or agent ID.

  ## Parameters

  - `agent_ref` - Either a PID or agent ID string

  ## Returns

  - `:ok` - Success
  - `{:error, reason}` - Failure with error reason
  """
  @spec stop_agent(pid() | String.t()) :: :ok | {:error, term()}
  def stop_agent(agent_ref) when is_pid(agent_ref) do
    case DynamicSupervisor.terminate_child(__MODULE__, agent_ref) do
      :ok ->
        Logger.info("Stopped agent with PID #{inspect(agent_ref)}")
        :ok

      {:error, reason} = error ->
        Logger.error("Failed to stop agent #{inspect(agent_ref)}: #{inspect(reason)}")
        error
    end
  end

  def stop_agent(agent_id) when is_binary(agent_id) do
    case Registry.lookup_agent(@registry_name, agent_id) do
      {:ok, %{pid: pid}} ->
        stop_agent(pid)

      {:error, :not_found} ->
        {:error, :agent_not_found}
    end
  end

  @doc """
  Lists all currently running agents.

  ## Returns

  A list of agent metadata maps containing:
  - `:agent_id` - Unique agent identifier
  - `:type` - Agent type
  - `:pid` - Process ID
  - `:status` - Current status
  - `:started_at` - Startup timestamp
  - `:config` - Agent configuration
  """
  @spec list_agents() :: [map()]
  def list_agents do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} ->
      # Get agent info from registry
      case Registry.find_agent_by_pid(@registry_name, pid) do
        {:ok, agent_id, metadata} ->
          Map.put(metadata, :agent_id, agent_id)

        {:error, :not_found} ->
          %{
            agent_id: "unknown",
            type: :unknown,
            pid: pid,
            status: :unknown,
            started_at: nil,
            config: %{}
          }
      end
    end)
  end

  @doc """
  Gets the count of running agents by type.

  ## Returns

  A map with agent types as keys and counts as values.

  ## Example

      %{
        research: 2,
        analysis: 1,
        generation: 3,
        review: 1
      }
  """
  @spec agent_counts() :: map()
  def agent_counts do
    list_agents()
    |> Enum.group_by(& &1.type)
    |> Map.new(fn {type, agents} -> {type, length(agents)} end)
  end

  @doc """
  Checks the health of the agent supervision tree.

  ## Returns

  A map containing health metrics:
  - `:total_agents` - Total number of running agents
  - `:agents_by_type` - Count by agent type
  - `:supervisor_pid` - Supervisor process ID
  - `:restart_intensity` - Current restart configuration
  """
  @spec health_check() :: map()
  def health_check do
    children = DynamicSupervisor.which_children(__MODULE__)

    %{
      total_agents: length(children),
      agents_by_type: agent_counts(),
      supervisor_pid: Process.whereis(__MODULE__),
      restart_intensity: get_restart_intensity(),
      uptime: get_supervisor_uptime()
    }
  end

  # DynamicSupervisor callbacks

  @impl true
  def init(_init_arg) do
    # Configure restart strategy
    # Allow 3 restarts within 5 seconds (same as Engine.Supervisor)
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 3,
      max_seconds: 5
    )
  end

  # Private functions

  defp generate_agent_id(agent_type) do
    timestamp = System.system_time(:millisecond)
    random = :rand.uniform(9999)
    "#{agent_type}_#{timestamp}_#{random}"
  end

  defp get_restart_intensity do
    # In production, this would query the supervisor's internal state
    # For now, return the configured values
    %{max_restarts: 3, max_seconds: 5}
  end

  defp get_supervisor_uptime do
    case Process.info(Process.whereis(__MODULE__), :current_function) do
      nil ->
        0

      _ ->
        # Simplified uptime calculation
        # In production, would track start time properly
        System.system_time(:second)
    end
  end

  defp get_agent_capabilities(:research, _config) do
    [:semantic_search, :context_building, :pattern_analysis, :information_extraction, :knowledge_synthesis]
  end

  defp get_agent_capabilities(:analysis, _config) do
    [:code_analysis, :security_analysis, :complexity_analysis, :pattern_detection, :style_checking]
  end

  defp get_agent_capabilities(:generation, _config) do
    [:code_generation, :refactoring, :code_completion, :documentation_generation, :code_fixing]
  end

  defp get_agent_capabilities(:review, _config) do
    [:change_review, :quality_assessment, :improvement_suggestions, :correctness_verification, :documentation_review]
  end

  defp get_agent_capabilities(_, _config) do
    []
  end
end
