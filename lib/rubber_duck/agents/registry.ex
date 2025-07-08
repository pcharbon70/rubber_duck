defmodule RubberDuck.Agents.Registry do
  @moduledoc """
  Registry for agent discovery, metadata management, and process tracking.

  Provides a centralized registry for all agent processes with metadata
  storage, lookup capabilities, and automatic cleanup on process death.
  Implements the same proven pattern as Engine.Registry.

  ## Features

  - Process registration and discovery
  - Metadata storage and retrieval
  - Automatic cleanup on process death
  - Query capabilities by type, status, and attributes
  - Health monitoring and diagnostics

  ## Usage

      # Register an agent
      Registry.register_agent(registry, agent_id, metadata)

      # Lookup an agent
      {:ok, metadata} = Registry.lookup_agent(registry, agent_id)

      # Find agents by type
      agents = Registry.find_agents_by_type(registry, :research)
  """

  @registry_name __MODULE__

  @doc """
  Starts the agent registry.
  """
  def start_link(_opts) do
    Registry.start_link(keys: :unique, name: @registry_name)
  end

  @doc """
  Returns the registry name for use in other modules.
  """
  def registry_name, do: @registry_name

  @doc """
  Registers an agent in the registry with metadata.

  ## Parameters

  - `registry` - Registry name (usually `@registry_name`)
  - `agent_id` - Unique agent identifier
  - `metadata` - Agent metadata map

  ## Metadata Format

  The metadata map should contain:
  - `:type` - Agent type (:research, :analysis, :generation, :review)
  - `:pid` - Process ID
  - `:config` - Agent configuration
  - `:started_at` - Startup timestamp
  - `:status` - Current status (:starting, :running, :stopping, :error)
  - `:capabilities` - List of agent capabilities (optional)
  - `:metrics` - Performance metrics (optional)

  ## Returns

  - `:ok` - Success
  - `{:error, reason}` - Failure with error reason
  """
  @spec register_agent(atom(), String.t(), map()) :: :ok | {:error, term()}
  def register_agent(registry, agent_id, metadata) do
    case Registry.register(registry, agent_id, metadata) do
      {:ok, _pid} ->
        :ok

      {:error, {:already_registered, _pid}} ->
        {:error, :already_registered}

      error ->
        error
    end
  end

  @doc """
  Updates agent metadata in the registry.

  ## Parameters

  - `registry` - Registry name
  - `agent_id` - Agent identifier
  - `updates` - Map of metadata updates to apply

  ## Returns

  - `:ok` - Success
  - `{:error, reason}` - Failure with error reason
  """
  @spec update_agent(atom(), String.t(), map()) :: :ok | {:error, term()}
  def update_agent(registry, agent_id, updates) do
    case Registry.lookup(registry, agent_id) do
      [{_pid, metadata}] ->
        updated_metadata = Map.merge(metadata, updates)
        Registry.update_value(registry, agent_id, fn _ -> updated_metadata end)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Looks up an agent by ID.

  ## Parameters

  - `registry` - Registry name
  - `agent_id` - Agent identifier

  ## Returns

  - `{:ok, metadata}` - Success with agent metadata
  - `{:error, :not_found}` - Agent not found
  """
  @spec lookup_agent(atom(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def lookup_agent(registry, agent_id) do
    case Registry.lookup(registry, agent_id) do
      [{_pid, metadata}] ->
        {:ok, metadata}

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Finds an agent by PID.

  ## Parameters

  - `registry` - Registry name
  - `pid` - Process ID

  ## Returns

  - `{:ok, agent_id, metadata}` - Success with agent ID and metadata
  - `{:error, :not_found}` - Agent not found
  """
  @spec find_agent_by_pid(atom(), pid()) :: {:ok, String.t(), map()} | {:error, :not_found}
  def find_agent_by_pid(registry, pid) do
    case Registry.keys(registry, pid) do
      [agent_id] ->
        case lookup_agent(registry, agent_id) do
          {:ok, metadata} ->
            {:ok, agent_id, metadata}

          error ->
            error
        end

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Finds all agents of a specific type.

  ## Parameters

  - `registry` - Registry name
  - `agent_type` - Agent type to search for

  ## Returns

  A list of `{agent_id, metadata}` tuples for matching agents.
  """
  @spec find_agents_by_type(atom(), atom()) :: [{String.t(), map()}]
  def find_agents_by_type(registry, agent_type) do
    Registry.select(registry, [
      {{:"$1", :"$2", :"$3"}, [{:==, {:map_get, :type, :"$3"}, agent_type}], [{{:"$1", :"$3"}}]}
    ])
  end

  @doc """
  Finds agents by status.

  ## Parameters

  - `registry` - Registry name
  - `status` - Status to search for (:running, :starting, :stopping, :error)

  ## Returns

  A list of `{agent_id, metadata}` tuples for matching agents.
  """
  @spec find_agents_by_status(atom(), atom()) :: [{String.t(), map()}]
  def find_agents_by_status(registry, status) do
    Registry.select(registry, [
      {{:"$1", :"$2", :"$3"}, [{:==, {:map_get, :status, :"$3"}, status}], [{{:"$1", :"$3"}}]}
    ])
  end

  @doc """
  Finds agents with specific capabilities.

  ## Parameters

  - `registry` - Registry name
  - `capability` - Capability to search for (atom)

  ## Returns

  A list of `{agent_id, metadata}` tuples for agents with the capability.
  """
  @spec find_agents_with_capability(atom(), atom()) :: [{String.t(), map()}]
  def find_agents_with_capability(registry, capability) do
    Registry.select(registry, [
      {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$3"}}]}
    ])
    |> Enum.filter(fn {_agent_id, metadata} ->
      capabilities = Map.get(metadata, :capabilities, [])
      capability in capabilities
    end)
  end

  @doc """
  Lists all registered agents.

  ## Parameters

  - `registry` - Registry name

  ## Returns

  A list of `{agent_id, metadata}` tuples for all registered agents.
  """
  @spec list_all_agents(atom()) :: [{String.t(), map()}]
  def list_all_agents(registry) do
    Registry.select(registry, [
      {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$3"}}]}
    ])
  end

  @doc """
  Unregisters an agent from the registry.

  ## Parameters

  - `registry` - Registry name
  - `agent_id` - Agent identifier

  ## Returns

  - `:ok` - Success
  - `{:error, :not_found}` - Agent not found
  """
  @spec unregister_agent(atom(), String.t()) :: :ok | {:error, :not_found}
  def unregister_agent(registry, agent_id) do
    case Registry.unregister(registry, agent_id) do
      :ok -> :ok
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Gets registry statistics and health information.

  ## Parameters

  - `registry` - Registry name

  ## Returns

  A map containing:
  - `:total_agents` - Total number of registered agents
  - `:agents_by_type` - Count by agent type
  - `:agents_by_status` - Count by status
  - `:registry_pid` - Registry process ID
  """
  @spec get_stats(atom()) :: map()
  def get_stats(registry) do
    all_agents = list_all_agents(registry)

    agents_by_type =
      all_agents
      |> Enum.group_by(fn {_id, metadata} -> Map.get(metadata, :type, :unknown) end)
      |> Map.new(fn {type, agents} -> {type, length(agents)} end)

    agents_by_status =
      all_agents
      |> Enum.group_by(fn {_id, metadata} -> Map.get(metadata, :status, :unknown) end)
      |> Map.new(fn {status, agents} -> {status, length(agents)} end)

    %{
      total_agents: length(all_agents),
      agents_by_type: agents_by_type,
      agents_by_status: agents_by_status,
      registry_pid: Process.whereis(registry)
    }
  end

  @doc """
  Performs a health check on the registry.

  ## Parameters

  - `registry` - Registry name

  ## Returns

  - `:healthy` - Registry is functioning properly
  - `{:unhealthy, reason}` - Registry has issues
  """
  @spec health_check(atom()) :: :healthy | {:unhealthy, term()}
  def health_check(registry) do
    case Process.whereis(registry) do
      nil ->
        {:unhealthy, :registry_not_running}

      pid when is_pid(pid) ->
        case Process.alive?(pid) do
          true -> :healthy
          false -> {:unhealthy, :registry_dead}
        end
    end
  end

  @doc """
  Cleans up stale agent registrations.

  Removes registry entries for agents whose processes are no longer alive.
  This is typically called automatically, but can be triggered manually.

  ## Parameters

  - `registry` - Registry name

  ## Returns

  - `{:ok, count}` - Number of stale entries cleaned up
  """
  @spec cleanup_stale_agents(atom()) :: {:ok, non_neg_integer()}
  def cleanup_stale_agents(registry) do
    all_agents = list_all_agents(registry)

    stale_count =
      all_agents
      |> Enum.count(fn {agent_id, metadata} ->
        pid = Map.get(metadata, :pid)

        if pid && !Process.alive?(pid) do
          unregister_agent(registry, agent_id)
          true
        else
          false
        end
      end)

    {:ok, stale_count}
  end
end
