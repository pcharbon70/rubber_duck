defmodule RubberDuck.MCP.Transport do
  @moduledoc """
  Behavior definition for MCP transport implementations.
  
  Transport modules handle the low-level communication between the MCP server
  and clients. Different transport implementations (STDIO, WebSocket, HTTP)
  must implement this behavior to ensure compatibility with the MCP server.
  
  ## Connection Lifecycle
  
  1. Transport starts and accepts connections
  2. On new connection, sends `{:transport_connected, connection_info}` to parent
  3. On receiving data, sends `{:transport_message, connection_id, data}` to parent
  4. On disconnect, sends `{:transport_disconnected, connection_id, reason}` to parent
  
  ## Implementing a Transport
  
  Transport implementations should:
  - Handle connection management
  - Parse incoming data into complete JSON-RPC messages
  - Send outgoing messages as JSON
  - Manage connection state and cleanup
  """
  
  @type connection_id :: String.t()
  @type connection_info :: %{
    id: connection_id(),
    remote_info: map(),
    connected_at: DateTime.t()
  }
  
  @doc """
  Starts the transport with the given options.
  
  The transport should start accepting connections and send connection
  events to the parent process specified in options.
  
  ## Options
  
  - `:parent` - PID to send transport events to (required)
  - Additional transport-specific options
  """
  @callback start_link(opts :: keyword()) :: GenServer.on_start()
  
  @doc """
  Subscribes the calling process to transport events.
  
  After subscription, the process will receive:
  - `{:transport_connected, connection_info}`
  - `{:transport_message, connection_id, message}`
  - `{:transport_disconnected, connection_id, reason}`
  """
  @callback subscribe(transport :: pid()) :: :ok
  
  @doc """
  Sends a message to a specific connection.
  
  The message should be a map that will be encoded to JSON.
  """
  @callback send_message(
    transport :: pid(),
    connection_id :: connection_id(),
    message :: map()
  ) :: :ok | {:error, term()}
  
  @doc """
  Closes a specific connection.
  
  This should gracefully close the connection and trigger a disconnect event.
  """
  @callback close_connection(
    transport :: pid(),
    connection_id :: connection_id()
  ) :: :ok
  
  @doc """
  Stops the transport, closing all connections.
  """
  @callback stop(transport :: pid()) :: :ok
  
  @doc """
  Gets information about active connections.
  """
  @callback list_connections(transport :: pid()) :: {:ok, [connection_info()]}
  
  @doc """
  Helper function to generate unique connection IDs.
  """
  def generate_connection_id do
    "conn_" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end
  
  @doc """
  Validates that a module implements the Transport behavior.
  """
  def validate_transport!(module) do
    unless function_exported?(module, :start_link, 1) do
      raise "Transport #{module} must implement start_link/1"
    end
    
    unless function_exported?(module, :subscribe, 1) do
      raise "Transport #{module} must implement subscribe/1"
    end
    
    unless function_exported?(module, :send_message, 3) do
      raise "Transport #{module} must implement send_message/3"
    end
    
    unless function_exported?(module, :close_connection, 2) do
      raise "Transport #{module} must implement close_connection/2"
    end
    
    unless function_exported?(module, :stop, 1) do
      raise "Transport #{module} must implement stop/1"
    end
    
    :ok
  end
end