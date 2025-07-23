defmodule RubberDuck.Projects.FileCollaboration do
  @moduledoc """
  Real-time collaborative features for file management.
  
  Provides:
  - File locking mechanisms
  - Real-time change notifications
  - Collaborative editing sessions
  - Presence tracking
  - Conflict resolution
  - Activity feeds
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Projects.{FileManager, FileAudit}
  alias Phoenix.PubSub
  
  @type lock_type :: :exclusive | :shared
  @type lock_id :: String.t()
  
  @type file_lock :: %{
    id: lock_id(),
    file_path: String.t(),
    user_id: String.t(),
    type: lock_type(),
    acquired_at: DateTime.t(),
    expires_at: DateTime.t() | nil,
    metadata: map()
  }
  
  @type presence_info :: %{
    user_id: String.t(),
    file_path: String.t(),
    cursor_position: {line :: pos_integer(), column :: pos_integer()} | nil,
    selection: {start_pos :: pos_integer(), end_pos :: pos_integer()} | nil,
    joined_at: DateTime.t()
  }
  
  @lock_timeout 300_000  # 5 minutes default
  @presence_timeout 30_000  # 30 seconds for presence updates
  
  # Client API
  
  @doc """
  Starts the collaboration server for a project.
  """
  def start_link(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    name = name(project_id)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Acquires a lock on a file.
  
  ## Options
  - `:type` - Lock type (:exclusive or :shared, default: :exclusive)
  - `:timeout` - Lock timeout in ms (default: 5 minutes)
  - `:metadata` - Additional metadata to store with lock
  """
  @spec acquire_lock(String.t(), FileManager.t(), String.t(), keyword()) ::
    {:ok, lock_id()} | {:error, :locked | term()}
  def acquire_lock(project_id, %FileManager{user: user}, file_path, opts \\ []) do
    GenServer.call(name(project_id), {:acquire_lock, file_path, user.id, opts})
  catch
    :exit, {:noproc, _} ->
      {:error, :collaboration_not_started}
  end
  
  @doc """
  Releases a lock on a file.
  """
  @spec release_lock(String.t(), lock_id()) :: :ok | {:error, :not_found}
  def release_lock(project_id, lock_id) do
    GenServer.call(name(project_id), {:release_lock, lock_id})
  catch
    :exit, {:noproc, _} ->
      {:error, :collaboration_not_started}
  end
  
  @doc """
  Checks if a file is locked.
  """
  @spec locked?(String.t(), String.t()) :: boolean()
  def locked?(project_id, file_path) do
    case get_lock(project_id, file_path) do
      {:ok, _lock} -> true
      _ -> false
    end
  end
  
  @doc """
  Gets lock information for a file.
  """
  @spec get_lock(String.t(), String.t()) :: {:ok, file_lock()} | {:error, :not_found}
  def get_lock(project_id, file_path) do
    GenServer.call(name(project_id), {:get_lock, file_path})
  catch
    :exit, {:noproc, _} ->
      {:error, :collaboration_not_started}
  end
  
  @doc """
  Lists all active locks in a project.
  """
  @spec list_locks(String.t()) :: {:ok, [file_lock()]}
  def list_locks(project_id) do
    GenServer.call(name(project_id), :list_locks)
  catch
    :exit, {:noproc, _} ->
      {:ok, []}
  end
  
  @doc """
  Tracks user presence on a file.
  """
  @spec track_presence(String.t(), FileManager.t(), String.t(), map()) :: :ok
  def track_presence(project_id, %FileManager{user: user}, file_path, metadata \\ %{}) do
    presence_info = %{
      user_id: user.id,
      file_path: file_path,
      cursor_position: Map.get(metadata, :cursor_position),
      selection: Map.get(metadata, :selection),
      joined_at: DateTime.utc_now()
    }
    
    GenServer.cast(name(project_id), {:track_presence, presence_info})
  catch
    :exit, {:noproc, _} ->
      :ok
  end
  
  @doc """
  Gets all users currently viewing a file.
  """
  @spec get_file_presence(String.t(), String.t()) :: {:ok, [presence_info()]}
  def get_file_presence(project_id, file_path) do
    GenServer.call(name(project_id), {:get_file_presence, file_path})
  catch
    :exit, {:noproc, _} ->
      {:ok, []}
  end
  
  @doc """
  Broadcasts a file change event to all collaborators.
  """
  @spec broadcast_change(String.t(), FileManager.t(), String.t(), map()) :: :ok
  def broadcast_change(project_id, %FileManager{user: user}, file_path, change_data) do
    event = %{
      type: :file_changed,
      file_path: file_path,
      user_id: user.id,
      change: change_data,
      timestamp: DateTime.utc_now()
    }
    
    PubSub.broadcast(
      RubberDuck.PubSub,
      file_topic(project_id, file_path),
      {:file_event, event}
    )
  end
  
  @doc """
  Subscribes to file events.
  """
  @spec subscribe_to_file(String.t(), String.t()) :: :ok | {:error, term()}
  def subscribe_to_file(project_id, file_path) do
    PubSub.subscribe(RubberDuck.PubSub, file_topic(project_id, file_path))
  end
  
  @doc """
  Subscribes to project-wide events.
  """
  @spec subscribe_to_project(String.t()) :: :ok | {:error, term()}
  def subscribe_to_project(project_id) do
    PubSub.subscribe(RubberDuck.PubSub, project_topic(project_id))
  end
  
  @doc """
  Records a collaborative action in the activity feed.
  """
  @spec record_activity(String.t(), FileManager.t(), String.t(), atom(), map()) :: :ok
  def record_activity(project_id, %FileManager{user: user}, file_path, action, metadata \\ %{}) do
    activity = %{
      project_id: project_id,
      user_id: user.id,
      file_path: file_path,
      action: action,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }
    
    # Broadcast to activity feed
    PubSub.broadcast(
      RubberDuck.PubSub,
      project_topic(project_id),
      {:activity, activity}
    )
    
    # Also log to FileAudit for persistence
    Task.start(fn ->
      FileAudit.log_operation(%{
        operation: action,
        file_path: file_path,
        status: :success,
        metadata: Map.put(metadata, :collaborative, true),
        project_id: project_id,
        user_id: user.id
      })
    end)
    
    :ok
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    
    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_expired, 60_000)
    
    state = %{
      project_id: project_id,
      locks: %{},  # file_path => lock
      lock_index: %{},  # lock_id => file_path
      presence: %{},  # file_path => %{user_id => presence_info}
      started_at: DateTime.utc_now()
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:acquire_lock, file_path, user_id, opts}, _from, state) do
    lock_type = Keyword.get(opts, :type, :exclusive)
    timeout = Keyword.get(opts, :timeout, @lock_timeout)
    metadata = Keyword.get(opts, :metadata, %{})
    
    case check_lock_compatibility(state.locks, file_path, lock_type, user_id) do
      :ok ->
        lock_id = generate_lock_id()
        now = DateTime.utc_now()
        
        lock = %{
          id: lock_id,
          file_path: file_path,
          user_id: user_id,
          type: lock_type,
          acquired_at: now,
          expires_at: if(timeout, do: DateTime.add(now, timeout, :millisecond), else: nil),
          metadata: metadata
        }
        
        new_locks = Map.put(state.locks, file_path, lock)
        new_index = Map.put(state.lock_index, lock_id, file_path)
        new_state = %{state | locks: new_locks, lock_index: new_index}
        
        # Broadcast lock acquired
        broadcast_lock_event(state.project_id, file_path, :lock_acquired, lock)
        
        {:reply, {:ok, lock_id}, new_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:release_lock, lock_id}, _from, state) do
    case Map.get(state.lock_index, lock_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      file_path ->
        lock = Map.get(state.locks, file_path)
        
        new_locks = Map.delete(state.locks, file_path)
        new_index = Map.delete(state.lock_index, lock_id)
        new_state = %{state | locks: new_locks, lock_index: new_index}
        
        # Broadcast lock released
        broadcast_lock_event(state.project_id, file_path, :lock_released, lock)
        
        {:reply, :ok, new_state}
    end
  end
  
  @impl true
  def handle_call({:get_lock, file_path}, _from, state) do
    case Map.get(state.locks, file_path) do
      nil -> {:reply, {:error, :not_found}, state}
      lock -> {:reply, {:ok, lock}, state}
    end
  end
  
  @impl true
  def handle_call(:list_locks, _from, state) do
    locks = Map.values(state.locks)
    {:reply, {:ok, locks}, state}
  end
  
  @impl true
  def handle_call({:get_file_presence, file_path}, _from, state) do
    presence_map = Map.get(state.presence, file_path, %{})
    presence_list = Map.values(presence_map)
    {:reply, {:ok, presence_list}, state}
  end
  
  @impl true
  def handle_cast({:track_presence, presence_info}, state) do
    file_path = presence_info.file_path
    user_id = presence_info.user_id
    
    file_presence = Map.get(state.presence, file_path, %{})
    updated_presence = Map.put(file_presence, user_id, presence_info)
    new_presence = Map.put(state.presence, file_path, updated_presence)
    
    # Broadcast presence update
    PubSub.broadcast(
      RubberDuck.PubSub,
      file_topic(state.project_id, file_path),
      {:presence_update, presence_info}
    )
    
    # Schedule presence timeout check
    Process.send_after(self(), {:check_presence, file_path, user_id}, @presence_timeout)
    
    {:noreply, %{state | presence: new_presence}}
  end
  
  @impl true
  def handle_info(:cleanup_expired, state) do
    now = DateTime.utc_now()
    
    # Clean up expired locks
    {active_locks, expired_locks} = state.locks
    |> Enum.split_with(fn {_path, lock} ->
      is_nil(lock.expires_at) or DateTime.compare(lock.expires_at, now) == :gt
    end)
    
    # Broadcast expired locks
    Enum.each(expired_locks, fn {file_path, lock} ->
      broadcast_lock_event(state.project_id, file_path, :lock_expired, lock)
    end)
    
    # Update state
    new_locks = Map.new(active_locks)
    expired_ids = Enum.map(expired_locks, fn {_path, lock} -> lock.id end)
    new_index = Map.drop(state.lock_index, expired_ids)
    
    # Schedule next cleanup
    Process.send_after(self(), :cleanup_expired, 60_000)
    
    {:noreply, %{state | locks: new_locks, lock_index: new_index}}
  end
  
  @impl true
  def handle_info({:check_presence, file_path, user_id}, state) do
    # Remove stale presence entries
    case get_in(state.presence, [file_path, user_id]) do
      nil ->
        {:noreply, state}
        
      presence_info ->
        age = DateTime.diff(DateTime.utc_now(), presence_info.joined_at, :millisecond)
        
        if age > @presence_timeout do
          # Remove stale presence
          new_presence = update_in(state.presence, [file_path], &Map.delete(&1 || %{}, user_id))
          
          # Clean up empty file entries
          new_presence = if map_size(new_presence[file_path] || %{}) == 0 do
            Map.delete(new_presence, file_path)
          else
            new_presence
          end
          
          # Broadcast presence left
          PubSub.broadcast(
            RubberDuck.PubSub,
            file_topic(state.project_id, file_path),
            {:presence_left, %{user_id: user_id, file_path: file_path}}
          )
          
          {:noreply, %{state | presence: new_presence}}
        else
          {:noreply, state}
        end
    end
  end
  
  # Private functions
  
  defp name(project_id) do
    {:via, Registry, {RubberDuck.CollaborationRegistry, project_id}}
  end
  
  defp file_topic(project_id, file_path) do
    "collaboration:#{project_id}:file:#{file_path}"
  end
  
  defp project_topic(project_id) do
    "collaboration:#{project_id}:project"
  end
  
  defp check_lock_compatibility(locks, file_path, lock_type, user_id) do
    case Map.get(locks, file_path) do
      nil ->
        :ok
        
      %{type: :shared, user_id: ^user_id} when lock_type == :shared ->
        # Same user can have multiple shared locks
        :ok
        
      %{type: :shared} when lock_type == :shared ->
        # Multiple users can have shared locks
        :ok
        
      %{user_id: ^user_id} ->
        # Same user already has a lock
        {:error, :already_locked_by_user}
        
      _ ->
        {:error, :locked}
    end
  end
  
  defp generate_lock_id do
    "lock_#{:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)}"
  end
  
  defp broadcast_lock_event(project_id, file_path, event_type, lock) do
    event = %{
      type: event_type,
      lock: lock,
      timestamp: DateTime.utc_now()
    }
    
    PubSub.broadcast(
      RubberDuck.PubSub,
      file_topic(project_id, file_path),
      {:lock_event, event}
    )
  end
end