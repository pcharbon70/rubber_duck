defmodule RubberDuck.Plugin.Runner do
  @moduledoc """
  Provides isolated execution environment for plugins.

  Each plugin can be run in its own supervised process to provide
  fault isolation and prevent plugins from affecting the main system
  or other plugins.
  """

  use GenServer
  require Logger

  @type plugin_ref :: atom() | pid()

  @doc """
  Starts a plugin runner process.
  """
  def start_link(opts) do
    plugin_module = Keyword.fetch!(opts, :module)
    plugin_config = Keyword.get(opts, :config, [])
    name = Keyword.get(opts, :name)

    GenServer.start_link(__MODULE__, {plugin_module, plugin_config}, name: name)
  end

  @doc """
  Executes a plugin in isolation.
  """
  def execute(runner, input, timeout \\ 5_000) do
    GenServer.call(runner, {:execute, input}, timeout)
  end

  @doc """
  Gets the current state of the plugin.
  """
  def get_state(runner) do
    GenServer.call(runner, :get_state)
  end

  @doc """
  Updates plugin configuration.
  """
  def update_config(runner, new_config) do
    GenServer.call(runner, {:update_config, new_config})
  end

  # Server Callbacks

  @impl true
  def init({plugin_module, plugin_config}) do
    Process.flag(:trap_exit, true)

    case plugin_module.init(plugin_config) do
      {:ok, plugin_state} ->
        state = %{
          module: plugin_module,
          plugin_state: plugin_state,
          config: plugin_config,
          stats: %{
            executions: 0,
            errors: 0,
            last_execution: nil
          }
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, {:plugin_init_failed, reason}}
    end
  end

  @impl true
  def handle_call({:execute, input}, _from, state) do
    start_time = System.monotonic_time()

    # Execute in a monitored task for isolation
    task =
      Task.async(fn ->
        execute_plugin(state.module, input, state.plugin_state)
      end)

    result =
      case Task.yield(task, :infinity) do
        {:ok, {:ok, output, new_plugin_state}} ->
          new_state = %{state | plugin_state: new_plugin_state, stats: update_stats(state.stats, :success, start_time)}
          {:reply, {:ok, output}, new_state}

        {:ok, {:error, reason, new_plugin_state}} ->
          new_state = %{state | plugin_state: new_plugin_state, stats: update_stats(state.stats, :error, start_time)}
          {:reply, {:error, reason}, new_state}

        {:ok, {:error, reason}} ->
          new_state = %{state | stats: update_stats(state.stats, :error, start_time)}
          {:reply, {:error, reason}, new_state}

        {:exit, reason} ->
          Logger.error("Plugin #{inspect(state.module)} crashed: #{inspect(reason)}")
          new_state = %{state | stats: update_stats(state.stats, :crash, start_time)}
          {:reply, {:error, {:plugin_crashed, reason}}, new_state}

        nil ->
          # Should not happen with :infinity timeout
          {:reply, {:error, :timeout}, state}
      end

    result
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state.plugin_state}, state}
  end

  @impl true
  def handle_call({:update_config, new_config}, _from, state) do
    case handle_config_update(state.module, new_config, state.plugin_state) do
      {:ok, new_plugin_state} ->
        new_state = %{state | config: new_config, plugin_state: new_plugin_state}
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    state.module.terminate(reason, state.plugin_state)
  end

  # Private Functions

  defp execute_plugin(module, input, plugin_state) do
    # Optional input validation
    with :ok <- validate_if_exported(module, input),
         {:ok, output, new_state} <- module.execute(input, plugin_state) do
      {:ok, output, new_state}
    else
      {:error, reason, new_state} -> {:error, reason, new_state}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_return, other}}
    end
  end

  defp validate_if_exported(module, input) do
    if function_exported?(module, :validate_input, 1) do
      module.validate_input(input)
    else
      :ok
    end
  end

  defp handle_config_update(module, new_config, plugin_state) do
    if function_exported?(module, :handle_config_change, 2) do
      module.handle_config_change(new_config, plugin_state)
    else
      # Plugin doesn't support config updates
      {:ok, plugin_state}
    end
  end

  defp update_stats(stats, result, start_time) do
    duration = System.monotonic_time() - start_time

    %{
      stats
      | executions: stats.executions + 1,
        errors: if(result == :error or result == :crash, do: stats.errors + 1, else: stats.errors),
        last_execution: %{
          timestamp: DateTime.utc_now(),
          duration_native: duration,
          duration_ms: System.convert_time_unit(duration, :native, :millisecond),
          result: result
        }
    }
  end
end
