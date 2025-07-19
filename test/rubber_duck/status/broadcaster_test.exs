defmodule RubberDuck.Status.BroadcasterTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Status.Broadcaster
  alias RubberDuck.Status
  
  setup do
    # Subscribe to test topics for verification
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:test-conv:engine")
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:test-conv:tool")
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:system:info")
    
    # Capture logs for overflow testing
    :ok
  end
  
  describe "broadcast/4" do
    test "queues messages for broadcasting" do
      assert :ok = Broadcaster.broadcast("test-conv", :engine, "Processing request", %{model: "gpt-4"})
    end
    
    test "accepts nil conversation_id for system messages" do
      assert :ok = Broadcaster.broadcast(nil, :info, "System started", %{})
    end
  end
  
  describe "public API" do
    test "Status module provides convenience functions" do
      assert :ok = Status.engine("test-conv", "Starting engine", %{model: "gpt-4"})
      assert :ok = Status.tool("test-conv", "Running tool", %{name: "search"})
      assert :ok = Status.workflow("test-conv", "Workflow step 1", %{})
      assert :ok = Status.progress("test-conv", "50% complete", %{percent: 50})
      assert :ok = Status.error("test-conv", "An error occurred", %{code: "E001"})
      assert :ok = Status.info("test-conv", "Information", %{})
    end
  end
  
  describe "queue management" do
    test "processes messages in batches" do
      # Queue multiple messages
      for i <- 1..5 do
        Broadcaster.broadcast("test-conv", :tool, "Executing tool #{i}", %{index: i})
      end
      
      # Wait for batch processing
      Process.sleep(100)
      
      # Should receive all messages
      for i <- 1..5 do
        assert_receive {:status_update, %{
          text: "Executing tool " <> _,
          category: :tool,
          metadata: %{index: ^i}
        }}, 1000
      end
    end
    
    test "groups messages by conversation and category" do
      # Send messages to different topics
      Broadcaster.broadcast("test-conv", :engine, "Engine update", %{})
      Broadcaster.broadcast("test-conv", :tool, "Tool update", %{})
      Broadcaster.broadcast(nil, :info, "System update", %{})
      
      Process.sleep(100)
      
      # Verify each message went to correct topic
      assert_receive {:status_update, %{text: "Engine update", category: :engine}}, 1000
      assert_receive {:status_update, %{text: "Tool update", category: :tool}}, 1000
      assert_receive {:status_update, %{text: "System update", category: :info}}, 1000
    end
  end
  
  describe "queue overflow protection" do
    @tag capture_log: true
    test "drops messages when queue is full" do
      # Start a new broadcaster with tiny queue limit for testing
      {:ok, pid} = GenServer.start_link(Broadcaster, [queue_limit: 10, flush_interval: 10000])
      
      # Overflow the queue
      for i <- 1..20 do
        GenServer.cast(pid, {:queue_message, %{
          conversation_id: "overflow-test",
          category: :test,
          text: "Message #{i}",
          metadata: %{},
          timestamp: DateTime.utc_now()
        }})
      end
      
      # Give it a moment
      Process.sleep(10)
      
      # Check state - should have exactly 10 messages
      state = :sys.get_state(pid)
      assert state.queue_size == 10
      
      GenServer.stop(pid)
    end
  end
  
  describe "telemetry events" do
    test "emits telemetry for queue operations" do
      # Create a separate process to avoid channel messages
      test_pid = self()
      
      # Attach telemetry handler
      :telemetry.attach(
        "test-broadcaster-#{System.unique_integer()}",
        [:rubber_duck, :status, :broadcaster, :queue_depth],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )
      
      # Send to a different conversation to avoid our subscriptions
      Broadcaster.broadcast("telemetry-test", :engine, "Test", %{})
      
      # May receive broadcast messages first, so filter them out
      receive do
        {:telemetry, [:rubber_duck, :status, :broadcaster, :queue_depth], %{size: size}, %{}} ->
          assert size >= 0
        {:status_update, _} ->
          # Ignore broadcast messages
          flunk("Did not receive telemetry event")
      after
        1000 ->
          flunk("Timeout waiting for telemetry event")
      end
      
      :telemetry.detach("test-broadcaster-#{System.unique_integer()}")
    end
  end
  
  describe "performance" do
    @tag :performance
    test "handles high message volume without blocking" do
      # Measure time to queue 1000 messages
      start_time = System.monotonic_time(:microsecond)
      
      for i <- 1..1000 do
        Broadcaster.broadcast("perf-test", :progress, "Message #{i}", %{index: i})
      end
      
      end_time = System.monotonic_time(:microsecond)
      duration = end_time - start_time
      
      # Should complete very quickly (< 10ms for 1000 messages)
      assert duration < 10_000, "Took #{duration}μs to queue 1000 messages"
    end
  end
end