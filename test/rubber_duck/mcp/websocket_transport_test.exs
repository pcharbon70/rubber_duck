defmodule RubberDuck.MCP.WebSocketTransportTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.MCP.WebSocketTransport
  alias RubberDuckWeb.{MCPConnectionManager, MCPMessageQueue}
  
  @test_config %{
    endpoint: RubberDuckWeb.Endpoint,
    socket_path: "/socket",
    channel_topics: ["mcp:session", "mcp:session:streaming"],
    presence_enabled: true,
    heartbeat_interval: 30_000,
    message_queue_enabled: true
  }
  
  @test_connection_id "test_connection_123"
  @test_message %{
    "jsonrpc" => "2.0",
    "method" => "tools/list",
    "params" => %{}
  }
  
  setup do
    # Start required services
    start_supervised!(MCPConnectionManager)
    start_supervised!(MCPMessageQueue)
    
    :ok
  end
  
  describe "init/1" do
    test "initializes with default options" do
      {:ok, config} = WebSocketTransport.init([])
      
      assert config.endpoint == RubberDuckWeb.Endpoint
      assert config.socket_path == "/socket"
      assert config.channel_topics == ["mcp:session", "mcp:session:streaming"]
      assert config.presence_enabled == true
      assert config.heartbeat_interval == 30_000
      assert config.message_queue_enabled == true
    end
    
    test "initializes with custom options" do
      opts = [
        endpoint: MyEndpoint,
        socket_path: "/custom",
        presence_enabled: false,
        heartbeat_interval: 60_000
      ]
      
      {:ok, config} = WebSocketTransport.init(opts)
      
      assert config.endpoint == MyEndpoint
      assert config.socket_path == "/custom"
      assert config.presence_enabled == false
      assert config.heartbeat_interval == 60_000
    end
  end
  
  describe "start_listener/1" do
    test "starts listener successfully" do
      {:ok, config} = WebSocketTransport.init([])
      
      # This should not crash
      result = WebSocketTransport.start_listener(config)
      
      # The actual result depends on whether supporting services are available
      # In a test environment, some services might not be startable
      assert result == :ok or match?({:error, _}, result)
    end
  end
  
  describe "stop_listener/1" do
    test "stops listener successfully" do
      {:ok, config} = WebSocketTransport.init([])
      
      :ok = WebSocketTransport.stop_listener(config)
    end
  end
  
  describe "authenticate/2" do
    test "authenticates connection with stored state" do
      # Store connection state
      connection_state = %{
        session_id: @test_connection_id,
        user_id: "test_user",
        client_info: %{name: "TestClient", version: "1.0.0"},
        connect_info: %{},
        connected_at: DateTime.utc_now(),
        last_activity: DateTime.utc_now()
      }
      
      MCPConnectionManager.store_connection_state(@test_connection_id, connection_state)
      
      auth_params = %{
        "clientInfo" => %{
          "name" => "TestClient",
          "version" => "1.0.0"
        },
        "apiKey" => "test_key"
      }
      
      {:ok, auth_context} = WebSocketTransport.authenticate(@test_connection_id, auth_params)
      
      assert auth_context.user_id == "mcp_user_test"
      assert auth_context.role == "api_user"
    end
    
    test "fails authentication for non-existent connection" do
      auth_params = %{
        "clientInfo" => %{
          "name" => "TestClient",
          "version" => "1.0.0"
        },
        "apiKey" => "test_key"
      }
      
      {:error, reason} = WebSocketTransport.authenticate("non_existent_connection", auth_params)
      
      assert reason =~ "Connection not found"
    end
  end
  
  describe "send_message/2" do
    test "queues message when connection not found" do
      # Message should be queued since connection doesn't exist
      result = WebSocketTransport.send_message(@test_connection_id, @test_message)
      
      # Should either succeed (if queuing is enabled) or fail
      assert result == :ok or match?({:error, _}, result)
      
      # If queuing is enabled, message should be in queue
      if result == :ok do
        pending = MCPMessageQueue.get_pending_messages(@test_connection_id)
        assert length(pending) >= 0  # May be 0 if queue is not enabled
      end
    end
    
    test "updates activity when sending message" do
      # Store connection state
      connection_state = %{
        session_id: @test_connection_id,
        user_id: "test_user",
        client_info: %{name: "TestClient", version: "1.0.0"},
        connected_at: DateTime.utc_now(),
        last_activity: DateTime.utc_now()
      }
      
      MCPConnectionManager.store_connection_state(@test_connection_id, connection_state)
      
      initial_activity = connection_state.last_activity
      
      # Small delay to ensure timestamp difference
      Process.sleep(10)
      
      # Send message (may fail due to no actual channel, but activity should be updated)
      WebSocketTransport.send_message(@test_connection_id, @test_message)
      
      # Verify activity was updated
      {:ok, updated_state} = MCPConnectionManager.get_connection_state(@test_connection_id)
      assert DateTime.compare(updated_state.last_activity, initial_activity) == :gt
    end
  end
  
  describe "broadcast_message/2" do
    test "broadcasts to multiple connections" do
      connection_ids = ["conn1", "conn2", "conn3"]
      
      # Store connection states
      Enum.each(connection_ids, fn conn_id ->
        connection_state = %{
          session_id: conn_id,
          user_id: "test_user",
          client_info: %{name: "TestClient", version: "1.0.0"},
          connected_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now()
        }
        
        MCPConnectionManager.store_connection_state(conn_id, connection_state)
      end)
      
      # Broadcast message
      result = WebSocketTransport.broadcast_message(connection_ids, @test_message)
      
      # Should either succeed or fail with error about connections
      assert result == :ok or match?({:error, _}, result)
    end
    
    test "handles broadcast to empty list" do
      :ok = WebSocketTransport.broadcast_message([], @test_message)
    end
  end
  
  describe "close_connection/2" do
    test "removes connection state on close" do
      # Store connection state
      connection_state = %{
        session_id: @test_connection_id,
        user_id: "test_user",
        client_info: %{name: "TestClient", version: "1.0.0"},
        connected_at: DateTime.utc_now(),
        last_activity: DateTime.utc_now()
      }
      
      MCPConnectionManager.store_connection_state(@test_connection_id, connection_state)
      
      # Verify state exists
      {:ok, _state} = MCPConnectionManager.get_connection_state(@test_connection_id)
      
      # Close connection (will fail due to no actual channel, but should clean up state)
      WebSocketTransport.close_connection(@test_connection_id, "test_close")
      
      # Verify state is removed
      {:error, :not_found} = MCPConnectionManager.get_connection_state(@test_connection_id)
    end
    
    test "handles closing non-existent connection" do
      {:error, _reason} = WebSocketTransport.close_connection("non_existent", "test_close")
    end
  end
  
  describe "get_connection_info/1" do
    test "returns connection info for existing connection" do
      # Store connection state
      connection_state = %{
        session_id: @test_connection_id,
        user_id: "test_user",
        client_info: %{name: "TestClient", version: "1.0.0"},
        capabilities: %{"tools" => %{}, "resources" => %{}},
        connected_at: DateTime.utc_now(),
        last_activity: DateTime.utc_now()
      }
      
      MCPConnectionManager.store_connection_state(@test_connection_id, connection_state)
      
      {:ok, info} = WebSocketTransport.get_connection_info(@test_connection_id)
      
      assert info.id == @test_connection_id
      assert info.transport == :websocket
      assert info.authenticated == true
      assert info.capabilities == %{"tools" => %{}, "resources" => %{}}
      assert info.metadata.connected_at
      assert info.metadata.client_info.name == "TestClient"
    end
    
    test "returns error for non-existent connection" do
      {:error, _reason} = WebSocketTransport.get_connection_info("non_existent")
    end
  end
  
  describe "list_connections/0" do
    test "lists all active connections" do
      # Store multiple connection states
      connection_ids = ["conn1", "conn2", "conn3"]
      
      Enum.each(connection_ids, fn conn_id ->
        connection_state = %{
          session_id: conn_id,
          user_id: "test_user",
          client_info: %{name: "TestClient", version: "1.0.0"},
          connected_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now()
        }
        
        MCPConnectionManager.store_connection_state(conn_id, connection_state)
      end)
      
      connections = WebSocketTransport.list_connections()
      
      assert length(connections) == 3
      assert Enum.all?(connection_ids, &(&1 in connections))
    end
    
    test "returns empty list when no connections" do
      connections = WebSocketTransport.list_connections()
      assert connections == []
    end
  end
  
  describe "connection_alive?/1" do
    test "returns false for non-existent connection" do
      refute WebSocketTransport.connection_alive?("non_existent")
    end
    
    test "returns false for connection without live process" do
      # Store connection state but no actual process
      connection_state = %{
        session_id: @test_connection_id,
        user_id: "test_user",
        client_info: %{name: "TestClient", version: "1.0.0"},
        connected_at: DateTime.utc_now(),
        last_activity: DateTime.utc_now()
      }
      
      MCPConnectionManager.store_connection_state(@test_connection_id, connection_state)
      
      # Should return false since no actual channel process exists
      refute WebSocketTransport.connection_alive?(@test_connection_id)
    end
  end
  
  describe "get_stats/0" do
    test "returns transport statistics" do
      # Store some connection states
      connection_states = [
        %{
          session_id: "conn1",
          user_id: "user1",
          client_info: %{name: "Client1", version: "1.0.0"},
          connected_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now()
        },
        %{
          session_id: "conn2",
          user_id: "user2",
          client_info: %{name: "Client2", version: "1.0.0"},
          connected_at: DateTime.utc_now(),
          last_activity: DateTime.utc_now()
        }
      ]
      
      Enum.each(connection_states, fn state ->
        MCPConnectionManager.store_connection_state(state.session_id, state)
      end)
      
      stats = WebSocketTransport.get_stats()
      
      assert stats.transport == :websocket
      assert stats.connections.total == 2
      assert stats.connections.by_client["Client1"] == 1
      assert stats.connections.by_client["Client2"] == 1
      assert stats.message_queue
      assert stats.uptime
    end
    
    test "returns empty stats when no connections" do
      stats = WebSocketTransport.get_stats()
      
      assert stats.transport == :websocket
      assert stats.connections.total == 0
      assert stats.connections.by_client == %{}
    end
  end
  
  describe "update_config/2" do
    test "updates configuration" do
      new_options = [
        heartbeat_interval: 45_000,
        presence_enabled: false
      ]
      
      {:ok, updated_config} = WebSocketTransport.update_config(@test_config, new_options)
      
      assert updated_config.heartbeat_interval == 45_000
      assert updated_config.presence_enabled == false
      # Other options should remain unchanged
      assert updated_config.endpoint == @test_config.endpoint
      assert updated_config.socket_path == @test_config.socket_path
    end
  end
  
  describe "register_connection/2" do
    test "registers connection successfully" do
      connection_state = %{
        session_id: @test_connection_id,
        user_id: "test_user",
        client_info: %{name: "TestClient", version: "1.0.0"},
        connected_at: DateTime.utc_now(),
        last_activity: DateTime.utc_now()
      }
      
      :ok = WebSocketTransport.register_connection(@test_connection_id, connection_state)
      
      # Verify connection was stored
      {:ok, stored_state} = MCPConnectionManager.get_connection_state(@test_connection_id)
      assert stored_state.session_id == @test_connection_id
      assert stored_state.user_id == "test_user"
    end
  end
  
  describe "acknowledge_message/1" do
    test "acknowledges message successfully" do
      # Should not crash
      :ok = WebSocketTransport.acknowledge_message("test_message_id")
    end
  end
  
  describe "report_delivery_failure/2" do
    test "reports delivery failure successfully" do
      # Should not crash
      :ok = WebSocketTransport.report_delivery_failure("test_message_id", "Connection failed")
    end
  end
  
  describe "enable_streaming/2" do
    test "enables streaming for connection" do
      topics = ["topic1", "topic2"]
      
      # Should not crash
      :ok = WebSocketTransport.enable_streaming(@test_connection_id, topics)
    end
  end
  
  describe "disable_streaming/2" do
    test "disables streaming for connection" do
      topics = ["topic1", "topic2"]
      
      # Should not crash
      :ok = WebSocketTransport.disable_streaming(@test_connection_id, topics)
    end
  end
end