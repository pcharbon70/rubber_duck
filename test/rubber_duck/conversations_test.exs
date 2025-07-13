defmodule RubberDuck.ConversationsTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Conversations

  describe "conversations" do
    test "can create a conversation" do
      user_id = Ash.UUID.generate()
      
      {:ok, conversation} = Conversations.create_conversation(%{
        user_id: user_id,
        title: "Test Conversation",
        status: :active
      })
      
      assert conversation.user_id == user_id
      assert conversation.title == "Test Conversation"
      assert conversation.status == :active
      assert conversation.message_count == 0
    end

    test "can create a message in a conversation" do
      user_id = Ash.UUID.generate()
      
      {:ok, conversation} = Conversations.create_conversation(%{
        user_id: user_id,
        title: "Test Conversation"
      })
      
      {:ok, message} = Conversations.create_message(%{
        conversation_id: conversation.id,
        role: :user,
        content: "Hello, world!",
        sequence_number: 1
      })
      
      assert message.conversation_id == conversation.id
      assert message.role == :user
      assert message.content == "Hello, world!"
      assert message.sequence_number == 1
    end

    test "can create conversation context" do
      user_id = Ash.UUID.generate()
      
      {:ok, conversation} = Conversations.create_conversation(%{
        user_id: user_id,
        title: "Test Conversation"
      })
      
      {:ok, context} = Conversations.create_context(%{
        conversation_id: conversation.id,
        conversation_type: :coding,
        context_window_size: 4000
      })
      
      assert context.conversation_id == conversation.id
      assert context.conversation_type == :coding
      assert context.context_window_size == 4000
    end

    test "can list conversations for a user" do
      user_id = Ash.UUID.generate()
      
      {:ok, _conversation1} = Conversations.create_conversation(%{
        user_id: user_id,
        title: "Conversation 1"
      })
      
      {:ok, _conversation2} = Conversations.create_conversation(%{
        user_id: user_id,
        title: "Conversation 2"
      })
      
      conversations = Conversations.list_user_conversations!(user_id: user_id)
      
      assert length(conversations) == 2
    end

    test "can get conversation messages" do
      user_id = Ash.UUID.generate()
      
      {:ok, conversation} = Conversations.create_conversation(%{
        user_id: user_id,
        title: "Test Conversation"
      })
      
      {:ok, _message1} = Conversations.create_message(%{
        conversation_id: conversation.id,
        role: :user,
        content: "First message",
        sequence_number: 1
      })
      
      {:ok, _message2} = Conversations.create_message(%{
        conversation_id: conversation.id,
        role: :assistant,
        content: "Second message",
        sequence_number: 2
      })
      
      messages = Conversations.list_conversation_messages!(conversation_id: conversation.id)
      
      assert length(messages) == 2
    end
  end
end