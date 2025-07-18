defmodule RubberDuckWeb.MCPChannel do
  @moduledoc """
  Phoenix Channel for Model Context Protocol (MCP) WebSocket transport.
  
  Implements MCP JSON-RPC 2.0 protocol over WebSocket, providing real-time
  bi-directional communication between external LLMs and RubberDuck's tool system.
  
  ## Features
  
  - Full MCP protocol support via JSON-RPC 2.0
  - Real-time tool execution with streaming
  - Connection state recovery and persistence
  - Message queuing for reliability
  - Channel presence tracking
  - Heartbeat mechanism for connection health
  
  ## Message Format
  
  All messages follow JSON-RPC 2.0 specification:
  
      # Request
      {
        "jsonrpc": "2.0",
        "id": "request-id",
        "method": "tools/list",
        "params": {}
      }
      
      # Response
      {
        "jsonrpc": "2.0",
        "id": "request-id",
        "result": {...}
      }
      
      # Notification
      {
        "jsonrpc": "2.0",
        "method": "notification/progress",
        "params": {...}
      }
  
  ## Channel Topics
  
  - `mcp:session` - Main MCP session channel
  - `mcp:session:streaming` - Streaming responses channel
  """
  
  use Phoenix.Channel
  
  alias RubberDuck.MCP.{Bridge, SecurityManager}
  alias RubberDuckWeb.{Presence, MCPAuth, MCPConnectionManager}
  
  require Logger
  
  # MCP protocol constants
  @mcp_version "2024-11-05"
  @jsonrpc_version "2.0"
  
  # Channel state
  @type channel_state :: %{
    session_id: String.t(),
    client_info: map(),
    message_queue: [map()],
    connected_at: DateTime.t(),
    last_heartbeat: DateTime.t(),
    streaming_subscriptions: MapSet.t(),
    capabilities: map()
  }
  
  @doc """
  Join the MCP channel.
  
  Handles MCP capability negotiation and session initialization.
  """
  def join("mcp:session", params, socket) do
    Logger.info("MCP client joining session with params: #{inspect(params)}")
    
    # Validate client info
    case validate_mcp_connection(params) do
      {:ok, client_info} ->
        # Authenticate client
        connect_info = socket.assigns[:connect_info] || %{}
        case MCPAuth.authenticate_client(params, connect_info) do
          {:ok, auth_context} ->
            session_id = generate_session_id()
            
            # Initialize channel state
            state = %{
              session_id: session_id,
              client_info: client_info,
              auth_context: auth_context,
              message_queue: [],
              connected_at: DateTime.utc_now(),
              last_heartbeat: DateTime.utc_now(),
              streaming_subscriptions: MapSet.new(),
              capabilities: negotiate_capabilities(client_info)
            }
            
            # Store state in socket assigns
            socket = assign(socket, :mcp_state, state)
            
            # Store connection state for recovery
            MCPConnectionManager.store_connection_state(session_id, state)
            
            # Track presence
            {:ok, _} = Presence.track(socket, session_id, %{
              client_info: client_info,
              connected_at: DateTime.utc_now(),
              capabilities: state.capabilities,
              channel_pid: self()
            })
            
            # Subscribe to streaming events
            Phoenix.PubSub.subscribe(RubberDuck.PubSub, "mcp_streaming:#{session_id}")
            
            # Start heartbeat timer
            schedule_heartbeat()
            
            # Send initialization response
            initialization_response = %{
              "protocolVersion" => @mcp_version,
              "capabilities" => state.capabilities,
              "serverInfo" => %{
                "name" => "RubberDuck",
                "version" => "1.0.0"
              },
              "sessionId" => session_id
            }
            
            Logger.info("MCP session #{session_id} initialized successfully")
            
            {:ok, initialization_response, socket}
            
          {:error, auth_reason} ->
            Logger.warning("MCP authentication failed: #{auth_reason}")
            {:error, %{reason: auth_reason}}
        end
        
      {:error, reason} ->
        Logger.warning("MCP connection rejected: #{reason}")
        {:error, %{reason: reason}}
    end
  end
  
  def join("mcp:session:streaming", %{"session_id" => session_id}, socket) do
    Logger.info("MCP streaming channel join for session: #{session_id}")
    
    # Verify session exists
    case get_session_state(socket, session_id) do
      {:ok, _state} ->
        socket = assign(socket, :streaming_session_id, session_id)
        Phoenix.PubSub.subscribe(RubberDuck.PubSub, "workflow_stream:#{session_id}")
        {:ok, socket}
        
      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end
  
  def join(_topic, _params, _socket) do
    {:error, %{reason: "Unknown channel topic"}}
  end
  
  @doc """
  Handle incoming MCP messages.
  
  Processes JSON-RPC 2.0 messages according to MCP protocol specification.
  """
  def handle_in("mcp_message", payload, socket) do
    Logger.debug("Received MCP message: #{inspect(payload)}")
    
    case validate_jsonrpc_message(payload) do
      {:ok, :request, message} ->
        handle_mcp_request(message, socket)
        
      {:ok, :response, message} ->
        handle_mcp_response(message, socket)
        
      {:ok, :notification, message} ->
        handle_mcp_notification(message, socket)
        
      {:error, error} ->
        send_error_response(socket, nil, error)
    end
    
    {:noreply, socket}
  end
  
  def handle_in("heartbeat", _payload, socket) do
    state = socket.assigns.mcp_state
    updated_state = %{state | last_heartbeat: DateTime.utc_now()}
    socket = assign(socket, :mcp_state, updated_state)
    
    push(socket, "heartbeat_ack", %{timestamp: DateTime.utc_now()})
    {:noreply, socket}
  end
  
  @doc """
  Handle channel termination.
  """
  def terminate(reason, socket) do
    if assigns = socket.assigns do
      if state = assigns[:mcp_state] do
        session_id = state.session_id
        Logger.info("MCP session #{session_id} terminated: #{inspect(reason)}")
        
        # Clean up presence
        Presence.untrack(socket, session_id)
        
        # Clean up streaming subscriptions
        Phoenix.PubSub.unsubscribe(RubberDuck.PubSub, "mcp_streaming:#{session_id}")
        Phoenix.PubSub.unsubscribe(RubberDuck.PubSub, "workflow_stream:#{session_id}")
        
        # Report termination to security manager
        if security_context = get_in(state, [:auth_context, :security_context]) do
          SecurityManager.report_security_event(
            security_context,
            "session_terminated",
            %{reason: inspect(reason), session_id: session_id}
          )
        end
        
        # Handle connection state based on termination reason
        case reason do
          :normal ->
            # Clean disconnect - remove connection state
            MCPConnectionManager.remove_connection_state(session_id)
            
          _ ->
            # Unexpected disconnect - keep state for recovery
            MCPConnectionManager.update_activity(session_id)
        end
      end
    end
    
    :ok
  end
  
  @doc """
  Handle streaming events from PubSub and heartbeat timeout.
  """
  def handle_info({:streaming_event, event}, socket) do
    # Forward streaming events to client
    push(socket, "streaming_event", event)
    {:noreply, socket}
  end
  
  def handle_info({:heartbeat_check}, socket) do
    state = socket.assigns.mcp_state
    current_time = DateTime.utc_now()
    
    # Check if heartbeat is overdue (30 seconds)
    if DateTime.diff(current_time, state.last_heartbeat) > 30 do
      Logger.warning("MCP session #{state.session_id} heartbeat timeout")
      
      # Report security event
      if security_context = get_in(state, [:auth_context, :security_context]) do
        SecurityManager.report_security_event(
          security_context,
          "session_timeout",
          %{reason: "heartbeat_timeout", session_id: state.session_id}
        )
      end
      
      {:stop, :heartbeat_timeout, socket}
    else
      schedule_heartbeat()
      {:noreply, socket}
    end
  end
  
  def handle_info(_info, socket) do
    {:noreply, socket}
  end
  
  # Private functions
  
  defp validate_mcp_connection(params) do
    # Validate required MCP connection parameters
    case params do
      %{"clientInfo" => client_info} when is_map(client_info) ->
        MCPAuth.validate_client_info(client_info)
        
      _ ->
        {:error, "Missing required clientInfo parameter"}
    end
  end
  
  defp negotiate_capabilities(_client_info) do
    # Negotiate capabilities based on client info and server capabilities
    server_capabilities = %{
      "tools" => %{
        "listChanged" => true
      },
      "resources" => %{
        "subscribe" => true,
        "listChanged" => true
      },
      "prompts" => %{
        "listChanged" => true
      },
      "logging" => %{},
      "sampling" => %{},
      "experimental" => %{
        "streaming" => true,
        "workflows" => true,
        "multiTool" => true
      }
    }
    
    # For now, return all server capabilities
    # In a full implementation, this would negotiate based on client_info
    server_capabilities
  end
  
  defp validate_jsonrpc_message(payload) do
    case payload do
      %{"jsonrpc" => @jsonrpc_version, "id" => id, "method" => method} when is_binary(method) ->
        message = %{
          id: id,
          method: method,
          params: Map.get(payload, "params", %{})
        }
        {:ok, :request, message}
        
      %{"jsonrpc" => @jsonrpc_version, "id" => id, "result" => result} ->
        message = %{id: id, result: result}
        {:ok, :response, message}
        
      %{"jsonrpc" => @jsonrpc_version, "id" => id, "error" => error} ->
        message = %{id: id, error: error}
        {:ok, :response, message}
        
      %{"jsonrpc" => @jsonrpc_version, "method" => method} when is_binary(method) ->
        message = %{
          method: method,
          params: Map.get(payload, "params", %{})
        }
        {:ok, :notification, message}
        
      _ ->
        {:error, "Invalid JSON-RPC 2.0 message format"}
    end
  end
  
  defp handle_mcp_request(%{id: id, method: method, params: params}, socket) do
    Logger.debug("Handling MCP request: #{method}")
    
    # Get security context from auth context
    state = socket.assigns.mcp_state
    security_context = get_in(state, [:auth_context, :security_context])
    
    # Check request size limits
    case SecurityManager.validate_request_size(%{method: method, params: params}) do
      :ok ->
        # Check rate limits
        case SecurityManager.check_rate_limit(security_context, method) do
          :ok ->
            # Check authorization
            case SecurityManager.authorize_operation(security_context, method, params) do
              :allow ->
                # Process the request
                result = process_authorized_request(method, params, id, socket)
                
                # Audit the operation
                SecurityManager.audit_operation(security_context, method, params, result)
                
                result
                
              {:deny, reason} ->
                SecurityManager.audit_operation(security_context, method, params, {:error, :unauthorized})
                send_error_response(socket, id, "Unauthorized: #{reason}")
            end
            
          {:error, :rate_limited, retry_after: retry_after} ->
            SecurityManager.audit_operation(security_context, method, params, {:error, :rate_limited})
            send_error_response(socket, id, %{
              code: -32000,
              message: "Rate limit exceeded",
              data: %{retry_after: retry_after}
            })
        end
        
      {:error, :request_too_large} ->
        send_error_response(socket, id, "Request too large")
    end
  end
  
  defp process_authorized_request(method, params, id, socket) do
    case method do
      "tools/list" ->
        result = Bridge.list_tools()
        send_success_response(socket, id, result)
        
      "tools/call" ->
        handle_tool_call(params, id, socket)
        
      "resources/list" ->
        result = Bridge.list_resources(params)
        send_success_response(socket, id, result)
        
      "resources/read" ->
        uri = Map.get(params, "uri")
        context = build_context(socket)
        result = Bridge.read_resource(uri, context)
        send_success_response(socket, id, result)
        
      "prompts/list" ->
        result = Bridge.list_prompts()
        send_success_response(socket, id, result)
        
      "prompts/get" ->
        name = Map.get(params, "name")
        result = Bridge.get_prompt(name)
        send_success_response(socket, id, result)
        
      "workflows/create" ->
        handle_workflow_create(params, id, socket)
        
      "workflows/execute" ->
        handle_workflow_execute(params, id, socket)
        
      "workflows/templates" ->
        result = Bridge.list_workflow_templates()
        send_success_response(socket, id, result)
        
      "sampling/createMessage" ->
        handle_sampling_request(params, id, socket)
        
      _ ->
        send_error_response(socket, id, "Method not found: #{method}")
    end
  end
  
  defp handle_mcp_response(%{id: id, result: result}, socket) do
    Logger.debug("Received MCP response for request #{id}: #{inspect(result)}")
    # Handle response correlation if needed
    {:ok, socket}
  end
  
  defp handle_mcp_response(%{id: id, error: error}, socket) do
    Logger.warning("Received MCP error response for request #{id}: #{inspect(error)}")
    {:ok, socket}
  end
  
  defp handle_mcp_notification(%{method: method, params: params}, socket) do
    Logger.debug("Handling MCP notification: #{method}")
    
    case method do
      "notifications/cancelled" ->
        # Handle request cancellation
        request_id = Map.get(params, "requestId")
        cancel_request(request_id, socket)
        
      "notifications/progress" ->
        # Handle progress notifications
        handle_progress_notification(params, socket)
        
      _ ->
        Logger.warning("Unknown MCP notification method: #{method}")
    end
    
    {:ok, socket}
  end
  
  defp handle_tool_call(params, id, socket) do
    tool_name = Map.get(params, "name")
    arguments = Map.get(params, "arguments", %{})
    context = build_context(socket)
    
    case enable_streaming?(socket) do
      true ->
        # Handle streaming tool execution
        handle_streaming_tool_call(tool_name, arguments, context, id, socket)
        
      false ->
        # Handle regular tool execution
        result = Bridge.execute_tool(tool_name, arguments, context)
        send_success_response(socket, id, result)
    end
  end
  
  defp handle_streaming_tool_call(tool_name, arguments, context, id, socket) do
    state = socket.assigns.mcp_state
    session_id = state.session_id
    
    # Set up streaming context
    streaming_context = Map.merge(context, %{
      streaming_enabled: true,
      session_id: session_id,
      request_id: id
    })
    
    # Execute tool with streaming
    Task.start(fn ->
      result = Bridge.execute_tool(tool_name, arguments, streaming_context)
      
      # Send final response
      send_success_response(socket, id, result)
    end)
  end
  
  defp handle_workflow_create(params, id, socket) do
    workflow_id = Map.get(params, "workflowId")
    definition = Map.get(params, "definition")
    options = Map.get(params, "options", %{})
    
    result = Bridge.create_workflow(workflow_id, definition, options)
    send_success_response(socket, id, result)
  end
  
  defp handle_workflow_execute(params, id, socket) do
    workflow_id = Map.get(params, "workflowId")
    definition = Map.get(params, "definition")
    options = Map.get(params, "options", %{})
    
    case enable_streaming?(socket) do
      true ->
        # Handle streaming workflow execution
        handle_streaming_workflow_execute(workflow_id, definition, options, id, socket)
        
      false ->
        # Handle regular workflow execution
        result = Bridge.execute_workflow(workflow_id, definition, options)
        send_success_response(socket, id, result)
    end
  end
  
  defp handle_streaming_workflow_execute(workflow_id, definition, options, id, socket) do
    state = socket.assigns.mcp_state
    session_id = state.session_id
    
    # Set up streaming options
    streaming_options = Map.merge(options, %{
      streaming_enabled: true,
      session_id: session_id,
      request_id: id
    })
    
    # Execute workflow with streaming
    Task.start(fn ->
      result = Bridge.execute_workflow(workflow_id, definition, streaming_options)
      
      # Send final response
      send_success_response(socket, id, result)
    end)
  end
  
  defp handle_sampling_request(params, id, socket) do
    sampling_config = Map.get(params, "config", %{})
    options = Map.get(params, "options", %{})
    
    result = Bridge.execute_workflow_sampling(sampling_config, options)
    send_success_response(socket, id, result)
  end
  
  defp cancel_request(request_id, _socket) do
    Logger.info("Cancelling MCP request: #{request_id}")
    # TODO: Implement request cancellation
    :ok
  end
  
  defp handle_progress_notification(params, _socket) do
    Logger.debug("Progress notification: #{inspect(params)}")
    # TODO: Handle progress notifications
    :ok
  end
  
  defp send_success_response(socket, id, result) do
    response = %{
      "jsonrpc" => @jsonrpc_version,
      "id" => id,
      "result" => result
    }
    
    push(socket, "mcp_message", response)
  end
  
  defp send_error_response(socket, id, error) when is_binary(error) do
    response = %{
      "jsonrpc" => @jsonrpc_version,
      "id" => id,
      "error" => %{
        "code" => -32000,
        "message" => error
      }
    }
    
    push(socket, "mcp_message", response)
  end
  
  defp send_error_response(socket, id, error) when is_map(error) do
    response = %{
      "jsonrpc" => @jsonrpc_version,
      "id" => id,
      "error" => error
    }
    
    push(socket, "mcp_message", response)
  end
  
  defp build_context(socket) do
    state = socket.assigns.mcp_state
    
    %{
      session_id: state.session_id,
      user_id: get_in(state, [:auth_context, :user_id]) || socket.assigns[:user_id],
      client_info: state.client_info,
      capabilities: state.capabilities,
      timestamp: DateTime.utc_now(),
      security_context: get_in(state, [:auth_context, :security_context])
    }
  end
  
  defp enable_streaming?(socket) do
    state = socket.assigns.mcp_state
    get_in(state.capabilities, ["experimental", "streaming"]) == true
  end
  
  defp get_session_state(socket, session_id) do
    state = socket.assigns.mcp_state
    
    if state.session_id == session_id do
      {:ok, state}
    else
      {:error, "Session not found"}
    end
  end
  
  defp schedule_heartbeat do
    Process.send_after(self(), {:heartbeat_check}, 15_000)
  end
  
  defp generate_session_id do
    "mcp_session_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end