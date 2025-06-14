defmodule RubberDuck.ContextManager do
  @moduledoc """
  Manages AI conversation context and session state using distributed Mnesia storage.
  
  This GenServer maintains session-based contexts including messages,
  metadata, and other relevant state for AI interactions across cluster nodes.
  """
  use GenServer
  
  alias RubberDuck.{TransactionWrapper, StateSynchronizer}

  # Client API

  @doc """
  Starts the ContextManager GenServer.
  
  ## Options
    * `:name` - Register the process with a specific name
    * `:initial_state` - Provide initial state
  """
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    
    # Pass the name in init_arg for Registry registration
    init_arg = Keyword.put(opts, :registry_name, name)
    
    # Use via tuple for Registry-based naming when name is not the module
    server_opts = if name != __MODULE__ && name != nil do
      [name: {:via, Registry, {RubberDuck.Registry, name}}]
    else
      [name: name]
    end
    
    GenServer.start_link(__MODULE__, init_arg, server_opts)
  end

  @doc """
  Creates a new session with a unique ID.
  """
  def create_session(server \\ __MODULE__) do
    GenServer.call(server, :create_session)
  end

  @doc """
  Retrieves the context for a specific session.
  """
  def get_context(server \\ __MODULE__, session_id) do
    GenServer.call(server, {:get_context, session_id})
  end

  @doc """
  Adds a message to a session's context.
  """
  def add_message(server \\ __MODULE__, session_id, message) do
    GenServer.call(server, {:add_message, session_id, message})
  end

  @doc """
  Updates metadata for a session.
  """
  def update_metadata(server \\ __MODULE__, session_id, metadata) do
    GenServer.call(server, {:update_metadata, session_id, metadata})
  end

  @doc """
  Clears all messages from a session but keeps the session active.
  """
  def clear_session(server \\ __MODULE__, session_id) do
    GenServer.call(server, {:clear_session, session_id})
  end

  @doc """
  Deletes a session completely.
  """
  def delete_session(server \\ __MODULE__, session_id) do
    GenServer.call(server, {:delete_session, session_id})
  end

  @doc """
  Lists all active session IDs.
  """
  def list_sessions(server \\ __MODULE__) do
    GenServer.call(server, :list_sessions)
  end

  @doc """
  Performs a health check on the GenServer.
  """
  def health_check(server \\ __MODULE__) do
    GenServer.call(server, :health_check)
  end

  @doc """
  Gets information about the GenServer state.
  """
  def get_info(server \\ __MODULE__) do
    GenServer.call(server, :get_info)
  end

  @doc """
  Requests a model for a session from the ModelCoordinator.
  """
  def request_model(session_id, criteria \\ []) do
    request_model(__MODULE__, session_id, criteria)
  end
  
  def request_model(server, session_id, criteria) do
    GenServer.call(server, {:request_model, session_id, criteria})
  end

  @doc """
  Reports model usage statistics.
  """
  def report_model_usage(server \\ __MODULE__, session_id, status, latency) do
    GenServer.call(server, {:report_model_usage, session_id, status, latency})
  end

  @doc """
  Updates model health warning for sessions using a specific model.
  """
  def update_model_health_warning(server \\ __MODULE__, model_name, health_status, reason \\ nil) do
    GenServer.cast(server, {:update_model_health_warning, model_name, health_status, reason})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    # Subscribe to state changes for sessions table
    StateSynchronizer.subscribe_to_changes([:sessions])
    
    state = %{
      start_time: System.monotonic_time(:millisecond),
      local_cache: %{},
      node_id: node()
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call(:create_session, _from, state) do
    session_id = generate_session_id()
    session = %{
      session_id: session_id,
      messages: [],
      metadata: %{},
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      node: state.node_id
    }
    
    case TransactionWrapper.create_record(:sessions, session, metadata: %{operation: :create_session}) do
      {:ok, _} ->
        # Update local cache
        new_cache = Map.put(state.local_cache, session_id, session)
        {:reply, {:ok, session_id}, %{state | local_cache: new_cache}}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_context, session_id}, _from, state) do
    # Try local cache first
    case Map.get(state.local_cache, session_id) do
      nil ->
        # Fallback to Mnesia
        case TransactionWrapper.read_records(:sessions, {:id, session_id}) do
          {:ok, [session]} ->
            # Update local cache
            new_cache = Map.put(state.local_cache, session_id, session)
            {:reply, {:ok, session}, %{state | local_cache: new_cache}}
          {:ok, []} ->
            {:reply, {:error, :session_not_found}, state}
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      session ->
        {:reply, {:ok, session}, state}
    end
  end

  @impl true
  def handle_call({:add_message, session_id, message}, _from, state) do
    # Get current session
    case get_session_from_cache_or_db(session_id, state) do
      {:ok, session, updated_state} ->
        # Add message with timestamp
        timestamped_message = Map.put(message, :timestamp, DateTime.utc_now())
        updated_messages = session.messages ++ [timestamped_message]
        
        # Update session
        updates = %{
          messages: updated_messages,
          updated_at: DateTime.utc_now()
        }
        
        case TransactionWrapper.update_record(:sessions, session_id, updates, metadata: %{operation: :add_message}) do
          {:ok, updated_session} ->
            # Update local cache
            new_cache = Map.put(updated_state.local_cache, session_id, updated_session)
            {:reply, :ok, %{updated_state | local_cache: new_cache}}
          {:error, reason} ->
            {:reply, {:error, reason}, updated_state}
        end
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:update_metadata, session_id, metadata}, _from, state) do
    case get_session_from_cache_or_db(session_id, state) do
      {:ok, _session, updated_state} ->
        updates = %{
          metadata: metadata,
          updated_at: DateTime.utc_now()
        }
        
        case TransactionWrapper.update_record(:sessions, session_id, updates, metadata: %{operation: :update_metadata}) do
          {:ok, updated_session} ->
            # Update local cache
            new_cache = Map.put(updated_state.local_cache, session_id, updated_session)
            {:reply, :ok, %{updated_state | local_cache: new_cache}}
          {:error, reason} ->
            {:reply, {:error, reason}, updated_state}
        end
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:clear_session, session_id}, _from, state) do
    case get_session_from_cache_or_db(session_id, state) do
      {:ok, _session, updated_state} ->
        updates = %{
          messages: [],
          updated_at: DateTime.utc_now()
        }
        
        case TransactionWrapper.update_record(:sessions, session_id, updates, metadata: %{operation: :clear_session}) do
          {:ok, updated_session} ->
            # Update local cache
            new_cache = Map.put(updated_state.local_cache, session_id, updated_session)
            {:reply, :ok, %{updated_state | local_cache: new_cache}}
          {:error, reason} ->
            {:reply, {:error, reason}, updated_state}
        end
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:delete_session, session_id}, _from, state) do
    case TransactionWrapper.delete_record(:sessions, session_id, metadata: %{operation: :delete_session}) do
      {:ok, _} ->
        # Remove from local cache
        new_cache = Map.delete(state.local_cache, session_id)
        {:reply, :ok, %{state | local_cache: new_cache}}
      {:error, :not_found} ->
        {:reply, {:error, :session_not_found}, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:list_sessions, _from, state) do
    case TransactionWrapper.read_records(:sessions, :all) do
      {:ok, sessions} ->
        session_ids = Enum.map(sessions, fn session ->
          case session do
            %{session_id: id} -> id
            {_, id, _, _, _, _, _} -> id
            _ -> nil
          end
        end)
        |> Enum.filter(& &1 != nil)
        {:reply, session_ids, state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      status: :running,
      session_count: map_size(state.sessions),
      memory: :erlang.process_info(self(), :memory) |> elem(1),
      uptime: System.monotonic_time(:millisecond) - state.start_time
    }
    {:reply, info, state}
  end

  @impl true
  def handle_call({:request_model, session_id, criteria}, _from, state) do
    case get_session_from_cache_or_db(session_id, state) do
      {:ok, session, updated_state} ->
        # Request model from ModelCoordinator
        case RubberDuck.ModelCoordinator.select_model(RubberDuck.ModelCoordinator, criteria) do
          {:ok, model} ->
            # Store selected model in session metadata
            updated_metadata = Map.put(session.metadata, :selected_model, model.name)
            updates = %{
              metadata: updated_metadata,
              updated_at: DateTime.utc_now()
            }
            
            case TransactionWrapper.update_record(:sessions, session_id, updates, metadata: %{operation: :select_model}) do
              {:ok, updated_session} ->
                # Update local cache
                new_cache = Map.put(updated_state.local_cache, session_id, updated_session)
                {:reply, {:ok, model}, %{updated_state | local_cache: new_cache}}
              {:error, reason} ->
                {:reply, {:error, reason}, updated_state}
            end
          error ->
            {:reply, error, updated_state}
        end
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:report_model_usage, session_id, status, latency}, _from, state) do
    case get_session_from_cache_or_db(session_id, state) do
      {:ok, session, updated_state} ->
        case Map.get(session.metadata, :selected_model) do
          nil ->
            {:reply, {:error, :no_model_selected}, updated_state}
          model_name ->
            # Report usage to ModelCoordinator
            RubberDuck.ModelCoordinator.track_usage(model_name, status, latency)
            {:reply, :ok, updated_state}
        end
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:update_model_health_warning, model_name, health_status, reason}, state) do
    warning = case health_status do
      :unhealthy -> "Model #{model_name} is unhealthy: #{reason}"
      :healthy -> nil
    end
    
    # Find all sessions using this model and update them
    case TransactionWrapper.read_records(:sessions, :all) do
      {:ok, sessions} ->
        affected_sessions = Enum.filter(sessions, fn session ->
          case session do
            %{metadata: %{selected_model: ^model_name}} -> true
            _ -> false
          end
        end)
        
        # Update each affected session
        Enum.each(affected_sessions, fn session ->
          session_id = session.session_id
          updated_metadata = if warning do
            Map.put(session.metadata, :model_health_warning, warning)
          else
            Map.delete(session.metadata, :model_health_warning)
          end
          
          updates = %{
            metadata: updated_metadata,
            updated_at: DateTime.utc_now()
          }
          
          TransactionWrapper.update_record(:sessions, session_id, updates, 
            metadata: %{operation: :update_health_warning}, broadcast: false)
        end)
        
        # Clear local cache for affected sessions to force reload
        new_cache = Enum.reduce(affected_sessions, state.local_cache, fn session, cache ->
          Map.delete(cache, session.session_id)
        end)
        
        {:noreply, %{state | local_cache: new_cache}}
      
      {:error, _reason} ->
        # Fallback to no-op if we can't read sessions
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({"state_change:sessions", {:state_change, event}}, state) do
    # Handle remote state changes from other nodes
    case event do
      %{operation: operation, table: :sessions, record: %{session_id: session_id}} ->
        case operation do
          op when op in [:create, :update] ->
            # Invalidate local cache to force reload from Mnesia
            new_cache = Map.delete(state.local_cache, session_id)
            {:noreply, %{state | local_cache: new_cache}}
          :delete ->
            # Remove from local cache
            new_cache = Map.delete(state.local_cache, session_id)
            {:noreply, %{state | local_cache: new_cache}}
          _ ->
            {:noreply, state}
        end
      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, _state) do
    # Cleanup logic can be added here if needed
    :ok
  end

  # Private Functions

  defp get_session_from_cache_or_db(session_id, state) do
    case Map.get(state.local_cache, session_id) do
      nil ->
        # Not in cache, try Mnesia
        case TransactionWrapper.read_records(:sessions, {:id, session_id}) do
          {:ok, [session]} ->
            # Update local cache
            new_cache = Map.put(state.local_cache, session_id, session)
            {:ok, session, %{state | local_cache: new_cache}}
          {:ok, []} ->
            {:error, :session_not_found}
          {:error, reason} ->
            {:error, reason}
        end
      session ->
        # Found in cache
        {:ok, session, state}
    end
  end

  defp generate_session_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end
end