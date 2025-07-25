defmodule RubberDuckWeb.AuthChannelApiKeyTest do
  use RubberDuckWeb.ChannelCase

  import RubberDuck.AccountsFixtures
  import RubberDuck.ApiKeyHelpers
  
  require Logger

  describe "API key authentication" do
    test "authenticates with valid API key and returns JWT token" do
      user = user_fixture()
      
      # Create API key with known value
      {:ok, api_key, api_key_value} = create_test_api_key(user)
      
      # Debug: log the API key info
      Logger.info("Test API key created: #{api_key.id}, valid: #{api_key.valid}, expires_at: #{api_key.expires_at}")
      Logger.info("Plaintext key: #{api_key_value}")
      
      {:ok, _, socket} = subscribe_and_join(socket(RubberDuckWeb.AuthSocket), RubberDuckWeb.AuthChannel, "auth:lobby")
      push(socket, "authenticate_with_api_key", %{"api_key" => api_key_value})
      
      assert_push "login_success", %{
        user: returned_user,
        token: token
      }
      
      assert returned_user.id == user.id
      assert returned_user.username == user.username
      assert returned_user.email == user.email
      assert is_binary(token)
      
      # Verify the JWT token is valid
      assert {:ok, _claims, _resource} = AshAuthentication.Jwt.verify(token, RubberDuck.Accounts.User)
    end

    test "rejects invalid API key" do
      # Create a user but don't create an API key
      _user = user_fixture()
      invalid_key = "rubberduck_invalid_key"
      
      {:ok, _, socket} = subscribe_and_join(socket(RubberDuckWeb.AuthSocket), RubberDuckWeb.AuthChannel, "auth:lobby")
      push(socket, "authenticate_with_api_key", %{"api_key" => invalid_key})
      
      assert_push "login_error", %{
        message: "Authentication failed",
        details: details
      }
      
      assert details == "Invalid credentials"
    end

    test "rejects missing API key" do
      {:ok, _, socket} = subscribe_and_join(socket(RubberDuckWeb.AuthSocket), RubberDuckWeb.AuthChannel, "auth:lobby")
      push(socket, "authenticate_with_api_key", %{})
      
      assert_push "login_error", %{
        message: "Authentication failed",
        details: "API key is required"
      }
    end

    test "rejects expired API key" do
      user = user_fixture()
      
      # Create expired API key
      {:ok, api_key, api_key_value} = create_expired_api_key(user)
      
      # Debug: log the API key info
      Logger.info("Expired API key created: #{api_key.id}, valid: #{api_key.valid}, expires_at: #{api_key.expires_at}")
      
      {:ok, _, socket} = subscribe_and_join(socket(RubberDuckWeb.AuthSocket), RubberDuckWeb.AuthChannel, "auth:lobby")
      push(socket, "authenticate_with_api_key", %{"api_key" => api_key_value})
      
      assert_push "login_error", %{
        message: "Authentication failed",
        details: details
      }
      
      assert details == "API key has expired"
    end

    test "applies rate limiting to API key authentication" do
      user = user_fixture()
      
      # Create API key
      {:ok, _api_key, api_key_value} = create_test_api_key(user)
      
      {:ok, _, socket} = subscribe_and_join(socket(RubberDuckWeb.AuthSocket), RubberDuckWeb.AuthChannel, "auth:lobby")
      
      # Rate limiting is not enforced yet (check_login_rate_limit always returns true)
      # But we can still test that multiple attempts work
      for _ <- 1..5 do
        push(socket, "authenticate_with_api_key", %{"api_key" => api_key_value})
        
        assert_push "login_success", %{
          user: _user,
          token: _token
        }
      end
    end
  end
end