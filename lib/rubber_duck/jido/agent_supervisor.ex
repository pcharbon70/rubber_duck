defmodule RubberDuck.Jido.AgentSupervisor do
  @moduledoc """
  DynamicSupervisor for managing Jido agents.

  This supervisor is responsible for starting, stopping, and monitoring
  individual Jido agents. It provides fault tolerance and automatic
  restart capabilities based on the configured strategy.

  ## Features

  - Dynamic agent spawning
  - Configurable restart strategies
  - Integration with Jido Registry
  - Telemetry events for monitoring
  """

  use DynamicSupervisor


  require Logger

  @registry RubberDuck.Jido.Registry

  @doc """
  Starts the agent supervisor.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Starts a new agent of the specified type.

  ## Parameters

  - `agent_type` - The type of agent to start
  - `config` - Agent configuration map

  ## Returns

  - `{:ok, pid}` - Success with agent PID
  - `{:error, reason}` - Failure with error reason
  """
  @spec start_agent(atom(), map()) :: {:ok, pid()} | {:error, term()}
  def start_agent(agent_type, config) do
    agent_id = generate_agent_id(agent_type)
    
    # Merge with default configuration
    defaults = get_agent_defaults()
    full_config = Map.merge(defaults, config)
    |> Map.put(:id, agent_id)
    |> Map.put(:type, agent_type)
    |> Map.put(:registry, @registry)

    # For now, create a simple test agent
    child_spec = %{
      id: agent_id,
      start: {GenServer, :start_link, [TestAgent, full_config]},
      restart: full_config.restart,
      shutdown: full_config.shutdown
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} = result ->
        # Register in the Jido registry
        Registry.register(@registry, agent_id, %{
          type: agent_type,
          pid: pid,
          config: config,
          started_at: DateTime.utc_now()
        })

        # Emit telemetry event
        :telemetry.execute(
          [:rubber_duck, :jido, :agent, :start],
          %{count: 1},
          %{agent_id: agent_id, agent_type: agent_type}
        )

        Logger.info("Started Jido agent #{agent_id} (#{agent_type}) with PID #{inspect(pid)}")
        result

      {:error, reason} = error ->
        Logger.error("Failed to start Jido agent #{agent_type}: #{inspect(reason)}")
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
  def stop_agent(pid) when is_pid(pid) do
    case DynamicSupervisor.terminate_child(__MODULE__, pid) do
      :ok ->
        # Emit telemetry event
        :telemetry.execute(
          [:rubber_duck, :jido, :agent, :stop],
          %{count: 1},
          %{pid: pid}
        )
        
        Logger.info("Stopped Jido agent with PID #{inspect(pid)}")
        :ok

      {:error, reason} = error ->
        Logger.error("Failed to stop Jido agent #{inspect(pid)}: #{inspect(reason)}")
        error
    end
  end

  def stop_agent(agent_id) when is_binary(agent_id) do
    case Registry.lookup(@registry, agent_id) do
      [{pid, _}] ->
        stop_agent(pid)

      [] ->
        {:error, :agent_not_found}
    end
  end

  @doc """
  Lists all active agents.

  ## Returns

  A list of agent information maps.
  """
  @spec list_agents() :: [map()]
  def list_agents do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} ->
      case find_agent_by_pid(pid) do
        {:ok, agent_id, metadata} ->
          Map.merge(metadata, %{
            id: agent_id,
            pid: pid,
            alive: Process.alive?(pid)
          })

        :error ->
          %{
            id: "unknown",
            pid: pid,
            alive: Process.alive?(pid),
            type: :unknown
          }
      end
    end)
  end

  @doc """
  Gets the count of active agents by type.

  ## Returns

  A map with agent types as keys and counts as values.
  """
  @spec agent_counts() :: map()
  def agent_counts do
    list_agents()
    |> Enum.group_by(& &1.type)
    |> Map.new(fn {type, agents} -> {type, length(agents)} end)
  end

  @impl true
  def init(_init_arg) do
    # Get agent supervisor specific configuration
    config = Application.get_env(:rubber_duck, :jido, [])
    supervisor_config = Keyword.get(config, :agent_supervisor, [])
    
    max_restarts = Keyword.get(supervisor_config, :max_restarts, 3)
    max_seconds = Keyword.get(supervisor_config, :max_seconds, 5)

    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: max_restarts,
      max_seconds: max_seconds
    )
  end

  # Private functions

  defp generate_agent_id(agent_type) do
    timestamp = System.system_time(:millisecond)
    random = :rand.uniform(9999)
    "jido_#{agent_type}_#{timestamp}_#{random}"
  end

  defp get_agent_defaults do
    config = Application.get_env(:rubber_duck, :jido, [])
    defaults = Keyword.get(config, :agent_defaults, [])
    
    %{
      timeout: Keyword.get(defaults, :timeout, 30_000),
      memory_limit: Keyword.get(defaults, :memory_limit, 25),
      mailbox_limit: Keyword.get(defaults, :mailbox_limit, 1000),
      restart: Keyword.get(defaults, :restart, :transient),
      shutdown: Keyword.get(defaults, :shutdown, 5000)
    }
  end

  defp find_agent_by_pid(pid) do
    Registry.select(@registry, [{{:"$1", :"$2", :"$3"}, [{:==, :"$2", pid}], [{{:"$1", :"$3"}}]}])
    |> case do
      [{agent_id, metadata}] -> {:ok, agent_id, metadata}
      [] -> :error
    end
  end
end