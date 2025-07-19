defmodule RubberDuckWeb.ConversationChannelLLMTest do
  use RubberDuckWeb.ChannelCase, async: true

  @test_user_id "test_user_123"
  @test_session_id "test_session_123"

  setup do
    socket =
      socket(RubberDuckWeb.UserSocket, "user_socket:#{@test_user_id}", %{
        user_id: @test_user_id
      })

    {:ok, socket: socket}
  end

  describe "LLM preference management" do
    test "set_llm_preference creates new configuration", %{socket: socket} do
      # Create a test user profile first
      {:ok, _profile} =
        RubberDuck.Memory.create_or_update_profile(%{
          user_id: @test_user_id,
          preferences: %{},
          learned_patterns: %{}
        })

      {:ok, _, socket} = subscribe_and_join(socket, RubberDuckWeb.ConversationChannel, "conversation:test")

      # Set LLM preference
      ref =
        push(socket, "set_llm_preference", %{
          "provider" => "openai",
          "model" => "gpt-4",
          "is_default" => true
        })

      # Should receive success response
      assert_reply(ref, :ok, %{
        "provider" => "openai",
        "model" => "gpt-4",
        "is_default" => true
      })
    end

    test "get_llm_preferences returns user configurations", %{socket: socket} do
      # Create a test user profile first
      {:ok, _profile} =
        RubberDuck.Memory.create_or_update_profile(%{
          user_id: @test_user_id,
          preferences: %{},
          learned_patterns: %{}
        })

      {:ok, _, socket} = subscribe_and_join(socket, RubberDuckWeb.ConversationChannel, "conversation:test")

      # First set a preference
      push(socket, "set_llm_preference", %{
        "provider" => "openai",
        "model" => "gpt-4",
        "is_default" => true
      })

      # Get preferences
      ref = push(socket, "get_llm_preferences", %{})

      # Should receive configurations
      assert_reply(ref, :ok, %{
        "configs" => configs,
        "count" => count
      })

      assert is_list(configs)
      assert count >= 0
    end

    test "get_llm_default returns default configuration", %{socket: socket} do
      # Create a test user profile first
      {:ok, _profile} =
        RubberDuck.Memory.create_or_update_profile(%{
          user_id: @test_user_id,
          preferences: %{},
          learned_patterns: %{}
        })

      {:ok, _, socket} = subscribe_and_join(socket, RubberDuckWeb.ConversationChannel, "conversation:test")

      # Set a default preference
      push(socket, "set_llm_preference", %{
        "provider" => "openai",
        "model" => "gpt-4",
        "is_default" => true
      })

      # Get default
      ref = push(socket, "get_llm_default", %{})

      # Should receive default configuration
      assert_reply(ref, :ok, %{
        "provider" => "openai",
        "model" => "gpt-4",
        "user_id" => @test_user_id
      })
    end

    test "get_llm_usage_stats returns usage information", %{socket: socket} do
      # Create a test user profile first
      {:ok, _profile} =
        RubberDuck.Memory.create_or_update_profile(%{
          user_id: @test_user_id,
          preferences: %{},
          learned_patterns: %{}
        })

      {:ok, _, socket} = subscribe_and_join(socket, RubberDuckWeb.ConversationChannel, "conversation:test")

      # Get usage stats
      ref = push(socket, "get_llm_usage_stats", %{})

      # Should receive usage stats
      assert_reply(ref, :ok, %{
        "stats" => stats,
        "user_id" => @test_user_id
      })

      assert is_map(stats)
      assert Map.has_key?(stats, "total_requests")
      assert Map.has_key?(stats, "providers")
    end

    test "handles invalid provider gracefully", %{socket: socket} do
      # Create a test user profile first
      {:ok, _profile} =
        RubberDuck.Memory.create_or_update_profile(%{
          user_id: @test_user_id,
          preferences: %{},
          learned_patterns: %{}
        })

      {:ok, _, socket} = subscribe_and_join(socket, RubberDuckWeb.ConversationChannel, "conversation:test")

      # Try to set invalid provider
      ref =
        push(socket, "set_llm_preference", %{
          "provider" => "invalid_provider",
          "model" => "gpt-4",
          "is_default" => true
        })

      # Should receive error response
      assert_reply(ref, :error, %{
        "operation" => "set_preference",
        "message" => "Failed to set LLM preference"
      })
    end
  end
end
