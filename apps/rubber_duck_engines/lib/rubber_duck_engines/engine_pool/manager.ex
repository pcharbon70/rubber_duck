defmodule RubberDuckEngines.EnginePool.Manager do
  @moduledoc """
  Engine pool configuration and lifecycle manager.

  Manages pool configurations for different engine types, handles pool sizing,
  and coordinates with the WorkerSupervisor for engine process management.
  """

  use GenServer

  alias RubberDuckEngines.EnginePool

  @default_pools %{
    code_analysis: %{
      engine_module: RubberDuckEngines.Engines.CodeReviewEngine,
      pool_size: 5,
      max_overflow: 2,
      timeout: 30_000
    },
    documentation: %{
      engine_module: RubberDuckEngines.Engines.DocumentationEngine,
      pool_size: 3,
      max_overflow: 1,
      timeout: 20_000
    },
    testing: %{
      engine_module: RubberDuckEngines.Engines.TestingEngine,
      pool_size: 2,
      max_overflow: 1,
      timeout: 25_000
    }
  }

  # Client API

  @doc """
  Starts the pool manager.
  """
  def start_link(init_arg \\ []) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Gets the configuration for a specific pool.
  """
  def get_pool_config(pool_type) do
    GenServer.call(__MODULE__, {:get_pool_config, pool_type})
  end

  @doc """
  Updates the configuration for a specific pool.
  """
  def update_pool_config(pool_type, config) do
    GenServer.call(__MODULE__, {:update_pool_config, pool_type, config})
  end

  @doc """
  Lists all configured pools.
  """
  def list_pools do
    GenServer.call(__MODULE__, :list_pools)
  end

  @doc """
  Gets pool statistics and status.
  """
  def pool_stats do
    GenServer.call(__MODULE__, :pool_stats)
  end

  @doc """
  Adds a new pool configuration.
  """
  def add_pool(pool_type, config) do
    GenServer.call(__MODULE__, {:add_pool, pool_type, config})
  end

  @doc """
  Removes a pool configuration.
  """
  def remove_pool(pool_type) do
    GenServer.call(__MODULE__, {:remove_pool, pool_type})
  end

  # Server implementation

  @impl true
  def init(_init_arg) do
    # Register with the pool registry
    Registry.register(EnginePool.Registry, __MODULE__, %{role: :manager})

    state = %{
      pools: @default_pools,
      stats: %{
        pools_created: map_size(@default_pools),
        pools_removed: 0,
        config_updates: 0
      }
    }

    emit_telemetry(:manager_started, state.stats, %{pools: Map.keys(state.pools)})
    {:ok, state}
  end

  @impl true
  def handle_call({:get_pool_config, pool_type}, _from, state) do
    config = Map.get(state.pools, pool_type)

    emit_telemetry(:pool_config_requested, %{pool_type: pool_type}, %{})
    {:reply, config, state}
  end

  @impl true
  def handle_call({:update_pool_config, pool_type, new_config}, _from, state) do
    case Map.get(state.pools, pool_type) do
      nil ->
        emit_telemetry(
          :pool_config_update_failed,
          %{pool_type: pool_type, reason: :not_found},
          %{}
        )

        {:reply, {:error, :pool_not_found}, state}

      current_config ->
        updated_config = Map.merge(current_config, new_config)
        new_pools = Map.put(state.pools, pool_type, updated_config)
        new_stats = update_in(state.stats, [:config_updates], &(&1 + 1))
        new_state = %{state | pools: new_pools, stats: new_stats}

        emit_telemetry(:pool_config_updated, %{pool_type: pool_type, config: updated_config}, %{})

        # Notify WorkerSupervisor of config change
        send_config_update_notification(pool_type, updated_config)

        {:reply, {:ok, updated_config}, new_state}
    end
  end

  @impl true
  def handle_call(:list_pools, _from, state) do
    pool_info =
      state.pools
      |> Enum.map(fn {type, config} ->
        {type, Map.merge(config, %{status: get_pool_status(type)})}
      end)
      |> Map.new()

    emit_telemetry(:pools_listed, %{count: map_size(pool_info)}, %{})
    {:reply, pool_info, state}
  end

  @impl true
  def handle_call(:pool_stats, _from, state) do
    stats =
      Map.merge(state.stats, %{
        active_pools: map_size(state.pools),
        timestamp: DateTime.utc_now()
      })

    emit_telemetry(:pool_stats_requested, stats, %{})
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:add_pool, pool_type, config}, _from, state) do
    if Map.has_key?(state.pools, pool_type) do
      emit_telemetry(:pool_add_failed, %{pool_type: pool_type, reason: :already_exists}, %{})
      {:reply, {:error, :pool_already_exists}, state}
    else
      new_pools = Map.put(state.pools, pool_type, config)
      new_stats = update_in(state.stats, [:pools_created], &(&1 + 1))
      new_state = %{state | pools: new_pools, stats: new_stats}

      emit_telemetry(:pool_added, %{pool_type: pool_type, config: config}, %{})

      # Notify WorkerSupervisor to create new pool
      send_pool_creation_notification(pool_type, config)

      {:reply, {:ok, config}, new_state}
    end
  end

  @impl true
  def handle_call({:remove_pool, pool_type}, _from, state) do
    case Map.pop(state.pools, pool_type) do
      {nil, _} ->
        emit_telemetry(:pool_remove_failed, %{pool_type: pool_type, reason: :not_found}, %{})
        {:reply, {:error, :pool_not_found}, state}

      {removed_config, new_pools} ->
        new_stats = update_in(state.stats, [:pools_removed], &(&1 + 1))
        new_state = %{state | pools: new_pools, stats: new_stats}

        emit_telemetry(:pool_removed, %{pool_type: pool_type, config: removed_config}, %{})

        # Notify WorkerSupervisor to remove pool
        send_pool_removal_notification(pool_type)

        {:reply, {:ok, removed_config}, new_state}
    end
  end

  # Private helper functions

  defp get_pool_status(pool_type) do
    case Registry.lookup(EnginePool.Registry, {:pool, pool_type}) do
      [{_pid, _}] -> :active
      [] -> :inactive
    end
  end

  defp send_config_update_notification(pool_type, config) do
    case Registry.lookup(EnginePool.Registry, EnginePool.WorkerSupervisor) do
      [{pid, _}] -> send(pid, {:config_updated, pool_type, config})
      [] -> :ok
    end
  end

  defp send_pool_creation_notification(pool_type, config) do
    case Registry.lookup(EnginePool.Registry, EnginePool.WorkerSupervisor) do
      [{pid, _}] -> send(pid, {:create_pool, pool_type, config})
      [] -> :ok
    end
  end

  defp send_pool_removal_notification(pool_type) do
    case Registry.lookup(EnginePool.Registry, EnginePool.WorkerSupervisor) do
      [{pid, _}] -> send(pid, {:remove_pool, pool_type})
      [] -> :ok
    end
  end

  defp emit_telemetry(event, metadata, measurements) do
    :telemetry.execute(
      [:rubber_duck_engines, :engine_pool, :manager, event],
      measurements,
      metadata
    )
  end
end
