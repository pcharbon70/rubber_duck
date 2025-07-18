defmodule RubberDuck.MCP.TransportBehaviour do
  @moduledoc """
  Behaviour for MCP transport implementations.
  
  Defines the interface that all MCP transport implementations must follow,
  enabling pluggable transport layers (WebSocket, HTTP, TCP, etc.).
  
  ## Transport Types
  
  - **WebSocket**: Real-time bi-directional communication via Phoenix Channels
  - **HTTP**: Request-response via REST API (future)
  - **TCP**: Direct TCP socket communication (future)
  - **STDIO**: Standard input/output for local clients (future)
  
  ## Transport Lifecycle
  
  1. **Connection**: Client establishes connection to transport
  2. **Authentication**: Client authenticates using supported method
  3. **Capability Negotiation**: Client and server negotiate capabilities
  4. **Message Exchange**: Bi-directional message exchange
  5. **Disconnection**: Clean or unexpected disconnection
  
  ## Message Format
  
  All messages follow JSON-RPC 2.0 specification regardless of transport:
  
      {
        "jsonrpc": "2.0",
        "id": "unique-id",
        "method": "method-name",
        "params": {...}
      }
  
  ## Error Handling
  
  Transport implementations must handle:
  - Connection failures
  - Authentication failures
  - Message parsing errors
  - Protocol violations
  - Timeout scenarios
  """
  
  @type connection_id :: String.t()
  @type message :: map()
  @type auth_params :: map()
  @type transport_options :: keyword()
  @type connection_info :: %{
    id: connection_id(),
    transport: atom(),
    authenticated: boolean(),
    capabilities: map(),
    metadata: map()
  }
  
  @doc """
  Initializes the transport with configuration options.
  
  Called when the transport is started. Should return transport-specific
  configuration or state.
  
  ## Example
  
      {:ok, config} = MyTransport.init(port: 8080, ssl: true)
  """
  @callback init(transport_options()) :: {:ok, term()} | {:error, term()}
  
  @doc """
  Starts the transport listener.
  
  Begins accepting connections on the configured interface.
  
  ## Example
  
      :ok = MyTransport.start_listener(config)
  """
  @callback start_listener(term()) :: :ok | {:error, term()}
  
  @doc """
  Stops the transport listener.
  
  Gracefully shuts down the transport and closes all connections.
  
  ## Example
  
      :ok = MyTransport.stop_listener(config)
  """
  @callback stop_listener(term()) :: :ok | {:error, term()}
  
  @doc """
  Authenticates a client connection.
  
  Verifies client credentials and returns authentication context.
  
  ## Example
  
      {:ok, auth_context} = MyTransport.authenticate(connection_id, auth_params)
  """
  @callback authenticate(connection_id(), auth_params()) :: 
    {:ok, map()} | {:error, term()}
  
  @doc """
  Sends a message to a specific connection.
  
  Delivers a message to the client identified by connection_id.
  
  ## Example
  
      :ok = MyTransport.send_message(connection_id, message)
  """
  @callback send_message(connection_id(), message()) :: :ok | {:error, term()}
  
  @doc """
  Broadcasts a message to multiple connections.
  
  Sends the same message to all specified connections.
  
  ## Example
  
      :ok = MyTransport.broadcast_message([conn1, conn2], message)
  """
  @callback broadcast_message([connection_id()], message()) :: :ok | {:error, term()}
  
  @doc """
  Closes a connection.
  
  Gracefully terminates the connection with the specified reason.
  
  ## Example
  
      :ok = MyTransport.close_connection(connection_id, "session_expired")
  """
  @callback close_connection(connection_id(), String.t()) :: :ok | {:error, term()}
  
  @doc """
  Gets information about a connection.
  
  Returns metadata about the connection state.
  
  ## Example
  
      {:ok, info} = MyTransport.get_connection_info(connection_id)
  """
  @callback get_connection_info(connection_id()) :: 
    {:ok, connection_info()} | {:error, term()}
  
  @doc """
  Lists all active connections.
  
  Returns a list of all currently active connection IDs.
  
  ## Example
  
      connections = MyTransport.list_connections()
  """
  @callback list_connections() :: [connection_id()]
  
  @doc """
  Checks if a connection is alive.
  
  Verifies that the connection is still active and responsive.
  
  ## Example
  
      true = MyTransport.connection_alive?(connection_id)
  """
  @callback connection_alive?(connection_id()) :: boolean()
  
  @doc """
  Gets transport-specific statistics.
  
  Returns metrics and statistics about the transport.
  
  ## Example
  
      stats = MyTransport.get_stats()
  """
  @callback get_stats() :: map()
  
  @doc """
  Handles transport-specific configuration updates.
  
  Updates transport configuration at runtime.
  
  ## Example
  
      :ok = MyTransport.update_config(config, new_options)
  """
  @callback update_config(term(), transport_options()) :: :ok | {:error, term()}
  
  @optional_callbacks [
    update_config: 2,
    get_stats: 0,
    connection_alive?: 1
  ]
end