defmodule RubberDuck.MCP.Session do
  @moduledoc """
  Manages individual MCP client sessions.

  Each session represents a single client connection and maintains:
  - Client state and context
  - Request/response correlation
  - Tool and resource subscriptions
  - Session-specific configuration

  Sessions are supervised by SessionSupervisor and communicate with
  the main MCP server for message routing.
  """

  use GenServer

  alias RubberDuck.MCP.{Protocol, Bridge}
  alias Phoenix.PubSub

  require Logger

  @request_timeout RubberDuck.Config.Timeouts.get([:mcp, :request], 30_000)
  @max_concurrent_requests 50

  defstruct [
    :id,
    :server_pid,
    :transport,
    :transport_mod,
    :client_info,
    :capabilities,
    :subscriptions,
    :pending_requests,
    :request_handlers,
    :initialized,
    :shutting_down
  ]

  # Client API

  @doc """
  Starts a new session.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Handles an incoming message for this session.
  """
  def handle_message(session, message) do
    GenServer.cast(session, {:handle_message, message})
  end

  @doc """
  Sends a notification to this session.
  """
  def send_notification(session, method, params) do
    GenServer.cast(session, {:send_notification, method, params})
  end

  @doc """
  Notifies the session about impending shutdown.
  """
  def notify_shutdown(session) do
    GenServer.cast(session, :notify_shutdown)
  end

  @doc """
  Stops the session process.
  """
  def stop(session, reason) do
    GenServer.stop(session, reason)
  end

  @doc """
  Gets session information.
  """
  def get_info(session) do
    GenServer.call(session, :get_info)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    state = %__MODULE__{
      id: Keyword.fetch!(opts, :id),
      server_pid: Keyword.fetch!(opts, :server_pid),
      transport: Keyword.fetch!(opts, :transport),
      transport_mod: Keyword.fetch!(opts, :transport_mod),
      client_info: Keyword.get(opts, :client_info, %{}),
      capabilities: %{},
      subscriptions: %{
        tools: MapSet.new(),
        resources: MapSet.new(),
        prompts: MapSet.new()
      },
      pending_requests: %{},
      request_handlers: %{},
      initialized: true,
      shutting_down: false
    }

    # Set up request handlers
    state = setup_request_handlers(state)

    # Monitor server process
    Process.monitor(state.server_pid)

    Logger.info("Session #{state.id} started")

    {:ok, state}
  end

  @impl true
  def handle_cast({:handle_message, message}, state) do
    case Protocol.parse_message(message) do
      {:ok, parsed_message} ->
        handle_parsed_message(parsed_message, state)

      {:error, reason} ->
        Logger.error("Failed to parse message in session #{state.id}: #{reason}")

        # Send parse error if we can determine an ID
        id = get_message_id(message)
        send_error(state, id, :parse_error, reason)

        {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:send_notification, method, params}, state) do
    notification = Protocol.build_notification(method, params)
    send_to_client(state, notification)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:notify_shutdown, state) do
    # Send shutdown notification to client
    send_notification(self(), "notifications/cancelled", %{
      "reason" => "Server is shutting down"
    })

    {:noreply, %{state | shutting_down: true}}
  end

  @impl true
  def handle_cast({:update_subscriptions, subscriptions}, state) do
    {:noreply, %{state | subscriptions: subscriptions}}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    info = %{
      id: state.id,
      client_info: state.client_info,
      capabilities: state.capabilities,
      subscriptions: %{
        tools: MapSet.size(state.subscriptions.tools),
        resources: MapSet.size(state.subscriptions.resources),
        prompts: MapSet.size(state.subscriptions.prompts)
      },
      pending_requests: map_size(state.pending_requests),
      shutting_down: state.shutting_down
    }

    {:reply, {:ok, info}, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) when pid == state.server_pid do
    Logger.warning("MCP server terminated, shutting down session #{state.id}: #{inspect(reason)}")
    {:stop, :server_down, state}
  end

  @impl true
  def handle_info({:request_timeout, request_id}, state) do
    case Map.get(state.pending_requests, request_id) do
      nil ->
        {:noreply, state}

      _request ->
        Logger.warning("Request #{request_id} timed out in session #{state.id}")

        # Clean up pending request
        state = %{state | pending_requests: Map.delete(state.pending_requests, request_id)}

        # Could send timeout error to client here if needed

        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:tool_update, tool_name, _event}, state) do
    if MapSet.member?(state.subscriptions.tools, tool_name) do
      send_notification(self(), "notifications/tools/list_changed", %{})
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:resource_update, resource_uri, event}, state) do
    if MapSet.member?(state.subscriptions.resources, resource_uri) do
      case event do
        :changed ->
          send_notification(self(), "notifications/resources/updated", %{
            "uri" => resource_uri
          })

        :deleted ->
          send_notification(self(), "notifications/resources/deleted", %{
            "uri" => resource_uri
          })

        _ ->
          :ok
      end
    end

    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Session #{state.id} terminating: #{inspect(reason)}")

    # Notify server about termination
    send(state.server_pid, {:session_terminated, state.id})

    # Clean up any resources
    cleanup_session(state)

    :ok
  end

  # Private functions

  defp setup_request_handlers(state) do
    handlers = %{
      # Tool-related methods
      "tools/list" => &handle_tools_list/2,
      "tools/call" => &handle_tools_call/2,

      # Resource-related methods
      "resources/list" => &handle_resources_list/2,
      "resources/read" => &handle_resources_read/2,
      "resources/subscribe" => &handle_resources_subscribe/2,
      "resources/unsubscribe" => &handle_resources_unsubscribe/2,

      # Prompt-related methods
      "prompts/list" => &handle_prompts_list/2,
      "prompts/get" => &handle_prompts_get/2,

      # Logging methods
      "logging/setLevel" => &handle_logging_set_level/2,

      # Lifecycle methods
      "ping" => &handle_ping/2,
      "shutdown" => &handle_shutdown/2
    }

    %{state | request_handlers: handlers}
  end

  defp handle_parsed_message(message, state) do
    cond do
      Protocol.request?(message) ->
        handle_request(message, state)

      Protocol.notification?(message) ->
        handle_notification(message, state)

      Protocol.response?(message) ->
        handle_response(message, state)

      true ->
        Logger.warning("Unknown message type in session #{state.id}")
        {:noreply, state}
    end
  end

  defp handle_request(%{"id" => id, "method" => method, "params" => params}, state) do
    # Check if shutting down
    if state.shutting_down do
      send_error(state, id, :internal_error, "Server is shutting down")
      {:noreply, state}
    else
      # Check concurrent request limit
      if map_size(state.pending_requests) >= @max_concurrent_requests do
        send_error(state, id, :internal_error, "Too many concurrent requests")
        {:noreply, state}
      else
        # Find handler
        case Map.get(state.request_handlers, method) do
          nil ->
            send_error(state, id, :method_not_found, "Method not found: #{method}")
            {:noreply, state}

          handler ->
            # Track pending request
            request_info = %{
              id: id,
              method: method,
              params: params || %{},
              started_at: System.monotonic_time(:millisecond)
            }

            state = %{state | pending_requests: Map.put(state.pending_requests, id, request_info)}

            # Set timeout
            Process.send_after(self(), {:request_timeout, id}, @request_timeout)

            # Execute handler
            Task.start(fn ->
              try do
                result = handler.(params || %{}, state)
                response = Protocol.build_response(id, result)
                send_to_client(state, response)
              rescue
                error ->
                  Logger.error("Request handler error: #{Exception.message(error)}")

                  error_response =
                    Protocol.build_error(
                      id,
                      :internal_error,
                      Exception.message(error)
                    )

                  send_to_client(state, error_response)
              end
            end)

            {:noreply, state}
        end
      end
    end
  end

  defp handle_notification(%{"method" => method, "params" => _params}, state) do
    Logger.debug("Received notification #{method} in session #{state.id}")

    # Handle known notifications
    case method do
      "notifications/cancelled" ->
        # Client cancelled something
        :ok

      _ ->
        Logger.debug("Unknown notification: #{method}")
    end

    {:noreply, state}
  end

  defp handle_response(_response, state) do
    # Handle responses to requests we sent to the client
    # (Not common in server role, but possible)
    {:noreply, state}
  end

  # Request handlers

  defp handle_tools_list(_params, _state) do
    Bridge.list_tools()
  end

  defp handle_tools_call(%{"name" => tool_name, "arguments" => arguments}, state) do
    Bridge.execute_tool(tool_name, arguments, build_context(state))
  end

  defp handle_resources_list(params, _state) do
    Bridge.list_resources(params)
  end

  defp handle_resources_read(%{"uri" => uri}, state) do
    Bridge.read_resource(uri, build_context(state))
  end

  defp handle_resources_subscribe(%{"uri" => uri}, state) do
    # Subscribe to resource updates
    :ok = PubSub.subscribe(RubberDuck.PubSub, "mcp:resources:#{uri}")

    # Update subscriptions
    updated_subscriptions =
      update_in(
        state.subscriptions.resources,
        &MapSet.put(&1, uri)
      )

    # Note: Need to update state through GenServer
    GenServer.cast(self(), {:update_subscriptions, updated_subscriptions})

    %{"success" => true}
  end

  defp handle_resources_unsubscribe(%{"uri" => uri}, state) do
    # Unsubscribe from resource updates
    :ok = PubSub.unsubscribe(RubberDuck.PubSub, "mcp:resources:#{uri}")

    # Update subscriptions
    updated_subscriptions =
      update_in(
        state.subscriptions.resources,
        &MapSet.delete(&1, uri)
      )

    GenServer.cast(self(), {:update_subscriptions, updated_subscriptions})

    %{"success" => true}
  end

  defp handle_prompts_list(_params, _state) do
    Bridge.list_prompts()
  end

  defp handle_prompts_get(%{"name" => name}, _state) do
    Bridge.get_prompt(name)
  end

  defp handle_logging_set_level(%{"level" => level}, state) do
    # Could implement session-specific logging levels
    Logger.info("Session #{state.id} requested log level: #{level}")
    %{"success" => true}
  end

  defp handle_ping(_params, _state) do
    %{"pong" => true}
  end

  defp handle_shutdown(_params, _state) do
    # Graceful shutdown requested by client
    Process.send_after(self(), :shutdown, 100)
    %{"success" => true}
  end

  # Helper functions

  defp send_to_client(state, message) do
    send(state.server_pid, {:session_response, state.id, message})
  end

  defp send_error(state, id, code, message) do
    error_response = Protocol.build_error(id, code, message)
    send_to_client(state, error_response)
  end

  defp build_context(state) do
    %{
      session_id: state.id,
      client_info: state.client_info,
      capabilities: state.capabilities
    }
  end

  defp get_message_id(message) when is_map(message), do: Map.get(message, "id")
  defp get_message_id(_), do: nil

  defp cleanup_session(state) do
    # Unsubscribe from all PubSub topics
    Enum.each(state.subscriptions.resources, fn uri ->
      PubSub.unsubscribe(RubberDuck.PubSub, "mcp:resources:#{uri}")
    end)

    Enum.each(state.subscriptions.tools, fn tool ->
      PubSub.unsubscribe(RubberDuck.PubSub, "mcp:tools:#{tool}")
    end)
  end
end
