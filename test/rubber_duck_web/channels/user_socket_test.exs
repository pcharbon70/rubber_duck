defmodule RubberDuckWeb.UserSocketTest do
  use RubberDuckWeb.ChannelCase
  import RubberDuck.AccountsFixtures

  alias RubberDuckWeb.UserSocket

  describe "connect/3" do
    test "authenticates with valid JWT token" do
      # Create a user and generate a JWT token
      user = user_fixture()
      {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)

      # Connect with token
      assert {:ok, socket} = connect(UserSocket, %{"token" => token})
      assert socket.assigns.user_id == user.id
      assert socket.assigns.joined_at
    end

    test "rejects API key authentication (moved to AuthSocket)" do
      # API key authentication has been moved to AuthSocket
      api_key = "test_api_key_that_is_long_enough_12345"

      assert :error = connect(UserSocket, %{"api_key" => api_key})
    end

    test "rejects expired JWT token" do
      # For this test, we'd need to mock the token verification
      # or use a pre-generated expired token
      expired_token = "expired.jwt.token"

      assert :error = connect(UserSocket, %{"token" => expired_token})
    end

    test "rejects invalid token" do
      assert :error = connect(UserSocket, %{"token" => "invalid_token"})
    end

    test "rejects short tokens" do
      assert :error = connect(UserSocket, %{"token" => "too_short"})
    end

    test "rejects connection without credentials" do
      assert :error = connect(UserSocket, %{})
    end

    test "socket id includes user_id" do
      # Create a user and generate a JWT token
      user = user_fixture()
      {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)

      {:ok, socket} = connect(UserSocket, %{"token" => token})
      assert UserSocket.id(socket) == "user_socket:#{user.id}"
    end
  end
end
