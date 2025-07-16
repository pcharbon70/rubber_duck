defmodule RubberDuck.MCP.Transports.WebSocketTransport do
  @moduledoc """
  WebSocket transport adapter for MCP connections.
  
  This transport communicates with MCP servers over WebSocket
  for bidirectional real-time communication.
  """

  @behaviour RubberDuck.MCP.Transport

  require Logger
  
  alias RubberDuck.MCP.Transports.WebSocketClient

  @doc """
  Starts a WebSocket transport connection.
  """
  def connect(opts) do
    url = Map.fetch!(opts, :url)
    headers = Map.get(opts, :headers, %{})
    
    Logger.debug("Connecting to WebSocket transport: #{url}")
    
    # Start a GenServer to manage the WebSocket connection
    case WebSocketClient.start_link(url: url, headers: headers) do
      {:ok, pid} ->
        {:ok, %{type: :websocket, url: url, pid: pid}}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends data through WebSocket transport.
  """
  def send(%{pid: pid} = transport, data) do
    WebSocketClient.send_message(pid, data)
  end

  @doc """
  Receives data from WebSocket transport.
  """
  def receive(%{pid: pid} = transport, timeout \\ 5000) do
    WebSocketClient.receive_message(pid, timeout)
  end

  @doc """
  Closes the WebSocket transport connection.
  """
  def close(%{pid: pid} = transport) do
    Logger.debug("Closing WebSocket transport")
    GenServer.stop(pid, :normal)
    :ok
  end
end