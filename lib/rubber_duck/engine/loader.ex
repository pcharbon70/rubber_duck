defmodule RubberDuck.Engine.Loader do
  @moduledoc """
  Loads and initializes engines from the configuration module.

  This GenServer is responsible for:
  - Loading engine configurations at startup
  - Registering engines with the CapabilityRegistry
  - Managing engine lifecycle
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Load engines after a short delay to ensure all systems are ready
    Process.send_after(self(), :load_engines, 100)

    {:ok,
     %{
       engine_module: Keyword.get(opts, :engine_module, RubberDuck.Engines),
       loaded: false
     }}
  end

  @impl true
  def handle_info(:load_engines, state) do
    case load_engines(state.engine_module) do
      :ok ->
        Logger.info("Successfully loaded engines from #{state.engine_module}")
        {:noreply, %{state | loaded: true}}

      {:error, reason} ->
        Logger.error("Failed to load engines: #{inspect(reason)}")
        # Retry after 5 seconds
        Process.send_after(self(), :load_engines, 5_000)
        {:noreply, state}
    end
  end

  defp load_engines(engine_module) do
    # Check if the engine module exists
    if Code.ensure_loaded?(engine_module) do
      try do
        # Load the engines using the Engine.Manager
        case RubberDuck.Engine.Manager.load_engines(engine_module) do
          {:ok, engines} ->
            Logger.info("Loaded #{length(engines)} engines")
            :ok

          {:error, reason} ->
            {:error, reason}
        end
      rescue
        e ->
          Logger.error("Exception while loading engines: #{Exception.message(e)}")
          {:error, {:exception, e}}
      end
    else
      Logger.warning("Engine module #{engine_module} not found, using default engines")
      load_default_engines()
    end
  end

  defp load_default_engines do
    # Load engines directly without configuration module
    engines = [
      {RubberDuck.Engines.Generation, [name: :generation]},
      {RubberDuck.Engines.Completion, [name: :completion]},
      {RubberDuck.Engines.Analysis, [name: :analysis]},
      {RubberDuck.Engines.Refactoring, [name: :refactoring]},
      {RubberDuck.Engines.TestGeneration, [name: :test_generation]}
    ]

    Enum.each(engines, fn {module, opts} ->
      case RubberDuck.Engine.Supervisor.start_engine(module, opts) do
        {:ok, _pid} ->
          Logger.info("Started engine #{module}")

        {:error, reason} ->
          Logger.error("Failed to start engine #{module}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  @doc """
  Check if engines are loaded.
  """
  def loaded? do
    GenServer.call(__MODULE__, :loaded?)
  end

  @impl true
  def handle_call(:loaded?, _from, state) do
    {:reply, state.loaded, state}
  end
end
