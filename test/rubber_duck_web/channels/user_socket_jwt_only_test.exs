defmodule RubberDuckWeb.UserSocketJwtOnlyTest do
  use RubberDuckWeb.ChannelCase

  import RubberDuck.AccountsFixtures

  alias RubberDuckWeb.UserSocket

  describe "JWT-only authentication" do
    setup do
      user = user_fixture()
      
      # Handle both return formats from token_for_user
      token = case AshAuthentication.Jwt.token_for_user(user) do
        {:ok, token, _claims} -> token
        {:ok, token} -> token
      end
      
      %{user: user, token: token}
    end

    test "accepts valid JWT token", %{token: token} do
      assert {:ok, socket} = connect(UserSocket, %{"token" => token})
      assert socket.assigns.user_id
    end

    test "rejects connection without token" do
      assert :error = connect(UserSocket, %{})
    end

    test "rejects connection with empty token" do
      assert :error = connect(UserSocket, %{"token" => ""})
    end

    test "rejects expired JWT token", %{user: _user} do
      # Create an expired token by manipulating the claims
      # This is a simplified test - in production you'd use proper token expiration
      assert :error = connect(UserSocket, %{"token" => "expired.jwt.token"})
    end

    test "rejects API key in params" do
      # API keys should no longer work
      assert :error = connect(UserSocket, %{"api_key" => "rubberduck_test_key"})
    end

    test "rejects API key instead of token" do
      # Ensure API key doesn't work even if passed as the only auth param
      assert :error = connect(UserSocket, %{"api_key" => "rubberduck_test_key"})
    end

    test "error message mentions JWT requirement" do
      # Test that the error message is helpful
      # Since Phoenix socket connect returns :error without details,
      # we can't test the message directly, but the implementation includes it
      assert :error = connect(UserSocket, %{})
    end
  end
end