defmodule RubberDuckWeb.ConversationChannelLobbyTest do
  use RubberDuckWeb.ChannelCase
  import RubberDuck.AccountsFixtures

  alias RubberDuckWeb.{UserSocket, ConversationChannel}

  describe "lobby conversation handling" do
    test "authenticated users joining lobby get their latest conversation or a new one" do
      # Arrange
      user = user_fixture()
      {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      
      # Act - Join lobby, should create a new conversation
      result = subscribe_and_join(socket, ConversationChannel, "conversation:lobby")
      
      # Assert
      assert {:ok, %{conversation_id: conversation_id, session_id: session_id}, _socket} = result
      assert is_binary(session_id)
      # The conversation_id should be a UUID, not "lobby"
      assert conversation_id != "lobby"
      assert {:ok, _uuid} = Ecto.UUID.cast(conversation_id)
      
      # Verify a database conversation was created
      assert {:ok, conversation} = RubberDuck.Conversations.get_conversation(conversation_id, actor: user)
      assert conversation.user_id == user.id
    end
    
    test "joining lobby multiple times returns the same conversation" do
      # Arrange
      user = user_fixture()
      {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
      
      # First connection
      {:ok, socket1} = connect(UserSocket, %{"token" => token})
      {:ok, %{conversation_id: conv_id1}, _socket1} = subscribe_and_join(socket1, ConversationChannel, "conversation:lobby")
      
      # Second connection (simulating reconnect)
      {:ok, socket2} = connect(UserSocket, %{"token" => token})
      {:ok, %{conversation_id: conv_id2}, _socket2} = subscribe_and_join(socket2, ConversationChannel, "conversation:lobby")
      
      # Assert - Should get the same conversation
      assert conv_id1 == conv_id2
      assert conv_id1 != "lobby"
    end
    
    test "lobby conversation with existing conversation loads the latest one" do
      # Arrange
      user = user_fixture()
      {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
      
      # Create an existing conversation for the user
      {:ok, existing_conv} = RubberDuck.Conversations.create_conversation(
        %{
          user_id: user.id,
          title: "Existing Conversation",
          status: :active
        },
        actor: user
      )
      
      # Act - Join lobby
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      {:ok, %{conversation_id: loaded_conv_id}, _socket} = subscribe_and_join(socket, ConversationChannel, "conversation:lobby")
      
      # Assert - Should load the existing conversation
      assert loaded_conv_id == existing_conv.id
    end
  end
end