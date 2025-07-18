defmodule RubberDuck.MCP.SessionManager do
  @moduledoc """
  Session management for MCP protocol connections.
  
  Handles session lifecycle including:
  - Session creation and validation
  - Token generation and refresh
  - Session timeout and expiry
  - Concurrent session limits
  - Session metadata tracking
  
  ## Features
  
  - Secure token generation with Phoenix.Token
  - Configurable session timeouts
  - Session activity tracking
  - Multi-session support per user
  - Session revocation
  """
  
  use GenServer
  
  require Logger
  
  @type session_id :: String.t()
  @type token :: String.t()
  @type session :: %{
    id: session_id(),
    user_id: String.t(),
    token: token(),
    created_at: DateTime.t(),
    last_activity: DateTime.t(),
    expires_at: DateTime.t(),
    ip_address: String.t() | nil,
    user_agent: String.t() | nil,
    metadata: map()
  }
  
  # Default configuration
  @default_config %{
    session_timeout: 3600,  # 1 hour in seconds
    max_sessions_per_user: 5,
    enable_refresh: true,
    refresh_window: 300,  # 5 minutes before expiry
    cleanup_interval: 60_000,  # 1 minute
    token_salt: "mcp_session"
  }
  
  # Client API
  
  @doc """
  Starts the session manager.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Creates a new session.
  """
  @spec create_session(map()) :: {:ok, session()} | {:error, term()}
  def create_session(session_data) do
    GenServer.call(__MODULE__, {:create_session, session_data})
  end
  
  @doc """
  Validates a session token.
  """
  @spec validate_token(token()) :: {:ok, session()} | {:error, term()}
  def validate_token(token) do
    GenServer.call(__MODULE__, {:validate_token, token})
  end
  
  @doc """
  Refreshes a session token.
  """
  @spec refresh_token(token()) :: {:ok, token()} | {:error, term()}
  def refresh_token(token) do
    GenServer.call(__MODULE__, {:refresh_token, token})
  end
  
  @doc """
  Updates session activity timestamp.
  """
  @spec touch_session(session_id()) :: :ok | {:error, :not_found}
  def touch_session(session_id) do
    GenServer.call(__MODULE__, {:touch_session, session_id})
  end
  
  @doc """
  Revokes a session.
  """
  @spec revoke_session(session_id()) :: :ok
  def revoke_session(session_id) do
    GenServer.call(__MODULE__, {:revoke_session, session_id})
  end
  
  @doc """
  Revokes a token.
  """
  @spec revoke_token(token()) :: :ok
  def revoke_token(token) do
    GenServer.call(__MODULE__, {:revoke_token, token})
  end
  
  @doc """
  Lists all sessions for a user.
  """
  @spec list_user_sessions(String.t()) :: [session()]
  def list_user_sessions(user_id) do
    GenServer.call(__MODULE__, {:list_user_sessions, user_id})
  end
  
  @doc """
  Revokes all sessions for a user.
  """
  @spec revoke_all_user_sessions(String.t()) :: {:ok, non_neg_integer()}
  def revoke_all_user_sessions(user_id) do
    GenServer.call(__MODULE__, {:revoke_all_user_sessions, user_id})
  end
  
  @doc """
  Gets session statistics.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Updates configuration.
  """
  @spec update_config(map()) :: :ok
  def update_config(config) do
    GenServer.call(__MODULE__, {:update_config, config})
  end
  
  # Server implementation
  
  @impl GenServer
  def init(opts) do
    # Create ETS tables
    :ets.new(:mcp_sessions, [:set, :public, :named_table])
    :ets.new(:mcp_session_tokens, [:set, :public, :named_table])
    :ets.new(:mcp_user_sessions, [:bag, :public, :named_table])
    :ets.new(:mcp_revoked_tokens, [:set, :public, :named_table])
    
    # Load configuration
    config = load_config(opts)
    
    # Schedule cleanup
    schedule_cleanup(config.cleanup_interval)
    
    state = %{
      config: config,
      stats: %{
        sessions_created: 0,
        sessions_validated: 0,
        sessions_refreshed: 0,
        sessions_expired: 0,
        sessions_revoked: 0
      }
    }
    
    Logger.info("MCP Session Manager started")
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:create_session, session_data}, _from, state) do
    user_id = Map.fetch!(session_data, :user_id)
    
    # Check session limit
    case check_session_limit(user_id, state.config) do
      :ok ->
        session = build_session(session_data, state.config)
        
        # Store session
        :ets.insert(:mcp_sessions, {session.id, session})
        :ets.insert(:mcp_session_tokens, {session.token, session.id})
        :ets.insert(:mcp_user_sessions, {user_id, session.id})
        
        new_state = update_in(state.stats.sessions_created, &(&1 + 1))
        
        Logger.info("Created session #{session.id} for user #{user_id}")
        {:reply, {:ok, session}, new_state}
        
      {:error, reason} = error ->
        {:reply, error, state}
    end
  end
  
  @impl GenServer
  def handle_call({:validate_token, token}, _from, state) do
    # Check if token is revoked
    if token_revoked?(token) do
      {:reply, {:error, "Token revoked"}, state}
    else
      # Verify token signature
      case Phoenix.Token.verify(RubberDuckWeb.Endpoint, state.config.token_salt, token, max_age: :infinity) do
        {:ok, session_id} ->
          case get_session(session_id) do
            {:ok, session} ->
              if DateTime.compare(DateTime.utc_now(), session.expires_at) == :lt do
                new_state = update_in(state.stats.sessions_validated, &(&1 + 1))
                {:reply, {:ok, session}, new_state}
              else
                {:reply, {:error, "Session expired"}, state}
              end
              
            :error ->
              {:reply, {:error, "Session not found"}, state}
          end
          
        {:error, reason} ->
          {:reply, {:error, "Invalid token: #{reason}"}, state}
      end
    end
  end
  
  @impl GenServer
  def handle_call({:refresh_token, old_token}, _from, state) do
    case validate_token(old_token) do
      {:ok, session} ->
        # Check if within refresh window
        now = DateTime.utc_now()
        time_until_expiry = DateTime.diff(session.expires_at, now)
        
        if state.config.enable_refresh and time_until_expiry <= state.config.refresh_window do
          # Generate new token
          new_token = generate_token(session.id, state.config)
          new_expires_at = DateTime.add(now, state.config.session_timeout, :second)
          
          # Update session
          updated_session = %{session | 
            token: new_token,
            expires_at: new_expires_at,
            last_activity: now
          }
          
          # Update storage
          :ets.insert(:mcp_sessions, {session.id, updated_session})
          :ets.delete(:mcp_session_tokens, old_token)
          :ets.insert(:mcp_session_tokens, {new_token, session.id})
          
          # Revoke old token
          revoke_token_internal(old_token)
          
          new_state = update_in(state.stats.sessions_refreshed, &(&1 + 1))
          
          Logger.info("Refreshed token for session #{session.id}")
          {:reply, {:ok, new_token}, new_state}
        else
          {:reply, {:error, "Token not eligible for refresh"}, state}
        end
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:touch_session, session_id}, _from, state) do
    case get_session(session_id) do
      {:ok, session} ->
        updated_session = %{session | last_activity: DateTime.utc_now()}
        :ets.insert(:mcp_sessions, {session_id, updated_session})
        {:reply, :ok, state}
        
      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:revoke_session, session_id}, _from, state) do
    case get_session(session_id) do
      {:ok, session} ->
        # Remove session
        :ets.delete(:mcp_sessions, session_id)
        :ets.delete(:mcp_session_tokens, session.token)
        :ets.delete_object(:mcp_user_sessions, {session.user_id, session_id})
        
        # Revoke token
        revoke_token_internal(session.token)
        
        new_state = update_in(state.stats.sessions_revoked, &(&1 + 1))
        
        Logger.info("Revoked session #{session_id}")
        {:reply, :ok, new_state}
        
      :error ->
        {:reply, :ok, state}
    end
  end
  
  @impl GenServer
  def handle_call({:revoke_token, token}, _from, state) do
    # Mark token as revoked
    revoke_token_internal(token)
    
    # Remove associated session if exists
    case :ets.lookup(:mcp_session_tokens, token) do
      [{^token, session_id}] ->
        revoke_session(session_id)
      [] ->
        :ok
    end
    
    {:reply, :ok, state}
  end
  
  @impl GenServer
  def handle_call({:list_user_sessions, user_id}, _from, state) do
    session_ids = :ets.lookup(:mcp_user_sessions, user_id)
    |> Enum.map(fn {_, sid} -> sid end)
    
    sessions = Enum.reduce(session_ids, [], fn sid, acc ->
      case get_session(sid) do
        {:ok, session} -> [session | acc]
        :error -> acc
      end
    end)
    |> Enum.sort_by(& &1.created_at, {:desc, DateTime})
    
    {:reply, sessions, state}
  end
  
  @impl GenServer
  def handle_call({:revoke_all_user_sessions, user_id}, _from, state) do
    sessions = list_user_sessions(user_id)
    
    Enum.each(sessions, fn session ->
      revoke_session(session.id)
    end)
    
    {:reply, {:ok, length(sessions)}, state}
  end
  
  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    stats = Map.merge(state.stats, %{
      active_sessions: :ets.info(:mcp_sessions, :size),
      revoked_tokens: :ets.info(:mcp_revoked_tokens, :size),
      unique_users: count_unique_users()
    })
    
    {:reply, stats, state}
  end
  
  @impl GenServer
  def handle_call({:update_config, config}, _from, state) do
    new_config = Map.merge(state.config, config)
    {:reply, :ok, %{state | config: new_config}}
  end
  
  @impl GenServer
  def handle_info(:cleanup, state) do
    # Remove expired sessions
    now = DateTime.utc_now()
    
    expired_sessions = :ets.select(:mcp_sessions, [
      {
        {:"$1", %{expires_at: :"$2"}},
        [{:"<", :"$2", now}],
        [:"$_"]
      }
    ])
    
    expired_count = Enum.reduce(expired_sessions, 0, fn {session_id, session}, count ->
      # Clean up session data
      :ets.delete(:mcp_sessions, session_id)
      :ets.delete(:mcp_session_tokens, session.token)
      :ets.delete_object(:mcp_user_sessions, {session.user_id, session_id})
      
      count + 1
    end)
    
    if expired_count > 0 do
      Logger.info("Cleaned up #{expired_count} expired sessions")
    end
    
    # Clean up old revoked tokens (older than session timeout)
    token_cutoff = System.monotonic_time(:second) - state.config.session_timeout
    :ets.select_delete(:mcp_revoked_tokens, [
      {
        {:_, :"$1"},
        [{:"<", :"$1", token_cutoff}],
        [true]
      }
    ])
    
    new_state = update_in(state.stats.sessions_expired, &(&1 + expired_count))
    
    # Schedule next cleanup
    schedule_cleanup(state.config.cleanup_interval)
    
    {:noreply, new_state}
  end
  
  # Private functions
  
  defp load_config(opts) do
    config = Keyword.get(opts, :config, %{})
    Map.merge(@default_config, config)
  end
  
  defp check_session_limit(user_id, config) do
    current_sessions = :ets.lookup(:mcp_user_sessions, user_id)
    |> length()
    
    if current_sessions >= config.max_sessions_per_user do
      {:error, "Maximum sessions (#{config.max_sessions_per_user}) reached for user"}
    else
      :ok
    end
  end
  
  defp build_session(session_data, config) do
    session_id = generate_session_id()
    now = DateTime.utc_now()
    
    %{
      id: session_id,
      user_id: Map.fetch!(session_data, :user_id),
      token: generate_token(session_id, config),
      created_at: now,
      last_activity: now,
      expires_at: DateTime.add(now, config.session_timeout, :second),
      ip_address: Map.get(session_data, :ip_address),
      user_agent: Map.get(session_data, :user_agent),
      metadata: Map.get(session_data, :metadata, %{})
    }
  end
  
  defp generate_session_id do
    "mcp_session_" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end
  
  defp generate_token(session_id, config) do
    Phoenix.Token.sign(RubberDuckWeb.Endpoint, config.token_salt, session_id)
  end
  
  defp get_session(session_id) do
    case :ets.lookup(:mcp_sessions, session_id) do
      [{^session_id, session}] -> {:ok, session}
      [] -> :error
    end
  end
  
  defp token_revoked?(token) do
    case :ets.lookup(:mcp_revoked_tokens, token) do
      [{^token, _}] -> true
      [] -> false
    end
  end
  
  defp revoke_token_internal(token) do
    timestamp = System.monotonic_time(:second)
    :ets.insert(:mcp_revoked_tokens, {token, timestamp})
  end
  
  defp count_unique_users do
    :ets.tab2list(:mcp_user_sessions)
    |> Enum.map(fn {user_id, _} -> user_id end)
    |> Enum.uniq()
    |> length()
  end
  
  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup, interval)
  end
end