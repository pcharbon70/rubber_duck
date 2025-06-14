defmodule RubberDuck.ContextManager do
  @moduledoc """
  Manages AI conversation context and session state.
  
  This GenServer maintains session-based contexts including messages,
  metadata, and other relevant state for AI interactions.
  """
  use GenServer

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
    initial_state = Keyword.get(opts, :initial_state, %{})
    
    state = %{
      sessions: initial_state[:sessions] || %{},
      start_time: System.monotonic_time(:millisecond)
    }
    
    # No need to manually register when using via tuple
    
    {:ok, state}
  end

  @impl true
  def handle_call(:create_session, _from, state) do
    session_id = generate_session_id()
    session = %{
      session_id: session_id,
      messages: [],
      metadata: %{},
      created_at: DateTime.utc_now()
    }
    
    new_state = put_in(state, [:sessions, session_id], session)
    {:reply, {:ok, session_id}, new_state}
  end

  @impl true
  def handle_call({:get_context, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil -> 
        {:reply, {:error, :session_not_found}, state}
      session ->
        {:reply, {:ok, session}, state}
    end
  end

  @impl true
  def handle_call({:add_message, session_id, message}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil -> 
        {:reply, {:error, :session_not_found}, state}
      _session ->
        new_state = update_in(state, [:sessions, session_id, :messages], &(&1 ++ [message]))
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:update_metadata, session_id, metadata}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil -> 
        {:reply, {:error, :session_not_found}, state}
      _session ->
        new_state = put_in(state, [:sessions, session_id, :metadata], metadata)
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:clear_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil -> 
        {:reply, {:error, :session_not_found}, state}
      _session ->
        new_state = put_in(state, [:sessions, session_id, :messages], [])
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:delete_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil -> 
        {:reply, {:error, :session_not_found}, state}
      _session ->
        new_state = %{state | sessions: Map.delete(state.sessions, session_id)}
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:list_sessions, _from, state) do
    session_ids = Map.keys(state.sessions)
    {:reply, session_ids, state}
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
    case Map.get(state.sessions, session_id) do
      nil -> 
        {:reply, {:error, :session_not_found}, state}
      _session ->
        # Request model from ModelCoordinator
        case RubberDuck.ModelCoordinator.select_model(RubberDuck.ModelCoordinator, criteria) do
          {:ok, model} ->
            # Store selected model in session metadata
            new_state = update_in(state, [:sessions, session_id, :metadata], fn metadata ->
              Map.put(metadata, :selected_model, model.name)
            end)
            {:reply, {:ok, model}, new_state}
          error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:report_model_usage, session_id, status, latency}, _from, state) do
    case get_in(state, [:sessions, session_id, :metadata, :selected_model]) do
      nil ->
        {:reply, {:error, :no_model_selected}, state}
      model_name ->
        # Report usage to ModelCoordinator
        RubberDuck.ModelCoordinator.track_usage(model_name, status, latency)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_cast({:update_model_health_warning, model_name, health_status, reason}, state) do
    warning = case health_status do
      :unhealthy -> "Model #{model_name} is unhealthy: #{reason}"
      :healthy -> nil
    end
    
    # Update all sessions using this model
    new_state = %{state | 
      sessions: Map.new(state.sessions, fn {session_id, session} ->
        if get_in(session, [:metadata, :selected_model]) == model_name do
          updated_session = if warning do
            put_in(session, [:metadata, :model_health_warning], warning)
          else
            update_in(session, [:metadata], &Map.delete(&1, :model_health_warning))
          end
          {session_id, updated_session}
        else
          {session_id, session}
        end
      end)
    }
    
    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, _state) do
    # Cleanup logic can be added here if needed
    :ok
  end

  # Private Functions

  defp generate_session_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end
end