defmodule RubberDuckCore.ConversationTest do
  use ExUnit.Case, async: true

  alias RubberDuckCore.{Conversation, Message}

  describe "new/1" do
    test "creates a conversation with default values" do
      conversation = Conversation.new()
      
      assert conversation.id != nil
      assert conversation.title == nil
      assert conversation.status == :active
      assert conversation.messages == []
      assert conversation.context == %{}
      assert %DateTime{} = conversation.created_at
      assert %DateTime{} = conversation.updated_at
    end

    test "creates a conversation with provided attributes" do
      attrs = [
        id: "test-123",
        title: "Test Conversation",
        status: :paused,
        context: %{project: "test"}
      ]
      
      conversation = Conversation.new(attrs)
      
      assert conversation.id == "test-123"
      assert conversation.title == "Test Conversation"
      assert conversation.status == :paused
      assert conversation.context == %{project: "test"}
    end
  end

  describe "add_message/2" do
    test "adds a message to the conversation" do
      conversation = Conversation.new()
      message = Message.user("Hello")
      
      updated_conversation = Conversation.add_message(conversation, message)
      
      assert length(updated_conversation.messages) == 1
      assert hd(updated_conversation.messages) == message
      assert updated_conversation.updated_at != conversation.updated_at
    end
  end

  describe "update_status/2" do
    test "updates the conversation status" do
      conversation = Conversation.new()
      
      updated_conversation = Conversation.update_status(conversation, :completed)
      
      assert updated_conversation.status == :completed
      assert updated_conversation.updated_at != conversation.updated_at
    end
  end
end