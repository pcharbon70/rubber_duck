defmodule RubberDuck.Interface.CLI.CommandParserTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Interface.CLI.CommandParser

  describe "parse/3" do
    test "parses ask command with question" do
      assert {:ok, request} = CommandParser.parse("ask", ["How do I sort a list?"])
      
      assert request.operation == :chat
      assert request.params.message == "How do I sort a list?"
      assert request.interface == :cli
    end

    test "parses ask command with flags" do
      args = ["What is recursion?", "--model", "gpt-4", "--format", "json"]
      assert {:ok, request} = CommandParser.parse("ask", args)
      
      assert request.params.message == "What is recursion?"
      assert request.params.model == "gpt-4"
      assert request.params.format == "json"
    end

    test "returns error for ask command without question" do
      assert {:error, message} = CommandParser.parse("ask", [])
      assert message =~ "Question is required"
    end

    test "parses complete command with prompt" do
      assert {:ok, request} = CommandParser.parse("complete", ["def fibonacci(n):"])
      
      assert request.operation == :complete
      assert request.params.prompt == "def fibonacci(n):"
    end

    test "parses complete command with language flag" do
      args = ["function add(", "--language", "javascript"]
      assert {:ok, request} = CommandParser.parse("complete", args)
      
      assert request.params.prompt == "function add("
      assert request.params.language == "javascript"
    end

    test "parses analyze command with content" do
      assert {:ok, request} = CommandParser.parse("analyze", ["def hello(): print('world')"])
      
      assert request.operation == :analyze
      assert request.params.content == "def hello(): print('world')"
    end

    test "parses chat command" do
      assert {:ok, request} = CommandParser.parse("chat", ["--stream"])
      
      assert request.operation == :chat
      assert request.params.interactive == true
      assert request.params.stream == true
    end

    test "parses session commands" do
      assert {:ok, request} = CommandParser.parse("session.list", [])
      assert request.operation == :session_management
      assert request.params.action == :list

      assert {:ok, request} = CommandParser.parse("session.new", ["my-session"])
      assert request.operation == :session_management
      assert request.params.action == :new
      assert request.params.name == "my-session"

      assert {:ok, request} = CommandParser.parse("session.switch", ["session_123"])
      assert request.operation == :session_management
      assert request.params.action == :switch
      assert request.params.session_id == "session_123"
    end

    test "parses config commands" do
      assert {:ok, request} = CommandParser.parse("config.show", [])
      assert request.operation == :configuration
      assert request.params.action == :show

      assert {:ok, request} = CommandParser.parse("config.set", ["colors", "false"])
      assert request.operation == :configuration
      assert request.params.action == :set
      assert request.params.key == "colors"
      assert request.params.value == false
    end

    test "parses help command" do
      assert {:ok, request} = CommandParser.parse("help", [])
      assert request.operation == :help
      assert request.params.topic == :general

      assert {:ok, request} = CommandParser.parse("help", ["commands"])
      assert request.params.topic == :commands
    end

    test "returns error for unknown command" do
      assert {:error, message} = CommandParser.parse("unknown", [])
      assert message =~ "Unknown command"
    end
  end

  describe "parse_interactive/2" do
    test "parses regular chat message" do
      assert {:ok, request} = CommandParser.parse_interactive("Hello, how are you?")
      
      assert request.operation == :chat
      assert request.params.message == "Hello, how are you?"
      assert request.params.interactive == true
    end

    test "parses slash commands" do
      assert {:ok, request} = CommandParser.parse_interactive("/help")
      assert request.operation == :help
      assert request.params.topic == :interactive

      assert {:ok, request} = CommandParser.parse_interactive("/session list")
      assert request.operation == :session_management
      assert request.params.action == :list

      assert {:ok, request} = CommandParser.parse_interactive("/clear")
      assert request.operation == :clear

      assert {:ok, request} = CommandParser.parse_interactive("/exit")
      assert request.operation == :exit
    end

    test "returns error for empty input" do
      assert {:error, message} = CommandParser.parse_interactive("")
      assert message == "Empty input"

      assert {:error, message} = CommandParser.parse_interactive("   ")
      assert message == "Empty input"
    end

    test "returns error for unknown slash command" do
      assert {:error, message} = CommandParser.parse_interactive("/unknown")
      assert message =~ "Unknown command"
    end
  end

  describe "validate_args/2" do
    test "validates ask args" do
      valid_args = %{message: "test question"}
      assert :ok = CommandParser.validate_args(:ask, valid_args)

      invalid_args = %{message: ""}
      assert {:error, _} = CommandParser.validate_args(:ask, invalid_args)

      missing_args = %{}
      assert {:error, _} = CommandParser.validate_args(:ask, missing_args)
    end

    test "validates complete args" do
      valid_args = %{prompt: "def test():"}
      assert :ok = CommandParser.validate_args(:complete, valid_args)

      invalid_args = %{prompt: ""}
      assert {:error, _} = CommandParser.validate_args(:complete, invalid_args)
    end

    test "validates analyze args" do
      valid_args = %{content: "some content to analyze"}
      assert :ok = CommandParser.validate_args(:analyze, valid_args)

      invalid_args = %{content: ""}
      assert {:error, _} = CommandParser.validate_args(:analyze, invalid_args)
    end

    test "allows chat args to be optional" do
      empty_args = %{}
      assert :ok = CommandParser.validate_args(:chat, empty_args)

      valid_args = %{interactive: true, stream: true}
      assert :ok = CommandParser.validate_args(:chat, valid_args)
    end
  end

  describe "command_help/1" do
    test "returns help for known commands" do
      help_text = CommandParser.command_help("ask")
      assert is_binary(help_text)
      assert help_text =~ "ask"
      assert help_text =~ "question"

      help_text = CommandParser.command_help("complete")
      assert help_text =~ "complete"
      assert help_text =~ "code"

      help_text = CommandParser.command_help("chat")
      assert help_text =~ "chat"
      assert help_text =~ "interactive"
    end

    test "returns error message for unknown commands" do
      help_text = CommandParser.command_help("unknown")
      assert help_text =~ "Unknown command"
    end
  end

  describe "flag parsing" do
    test "parses boolean flags" do
      args = ["test question", "--verbose", "--stream"]
      {parsed_args, question} = extract_question_and_flags(args)
      
      assert question == "test question"
      assert parsed_args[:verbose] == true
      assert parsed_args[:stream] == true
    end

    test "parses value flags" do
      args = ["test", "--model", "gpt-4", "--temperature", "0.7"]
      {parsed_args, question} = extract_question_and_flags(args)
      
      assert question == "test"
      assert parsed_args[:model] == "gpt-4"
      assert parsed_args[:temperature] == "0.7"
    end

    test "handles mixed flags and content" do
      args = ["--model", "claude", "What is", "machine learning?", "--format", "json"]
      {parsed_args, question} = extract_question_and_flags(args)
      
      assert question == "What is machine learning?"
      assert parsed_args[:model] == "claude"
      assert parsed_args[:format] == "json"
    end
  end

  describe "type coercion" do
    test "coerces string numbers to appropriate types" do
      # Test temperature parsing
      args = ["test", "--temperature", "0.7"]
      assert {:ok, request} = CommandParser.parse("ask", args)
      assert request.params.temperature == 0.7

      # Test max_tokens parsing
      args = ["test", "--max-tokens", "100"]
      assert {:ok, request} = CommandParser.parse("ask", args)
      assert request.params.max_tokens == 100
    end

    test "handles invalid number strings" do
      args = ["test", "--temperature", "not_a_number"]
      assert {:ok, request} = CommandParser.parse("ask", args)
      assert request.params.temperature == nil
    end

    test "parses config values correctly" do
      # Boolean values
      assert {:ok, request} = CommandParser.parse("config.set", ["colors", "true"])
      assert request.params.value == true

      assert {:ok, request} = CommandParser.parse("config.set", ["colors", "false"])
      assert request.params.value == false

      # Numeric values
      assert {:ok, request} = CommandParser.parse("config.set", ["timeout", "5000"])
      assert request.params.value == 5000

      assert {:ok, request} = CommandParser.parse("config.set", ["temperature", "0.8"])
      assert request.params.value == 0.8

      # String values
      assert {:ok, request} = CommandParser.parse("config.set", ["model", "gpt-4"])
      assert request.params.value == "gpt-4"
    end
  end

  # Helper function for testing (would normally be private)
  defp extract_question_and_flags(args) do
    # This replicates the private function for testing
    {flags, non_flags} = Enum.split_with(args, &String.starts_with?(&1, "--"))
    
    parsed_flags = parse_flags(flags)
    question = Enum.join(non_flags, " ")
    
    {parsed_flags, question}
  end

  defp parse_flags(args) do
    args
    |> Enum.filter(&String.starts_with?(&1, "--"))
    |> Enum.chunk_every(2, 1, [:no_value])
    |> Enum.map(&parse_flag/1)
    |> Enum.into(%{})
  end

  defp parse_flag([flag]) do
    key = flag |> String.trim_leading("--") |> String.to_atom()
    {key, true}
  end

  defp parse_flag([flag, :no_value]) do
    key = flag |> String.trim_leading("--") |> String.to_atom()
    {key, true}
  end

  defp parse_flag([flag, value]) do
    key = flag |> String.trim_leading("--") |> String.to_atom()
    {key, value}
  end
end