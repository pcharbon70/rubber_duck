defmodule RubberDuck.Interface.CLI.SessionManager do
  @moduledoc """
  Manages CLI sessions for maintaining conversation context and history.
  
  This module handles session creation, persistence, restoration, and management
  for the CLI interface. It integrates with the distributed session system while
  providing CLI-specific session handling capabilities.
  
  ## Features
  
  - Session creation and management
  - Local session persistence
  - Distributed session coordination
  - Session history tracking
  - Context preservation across CLI invocations
  - Session metadata management
  
  ## Session Storage
  
  Sessions are stored locally in `~/.rubber_duck/sessions/` and synchronized
  with the distributed Mnesia cluster when available.
  """

  use GenServer

  require Logger

  @type session_id :: String.t()
  @type session :: %{
    id: session_id(),
    name: String.t() | nil,
    created_at: DateTime.t(),
    updated_at: DateTime.t(),
    metadata: map(),
    history: [map()],
    context: map()
  }
  @type session_state :: %{
    sessions: %{session_id() => session()},
    current_session: session_id() | nil,
    storage_path: String.t(),
    auto_save: boolean(),
    max_history: integer()
  }

  # Default configuration
  @default_config %{
    storage_path: Path.expand("~/.rubber_duck/sessions"),
    auto_save: true,
    max_history: 1000,
    sync_interval: 30_000
  }

  @doc """
  Initialize the session manager with CLI configuration.
  """
  def init(config \\ %{}) do
    merged_config = Map.merge(@default_config, config)
    
    # Ensure storage directory exists
    File.mkdir_p!(merged_config.storage_path)
    
    # Load existing sessions
    sessions = load_sessions_from_disk(merged_config.storage_path)
    
    initial_state = %{
      sessions: sessions,
      current_session: nil,
      storage_path: merged_config.storage_path,
      auto_save: merged_config.auto_save,
      max_history: merged_config.max_history
    }
    
    {:ok, initial_state}
  end

  @doc """
  Start the session manager as a GenServer.
  """
  def start_link(config \\ %{}) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Create a new session with optional name.
  """
  def create_session(name \\ nil, context \\ %{}, state_or_pid \\ __MODULE__)

  def create_session(name, context, pid) when is_pid(pid) do
    GenServer.call(pid, {:create_session, name, context})
  end

  def create_session(name, context, state) when is_map(state) do
    session_id = generate_session_id()
    
    session = %{
      id: session_id,
      name: name,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      metadata: extract_session_metadata(context),
      history: [],
      context: context
    }
    
    new_sessions = Map.put(state.sessions, session_id, session)
    new_state = %{state | sessions: new_sessions}
    
    # Save to disk if auto_save enabled
    if state.auto_save do
      save_session_to_disk(session, state.storage_path)
    end
    
    {:ok, session, new_state}
  end

  @doc """
  Get an existing session by ID.
  """
  def get_session(session_id, state_or_pid \\ __MODULE__)

  def get_session(session_id, pid) when is_pid(pid) do
    GenServer.call(pid, {:get_session, session_id})
  end

  def get_session(session_id, state) when is_map(state) do
    case Map.get(state.sessions, session_id) do
      nil -> {:error, :not_found}
      session -> {:ok, session}
    end
  end

  @doc """
  List all available sessions.
  """
  def list_sessions(state_or_pid \\ __MODULE__)

  def list_sessions(pid) when is_pid(pid) do
    GenServer.call(pid, :list_sessions)
  end

  def list_sessions(state) when is_map(state) do
    sessions = Map.values(state.sessions)
    |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
    
    sessions
  end

  @doc """
  Update session with new context or history.
  """
  def update_session(session_id, updates, state_or_pid \\ __MODULE__)

  def update_session(session_id, updates, pid) when is_pid(pid) do
    GenServer.call(pid, {:update_session, session_id, updates})
  end

  def update_session(session_id, updates, state) when is_map(state) do
    case Map.get(state.sessions, session_id) do
      nil -> 
        {:error, :not_found}
      
      session ->
        updated_session = session
        |> Map.merge(updates)
        |> Map.put(:updated_at, DateTime.utc_now())
        
        new_sessions = Map.put(state.sessions, session_id, updated_session)
        new_state = %{state | sessions: new_sessions}
        
        # Save to disk if auto_save enabled
        if state.auto_save do
          save_session_to_disk(updated_session, state.storage_path)
        end
        
        {:ok, updated_session, new_state}
    end
  end

  @doc """
  Add a message to session history.
  """
  def add_to_history(session_id, message, state_or_pid \\ __MODULE__)

  def add_to_history(session_id, message, pid) when is_pid(pid) do
    GenServer.call(pid, {:add_to_history, session_id, message})
  end

  def add_to_history(session_id, message, state) when is_map(state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:error, :not_found}
        
      session ->
        # Create history entry
        history_entry = %{
          timestamp: DateTime.utc_now(),
          type: Map.get(message, :type, :message),
          content: message,
          id: generate_message_id()
        }
        
        # Add to history (limit to max_history)
        new_history = [history_entry | session.history]
        |> Enum.take(state.max_history)
        
        updates = %{
          history: new_history,
          updated_at: DateTime.utc_now()
        }
        
        update_session(session_id, updates, state)
    end
  end

  @doc """
  Delete a session.
  """
  def delete_session(session_id, state_or_pid \\ __MODULE__)

  def delete_session(session_id, pid) when is_pid(pid) do
    GenServer.call(pid, {:delete_session, session_id})
  end

  def delete_session(session_id, state) when is_map(state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:error, :not_found}
        
      _session ->
        # Remove from memory
        new_sessions = Map.delete(state.sessions, session_id)
        new_state = %{state | sessions: new_sessions}
        
        # Remove from disk
        delete_session_from_disk(session_id, state.storage_path)
        
        {:ok, new_state}
    end
  end

  @doc """
  Save a specific session to persistent storage.
  """
  def save_session(session_or_id, state_or_pid \\ __MODULE__)

  def save_session(session_id, pid) when is_binary(session_id) and is_pid(pid) do
    GenServer.call(pid, {:save_session, session_id})
  end

  def save_session(session, state) when is_map(session) and is_map(state) do
    save_session_to_disk(session, state.storage_path)
    :ok
  end

  @doc """
  Load sessions from distributed storage (Mnesia) if available.
  """
  def sync_with_distributed_storage(state_or_pid \\ __MODULE__)

  def sync_with_distributed_storage(pid) when is_pid(pid) do
    GenServer.call(pid, :sync_with_distributed_storage)
  end

  def sync_with_distributed_storage(state) when is_map(state) do
    # This would integrate with the distributed session system
    # For now, we'll just return the current state
    {:ok, state}
  end

  @doc """
  Get session statistics and metadata.
  """
  def get_session_stats(state_or_pid \\ __MODULE__)

  def get_session_stats(pid) when is_pid(pid) do
    GenServer.call(pid, :get_session_stats)
  end

  def get_session_stats(state) when is_map(state) do
    sessions = Map.values(state.sessions)
    
    stats = %{
      total_sessions: length(sessions),
      active_sessions: count_active_sessions(sessions),
      oldest_session: get_oldest_session(sessions),
      newest_session: get_newest_session(sessions),
      total_history_entries: count_total_history(sessions),
      storage_path: state.storage_path
    }
    
    stats
  end

  # GenServer callbacks

  def init(config) do
    case init(config) do
      {:ok, state} -> {:ok, state}
      error -> error
    end
  end

  def handle_call({:create_session, name, context}, _from, state) do
    case create_session(name, context, state) do
      {:ok, session, new_state} -> {:reply, {:ok, session, new_state}, new_state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:get_session, session_id}, _from, state) do
    result = get_session(session_id, state)
    {:reply, result, state}
  end

  def handle_call(:list_sessions, _from, state) do
    sessions = list_sessions(state)
    {:reply, sessions, state}
  end

  def handle_call({:update_session, session_id, updates}, _from, state) do
    case update_session(session_id, updates, state) do
      {:ok, session, new_state} -> {:reply, {:ok, session}, new_state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:add_to_history, session_id, message}, _from, state) do
    case add_to_history(session_id, message, state) do
      {:ok, session, new_state} -> {:reply, {:ok, session}, new_state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:delete_session, session_id}, _from, state) do
    case delete_session(session_id, state) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:save_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil -> {:reply, {:error, :not_found}, state}
      session -> 
        result = save_session(session, state)
        {:reply, result, state}
    end
  end

  def handle_call(:sync_with_distributed_storage, _from, state) do
    case sync_with_distributed_storage(state) do
      {:ok, new_state} -> {:reply, :ok, new_state}
      error -> {:reply, error, state}
    end
  end

  def handle_call(:get_session_stats, _from, state) do
    stats = get_session_stats(state)
    {:reply, stats, state}
  end

  # Private helper functions

  defp generate_session_id do
    timestamp = System.system_time(:millisecond)
    random = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "session_#{timestamp}_#{random}"
  end

  defp generate_message_id do
    timestamp = System.system_time(:microsecond)
    random = :crypto.strong_rand_bytes(2) |> Base.encode16(case: :lower)
    "msg_#{timestamp}_#{random}"
  end

  defp extract_session_metadata(context) do
    %{
      interface: :cli,
      created_by: System.get_env("USER") || "unknown",
      node: Node.self(),
      pid: self(),
      initial_context: Map.take(context, [:user_id, :workspace, :project])
    }
  end

  defp load_sessions_from_disk(storage_path) do
    sessions_pattern = Path.join(storage_path, "*.json")
    
    sessions_pattern
    |> Path.wildcard()
    |> Enum.reduce(%{}, fn file_path, acc ->
      case load_session_file(file_path) do
        {:ok, session} -> Map.put(acc, session.id, session)
        {:error, reason} -> 
          Logger.warning("Failed to load session from #{file_path}: #{reason}")
          acc
      end
    end)
  end

  defp load_session_file(file_path) do
    with {:ok, content} <- File.read(file_path),
         {:ok, session_data} <- Jason.decode(content),
         {:ok, session} <- parse_session_data(session_data) do
      {:ok, session}
    else
      error -> error
    end
  end

  defp parse_session_data(data) when is_map(data) do
    try do
      session = %{
        id: data["id"],
        name: data["name"],
        created_at: parse_datetime(data["created_at"]),
        updated_at: parse_datetime(data["updated_at"]),
        metadata: data["metadata"] || %{},
        history: data["history"] || [],
        context: data["context"] || %{}
      }
      {:ok, session}
    rescue
      error -> {:error, "Parse error: #{Exception.message(error)}"}
    end
  end

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    case DateTime.from_iso8601(datetime_string) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> DateTime.utc_now()
    end
  end
  defp parse_datetime(_), do: DateTime.utc_now()

  defp save_session_to_disk(session, storage_path) do
    session_data = %{
      "id" => session.id,
      "name" => session.name,
      "created_at" => DateTime.to_iso8601(session.created_at),
      "updated_at" => DateTime.to_iso8601(session.updated_at),
      "metadata" => session.metadata,
      "history" => session.history,
      "context" => session.context
    }
    
    file_path = Path.join(storage_path, "#{session.id}.json")
    
    case Jason.encode(session_data, pretty: true) do
      {:ok, json} -> File.write(file_path, json)
      error -> error
    end
  end

  defp delete_session_from_disk(session_id, storage_path) do
    file_path = Path.join(storage_path, "#{session_id}.json")
    
    if File.exists?(file_path) do
      File.rm(file_path)
    else
      :ok
    end
  end

  defp count_active_sessions(sessions) do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-24, :hour)
    
    Enum.count(sessions, fn session ->
      DateTime.compare(session.updated_at, cutoff_time) == :gt
    end)
  end

  defp get_oldest_session([]), do: nil
  defp get_oldest_session(sessions) do
    Enum.min_by(sessions, & &1.created_at, DateTime)
  end

  defp get_newest_session([]), do: nil
  defp get_newest_session(sessions) do
    Enum.max_by(sessions, & &1.created_at, DateTime)
  end

  defp count_total_history(sessions) do
    Enum.reduce(sessions, 0, fn session, acc ->
      acc + length(session.history)
    end)
  end
end