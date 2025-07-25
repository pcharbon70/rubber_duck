defmodule RubberDuckWeb.ConversationChannelTest do
  use RubberDuckWeb.ChannelCase
  import RubberDuck.AccountsFixtures

  alias RubberDuckWeb.ConversationChannel

  setup do
    # Create a user for authentication
    user = user_fixture()
    
    # Generate JWT token
    {:ok, token, _claims} = AshAuthentication.Jwt.token_for_user(user)
    
    # Create a socket with JWT authentication
    {:ok, socket} = connect(RubberDuckWeb.UserSocket, %{"token" => token})

    # Generate a valid UUID for the conversation
    conversation_id = Ecto.UUID.generate()
    
    # Join the conversation channel
    {:ok, _, socket} = subscribe_and_join(socket, ConversationChannel, "conversation:#{conversation_id}")

    %{socket: socket, user: user, conversation_id: conversation_id}
  end

  describe "message handling" do
    test "simple message receives response", %{socket: socket} do
      # Send a simple message
      push(socket, "message", %{
        "content" => "What is Elixir?",
        "llm_config" => %{
          "provider" => "mock",
          "model" => "test-model"
        }
      })

      # Should receive thinking indicator
      assert_push("thinking", %{})

      # Should receive response (this will fail without LLM config)
      assert_push("response", response, 10_000)

      assert response.query == "What is Elixir?"
      assert response.response
      assert response.conversation_type
      assert response.timestamp
    end

    test "message with context", %{socket: socket} do
      # Send message with additional context
      push(socket, "message", %{
        "content" => "Can you explain pattern matching in Elixir?",
        "context" => %{
          "skill_level" => "beginner",
          "preferred_language" => "en"
        },
        "options" => %{
          "include_examples" => true
        },
        "llm_config" => %{
          "provider" => "mock",
          "model" => "test-model"
        }
      })

      assert_push("thinking", %{})

      # This will fail without LLM configuration
      assert_push("response", response, 10_000)
      assert response.response
    end

    test "multi-turn conversation maintains context", %{socket: socket} do
      # First message
      push(socket, "message", %{
        "content" => "What is pattern matching?",
        "llm_config" => %{"provider" => "mock", "model" => "test-model"}
      })
      assert_push("thinking", %{})
      assert_push("response", _, 10_000)

      # Follow-up message - should have context
      push(socket, "message", %{
        "content" => "Can you show me an example?",
        "llm_config" => %{"provider" => "mock", "model" => "test-model"}
      })
      assert_push("thinking", %{})
      assert_push("response", response, 10_000)

      # Response should be contextual
      assert response.response
    end
  end

  describe "conversation management" do
    test "new conversation resets context", %{socket: socket} do
      # Send initial message
      push(socket, "message", %{"content" => "Hello"})
      assert_push("thinking", %{})

      # Start new conversation
      push(socket, "new_conversation", %{})
      assert_push("conversation_reset", %{session_id: session_id, timestamp: _})

      # Session ID should be new
      assert session_id
    end

    test "set context updates conversation context", %{socket: socket} do
      # Set custom context
      push(socket, "set_context", %{
        "context" => %{
          "project_type" => "phoenix",
          "language" => "elixir",
          "framework_version" => "1.7"
        }
      })

      assert_push("context_updated", %{
        context: context,
        timestamp: _
      })

      assert context["project_type"] == "phoenix"
      assert context["language"] == "elixir"
    end

    test "typing indicator", %{socket: socket} do
      # Send typing indicator
      push(socket, "typing", %{"typing" => true})

      # Should not crash - just acknowledges
      refute_push("error", _)
    end
  end

  describe "error handling" do
    test "handles malformed messages gracefully", %{socket: socket} do
      # Send message without content
      push(socket, "message", %{})

      # Should receive error
      assert_push("error", %{message: message})
      assert message
    end

    test "handles missing llm config", %{socket: socket} do
      # This will trigger an error due to missing LLM config
      push(socket, "message", %{"content" => "Test message"})

      # Should receive error about missing configuration
      assert_push("error", %{message: message, type: "llm_not_configured"})
      assert message =~ "configure your LLM provider"
    end
  end
end
