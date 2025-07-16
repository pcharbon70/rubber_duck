defmodule RubberDuck.MCP.Transports.HTTPSSETransport do
  @moduledoc """
  HTTP/SSE (Server-Sent Events) transport adapter for MCP connections.
  
  This transport communicates with MCP servers over HTTP using
  Server-Sent Events for real-time updates.
  """

  @behaviour RubberDuck.MCP.Transport

  require Logger
  
  alias RubberDuck.MCP.Transports.HTTPSSEClient

  @doc """
  Starts an HTTP/SSE transport connection.
  """
  def connect(opts) do
    url = Map.fetch!(opts, :url)
    headers = Map.get(opts, :headers, %{})
    
    Logger.debug("Connecting to HTTP/SSE transport: #{url}")
    
    # Start a GenServer to manage the SSE connection
    case HTTPSSEClient.start_link(url: url, headers: headers) do
      {:ok, pid} ->
        {:ok, %{type: :http_sse, url: url, pid: pid}}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends data through HTTP/SSE transport.
  """
  def send(%{pid: pid} = transport, data) do
    HTTPSSEClient.send_request(pid, data)
  end

  @doc """
  Receives data from HTTP/SSE transport.
  """
  def receive(%{pid: pid} = transport, timeout \\ 5000) do
    HTTPSSEClient.receive_event(pid, timeout)
  end

  @doc """
  Closes the HTTP/SSE transport connection.
  """
  def close(%{pid: pid} = transport) do
    Logger.debug("Closing HTTP/SSE transport")
    GenServer.stop(pid, :normal)
    :ok
  end
end