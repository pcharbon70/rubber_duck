defmodule RubberDuck.Commands.Handlers.ConversationTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Commands.{Command, Context}
  alias RubberDuck.Commands.Handlers.Conversation

  describe "conversation commands" do
    test "can start a conversation" do
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
        args: %{title: "Test Conversation"},
        options: %{type: "coding"},
        context: context,
        client_type: :cli,
        format: :text
      }

      assert {:ok, result} = Conversation.execute(command)
      assert is_binary(result)
      assert String.contains?(result, "Conversation created successfully")
    end

    test "can list conversations" do
      context = Context.new(%{
        user_id: Ash.UUID.generate(),
        project_id: nil,
        session_id: "test_session",
        permissions: [:read, :write],
        metadata: %{}
      })

      command = %Command{
        name: :conversation,
        subcommand: :list,
        args: %{},
        options: %{},
        context: context,
        client_type: :cli,
        format: :text
      }

      assert {:ok, result} = Conversation.execute(command)
      assert is_binary(result)
    end

    test "returns error for unknown subcommand" do
      context = Context.new(%{
        user_id: Ash.UUID.generate(),
        project_id: nil,
        session_id: "test_session",
        permissions: [:read, :write],
        metadata: %{}
      })

      command = %Command{
        name: :conversation,
        subcommand: :unknown,
        args: %{},
        options: %{},
        context: context,
        client_type: :cli,
        format: :text
      }

      assert {:error, message} = Conversation.execute(command)
      assert String.contains?(message, "Unknown conversation subcommand")
    end
  end
end