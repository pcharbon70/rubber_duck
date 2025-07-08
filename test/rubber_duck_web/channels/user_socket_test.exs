defmodule RubberDuckWeb.UserSocketTest do
  use RubberDuckWeb.ChannelCase

  alias RubberDuckWeb.UserSocket

  describe "connect/3" do
    test "authenticates with valid token" do
      # Generate a valid token
      user_id = "user_123"
      token = Phoenix.Token.sign(RubberDuckWeb.Endpoint, "user socket", user_id)

      # Connect with token
      assert {:ok, socket} = connect(UserSocket, %{"token" => token})
      assert socket.assigns.user_id == user_id
      assert socket.assigns.joined_at
    end

    test "authenticates with valid API key" do
      # Use a valid API key (32+ chars)
      api_key = "test_api_key_that_is_long_enough_12345"

      assert {:ok, socket} = connect(UserSocket, %{"api_key" => api_key})
      assert socket.assigns.user_id == "api_user_#{api_key}"
    end

    test "rejects expired token" do
      # Generate an expired token
      user_id = "user_123"
      # Token with max_age of -1 second (already expired)
      token =
        Phoenix.Token.sign(RubberDuckWeb.Endpoint, "user socket", user_id,
          signed_at: System.system_time(:second) - 86401
        )

      assert :error = connect(UserSocket, %{"token" => token})
    end

    test "rejects invalid token" do
      assert :error = connect(UserSocket, %{"token" => "invalid_token"})
    end

    test "rejects short API key" do
      assert :error = connect(UserSocket, %{"api_key" => "too_short"})
    end

    test "rejects connection without credentials" do
      assert :error = connect(UserSocket, %{})
    end

    test "socket id includes user_id" do
      user_id = "user_123"
      token = Phoenix.Token.sign(RubberDuckWeb.Endpoint, "user socket", user_id)

      {:ok, socket} = connect(UserSocket, %{"token" => token})
      assert UserSocket.id(socket) == "user_socket:#{user_id}"
    end
  end
end
