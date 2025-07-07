defmodule RubberDuck.Plugin.Supervisor do
  @moduledoc """
  Supervises plugin runner processes.

  Provides fault isolation by supervising each plugin in its own process.
  If a plugin crashes, it can be restarted without affecting other plugins
  or the main system.
  """

  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 60
    )
  end

  @doc """
  Starts a new plugin runner under supervision.
  """
  def start_plugin(plugin_name, plugin_module, config \\ []) do
    spec = %{
      id: plugin_name,
      start:
        {RubberDuck.Plugin.Runner, :start_link,
         [
           [
             module: plugin_module,
             config: config,
             name: via_tuple(plugin_name)
           ]
         ]},
      restart: :permanent,
      type: :worker
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Stops a plugin runner.
  """
  def stop_plugin(plugin_name) do
    case Registry.lookup(RubberDuck.Plugin.Registry, plugin_name) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all running plugin runners.
  """
  def list_plugins do
    __MODULE__
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_, pid, _, _} ->
      case Registry.keys(RubberDuck.Plugin.Registry, pid) do
        [name] -> {name, pid}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Gets the pid of a plugin runner by name.
  """
  def get_plugin(plugin_name) do
    case Registry.lookup(RubberDuck.Plugin.Registry, plugin_name) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  defp via_tuple(plugin_name) do
    {:via, Registry, {RubberDuck.Plugin.Registry, plugin_name}}
  end
end
