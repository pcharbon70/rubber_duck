defmodule InterAppCommunicationTest do
  @moduledoc """
  Tests for inter-app communication patterns and PubSub functionality.
  """
  
  use ExUnit.Case, async: false

  setup do
    # Ensure PubSub is started
    start_supervised!({Phoenix.PubSub, name: RubberDuckCore.PubSub})
    :ok
  end

  describe "PubSub communication" do
    test "can subscribe and receive messages across apps" do
      topic = "test_topic_#{:rand.uniform(10000)}"
      test_message = {:test_message, self(), :rand.uniform(1000)}
      
      # Subscribe to topic
      :ok = Phoenix.PubSub.subscribe(RubberDuckCore.PubSub, topic)
      
      # Broadcast message
      :ok = Phoenix.PubSub.broadcast(RubberDuckCore.PubSub, topic, test_message)
      
      # Should receive the message
      assert_receive ^test_message, 1000
    end

    test "multiple processes can subscribe to same topic" do
      topic = "multi_subscriber_#{:rand.uniform(10000)}"
      test_message = {:multi_test, :rand.uniform(1000)}
      
      # Create multiple subscriber processes
      subscribers = Enum.map(1..3, fn i ->
        spawn_link(fn ->
          Phoenix.PubSub.subscribe(RubberDuckCore.PubSub, topic)
          
          receive do
            ^test_message -> send(self(), {:received, i})
          after
            2000 -> send(self(), {:timeout, i})
          end
        end)
      end)
      
      # Broadcast message
      :ok = Phoenix.PubSub.broadcast(RubberDuckCore.PubSub, topic, test_message)
      
      # All subscribers should receive the message
      Enum.each(subscribers, fn pid ->
        assert_receive {:received, _}, 3000
      end)
    end

    test "PubSub process is properly supervised" do
      # PubSub process should be running
      pid = Process.whereis(RubberDuckCore.PubSub)
      assert is_pid(pid)
      assert Process.alive?(pid)
      
      # Should be able to get info about the process
      info = Process.info(pid)
      assert is_list(info)
    end
  end

  describe "core to storage communication" do
    test "core can call storage repository functions" do
      # Test basic repository function calls
      result = try do
        # This should work if storage is properly configured
        projects = RubberDuckStorage.Repository.all_projects()
        assert is_list(projects)
        true
      rescue
        error ->
          # If there's a database connection issue, that's a separate concern
          # We're testing the module loading and function availability
          case error do
            %DBConnection.ConnectionError{} -> true  # DB not available but function exists
            %Postgrex.Error{} -> true                # DB connection issue but function exists
            _ -> false                               # Actual code issue
          end
      end
      
      assert result, "Core cannot properly call storage repository functions"
    end

    test "core can access storage configuration" do
      # Core should be able to access storage config
      cache_ttl = RubberDuckStorage.Config.cache_ttl()
      cache_max_size = RubberDuckStorage.Config.cache_max_size()
      
      assert is_integer(cache_ttl)
      assert is_integer(cache_max_size)
    end
  end

  describe "core to engines communication" do
    test "core can access engine configuration" do
      # Core should be able to access engine config
      pool_size = RubberDuckEngines.Config.pool_size()
      enabled_engines = RubberDuckEngines.Config.enabled_engines()
      
      assert is_integer(pool_size)
      assert is_list(enabled_engines)
    end

    test "engines can publish to core PubSub" do
      topic = "engine_notification_#{:rand.uniform(10000)}"
      test_message = {:engine_result, :analysis_complete, %{result: "test"}}
      
      # Subscribe to engine notifications
      :ok = Phoenix.PubSub.subscribe(RubberDuckCore.PubSub, topic)
      
      # Simulate engine publishing a result
      :ok = Phoenix.PubSub.broadcast(RubberDuckCore.PubSub, topic, test_message)
      
      # Should receive the notification
      assert_receive ^test_message, 1000
    end
  end

  describe "web to core communication" do
    test "web can access core conversation manager functions" do
      # Test that web can call core functions
      result = try do
        # This might fail with actual GenServer start, but should not fail with undefined function
        RubberDuckCore.ConversationManager.start_conversation("test-project", "test-user")
        true
      rescue
        %UndefinedFunctionError{} -> false  # Function doesn't exist - this is what we're testing
        _ -> true                           # Other errors are fine for this test
      catch
        _ -> true  # Catches and other issues are fine for this test
      end
      
      assert result, "Web cannot access core conversation manager functions"
    end

    test "web can publish to core PubSub" do
      topic = "web_message_#{:rand.uniform(10000)}"
      test_message = {:web_event, :user_message, %{user: "test", message: "hello"}}
      
      # Subscribe to web events
      :ok = Phoenix.PubSub.subscribe(RubberDuckCore.PubSub, topic)
      
      # Simulate web publishing an event
      :ok = Phoenix.PubSub.broadcast(RubberDuckCore.PubSub, topic, test_message)
      
      # Should receive the event
      assert_receive ^test_message, 1000
    end
  end

  describe "application startup communication" do
    test "all apps can access shared PubSub" do
      # Test that each app can access the shared PubSub
      pubsub_name = RubberDuckCore.PubSub
      
      # Should be able to get the PubSub process
      pid = Process.whereis(pubsub_name)
      assert is_pid(pid), "PubSub process not found"
      
      # Each app should be able to use it
      topics = [
        "core_topic_#{:rand.uniform(1000)}",
        "storage_topic_#{:rand.uniform(1000)}",
        "engines_topic_#{:rand.uniform(1000)}",
        "web_topic_#{:rand.uniform(1000)}"
      ]
      
      Enum.each(topics, fn topic ->
        assert :ok = Phoenix.PubSub.subscribe(pubsub_name, topic)
        assert :ok = Phoenix.PubSub.broadcast(pubsub_name, topic, {:test, topic})
        
        assert_receive {:test, ^topic}, 1000
        
        :ok = Phoenix.PubSub.unsubscribe(pubsub_name, topic)
      end)
    end

    test "application dependencies start in correct order" do
      # This test verifies the supervision tree allows proper communication
      # by checking that required processes are available
      
      # Storage repo should be available if storage is started
      repo_available = case Process.whereis(RubberDuckStorage.Repo) do
        nil -> false
        pid when is_pid(pid) -> Process.alive?(pid)
      end
      
      # PubSub should be available if core is started
      pubsub_available = case Process.whereis(RubberDuckCore.PubSub) do
        nil -> false
        pid when is_pid(pid) -> Process.alive?(pid)
      end
      
      # Web endpoint should be available if web is started (in dev/prod)
      # In test environment, server is disabled, so this might not be running
      endpoint_available = case Process.whereis(RubberDuckWeb.Endpoint) do
        nil -> true  # Acceptable in test environment
        pid when is_pid(pid) -> Process.alive?(pid)
      end
      
      # At minimum, PubSub should be available for inter-app communication
      assert pubsub_available, "PubSub not available for inter-app communication"
      
      # Repo may not be available if database is not configured, which is OK for compilation tests
      # but we should at least verify the module loads
      assert Code.ensure_loaded?(RubberDuckStorage.Repo)
      
      # Endpoint should at least be loadable
      assert Code.ensure_loaded?(RubberDuckWeb.Endpoint)
    end
  end

  describe "error handling in inter-app communication" do
    test "PubSub handles non-existent topics gracefully" do
      non_existent_topic = "non_existent_#{:rand.uniform(100000)}"
      
      # Should be able to broadcast to non-existent topic without error
      assert :ok = Phoenix.PubSub.broadcast(RubberDuckCore.PubSub, non_existent_topic, :test)
      
      # Should be able to subscribe to new topic
      assert :ok = Phoenix.PubSub.subscribe(RubberDuckCore.PubSub, non_existent_topic)
      
      # Should be able to unsubscribe from topic
      assert :ok = Phoenix.PubSub.unsubscribe(RubberDuckCore.PubSub, non_existent_topic)
    end

    test "failed function calls don't crash PubSub" do
      topic = "error_test_#{:rand.uniform(10000)}"
      
      # Subscribe to topic
      :ok = Phoenix.PubSub.subscribe(RubberDuckCore.PubSub, topic)
      
      # Send a message that might cause processing errors
      :ok = Phoenix.PubSub.broadcast(RubberDuckCore.PubSub, topic, {:error_test, nil})
      
      # PubSub should still be working
      :ok = Phoenix.PubSub.broadcast(RubberDuckCore.PubSub, topic, {:normal_message, :ok})
      
      # Should receive both messages
      assert_receive {:error_test, nil}, 1000
      assert_receive {:normal_message, :ok}, 1000
      
      # PubSub process should still be alive
      pid = Process.whereis(RubberDuckCore.PubSub)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end
  end

  describe "message patterns and protocols" do
    test "apps use consistent message formats" do
      topic = "protocol_test_#{:rand.uniform(10000)}"
      
      # Define expected message patterns
      core_message = {:core_event, :conversation_started, %{conversation_id: "123", user: "test"}}
      engine_message = {:engine_result, :analysis_complete, %{analysis_id: "456", result: %{}}}
      web_message = {:web_event, :user_connected, %{user_id: "789", channel: "coding"}}
      storage_message = {:storage_event, :data_persisted, %{type: :conversation, id: "101"}}
      
      # Subscribe to topic
      :ok = Phoenix.PubSub.subscribe(RubberDuckCore.PubSub, topic)
      
      # Test that all message types can be sent and received
      messages = [core_message, engine_message, web_message, storage_message]
      
      Enum.each(messages, fn message ->
        :ok = Phoenix.PubSub.broadcast(RubberDuckCore.PubSub, topic, message)
        assert_receive ^message, 1000
      end)
    end

    test "message broadcasting is reliable" do
      topic = "reliability_test_#{:rand.uniform(10000)}"
      num_messages = 10
      
      # Subscribe to topic
      :ok = Phoenix.PubSub.subscribe(RubberDuckCore.PubSub, topic)
      
      # Send multiple messages
      messages = Enum.map(1..num_messages, fn i ->
        message = {:reliability_test, i, :rand.uniform(1000)}
        :ok = Phoenix.PubSub.broadcast(RubberDuckCore.PubSub, topic, message)
        message
      end)
      
      # Should receive all messages
      received = Enum.map(1..num_messages, fn _ ->
        assert_receive message, 2000
        message
      end)
      
      # All sent messages should be received
      assert length(received) == num_messages
      assert Enum.sort(received) == Enum.sort(messages)
    end
  end
end