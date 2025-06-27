defmodule RubberDuckEngines.EnginePool.WorkerSupervisor do
  @moduledoc """
  Worker supervisor for managing engine process pools.

  This supervisor creates and manages individual engine pools based on
  configurations from the Manager. Uses DynamicSupervisor for flexible
  pool creation and management.
  """

  use DynamicSupervisor

  alias RubberDuckEngines.EnginePool

  @doc """
  Starts the worker supervisor.
  """
  def start_link(init_arg \\ []) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Creates a new engine pool for the specified type.
  """
  def create_pool(pool_type, config) do
    child_spec = {EnginePool.Worker, [pool_type: pool_type, config: config]}

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        emit_telemetry(:pool_created, %{pool_type: pool_type, pid: pid}, %{})
        {:ok, pid}

      {:error, reason} ->
        emit_telemetry(:pool_creation_failed, %{pool_type: pool_type, reason: reason}, %{})
        {:error, reason}
    end
  end

  @doc """
  Removes an engine pool.
  """
  def remove_pool(pool_type) do
    case find_pool_worker(pool_type) do
      {:ok, pid} ->
        result = DynamicSupervisor.terminate_child(__MODULE__, pid)
        emit_telemetry(:pool_removed, %{pool_type: pool_type, pid: pid}, %{})
        result

      {:error, :not_found} ->
        emit_telemetry(:pool_removal_failed, %{pool_type: pool_type, reason: :not_found}, %{})
        {:error, :not_found}
    end
  end

  @doc """
  Updates configuration for an existing pool.
  """
  def update_pool_config(pool_type, new_config) do
    case find_pool_worker(pool_type) do
      {:ok, pid} ->
        GenServer.call(pid, {:update_config, new_config})
        emit_telemetry(:pool_config_updated, %{pool_type: pool_type, pid: pid}, %{})
        :ok

      {:error, :not_found} ->
        emit_telemetry(
          :pool_config_update_failed,
          %{pool_type: pool_type, reason: :not_found},
          %{}
        )

        {:error, :not_found}
    end
  end

  @doc """
  Lists all active engine pools.
  """
  def list_pools do
    children = DynamicSupervisor.which_children(__MODULE__)

    pools =
      children
      |> Enum.map(fn {_id, pid, _type, _modules} ->
        case Registry.lookup(EnginePool.Registry, {:pool_worker, pid}) do
          [{^pid, pool_info}] -> pool_info
          [] -> %{pid: pid, type: :unknown, status: :unknown}
        end
      end)

    emit_telemetry(:pools_listed, %{count: length(pools)}, %{})
    pools
  end

  @doc """
  Gets pool statistics for monitoring.
  """
  def pool_stats do
    children_count = DynamicSupervisor.count_children(__MODULE__)

    stats = %{
      total_pools: children_count.workers,
      supervisors: children_count.supervisors,
      timestamp: DateTime.utc_now()
    }

    emit_telemetry(:pool_stats_requested, stats, %{})
    stats
  end

  @impl true
  def init(_init_arg) do
    # Register with the pool registry
    Registry.register(EnginePool.Registry, __MODULE__, %{role: :worker_supervisor})

    emit_telemetry(:worker_supervisor_started, %{}, %{})
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def handle_info({:create_pool, pool_type, config}, state) do
    create_pool(pool_type, config)
    {:noreply, state}
  end

  def handle_info({:remove_pool, pool_type}, state) do
    remove_pool(pool_type)
    {:noreply, state}
  end

  def handle_info({:config_updated, pool_type, new_config}, state) do
    update_pool_config(pool_type, new_config)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private helper functions

  defp find_pool_worker(pool_type) do
    case Registry.lookup(EnginePool.Registry, {:pool, pool_type}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  defp emit_telemetry(event, metadata, measurements) do
    :telemetry.execute(
      [:rubber_duck_engines, :engine_pool, :worker_supervisor, event],
      measurements,
      metadata
    )
  end
end
