defmodule RubberDuck.MCP.Transports.STDIO do
  @moduledoc """
  STDIO transport adapter for MCP connections.
  
  This transport communicates with MCP servers that use standard
  input/output for communication, typically local command-line tools.
  """

  @behaviour RubberDuck.MCP.Transport

  require Logger

  @doc """
  Starts a STDIO transport connection.
  """
  def connect(opts) do
    command = Map.fetch!(opts, :command)
    args = Map.get(opts, :args, [])
    
    Logger.debug("Starting STDIO transport: #{command} #{Enum.join(args, " ")}")
    
    # The actual STDIO connection is handled by Hermes MCP
    # This is just a placeholder for the transport configuration
    {:ok, %{type: :stdio, command: command, args: args}}
  end

  @doc """
  Sends data through STDIO transport.
  """
  def send(transport, data) do
    # In practice, Hermes MCP handles the actual STDIO communication
    # This is a placeholder for the transport interface
    Logger.debug("STDIO send: #{inspect(data)}")
    :ok
  end

  @doc """
  Receives data from STDIO transport.
  """
  def receive(transport, timeout \\ 5000) do
    # In practice, Hermes MCP handles the actual STDIO communication
    # This is a placeholder for the transport interface
    {:ok, %{}}
  end

  @doc """
  Closes the STDIO transport connection.
  """
  def close(transport) do
    Logger.debug("Closing STDIO transport")
    :ok
  end
end