defmodule RubberDuck.SelfCorrection.EngineTest do
  use ExUnit.Case, async: false

  alias RubberDuck.SelfCorrection.Engine

  setup do
    # Ensure clean state
    :ok = Application.stop(:rubber_duck)
    :ok = Application.start(:rubber_duck)

    # Wait for processes to start
    Process.sleep(100)

    :ok
  end

  describe "correct/1" do
    test "corrects simple syntax errors in code" do
      request = %{
        content: """
        defmodule Example do
          def hello do
            "Hello, world!"
        end
        """,
        type: :code,
        context: %{language: "elixir"},
        max_iterations: 5
      }

      assert {:ok, result} = Engine.correct(request)
      assert result.corrected_content =~ "end"
      assert result.success == true
      assert result.iterations > 0
      assert length(result.corrections_applied) > 0
    end

    test "improves text clarity" do
      request = %{
        content:
          "This is a very very very long sentence that could definitely be written in a much more clear and concise way without losing any of the important meaning.",
        type: :text,
        context: %{},
        target_score: 0.7
      }

      assert {:ok, result} = Engine.correct(request)
      assert result.success == true
      assert result.final_evaluation.overall_score >= 0.7
    end

    test "handles mixed content" do
      request = %{
        content: """
        # Example Code

        Here's a function with issues:

        ```elixir
        def calc(x, y)
          x + y
        ```

        This function calculates things.
        """,
        type: :mixed,
        context: %{}
      }

      assert {:ok, result} = Engine.correct(request)
      assert result.success == true
      assert result.corrected_content =~ "def calc(x, y) do"
    end

    test "respects max iterations limit" do
      request = %{
        content: "Bad content with many issues",
        type: :text,
        context: %{},
        max_iterations: 2
      }

      assert {:ok, result} = Engine.correct(request)
      assert result.iterations <= 2
    end

    test "detects convergence early" do
      # Content that's already good
      request = %{
        content: """
        defmodule WellWritten do
          @moduledoc "A well-documented module"
          
          @doc "Adds two numbers"
          def add(x, y) do
            x + y
          end
        end
        """,
        type: :code,
        context: %{language: "elixir"}
      }

      assert {:ok, result} = Engine.correct(request)
      # Should stop early
      assert result.iterations == 1
      assert result.success == true
    end
  end

  describe "analyze/1" do
    test "analyzes content without applying corrections" do
      request = %{
        content: "def hello do 'world'",
        type: :code,
        context: %{language: "elixir"}
      }

      assert {:ok, analysis} = Engine.analyze(request)
      assert analysis.initial_evaluation
      assert length(analysis.strategy_analyses) > 0
      assert analysis.recommended_corrections
    end
  end

  describe "get_status/0" do
    test "returns engine status" do
      status = Engine.get_status()

      assert status.state in [:idle, :correcting]
      assert is_map(status.stats)
      assert is_integer(status.stats.total_corrections)
      assert is_integer(status.stats.successful_corrections)
    end
  end

  describe "strategy integration" do
    test "uses syntax strategy for syntax errors" do
      request = %{
        # Missing closing paren
        content: "def broken(x do x end",
        type: :code,
        context: %{language: "elixir"},
        strategies: [:syntax]
      }

      assert {:ok, result} = Engine.correct(request)

      assert Enum.any?(result.corrections_applied, fn c ->
               c.strategy == :syntax
             end)
    end

    test "uses semantic strategy for clarity issues" do
      request = %{
        content: "The thing does stuff with the data and returns a result.",
        type: :text,
        context: %{},
        strategies: [:semantic]
      }

      assert {:ok, result} = Engine.correct(request)

      assert result.corrections_applied == [] ||
               Enum.any?(result.corrections_applied, fn c ->
                 c.strategy == :semantic
               end)
    end

    test "uses logic strategy for logical issues" do
      request = %{
        content: """
        if true do
          "This always runs"
        else
          "This never runs"
        end
        """,
        type: :code,
        context: %{language: "elixir"},
        strategies: [:logic]
      }

      assert {:ok, result} = Engine.correct(request)
      # Logic strategy should identify the constant condition
      assert Enum.any?(result.issues_found, fn issue ->
               issue.type == :constant_condition
             end)
    end
  end

  describe "error handling" do
    test "handles invalid content type" do
      request = %{
        content: "test",
        type: :invalid_type,
        context: %{}
      }

      assert {:error, reason} = Engine.correct(request)
      assert reason =~ "Unsupported content type"
    end

    test "handles missing required fields" do
      request = %{
        type: :code,
        context: %{}
      }

      assert {:error, reason} = Engine.correct(request)
      assert reason =~ "Missing required field"
    end

    test "handles timeout gracefully" do
      request = %{
        content: "test content",
        type: :text,
        context: %{},
        # 1ms timeout
        timeout: 1
      }

      # This should timeout
      assert {:error, :timeout} = Engine.correct(request)
    end
  end
end
