defmodule RubberDuck.MCP.Server.Prompts.CodeReviewTest do
  use ExUnit.Case, async: true

  alias RubberDuck.MCP.Server.Prompts.CodeReview
  alias Hermes.Server.Frame

  @moduletag :mcp_server

  describe "get_messages/2" do
    setup do
      frame = Hermes.Server.Frame.new()
      {:ok, frame: frame}
    end

    test "generates messages with required parameters", %{frame: frame} do
      params = %{
        language: "elixir",
        code: "def add(a, b), do: a + b",
        context: nil,
        focus_areas: ["correctness", "readability"],
        severity_level: "normal"
      }

      assert {:ok, messages, _frame} = CodeReview.get_messages(params, frame)

      assert length(messages) == 2

      # Check system message
      system_msg = Enum.find(messages, &(&1["role"] == "system"))
      assert system_msg["content"] =~ "expert elixir code reviewer"
      assert system_msg["content"] =~ "normal"
      assert system_msg["content"] =~ "correctness"
      assert system_msg["content"] =~ "readability"

      # Check user message
      user_msg = Enum.find(messages, &(&1["role"] == "user"))
      assert user_msg["content"] =~ "elixir"
      assert user_msg["content"] =~ "def add(a, b), do: a + b"
    end

    test "includes context when provided", %{frame: frame} do
      params = %{
        language: "python",
        code: "def divide(a, b): return a / b",
        context: "This function is used in financial calculations",
        focus_areas: ["correctness"],
        severity_level: "strict"
      }

      assert {:ok, messages, _frame} = CodeReview.get_messages(params, frame)

      user_msg = Enum.find(messages, &(&1["role"] == "user"))
      assert user_msg["content"] =~ "financial calculations"
    end

    test "uses default values for optional parameters", %{frame: frame} do
      params = %{
        language: "javascript",
        code: "const sum = (a, b) => a + b"
      }

      assert {:ok, messages, _frame} = CodeReview.get_messages(params, frame)

      system_msg = Enum.find(messages, &(&1["role"] == "system"))
      # Should include default focus areas
      assert system_msg["content"] =~ "correctness"
      assert system_msg["content"] =~ "performance"
      assert system_msg["content"] =~ "readability"
      assert system_msg["content"] =~ "maintainability"
      # Should use default severity
      assert system_msg["content"] =~ "normal"
    end
  end

  describe "schema validation" do
    test "defines proper arguments schema" do
      schema = CodeReview.arguments()

      assert is_list(schema)

      # Find required fields
      language_arg = Enum.find(schema, &(&1["name"] == "language"))
      assert language_arg["required"] == true

      code_arg = Enum.find(schema, &(&1["name"] == "code"))
      assert code_arg["required"] == true

      # Optional fields
      severity_arg = Enum.find(schema, &(&1["name"] == "severity_level"))
      assert severity_arg["required"] == false
      assert "enum" in Map.keys(severity_arg)
    end
  end

  describe "prompt variations" do
    setup do
      frame = Hermes.Server.Frame.new()
      {:ok, frame: frame}
    end

    test "adjusts prompt for different severity levels", %{frame: frame} do
      base_params = %{
        language: "elixir",
        code: "def test, do: :ok",
        focus_areas: ["correctness"]
      }

      # Strict
      params = Map.put(base_params, :severity_level, "strict")
      {:ok, messages, _} = CodeReview.get_messages(params, frame)
      system_msg = Enum.find(messages, &(&1["role"] == "system"))
      assert system_msg["content"] =~ "strict"

      # Lenient
      params = Map.put(base_params, :severity_level, "lenient")
      {:ok, messages, _} = CodeReview.get_messages(params, frame)
      system_msg = Enum.find(messages, &(&1["role"] == "system"))
      assert system_msg["content"] =~ "lenient"
    end

    test "customizes focus areas", %{frame: frame} do
      params = %{
        language: "rust",
        code: "fn main() {}",
        focus_areas: ["memory-safety", "concurrency", "performance"],
        severity_level: "normal"
      }

      {:ok, messages, _} = CodeReview.get_messages(params, frame)

      system_msg = Enum.find(messages, &(&1["role"] == "system"))
      assert system_msg["content"] =~ "memory-safety"
      assert system_msg["content"] =~ "concurrency"
      assert system_msg["content"] =~ "performance"
    end
  end

  describe "prompt metadata" do
    test "has proper description" do
      assert CodeReview.__description__() =~ "code review"
    end
  end
end
