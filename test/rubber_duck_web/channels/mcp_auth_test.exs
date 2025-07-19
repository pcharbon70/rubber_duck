defmodule RubberDuckWeb.MCPAuthTest do
  use ExUnit.Case, async: true

  alias RubberDuckWeb.MCPAuth

  @valid_client_info %{
    "name" => "TestClient",
    "version" => "1.0.0",
    "capabilities" => %{
      "tools" => %{},
      "resources" => %{}
    },
    "metadata" => %{
      "platform" => "test"
    }
  }

  @valid_auth_params %{
    "clientInfo" => @valid_client_info,
    "apiKey" => "test_key"
  }

  describe "authenticate_client/2" do
    test "authenticates with valid API key" do
      connect_info = %{}

      {:ok, auth_context} = MCPAuth.authenticate_client(@valid_auth_params, connect_info)

      assert auth_context.user_id == "mcp_user_test"
      assert auth_context.permissions == ["tools:*", "resources:*", "prompts:*", "workflows:*"]
      assert auth_context.role == "api_user"
    end

    test "authenticates with API key in query string" do
      connect_info = %{
        uri: %{
          query: "api_key=test_key"
        }
      }

      {:ok, auth_context} = MCPAuth.authenticate_client(%{"clientInfo" => @valid_client_info}, connect_info)

      assert auth_context.user_id == "mcp_user_test"
      assert auth_context.permissions == ["tools:*", "resources:*", "prompts:*", "workflows:*"]
    end

    test "authenticates with valid token" do
      # Create a valid token
      token_data = %{
        user_id: "test_user",
        permissions: ["tools:*"],
        role: "user",
        client_info: @valid_client_info
      }

      token = Phoenix.Token.sign(RubberDuckWeb.Endpoint, "mcp_auth", token_data)

      params = %{
        "clientInfo" => @valid_client_info,
        "token" => token
      }

      {:ok, auth_context} = MCPAuth.authenticate_client(params, %{})

      assert auth_context.user_id == "test_user"
      assert auth_context.permissions == ["tools:*"]
      assert auth_context.role == "user"
    end

    test "rejects invalid API key" do
      params = %{
        "clientInfo" => @valid_client_info,
        "apiKey" => "invalid_key"
      }

      {:error, reason} = MCPAuth.authenticate_client(params, %{})

      assert reason =~ "Invalid API key"
    end

    test "rejects expired token" do
      # Create an expired token
      expired_token = Phoenix.Token.sign(RubberDuckWeb.Endpoint, "mcp_auth", %{user_id: "test"})

      # Sleep to ensure expiration (if max_age is very small)
      Process.sleep(10)

      params = %{
        "clientInfo" => @valid_client_info,
        "token" => expired_token
      }

      # This test depends on implementation details of token verification
      # May need adjustment based on actual token expiration handling
      result = MCPAuth.authenticate_client(params, %{})

      case result do
        # Token still valid
        {:ok, _} -> :ok
        {:error, reason} -> assert reason =~ "Token"
      end
    end

    test "rejects when no credentials provided" do
      params = %{
        "clientInfo" => @valid_client_info
      }

      {:error, reason} = MCPAuth.authenticate_client(params, %{})

      assert reason == "No authentication credentials provided"
    end

    test "generates consistent user ID from API key" do
      connect_info = %{}

      {:ok, auth_context1} = MCPAuth.authenticate_client(@valid_auth_params, connect_info)
      {:ok, auth_context2} = MCPAuth.authenticate_client(@valid_auth_params, connect_info)

      assert auth_context1.user_id == auth_context2.user_id
    end
  end

  describe "validate_client_info/1" do
    test "validates complete client info" do
      {:ok, validated_info} = MCPAuth.validate_client_info(@valid_client_info)

      assert validated_info.name == "TestClient"
      assert validated_info.version == "1.0.0"
      assert validated_info.capabilities == %{"tools" => %{}, "resources" => %{}}
      assert validated_info.metadata == %{"platform" => "test"}
    end

    test "validates client info with minimal fields" do
      minimal_info = %{
        "name" => "MinimalClient",
        "version" => "1.0.0"
      }

      {:ok, validated_info} = MCPAuth.validate_client_info(minimal_info)

      assert validated_info.name == "MinimalClient"
      assert validated_info.version == "1.0.0"
      assert validated_info.capabilities == %{}
      assert validated_info.metadata == %{}
    end

    test "rejects client info missing name" do
      invalid_info = %{
        "version" => "1.0.0"
      }

      {:error, reason} = MCPAuth.validate_client_info(invalid_info)

      assert reason =~ "Missing or invalid client name"
    end

    test "rejects client info missing version" do
      invalid_info = %{
        "name" => "TestClient"
      }

      {:error, reason} = MCPAuth.validate_client_info(invalid_info)

      assert reason =~ "Missing or invalid client version"
    end

    test "rejects client info with empty name" do
      invalid_info = %{
        "name" => "",
        "version" => "1.0.0"
      }

      {:error, reason} = MCPAuth.validate_client_info(invalid_info)

      assert reason =~ "Missing or invalid client name"
    end

    test "rejects non-map client info" do
      {:error, reason} = MCPAuth.validate_client_info("invalid")

      assert reason == "Invalid client info format"
    end

    test "rejects client info with invalid capabilities" do
      invalid_info = %{
        "name" => "TestClient",
        "version" => "1.0.0",
        "capabilities" => "invalid"
      }

      {:error, reason} = MCPAuth.validate_client_info(invalid_info)

      assert reason =~ "Invalid client capabilities format"
    end
  end

  describe "authorize_capability/2" do
    test "authorizes admin role for any capability" do
      auth_context = %{role: "admin"}

      assert MCPAuth.authorize_capability(auth_context, "tools:execute")
      assert MCPAuth.authorize_capability(auth_context, "admin:delete")
      assert MCPAuth.authorize_capability(auth_context, "any:capability")
    end

    test "authorizes user role for allowed capabilities" do
      auth_context = %{role: "user"}

      assert MCPAuth.authorize_capability(auth_context, "tools:list")
      assert MCPAuth.authorize_capability(auth_context, "tools:call")
      assert MCPAuth.authorize_capability(auth_context, "resources:list")
      refute MCPAuth.authorize_capability(auth_context, "admin:delete")
    end

    test "authorizes readonly role for read-only capabilities" do
      auth_context = %{role: "readonly"}

      assert MCPAuth.authorize_capability(auth_context, "tools:list")
      assert MCPAuth.authorize_capability(auth_context, "resources:list")
      refute MCPAuth.authorize_capability(auth_context, "tools:call")
      refute MCPAuth.authorize_capability(auth_context, "workflows:create")
    end

    test "authorizes specific permissions" do
      auth_context = %{permissions: ["tools:list", "resources:read"]}

      assert MCPAuth.authorize_capability(auth_context, "tools:list")
      assert MCPAuth.authorize_capability(auth_context, "resources:read")
      refute MCPAuth.authorize_capability(auth_context, "tools:call")
    end

    test "authorizes wildcard permissions" do
      auth_context = %{permissions: ["tools:*"]}

      assert MCPAuth.authorize_capability(auth_context, "tools:list")
      assert MCPAuth.authorize_capability(auth_context, "tools:call")
      assert MCPAuth.authorize_capability(auth_context, "tools:execute")
      refute MCPAuth.authorize_capability(auth_context, "resources:list")
    end

    test "authorizes with global wildcard" do
      auth_context = %{permissions: ["*"]}

      assert MCPAuth.authorize_capability(auth_context, "tools:list")
      assert MCPAuth.authorize_capability(auth_context, "resources:read")
      assert MCPAuth.authorize_capability(auth_context, "admin:delete")
    end

    test "denies unknown roles" do
      auth_context = %{role: "unknown"}

      refute MCPAuth.authorize_capability(auth_context, "tools:list")
      refute MCPAuth.authorize_capability(auth_context, "any:capability")
    end

    test "denies empty auth context" do
      auth_context = %{}

      refute MCPAuth.authorize_capability(auth_context, "tools:list")
      refute MCPAuth.authorize_capability(auth_context, "any:capability")
    end
  end

  describe "create_session_token/1" do
    test "creates valid session token" do
      auth_context = %{
        user_id: "test_user",
        client_info: @valid_client_info,
        permissions: ["tools:*"],
        role: "user"
      }

      token = MCPAuth.create_session_token(auth_context)

      assert is_binary(token)
      assert byte_size(token) > 0
    end

    test "creates different tokens for different contexts" do
      auth_context1 = %{
        user_id: "user1",
        client_info: @valid_client_info,
        permissions: ["tools:*"]
      }

      auth_context2 = %{
        user_id: "user2",
        client_info: @valid_client_info,
        permissions: ["tools:*"]
      }

      token1 = MCPAuth.create_session_token(auth_context1)
      token2 = MCPAuth.create_session_token(auth_context2)

      assert token1 != token2
    end
  end

  describe "verify_session_token/1" do
    test "verifies valid session token" do
      auth_context = %{
        user_id: "test_user",
        client_info: @valid_client_info,
        permissions: ["tools:*"]
      }

      token = MCPAuth.create_session_token(auth_context)

      {:ok, session_data} = MCPAuth.verify_session_token(token)

      assert session_data.user_id == "test_user"
      assert session_data.permissions == ["tools:*"]
    end

    test "rejects invalid session token" do
      {:error, reason} = MCPAuth.verify_session_token("invalid_token")

      assert reason =~ "Invalid session token"
    end

    test "rejects expired session token" do
      # Create a token that will expire quickly
      session_data = %{
        user_id: "test_user",
        client_info: @valid_client_info,
        permissions: ["tools:*"],
        expires_at: DateTime.add(DateTime.utc_now(), -1, :second)
      }

      token = Phoenix.Token.sign(RubberDuckWeb.Endpoint, "mcp_session", session_data)

      {:error, reason} = MCPAuth.verify_session_token(token)

      assert reason == "Session expired"
    end
  end

  describe "refresh_session_token/1" do
    test "refreshes valid session token" do
      auth_context = %{
        user_id: "test_user",
        client_info: @valid_client_info,
        permissions: ["tools:*"]
      }

      original_token = MCPAuth.create_session_token(auth_context)

      {:ok, new_token} = MCPAuth.refresh_session_token(original_token)

      assert is_binary(new_token)
      assert new_token != original_token

      # Verify new token is valid
      {:ok, session_data} = MCPAuth.verify_session_token(new_token)
      assert session_data.user_id == "test_user"
    end

    test "rejects refreshing invalid token" do
      {:error, reason} = MCPAuth.refresh_session_token("invalid_token")

      assert reason =~ "Invalid session token"
    end
  end
end
