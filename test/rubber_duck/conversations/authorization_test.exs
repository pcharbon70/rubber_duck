defmodule RubberDuck.Conversations.AuthorizationTest do
  use RubberDuck.DataCase, async: true
  
  alias RubberDuck.Conversations
  alias RubberDuck.Conversations.Conversation
  alias RubberDuck.Accounts
  alias Ash.Error.Forbidden
  
  setup do
    # Create two test users
    # Use the register_with_password action to create users
    {:ok, user1} = Ash.create(Accounts.User, %{
      username: "user1_#{System.unique_integer([:positive])}",
      email: "user1_#{System.unique_integer([:positive])}@example.com",
      password: "password123",
      password_confirmation: "password123"
    }, action: :register_with_password, authorize?: false)
    
    {:ok, user2} = Ash.create(Accounts.User, %{
      username: "user2_#{System.unique_integer([:positive])}",
      email: "user2_#{System.unique_integer([:positive])}@example.com", 
      password: "password123",
      password_confirmation: "password123"
    }, action: :register_with_password, authorize?: false)
    
    %{user1: user1, user2: user2}
  end
  
  describe "conversation authorization" do
    test "users can create conversations", %{user1: user} do
      attrs = %{
        title: "Test Conversation",
        user_id: user.id,
        metadata: %{"test" => true}
      }
      
      assert {:ok, conversation} = Conversations.create_conversation(attrs, actor: user)
      assert conversation.user_id == user.id
      assert conversation.title == "Test Conversation"
    end
    
    test "users cannot create conversations for other users", %{user1: user1, user2: user2} do
      attrs = %{
        title: "Test Conversation",
        user_id: user2.id, # Trying to create for user2
        metadata: %{"test" => true}
      }
      
      # Should create but with user1's ID (enforced by change in action)
      assert {:ok, conversation} = Conversations.create_conversation(attrs, actor: user1)
      assert conversation.user_id == user1.id
    end
    
    test "users can read their own conversations", %{user1: user} do
      # Create a conversation
      {:ok, conversation} = Conversations.create_conversation(%{
        title: "My Conversation",
        user_id: user.id
      }, actor: user)
      
      # User should be able to read it
      assert {:ok, fetched} = Conversations.get_conversation(conversation.id, actor: user)
      assert fetched.id == conversation.id
    end
    
    test "users cannot read other users' conversations", %{user1: user1, user2: user2} do
      # Create a conversation for user1
      {:ok, conversation} = Conversations.create_conversation(%{
        title: "User1's Private Conversation",
        user_id: user1.id
      }, actor: user1)
      
      # User2 should not be able to read it - Ash returns NotFound to prevent information leakage
      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} = Conversations.get_conversation(conversation.id, actor: user2)
    end
    
    test "list_conversations only returns user's own conversations", %{user1: user1, user2: user2} do
      # Create conversations for both users
      {:ok, conv1} = Conversations.create_conversation(%{
        title: "User1 Conv 1",
        user_id: user1.id
      }, actor: user1)
      
      {:ok, conv2} = Conversations.create_conversation(%{
        title: "User1 Conv 2", 
        user_id: user1.id
      }, actor: user1)
      
      {:ok, _conv3} = Conversations.create_conversation(%{
        title: "User2 Conv",
        user_id: user2.id
      }, actor: user2)
      
      # User1 should only see their conversations
      {:ok, user1_convs} = Conversations.list_conversations(actor: user1)
      assert length(user1_convs) == 2
      assert Enum.all?(user1_convs, &(&1.user_id == user1.id))
      
      # User2 should only see their conversation
      {:ok, user2_convs} = Conversations.list_conversations(actor: user2)
      assert length(user2_convs) == 1
      assert Enum.all?(user2_convs, &(&1.user_id == user2.id))
    end
    
    test "users can update their own conversations", %{user1: user} do
      # Create a conversation
      {:ok, conversation} = Conversations.create_conversation(%{
        title: "Original Title",
        user_id: user.id
      }, actor: user)
      
      # Update it
      {:ok, updated} = Conversations.update_conversation(conversation, %{
        title: "Updated Title"
      }, actor: user)
      
      assert updated.title == "Updated Title"
    end
    
    test "users cannot update other users' conversations", %{user1: user1, user2: user2} do
      # Create a conversation for user1
      {:ok, conversation} = Conversations.create_conversation(%{
        title: "User1's Conversation",
        user_id: user1.id
      }, actor: user1)
      
      # User2 tries to update it
      assert {:error, %Forbidden{}} = Conversations.update_conversation(conversation, %{
        title: "Hacked Title"
      }, actor: user2)
    end
    
    test "users can delete their own conversations", %{user1: user} do
      # Create a conversation
      {:ok, conversation} = Conversations.create_conversation(%{
        title: "To Be Deleted",
        user_id: user.id
      }, actor: user)
      
      # Delete it
      assert :ok = Conversations.delete_conversation(conversation, actor: user)
      
      # Verify it's gone
      assert {:error, _} = Conversations.get_conversation(conversation.id, actor: user)
    end
    
    test "users cannot delete other users' conversations", %{user1: user1, user2: user2} do
      # Create a conversation for user1
      {:ok, conversation} = Conversations.create_conversation(%{
        title: "User1's Conversation",
        user_id: user1.id
      }, actor: user1)
      
      # User2 tries to delete it
      assert {:error, %Forbidden{}} = Conversations.delete_conversation(conversation, actor: user2)
      
      # Verify it still exists
      assert {:ok, _} = Conversations.get_conversation(conversation.id, actor: user1)
    end
    
    test "system operations can bypass authorization", %{user1: user1, user2: user2} do
      # Create conversations for both users
      {:ok, conv1} = Conversations.create_conversation(%{
        title: "User1 Conv",
        user_id: user1.id
      }, actor: user1)
      
      {:ok, conv2} = Conversations.create_conversation(%{
        title: "User2 Conv",
        user_id: user2.id
      }, actor: user2)
      
      # System can read all conversations without authorization
      {:ok, all_convs} = Conversations.list_conversations(authorize?: false)
      conv_ids = Enum.map(all_convs, & &1.id)
      
      assert conv1.id in conv_ids
      assert conv2.id in conv_ids
    end
  end
  
  describe "list_by_user action" do
    test "returns all conversations for a specific user", %{user1: user1, user2: user2} do
      # Create conversations
      {:ok, _conv1} = Conversations.create_conversation(%{
        title: "User1 Conv 1",
        user_id: user1.id
      }, actor: user1)
      
      {:ok, _conv2} = Conversations.create_conversation(%{
        title: "User1 Conv 2",
        user_id: user1.id
      }, actor: user1)
      
      {:ok, _conv3} = Conversations.create_conversation(%{
        title: "User2 Conv",
        user_id: user2.id
      }, actor: user2)
      
      # Use list_user_conversations action - it expects arguments in a map
      {:ok, user1_convs} = Conversations.list_user_conversations(%{user_id: user1.id}, actor: user1)
      assert length(user1_convs) == 2
      assert Enum.all?(user1_convs, &(&1.user_id == user1.id))
    end
  end
end