defmodule RubberDuckWeb.MCPChannelTest do
  use RubberDuckWeb.ChannelCase, async: true

  import Phoenix.Socket, only: [assign: 3]

  alias RubberDuckWeb.MCPChannel
  alias RubberDuckWeb.UserSocket
  alias RubberDuckWeb.{MCPAuth, MCPConnectionManager, MCPMessageQueue}

  @valid_client_info %{
    "name" => "TestClient",
    "version" => "1.0.0",
    "capabilities" => %{
      "tools" => %{},
      "resources" => %{}
    }
  }

  @valid_auth_params %{
    "clientInfo" => @valid_client_info,
    "apiKey" => "test_key"
  }

  setup do
    # Start required services
    start_supervised!(MCPConnectionManager)
    start_supervised!(MCPMessageQueue)

    # Create socket
    {:ok, socket} = connect(UserSocket, %{"api_key" => "test_key"})

    {:ok, socket: socket}
  end

  describe "join/3" do
    test "successfully joins MCP session with valid params", %{socket: socket} do
      {:ok, response, socket} = subscribe_and_join(socket, MCPChannel, "mcp:session", @valid_auth_params)

      assert response["protocolVersion"] == "2024-11-05"
      assert response["capabilities"]
      assert response["serverInfo"]["name"] == "RubberDuck"
      assert response["sessionId"]

      # Verify socket state
      assert socket.assigns.mcp_state.session_id
      assert socket.assigns.mcp_state.client_info == @valid_client_info
      assert socket.assigns.mcp_state.capabilities
    end

    test "rejects connection with invalid client info", %{socket: socket} do
      invalid_params = %{
        # Missing version
        "clientInfo" => %{"name" => "TestClient"},
        "apiKey" => "test_key"
      }

      {:error, response} = subscribe_and_join(socket, MCPChannel, "mcp:session", invalid_params)

      assert response.reason
    end

    test "rejects connection with invalid authentication", %{socket: socket} do
      invalid_params = %{
        "clientInfo" => @valid_client_info,
        "apiKey" => "invalid_key"
      }

      {:error, response} = subscribe_and_join(socket, MCPChannel, "mcp:session", invalid_params)

      assert response.reason
    end

    test "successfully joins streaming channel", %{socket: socket} do
      # First join main session
      {:ok, response, _session_socket} = subscribe_and_join(socket, MCPChannel, "mcp:session", @valid_auth_params)
      session_id = response["sessionId"]

      # Then join streaming channel
      {:ok, streaming_socket} =
        subscribe_and_join(socket, MCPChannel, "mcp:session:streaming", %{"session_id" => session_id})

      assert streaming_socket.assigns.streaming_session_id == session_id
    end
  end

  describe "handle_in/3 - MCP messages" do
    setup %{socket: socket} do
      {:ok, _, socket} = subscribe_and_join(socket, MCPChannel, "mcp:session", @valid_auth_params)
      {:ok, socket: socket}
    end

    test "handles tools/list request", %{socket: socket} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => "test-1",
        "method" => "tools/list",
        "params" => %{}
      }

      ref = push(socket, "mcp_message", message)

      assert_reply(ref, :ok)
      assert_push("mcp_message", response)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == "test-1"
      assert response["result"]["tools"]
    end

    test "handles tools/call request", %{socket: socket} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => "test-2",
        "method" => "tools/call",
        "params" => %{
          "name" => "test_tool",
          "arguments" => %{"param" => "value"}
        }
      }

      ref = push(socket, "mcp_message", message)

      assert_reply(ref, :ok)
      assert_push("mcp_message", response)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == "test-2"
      # Response may contain result or error depending on tool availability
      assert response["result"] || response["error"]
    end

    test "handles resources/list request", %{socket: socket} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => "test-3",
        "method" => "resources/list",
        "params" => %{}
      }

      ref = push(socket, "mcp_message", message)

      assert_reply(ref, :ok)
      assert_push("mcp_message", response)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == "test-3"
      assert response["result"]["resources"]
    end

    test "handles resources/read request", %{socket: socket} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => "test-4",
        "method" => "resources/read",
        "params" => %{
          "uri" => "memory://short-term/current"
        }
      }

      ref = push(socket, "mcp_message", message)

      assert_reply(ref, :ok)
      assert_push("mcp_message", response)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == "test-4"
      assert response["result"]["contents"]
    end

    test "handles prompts/list request", %{socket: socket} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => "test-5",
        "method" => "prompts/list",
        "params" => %{}
      }

      ref = push(socket, "mcp_message", message)

      assert_reply(ref, :ok)
      assert_push("mcp_message", response)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == "test-5"
      assert response["result"]["prompts"]
    end

    test "handles workflows/create request", %{socket: socket} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => "test-6",
        "method" => "workflows/create",
        "params" => %{
          "workflowId" => "test-workflow",
          "definition" => %{
            "type" => "sequential",
            "steps" => []
          }
        }
      }

      ref = push(socket, "mcp_message", message)

      assert_reply(ref, :ok)
      assert_push("mcp_message", response)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == "test-6"
      assert response["result"]["workflow_id"] == "test-workflow"
    end

    test "handles invalid JSON-RPC message", %{socket: socket} do
      invalid_message = %{
        # Invalid version
        "jsonrpc" => "1.0",
        "id" => "test-7",
        "method" => "tools/list"
      }

      ref = push(socket, "mcp_message", invalid_message)

      assert_reply(ref, :ok)
      assert_push("mcp_message", response)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == "test-7"
      assert response["error"]["message"]
    end

    test "handles unknown method", %{socket: socket} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => "test-8",
        "method" => "unknown/method",
        "params" => %{}
      }

      ref = push(socket, "mcp_message", message)

      assert_reply(ref, :ok)
      assert_push("mcp_message", response)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == "test-8"
      assert response["error"]["message"] =~ "Method not found"
    end
  end

  describe "handle_in/3 - heartbeat" do
    setup %{socket: socket} do
      {:ok, _, socket} = subscribe_and_join(socket, MCPChannel, "mcp:session", @valid_auth_params)
      {:ok, socket: socket}
    end

    test "responds to heartbeat", %{socket: socket} do
      ref = push(socket, "heartbeat", %{})

      assert_reply(ref, :ok)
      assert_push("heartbeat_ack", response)

      assert response["timestamp"]
    end

    test "updates last heartbeat timestamp", %{socket: socket} do
      initial_heartbeat = socket.assigns.mcp_state.last_heartbeat

      # Small delay to ensure timestamp difference
      Process.sleep(10)

      ref = push(socket, "heartbeat", %{})
      assert_reply(ref, :ok)

      # Check that heartbeat was updated
      updated_heartbeat = socket.assigns.mcp_state.last_heartbeat
      assert DateTime.compare(updated_heartbeat, initial_heartbeat) == :gt
    end
  end

  describe "handle_info/2" do
    setup %{socket: socket} do
      {:ok, _, socket} = subscribe_and_join(socket, MCPChannel, "mcp:session", @valid_auth_params)
      {:ok, socket: socket}
    end

    test "forwards streaming events", %{socket: socket} do
      event = %{
        type: "test_event",
        data: %{message: "test"}
      }

      send(socket.channel_pid, {:streaming_event, event})

      assert_push("streaming_event", ^event)
    end

    test "handles heartbeat timeout", %{socket: socket} do
      # Simulate old heartbeat
      old_heartbeat = DateTime.add(DateTime.utc_now(), -35, :second)
      state = %{socket.assigns.mcp_state | last_heartbeat: old_heartbeat}
      socket = assign(socket, :mcp_state, state)

      send(socket.channel_pid, {:heartbeat_check})

      # Channel should close due to timeout
      assert_receive %Phoenix.Socket.Message{event: "phx_close"}
    end
  end

  describe "terminate/2" do
    test "cleans up resources on normal termination", %{socket: socket} do
      {:ok, _, socket} = subscribe_and_join(socket, MCPChannel, "mcp:session", @valid_auth_params)
      session_id = socket.assigns.mcp_state.session_id

      # Verify connection state exists
      assert {:ok, _} = MCPConnectionManager.get_connection_state(session_id)

      # Terminate normally
      close(socket)

      # Verify connection state is cleaned up
      assert {:error, :not_found} = MCPConnectionManager.get_connection_state(session_id)
    end

    test "preserves connection state on abnormal termination", %{socket: socket} do
      {:ok, _, socket} = subscribe_and_join(socket, MCPChannel, "mcp:session", @valid_auth_params)
      session_id = socket.assigns.mcp_state.session_id

      # Verify connection state exists
      assert {:ok, _} = MCPConnectionManager.get_connection_state(session_id)

      # Terminate abnormally
      Process.exit(socket.channel_pid, :kill)

      # Give some time for cleanup
      Process.sleep(10)

      # Verify connection state is preserved for recovery
      assert {:ok, _} = MCPConnectionManager.get_connection_state(session_id)
    end
  end

  describe "capability negotiation" do
    test "negotiates capabilities based on client info", %{socket: socket} do
      client_with_experimental = %{
        @valid_client_info
        | "capabilities" => %{
            "tools" => %{},
            "experimental" => %{
              "streaming" => true
            }
          }
      }

      params = %{@valid_auth_params | "clientInfo" => client_with_experimental}

      {:ok, response, _socket} = subscribe_and_join(socket, MCPChannel, "mcp:session", params)

      assert response["capabilities"]["experimental"]["streaming"] == true
      assert response["capabilities"]["tools"]
      assert response["capabilities"]["resources"]
    end
  end

  describe "presence tracking" do
    test "tracks presence on join", %{socket: socket} do
      {:ok, response, _socket} = subscribe_and_join(socket, MCPChannel, "mcp:session", @valid_auth_params)
      session_id = response["sessionId"]

      # Check presence
      presences = RubberDuckWeb.Presence.list(session_id)
      assert map_size(presences) > 0
    end
  end

  describe "message queuing integration" do
    test "queues messages when streaming is enabled", %{socket: socket} do
      {:ok, _, socket} = subscribe_and_join(socket, MCPChannel, "mcp:session", @valid_auth_params)
      session_id = socket.assigns.mcp_state.session_id

      # Test message gets queued (implementation depends on message queue behavior)
      # This is a placeholder test - actual implementation may vary
      assert MCPMessageQueue.get_pending_messages(session_id) == []
    end
  end
end
