defmodule RubberDuck.MCP.Server do
  @moduledoc """
  Core MCP (Model Context Protocol) server implementation.

  Handles JSON-RPC 2.0 protocol messages and manages connections to external
  AI systems and tools. Supports multiple transport mechanisms and provides
  session management with fault tolerance.

  ## Architecture

  The server follows a layered architecture:
  - Transport Layer: Handles different connection types (STDIO, WebSocket, HTTP)
  - Protocol Layer: JSON-RPC 2.0 message parsing and validation
  - Session Layer: Per-connection state management
  - Bridge Layer: Integration with RubberDuck's tool system

  ## Protocol Version

  Supports MCP protocol version 2024-11-05
  """

  use GenServer

  alias RubberDuck.MCP.{
    Protocol,
    Session,
    SessionSupervisor,
    Capability
  }

  alias Phoenix.PubSub

  require Logger

  @protocol_version "2024-11-05"

  # Client API

  @doc """
  Starts the MCP server with the given options.

  ## Options

  - `:transport` - Transport module to use (required)
  - `:transport_opts` - Options for the transport
  - `:name` - GenServer name (defaults to __MODULE__)
  - `:max_sessions` - Maximum concurrent sessions (defaults to 100)
  - `:capabilities` - Server capabilities to advertise
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Sends a notification to a specific session.
  """
  def notify(server \\ __MODULE__, session_id, method, params) do
    GenServer.cast(server, {:notify, session_id, method, params})
  end

  @doc """
  Gets the current server status.
  """
  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  end

  @doc """
  Lists active sessions.
  """
  def list_sessions(server \\ __MODULE__) do
    GenServer.call(server, :list_sessions)
  end

  @doc """
  Gracefully shuts down the server.
  """
  def shutdown(server \\ __MODULE__) do
    GenServer.call(server, :shutdown)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    # Initialize transport
    transport_mod = Keyword.fetch!(opts, :transport)
    transport_opts = Keyword.get(opts, :transport_opts, [])

    {:ok, transport} = transport_mod.start_link(Keyword.merge(transport_opts, parent: self()))

    # Start session supervisor
    {:ok, session_supervisor} = SessionSupervisor.start_link()

    state = %{
      transport: transport,
      transport_mod: transport_mod,
      session_supervisor: session_supervisor,
      sessions: %{},
      capabilities: build_capabilities(opts),
      max_sessions: Keyword.get(opts, :max_sessions, 100),
      protocol_version: @protocol_version,
      shutdown_requested: false
    }

    # Subscribe to transport events
    :ok = transport_mod.subscribe(transport)

    Logger.info("MCP Server started with transport: #{transport_mod}")

    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      transport: state.transport_mod,
      active_sessions: map_size(state.sessions),
      max_sessions: state.max_sessions,
      protocol_version: state.protocol_version,
      capabilities: state.capabilities,
      shutdown_requested: state.shutdown_requested
    }

    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call(:list_sessions, _from, state) do
    sessions =
      Enum.map(state.sessions, fn {id, session} ->
        %{
          id: id,
          client_info: session.client_info,
          created_at: session.created_at,
          last_activity: session.last_activity
        }
      end)

    {:reply, {:ok, sessions}, state}
  end

  @impl true
  def handle_call(:shutdown, _from, state) do
    Logger.info("MCP Server shutdown requested")

    # Mark shutdown requested
    state = %{state | shutdown_requested: true}

    # Notify all sessions about shutdown
    Enum.each(state.sessions, fn {session_id, _} ->
      Session.notify_shutdown(session_id)
    end)

    # Give sessions time to gracefully close
    Process.send_after(self(), :force_shutdown, 5_000)

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:notify, session_id, method, params}, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        Logger.warning("Attempted to notify non-existent session: #{session_id}")
        {:noreply, state}

      _session ->
        notification = Protocol.build_notification(method, params)
        :ok = state.transport_mod.send_message(state.transport, session_id, notification)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:transport_connected, connection_info}, state) do
    if state.shutdown_requested do
      # Reject new connections during shutdown
      state.transport_mod.close_connection(state.transport, connection_info.id)
      {:noreply, state}
    else
      handle_new_connection(connection_info, state)
    end
  end

  @impl true
  def handle_info({:transport_message, connection_id, message}, state) do
    case Map.get(state.sessions, connection_id) do
      nil ->
        # Message from unknown connection - might be initialization
        handle_initialization_message(connection_id, message, state)

      session ->
        # Forward to session
        Session.handle_message(session.pid, message)

        # Update last activity
        updated_session = %{session | last_activity: DateTime.utc_now()}
        updated_sessions = Map.put(state.sessions, connection_id, updated_session)
        {:noreply, %{state | sessions: updated_sessions}}
    end
  end

  @impl true
  def handle_info({:transport_disconnected, connection_id, reason}, state) do
    case Map.get(state.sessions, connection_id) do
      nil ->
        {:noreply, state}

      session ->
        Logger.info("Session #{connection_id} disconnected: #{inspect(reason)}")

        # Terminate session
        Session.stop(session.pid, reason)

        # Remove from state
        updated_sessions = Map.delete(state.sessions, connection_id)
        {:noreply, %{state | sessions: updated_sessions}}
    end
  end

  @impl true
  def handle_info({:session_response, session_id, response}, state) do
    # Forward response to transport
    :ok = state.transport_mod.send_message(state.transport, session_id, response)
    {:noreply, state}
  end

  @impl true
  def handle_info({:session_terminated, session_id}, state) do
    # Clean up terminated session
    updated_sessions = Map.delete(state.sessions, session_id)

    # Close transport connection
    state.transport_mod.close_connection(state.transport, session_id)

    {:noreply, %{state | sessions: updated_sessions}}
  end

  @impl true
  def handle_info(:force_shutdown, state) do
    Logger.warning("Forcing MCP Server shutdown")

    # Force close all sessions
    Enum.each(state.sessions, fn {_, session} ->
      Process.exit(session.pid, :shutdown)
    end)

    # Stop transport
    state.transport_mod.stop(state.transport)

    {:stop, :shutdown, state}
  end

  # Private functions

  defp handle_new_connection(connection_info, state) do
    # Check session limit
    if map_size(state.sessions) >= state.max_sessions do
      Logger.warning("Maximum sessions reached, rejecting connection")

      error =
        Protocol.build_error(
          nil,
          :internal_error,
          "Maximum sessions reached"
        )

      state.transport_mod.send_message(state.transport, connection_info.id, error)
      state.transport_mod.close_connection(state.transport, connection_info.id)

      {:noreply, state}
    else
      # Connection accepted, waiting for initialization
      Logger.info("New connection accepted: #{connection_info.id}")
      {:noreply, state}
    end
  end

  defp handle_initialization_message(connection_id, message, state) do
    case Protocol.parse_message(message) do
      {:ok, %{method: "initialize", params: params, id: request_id}} ->
        # Handle initialization request
        handle_initialization(connection_id, request_id, params, state)

      {:ok, _} ->
        # Non-initialization message before initialization
        error =
          Protocol.build_error(
            nil,
            :invalid_request,
            "Must initialize before sending other messages"
          )

        state.transport_mod.send_message(state.transport, connection_id, error)
        state.transport_mod.close_connection(state.transport, connection_id)
        {:noreply, state}

      {:error, parse_error} ->
        # Invalid message
        error = Protocol.build_error(nil, :parse_error, parse_error)
        state.transport_mod.send_message(state.transport, connection_id, error)
        state.transport_mod.close_connection(state.transport, connection_id)
        {:noreply, state}
    end
  end

  defp handle_initialization(connection_id, request_id, params, state) do
    # Validate protocol version
    client_version = Map.get(params, "protocolVersion", "unknown")

    if not compatible_version?(client_version, state.protocol_version) do
      error =
        Protocol.build_error(
          request_id,
          :invalid_params,
          "Incompatible protocol version: #{client_version}"
        )

      state.transport_mod.send_message(state.transport, connection_id, error)
      state.transport_mod.close_connection(state.transport, connection_id)
      {:noreply, state}
    else
      # Start session
      case SessionSupervisor.start_session(state.session_supervisor, %{
             id: connection_id,
             server_pid: self(),
             transport: state.transport,
             transport_mod: state.transport_mod,
             client_info: Map.get(params, "clientInfo", %{})
           }) do
        {:ok, session_pid} ->
          # Create session record
          session = %{
            id: connection_id,
            pid: session_pid,
            client_info: Map.get(params, "clientInfo", %{}),
            created_at: DateTime.utc_now(),
            last_activity: DateTime.utc_now()
          }

          # Store session
          updated_sessions = Map.put(state.sessions, connection_id, session)

          # Send initialization response
          response =
            Protocol.build_response(request_id, %{
              "protocolVersion" => state.protocol_version,
              "capabilities" => state.capabilities,
              "serverInfo" => Capability.server_info()
            })

          state.transport_mod.send_message(state.transport, connection_id, response)

          # Notify session initialized
          PubSub.broadcast(
            RubberDuck.PubSub,
            "mcp:sessions",
            {:session_initialized, connection_id}
          )

          {:noreply, %{state | sessions: updated_sessions}}

        {:error, reason} ->
          Logger.error("Failed to start session: #{inspect(reason)}")

          error =
            Protocol.build_error(
              request_id,
              :internal_error,
              "Failed to start session"
            )

          state.transport_mod.send_message(state.transport, connection_id, error)
          state.transport_mod.close_connection(state.transport, connection_id)
          {:noreply, state}
      end
    end
  end

  defp build_capabilities(opts) do
    # Get custom capabilities from options
    custom_capabilities = Keyword.get(opts, :capabilities, %{})

    # Use Capability module to build capabilities
    Capability.merge_capabilities(custom_capabilities)
  end

  defp compatible_version?(client_version, server_version) do
    Capability.compatible_version?(client_version, server_version)
  end
end
