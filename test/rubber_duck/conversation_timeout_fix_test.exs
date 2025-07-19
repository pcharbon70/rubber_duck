defmodule RubberDuck.ConversationTimeoutFixTest do
  use ExUnit.Case

  alias RubberDuck.Commands.{Command, Context}
  alias RubberDuck.Commands.Handlers.Conversation

  describe "conversation timeout fixes" do
    test "conversation start fails fast when connection manager not running" do
      # Create command context
      {:ok, context} =
        Context.new(%{
          user_id: "00000000-0000-0000-0000-000000000001",
          session_id: "test_session",
          permissions: [:read, :write],
          metadata: %{test: true}
        })

      # Create command for conversation start
      command = %Command{
        name: :conversation,
        subcommand: :start,
        args: ["Test Conversation"],
        options: %{},
        context: context,
        client_type: :cli,
        format: :text
      }

      # Act - This should fail quickly with specific error about connection manager
      start_time = System.monotonic_time(:millisecond)
      result = Conversation.execute(command)
      end_time = System.monotonic_time(:millisecond)
      execution_time = end_time - start_time

      # Assert - Should fail fast with connection manager error
      assert execution_time < 1000, "Command took #{execution_time}ms, expected < 1s"

      case result do
        {:error, message} when is_binary(message) ->
          assert String.contains?(message, "connection manager") or String.contains?(message, "not running"),
                 "Expected connection manager error, got: #{message}"

        other ->
          flunk("Expected error about connection manager, got: #{inspect(other)}")
      end
    end

    test "conversation send fails fast when LLM processes not running" do
      # Create command for conversation send
      command = %Command{
        name: :conversation,
        subcommand: :send,
        args: ["What is 2+2?"],
        options: %{conversation: "test-id"},
        context: %{user_id: "test-user"},
        client_type: :cli,
        format: :text
      }

      # Act - This should fail quickly 
      start_time = System.monotonic_time(:millisecond)
      result = Conversation.execute(command)
      end_time = System.monotonic_time(:millisecond)
      execution_time = end_time - start_time

      # Assert - Should fail fast
      assert execution_time < 1000, "Command took #{execution_time}ms, expected < 1s"

      case result do
        {:error, message} when is_binary(message) ->
          # Should get either connection manager or conversation ID error (both are fast)
          assert String.contains?(message, "connection manager") or
                   String.contains?(message, "conversation") or
                   String.contains?(message, "not running"),
                 "Expected fast error, got: #{message}"

        other ->
          flunk("Expected error message, got: #{inspect(other)}")
      end
    end
  end
end
