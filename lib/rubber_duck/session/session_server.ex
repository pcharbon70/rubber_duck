defmodule RubberDuck.Session.SessionServer do
  @moduledoc """
  GenServer implementation for session management in the distributed cluster.
  Handles session state, lifecycle, and recovery for AI assistant sessions.
  """
  use GenServer
  require Logger

  defstruct [
    :session_id,
    :state,
    :config,
    :created_at,
    :last_activity,
    :metadata
  ]

  def start_link(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(session_id))
  end

  @doc """
  Gets the current session state.
  """
  def get_state(session_id) do
    GenServer.call(via_tuple(session_id), :get_state)
  end

  @doc """
  Updates the session state.
  """
  def update_state(session_id, new_state) do
    GenServer.call(via_tuple(session_id), {:update_state, new_state})
  end

  @doc """
  Restores session state (used for migration/recovery).
  """
  def restore_state(session_id, state) do
    GenServer.call(via_tuple(session_id), {:restore_state, state})
  end

  @doc """
  Health check for the session.
  """
  def health_check(session_id) do
    GenServer.call(via_tuple(session_id), :health_check)
  end

  @impl true
  def init(opts) do
    session_id = Keyword.fetch!(opts, :session_id)
    config = Keyword.get(opts, :config, %{})
    
    state = %__MODULE__{
      session_id: session_id,
      state: %{},
      config: config,
      created_at: System.monotonic_time(:millisecond),
      last_activity: System.monotonic_time(:millisecond),
      metadata: %{}
    }
    
    Logger.debug("Initialized session server for #{session_id}")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    updated_state = update_activity(state)
    {:reply, updated_state.state, updated_state}
  end

  @impl true
  def handle_call({:update_state, new_state}, _from, state) do
    updated_state = %{state | 
      state: new_state,
      last_activity: System.monotonic_time(:millisecond)
    }
    
    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call({:restore_state, restored_state}, _from, state) do
    updated_state = %{state |
      state: restored_state,
      last_activity: System.monotonic_time(:millisecond),
      metadata: Map.put(state.metadata, :restored_at, System.monotonic_time(:millisecond))
    }
    
    Logger.info("Restored state for session #{state.session_id}")
    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    updated_state = update_activity(state)
    {:reply, :ok, updated_state}
  end

  # Private functions

  defp via_tuple(session_id) do
    {:via, Registry, {RubberDuck.Registry, {:session, session_id}}}
  end

  defp update_activity(state) do
    %{state | last_activity: System.monotonic_time(:millisecond)}
  end
end