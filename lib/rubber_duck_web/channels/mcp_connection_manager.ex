defmodule RubberDuckWeb.MCPConnectionManager do
  @moduledoc """
  Connection state management and recovery for MCP channels.

  Handles:
  - Connection state persistence
  - Session recovery after disconnection
  - Message replay for missed messages
  - Connection health monitoring
  """

  use GenServer

  require Logger

  @type connection_state :: %{
          session_id: String.t(),
          user_id: String.t(),
          client_info: map(),
          connected_at: DateTime.t(),
          last_activity: DateTime.t(),
          message_queue: [map()],
          subscriptions: MapSet.t(),
          capabilities: map(),
          recovery_token: String.t() | nil
        }

  @table_name :mcp_connections
  # 5 minutes
  @recovery_window_seconds 300

  # Client API

  @doc """
  Starts the connection manager.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Stores connection state for recovery.
  """
  @spec store_connection_state(String.t(), connection_state()) :: :ok
  def store_connection_state(session_id, state) do
    GenServer.call(__MODULE__, {:store_connection_state, session_id, state})
  end

  @doc """
  Retrieves connection state for recovery.
  """
  @spec get_connection_state(String.t()) :: {:ok, connection_state()} | {:error, term()}
  def get_connection_state(session_id) do
    GenServer.call(__MODULE__, {:get_connection_state, session_id})
  end

  @doc """
  Updates connection activity timestamp.
  """
  @spec update_activity(String.t()) :: :ok
  def update_activity(session_id) do
    GenServer.cast(__MODULE__, {:update_activity, session_id})
  end

  @doc """
  Queues a message for potential replay.
  """
  @spec queue_message(String.t(), map()) :: :ok
  def queue_message(session_id, message) do
    GenServer.cast(__MODULE__, {:queue_message, session_id, message})
  end

  @doc """
  Gets queued messages for replay.
  """
  @spec get_queued_messages(String.t(), DateTime.t()) :: [map()]
  def get_queued_messages(session_id, since) do
    GenServer.call(__MODULE__, {:get_queued_messages, session_id, since})
  end

  @doc """
  Removes connection state (called on clean disconnect).
  """
  @spec remove_connection_state(String.t()) :: :ok
  def remove_connection_state(session_id) do
    GenServer.cast(__MODULE__, {:remove_connection_state, session_id})
  end

  @doc """
  Generates a recovery token for reconnection.
  """
  @spec generate_recovery_token(String.t()) :: String.t()
  def generate_recovery_token(session_id) do
    token_data = %{
      session_id: session_id,
      generated_at: DateTime.utc_now(),
      expires_at: DateTime.add(DateTime.utc_now(), @recovery_window_seconds, :second)
    }

    Phoenix.Token.sign(RubberDuckWeb.Endpoint, "mcp_recovery", token_data)
  end

  @doc """
  Verifies a recovery token and returns session information.
  """
  @spec verify_recovery_token(String.t()) :: {:ok, String.t()} | {:error, term()}
  def verify_recovery_token(token) do
    case Phoenix.Token.verify(RubberDuckWeb.Endpoint, "mcp_recovery", token, max_age: @recovery_window_seconds) do
      {:ok, %{session_id: session_id, expires_at: expires_at}} ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:ok, session_id}
        else
          {:error, :expired}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Attempts to recover a session from a recovery token.
  """
  @spec recover_session(String.t()) :: {:ok, connection_state()} | {:error, term()}
  def recover_session(recovery_token) do
    case verify_recovery_token(recovery_token) do
      {:ok, session_id} ->
        get_connection_state(session_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists all active connections.
  """
  @spec list_active_connections() :: [connection_state()]
  def list_active_connections do
    GenServer.call(__MODULE__, :list_active_connections)
  end

  @doc """
  Cleans up expired connections.
  """
  @spec cleanup_expired_connections() :: integer()
  def cleanup_expired_connections do
    GenServer.call(__MODULE__, :cleanup_expired_connections)
  end

  # Server implementation

  @impl GenServer
  def init(opts) do
    # Create ETS table for connection state
    table = :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])

    # Schedule periodic cleanup
    # 1 minute
    cleanup_interval = Keyword.get(opts, :cleanup_interval, 60_000)
    schedule_cleanup(cleanup_interval)

    state = %{
      table: table,
      cleanup_interval: cleanup_interval
    }

    Logger.info("MCP Connection Manager started")
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:store_connection_state, session_id, connection_state}, _from, state) do
    # Add recovery token to state
    enhanced_state = Map.put(connection_state, :recovery_token, generate_recovery_token(session_id))

    # Store in ETS
    :ets.insert(state.table, {session_id, enhanced_state})

    Logger.debug("Stored connection state for session: #{session_id}")
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:get_connection_state, session_id}, _from, state) do
    case :ets.lookup(state.table, session_id) do
      [{^session_id, connection_state}] ->
        {:reply, {:ok, connection_state}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl GenServer
  def handle_call({:get_queued_messages, session_id, since}, _from, state) do
    case :ets.lookup(state.table, session_id) do
      [{^session_id, connection_state}] ->
        # Filter messages by timestamp
        messages =
          connection_state.message_queue
          |> Enum.filter(fn msg ->
            case msg do
              %{timestamp: timestamp} ->
                DateTime.compare(timestamp, since) == :gt

              _ ->
                false
            end
          end)

        {:reply, messages, state}

      [] ->
        {:reply, [], state}
    end
  end

  @impl GenServer
  def handle_call(:list_active_connections, _from, state) do
    connections =
      :ets.tab2list(state.table)
      |> Enum.map(fn {_session_id, connection_state} -> connection_state end)

    {:reply, connections, state}
  end

  @impl GenServer
  def handle_call(:cleanup_expired_connections, _from, state) do
    current_time = DateTime.utc_now()
    expiry_threshold = DateTime.add(current_time, -@recovery_window_seconds, :second)

    # Find expired connections
    expired_sessions =
      :ets.tab2list(state.table)
      |> Enum.filter(fn {_session_id, connection_state} ->
        DateTime.compare(connection_state.last_activity, expiry_threshold) == :lt
      end)
      |> Enum.map(fn {session_id, _connection_state} -> session_id end)

    # Remove expired connections
    Enum.each(expired_sessions, fn session_id ->
      :ets.delete(state.table, session_id)
    end)

    count = length(expired_sessions)

    if count > 0 do
      Logger.info("Cleaned up #{count} expired MCP connections")
    end

    {:reply, count, state}
  end

  @impl GenServer
  def handle_cast({:update_activity, session_id}, state) do
    case :ets.lookup(state.table, session_id) do
      [{^session_id, connection_state}] ->
        updated_state = %{connection_state | last_activity: DateTime.utc_now()}
        :ets.insert(state.table, {session_id, updated_state})

      [] ->
        Logger.warning("Attempted to update activity for non-existent session: #{session_id}")
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:queue_message, session_id, message}, state) do
    case :ets.lookup(state.table, session_id) do
      [{^session_id, connection_state}] ->
        # Add timestamp to message
        timestamped_message = Map.put(message, :timestamp, DateTime.utc_now())

        # Add to message queue (keep last 100 messages)
        updated_queue =
          [timestamped_message | connection_state.message_queue]
          |> Enum.take(100)

        updated_state = %{connection_state | message_queue: updated_queue, last_activity: DateTime.utc_now()}

        :ets.insert(state.table, {session_id, updated_state})

      [] ->
        Logger.warning("Attempted to queue message for non-existent session: #{session_id}")
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:remove_connection_state, session_id}, state) do
    :ets.delete(state.table, session_id)
    Logger.debug("Removed connection state for session: #{session_id}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    cleanup_expired_connections()
    schedule_cleanup(state.cleanup_interval)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
  end
end
