defmodule RubberDuck.ConversationSendTimeoutTest do
  use RubberDuck.DataCase
  
  alias RubberDuck.Commands.{Command, Context}
  alias RubberDuck.Commands.Handlers.Conversation
  alias RubberDuck.Conversations
  
  setup do
    # Configure test LLM providers - use config similar to dev.exs
    Application.put_env(:rubber_duck, :llm, 
      providers: [
        %{
          name: :ollama,
          adapter: RubberDuck.LLM.Providers.Ollama,
          base_url: "http://localhost:11434",
          models: ["llama2", "codellama", "mistral"],
          timeout: 60_000
        },
        %{
          name: :mock,
          adapter: RubberDuck.LLM.Providers.Mock,
          default: true,
          models: ["mock-gpt", "mock-codellama"]
        }
      ]
    )
    
    :ok
  end
  
  describe "conversation send timeout bug" do
    test "send command should complete quickly with ollama connected" do
      # Arrange - This test will reproduce the timeout issue
      # Skip connecting to Ollama since we want to test the actual CLI timeout issue
      
      # Create test conversation
      user_id = "00000000-0000-0000-0000-000000000001" 
      {:ok, conversation} = Conversations.create_conversation(%{
        user_id: user_id,
        title: "Test Conversation",
        status: :active,
        metadata: %{
          created_via: "test",
          conversation_type: :general
        }
      })
      
      # Create command context
      {:ok, context} = Context.new(%{
        user_id: user_id,
        session_id: "test_session",
        permissions: [:read, :write],
        metadata: %{test: true}
      })
      
      # Create command for conversation send
      command = %Command{
        name: :conversation,
        subcommand: :send,
        args: ["Hello, how are you?"],
        options: %{conversation: conversation.id},
        context: context,
        client_type: :cli,
        format: :text
      }
      
      # Act - This should complete quickly but will timeout due to no LLM connection
      start_time = System.monotonic_time(:millisecond)
      result = Conversation.execute(command)
      end_time = System.monotonic_time(:millisecond)
      execution_time = end_time - start_time
      
      # Assert - The test should fail due to timeout, demonstrating the bug
      # When the bug is fixed, this should return an error about no LLM connected quickly
      case result do
        {:error, reason} when is_binary(reason) ->
          # Good - we got an error quickly instead of timing out
          assert execution_time < 5000, "Command should fail quickly, took #{execution_time}ms"
          assert String.contains?(reason, "LLM") or String.contains?(reason, "provider"), 
                 "Expected LLM-related error, got: #{reason}"
        
        {:ok, _response} ->
          # Should not succeed without LLM connection
          flunk("Command succeeded without LLM connection, execution time: #{execution_time}ms")
          
        {:error, :timeout} ->
          # This demonstrates the bug - we're getting timeout instead of proper error
          flunk("Command timed out after #{execution_time}ms - this is the bug we're fixing")
      end
    end
  end
end