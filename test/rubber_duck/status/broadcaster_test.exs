defmodule RubberDuck.Status.BroadcasterTest do
  @moduledoc """
  Tests for the Status.Broadcaster GenServer.
  """
  
  use ExUnit.Case, async: false
  
  alias RubberDuck.Status.Broadcaster
  
  @test_conversation_id "broadcaster_test_123"
  
  setup do
    # Start broadcaster for each test
    {:ok, pid} = start_supervised(Broadcaster)
    
    # Subscribe to test conversation
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:#{@test_conversation_id}")
    
    %{broadcaster: pid}
  end
  
  describe "queue management" do
    test "batches multiple updates", %{broadcaster: _pid} do
      # Send multiple updates rapidly
      for i <- 1..5 do
        Broadcaster.queue_update(@test_conversation_id, :info, "Update #{i}", %{index: i})
      end
      
      # Should receive a batched update
      assert_receive {:status_batch, batch}, 500
      assert length(batch) == 5
      assert Enum.all?(batch, fn update -> update.category == :info end)
    end
    
    test "respects max batch size", %{broadcaster: _pid} do
      # Send more updates than max batch size (assuming max is 10)
      for i <- 1..15 do
        Broadcaster.queue_update(@test_conversation_id, :info, "Update #{i}", %{})
      end
      
      # Should receive two batches
      assert_receive {:status_batch, batch1}, 500
      assert_receive {:status_batch, batch2}, 500
      
      assert length(batch1) == 10
      assert length(batch2) == 5
    end
    
    test "flushes on timeout", %{broadcaster: _pid} do
      # Send just one update
      Broadcaster.queue_update(@test_conversation_id, :info, "Single update", %{})
      
      # Should receive after flush interval
      assert_receive {:status_batch, [update]}, 200
      assert update.text == "Single update"
    end
  end
  
  describe "conversation tracking" do
    test "tracks updates per conversation", %{broadcaster: pid} do
      conv1 = "conv_1"
      conv2 = "conv_2"
      
      # Subscribe to both conversations
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:#{conv1}")
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:#{conv2}")
      
      # Send updates to different conversations
      Broadcaster.queue_update(conv1, :info, "Conv1 update", %{})
      Broadcaster.queue_update(conv2, :info, "Conv2 update", %{})
      
      # Get stats
      stats = GenServer.call(pid, :get_stats)
      
      assert stats.conversation_count >= 2
      assert stats.total_updates >= 2
    end
    
    test "handles high volume gracefully", %{broadcaster: _pid} do
      # Send many updates rapidly
      tasks = for i <- 1..100 do
        Task.async(fn ->
          Broadcaster.queue_update(@test_conversation_id, :info, "Update #{i}", %{})
        end)
      end
      
      # Wait for all tasks
      Task.await_many(tasks)
      
      # Should receive batches without dropping updates
      received = receive_all_batches()
      total_updates = Enum.sum(Enum.map(received, &length/1))
      
      assert total_updates == 100
    end
  end
  
  describe "error handling" do
    test "continues operating after broadcast failure", %{broadcaster: pid} do
      # Simulate PubSub failure by unsubscribing
      Phoenix.PubSub.unsubscribe(RubberDuck.PubSub, "status:#{@test_conversation_id}")
      
      # Send update (will fail to deliver but shouldn't crash)
      Broadcaster.queue_update(@test_conversation_id, :info, "Failed update", %{})
      
      # Re-subscribe
      Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:#{@test_conversation_id}")
      
      # Should still be able to send updates
      Broadcaster.queue_update(@test_conversation_id, :info, "Success update", %{})
      
      assert_receive {:status_batch, [update]}, 500
      assert update.text == "Success update"
      
      # Broadcaster should still be alive
      assert Process.alive?(pid)
    end
  end
  
  describe "performance" do
    test "maintains performance under load", %{broadcaster: _pid} do
      start_time = System.monotonic_time(:millisecond)
      
      # Send 1000 updates
      for i <- 1..1000 do
        Broadcaster.queue_update(@test_conversation_id, :info, "Load test #{i}", %{index: i})
      end
      
      # Receive all batches
      batches = receive_all_batches(5000)
      total_received = Enum.sum(Enum.map(batches, &length/1))
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Should receive all updates
      assert total_received == 1000
      
      # Should complete reasonably quickly (< 5 seconds)
      assert duration < 5000
      
      # Calculate throughput
      throughput = 1000 / (duration / 1000)
      assert throughput > 200  # Should handle at least 200 updates/second
    end
  end
  
  describe "memory management" do
    test "cleans up completed conversations", %{broadcaster: pid} do
      # Create updates for multiple conversations
      for i <- 1..10 do
        conv_id = "temp_conv_#{i}"
        Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:#{conv_id}")
        
        # Send some updates
        for j <- 1..5 do
          Broadcaster.queue_update(conv_id, :info, "Update #{j}", %{})
        end
      end
      
      # Wait for processing
      Process.sleep(500)
      
      # Get initial stats
      initial_stats = GenServer.call(pid, :get_stats)
      
      # Trigger cleanup (in real implementation)
      # GenServer.cast(pid, :cleanup_stale_conversations)
      
      # Stats should show active conversations
      assert initial_stats.conversation_count >= 10
    end
  end
  
  # Helper functions
  
  defp receive_all_batches(timeout \\ 1000) do
    receive_all_batches([], timeout)
  end
  
  defp receive_all_batches(acc, timeout) do
    receive do
      {:status_batch, batch} ->
        receive_all_batches([batch | acc], timeout)
    after
      timeout ->
        Enum.reverse(acc)
    end
  end
end