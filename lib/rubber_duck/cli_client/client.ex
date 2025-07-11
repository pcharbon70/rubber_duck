defmodule RubberDuck.CLIClient.Client do
  @moduledoc """
  WebSocket client for RubberDuck CLI.

  Handles connection management, message sending/receiving, and reconnection logic.
  """

  use GenServer
  require Logger

  alias Phoenix.Channels.GenSocketClient
  alias RubberDuck.CLIClient.Auth

  @default_url "ws://localhost:5555/socket/websocket"
  @reconnect_interval 5_000
  @timeout 300_000  # 5 minutes for LLM operations

  defmodule State do
    @moduledoc false
    defstruct [
      :socket,
      :channel,
      :url,
      :api_key,
      :connected,
      :channel_joined,
      :pending_requests,
      :event_handlers,
      :connect_from
    ]
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Connect to the RubberDuck server.
  """
  def connect(url \\ nil) do
    GenServer.call(__MODULE__, {:connect, url}, @timeout)
  end

  @doc """
  Disconnect from the server.
  """
  def disconnect do
    GenServer.call(__MODULE__, :disconnect)
  end

  @doc """
  Send a command to the server.
  """
  def send_command(command, params \\ %{}) do
    GenServer.call(__MODULE__, {:send_command, command, params}, @timeout)
  end

  @doc """
  Send a command and handle streaming responses.
  """
  def send_streaming_command(command, params, handler) do
    GenServer.call(__MODULE__, {:send_streaming_command, command, params, handler}, @timeout)
  end

  @doc """
  Check if connected to the server.
  """
  def connected? do
    GenServer.call(__MODULE__, :connected?)
  end

  @doc """
  Get connection stats.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    # Load configuration
    url = opts[:url] || System.get_env("RUBBER_DUCK_URL") || @default_url
    api_key = opts[:api_key] || Auth.get_api_key()

    state = %State{
      url: url,
      api_key: api_key,
      connected: false,
      channel_joined: false,
      pending_requests: %{},
      event_handlers: %{}
    }

    # Don't auto-connect, wait for explicit connect call
    # if api_key do
    #   send(self(), :connect)
    # end

    {:ok, state}
  end

  @impl true
  def handle_call({:connect, url}, from, state) do
    new_url = url || state.url

    case do_connect(new_url, state.api_key) do
      {:ok, socket_pid} ->
        # Store the socket PID but don't mark as joined yet
        state = %{
          state
          | socket: socket_pid,
            url: new_url,
            connected: true,
            channel_joined: false,
            # Store who's waiting for connection
            connect_from: from
        }

        # Don't reply yet - wait for channel_joined message
        {:noreply, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    if state.socket do
      Process.exit(state.socket, :normal)
    end

    state = %{state | socket: nil, connected: false, channel_joined: false, pending_requests: %{}}

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:send_command, command, params}, from, state) do
    if state.channel_joined do
      # Create a unique request ID
      request_id = generate_request_id()

      # Add request_id to params for async result matching
      params_with_id = Map.put(params, "request_id", request_id)

      # Send the command to the Transport process
      ref = make_ref()
      send(state.socket, {:push, "cli:commands", command, params_with_id, ref, self()})
      
      # Store the pending request with both ref (for immediate reply) and request_id (for async result)
      pending_requests =
        state.pending_requests
        |> Map.put(ref, {from, command})
        |> Map.put(request_id, from)

      {:noreply, %{state | pending_requests: pending_requests}}
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl true
  def handle_call({:send_streaming_command, command, params, handler}, _from, state) do
    if state.channel_joined do
      stream_id = generate_request_id()

      # Register the stream handler
      event_handlers = Map.put(state.event_handlers, stream_id, handler)

      # Send the streaming command
      case GenSocketClient.push(
             state.socket,
             "cli:commands",
             "stream:#{command}",
             Map.put(params, :stream_id, stream_id)
           ) do
        {:ok, _ref} ->
          {:reply, {:ok, stream_id}, %{state | event_handlers: event_handlers}}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl true
  def handle_call(:connected?, _from, state) do
    {:reply, state.connected && state.channel_joined, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    if state.channel_joined do
      case GenSocketClient.push(state.socket, "cli:commands", "stats", %{}) do
        {:ok, stats} ->
          {:reply, {:ok, stats}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :not_connected}, state}
    end
  end

  @impl true
  def handle_info(:connect, state) do
    case do_connect(state.url, state.api_key) do
      {:ok, socket} ->
        # Join the CLI channel
        case GenSocketClient.join(socket, "cli:commands", %{}) do
          {:ok, _ref} ->
            Logger.info("Connected and joined CLI channel")
            state = %{state | socket: socket, connected: true, channel_joined: true}
            {:noreply, state}

          {:error, reason} ->
            Logger.error("Failed to join CLI channel: #{inspect(reason)}")
            Process.exit(socket, :normal)
            Process.send_after(self(), :connect, @reconnect_interval)
            {:noreply, state}
        end

      {:error, reason} ->
        Logger.error("Connection failed: #{inspect(reason)}")
        Process.send_after(self(), :connect, @reconnect_interval)
        {:noreply, state}
    end
  end

  # Handle channel messages
  @impl true
  def handle_info({:channel_reply, "cli:commands", payload}, state) do
    handle_reply(payload, state)
  end

  @impl true
  def handle_info({:channel_event, "cli:commands", event, payload}, state) do
    case event do
      "stream:start" ->
        handle_stream_start(payload, state)

      "stream:data" ->
        handle_stream_data(payload, state)

      "stream:end" ->
        handle_stream_end(payload, state)

      event when event in ~w(analyze:result generate:result complete:result refactor:result test:result) ->
        Logger.debug("Received command result event: #{event}, payload: #{inspect(payload)}")
        handle_command_result(event, payload, state)

      event when event in ~w(analyze:error generate:error complete:error refactor:error test:error) ->
        handle_command_error(event, payload, state)

      "llm:connected" ->
        Logger.info("LLM provider connected: #{payload["provider"]}")
        {:noreply, state}

      _ ->
        Logger.debug("Unhandled channel event: #{event}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:channel_joined, topic}, state) do
    Logger.info("Client notified of channel join: #{topic}")

    # Reply to the waiting connect call if any
    if state.connect_from do
      GenServer.reply(state.connect_from, :ok)
    end

    {:noreply, %{state | channel_joined: true, connect_from: nil}}
  end

  @impl true
  def handle_info({:push_error, ref, reason}, state) do
    # Handle error from push request
    case Map.pop(state.pending_requests, ref) do
      {nil, pending_requests} ->
        Logger.warning("Received push error for unknown ref: #{inspect(ref)}")
        {:noreply, %{state | pending_requests: pending_requests}}

      {{from, _command}, pending_requests} ->
        GenServer.reply(from, {:error, reason})
        {:noreply, %{state | pending_requests: pending_requests}}
    end
  end

  @impl true
  def handle_info({:push_reply, ref, payload}, state) do
    # Handle reply from a push request
    case Map.get(state.pending_requests, ref) do
      nil ->
        Logger.warning("Received reply for unknown ref: #{inspect(ref)}")
        {:noreply, state}

      {from, command} ->
        Logger.debug("Push reply for command #{command}: #{inspect(payload)}")
        # Check if this is a processing status for async commands
        case {command, payload} do
          {cmd, %{"status" => "ok", "response" => %{"status" => "processing"}}}
          when cmd in ["analyze", "generate", "refactor", "test"] ->
            # Don't reply yet - wait for the async result event
            Logger.debug("Command #{cmd} is processing, waiting for async result")
            # Remove the ref-based entry but keep the request_id entry
            pending_requests = Map.delete(state.pending_requests, ref)
            {:noreply, %{state | pending_requests: pending_requests}}

          _ ->
            # For non-async commands or errors, reply immediately
            pending_requests = Map.delete(state.pending_requests, ref)

            case payload do
              %{"status" => "ok", "response" => data} ->
                GenServer.reply(from, {:ok, data})

              %{"status" => "error", "error" => reason} ->
                GenServer.reply(from, {:error, reason})

              _ ->
                GenServer.reply(from, {:ok, payload})
            end

            {:noreply, %{state | pending_requests: pending_requests}}
        end
    end
  end

  @impl true
  def handle_info({:disconnected, reason}, state) do
    Logger.warning("Disconnected: #{inspect(reason)}")

    # Clear pending requests
    for {_id, {from, _}} <- state.pending_requests do
      GenServer.reply(from, {:error, :disconnected})
    end

    state = %{state | socket: nil, connected: false, channel_joined: false, pending_requests: %{}, event_handlers: %{}}

    # Schedule reconnection
    Process.send_after(self(), :connect, @reconnect_interval)

    {:noreply, state}
  end


  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private functions

  defp do_connect(url, api_key) do
    if api_key do
      Logger.debug("Connecting to #{url}")

      # start_link expects (module, transport_mod, opts)
      GenSocketClient.start_link(
        __MODULE__.Transport,
        Phoenix.Channels.GenSocketClient.Transport.WebSocketClient,
        url: url,
        params: %{api_key: api_key},
        parent: self()
      )
    else
      {:error, :no_api_key}
    end
  end

  defp generate_request_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp handle_reply(payload, state) do
    # The payload comes from Transport with ref and payload
    case payload do
      %{ref: push_ref, payload: response} ->
        # Find the pending request by checking all refs
        {matching_ref, pending_requests} =
          Enum.find_value(state.pending_requests, {nil, state.pending_requests}, fn
            {ref, {_from, _command}} ->
              # Check if this is our ref (stored in Transport's pending map)
              if Map.get(state, {:push_ref, ref}) == push_ref do
                {ref, Map.delete(state.pending_requests, ref)}
              else
                nil
              end
          end)

        if matching_ref do
          {{from, _command}, _} = Map.get(state.pending_requests, matching_ref)

          # Reply based on the response
          case response do
            %{"status" => "ok", "response" => data} ->
              GenServer.reply(from, {:ok, data})

            %{"status" => "error", "error" => reason} ->
              GenServer.reply(from, {:error, reason})

            _ ->
              GenServer.reply(from, {:ok, response})
          end
        end

        {:noreply, %{state | pending_requests: pending_requests}}

      _ ->
        Logger.warning("Unexpected reply format: #{inspect(payload)}")
        {:noreply, state}
    end
  end

  defp handle_command_result(_event, payload, state) do
    # Find and reply to pending request
    request_id = payload["request_id"]

    case Map.pop(state.pending_requests, request_id) do
      {nil, pending_requests} ->
        # No pending request, might be a broadcast
        Logger.debug("No pending request for result with request_id: #{inspect(request_id)}")
        {:noreply, %{state | pending_requests: pending_requests}}

      {from, pending_requests} ->
        # Clean up any associated request_id entries
        result = Map.get(payload, "result", payload)
        GenServer.reply(from, {:ok, result})
        {:noreply, %{state | pending_requests: pending_requests}}
    end
  end

  defp handle_command_error(_event, payload, state) do
    # Find and reply to pending request
    request_id = payload["request_id"]

    case Map.pop(state.pending_requests, request_id) do
      {nil, pending_requests} ->
        Logger.debug("No pending request for error with request_id: #{inspect(request_id)}")
        {:noreply, %{state | pending_requests: pending_requests}}

      {from, pending_requests} ->
        error_reason = Map.get(payload, "reason", "Unknown error")
        GenServer.reply(from, {:error, error_reason})
        {:noreply, %{state | pending_requests: pending_requests}}
    end
  end

  defp handle_stream_start(payload, state) do
    stream_id = payload["stream_id"]

    case Map.get(state.event_handlers, stream_id) do
      nil ->
        {:noreply, state}

      handler ->
        handler.({:start, payload})
        {:noreply, state}
    end
  end

  defp handle_stream_data(payload, state) do
    stream_id = payload["stream_id"]

    case Map.get(state.event_handlers, stream_id) do
      nil ->
        {:noreply, state}

      handler ->
        handler.({:data, payload["chunk"]})
        {:noreply, state}
    end
  end

  defp handle_stream_end(payload, state) do
    stream_id = payload["stream_id"]

    case Map.pop(state.event_handlers, stream_id) do
      {nil, event_handlers} ->
        {:noreply, %{state | event_handlers: event_handlers}}

      {handler, event_handlers} ->
        handler.({:end, payload["status"]})
        {:noreply, %{state | event_handlers: event_handlers}}
    end
  end
end
