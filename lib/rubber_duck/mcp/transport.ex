defmodule RubberDuck.MCP.Transport do
  @moduledoc """
  Behaviour for MCP transport implementations.
  
  This module defines the interface that all MCP transports must implement,
  allowing for different communication methods (STDIO, HTTP/SSE, WebSocket, etc.).
  """

  @type transport_opts :: map()
  @type transport_state :: any()
  @type data :: map() | binary()

  @doc """
  Establishes a connection using the transport.
  
  Returns `{:ok, state}` on success or `{:error, reason}` on failure.
  """
  @callback connect(transport_opts) :: {:ok, transport_state} | {:error, any()}

  @doc """
  Sends data through the transport.
  
  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @callback send(transport_state, data) :: :ok | {:error, any()}

  @doc """
  Receives data from the transport.
  
  Returns `{:ok, data}` on success or `{:error, reason}` on failure.
  The function should respect the timeout value.
  """
  @callback receive(transport_state, timeout :: non_neg_integer()) :: 
    {:ok, data} | {:error, any()}

  @doc """
  Closes the transport connection.
  
  Should clean up any resources and return `:ok`.
  """
  @callback close(transport_state) :: :ok
end