defmodule RubberDuck.Commands.ParserTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Commands.{Parser, Command, Context}

  setup do
    context = %Context{
      user_id: "test_user",
      session_id: "test_session",
      permissions: [:read, :write, :execute]
    }
    
    {:ok, context: context}
  end

  describe "parse/3 for CLI input" do
    test "parses analyze command with path argument", %{context: context} do
      args = ["analyze", "/path/to/file.ex"]
      
      assert {:ok, command} = Parser.parse(args, :cli, context)
      assert command.name == :analyze
      assert command.args == %{path: "/path/to/file.ex"}
      assert command.client_type == :cli
      assert command.context == context
    end

    test "parses analyze command with options", %{context: context} do
      args = ["analyze", "/path/to/file.ex", "--recursive", "--type", "security"]
      
      assert {:ok, command} = Parser.parse(args, :cli, context)
      assert command.name == :analyze
      assert command.args == %{path: "/path/to/file.ex"}
      assert command.options[:recursive] == true
      assert command.options[:type] == "security"
    end

    test "parses generate command with description", %{context: context} do
      args = ["generate", "Create a GenServer module", "--language", "elixir"]
      
      assert {:ok, command} = Parser.parse(args, :cli, context)
      assert command.name == :generate
      assert command.args == %{description: "Create a GenServer module"}
      assert command.options[:language] == "elixir"
    end

    test "returns error for unknown command", %{context: context} do
      args = ["unknown_command", "arg"]
      
      assert {:error, reason} = Parser.parse(args, :cli, context)
      # Optimus returns "unrecognized arguments" for unknown commands
      assert reason =~ "unrecognized arguments" or reason =~ "Unknown command"
    end
  end

  describe "parse/3 for WebSocket input" do
    test "parses WebSocket message format", %{context: context} do
      message = %{
        "command" => "analyze",
        "args" => %{"path" => "/path/to/file.ex"},
        "options" => %{"recursive" => true}
      }
      
      assert {:ok, command} = Parser.parse(message, :websocket, context)
      assert command.name == :analyze
      assert command.args == %{path: "/path/to/file.ex"}
      assert command.options == %{recursive: true}
      assert command.client_type == :websocket
    end
  end

  describe "parse/3 for LiveView input" do
    test "parses LiveView params format", %{context: context} do
      params = %{
        "command" => "generate",
        "description" => "Create a LiveView module",
        "language" => "elixir",
        "format" => "html"
      }
      
      assert {:ok, command} = Parser.parse(params, :liveview, context)
      assert command.name == :generate
      assert command.args == %{description: "Create a LiveView module"}
      assert command.options == %{language: "elixir"}
      assert command.format == :markdown  # LiveView defaults to markdown
      assert command.client_type == :liveview
    end
  end
end