defmodule RubberDuckEngines.EnginePool.Supervisor do
  @moduledoc """
  Engine pool supervisor implementing rest_for_one strategy.

  This supervisor manages the engine pool hierarchy with proper dependency ordering:
  1. Registry - Foundation for all pool operations
  2. Manager - Pool configuration and lifecycle management  
  3. WorkerSupervisor - Engine process management
  4. Router - Request routing and load balancing

  Using rest_for_one strategy ensures that when a component fails, all dependent
  components are restarted to maintain consistency.
  """

  use Supervisor

  alias RubberDuckEngines.EnginePool

  @doc """
  Starts the engine pool supervisor.
  """
  def start_link(init_arg \\ []) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Registry for engine pool process discovery - MUST BE FIRST
      # All other components depend on this registry
      {Registry, keys: :unique, name: EnginePool.Registry},

      # Pool configuration manager - depends on registry
      # Manages pool configurations, sizes, and lifecycle policies
      {EnginePool.Manager, []},

      # Worker supervisor for engine processes - depends on manager and registry
      # Creates and manages the actual engine process pools
      {EnginePool.WorkerSupervisor, []},

      # Request router - depends on all above components
      # Routes requests to available engines and manages load balancing
      {EnginePool.Router, []}
    ]

    # rest_for_one strategy ensures proper dependency restart order:
    # - Registry failure -> All restart (everything depends on registry)
    # - Manager failure -> Manager, WorkerSupervisor, Router restart
    # - WorkerSupervisor failure -> WorkerSupervisor, Router restart  
    # - Router failure -> Only Router restarts
    opts = [
      strategy: :rest_for_one,
      name: __MODULE__,
      max_restarts: 3,
      max_seconds: 5
    ]

    Supervisor.init(children, opts)
  end

  @doc """
  Gets the current supervision tree status and statistics.
  """
  def supervision_status do
    children_info = Supervisor.which_children(__MODULE__)

    stats = %{
      strategy: :rest_for_one,
      children_count: length(children_info),
      children: Enum.map(children_info, &format_child_info/1),
      restart_policy: %{
        max_restarts: 3,
        max_seconds: 5
      }
    }

    emit_telemetry(:supervision_status_requested, stats, %{})
    stats
  end

  @doc """
  Manually restarts a specific child in the supervision tree.
  """
  def restart_child(child_id) do
    case Supervisor.restart_child(__MODULE__, child_id) do
      {:ok, pid} ->
        emit_telemetry(:child_restarted, %{child_id: child_id, pid: pid}, %{})
        {:ok, pid}

      {:error, reason} ->
        emit_telemetry(:child_restart_failed, %{child_id: child_id, reason: reason}, %{})
        {:error, reason}
    end
  end

  # Private helper functions

  defp format_child_info({id, pid, type, modules}) do
    %{
      id: id,
      pid: pid,
      type: type,
      modules: modules,
      status: if(pid == :undefined, do: :not_running, else: :running)
    }
  end

  defp emit_telemetry(event, metadata, measurements) do
    :telemetry.execute(
      [:rubber_duck_engines, :engine_pool, :supervisor, event],
      measurements,
      metadata
    )
  end
end
