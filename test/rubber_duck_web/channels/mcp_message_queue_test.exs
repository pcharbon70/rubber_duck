defmodule RubberDuckWeb.MCPMessageQueueTest do
  use ExUnit.Case, async: true
  
  alias RubberDuckWeb.MCPMessageQueue
  
  @test_session_id "test_session_123"
  @test_payload %{
    "jsonrpc" => "2.0",
    "method" => "test/method",
    "params" => %{"data" => "test"}
  }
  
  setup do
    # Start the message queue
    start_supervised!(MCPMessageQueue)
    
    :ok
  end
  
  describe "enqueue_message/3" do
    test "enqueues message with default options" do
      {:ok, message_id} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload)
      
      assert is_binary(message_id)
      assert message_id =~ "msg_"
      
      # Verify message was enqueued
      messages = MCPMessageQueue.get_pending_messages(@test_session_id)
      assert length(messages) == 1
      
      message = hd(messages)
      assert message.id == message_id
      assert message.session_id == @test_session_id
      assert message.payload == @test_payload
      assert message.priority == :normal
      assert message.retry_count == 0
    end
    
    test "enqueues message with custom options" do
      opts = [priority: :high, ttl: 600, max_retries: 5]
      
      {:ok, message_id} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload, opts)
      
      messages = MCPMessageQueue.get_pending_messages(@test_session_id)
      message = hd(messages)
      
      assert message.priority == :high
      assert message.max_retries == 5
      assert message.expires_at
    end
    
    test "enqueues multiple messages for same session" do
      {:ok, _id1} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload)
      {:ok, _id2} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload)
      
      messages = MCPMessageQueue.get_pending_messages(@test_session_id)
      assert length(messages) == 2
    end
    
    test "enqueues messages for different sessions" do
      session1 = "session_1"
      session2 = "session_2"
      
      {:ok, _id1} = MCPMessageQueue.enqueue_message(session1, @test_payload)
      {:ok, _id2} = MCPMessageQueue.enqueue_message(session2, @test_payload)
      
      messages1 = MCPMessageQueue.get_pending_messages(session1)
      messages2 = MCPMessageQueue.get_pending_messages(session2)
      
      assert length(messages1) == 1
      assert length(messages2) == 1
    end
  end
  
  describe "dequeue_message/1" do
    test "dequeues message in priority order" do
      # Enqueue messages with different priorities
      {:ok, low_id} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload, priority: :low)
      {:ok, urgent_id} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload, priority: :urgent)
      {:ok, normal_id} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload, priority: :normal)
      
      # Dequeue should return urgent message first
      {:ok, message1} = MCPMessageQueue.dequeue_message(@test_session_id)
      assert message1.id == urgent_id
      assert message1.priority == :urgent
      
      # Then normal priority
      {:ok, message2} = MCPMessageQueue.dequeue_message(@test_session_id)
      assert message2.id == normal_id
      assert message2.priority == :normal
      
      # Then low priority
      {:ok, message3} = MCPMessageQueue.dequeue_message(@test_session_id)
      assert message3.id == low_id
      assert message3.priority == :low
    end
    
    test "returns empty when no messages for session" do
      {:error, :empty} = MCPMessageQueue.dequeue_message(@test_session_id)
    end
    
    test "only dequeues messages for specific session" do
      session1 = "session_1"
      session2 = "session_2"
      
      {:ok, id1} = MCPMessageQueue.enqueue_message(session1, @test_payload)
      {:ok, _id2} = MCPMessageQueue.enqueue_message(session2, @test_payload)
      
      {:ok, message} = MCPMessageQueue.dequeue_message(session1)
      assert message.id == id1
      assert message.session_id == session1
      
      # Session2 should still have its message
      {:ok, message2} = MCPMessageQueue.dequeue_message(session2)
      assert message2.session_id == session2
    end
    
    test "removes message from queue after dequeue" do
      {:ok, _id} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload)
      
      # Verify message is in queue
      messages = MCPMessageQueue.get_pending_messages(@test_session_id)
      assert length(messages) == 1
      
      # Dequeue message
      {:ok, _message} = MCPMessageQueue.dequeue_message(@test_session_id)
      
      # Verify message is no longer in queue
      messages = MCPMessageQueue.get_pending_messages(@test_session_id)
      assert length(messages) == 0
    end
    
    test "skips expired messages" do
      # Enqueue message with very short TTL
      {:ok, _expired_id} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload, ttl: 0)
      
      # Wait for expiration
      Process.sleep(10)
      
      # Dequeue should not return expired message
      {:error, :empty} = MCPMessageQueue.dequeue_message(@test_session_id)
    end
  end
  
  describe "acknowledge_message/1" do
    test "acknowledges message successfully" do
      {:ok, message_id} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload)
      
      # Acknowledge should not crash
      :ok = MCPMessageQueue.acknowledge_message(message_id)
    end
    
    test "handles acknowledgment of non-existent message" do
      # Should not crash
      :ok = MCPMessageQueue.acknowledge_message("non_existent_id")
    end
  end
  
  describe "report_delivery_failure/2" do
    test "increments retry count on failure" do
      {:ok, message_id} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload)
      
      # Dequeue message
      {:ok, message} = MCPMessageQueue.dequeue_message(@test_session_id)
      assert message.retry_count == 0
      
      # Report failure
      :ok = MCPMessageQueue.report_delivery_failure(message_id, "Connection failed")
      
      # Message should be requeued with incremented retry count
      {:ok, retried_message} = MCPMessageQueue.dequeue_message(@test_session_id)
      assert retried_message.retry_count == 1
      assert retried_message.last_error == "Connection failed"
    end
    
    test "moves message to dead letter queue after max retries" do
      {:ok, message_id} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload, max_retries: 2)
      
      # Fail message 3 times (should exceed max_retries)
      for i <- 1..3 do
        {:ok, _message} = MCPMessageQueue.dequeue_message(@test_session_id)
        :ok = MCPMessageQueue.report_delivery_failure(message_id, "Failure #{i}")
      end
      
      # Message should no longer be in main queue
      {:error, :empty} = MCPMessageQueue.dequeue_message(@test_session_id)
      
      # Message should be in dead letter queue
      dlq_messages = MCPMessageQueue.get_dead_letter_messages(@test_session_id)
      assert length(dlq_messages) == 1
      
      dlq_message = hd(dlq_messages)
      assert dlq_message.id == message_id
      assert dlq_message.retry_count == 3
    end
    
    test "handles failure report for non-existent message" do
      # Should not crash
      :ok = MCPMessageQueue.report_delivery_failure("non_existent_id", "Error")
    end
  end
  
  describe "get_pending_messages/1" do
    test "returns all pending messages for session" do
      {:ok, _id1} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload)
      {:ok, _id2} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload)
      
      messages = MCPMessageQueue.get_pending_messages(@test_session_id)
      assert length(messages) == 2
      
      # All messages should be for the same session
      Enum.each(messages, fn message ->
        assert message.session_id == @test_session_id
      end)
    end
    
    test "returns empty list for session with no messages" do
      messages = MCPMessageQueue.get_pending_messages(@test_session_id)
      assert messages == []
    end
    
    test "returns messages sorted by creation time" do
      {:ok, id1} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload)
      Process.sleep(10)
      {:ok, id2} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload)
      
      messages = MCPMessageQueue.get_pending_messages(@test_session_id)
      
      # Should be sorted by creation time
      assert hd(messages).id == id1
      assert Enum.at(messages, 1).id == id2
    end
  end
  
  describe "get_queue_stats/0" do
    test "returns queue statistics" do
      {:ok, _id1} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload, priority: :high)
      {:ok, _id2} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload, priority: :normal)
      {:ok, _id3} = MCPMessageQueue.enqueue_message("another_session", @test_payload, priority: :low)
      
      stats = MCPMessageQueue.get_queue_stats()
      
      assert stats.total_messages == 3
      assert stats.priority_counts[:high] == 1
      assert stats.priority_counts[:normal] == 1
      assert stats.priority_counts[:low] == 1
      assert stats.session_counts[@test_session_id] == 2
      assert stats.session_counts["another_session"] == 1
      assert stats.uptime
    end
    
    test "returns zero stats when queue is empty" do
      stats = MCPMessageQueue.get_queue_stats()
      
      assert stats.total_messages == 0
      assert stats.dead_letter_messages == 0
      assert stats.priority_counts == %{}
      assert stats.session_counts == %{}
    end
  end
  
  describe "purge_session_messages/1" do
    test "removes all messages for session" do
      {:ok, _id1} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload)
      {:ok, _id2} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload)
      {:ok, _id3} = MCPMessageQueue.enqueue_message("another_session", @test_payload)
      
      # Verify messages exist
      messages = MCPMessageQueue.get_pending_messages(@test_session_id)
      assert length(messages) == 2
      
      # Purge session messages
      :ok = MCPMessageQueue.purge_session_messages(@test_session_id)
      
      # Verify messages are gone
      messages = MCPMessageQueue.get_pending_messages(@test_session_id)
      assert length(messages) == 0
      
      # Other session should be unaffected
      other_messages = MCPMessageQueue.get_pending_messages("another_session")
      assert length(other_messages) == 1
    end
    
    test "handles purging non-existent session" do
      # Should not crash
      :ok = MCPMessageQueue.purge_session_messages("non_existent_session")
    end
  end
  
  describe "get_dead_letter_messages/1" do
    test "returns dead letter messages for session" do
      {:ok, message_id} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload, max_retries: 1)
      
      # Fail message to move to DLQ
      {:ok, _message} = MCPMessageQueue.dequeue_message(@test_session_id)
      :ok = MCPMessageQueue.report_delivery_failure(message_id, "Test failure")
      {:ok, _message} = MCPMessageQueue.dequeue_message(@test_session_id)
      :ok = MCPMessageQueue.report_delivery_failure(message_id, "Test failure 2")
      
      dlq_messages = MCPMessageQueue.get_dead_letter_messages(@test_session_id)
      assert length(dlq_messages) == 1
      
      dlq_message = hd(dlq_messages)
      assert dlq_message.id == message_id
      assert dlq_message.session_id == @test_session_id
    end
    
    test "returns empty list for session with no DLQ messages" do
      dlq_messages = MCPMessageQueue.get_dead_letter_messages(@test_session_id)
      assert dlq_messages == []
    end
  end
  
  describe "retry_dead_letter_message/1" do
    test "retries message from dead letter queue" do
      {:ok, message_id} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload, max_retries: 1)
      
      # Move message to DLQ
      {:ok, _message} = MCPMessageQueue.dequeue_message(@test_session_id)
      :ok = MCPMessageQueue.report_delivery_failure(message_id, "Test failure")
      {:ok, _message} = MCPMessageQueue.dequeue_message(@test_session_id)
      :ok = MCPMessageQueue.report_delivery_failure(message_id, "Test failure 2")
      
      # Verify message is in DLQ
      dlq_messages = MCPMessageQueue.get_dead_letter_messages(@test_session_id)
      assert length(dlq_messages) == 1
      
      # Retry message
      :ok = MCPMessageQueue.retry_dead_letter_message(message_id)
      
      # Message should be back in main queue
      {:ok, retried_message} = MCPMessageQueue.dequeue_message(@test_session_id)
      assert retried_message.id == message_id
      assert retried_message.retry_count == 0  # Reset
      assert retried_message.last_error == nil  # Reset
      
      # Message should be gone from DLQ
      dlq_messages = MCPMessageQueue.get_dead_letter_messages(@test_session_id)
      assert length(dlq_messages) == 0
    end
    
    test "handles retry of non-existent DLQ message" do
      {:error, :not_found} = MCPMessageQueue.retry_dead_letter_message("non_existent_id")
    end
  end
  
  describe "message expiration" do
    test "expired messages are cleaned up" do
      {:ok, _id} = MCPMessageQueue.enqueue_message(@test_session_id, @test_payload, ttl: 0)
      
      # Wait for expiration
      Process.sleep(10)
      
      # Trigger cleanup (this would normally be done by periodic cleanup)
      # We'll simulate by trying to dequeue - expired messages should be skipped
      {:error, :empty} = MCPMessageQueue.dequeue_message(@test_session_id)
    end
  end
end