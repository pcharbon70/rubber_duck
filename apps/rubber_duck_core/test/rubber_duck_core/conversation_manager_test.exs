defmodule RubberDuckCore.ConversationManagerTest do
  use ExUnit.Case, async: true

  alias RubberDuckCore.{ConversationManager, Message}

  setup do
    # Start a test ConversationManager for each test
    name = :"test_manager_#{System.unique_integer()}"
    {:ok, pid} = ConversationManager.start_link(name: name)
    
    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)
    
    %{manager: name}
  end

  describe "conversation management" do
    test "creates a new conversation", %{manager: manager} do
      {:ok, conversation} = ConversationManager.create_conversation(manager)
      
      assert conversation.id != nil
      assert conversation.status == :active
      assert conversation.messages == []
    end

    test "creates a conversation with attributes", %{manager: manager} do
      attrs = [title: "Test Conversation", status: :paused]
      {:ok, conversation} = ConversationManager.create_conversation(manager, attrs)
      
      assert conversation.title == "Test Conversation"
      assert conversation.status == :paused
    end

    test "gets an existing conversation", %{manager: manager} do
      {:ok, conversation} = ConversationManager.create_conversation(manager)
      
      {:ok, retrieved} = ConversationManager.get_conversation(manager, conversation.id)
      
      assert retrieved.id == conversation.id
    end

    test "returns error for non-existent conversation", %{manager: manager} do
      result = ConversationManager.get_conversation(manager, "non-existent")
      
      assert result == {:error, :not_found}
    end

    test "lists all conversations", %{manager: manager} do
      {:ok, conv1} = ConversationManager.create_conversation(manager)
      {:ok, conv2} = ConversationManager.create_conversation(manager)
      
      {:ok, conversations} = ConversationManager.list_conversations(manager)
      
      assert length(conversations) == 2
      assert Enum.find(conversations, &(&1.id == conv1.id))
      assert Enum.find(conversations, &(&1.id == conv2.id))
    end
  end

  describe "message management" do
    test "adds a message to a conversation", %{manager: manager} do
      {:ok, conversation} = ConversationManager.create_conversation(manager)
      message = Message.user("Hello world")
      
      {:ok, updated_conversation} = ConversationManager.add_message(manager, conversation.id, message)
      
      assert length(updated_conversation.messages) == 1
      assert hd(updated_conversation.messages) == message
    end

    test "returns error when adding message to non-existent conversation", %{manager: manager} do
      message = Message.user("Hello")
      
      result = ConversationManager.add_message(manager, "non-existent", message)
      
      assert result == {:error, :conversation_not_found}
    end
  end

  describe "BaseServer behavior" do
    test "responds to ping", %{manager: manager} do
      result = GenServer.call({:via, Registry, {RubberDuckCore.Registry, manager}}, {:ping})
      
      assert result == :pong
    end
  end
end