defmodule RubberDuckWeb.StatusChannelSimpleTest do
  use ExUnit.Case
  
  alias RubberDuck.Status.Broadcaster
  alias Phoenix.PubSub
  
  describe "status broadcaster integration" do
    test "broadcaster sends messages to correct topics" do
      # Start the broadcaster if not started
      case Process.whereis(RubberDuck.Status.Broadcaster) do
        nil -> {:ok, _} = Broadcaster.start_link([])
        _ -> :ok
      end
      
      # Subscribe to a topic
      conversation_id = "test-conversation-123"
      category = :engine
      topic = "status:#{conversation_id}:#{category}"
      
      PubSub.subscribe(RubberDuck.PubSub, topic)
      
      # Broadcast a status update
      Broadcaster.broadcast(conversation_id, category, "Test message", %{foo: "bar"})
      
      # Wait for the message (broadcaster is async)
      assert_receive {:status_update, :engine, "Test message", %{foo: "bar"}}, 1000
    end
    
    test "broadcaster handles system messages" do
      # Start the broadcaster if not started
      case Process.whereis(RubberDuck.Status.Broadcaster) do
        nil -> {:ok, _} = Broadcaster.start_link([])
        _ -> :ok
      end
      
      # Subscribe to system topic
      category = :info
      topic = "status:system:#{category}"
      
      PubSub.subscribe(RubberDuck.PubSub, topic)
      
      # Broadcast a system status update
      Broadcaster.broadcast(nil, category, "System message", %{})
      
      # Wait for the message
      assert_receive {:status_update, :info, "System message", %{}}, 1000
    end
  end
end