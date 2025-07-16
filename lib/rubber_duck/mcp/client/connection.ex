defmodule RubberDuck.MCP.Client.Connection do
  @moduledoc """
  Handles the MCP protocol connection and communication.
  
  This module manages the low-level connection details and protocol
  implementation using Hermes MCP.
  """

  require Logger
  
  alias RubberDuck.MCP.Client.State
  alias RubberDuck.MCP.Transports.{STDIO, HTTPSSETransport, WebSocketTransport}

  @doc """
  Establishes a connection to an MCP server based on the client state.
  """
  def connect(%State{} = state) do
    Logger.info("Connecting MCP client #{state.name} via #{elem(state.transport, 0)}")
    
    case create_transport(state.transport) do
      {:ok, transport_module, transport_opts} ->
        # Create client configuration
        client_info = %{
          name: "RubberDuck",
          version: "0.1.0"
        }
        
        # Use Hermes MCP to connect
        case start_mcp_client(transport_module, transport_opts, client_info, state) do
          {:ok, connection} ->
            {:ok, connection}
          
          {:error, reason} ->
            {:error, reason}
        end
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Disconnects from the MCP server.
  """
  def disconnect(connection) when is_pid(connection) do
    # Stop the Hermes MCP client process
    GenServer.stop(connection, :normal)
    :ok
  end
  
  def disconnect(_), do: :ok

  @doc """
  Sends a request to the MCP server.
  """
  def request(connection, method, params \\ %{}, timeout \\ 30_000) do
    try do
      # Use Hermes MCP client to send request
      case GenServer.call(connection, {:request, method, params}, timeout) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    catch
      :exit, {:timeout, _} ->
        {:error, :timeout}
      
      :exit, reason ->
        {:error, {:connection_error, reason}}
    end
  end

  @doc """
  Sends a ping to check connection health.
  """
  def ping(connection, timeout \\ 5_000) do
    # MCP doesn't have a standard ping, so we'll use a lightweight request
    case request(connection, "ping", %{}, timeout) do
      {:ok, _} -> :ok
      {:error, %{"code" => -32601}} -> :ok  # Method not found is ok for ping
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp create_transport({:stdio, opts}) do
    command = Keyword.fetch!(opts, :command)
    args = Keyword.get(opts, :args, [])
    {:ok, STDIO, %{command: command, args: args}}
  end
  
  defp create_transport({:http_sse, opts}) do
    url = Keyword.fetch!(opts, :url)
    headers = Keyword.get(opts, :headers, %{})
    {:ok, HTTPSSETransport, %{url: url, headers: headers}}
  end
  
  defp create_transport({:websocket, opts}) do
    url = Keyword.fetch!(opts, :url)
    headers = Keyword.get(opts, :headers, %{})
    {:ok, WebSocketTransport, %{url: url, headers: headers}}
  end
  
  defp create_transport(unknown) do
    {:error, {:unsupported_transport, unknown}}
  end

  defp start_mcp_client(transport_module, transport_opts, client_info, state) do
    # For now, we'll create a wrapper around Hermes MCP
    # In a real implementation, we'd use Hermes.Client directly
    case transport_module do
      STDIO ->
        # Start STDIO transport with Hermes MCP
        start_stdio_client(transport_opts, client_info, state)
      
      HTTPSSETransport ->
        # Start HTTP/SSE transport
        start_http_sse_client(transport_opts, client_info, state)
      
      WebSocketTransport ->
        # Start WebSocket transport
        start_websocket_client(transport_opts, client_info, state)
    end
  end

  defp start_stdio_client(transport_opts, client_info, state) do
    # Define a dynamic client module using Hermes MCP
    client_module = Module.concat([RubberDuck.MCP.Clients, state.name])
    
    # Check if module already exists
    if not Code.ensure_loaded?(client_module) do
      # Create the module dynamically
      Module.create(client_module, quote do
        use Hermes.Client,
          name: unquote(to_string(state.name)),
          version: "0.1.0",
          protocol_version: "2024-11-05",
          capabilities: unquote(state.capabilities)
      end, Macro.Env.location(__ENV__))
    end

    # Start the client with STDIO transport
    children = [
      {client_module, 
        transport: {:stdio, 
          command: transport_opts.command, 
          args: transport_opts.args
        }
      }
    ]

    # Start under a supervisor
    case DynamicSupervisor.start_child(
      RubberDuck.MCP.ClientSupervisor,
      {client_module, transport: {:stdio, command: transport_opts.command, args: transport_opts.args}}
    ) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  defp start_http_sse_client(_transport_opts, _client_info, _state) do
    # TODO: Implement HTTP/SSE transport
    # Hermes MCP doesn't support HTTP/SSE yet, so we'll need to implement this
    {:error, :not_implemented}
  end

  defp start_websocket_client(_transport_opts, _client_info, _state) do
    # TODO: Implement WebSocket transport
    # Hermes MCP doesn't support WebSocket yet, so we'll need to implement this
    {:error, :not_implemented}
  end
end