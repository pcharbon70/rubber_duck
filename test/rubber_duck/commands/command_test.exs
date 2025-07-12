defmodule RubberDuck.Commands.CommandTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Commands.{Command, Context}

  describe "Command struct" do
    test "creates a command with all required fields" do
      context = %Context{
        user_id: "test_user",
        project_id: "test_project",
        session_id: "test_session",
        permissions: [:read, :write],
        metadata: %{}
      }

      command = %Command{
        name: :analyze,
        subcommand: nil,
        args: %{path: "/test/path"},
        options: %{recursive: true},
        context: context,
        client_type: :cli,
        format: :json
      }

      assert command.name == :analyze
      assert command.args == %{path: "/test/path"}
      assert command.options == %{recursive: true}
      assert command.context.user_id == "test_user"
      assert command.client_type == :cli
      assert command.format == :json
    end

    test "validates client_type is one of allowed values" do
      context = %Context{
        user_id: "test_user",
        session_id: "test_session"
      }

      assert {:error, "Invalid client_type: :invalid_type"} = 
        Command.new(%{
          name: :analyze,
          context: context,
          client_type: :invalid_type,
          format: :json
        })
    end

    test "validates format is one of allowed values" do
      context = %Context{
        user_id: "test_user",
        session_id: "test_session"
      }

      assert {:error, "Invalid format: :invalid_format"} = 
        Command.new(%{
          name: :analyze,
          context: context,
          client_type: :cli,
          format: :invalid_format
        })
    end
  end
end