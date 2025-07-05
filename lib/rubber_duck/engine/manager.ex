defmodule RubberDuck.Engine.Manager do
  @moduledoc """
  High-level API for managing and interacting with engines.
  
  This module provides convenient functions for loading engines from
  DSL modules, executing requests, and managing engine lifecycle.
  """
  
  require Logger
  
  alias RubberDuck.Engine.{CapabilityRegistry, Server, Supervisor}
  alias RubberDuck.EngineSystem
  
  @doc """
  Loads engines from an EngineSystem DSL module.
  """
  def load_engines(engine_module) do
    engines = EngineSystem.engines(engine_module)
    
    results = Enum.map(engines, fn engine_config ->
      case start_engine(engine_config) do
        {:ok, _pid} -> {:ok, engine_config.name}
        {:error, reason} -> {:error, {engine_config.name, reason}}
      end
    end)
    
    successes = Enum.count(results, &match?({:ok, _}, &1))
    failures = Enum.filter(results, &match?({:error, _}, &1))
    
    if failures == [] do
      Logger.info("Successfully loaded #{successes} engines from #{engine_module}")
      :ok
    else
      Logger.warning("Loaded #{successes} engines, failed to load: #{inspect(failures)}")
      {:error, failures}
    end
  end
  
  @doc """
  Starts an engine.
  """
  def start_engine(engine_config) do
    with :ok <- CapabilityRegistry.register_engine(engine_config),
         {:ok, pid} <- Supervisor.start_engine(engine_config) do
      {:ok, pid}
    else
      {:error, :already_started} ->
        # Engine is already running, that's fine
        case Elixir.Registry.lookup(RubberDuck.Engine.Registry, engine_config.name) do
          [{pid, _}] -> {:ok, pid}
          [] -> {:error, :registry_inconsistency}
        end
        
      error ->
        # Clean up registry if supervisor start failed
        CapabilityRegistry.unregister_engine(engine_config.name)
        error
    end
  end
  
  @doc """
  Stops an engine.
  """
  def stop_engine(engine_name) do
    with :ok <- Supervisor.stop_engine(engine_name),
         :ok <- CapabilityRegistry.unregister_engine(engine_name) do
      :ok
    end
  end
  
  @doc """
  Restarts an engine.
  """
  def restart_engine(engine_name) do
    case CapabilityRegistry.get_engine(engine_name) do
      nil ->
        {:error, :not_found}
        
      engine_config ->
        with :ok <- stop_engine(engine_name),
             :ok <- Process.sleep(100),
             {:ok, pid} <- start_engine(engine_config) do
          {:ok, pid}
        end
    end
  end
  
  @doc """
  Executes a request on a specific engine.
  """
  def execute(engine_name, input, timeout \\ 5000) do
    case Elixir.Registry.lookup(RubberDuck.Engine.Registry, engine_name) do
      [{pid, _}] ->
        Server.execute(pid, input, timeout)
        
      [] ->
        {:error, :engine_not_found}
    end
  end
  
  @doc """
  Executes a request on any engine with the given capability.
  
  Options:
    - :strategy - :first | :random | :round_robin (default: :first)
    - :timeout - execution timeout in ms (default: 5000)
  """
  def execute_by_capability(capability, input, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :first)
    timeout = Keyword.get(opts, :timeout, 5000)
    
    case CapabilityRegistry.find_by_capability(capability) do
      [] ->
        {:error, :no_engine_with_capability}
        
      engines ->
        engine = select_engine(engines, strategy)
        execute(engine.name, input, timeout)
    end
  end
  
  @doc """
  Gets the status of an engine.
  """
  def status(engine_name) do
    case Elixir.Registry.lookup(RubberDuck.Engine.Registry, engine_name) do
      [{pid, _}] ->
        Server.status(pid)
        
      [] ->
        {:error, :engine_not_found}
    end
  end
  
  @doc """
  Gets the health status of an engine.
  """
  def health_status(engine_name) do
    case Elixir.Registry.lookup(RubberDuck.Engine.Registry, engine_name) do
      [{pid, _}] ->
        Server.health_check(pid)
        
      [] ->
        :not_found
    end
  end
  
  @doc """
  Lists all running engines.
  """
  def list_engines do
    Supervisor.list_engines()
  end
  
  @doc """
  Lists all available capabilities.
  """
  def list_capabilities do
    CapabilityRegistry.list_capabilities()
  end
  
  @doc """
  Finds engines by capability.
  """
  def find_engines_by_capability(capability) do
    CapabilityRegistry.find_by_capability(capability)
  end
  
  @doc """
  Gets statistics for all engines.
  """
  def stats do
    engines = list_engines()
    
    engine_stats = Enum.map(engines, fn {name, _pid} ->
      case status(name) do
        {:error, _} -> nil
        status_info -> {name, status_info}
      end
    end)
    |> Enum.filter(& &1)
    |> Map.new()
    
    %{
      total_engines: length(engines),
      engines: engine_stats,
      capabilities: list_capabilities()
    }
  end
  
  # Private Functions
  
  defp select_engine(engines, :first) do
    hd(engines)
  end
  
  defp select_engine(engines, :random) do
    Enum.random(engines)
  end
  
  defp select_engine(engines, :round_robin) do
    # Simple round-robin using current timestamp
    # In production, you'd want a more sophisticated approach
    index = rem(System.system_time(:second), length(engines))
    Enum.at(engines, index)
  end
end