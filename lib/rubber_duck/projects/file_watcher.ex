defmodule RubberDuck.Projects.FileWatcher do
  @moduledoc """
  GenServer for watching file changes in a project directory.
  
  Monitors file system events, validates paths against project sandbox,
  batches events, and broadcasts them via PubSub.
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Projects.{FileAccess, SymlinkSecurity}
  alias Phoenix.PubSub
  
  @registry RubberDuck.Projects.FileWatcher.Registry
  @pubsub RubberDuck.PubSub
  @default_debounce_ms 100
  @default_batch_size 50
  
  defmodule State do
    @moduledoc false
    defstruct [
      :project_id,
      :root_path,
      :watcher_pid,
      :debounce_ms,
      :batch_size,
      :debounce_timer,
      :recursive,
      event_buffer: [],
      subscribers: MapSet.new()
    ]
  end
  
  # Client API
  
  def start_link(project_id, opts) do
    GenServer.start_link(__MODULE__, {project_id, opts}, 
      name: {:via, Registry, {@registry, project_id}})
  end
  
  @doc """
  Subscribe to file change events for a project.
  """
  def subscribe(project_id) do
    topic = file_watcher_topic(project_id)
    PubSub.subscribe(@pubsub, topic)
  end
  
  @doc """
  Unsubscribe from file change events for a project.
  """
  def unsubscribe(project_id) do
    topic = file_watcher_topic(project_id)
    PubSub.unsubscribe(@pubsub, topic)
  end
  
  @doc """
  Get current status of the file watcher.
  """
  def get_status(project_id) do
    case Registry.lookup(@registry, project_id) do
      [{pid, _}] -> GenServer.call(pid, :get_status)
      [] -> {:error, :not_found}
    end
  end
  
  # Server callbacks
  
  @impl true
  def init({project_id, opts}) do
    Process.flag(:trap_exit, true)
    
    state = %State{
      project_id: project_id,
      root_path: opts.root_path,
      debounce_ms: opts[:debounce_ms] || @default_debounce_ms,
      batch_size: opts[:batch_size] || @default_batch_size,
      recursive: opts[:recursive] !== false
    }
    
    case start_file_system(state) do
      {:ok, watcher_pid} ->
        Logger.info("File watcher started for project #{project_id} at #{state.root_path}")
        
        # TODO: Log the start event when SecurityAudit.log_file_access is implemented
        # SecurityAudit.log_file_access(project_id, %{
        #   action: "file_watcher_started",
        #   path: state.root_path,
        #   status: "success"
        # })
        
        {:ok, %{state | watcher_pid: watcher_pid}}
        
      :ignore ->
        # FileSystem is not available (e.g., inotify-tools not installed)
        Logger.warning("File system watching not available for project #{project_id} - file watcher will run in degraded mode")
        {:ok, state}
        
      {:error, reason} ->
        Logger.error("Failed to start file watcher: #{inspect(reason)}")
        {:stop, reason}
    end
  end
  
  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      project_id: state.project_id,
      root_path: state.root_path,
      watching: not is_nil(state.watcher_pid),
      buffer_size: length(state.event_buffer),
      subscriber_count: MapSet.size(state.subscribers)
    }
    
    {:reply, {:ok, status}, state}
  end
  
  @impl true
  def handle_info({:file_event, watcher_pid, {path, events}}, %{watcher_pid: watcher_pid} = state) do
    # Validate the path is within project bounds
    case validate_and_process_event(path, events, state) do
      {:ok, event} ->
        state = add_event_to_buffer(event, state)
        state = schedule_or_reset_debounce(state)
        {:noreply, state}
        
      {:error, reason} ->
        Logger.debug("Ignoring file event for #{path}: #{reason}")
        {:noreply, state}
    end
  end
  
  def handle_info({:file_event, watcher_pid, :stop}, %{watcher_pid: watcher_pid} = state) do
    Logger.info("File system watcher stopped for project #{state.project_id}")
    {:noreply, %{state | watcher_pid: nil}}
  end
  
  def handle_info({:file_event, _, _}, state) do
    # Ignore events from unknown watchers
    {:noreply, state}
  end
  
  def handle_info(:flush_events, state) do
    state = flush_event_buffer(state)
    {:noreply, state}
  end
  
  def handle_info({:EXIT, pid, reason}, %{watcher_pid: pid} = state) do
    Logger.warning("File system watcher crashed: #{inspect(reason)}")
    
    # Try to restart the watcher
    case start_file_system(state) do
      {:ok, new_pid} ->
        {:noreply, %{state | watcher_pid: new_pid}}
        
      {:error, _} ->
        # Give up after restart failure
        {:stop, :watcher_failed, state}
    end
  end
  
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  @impl true
  def terminate(reason, state) do
    Logger.info("File watcher terminating for project #{state.project_id}: #{inspect(reason)}")
    
    # The file system watcher will be terminated automatically
    # when this process terminates due to the link
    
    # Cancel debounce timer
    if state.debounce_timer do
      Process.cancel_timer(state.debounce_timer)
    end
    
    # Flush any remaining events
    flush_event_buffer(state)
    
    # TODO: Log the stop event when SecurityAudit.log_file_access is implemented
    # SecurityAudit.log_file_access(state.project_id, %{
    #   action: "file_watcher_stopped",
    #   path: state.root_path,
    #   status: "success"
    # })
    
    :ok
  end
  
  # Private functions
  
  defp start_file_system(state) do
    case FileSystem.start_link(dirs: [state.root_path], recursive: state.recursive) do
      {:ok, pid} ->
        # Subscribe to file system events
        FileSystem.subscribe(pid)
        {:ok, pid}
        
      :ignore ->
        # FileSystem not available (missing inotify-tools)
        :ignore
        
      error ->
        error
    end
  end
  
  defp validate_and_process_event(path, events, state) do
    # Convert events to our format
    event_type = categorize_events(events)
    
    # Validate path is within project bounds
    with {:ok, safe_path} <- FileAccess.validate_path(path, state.root_path),
         {:ok, :safe} <- SymlinkSecurity.check_symlinks(safe_path, state.root_path) do
      
      # Create relative path for the event
      relative_path = Path.relative_to(safe_path, state.root_path)
      
      event = %{
        path: relative_path,
        absolute_path: safe_path,
        type: event_type,
        timestamp: DateTime.utc_now()
      }
      
      {:ok, event}
    else
      error -> error
    end
  end
  
  defp categorize_events(events) do
    cond do
      :created in events -> :created
      :removed in events -> :deleted
      :renamed in events -> :renamed
      :modified in events -> :modified
      true -> :unknown
    end
  end
  
  defp add_event_to_buffer(event, state) do
    buffer = [event | state.event_buffer]
    
    # If buffer is full, flush immediately
    if length(buffer) >= state.batch_size do
      flush_event_buffer(%{state | event_buffer: buffer})
    else
      %{state | event_buffer: buffer}
    end
  end
  
  defp schedule_or_reset_debounce(state) do
    # Cancel existing timer
    if state.debounce_timer do
      Process.cancel_timer(state.debounce_timer)
    end
    
    # Schedule new timer
    timer = Process.send_after(self(), :flush_events, state.debounce_ms)
    %{state | debounce_timer: timer}
  end
  
  defp flush_event_buffer(%{event_buffer: []} = state), do: state
  
  defp flush_event_buffer(state) do
    # Reverse to maintain chronological order
    events = Enum.reverse(state.event_buffer)
    
    # Deduplicate events by path, keeping the latest
    unique_events = events
    |> Enum.reduce(%{}, fn event, acc ->
      Map.put(acc, event.path, event)
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.timestamp)
    
    # Broadcast the batch
    message = %{
      event: :file_changed,
      project_id: state.project_id,
      changes: unique_events,
      batch_size: length(unique_events)
    }
    
    topic = file_watcher_topic(state.project_id)
    PubSub.broadcast(@pubsub, topic, message)
    
    # TODO: Log batch for security audit when SecurityAudit.log_file_access is implemented
    # SecurityAudit.log_file_access(state.project_id, %{
    #   action: "file_watcher_batch",
    #   paths: Enum.map(unique_events, & &1.path),
    #   event_count: length(unique_events),
    #   status: "success"
    # })
    
    Logger.debug("Broadcast #{length(unique_events)} file events for project #{state.project_id}")
    
    %{state | event_buffer: [], debounce_timer: nil}
  end
  
  defp file_watcher_topic(project_id) do
    "file_watcher:project:#{project_id}"
  end
end