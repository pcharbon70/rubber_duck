defmodule RubberDuck.MCP.WebSocketTransport do
  @moduledoc """
  WebSocket transport implementation for MCP protocol.
  
  Implements the TransportBehaviour using Phoenix Channels for WebSocket
  communication. Provides real-time bi-directional messaging with connection
  management, authentication, and reliable message delivery.
  
  ## Features
  
  - Real-time bi-directional messaging
  - Connection state management
  - Authentication via tokens or API keys
  - Message queuing for reliability
  - Presence tracking
  - Heartbeat mechanism
  - Streaming support
  
  ## Usage
  
      # Initialize transport
      {:ok, config} = WebSocketTransport.init(
        endpoint: RubberDuckWeb.Endpoint,
        socket_path: "/socket"
      )
      
      # Start listener
      :ok = WebSocketTransport.start_listener(config)
      
      # Send message
      :ok = WebSocketTransport.send_message(connection_id, message)
  """
  
  @behaviour RubberDuck.MCP.TransportBehaviour
  
  alias RubberDuckWeb.{MCPAuth, MCPConnectionManager, MCPMessageQueue}
  alias RubberDuckWeb.Presence
  
  require Logger
  
  @type config :: %{
    endpoint: module(),
    socket_path: String.t(),
    channel_topics: [String.t()],
    presence_enabled: boolean(),
    heartbeat_interval: integer(),
    message_queue_enabled: boolean()
  }
  
  @impl true
  def init(opts) do
    config = %{
      endpoint: Keyword.get(opts, :endpoint, RubberDuckWeb.Endpoint),
      socket_path: Keyword.get(opts, :socket_path, "/socket"),
      channel_topics: Keyword.get(opts, :channel_topics, ["mcp:session", "mcp:session:streaming"]),
      presence_enabled: Keyword.get(opts, :presence_enabled, true),
      heartbeat_interval: Keyword.get(opts, :heartbeat_interval, 30_000),
      message_queue_enabled: Keyword.get(opts, :message_queue_enabled, true)
    }
    
    Logger.info("WebSocket transport initialized with config: #{inspect(config)}")
    {:ok, config}
  end
  
  @impl true
  def start_listener(config) do
    try do
      # Start supporting processes
      # Note: Presence is typically started by the application supervisor
      
      if config.message_queue_enabled do
        {:ok, _} = MCPMessageQueue.start_link()
      end
      
      {:ok, _} = MCPConnectionManager.start_link()
      
      # WebSocket listener is started by Phoenix Endpoint
      # No additional action needed for Phoenix Channels
      
      Logger.info("WebSocket transport listener started")
      :ok
    rescue
      error ->
        Logger.error("Failed to start WebSocket transport: #{inspect(error)}")
        {:error, error}
    end
  end
  
  @impl true
  def stop_listener(_config) do
    Logger.info("WebSocket transport listener stopped")
    :ok
  end
  
  @impl true
  def authenticate(connection_id, auth_params) do
    # Extract connect_info from stored connection state
    case MCPConnectionManager.get_connection_state(connection_id) do
      {:ok, connection_state} ->
        connect_info = Map.get(connection_state, :connect_info, %{})
        MCPAuth.authenticate_client(auth_params, connect_info)
        
      {:error, reason} ->
        {:error, "Connection not found: #{reason}"}
    end
  end
  
  @impl true
  def send_message(connection_id, message) do
    case find_channel_pid(connection_id) do
      {:ok, channel_pid} ->
        # Send message through Phoenix Channel
        Phoenix.Channel.push(channel_pid, "mcp_message", message)
        
        # Update activity
        MCPConnectionManager.update_activity(connection_id)
        
        :ok
        
      {:error, reason} ->
        # Queue message for later delivery if queue is enabled
        if message_queue_enabled?() do
          MCPMessageQueue.enqueue_message(connection_id, message, priority: :normal)
        end
        
        {:error, reason}
    end
  end
  
  @impl true
  def broadcast_message(connection_ids, message) do
    results = Enum.map(connection_ids, fn connection_id ->
      {connection_id, send_message(connection_id, message)}
    end)
    
    # Check if any failed
    failed = Enum.filter(results, fn {_id, result} -> result != :ok end)
    
    if Enum.empty?(failed) do
      :ok
    else
      {:error, "Failed to send to #{length(failed)} connections"}
    end
  end
  
  @impl true
  def close_connection(connection_id, reason) do
    case find_channel_pid(connection_id) do
      {:ok, channel_pid} ->
        # Send close message and terminate channel
        Phoenix.Channel.push(channel_pid, "close", %{reason: reason})
        Process.exit(channel_pid, :normal)
        
        # Clean up connection state
        MCPConnectionManager.remove_connection_state(connection_id)
        
        Logger.info("Closed connection #{connection_id}: #{reason}")
        :ok
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @impl true
  def get_connection_info(connection_id) do
    case MCPConnectionManager.get_connection_state(connection_id) do
      {:ok, connection_state} ->
        info = %{
          id: connection_id,
          transport: :websocket,
          authenticated: true,
          capabilities: connection_state.capabilities,
          metadata: %{
            connected_at: connection_state.connected_at,
            last_activity: connection_state.last_activity,
            client_info: connection_state.client_info
          }
        }
        
        {:ok, info}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @impl true
  def list_connections do
    MCPConnectionManager.list_active_connections()
    |> Enum.map(fn connection_state -> connection_state.session_id end)
  end
  
  @impl true
  def connection_alive?(connection_id) do
    case get_connection_info(connection_id) do
      {:ok, _info} ->
        # Check if channel process is alive
        case find_channel_pid(connection_id) do
          {:ok, channel_pid} -> Process.alive?(channel_pid)
          {:error, _} -> false
        end
        
      {:error, _} ->
        false
    end
  end
  
  @impl true
  def get_stats do
    connection_stats = MCPConnectionManager.list_active_connections()
    |> Enum.reduce(%{total: 0, by_client: %{}}, fn connection_state, acc ->
      client_name = get_in(connection_state, [:client_info, :name]) || "unknown"
      
      %{
        total: acc.total + 1,
        by_client: Map.update(acc.by_client, client_name, 1, &(&1 + 1))
      }
    end)
    
    queue_stats = if message_queue_enabled?() do
      MCPMessageQueue.get_queue_stats()
    else
      %{}
    end
    
    presence_stats = if presence_enabled?() do
      %{
        presence_count: Presence.list("mcp_sessions") |> map_size()
      }
    else
      %{}
    end
    
    %{
      transport: :websocket,
      connections: connection_stats,
      message_queue: queue_stats,
      presence: presence_stats,
      uptime: DateTime.utc_now()
    }
  end
  
  @impl true
  def update_config(current_config, new_options) do
    updated_config = Map.merge(current_config, Map.new(new_options))
    
    Logger.info("Updated WebSocket transport config: #{inspect(new_options)}")
    {:ok, updated_config}
  end
  
  # Public API for channel integration
  
  @doc """
  Registers a new connection with the transport.
  
  Called by MCPChannel when a new connection is established.
  """
  @spec register_connection(String.t(), map()) :: :ok
  def register_connection(connection_id, connection_state) do
    MCPConnectionManager.store_connection_state(connection_id, connection_state)
  end
  
  @doc """
  Handles message delivery acknowledgment.
  
  Called when a message is successfully delivered to the client.
  """
  @spec acknowledge_message(String.t()) :: :ok
  def acknowledge_message(message_id) do
    if message_queue_enabled?() do
      MCPMessageQueue.acknowledge_message(message_id)
    else
      :ok
    end
  end
  
  @doc """
  Reports message delivery failure.
  
  Called when a message fails to be delivered to the client.
  """
  @spec report_delivery_failure(String.t(), String.t()) :: :ok
  def report_delivery_failure(message_id, error) do
    if message_queue_enabled?() do
      MCPMessageQueue.report_delivery_failure(message_id, error)
    else
      :ok
    end
  end
  
  @doc """
  Enables streaming mode for a connection.
  
  Sets up streaming subscriptions for real-time updates.
  """
  @spec enable_streaming(String.t(), [String.t()]) :: :ok
  def enable_streaming(connection_id, topics) do
    # Subscribe to streaming topics
    Enum.each(topics, fn topic ->
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, topic)
    end)
    
    Logger.debug("Enabled streaming for connection #{connection_id} on topics: #{inspect(topics)}")
    :ok
  end
  
  @doc """
  Disables streaming mode for a connection.
  
  Removes streaming subscriptions.
  """
  @spec disable_streaming(String.t(), [String.t()]) :: :ok
  def disable_streaming(connection_id, topics) do
    # Unsubscribe from streaming topics
    Enum.each(topics, fn topic ->
      Phoenix.PubSub.unsubscribe(RubberDuck.PubSub, topic)
    end)
    
    Logger.debug("Disabled streaming for connection #{connection_id} on topics: #{inspect(topics)}")
    :ok
  end
  
  # Private functions
  
  defp find_channel_pid(connection_id) do
    # Look up channel process by connection ID
    # This is a simplified implementation - in practice, you'd need
    # to maintain a registry of channel PIDs
    case Presence.list("mcp_sessions") do
      %{^connection_id => %{metas: [%{channel_pid: pid} | _]}} ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          {:error, :process_dead}
        end
        
      _ ->
        {:error, :not_found}
    end
  end
  
  defp message_queue_enabled? do
    # Check if message queue is enabled
    # This could be configuration-driven
    true
  end
  
  defp presence_enabled? do
    # Check if presence is enabled
    # This could be configuration-driven
    true
  end
end