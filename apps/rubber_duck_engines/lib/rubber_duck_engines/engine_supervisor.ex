defmodule RubberDuckEngines.EngineSupervisor do
  @moduledoc """
  Dynamic supervisor for managing analysis engine processes.

  Handles starting, stopping, and restarting engine processes
  with proper isolation and fault tolerance.
  """

  use DynamicSupervisor

  @doc """
  Starts the engine supervisor.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Starts an engine process under supervision.
  """
  def start_engine(engine_module, config \\ %{}) do
    start_time = System.monotonic_time()

    child_spec = %{
      id: engine_module,
      start: {engine_module, :start_link, [[config: config, name: engine_module]]},
      restart: :permanent,
      shutdown: 5_000,
      type: :worker
    }

    result = DynamicSupervisor.start_child(__MODULE__, child_spec)

    case result do
      {:ok, pid} ->
        emit_telemetry(:engine_started, %{engine: engine_module, pid: pid}, %{
          start_time: start_time
        })

        {:ok, pid}

      {:error, {:already_started, pid}} ->
        emit_telemetry(:engine_already_started, %{engine: engine_module, pid: pid}, %{})
        {:ok, pid}

      {:error, reason} ->
        emit_telemetry(:engine_start_failed, %{engine: engine_module, reason: reason}, %{
          start_time: start_time
        })

        {:error, reason}
    end
  end

  @doc """
  Stops an engine process.
  """
  def stop_engine(engine_module) do
    case Registry.lookup(RubberDuckEngines.Registry, engine_module) do
      [{pid, _}] ->
        result = DynamicSupervisor.terminate_child(__MODULE__, pid)
        emit_telemetry(:engine_stopped, %{engine: engine_module, pid: pid}, %{})
        result

      [] ->
        emit_telemetry(:engine_stop_failed, %{engine: engine_module, reason: :not_found}, %{})
        {:error, :not_found}
    end
  end

  @doc """
  Lists all running engine processes.
  """
  def list_engines do
    children = DynamicSupervisor.which_children(__MODULE__)

    engines =
      children
      |> Enum.map(fn {_id, pid, _type, modules} ->
        case modules do
          [module] -> {module, pid}
          _ -> {:unknown, pid}
        end
      end)

    emit_telemetry(:engines_listed, %{count: length(engines)}, %{})
    engines
  end

  @doc """
  Gets the count of running engines.
  """
  def engine_count do
    DynamicSupervisor.count_children(__MODULE__)
  end

  @doc """
  Checks if an engine is running.
  """
  def engine_running?(engine_module) do
    case Registry.lookup(RubberDuckEngines.Registry, engine_module) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  @doc """
  Restarts an engine process.
  """
  def restart_engine(engine_module, new_config \\ %{}) do
    emit_telemetry(:engine_restart_requested, %{engine: engine_module}, %{})

    case stop_engine(engine_module) do
      :ok ->
        result = start_engine(engine_module, new_config)
        emit_telemetry(:engine_restarted, %{engine: engine_module}, %{})
        result

      {:error, :not_found} ->
        result = start_engine(engine_module, new_config)
        emit_telemetry(:engine_restarted, %{engine: engine_module}, %{})
        result

      error ->
        emit_telemetry(:engine_restart_failed, %{engine: engine_module, reason: error}, %{})
        error
    end
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # Private functions

  defp emit_telemetry(event, metadata, measurements) do
    :telemetry.execute(
      [:rubber_duck_engines, :engine_supervisor, event],
      measurements,
      metadata
    )
  end
end
