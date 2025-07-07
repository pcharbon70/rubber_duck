defmodule RubberDuck.Plugin.MessageBusTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Plugin.MessageBus

  describe "pub/sub functionality" do
    test "subscribes to topics" do
      assert :ok = MessageBus.subscribe(:test_topic)

      topics = MessageBus.list_topics()
      assert {:test_topic, 1} in topics
    end

    test "publishes messages to subscribers" do
      MessageBus.subscribe(:test_topic, :my_tag)
      MessageBus.publish(:test_topic, "Hello, World!")

      assert_receive {:plugin_message, :test_topic, "Hello, World!", metadata}
      assert is_map(metadata)
      assert Map.has_key?(metadata, :timestamp)
    end

    test "multiple subscribers receive messages" do
      # Subscribe from multiple processes
      parent = self()

      pid1 =
        spawn(fn ->
          MessageBus.subscribe(:multi_topic)
          send(parent, {:subscribed, 1})

          receive do
            {:plugin_message, _, msg, _} -> send(parent, {:received, 1, msg})
          end
        end)

      pid2 =
        spawn(fn ->
          MessageBus.subscribe(:multi_topic)
          send(parent, {:subscribed, 2})

          receive do
            {:plugin_message, _, msg, _} -> send(parent, {:received, 2, msg})
          end
        end)

      # Wait for subscriptions
      assert_receive {:subscribed, 1}
      assert_receive {:subscribed, 2}

      # Publish message
      MessageBus.publish(:multi_topic, "broadcast")

      # Both should receive
      assert_receive {:received, 1, "broadcast"}
      assert_receive {:received, 2, "broadcast"}
    end

    test "unsubscribes from topics" do
      MessageBus.subscribe(:unsub_topic)
      assert {:unsub_topic, 1} in MessageBus.list_topics()

      MessageBus.unsubscribe(:unsub_topic)
      topics = MessageBus.list_topics()
      refute Enum.any?(topics, fn {topic, _count} -> topic == :unsub_topic end)
    end

    test "cleans up when subscriber process dies" do
      pid =
        spawn(fn ->
          MessageBus.subscribe(:cleanup_topic)

          receive do
            :block -> :infinity
          end
        end)

      # Ensure subscription is registered
      Process.sleep(50)
      assert {:cleanup_topic, 1} in MessageBus.list_topics()

      # Kill the process
      Process.exit(pid, :kill)
      Process.sleep(50)

      # Topic should be cleaned up
      topics = MessageBus.list_topics()
      refute Enum.any?(topics, fn {topic, _count} -> topic == :cleanup_topic end)
    end
  end

  describe "request/response functionality" do
    test "sends request and receives response" do
      # Set up handler
      MessageBus.handle_requests(:echo_service, fn request, _metadata ->
        {:echoed, request}
      end)

      # Send request
      assert {:ok, {:echoed, "hello"}} = MessageBus.request(:echo_service, "hello")
    end

    test "handles request timeout" do
      # No handler registered
      assert {:error, :timeout} = MessageBus.request(:no_handler, "data", 100)
    end

    test "handler errors are caught" do
      # Set up failing handler
      MessageBus.handle_requests(:error_service, fn _request, _metadata ->
        raise "Handler error"
      end)

      assert {:ok, {:error, :handler_error}} = MessageBus.request(:error_service, "data")
    end
  end

  describe "topic management" do
    test "lists all active topics with subscriber counts" do
      MessageBus.subscribe(:topic1)
      MessageBus.subscribe(:topic2)

      spawn(fn ->
        MessageBus.subscribe(:topic1)
        Process.sleep(:infinity)
      end)

      Process.sleep(50)

      topics = MessageBus.list_topics()
      assert length(topics) >= 2

      topic_map = Map.new(topics)
      assert topic_map[:topic1] == 2
      assert topic_map[:topic2] == 1
    end
  end
end
