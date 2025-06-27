defmodule RubberDuckEngines.Engines.TestingEngine do
  @moduledoc """
  Analysis engine for test coverage and quality assessment.

  Analyzes test files, identifies testing gaps, and provides
  suggestions for improving test coverage and quality.
  """

  use RubberDuckEngines.Engine

  alias RubberDuckCore.Analysis

  @impl true
  def init_engine(config) do
    state = %{
      config: config,
      min_test_coverage: Map.get(config, :min_test_coverage, 80),
      metrics: %{
        test_analyses: 0,
        gaps_identified: 0
      }
    }

    {:ok, state}
  end

  @impl true
  def analyze(%Analysis{type: :testing, input: input}, state) do
    code_content = Map.get(input, :code, "")
    test_content = Map.get(input, :tests, "")

    try do
      analysis_result = analyze_test_coverage(code_content, test_content)
      gaps = identify_test_gaps(analysis_result)
      suggestions = generate_test_suggestions(gaps, analysis_result)

      result = %{
        coverage: analysis_result.coverage,
        test_quality: analysis_result.quality,
        gaps: gaps,
        suggestions: suggestions,
        test_score: calculate_test_score(analysis_result)
      }

      # Update metrics
      new_metrics = %{
        state.metrics
        | test_analyses: state.metrics.test_analyses + 1,
          gaps_identified: state.metrics.gaps_identified + length(gaps)
      }

      new_state = %{state | metrics: new_metrics}

      {{:ok, result}, new_state}
    catch
      error -> {{:error, "Testing analysis failed: #{inspect(error)}"}, state}
    end
  end

  def analyze(%Analysis{type: type}, state) do
    {{:error, "Unsupported analysis type: #{type}"}, state}
  end

  @impl true
  def capabilities do
    [
      %{
        name: :test_analysis,
        description: "Test coverage and quality analysis",
        input_types: [:testing],
        output_format: :test_report
      }
    ]
  end

  @impl true
  def health_check(state) do
    diagnostics = %{
      timestamp: DateTime.utc_now(),
      test_analyses: state.metrics.test_analyses,
      gaps_identified: state.metrics.gaps_identified,
      min_coverage_threshold: state.min_test_coverage
    }

    {:healthy, diagnostics, state}
  end

  @impl true
  def handle_config_change(_new_config, state) do
    {:ok, state}
  end

  # Private functions for test analysis

  defp analyze_test_coverage(code_content, test_content) do
    code_functions = extract_functions(code_content)
    test_functions = extract_test_functions(test_content)
    tested_functions = identify_tested_functions(code_functions, test_content)

    coverage_percentage =
      if length(code_functions) > 0 do
        length(tested_functions) / length(code_functions) * 100
      else
        100
      end

    %{
      total_functions: length(code_functions),
      tested_functions: length(tested_functions),
      total_tests: length(test_functions),
      coverage: Float.round(coverage_percentage, 1),
      quality: assess_test_quality(test_content),
      untested_functions: code_functions -- tested_functions
    }
  end

  defp extract_functions(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(fn line ->
      String.starts_with?(line, "def ") and not String.starts_with?(line, "defp ")
    end)
    |> Enum.map(&extract_function_name/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_test_functions(content) do
    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.starts_with?(&1, "test "))
    |> Enum.map(&extract_test_name/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_function_name(line) do
    case Regex.run(~r/def\s+([a-zA-Z_][a-zA-Z0-9_]*\??!)/, line) do
      [_, function_name] -> function_name
      _ -> nil
    end
  end

  defp extract_test_name(line) do
    case Regex.run(~r/test\s+"([^"]+)"/, line) do
      [_, test_name] ->
        test_name

      _ ->
        case Regex.run(~r/test\s+:([a-zA-Z_][a-zA-Z0-9_]*)/, line) do
          [_, test_name] -> test_name
          _ -> nil
        end
    end
  end

  defp identify_tested_functions(code_functions, test_content) do
    code_functions
    |> Enum.filter(fn function_name ->
      # Simple heuristic: check if function name appears in test content
      String.contains?(test_content, function_name)
    end)
  end

  defp assess_test_quality(test_content) do
    _lines = String.split(test_content, "\n")

    quality_metrics = %{
      has_assertions: String.contains?(test_content, "assert"),
      has_setup: String.contains?(test_content, "setup"),
      has_describe_blocks: String.contains?(test_content, "describe"),
      test_count: count_tests(test_content),
      assertion_count: count_assertions(test_content)
    }

    calculate_quality_score(quality_metrics)
  end

  defp count_tests(content) do
    content
    |> String.split("\n")
    |> Enum.count(&String.contains?(&1, "test "))
  end

  defp count_assertions(content) do
    assertion_patterns = ["assert", "refute", "assert_receive", "assert_raise"]

    assertion_patterns
    |> Enum.map(fn pattern ->
      content
      |> String.split("\n")
      |> Enum.count(&String.contains?(&1, pattern))
    end)
    |> Enum.sum()
  end

  defp calculate_quality_score(metrics) do
    base_score = 50

    # Bonus for having assertions
    score = if metrics.has_assertions, do: base_score + 20, else: base_score

    # Bonus for setup blocks
    score = if metrics.has_setup, do: score + 10, else: score

    # Bonus for describe blocks (organization)
    score = if metrics.has_describe_blocks, do: score + 10, else: score

    # Bonus for assertion density
    if metrics.test_count > 0 do
      assertion_density = metrics.assertion_count / metrics.test_count
      density_bonus = min(10, assertion_density * 2)
      score + density_bonus
    else
      score
    end
  end

  defp identify_test_gaps(analysis) do
    gaps = []

    # Coverage gap
    gaps =
      if analysis.coverage < 80 do
        [
          %{
            type: :low_coverage,
            severity: if(analysis.coverage < 50, do: :high, else: :medium),
            description: "Test coverage is #{analysis.coverage}% (below recommended 80%)",
            affected_functions: analysis.untested_functions
          }
          | gaps
        ]
      else
        gaps
      end

    # Missing tests for specific functions
    gaps =
      if length(analysis.untested_functions) > 0 do
        [
          %{
            type: :untested_functions,
            severity: :medium,
            description: "#{length(analysis.untested_functions)} function(s) have no tests",
            affected_functions: analysis.untested_functions
          }
          | gaps
        ]
      else
        gaps
      end

    # Test quality issues
    gaps =
      if analysis.quality < 70 do
        [
          %{
            type: :test_quality,
            severity: :low,
            description: "Test quality score is low (#{Float.round(analysis.quality, 1)}%)",
            affected_functions: []
          }
          | gaps
        ]
      else
        gaps
      end

    gaps
  end

  defp generate_test_suggestions(gaps, analysis) do
    suggestions = []

    suggestions =
      if Enum.any?(gaps, &(&1.type == :low_coverage)) do
        [
          "Add tests for untested functions to improve coverage",
          "Consider using property-based testing for complex functions"
          | suggestions
        ]
      else
        suggestions
      end

    suggestions =
      if Enum.any?(gaps, &(&1.type == :test_quality)) do
        quality_suggestions = [
          "Add more assertions to verify behavior thoroughly",
          "Use setup blocks to reduce test duplication",
          "Organize tests with describe blocks for better structure",
          "Test edge cases and error conditions"
        ]

        suggestions ++ quality_suggestions
      else
        suggestions
      end

    suggestions =
      if analysis.total_tests == 0 do
        [
          "Create a test file with ExUnit.Case",
          "Start with testing the main public functions",
          "Add both positive and negative test cases"
          | suggestions
        ]
      else
        suggestions
      end

    Enum.uniq(suggestions)
  end

  defp calculate_test_score(analysis) do
    coverage_score = analysis.coverage
    quality_score = analysis.quality

    # Weighted average: 60% coverage, 40% quality
    Float.round(coverage_score * 0.6 + quality_score * 0.4, 1)
  end
end
