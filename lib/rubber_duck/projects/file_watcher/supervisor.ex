defmodule RubberDuck.Projects.FileWatcher.Supervisor do
  @moduledoc """
  DynamicSupervisor for managing project file watchers.

  Provides supervised file watching capabilities with automatic restart
  and Registry-based process tracking.
  """

  use DynamicSupervisor
  require Logger

  alias RubberDuck.Projects.FileWatcher

  @registry RubberDuck.Projects.FileWatcher.Registry

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 3,
      max_seconds: 5
    )
  end

  @doc """
  Starts a file watcher for a specific project.

  ## Options
    * `:root_path` - Required. The root directory to watch
    * `:debounce_ms` - Debounce interval in milliseconds (default: 100)
    * `:batch_size` - Maximum events per batch (default: 50)
    * `:recursive` - Watch subdirectories (default: true)
  """
  @spec start_watcher(String.t(), map()) :: {:ok, pid()} | {:error, term()}
  def start_watcher(project_id, opts) when is_binary(project_id) do
    with :ok <- validate_opts(opts),
         {:ok, _} <- ensure_not_running(project_id) do
      child_spec = %{
        id: {:file_watcher, project_id},
        start: {FileWatcher, :start_link, [project_id, opts]},
        restart: :transient
      }

      case DynamicSupervisor.start_child(__MODULE__, child_spec) do
        {:ok, pid} ->
          Logger.info("Started file watcher for project #{project_id}")
          {:ok, pid}

        {:error, {:already_started, pid}} ->
          {:ok, pid}

        error ->
          Logger.error("Failed to start file watcher for project #{project_id}: #{inspect(error)}")
          error
      end
    end
  end

  @doc """
  Stops the file watcher for a specific project.
  """
  @spec stop_watcher(String.t()) :: :ok | {:error, :not_found}
  def stop_watcher(project_id) when is_binary(project_id) do
    case Registry.lookup(@registry, project_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        Logger.info("Stopped file watcher for project #{project_id}")
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all active file watchers.
  """
  @spec list_watchers() :: [{String.t(), pid()}]
  def list_watchers do
    Registry.select(@registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
  end

  @doc """
  Checks if a watcher is running for a project.
  """
  @spec watcher_running?(String.t()) :: boolean()
  def watcher_running?(project_id) when is_binary(project_id) do
    case Registry.lookup(@registry, project_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  @doc """
  Gets the pid of a watcher for a project.
  """
  @spec get_watcher(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def get_watcher(project_id) when is_binary(project_id) do
    case Registry.lookup(@registry, project_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  # Private functions

  defp validate_opts(opts) do
    cond do
      not is_binary(opts[:root_path]) ->
        {:error, :invalid_root_path}

      not File.dir?(opts[:root_path]) ->
        {:error, :root_path_not_directory}

      true ->
        :ok
    end
  end

  defp ensure_not_running(project_id) do
    case Registry.lookup(@registry, project_id) do
      [{pid, _}] -> {:error, {:already_started, pid}}
      [] -> {:ok, :not_running}
    end
  end
end

