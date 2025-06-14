defmodule RubberDuck.EventBroadcasting.EventBroadcasterTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.EventBroadcasting.EventBroadcaster
  
  setup do
    # Start EventBroadcaster for each test
    {:ok, pid} = EventBroadcaster.start_link()
    
    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid)
      end
    end)
    
    %{broadcaster: pid}
  end
  
  describe "subscription management" do
    test "can subscribe to topic patterns" do
      assert :ok = EventBroadcaster.subscribe("provider.health.*")
      assert :ok = EventBroadcaster.subscribe("metrics.performance")
    end
    
    test "can unsubscribe from topics" do
      assert :ok = EventBroadcaster.subscribe("test.topic")
      assert :ok = EventBroadcaster.unsubscribe("test.topic")
    end
    
    test "subscription with acknowledgment requirements" do
      assert :ok = EventBroadcaster.subscribe("critical.events", ack_required: true)
      
      subscribers = EventBroadcaster.get_subscribers("critical.events")
      assert length(subscribers) == 1
      
      {_pid, subscription} = List.first(subscribers)
      assert subscription.ack_required == true
    end
    
    test "subscription with filter function" do
      filter_fn = fn event -> event.payload.severity == :high end
      assert :ok = EventBroadcaster.subscribe("filtered.events", filter_fn: filter_fn)
      
      subscribers = EventBroadcaster.get_subscribers("filtered.events")
      assert length(subscribers) == 1
      
      {_pid, subscription} = List.first(subscribers)
      assert is_function(subscription.filter_fn)
    end
  end
  
  describe "event broadcasting" do
    test "broadcasts events to subscribers" do
      EventBroadcaster.subscribe("test.broadcast")
      
      event = %{
        topic: "test.broadcast",
        payload: %{message: "hello"},
        priority: :normal
      }
      
      assert :ok = EventBroadcaster.broadcast(event)
      
      # Receive the event
      assert_receive {:event, received_event}
      assert received_event.topic == "test.broadcast"
      assert received_event.payload.message == "hello"
      assert received_event.priority == :normal
      assert is_binary(received_event.id)
      assert received_event.source_node == node()
    end
    
    test "async broadcasting" do
      EventBroadcaster.subscribe("async.test")
      
      event = %{
        topic: "async.test",
        payload: %{data: "async_data"}
      }
      
      assert :ok = EventBroadcaster.broadcast_async(event)
      
      # Receive the event
      assert_receive {:event, received_event}
      assert received_event.topic == "async.test"
      assert received_event.payload.data == "async_data"
    end
    
    test "wildcard topic matching" do
      EventBroadcaster.subscribe("provider.*")
      
      # Should match
      event1 = %{topic: "provider.health", payload: %{}}
      assert :ok = EventBroadcaster.broadcast_async(event1)
      assert_receive {:event, %{topic: "provider.health"}}
      
      # Should match
      event2 = %{topic: "provider.metrics", payload: %{}}
      assert :ok = EventBroadcaster.broadcast_async(event2)
      assert_receive {:event, %{topic: "provider.metrics"}}
      
      # Should not match
      event3 = %{topic: "cluster.health", payload: %{}}
      assert :ok = EventBroadcaster.broadcast_async(event3)
      refute_receive {:event, %{topic: "cluster.health"}}, 100
    end
    
    test "filtered event delivery" do
      filter_fn = fn event -> event.payload.level == :critical end
      EventBroadcaster.subscribe("alerts.*", filter_fn: filter_fn)
      
      # Should be delivered
      critical_event = %{
        topic: "alerts.system", 
        payload: %{level: :critical, message: "critical alert"}
      }
      assert :ok = EventBroadcaster.broadcast_async(critical_event)
      assert_receive {:event, %{payload: %{level: :critical}}}
      
      # Should not be delivered
      info_event = %{
        topic: "alerts.system", 
        payload: %{level: :info, message: "info alert"}
      }
      assert :ok = EventBroadcaster.broadcast_async(info_event)
      refute_receive {:event, %{payload: %{level: :info}}}, 100
    end
  end
  
  describe "acknowledgment handling" do
    test "acknowledgment-required broadcasting" do
      EventBroadcaster.subscribe("ack.test", ack_required: true)
      
      event = %{topic: "ack.test", payload: %{}}
      
      assert {:ok, :ack_pending} = EventBroadcaster.broadcast(event, ack_required: true)
      
      # Receive event and acknowledge
      assert_receive {:event, received_event}
      assert :ok = EventBroadcaster.acknowledge(received_event.id)
    end
    
    test "acknowledgment timeout handling" do
      EventBroadcaster.subscribe("timeout.test", ack_required: true)
      
      event = %{topic: "timeout.test", payload: %{}}
      
      assert {:ok, :ack_pending} = EventBroadcaster.broadcast(event, ack_required: true, timeout: 100)
      
      # Don't acknowledge - should timeout
      assert_receive {:event, _received_event}
      
      # Wait for timeout and check stats
      Process.sleep(150)
      stats = EventBroadcaster.get_stats()
      assert stats.pending_acks == 0  # Should be cleaned up after timeout
    end
  end
  
  describe "event history and persistence" do
    test "maintains event history" do
      event = %{topic: "history.test", payload: %{data: "test"}}
      assert :ok = EventBroadcaster.broadcast_async(event)
      
      history = EventBroadcaster.get_event_history(limit: 10)
      assert length(history) >= 1
      
      latest_event = List.first(history)
      assert latest_event.topic == "history.test"
      assert latest_event.payload.data == "test"
    end
    
    test "event history filtering by topic" do
      # Broadcast events with different topics
      assert :ok = EventBroadcaster.broadcast_async(%{topic: "filter.test1", payload: %{}})
      assert :ok = EventBroadcaster.broadcast_async(%{topic: "filter.test2", payload: %{}})
      assert :ok = EventBroadcaster.broadcast_async(%{topic: "other.topic", payload: %{}})
      
      # Get filtered history
      filtered_history = EventBroadcaster.get_event_history(topic: "filter.*", limit: 10)
      
      # Should only contain events matching the pattern
      assert length(filtered_history) == 2
      assert Enum.all?(filtered_history, fn event -> 
        String.starts_with?(event.topic, "filter.")
      end)
    end
  end
  
  describe "statistics and monitoring" do
    test "tracks broadcasting statistics" do
      initial_stats = EventBroadcaster.get_stats()
      
      EventBroadcaster.subscribe("stats.test")
      event = %{topic: "stats.test", payload: %{}}
      
      assert :ok = EventBroadcaster.broadcast_async(event)
      assert_receive {:event, _}
      
      updated_stats = EventBroadcaster.get_stats()
      assert updated_stats.events_sent > initial_stats.events_sent
      assert updated_stats.subscription_count >= 1
    end
    
    test "lists active subscribers" do
      EventBroadcaster.subscribe("subscriber.test1")
      EventBroadcaster.subscribe("subscriber.test2")
      
      all_subscribers = EventBroadcaster.get_subscribers()
      assert length(all_subscribers) >= 2
      
      specific_subscribers = EventBroadcaster.get_subscribers("subscriber.test1")
      assert length(specific_subscribers) == 1
    end
  end
  
  describe "process monitoring and cleanup" do
    test "removes subscriptions when subscriber process dies" do
      # Start a temporary process
      {:ok, temp_pid} = Task.start(fn -> 
        EventBroadcaster.subscribe("cleanup.test")
        Process.sleep(100)
      end)
      
      # Wait for subscription
      Process.sleep(50)
      
      initial_count = EventBroadcaster.get_stats().subscription_count
      
      # Kill the process
      Process.exit(temp_pid, :kill)
      Process.sleep(50)
      
      # Subscription should be cleaned up
      final_count = EventBroadcaster.get_stats().subscription_count
      assert final_count < initial_count
    end
  end
  
  describe "topic pattern matching" do
    test "exact topic matching" do
      EventBroadcaster.subscribe("exact.topic")
      
      # Should match
      assert :ok = EventBroadcaster.broadcast_async(%{topic: "exact.topic", payload: %{}})
      assert_receive {:event, %{topic: "exact.topic"}}
      
      # Should not match
      assert :ok = EventBroadcaster.broadcast_async(%{topic: "exact.topic.extra", payload: %{}})
      refute_receive {:event, %{topic: "exact.topic.extra"}}, 100
    end
    
    test "single wildcard matching" do
      EventBroadcaster.subscribe("wildcard.*")
      
      # Should match
      assert :ok = EventBroadcaster.broadcast_async(%{topic: "wildcard.test", payload: %{}})
      assert_receive {:event, %{topic: "wildcard.test"}}
      
      # Should not match multiple segments
      assert :ok = EventBroadcaster.broadcast_async(%{topic: "wildcard.test.extra", payload: %{}})
      refute_receive {:event, %{topic: "wildcard.test.extra"}}, 100
    end
    
    test "multiple wildcard patterns" do
      EventBroadcaster.subscribe("multi.*.pattern")
      
      # Should match
      assert :ok = EventBroadcaster.broadcast_async(%{topic: "multi.test.pattern", payload: %{}})
      assert_receive {:event, %{topic: "multi.test.pattern"}}
      
      # Should not match
      assert :ok = EventBroadcaster.broadcast_async(%{topic: "multi.test.wrong", payload: %{}})
      refute_receive {:event, %{topic: "multi.test.wrong"}}, 100
    end
  end
end