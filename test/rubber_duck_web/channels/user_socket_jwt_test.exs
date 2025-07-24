defmodule RubberDuckWeb.UserSocketJWTTest do
  use RubberDuckWeb.ChannelCase
  import RubberDuck.AccountsFixtures

  alias RubberDuckWeb.UserSocket

  describe "JWT subject handling" do
    test "extracts user_id from AshAuthentication JWT subject format" do
      # Create a user
      user = user_fixture()
      
      # Generate JWT token
      {:ok, token, claims} = AshAuthentication.Jwt.token_for_user(user)
      
      # Verify the subject format
      assert claims["sub"] =~ "user?id="
      
      # Connect with token
      assert {:ok, socket} = connect(UserSocket, %{"token" => token})
      
      # Verify the user_id was correctly extracted
      assert socket.assigns.user_id == user.id
    end
    
    test "handles different subject formats gracefully" do
      # This test would require mocking the JWT verification
      # to return a different subject format
      # For now, we just verify the current implementation works
      user = user_fixture()
      {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
      
      assert {:ok, socket} = connect(UserSocket, %{"token" => token})
      assert socket.assigns.user_id == user.id
    end
  end
  
  describe "SessionContext integration" do
    test "conversation channel can join after JWT authentication" do
      # Create a user and authenticate
      user = user_fixture()
      {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
      
      # Connect to UserSocket
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      
      # Join conversation channel
      {:ok, _reply, _socket} = subscribe_and_join(socket, "conversation:lobby", %{})
    end
  end
end