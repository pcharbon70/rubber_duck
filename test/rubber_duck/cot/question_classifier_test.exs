defmodule RubberDuck.CoT.QuestionClassifierTest do
  use ExUnit.Case, async: true

  alias RubberDuck.CoT.QuestionClassifier

  describe "classify/2" do
    test "classifies simple factual questions" do
      simple_questions = [
        "What is Elixir?",
        "How do I install Phoenix?",
        "What does GenServer mean?",
        "Define pattern matching",
        "Explain recursion",
        "What version of Elixir should I use?",
        "Where is the documentation?",
        "When was Elixir created?",
        "Who created Elixir?",
        "Why use Elixir?"
      ]

      for question <- simple_questions do
        assert QuestionClassifier.classify(question) == :simple,
               "Expected '#{question}' to be classified as simple"
      end
    end

    test "classifies complex problem-solving questions" do
      complex_questions = [
        "How can I implement a distributed system with fault tolerance?",
        "Debug this GenServer that's crashing under load",
        "Help me optimize this slow database query",
        "What's the best approach for handling user authentication?",
        "Analyze this code and suggest improvements",
        "Design a scalable architecture for real-time messaging",
        "Implement a custom behaviour for plugin system",
        "Refactor this module to be more maintainable",
        "Generate code for a REST API with validation",
        "Create a comprehensive test suite for this module"
      ]

      for question <- complex_questions do
        assert QuestionClassifier.classify(question) == :complex,
               "Expected '#{question}' to be classified as complex"
      end
    end

    test "classifies based on question length" do
      short_simple = "What is OTP?"

      long_complex =
        "I'm working on a distributed system where I need to handle millions of concurrent connections, implement fault tolerance, manage state consistency across nodes, and ensure high availability. The system needs to process real-time data streams, perform complex calculations, and maintain audit logs. How should I architect this solution?"

      assert QuestionClassifier.classify(short_simple) == :simple
      assert QuestionClassifier.classify(long_complex) == :complex
    end

    test "considers conversation context" do
      single_message_context = %{
        messages: [%{"content" => "What is Elixir?"}],
        message_count: 1
      }

      multi_message_context = %{
        messages: [
          %{"content" => "I'm building a web app"},
          %{"content" => "It needs user authentication"},
          %{"content" => "How do I handle sessions?"},
          %{"content" => "Also, what about password hashing?"},
          %{"content" => "And how do I implement OAuth?"}
        ],
        message_count: 5
      }

      # Even simple-looking questions become complex in multi-step contexts
      assert QuestionClassifier.classify("How do I implement OAuth?", single_message_context) == :simple
      assert QuestionClassifier.classify("How do I implement OAuth?", multi_message_context) == :complex
    end

    test "detects code-related complexity" do
      code_questions = [
        "Fix this function: ```elixir\ndef broken_func(x), do: x + y\n```",
        "Review this GenServer implementation",
        "Generate a unit test for `calculate_total/2`",
        "Optimize this Enum.map operation"
      ]

      for question <- code_questions do
        assert QuestionClassifier.classify(question) == :complex,
               "Expected '#{question}' to be classified as complex"
      end
    end
  end

  describe "determine_question_type/2" do
    test "identifies factual questions" do
      factual_questions = [
        "What is Elixir?",
        "Define pattern matching",
        "Explain GenServer"
      ]

      for question <- factual_questions do
        assert QuestionClassifier.determine_question_type(question) == :factual
      end
    end

    test "identifies basic code questions" do
      basic_code_questions = [
        "Syntax for case statement",
        "Example of with clause",
        "How to use pipe operator"
      ]

      for question <- basic_code_questions do
        type = QuestionClassifier.determine_question_type(question)
        assert type in [:basic_code, :straightforward]
      end
    end

    test "identifies complex problems" do
      complex_problems = [
        "Debug this distributed system issue",
        "Optimize database performance",
        "Implement fault tolerance",
        "Design scalable architecture"
      ]

      for question <- complex_problems do
        assert QuestionClassifier.determine_question_type(question) == :complex_problem
      end
    end

    test "identifies multi-step processes from context" do
      multi_step_context = %{
        messages: [
          %{"content" => "First, I need to set up the database"},
          %{"content" => "Then, I'll create the models"},
          %{"content" => "Next, I'll implement the API"},
          %{"content" => "Finally, I'll add authentication"},
          %{"content" => "What's the next step?"}
        ],
        message_count: 5
      }

      assert QuestionClassifier.determine_question_type("What's the next step?", multi_step_context) == :multi_step
    end
  end

  describe "explain_classification/2" do
    test "provides reasoning for classifications" do
      explanation = QuestionClassifier.explain_classification("What is Elixir?")
      assert is_binary(explanation)
      assert String.contains?(explanation, "Simple factual question")

      explanation = QuestionClassifier.explain_classification("Debug this complex distributed system")
      assert is_binary(explanation)
      assert String.contains?(explanation, "Complex problem")
    end
  end

  describe "get_classification_stats/0" do
    test "returns classification statistics" do
      stats = QuestionClassifier.get_classification_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :simple_patterns)
      assert Map.has_key?(stats, :complex_indicators)
      assert Map.has_key?(stats, :simple_indicators)
      assert Map.has_key?(stats, :classification_types)

      assert is_integer(stats.simple_patterns)
      assert is_integer(stats.complex_indicators)
      assert is_integer(stats.simple_indicators)
      assert is_list(stats.classification_types)
    end
  end

  describe "edge cases" do
    test "handles empty strings" do
      assert QuestionClassifier.classify("") == :complex
      assert QuestionClassifier.classify("   ") == :complex
    end

    test "handles nil context" do
      assert QuestionClassifier.classify("What is Elixir?", nil) == :simple
    end

    test "handles malformed messages in context" do
      malformed_context = %{
        messages: [
          # empty map
          %{},
          # missing content
          %{"role" => "user"},
          # nil content
          %{"content" => nil},
          # not a map
          "invalid message"
        ],
        message_count: 4
      }

      # Should not crash, should still classify
      result = QuestionClassifier.classify("What is Elixir?", malformed_context)
      assert result in [:simple, :complex]
    end
  end

  describe "performance edge cases" do
    test "handles very long questions" do
      very_long_question = String.duplicate("This is a very long question that keeps going on and on. ", 100)

      # Should classify as complex due to length
      assert QuestionClassifier.classify(very_long_question) == :complex
    end

    test "handles questions with special characters" do
      special_questions = [
        "What is @spec in Elixir?",
        "How do I use &(&1 + 1)?",
        "Explain |> operator",
        "What does ~r/pattern/i mean?"
      ]

      for question <- special_questions do
        result = QuestionClassifier.classify(question)
        assert result in [:simple, :complex]
      end
    end
  end
end
