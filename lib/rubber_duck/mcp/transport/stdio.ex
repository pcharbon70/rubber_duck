defmodule RubberDuck.MCP.Transport.STDIO do
  @moduledoc """
  STDIO transport implementation for MCP.

  Communicates via standard input/output streams using newline-delimited
  JSON-RPC messages. This is the simplest transport and is commonly used
  for CLI-based MCP servers.

  ## Message Format

  Messages are sent as single-line JSON objects terminated by newline:
  ```
  {"jsonrpc":"2.0","method":"tools/list","id":1}\\n
  {"jsonrpc":"2.0","result":[...],"id":1}\\n
  ```
  """

  use GenServer

  @behaviour RubberDuck.MCP.Transport

  require Logger

  defstruct [
    :parent,
    :connection_id,
    :input_port,
    :output_device,
    :buffer,
    :connected
  ]

  # Client API

  @impl RubberDuck.MCP.Transport
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl RubberDuck.MCP.Transport
  def subscribe(transport) do
    GenServer.call(transport, :subscribe)
  end

  @impl RubberDuck.MCP.Transport
  def send_message(transport, connection_id, message) do
    GenServer.call(transport, {:send_message, connection_id, message})
  end

  @impl RubberDuck.MCP.Transport
  def close_connection(transport, connection_id) do
    GenServer.call(transport, {:close_connection, connection_id})
  end

  @impl RubberDuck.MCP.Transport
  def stop(transport) do
    GenServer.stop(transport)
  end

  @impl RubberDuck.MCP.Transport
  def list_connections(transport) do
    GenServer.call(transport, :list_connections)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    parent = Keyword.fetch!(opts, :parent)

    # Use custom input/output for testing, or default to stdio
    _input_device = Keyword.get(opts, :input_device, :stdio)
    output_device = Keyword.get(opts, :output_device, :stdio)

    state = %__MODULE__{
      parent: parent,
      connection_id: RubberDuck.MCP.Transport.generate_connection_id(),
      input_port: nil,
      output_device: output_device,
      buffer: "",
      connected: false
    }

    # Start reading from input in a separate process
    {:ok, state, {:continue, :start_reading}}
  end

  @impl true
  def handle_continue(:start_reading, state) do
    # Open port for reading stdin
    port_opts = [
      # Max line length
      {:line, 65536},
      :binary,
      :eof,
      {:args, []},
      {:cd, File.cwd!()}
    ]

    # Use cat for reading stdin
    port = Port.open({:spawn, "cat"}, port_opts)

    # Send connection event
    connection_info = %{
      id: state.connection_id,
      remote_info: %{type: "stdio"},
      connected_at: DateTime.utc_now()
    }

    send(state.parent, {:transport_connected, connection_info})

    {:noreply, %{state | input_port: port, connected: true}}
  end

  @impl true
  def handle_call(:subscribe, {_pid, _}, state) do
    # For STDIO, subscription is implicit - there's only one connection
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:send_message, connection_id, message}, _from, state) do
    if connection_id == state.connection_id and state.connected do
      case Jason.encode(message) do
        {:ok, json} ->
          # Write to output with newline
          IO.puts(state.output_device, json)
          {:reply, :ok, state}

        {:error, reason} ->
          Logger.error("Failed to encode message: #{inspect(reason)}")
          {:reply, {:error, :encoding_failed}, state}
      end
    else
      {:reply, {:error, :invalid_connection}, state}
    end
  end

  @impl true
  def handle_call({:close_connection, connection_id}, _from, state) do
    if connection_id == state.connection_id do
      # Close the input port
      if state.input_port do
        Port.close(state.input_port)
      end

      # Send disconnect event
      send(state.parent, {:transport_disconnected, state.connection_id, :closed})

      {:reply, :ok, %{state | connected: false, input_port: nil}}
    else
      {:reply, {:error, :invalid_connection}, state}
    end
  end

  @impl true
  def handle_call(:list_connections, _from, state) do
    connections =
      if state.connected do
        [
          %{
            id: state.connection_id,
            remote_info: %{type: "stdio"},
            connected_at: DateTime.utc_now()
          }
        ]
      else
        []
      end

    {:reply, {:ok, connections}, state}
  end

  @impl true
  def handle_info({port, {:data, {:eol, data}}}, %{input_port: port} = state) do
    # Received a complete line
    line = state.buffer <> data

    # Try to parse as JSON
    case Jason.decode(line) do
      {:ok, message} ->
        # Send to parent
        send(state.parent, {:transport_message, state.connection_id, message})
        {:noreply, %{state | buffer: ""}}

      {:error, _} ->
        Logger.warning("Failed to parse STDIO input: #{inspect(line)}")
        {:noreply, %{state | buffer: ""}}
    end
  end

  @impl true
  def handle_info({port, {:data, {:noeol, data}}}, %{input_port: port} = state) do
    # Partial line, add to buffer
    {:noreply, %{state | buffer: state.buffer <> data}}
  end

  @impl true
  def handle_info({port, :eof}, %{input_port: port} = state) do
    # Input closed
    Logger.info("STDIO input closed")

    # Send disconnect event
    send(state.parent, {:transport_disconnected, state.connection_id, :eof})

    {:noreply, %{state | connected: false, input_port: nil}}
  end

  @impl true
  def handle_info({:EXIT, port, reason}, %{input_port: port} = state) do
    Logger.warning("STDIO port exited: #{inspect(reason)}")

    # Send disconnect event
    send(state.parent, {:transport_disconnected, state.connection_id, {:port_exit, reason}})

    {:noreply, %{state | connected: false, input_port: nil}}
  end

  @impl true
  def terminate(_reason, state) do
    # Clean up port if still open
    if state.input_port do
      Port.close(state.input_port)
    end

    :ok
  end
end
