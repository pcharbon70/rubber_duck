defmodule RubberDuck.Engine.Supervisor do
  @moduledoc """
  Supervisor for engine processes.
  
  Uses a DynamicSupervisor to manage engine instances, allowing engines
  to be started and stopped at runtime.
  """
  
  use DynamicSupervisor
  
  require Logger
  
  @doc """
  Starts the engine supervisor.
  """
  def start_link(init_arg \\ []) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @doc """
  Starts an engine under supervision.
  """
  def start_engine(engine_config, opts \\ []) do
    child_spec = %{
      id: engine_config.name,
      start: {RubberDuck.Engine.Server, :start_link, [engine_config, opts]},
      restart: :permanent,
      type: :worker
    }
    
    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        Logger.info("Started engine #{engine_config.name} with pid #{inspect(pid)}")
        {:ok, pid}
        
      {:error, {:already_started, pid}} ->
        Logger.warning("Engine #{engine_config.name} already started with pid #{inspect(pid)}")
        {:error, :already_started}
        
      {:error, reason} ->
        Logger.error("Failed to start engine #{engine_config.name}: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Stops an engine.
  """
  def stop_engine(engine_name) when is_atom(engine_name) do
    case Elixir.Registry.lookup(RubberDuck.Engine.Registry, engine_name) do
      [{pid, _}] ->
        Logger.info("Stopping engine #{engine_name}")
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        
      [] ->
        {:error, :not_found}
    end
  end
  
  def stop_engine(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
  
  @doc """
  Lists all running engines.
  """
  def list_engines do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_, pid, _, _} -> 
      case Elixir.Registry.keys(RubberDuck.Engine.Registry, pid) do
        [name] -> {name, pid}
        _ -> nil
      end
    end)
    |> Enum.filter(& &1)
  end
  
  @doc """
  Counts running engines.
  """
  def count_engines do
    DynamicSupervisor.count_children(__MODULE__)
  end
  
  @doc """
  Restarts an engine.
  """
  def restart_engine(engine_name, engine_config) do
    with :ok <- stop_engine(engine_name),
         # Give it a moment to clean up
         :ok <- Process.sleep(100),
         {:ok, pid} <- start_engine(engine_config) do
      {:ok, pid}
    end
  end
  
  # Callbacks
  
  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 3,
      max_seconds: 5
    )
  end
end