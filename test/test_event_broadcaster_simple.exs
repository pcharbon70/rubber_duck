defmodule SimpleEventBroadcasterTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.EventBroadcasting.EventBroadcaster
  
  test "basic event broadcaster functionality" do
    # Start pg if not already started
    case :pg.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
    
    # Start EventBroadcaster
    {:ok, broadcaster_pid} = EventBroadcaster.start_link()
    
    # Test subscription
    assert :ok = EventBroadcaster.subscribe("test.topic")
    
    # Test broadcasting
    event = %{topic: "test.topic", payload: %{message: "hello"}}
    assert :ok = EventBroadcaster.broadcast_async(event)
    
    # Should receive the event
    assert_receive {:event, received_event}
    assert received_event.topic == "test.topic"
    assert received_event.payload.message == "hello"
    
    # Test stats
    stats = EventBroadcaster.get_stats()
    assert is_map(stats)
    assert stats.subscription_count >= 1
    
    # Cleanup
    GenServer.stop(broadcaster_pid)
  end
end