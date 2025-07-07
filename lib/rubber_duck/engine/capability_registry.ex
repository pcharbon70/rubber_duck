defmodule RubberDuck.Engine.CapabilityRegistry do
  @moduledoc """
  Registry for engine processes with capability-based discovery.

  This module maintains a registry of running engines and indexes them
  by their capabilities for efficient lookup.
  """

  use GenServer

  require Logger

  defmodule State do
    @moduledoc false
    defstruct [
      # capability => [engine_names]
      capabilities: %{},
      # engine_name => engine_config
      engines: %{}
    ]
  end

  # Client API

  @doc """
  Starts the engine registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers an engine with its capabilities.
  """
  def register_engine(engine_config) do
    GenServer.call(__MODULE__, {:register_engine, engine_config})
  end

  @doc """
  Unregisters an engine.
  """
  def unregister_engine(engine_name) do
    GenServer.call(__MODULE__, {:unregister_engine, engine_name})
  end

  @doc """
  Finds engines by capability.
  """
  def find_by_capability(capability) do
    GenServer.call(__MODULE__, {:find_by_capability, capability})
  end

  @doc """
  Gets engine configuration by name.
  """
  def get_engine(engine_name) do
    GenServer.call(__MODULE__, {:get_engine, engine_name})
  end

  @doc """
  Lists all registered engines.
  """
  def list_engines do
    GenServer.call(__MODULE__, :list_engines)
  end

  @doc """
  Lists all known capabilities.
  """
  def list_capabilities do
    GenServer.call(__MODULE__, :list_capabilities)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    {:ok, %State{}}
  end

  @impl true
  def handle_call({:register_engine, engine_config}, _from, state) do
    # Get capabilities from the engine module
    capabilities =
      if Code.ensure_loaded?(engine_config.module) and
           function_exported?(engine_config.module, :capabilities, 0) do
        engine_config.module.capabilities()
      else
        []
      end

    # Update capabilities index
    new_capabilities =
      Enum.reduce(capabilities, state.capabilities, fn cap, acc ->
        Map.update(acc, cap, [engine_config.name], fn engines ->
          if engine_config.name in engines do
            engines
          else
            [engine_config.name | engines]
          end
        end)
      end)

    # Store engine config
    new_engines = Map.put(state.engines, engine_config.name, engine_config)

    new_state = %{state | capabilities: new_capabilities, engines: new_engines}

    Logger.info("Registered engine #{engine_config.name} with capabilities: #{inspect(capabilities)}")

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unregister_engine, engine_name}, _from, state) do
    case Map.get(state.engines, engine_name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      engine_config ->
        # Get capabilities to clean up
        capabilities =
          if Code.ensure_loaded?(engine_config.module) and
               function_exported?(engine_config.module, :capabilities, 0) do
            engine_config.module.capabilities()
          else
            []
          end

        # Remove from capabilities index
        new_capabilities =
          Enum.reduce(capabilities, state.capabilities, fn cap, acc ->
            Map.update(acc, cap, [], fn engines ->
              List.delete(engines, engine_name)
            end)
          end)

        # Clean up empty capability entries
        new_capabilities =
          new_capabilities
          |> Enum.filter(fn {_cap, engines} -> engines != [] end)
          |> Map.new()

        # Remove engine config
        new_engines = Map.delete(state.engines, engine_name)

        new_state = %{state | capabilities: new_capabilities, engines: new_engines}

        Logger.info("Unregistered engine #{engine_name}")

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:find_by_capability, capability}, _from, state) do
    engine_names = Map.get(state.capabilities, capability, [])

    # Return only engines that are actually running
    running_engines =
      engine_names
      |> Enum.filter(fn name ->
        case Elixir.Registry.lookup(RubberDuck.Engine.Registry, name) do
          [{_pid, _}] -> true
          [] -> false
        end
      end)
      |> Enum.map(fn name -> Map.get(state.engines, name) end)
      |> Enum.filter(& &1)

    {:reply, running_engines, state}
  end

  @impl true
  def handle_call({:get_engine, engine_name}, _from, state) do
    engine = Map.get(state.engines, engine_name)
    {:reply, engine, state}
  end

  @impl true
  def handle_call(:list_engines, _from, state) do
    engines = Map.values(state.engines)
    {:reply, engines, state}
  end

  @impl true
  def handle_call(:list_capabilities, _from, state) do
    capabilities = Map.keys(state.capabilities)
    {:reply, capabilities, state}
  end
end
