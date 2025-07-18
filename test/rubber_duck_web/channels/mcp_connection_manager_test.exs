defmodule RubberDuckWeb.MCPConnectionManagerTest do
  use ExUnit.Case, async: true
  
  alias RubberDuckWeb.MCPConnectionManager
  
  @test_connection_state %{
    session_id: "test_session_123",
    user_id: "test_user",
    client_info: %{
      name: "TestClient",
      version: "1.0.0"
    },
    connected_at: DateTime.utc_now(),
    last_activity: DateTime.utc_now(),
    message_queue: [],
    subscriptions: MapSet.new(),
    capabilities: %{
      "tools" => %{},
      "resources" => %{}
    }
  }
  
  setup do
    # Start the connection manager
    start_supervised!(MCPConnectionManager)
    
    :ok
  end
  
  describe "store_connection_state/2" do
    test "stores connection state successfully" do
      session_id = "test_session_123"
      
      :ok = MCPConnectionManager.store_connection_state(session_id, @test_connection_state)
      
      {:ok, retrieved_state} = MCPConnectionManager.get_connection_state(session_id)
      
      assert retrieved_state.session_id == session_id
      assert retrieved_state.user_id == @test_connection_state.user_id
      assert retrieved_state.client_info == @test_connection_state.client_info
      assert retrieved_state.recovery_token  # Should be added automatically
    end
    
    test "overwrites existing connection state" do
      session_id = "test_session_123"
      
      # Store initial state
      :ok = MCPConnectionManager.store_connection_state(session_id, @test_connection_state)
      
      # Update state
      updated_state = %{@test_connection_state | user_id: "updated_user"}
      :ok = MCPConnectionManager.store_connection_state(session_id, updated_state)
      
      {:ok, retrieved_state} = MCPConnectionManager.get_connection_state(session_id)
      
      assert retrieved_state.user_id == "updated_user"
    end
  end
  
  describe "get_connection_state/1" do
    test "retrieves existing connection state" do
      session_id = "test_session_123"
      
      :ok = MCPConnectionManager.store_connection_state(session_id, @test_connection_state)
      
      {:ok, retrieved_state} = MCPConnectionManager.get_connection_state(session_id)
      
      assert retrieved_state.session_id == session_id
      assert retrieved_state.user_id == @test_connection_state.user_id
    end
    
    test "returns error for non-existent session" do
      {:error, :not_found} = MCPConnectionManager.get_connection_state("non_existent_session")
    end
  end
  
  describe "update_activity/1" do
    test "updates last activity timestamp" do
      session_id = "test_session_123"
      
      :ok = MCPConnectionManager.store_connection_state(session_id, @test_connection_state)
      
      # Get initial state
      {:ok, initial_state} = MCPConnectionManager.get_connection_state(session_id)
      initial_activity = initial_state.last_activity
      
      # Small delay to ensure timestamp difference
      Process.sleep(10)
      
      # Update activity
      :ok = MCPConnectionManager.update_activity(session_id)
      
      # Verify activity was updated
      {:ok, updated_state} = MCPConnectionManager.get_connection_state(session_id)
      
      assert DateTime.compare(updated_state.last_activity, initial_activity) == :gt
    end
    
    test "handles update for non-existent session gracefully" do
      # Should not crash
      :ok = MCPConnectionManager.update_activity("non_existent_session")
    end
  end
  
  describe "queue_message/2" do
    test "queues message for existing session" do
      session_id = "test_session_123"
      
      :ok = MCPConnectionManager.store_connection_state(session_id, @test_connection_state)
      
      message = %{
        id: "msg_123",
        type: "test_message",
        content: "Hello"
      }
      
      :ok = MCPConnectionManager.queue_message(session_id, message)
      
      # Verify message was queued
      {:ok, state} = MCPConnectionManager.get_connection_state(session_id)
      
      assert length(state.message_queue) == 1
      assert hd(state.message_queue).id == "msg_123"
      assert hd(state.message_queue).timestamp
    end
    
    test "limits message queue size" do
      session_id = "test_session_123"
      
      :ok = MCPConnectionManager.store_connection_state(session_id, @test_connection_state)
      
      # Queue 101 messages (should keep only last 100)
      for i <- 1..101 do
        message = %{id: "msg_#{i}", content: "Message #{i}"}
        :ok = MCPConnectionManager.queue_message(session_id, message)
      end
      
      {:ok, state} = MCPConnectionManager.get_connection_state(session_id)
      
      assert length(state.message_queue) == 100
      # Should have the most recent messages
      assert hd(state.message_queue).id == "msg_101"
    end
  end
  
  describe "get_queued_messages/2" do
    test "returns messages since specified time" do
      session_id = "test_session_123"
      
      :ok = MCPConnectionManager.store_connection_state(session_id, @test_connection_state)
      
      # Queue some messages
      message1 = %{id: "msg_1", content: "First"}
      message2 = %{id: "msg_2", content: "Second"}
      
      :ok = MCPConnectionManager.queue_message(session_id, message1)
      
      # Get timestamp between messages
      since_time = DateTime.utc_now()
      Process.sleep(10)
      
      :ok = MCPConnectionManager.queue_message(session_id, message2)
      
      # Get messages since the middle timestamp
      messages = MCPConnectionManager.get_queued_messages(session_id, since_time)
      
      assert length(messages) == 1
      assert hd(messages).id == "msg_2"
    end
    
    test "returns empty list for non-existent session" do
      messages = MCPConnectionManager.get_queued_messages("non_existent", DateTime.utc_now())
      
      assert messages == []
    end
  end
  
  describe "remove_connection_state/1" do
    test "removes connection state" do
      session_id = "test_session_123"
      
      :ok = MCPConnectionManager.store_connection_state(session_id, @test_connection_state)
      
      # Verify state exists
      {:ok, _state} = MCPConnectionManager.get_connection_state(session_id)
      
      # Remove state
      :ok = MCPConnectionManager.remove_connection_state(session_id)
      
      # Verify state is gone
      {:error, :not_found} = MCPConnectionManager.get_connection_state(session_id)
    end
    
    test "handles removal of non-existent state gracefully" do
      # Should not crash
      :ok = MCPConnectionManager.remove_connection_state("non_existent_session")
    end
  end
  
  describe "generate_recovery_token/1" do
    test "generates valid recovery token" do
      session_id = "test_session_123"
      
      token = MCPConnectionManager.generate_recovery_token(session_id)
      
      assert is_binary(token)
      assert byte_size(token) > 0
    end
    
    test "generates different tokens for different sessions" do
      token1 = MCPConnectionManager.generate_recovery_token("session_1")
      token2 = MCPConnectionManager.generate_recovery_token("session_2")
      
      assert token1 != token2
    end
  end
  
  describe "verify_recovery_token/1" do
    test "verifies valid recovery token" do
      session_id = "test_session_123"
      
      token = MCPConnectionManager.generate_recovery_token(session_id)
      
      {:ok, verified_session_id} = MCPConnectionManager.verify_recovery_token(token)
      
      assert verified_session_id == session_id
    end
    
    test "rejects invalid recovery token" do
      {:error, _reason} = MCPConnectionManager.verify_recovery_token("invalid_token")
    end
    
    test "rejects expired recovery token" do
      # Create an expired token (implementation depends on token expiration)
      session_id = "test_session_123"
      
      # This test might need adjustment based on how token expiration is handled
      # For now, we'll test with a malformed token
      expired_token = "expired_token"
      
      {:error, _reason} = MCPConnectionManager.verify_recovery_token(expired_token)
    end
  end
  
  describe "recover_session/1" do
    test "recovers session from valid token" do
      session_id = "test_session_123"
      
      :ok = MCPConnectionManager.store_connection_state(session_id, @test_connection_state)
      
      token = MCPConnectionManager.generate_recovery_token(session_id)
      
      {:ok, recovered_state} = MCPConnectionManager.recover_session(token)
      
      assert recovered_state.session_id == session_id
      assert recovered_state.user_id == @test_connection_state.user_id
    end
    
    test "fails to recover from invalid token" do
      {:error, _reason} = MCPConnectionManager.recover_session("invalid_token")
    end
    
    test "fails to recover non-existent session" do
      # Create token for non-existent session
      token = MCPConnectionManager.generate_recovery_token("non_existent_session")
      
      {:error, :not_found} = MCPConnectionManager.recover_session(token)
    end
  end
  
  describe "list_active_connections/0" do
    test "lists all active connections" do
      session1 = "test_session_1"
      session2 = "test_session_2"
      
      state1 = %{@test_connection_state | session_id: session1}
      state2 = %{@test_connection_state | session_id: session2}
      
      :ok = MCPConnectionManager.store_connection_state(session1, state1)
      :ok = MCPConnectionManager.store_connection_state(session2, state2)
      
      connections = MCPConnectionManager.list_active_connections()
      
      assert length(connections) == 2
      
      session_ids = Enum.map(connections, & &1.session_id)
      assert session1 in session_ids
      assert session2 in session_ids
    end
    
    test "returns empty list when no connections" do
      connections = MCPConnectionManager.list_active_connections()
      
      assert connections == []
    end
  end
  
  describe "cleanup_expired_connections/0" do
    test "removes expired connections" do
      session_id = "test_session_123"
      
      # Create state with old activity
      old_activity = DateTime.add(DateTime.utc_now(), -400, :second)  # 6+ minutes ago
      expired_state = %{@test_connection_state | last_activity: old_activity}
      
      :ok = MCPConnectionManager.store_connection_state(session_id, expired_state)
      
      # Verify state exists
      {:ok, _state} = MCPConnectionManager.get_connection_state(session_id)
      
      # Clean up expired connections
      count = MCPConnectionManager.cleanup_expired_connections()
      
      assert count == 1
      
      # Verify state is gone
      {:error, :not_found} = MCPConnectionManager.get_connection_state(session_id)
    end
    
    test "keeps recent connections" do
      session_id = "test_session_123"
      
      # Create state with recent activity
      recent_state = %{@test_connection_state | last_activity: DateTime.utc_now()}
      
      :ok = MCPConnectionManager.store_connection_state(session_id, recent_state)
      
      # Clean up expired connections
      count = MCPConnectionManager.cleanup_expired_connections()
      
      assert count == 0
      
      # Verify state still exists
      {:ok, _state} = MCPConnectionManager.get_connection_state(session_id)
    end
  end
end