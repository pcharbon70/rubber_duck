defmodule RubberDuck.Projects.FileManagerWatcher do
  @moduledoc """
  Integration between FileManager and FileWatcher for automatic cache invalidation
  and real-time file system monitoring.
  
  This module subscribes to file watcher events and automatically invalidates
  the FileCache when files change, ensuring cached data stays fresh.
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Projects.FileCache
  alias Phoenix.PubSub
  
  @pubsub RubberDuck.PubSub
  
  defmodule State do
    @moduledoc false
    defstruct [
      :project_id,
      subscriptions: MapSet.new()
    ]
  end
  
  # Client API
  
  @doc """
  Starts the FileManagerWatcher for a specific project.
  """
  def start_link(project_id) do
    GenServer.start_link(__MODULE__, project_id, 
      name: {:via, Registry, {RubberDuck.Projects.FileManagerWatcher.Registry, project_id}})
  end
  
  @doc """
  Ensures the watcher is running for a project.
  """
  def ensure_running(project_id) do
    case Registry.lookup(RubberDuck.Projects.FileManagerWatcher.Registry, project_id) do
      [] ->
        DynamicSupervisor.start_child(
          RubberDuck.Projects.FileManagerWatcher.Supervisor,
          {__MODULE__, project_id}
        )
      
      [{pid, _}] ->
        {:ok, pid}
    end
  end
  
  @doc """
  Stops the watcher for a project.
  """
  def stop(project_id) do
    case Registry.lookup(RubberDuck.Projects.FileManagerWatcher.Registry, project_id) do
      [{pid, _}] ->
        GenServer.stop(pid)
      
      [] ->
        :ok
    end
  end
  
  # Server callbacks
  
  @impl true
  def init(project_id) do
    # Subscribe to file watcher events
    topic = "file_watcher:#{project_id}"
    :ok = PubSub.subscribe(@pubsub, topic)
    
    state = %State{
      project_id: project_id,
      subscriptions: MapSet.new([topic])
    }
    
    Logger.info("FileManagerWatcher started for project #{project_id}")
    
    {:ok, state}
  end
  
  @impl true
  def handle_info({:file_changed, changes}, state) when is_list(changes) do
    # Process batch of changes
    Enum.each(changes, fn change ->
      handle_file_change(change, state.project_id)
    end)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info({:file_changed, change}, state) do
    handle_file_change(change, state.project_id)
    {:noreply, state}
  end
  
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  @impl true
  def terminate(_reason, state) do
    # Unsubscribe from all topics
    Enum.each(state.subscriptions, fn topic ->
      PubSub.unsubscribe(@pubsub, topic)
    end)
    
    :ok
  end
  
  # Private functions
  
  defp handle_file_change(change, project_id) do
    case change do
      %{type: :created, path: path} ->
        invalidate_for_change(project_id, path, :created)
        
      %{type: :modified, path: path} ->
        invalidate_for_change(project_id, path, :modified)
        
      %{type: :deleted, path: path} ->
        invalidate_for_change(project_id, path, :deleted)
        
      %{type: :renamed, old_path: old_path, new_path: new_path} ->
        invalidate_for_change(project_id, old_path, :deleted)
        invalidate_for_change(project_id, new_path, :created)
        
      _ ->
        Logger.debug("Unhandled file change type: #{inspect(change)}")
    end
  end
  
  defp invalidate_for_change(project_id, path, change_type) do
    # Always invalidate the specific file
    FileCache.invalidate(project_id, path)
    
    # Invalidate parent directory listing
    parent = Path.dirname(path)
    FileCache.invalidate_pattern(project_id, "list:#{parent}:*")
    
    # For directories, invalidate all children
    if change_type in [:deleted, :modified] do
      FileCache.invalidate_pattern(project_id, "#{path}/**")
    end
    
    Logger.debug("Cache invalidated for #{change_type} file: #{path}")
  end
end