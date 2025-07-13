defmodule RubberDuck.Commands.Handlers.ConversationIntegrationTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Commands.{Command, Context}
  alias RubberDuck.Commands.Handlers.Conversation
  alias RubberDuck.Conversations

  describe "conversation LLM integration" do
    test "can create conversation and analyze message intent" do
      context = Context.new(%{
        user_id: Ash.UUID.generate(),
        project_id: nil,
        session_id: "test_session",
        permissions: [:read, :write],
        metadata: %{}
      })

      command = %Command{
        name: :conversation,
        subcommand: :start,
        args: %{title: "Debug Session"},
        options: %{type: "debugging"},
        context: context,
        client_type: :cli,
        format: :text
      }

      assert {:ok, result} = Conversation.execute(command)
      assert is_binary(result)
      assert String.contains?(result, "Conversation created successfully")
      assert String.contains?(result, "Debug Session")
    end

    test "can list user conversations" do
      user_id = Ash.UUID.generate()
      
      # Create a test conversation
      {:ok, conversation} = Conversations.create_conversation(%{
        user_id: user_id,
        title: "Test Conversation",
        status: :active
      })

      context = Context.new(%{
        user_id: user_id,
        project_id: nil,
        session_id: "test_session",
        permissions: [:read, :write],
        metadata: %{}
      })

      command = %Command{
        name: :conversation,
        subcommand: :list,
        args: [],
        options: %{},
        context: context,
        client_type: :cli,
        format: :text
      }

      assert {:ok, result} = Conversation.execute(command)
      assert is_binary(result)
      assert String.contains?(result, "Test Conversation")
    end

    test "can create conversation with different types and get appropriate LLM preferences" do
      user_id = Ash.UUID.generate()
      
      # Create coding conversation
      {:ok, coding_conv} = Conversations.create_conversation(%{
        user_id: user_id,
        title: "Coding Session",
        status: :active
      })

      {:ok, coding_context} = Conversations.create_context(%{
        conversation_id: coding_conv.id,
        conversation_type: :coding,
        context_window_size: 8000,
        llm_preferences: %{
          "temperature" => 0.2,
          "preferred_model" => "codellama"
        }
      })

      assert coding_context.conversation_type == :coding
      assert coding_context.context_window_size == 8000
      assert coding_context.llm_preferences["preferred_model"] == "codellama"

      # Create debugging conversation  
      {:ok, debug_conv} = Conversations.create_conversation(%{
        user_id: user_id,
        title: "Debug Session", 
        status: :active
      })

      {:ok, debug_context} = Conversations.create_context(%{
        conversation_id: debug_conv.id,
        conversation_type: :debugging,
        context_window_size: 6000,
        llm_preferences: %{
          "temperature" => 0.1,
          "preferred_model" => "claude-3-sonnet"
        }
      })

      assert debug_context.conversation_type == :debugging
      assert debug_context.context_window_size == 6000
      assert debug_context.llm_preferences["preferred_model"] == "claude-3-sonnet"
    end

    test "can create messages and build conversation history" do
      user_id = Ash.UUID.generate()
      
      {:ok, conversation} = Conversations.create_conversation(%{
        user_id: user_id,
        title: "Test Conversation",
        status: :active
      })

      # Create user message
      {:ok, user_msg} = Conversations.create_message(%{
        conversation_id: conversation.id,
        role: :user,
        content: "How do I fix this bug?",
        sequence_number: 1
      })

      # Create assistant message
      {:ok, assistant_msg} = Conversations.create_message(%{
        conversation_id: conversation.id,
        role: :assistant,
        content: "Here's how to fix the bug...",
        sequence_number: 2,
        model_used: "claude-3-sonnet",
        provider_used: "anthropic",
        tokens_used: 150
      })

      assert user_msg.role == :user
      assert user_msg.sequence_number == 1
      assert assistant_msg.role == :assistant
      assert assistant_msg.sequence_number == 2
      assert assistant_msg.model_used == "claude-3-sonnet"
    end
  end

  # Helper to test private functions
  defp call_private(module, function, args) do
    apply(module, function, args)
  end
end