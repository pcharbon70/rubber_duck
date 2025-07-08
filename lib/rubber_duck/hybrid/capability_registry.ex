defmodule RubberDuck.Hybrid.CapabilityRegistry do
  @moduledoc """
  Unified registry for engines and workflows with capability-based discovery.

  This module provides a centralized registry that tracks capabilities across
  both engine and workflow systems, enabling intelligent routing and discovery
  of hybrid execution targets.
  """

  use GenServer
  require Logger

  @type capability :: atom()
  @type entity_type :: :engine | :workflow | :hybrid
  @type entity_id :: atom()
  @type metadata :: map()

  @type registration :: %{
          id: entity_id(),
          type: entity_type(),
          capability: capability(),
          metadata: metadata(),
          module: module(),
          priority: integer(),
          registered_at: DateTime.t()
        }

  defstruct [:registry_table, :capability_index, :type_index]

  @table_name :hybrid_capability_registry
  @capability_index_table :hybrid_capability_index
  @type_index_table :hybrid_type_index

  ## Client API

  @doc """
  Starts the capability registry GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers an engine capability with workflow integration metadata.
  """
  @spec register_engine_capability(entity_id(), capability(), metadata()) :: :ok | {:error, term()}
  def register_engine_capability(engine_id, capability, metadata \\ %{}) do
    registration = %{
      id: engine_id,
      type: :engine,
      capability: capability,
      metadata: Map.put(metadata, :can_integrate_with_workflows, true),
      module: metadata[:module],
      priority: metadata[:priority] || 100,
      registered_at: DateTime.utc_now()
    }

    GenServer.call(__MODULE__, {:register, registration})
  end

  @doc """
  Registers a workflow capability with engine integration metadata.
  """
  @spec register_workflow_capability(entity_id(), capability(), metadata()) :: :ok | {:error, term()}
  def register_workflow_capability(workflow_id, capability, metadata \\ %{}) do
    registration = %{
      id: workflow_id,
      type: :workflow,
      capability: capability,
      metadata: Map.put(metadata, :can_integrate_with_engines, true),
      module: metadata[:module],
      priority: metadata[:priority] || 100,
      registered_at: DateTime.utc_now()
    }

    GenServer.call(__MODULE__, {:register, registration})
  end

  @doc """
  Registers a hybrid capability that combines engine and workflow features.
  """
  @spec register_hybrid_capability(entity_id(), capability(), metadata()) :: :ok | {:error, term()}
  def register_hybrid_capability(hybrid_id, capability, metadata \\ %{}) do
    registration = %{
      id: hybrid_id,
      type: :hybrid,
      capability: capability,
      metadata: metadata,
      module: metadata[:module],
      # Higher priority for hybrid capabilities
      priority: metadata[:priority] || 150,
      registered_at: DateTime.utc_now()
    }

    GenServer.call(__MODULE__, {:register, registration})
  end

  @doc """
  Finds entities by capability, optionally filtered by type.

  Returns results sorted by priority (highest first).
  """
  @spec find_by_capability(capability(), entity_type() | :any) :: [registration()]
  def find_by_capability(capability, type \\ :any) do
    GenServer.call(__MODULE__, {:find_by_capability, capability, type})
  end

  @doc """
  Finds the best entity for a capability based on priority and type preference.
  """
  @spec find_best_for_capability(capability(), entity_type() | :any) :: registration() | nil
  def find_best_for_capability(capability, type_preference \\ :any) do
    case find_by_capability(capability, type_preference) do
      [] -> nil
      [best | _] -> best
    end
  end

  @doc """
  Finds entities by type.
  """
  @spec find_by_type(entity_type()) :: [registration()]
  def find_by_type(type) do
    GenServer.call(__MODULE__, {:find_by_type, type})
  end

  @doc """
  Finds a specific entity by ID.
  """
  @spec find_by_id(entity_id()) :: registration() | nil
  def find_by_id(entity_id) do
    GenServer.call(__MODULE__, {:find_by_id, entity_id})
  end

  @doc """
  Lists all registered capabilities.
  """
  @spec list_capabilities() :: [capability()]
  def list_capabilities do
    GenServer.call(__MODULE__, :list_capabilities)
  end

  @doc """
  Lists all registrations.
  """
  @spec list_all() :: [registration()]
  def list_all do
    GenServer.call(__MODULE__, :list_all)
  end

  @doc """
  Unregisters an entity.
  """
  @spec unregister(entity_id()) :: :ok
  def unregister(entity_id) do
    GenServer.call(__MODULE__, {:unregister, entity_id})
  end

  @doc """
  Updates the metadata for a registered entity.
  """
  @spec update_metadata(entity_id(), metadata()) :: :ok | {:error, :not_found}
  def update_metadata(entity_id, metadata) do
    GenServer.call(__MODULE__, {:update_metadata, entity_id, metadata})
  end

  @doc """
  Checks if an entity supports a specific capability.
  """
  @spec supports_capability?(entity_id(), capability()) :: boolean()
  def supports_capability?(entity_id, capability) do
    case find_by_id(entity_id) do
      nil -> false
      registration -> registration.capability == capability
    end
  end

  @doc """
  Gets hybrid-compatible entities for a capability.

  Returns entities that can participate in hybrid execution for the given capability.
  """
  @spec find_hybrid_compatible(capability()) :: [registration()]
  def find_hybrid_compatible(capability) do
    find_by_capability(capability, :any)
    |> Enum.filter(&hybrid_compatible?/1)
  end

  ## GenServer Implementation

  @impl GenServer
  def init(_opts) do
    # Create ETS tables for fast lookups
    registry_table = :ets.new(@table_name, [:set, :protected, :named_table])
    capability_index = :ets.new(@capability_index_table, [:bag, :protected, :named_table])
    type_index = :ets.new(@type_index_table, [:bag, :protected, :named_table])

    state = %__MODULE__{
      registry_table: registry_table,
      capability_index: capability_index,
      type_index: type_index
    }

    Logger.info("Hybrid capability registry started")
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:register, registration}, _from, state) do
    case validate_registration(registration) do
      :ok ->
        register_entity(registration, state)
        Logger.debug("Registered #{registration.type} capability: #{registration.id} -> #{registration.capability}")
        {:reply, :ok, state}

      {:error, reason} ->
        Logger.warning("Failed to register capability: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:find_by_capability, capability, type}, _from, state) do
    results =
      :ets.lookup(state.capability_index, capability)
      |> Enum.map(fn {_, entity_id} ->
        [{_, registration}] = :ets.lookup(state.registry_table, entity_id)
        registration
      end)
      |> filter_by_type(type)
      |> Enum.sort_by(& &1.priority, :desc)

    {:reply, results, state}
  end

  @impl GenServer
  def handle_call({:find_by_type, type}, _from, state) do
    results =
      :ets.lookup(state.type_index, type)
      |> Enum.map(fn {_, entity_id} ->
        [{_, registration}] = :ets.lookup(state.registry_table, entity_id)
        registration
      end)
      |> Enum.sort_by(& &1.priority, :desc)

    {:reply, results, state}
  end

  @impl GenServer
  def handle_call({:find_by_id, entity_id}, _from, state) do
    result =
      case :ets.lookup(state.registry_table, entity_id) do
        [{_, registration}] -> registration
        [] -> nil
      end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:list_capabilities, _from, state) do
    capabilities =
      :ets.tab2list(state.capability_index)
      |> Enum.map(fn {capability, _} -> capability end)
      |> Enum.uniq()

    {:reply, capabilities, state}
  end

  @impl GenServer
  def handle_call(:list_all, _from, state) do
    registrations =
      :ets.tab2list(state.registry_table)
      |> Enum.map(fn {_, registration} -> registration end)
      |> Enum.sort_by(& &1.priority, :desc)

    {:reply, registrations, state}
  end

  @impl GenServer
  def handle_call({:unregister, entity_id}, _from, state) do
    case :ets.lookup(state.registry_table, entity_id) do
      [{_, registration}] ->
        :ets.delete(state.registry_table, entity_id)
        :ets.delete_object(state.capability_index, {registration.capability, entity_id})
        :ets.delete_object(state.type_index, {registration.type, entity_id})
        Logger.debug("Unregistered entity: #{entity_id}")

      [] ->
        :ok
    end

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:update_metadata, entity_id, metadata}, _from, state) do
    case :ets.lookup(state.registry_table, entity_id) do
      [{_, registration}] ->
        updated_registration = %{registration | metadata: metadata}
        :ets.insert(state.registry_table, {entity_id, updated_registration})
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  ## Private Functions

  defp register_entity(registration, state) do
    entity_id = registration.id

    # Store in main registry
    :ets.insert(state.registry_table, {entity_id, registration})

    # Index by capability
    :ets.insert(state.capability_index, {registration.capability, entity_id})

    # Index by type
    :ets.insert(state.type_index, {registration.type, entity_id})
  end

  defp validate_registration(registration) do
    cond do
      not is_atom(registration.id) ->
        {:error, "Entity ID must be an atom"}

      not is_atom(registration.capability) ->
        {:error, "Capability must be an atom"}

      registration.type not in [:engine, :workflow, :hybrid] ->
        {:error, "Type must be :engine, :workflow, or :hybrid"}

      not is_integer(registration.priority) ->
        {:error, "Priority must be an integer"}

      true ->
        :ok
    end
  end

  defp filter_by_type(registrations, :any), do: registrations

  defp filter_by_type(registrations, type) do
    Enum.filter(registrations, &(&1.type == type))
  end

  defp hybrid_compatible?(registration) do
    case registration.type do
      :hybrid -> true
      :engine -> Map.get(registration.metadata, :can_integrate_with_workflows, false)
      :workflow -> Map.get(registration.metadata, :can_integrate_with_engines, false)
    end
  end
end
