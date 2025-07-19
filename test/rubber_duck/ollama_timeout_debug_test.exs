defmodule RubberDuck.OllamaTimeoutDebugTest do
  use RubberDuck.DataCase

  alias RubberDuck.Commands.{Command, Context}
  alias RubberDuck.Commands.Handlers.Conversation
  alias RubberDuck.Conversations

  setup do
    # Configure test LLM providers to match dev config
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

  describe "ollama timeout debug" do
    test "identify model being requested and validation failure" do
      # Create test conversation
      user_id = "00000000-0000-0000-0000-000000000001"

      {:ok, conversation} =
        Conversations.create_conversation(%{
          user_id: user_id,
          title: "Test Conversation",
          status: :active,
          metadata: %{
            created_via: "test",
            conversation_type: :general
          }
        })

      # Create command context
      {:ok, context} =
        Context.new(%{
          user_id: user_id,
          session_id: "test_session",
          permissions: [:read, :write],
          metadata: %{test: true}
        })

      # Create command for conversation send
      command = %Command{
        name: :conversation,
        subcommand: :send,
        # Simple math question
        args: ["What is 2+2?"],
        options: %{conversation: conversation.id},
        context: context,
        client_type: :cli,
        format: :text
      }

      # Act - This should fail quickly with specific error about model validation
      start_time = System.monotonic_time(:millisecond)
      result = Conversation.execute(command)
      end_time = System.monotonic_time(:millisecond)
      execution_time = end_time - start_time

      # Assert - We expect this to either succeed or fail quickly with model error
      case result do
        {:ok, _response} ->
          # If it succeeds, ensure it's fast
          assert execution_time < 10_000, "Successful response took #{execution_time}ms, expected < 10s"

        {:error, reason} when is_binary(reason) ->
          # Should get a specific error about model validation
          assert execution_time < 5_000, "Error response took #{execution_time}ms, expected < 5s"

          # Check if it's a model-related error
          if String.contains?(reason, "model") or String.contains?(reason, "provider") do
            IO.puts("Model validation error: #{reason}")
          else
            IO.puts("Other error: #{reason}")
          end

        other ->
          flunk("Unexpected result: #{inspect(other)}, execution time: #{execution_time}ms")
      end
    end
  end
end
