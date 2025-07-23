defmodule RubberDuckWeb.StatusChannelTest do
  @moduledoc """
  Tests for the StatusChannel WebSocket functionality.
  """

  use RubberDuckWeb.ChannelCase

  alias RubberDuckWeb.StatusChannel
  alias RubberDuck.Status

  @test_conversation_id "channel_test_456"
  @test_user_id "user_789"

  setup do
    # Start status broadcaster
    start_supervised!(Status.Broadcaster)

    # Create socket
    {:ok, socket} = connect(RubberDuckWeb.UserSocket, %{"user_id" => @test_user_id})

    %{socket: socket}
  end

  describe "channel join" do
    test "joins successfully with valid conversation ID", %{socket: socket} do
      assert {:ok, reply, _socket} =
               subscribe_and_join(socket, StatusChannel, "status:#{@test_conversation_id}")

      assert reply == %{status: "joined", categories: StatusChannel.valid_categories()}
    end

    test "joins system status channel", %{socket: socket} do
      assert {:ok, reply, _socket} =
               subscribe_and_join(socket, StatusChannel, "status:system")

      assert reply == %{status: "joined", categories: StatusChannel.valid_categories()}
    end

    test "rejects invalid topic format", %{socket: socket} do
      assert {:error, %{reason: "invalid_topic"}} =
               subscribe_and_join(socket, StatusChannel, "invalid:topic:format")
    end
  end

  describe "status updates" do
    setup %{socket: socket} do
      {:ok, _, socket} = subscribe_and_join(socket, StatusChannel, "status:#{@test_conversation_id}")
      %{channel_socket: socket}
    end

    test "receives status updates for conversation", %{channel_socket: _socket} do
      # Send status update
      Status.info(@test_conversation_id, "Test update", %{source: "test"})

      # Should receive through channel
      assert_push("status_update", %{
        category: "info",
        text: "Test update",
        metadata: metadata
      })

      assert metadata.source == "test"
      assert metadata.timestamp
    end

    test "receives batched updates", %{channel_socket: _socket} do
      # Send multiple updates rapidly
      for i <- 1..3 do
        Status.info(@test_conversation_id, "Update #{i}", %{index: i})
      end

      # Should receive batch
      assert_push("status_batch", %{updates: updates})
      assert length(updates) == 3

      # Verify update order
      assert Enum.at(updates, 0).metadata.index == 1
      assert Enum.at(updates, 1).metadata.index == 2
      assert Enum.at(updates, 2).metadata.index == 3
    end

    test "does not receive updates for other conversations", %{channel_socket: _socket} do
      # Send to different conversation
      Status.info("other_conversation", "Should not receive", %{})

      # Should not receive
      refute_push("status_update", %{text: "Should not receive"}, 500)
    end
  end

  describe "category filtering" do
    setup %{socket: socket} do
      {:ok, _, socket} = subscribe_and_join(socket, StatusChannel, "status:#{@test_conversation_id}")
      %{channel_socket: socket}
    end

    test "updates subscription categories", %{channel_socket: socket} do
      # Update to only receive errors and warnings
      ref = push(socket, "update_subscription", %{"categories" => ["error", "warning"]})

      assert_reply(ref, :ok, %{subscribed_categories: categories})
      assert categories == ["error", "warning"]

      # Send various updates
      Status.info(@test_conversation_id, "Info msg", %{})
      Status.warning(@test_conversation_id, "Warning msg", %{})
      Status.error(@test_conversation_id, "Error msg", %{})

      # Should only receive warning and error
      assert_push("status_update", %{category: "warning", text: "Warning msg"})
      assert_push("status_update", %{category: "error", text: "Error msg"})
      refute_push("status_update", %{category: "info"}, 100)
    end

    test "validates category names", %{channel_socket: socket} do
      # Try invalid categories
      ref = push(socket, "update_subscription", %{"categories" => ["invalid", "error"]})

      assert_reply(ref, :error, %{reason: "invalid_categories", invalid: ["invalid"]})
    end

    test "empty categories means all categories", %{channel_socket: socket} do
      # Set empty array
      ref = push(socket, "update_subscription", %{"categories" => []})

      assert_reply(ref, :ok, %{subscribed_categories: categories})
      assert categories == StatusChannel.valid_categories()
    end
  end

  describe "presence tracking" do
    setup %{socket: socket} do
      {:ok, _, socket} = subscribe_and_join(socket, StatusChannel, "status:#{@test_conversation_id}")
      %{channel_socket: socket}
    end

    test "tracks user presence", %{channel_socket: _socket} do
      # Should receive presence state after join
      assert_push("presence_state", state)

      # Should have our user
      assert Map.has_key?(state, @test_user_id)
    end

    test "broadcasts presence changes", %{socket: socket} do
      {:ok, _, socket1} = subscribe_and_join(socket, StatusChannel, "status:#{@test_conversation_id}")

      # Create another connection
      {:ok, socket2} = connect(RubberDuckWeb.UserSocket, %{"user_id" => "user2"})
      {:ok, _, _socket2} = subscribe_and_join(socket2, StatusChannel, "status:#{@test_conversation_id}")

      # Should receive presence_diff
      assert_push("presence_diff", %{
        joins: joins,
        leaves: leaves
      })

      assert Map.has_key?(joins, "user2")
      assert leaves == %{}
    end
  end

  describe "rate limiting" do
    setup %{socket: socket} do
      {:ok, _, socket} = subscribe_and_join(socket, StatusChannel, "status:#{@test_conversation_id}")
      %{channel_socket: socket}
    end

    test "enforces rate limits on subscription updates", %{channel_socket: socket} do
      # Make many rapid subscription updates
      for i <- 1..15 do
        push(socket, "update_subscription", %{"categories" => ["info"]})
      end

      # Should eventually get rate limited
      ref = push(socket, "update_subscription", %{"categories" => ["error"]})
      assert_reply(ref, :error, %{reason: "rate_limited"})
    end
  end

  describe "error handling" do
    setup %{socket: socket} do
      {:ok, _, socket} = subscribe_and_join(socket, StatusChannel, "status:#{@test_conversation_id}")
      %{channel_socket: socket}
    end

    test "handles malformed messages gracefully", %{channel_socket: socket} do
      # Send malformed update subscription
      ref = push(socket, "update_subscription", %{"wrong_key" => "value"})
      assert_reply(ref, :error, %{reason: _})

      # Channel should still work
      Status.info(@test_conversation_id, "Still working", %{})
      assert_push("status_update", %{text: "Still working"})
    end
  end

  describe "system status channel" do
    setup %{socket: socket} do
      {:ok, _, socket} = subscribe_and_join(socket, StatusChannel, "status:system")
      %{channel_socket: socket}
    end

    test "receives system-wide status updates", %{channel_socket: _socket} do
      # Send system status (nil conversation_id)
      Status.error(nil, "System error", %{component: "database"})

      # Should receive through system channel
      assert_push("status_update", %{
        category: "error",
        text: "System error",
        metadata: %{component: "database"}
      })
    end
  end
end
