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
    child_spec = %{
      id: engine_module,
      start: {engine_module, :start_link, [[config: config, name: engine_module]]},
      restart: :permanent,
      shutdown: 5_000,
      type: :worker
    }
    
    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Stops an engine process.
  """
  def stop_engine(engine_module) do
    case Registry.lookup(RubberDuckEngines.Registry, engine_module) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
      
      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all running engine processes.
  """
  def list_engines do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_id, pid, _type, modules} ->
      case modules do
        [module] -> {module, pid}
        _ -> {:unknown, pid}
      end
    end)
  end

  @doc """
  Restarts an engine process.
  """
  def restart_engine(engine_module, new_config \\ %{}) do
    case stop_engine(engine_module) do
      :ok -> start_engine(engine_module, new_config)
      {:error, :not_found} -> start_engine(engine_module, new_config)
      error -> error
    end
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end