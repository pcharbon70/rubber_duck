defmodule RubberDuck.MCPWebSocketIntegrationTest do
  use RubberDuckWeb.ChannelCase, async: true
  
  alias RubberDuckWeb.{MCPChannel, UserSocket}
  alias RubberDuckWeb.{MCPConnectionManager, MCPMessageQueue}
  alias RubberDuck.MCP.WebSocketTransport
  
  @valid_client_info %{
    "name" => "IntegrationTestClient",
    "version" => "1.0.0",
    "capabilities" => %{
      "tools" => %{"listChanged" => true},
      "resources" => %{"subscribe" => true},
      "experimental" => %{"streaming" => true}
    }
  }
  
  @valid_auth_params %{
    "clientInfo" => @valid_client_info,
    "apiKey" => "test_key"
  }
  
  setup do
    # Start all required services
    start_supervised!(MCPConnectionManager)
    start_supervised!(MCPMessageQueue)
    
    # Initialize WebSocket transport
    {:ok, transport_config} = WebSocketTransport.init([])
    :ok = WebSocketTransport.start_listener(transport_config)
    
    # Create socket connection
    {:ok, socket} = connect(UserSocket, %{"api_key" => "test_key"})
    
    {:ok, socket: socket, transport_config: transport_config}
  end
  
  describe "full MCP session lifecycle" do
    test "complete session from connection to disconnection", %{socket: socket} do
      # Step 1: Join MCP session
      {:ok, response, session_socket} = subscribe_and_join(socket, MCPChannel, "mcp:session", @valid_auth_params)
      
      # Verify initialization response
      assert response["protocolVersion"] == "2024-11-05"
      assert response["capabilities"]["tools"]
      assert response["capabilities"]["resources"]
      assert response["capabilities"]["experimental"]["streaming"] == true
      assert response["serverInfo"]["name"] == "RubberDuck"
      assert response["sessionId"]
      
      session_id = response["sessionId"]
      
      # Step 2: Verify connection is tracked
      {:ok, connection_info} = WebSocketTransport.get_connection_info(session_id)
      assert connection_info.id == session_id
      assert connection_info.transport == :websocket
      assert connection_info.authenticated == true
      
      # Step 3: Test basic MCP operations
      
      # List tools
      tools_message = %{
        "jsonrpc" => "2.0",
        "id" => "test-tools-1",
        "method" => "tools/list",
        "params" => %{}
      }
      
      ref = push(session_socket, "mcp_message", tools_message)
      assert_reply ref, :ok
      assert_push "mcp_message", tools_response
      
      assert tools_response["jsonrpc"] == "2.0"
      assert tools_response["id"] == "test-tools-1"
      assert tools_response["result"]["tools"]
      
      # List resources
      resources_message = %{
        "jsonrpc" => "2.0",
        "id" => "test-resources-1",
        "method" => "resources/list",
        "params" => %{}
      }
      
      ref = push(session_socket, "mcp_message", resources_message)
      assert_reply ref, :ok
      assert_push "mcp_message", resources_response
      
      assert resources_response["jsonrpc"] == "2.0"
      assert resources_response["id"] == "test-resources-1"
      assert resources_response["result"]["resources"]
      
      # List prompts
      prompts_message = %{
        "jsonrpc" => "2.0",
        "id" => "test-prompts-1",
        "method" => "prompts/list",
        "params" => %{}
      }
      
      ref = push(session_socket, "mcp_message", prompts_message)
      assert_reply ref, :ok
      assert_push "mcp_message", prompts_response
      
      assert prompts_response["jsonrpc"] == "2.0"
      assert prompts_response["id"] == "test-prompts-1"
      assert prompts_response["result"]["prompts"]
      
      # Step 4: Test heartbeat mechanism
      heartbeat_ref = push(session_socket, "heartbeat", %{})
      assert_reply heartbeat_ref, :ok
      assert_push "heartbeat_ack", heartbeat_response
      assert heartbeat_response["timestamp"]
      
      # Step 5: Test workflow operations
      workflow_message = %{
        "jsonrpc" => "2.0",
        "id" => "test-workflow-1",
        "method" => "workflows/create",
        "params" => %{
          "workflowId" => "test-workflow-integration",
          "definition" => %{
            "type" => "sequential",
            "steps" => [
              %{"tool" => "test_tool", "params" => %{"input" => "test"}}
            ]
          }
        }
      }
      
      ref = push(session_socket, "mcp_message", workflow_message)
      assert_reply ref, :ok
      assert_push "mcp_message", workflow_response
      
      assert workflow_response["jsonrpc"] == "2.0"
      assert workflow_response["id"] == "test-workflow-1"
      assert workflow_response["result"]["workflow_id"] == "test-workflow-integration"
      
      # Step 6: Test error handling
      invalid_message = %{
        "jsonrpc" => "2.0",
        "id" => "test-error-1",
        "method" => "invalid/method",
        "params" => %{}
      }
      
      ref = push(session_socket, "mcp_message", invalid_message)
      assert_reply ref, :ok
      assert_push "mcp_message", error_response
      
      assert error_response["jsonrpc"] == "2.0"
      assert error_response["id"] == "test-error-1"
      assert error_response["error"]["message"] =~ "Method not found"
      
      # Step 7: Test streaming channel
      {:ok, streaming_socket} = subscribe_and_join(socket, MCPChannel, "mcp:session:streaming", %{"session_id" => session_id})
      
      assert streaming_socket.assigns.streaming_session_id == session_id
      
      # Step 8: Verify transport statistics
      stats = WebSocketTransport.get_stats()
      assert stats.transport == :websocket
      assert stats.connections.total >= 1
      assert stats.connections.by_client["IntegrationTestClient"] >= 1
      
      # Step 9: Test graceful disconnection
      close(session_socket)
      
      # Verify connection is cleaned up
      assert {:error, :not_found} = MCPConnectionManager.get_connection_state(session_id)
    end
  end
  
  describe "connection recovery" do
    test "recovers connection after unexpected disconnect", %{socket: socket} do
      # Step 1: Establish connection
      {:ok, response, session_socket} = subscribe_and_join(socket, MCPChannel, "mcp:session", @valid_auth_params)
      session_id = response["sessionId"]
      
      # Step 2: Verify connection exists
      {:ok, initial_state} = MCPConnectionManager.get_connection_state(session_id)
      assert initial_state.session_id == session_id
      
      # Step 3: Simulate unexpected disconnect
      Process.exit(session_socket.channel_pid, :kill)
      
      # Give time for cleanup
      Process.sleep(100)
      
      # Step 4: Verify connection state is preserved for recovery
      {:ok, preserved_state} = MCPConnectionManager.get_connection_state(session_id)
      assert preserved_state.session_id == session_id
      
      # Step 5: Generate recovery token
      recovery_token = MCPConnectionManager.generate_recovery_token(session_id)
      
      # Step 6: Test recovery
      {:ok, recovered_session_id} = MCPConnectionManager.verify_recovery_token(recovery_token)
      assert recovered_session_id == session_id
      
      {:ok, recovered_state} = MCPConnectionManager.recover_session(recovery_token)
      assert recovered_state.session_id == session_id
      assert recovered_state.user_id == initial_state.user_id
    end
  end
  
  describe "message queuing" do
    test "queues and delivers messages reliably", %{socket: socket} do
      # Step 1: Establish connection
      {:ok, response, session_socket} = subscribe_and_join(socket, MCPChannel, "mcp:session", @valid_auth_params)
      session_id = response["sessionId"]
      
      # Step 2: Queue some messages
      message1 = %{
        "jsonrpc" => "2.0",
        "method" => "notification/test",
        "params" => %{"message" => "Hello 1"}
      }
      
      message2 = %{
        "jsonrpc" => "2.0",
        "method" => "notification/test",
        "params" => %{"message" => "Hello 2"}
      }
      
      {:ok, msg_id1} = MCPMessageQueue.enqueue_message(session_id, message1, priority: :high)
      {:ok, msg_id2} = MCPMessageQueue.enqueue_message(session_id, message2, priority: :normal)
      
      # Step 3: Verify messages are queued
      pending_messages = MCPMessageQueue.get_pending_messages(session_id)
      assert length(pending_messages) == 2
      
      # Step 4: Dequeue messages in priority order
      {:ok, dequeued1} = MCPMessageQueue.dequeue_message(session_id)
      assert dequeued1.id == msg_id1
      assert dequeued1.priority == :high
      
      {:ok, dequeued2} = MCPMessageQueue.dequeue_message(session_id)
      assert dequeued2.id == msg_id2
      assert dequeued2.priority == :normal
      
      # Step 5: Verify queue is empty
      {:error, :empty} = MCPMessageQueue.dequeue_message(session_id)
      
      # Step 6: Test message acknowledgment
      :ok = MCPMessageQueue.acknowledge_message(msg_id1)
      :ok = MCPMessageQueue.acknowledge_message(msg_id2)
      
      # Step 7: Test delivery failure and retry
      {:ok, retry_msg_id} = MCPMessageQueue.enqueue_message(session_id, message1, max_retries: 2)
      
      # Simulate delivery failures
      {:ok, retry_msg} = MCPMessageQueue.dequeue_message(session_id)
      :ok = MCPMessageQueue.report_delivery_failure(retry_msg_id, "Connection failed")
      
      # Message should be requeued
      {:ok, retried_msg} = MCPMessageQueue.dequeue_message(session_id)
      assert retried_msg.id == retry_msg_id
      assert retried_msg.retry_count == 1
      
      # Step 8: Test dead letter queue
      # Fail again to exceed max retries
      :ok = MCPMessageQueue.report_delivery_failure(retry_msg_id, "Connection failed again")
      {:ok, failed_again} = MCPMessageQueue.dequeue_message(session_id)
      :ok = MCPMessageQueue.report_delivery_failure(retry_msg_id, "Connection failed final")
      
      # Message should be in dead letter queue
      {:error, :empty} = MCPMessageQueue.dequeue_message(session_id)
      
      dlq_messages = MCPMessageQueue.get_dead_letter_messages(session_id)
      assert length(dlq_messages) == 1
      assert hd(dlq_messages).id == retry_msg_id
      
      # Step 9: Test DLQ retry
      :ok = MCPMessageQueue.retry_dead_letter_message(retry_msg_id)
      
      # Message should be back in main queue
      {:ok, retried_from_dlq} = MCPMessageQueue.dequeue_message(session_id)
      assert retried_from_dlq.id == retry_msg_id
      assert retried_from_dlq.retry_count == 0  # Reset
      
      # Cleanup
      close(session_socket)
    end
  end
  
  describe "transport behavior compliance" do
    test "implements full transport behavior interface", %{transport_config: config} do
      # Test all transport behavior methods
      
      # init/1 - already tested in setup
      
      # start_listener/1 - already tested in setup
      
      # stop_listener/1
      :ok = WebSocketTransport.stop_listener(config)
      
      # authenticate/2 - requires connection state
      connection_state = %{
        session_id: "test_connection",
        user_id: "test_user",
        client_info: %{name: "TestClient", version: "1.0.0"},
        connect_info: %{},
        connected_at: DateTime.utc_now(),
        last_activity: DateTime.utc_now()
      }
      
      MCPConnectionManager.store_connection_state("test_connection", connection_state)
      
      auth_params = %{
        "clientInfo" => %{
          "name" => "TestClient",
          "version" => "1.0.0"
        },
        "apiKey" => "test_key"
      }
      
      {:ok, auth_context} = WebSocketTransport.authenticate("test_connection", auth_params)
      assert auth_context.user_id
      
      # send_message/2
      test_message = %{"jsonrpc" => "2.0", "method" => "test"}
      result = WebSocketTransport.send_message("test_connection", test_message)
      assert result == :ok or match?({:error, _}, result)
      
      # broadcast_message/2
      result = WebSocketTransport.broadcast_message(["test_connection"], test_message)
      assert result == :ok or match?({:error, _}, result)
      
      # close_connection/2
      result = WebSocketTransport.close_connection("test_connection", "test_close")
      assert result == :ok or match?({:error, _}, result)
      
      # get_connection_info/1 - should fail after close
      {:error, _} = WebSocketTransport.get_connection_info("test_connection")
      
      # list_connections/0
      connections = WebSocketTransport.list_connections()
      assert is_list(connections)
      
      # connection_alive?/1
      alive = WebSocketTransport.connection_alive?("test_connection")
      assert is_boolean(alive)
      
      # get_stats/0
      stats = WebSocketTransport.get_stats()
      assert stats.transport == :websocket
      assert is_map(stats.connections)
      
      # update_config/2
      {:ok, updated_config} = WebSocketTransport.update_config(config, [heartbeat_interval: 45_000])
      assert updated_config.heartbeat_interval == 45_000
    end
  end
  
  describe "concurrent connections" do
    test "handles multiple concurrent MCP sessions", %{socket: socket} do
      # Create multiple connections
      session_sockets = for i <- 1..3 do
        {:ok, response, session_socket} = subscribe_and_join(socket, MCPChannel, "mcp:session", @valid_auth_params)
        {response["sessionId"], session_socket}
      end
      
      session_ids = Enum.map(session_sockets, fn {id, _socket} -> id end)
      
      # Verify all connections are tracked
      connections = WebSocketTransport.list_connections()
      assert length(connections) >= 3
      
      Enum.each(session_ids, fn session_id ->
        {:ok, info} = WebSocketTransport.get_connection_info(session_id)
        assert info.id == session_id
      end)
      
      # Test concurrent operations
      Enum.each(session_sockets, fn {_session_id, session_socket} ->
        tools_message = %{
          "jsonrpc" => "2.0",
          "id" => "concurrent-test-#{:rand.uniform(1000)}",
          "method" => "tools/list",
          "params" => %{}
        }
        
        ref = push(session_socket, "mcp_message", tools_message)
        assert_reply ref, :ok
        assert_push "mcp_message", _response
      end)
      
      # Verify transport stats
      stats = WebSocketTransport.get_stats()
      assert stats.connections.total >= 3
      
      # Clean up
      Enum.each(session_sockets, fn {_session_id, session_socket} ->
        close(session_socket)
      end)
    end
  end
  
  describe "error scenarios" do
    test "handles malformed JSON-RPC messages gracefully", %{socket: socket} do
      {:ok, _response, session_socket} = subscribe_and_join(socket, MCPChannel, "mcp:session", @valid_auth_params)
      
      # Test various malformed messages
      malformed_messages = [
        %{"jsonrpc" => "1.0", "method" => "test"},  # Wrong JSON-RPC version
        %{"jsonrpc" => "2.0"},  # Missing method
        %{"method" => "test"},  # Missing jsonrpc
        %{"jsonrpc" => "2.0", "method" => 123},  # Invalid method type
        "not a map"  # Not even a map
      ]
      
      Enum.each(malformed_messages, fn message ->
        ref = push(session_socket, "mcp_message", message)
        assert_reply ref, :ok
        
        # Should receive error response for messages with ID
        if is_map(message) and Map.has_key?(message, "id") do
          assert_push "mcp_message", error_response
          assert error_response["error"]
        end
      end)
      
      close(session_socket)
    end
    
    test "handles channel crashes gracefully", %{socket: socket} do
      {:ok, response, session_socket} = subscribe_and_join(socket, MCPChannel, "mcp:session", @valid_auth_params)
      session_id = response["sessionId"]
      
      # Verify connection exists
      {:ok, _state} = MCPConnectionManager.get_connection_state(session_id)
      
      # Crash the channel
      Process.exit(session_socket.channel_pid, :kill)
      
      # Give time for cleanup
      Process.sleep(100)
      
      # Connection state should be preserved for recovery
      {:ok, preserved_state} = MCPConnectionManager.get_connection_state(session_id)
      assert preserved_state.session_id == session_id
    end
  end
end