defmodule RubberDuckEngines.Engines.CodeReviewEngine do
  @moduledoc """
  Analysis engine for automated code review.
  
  Provides code quality analysis, style checking, and best practice
  recommendations for Elixir code.
  """

  use RubberDuckEngines.Engine

  alias RubberDuckCore.Analysis

  @impl true
  def init_engine(config) do
    state = %{
      config: config,
      rules: Map.get(config, :rules, default_rules()),
      metrics: %{
        reviews_performed: 0,
        issues_found: 0
      }
    }
    
    {:ok, state}
  end

  @impl true
  def analyze(%Analysis{type: :code_review, input: input}, state) do
    content = Map.get(input, :code, "")
    
    try do
      # Perform code analysis
      issues = analyze_code(content, state.rules)
      metrics = calculate_metrics(content)
      
      result = %{
        issues: issues,
        metrics: metrics,
        score: calculate_score(issues, metrics),
        suggestions: generate_suggestions(issues)
      }
      
      # Update engine metrics
      new_metrics = %{state.metrics | 
        reviews_performed: state.metrics.reviews_performed + 1,
        issues_found: state.metrics.issues_found + length(issues)
      }
      
      new_state = %{state | metrics: new_metrics}
      
      {{:ok, result}, new_state}
    catch
      error -> {{:error, "Code analysis failed: #{inspect(error)}"}, state}
    end
  end

  def analyze(%Analysis{type: type}, state) do
    {{:error, "Unsupported analysis type: #{type}"}, state}
  end

  @impl true
  def capabilities do
    [
      %{
        name: :code_review,
        description: "Automated code review with quality analysis",
        input_types: [:code_review],
        output_format: :structured_report
      }
    ]
  end

  @impl true
  def health_check(state) do
    diagnostics = %{
      timestamp: DateTime.utc_now(),
      reviews_performed: state.metrics.reviews_performed,
      issues_found: state.metrics.issues_found,
      rules_count: length(state.rules)
    }
    
    {:healthy, diagnostics, state}
  end

  # Private functions for code analysis

  defp default_rules do
    [
      :unused_variables,
      :long_functions,
      :complex_conditionals,
      :missing_documentation,
      :naming_conventions
    ]
  end

  defp analyze_code(content, rules) do
    # Basic static analysis - this would be expanded with real analysis
    issues = []
    
    issues = if :unused_variables in rules do
      issues ++ check_unused_variables(content)
    else
      issues
    end
    
    issues = if :long_functions in rules do
      issues ++ check_function_length(content)
    else
      issues
    end
    
    issues = if :missing_documentation in rules do
      issues ++ check_documentation(content)
    else
      issues
    end
    
    issues
  end

  defp check_unused_variables(content) do
    # Simple check for variables starting with _ that might be unused
    if String.contains?(content, "= _") do
      [%{
        type: :warning,
        rule: :unused_variables,
        message: "Possible unused variable assignment",
        line: 1,
        suggestion: "Consider using pattern matching or renaming variable"
      }]
    else
      []
    end
  end

  defp check_function_length(content) do
    lines = String.split(content, "\n")
    
    if length(lines) > 20 do
      [%{
        type: :warning,
        rule: :long_functions,
        message: "Function appears to be quite long (#{length(lines)} lines)",
        line: 1,
        suggestion: "Consider breaking into smaller functions"
      }]
    else
      []
    end
  end

  defp check_documentation(content) do
    has_moduledoc = String.contains?(content, "@moduledoc")
    has_doc = String.contains?(content, "@doc")
    
    issues = []
    
    issues = if not has_moduledoc do
      [%{
        type: :info,
        rule: :missing_documentation,
        message: "Module documentation missing",
        line: 1,
        suggestion: "Add @moduledoc to describe the module's purpose"
      } | issues]
    else
      issues
    end
    
    issues = if String.contains?(content, "def ") and not has_doc do
      [%{
        type: :info,
        rule: :missing_documentation,
        message: "Function documentation missing",
        line: 1,
        suggestion: "Add @doc to describe function behavior"
      } | issues]
    else
      issues
    end
    
    issues
  end

  defp calculate_metrics(content) do
    lines = String.split(content, "\n")
    
    %{
      lines_of_code: length(lines),
      functions: count_functions(content),
      complexity: calculate_complexity(content)
    }
  end

  defp count_functions(content) do
    content
    |> String.split("\n")
    |> Enum.count(&String.contains?(&1, "def "))
  end

  defp calculate_complexity(content) do
    # Simple complexity calculation based on control structures
    complexity = 1
    
    complexity = complexity + count_occurrences(content, "if ")
    complexity = complexity + count_occurrences(content, "case ")
    complexity = complexity + count_occurrences(content, "cond ")
    complexity = complexity + count_occurrences(content, "with ")
    
    complexity
  end

  defp count_occurrences(content, pattern) do
    content
    |> String.split(pattern)
    |> length()
    |> Kernel.-(1)
    |> max(0)
  end

  defp calculate_score(issues, metrics) do
    base_score = 100
    
    # Deduct points for issues
    deductions = issues
    |> Enum.map(fn issue ->
      case issue.type do
        :error -> 10
        :warning -> 5
        :info -> 1
      end
    end)
    |> Enum.sum()
    
    # Complexity penalty
    complexity_penalty = max(0, metrics.complexity - 5) * 2
    
    max(0, base_score - deductions - complexity_penalty)
  end

  defp generate_suggestions(issues) do
    issues
    |> Enum.map(& &1.suggestion)
    |> Enum.uniq()
  end
end