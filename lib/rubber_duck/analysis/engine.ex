defmodule RubberDuck.Analysis.Engine do
  @moduledoc """
  Behavior defining the interface for code analysis engines.

  Each analysis engine focuses on a specific aspect of code quality:
  - Semantic: Dead code, complexity, dependencies
  - Style: Code smells, naming, formatting
  - Security: Vulnerabilities, secrets, unsafe patterns

  Engines process AST data and return structured analysis results.
  """

  alias RubberDuck.Analysis.AST

  @type severity :: :info | :low | :medium | :high | :critical
  @type issue_type :: atom()
  @type location :: %{
          file: String.t(),
          line: non_neg_integer(),
          column: non_neg_integer() | nil,
          end_line: non_neg_integer() | nil,
          end_column: non_neg_integer() | nil
        }

  @type issue :: %{
          type: issue_type(),
          severity: severity(),
          message: String.t(),
          location: location(),
          rule: String.t(),
          category: atom(),
          metadata: map()
        }

  @type fix_suggestion :: %{
          description: String.t(),
          diff: String.t() | nil,
          auto_applicable: boolean()
        }

  @type analysis_result :: %{
          engine: atom(),
          issues: list(issue()),
          metrics: map(),
          suggestions: %{issue_type() => list(fix_suggestion())},
          metadata: map()
        }

  @type options :: keyword()

  @doc """
  Returns the name of the analysis engine.
  """
  @callback name() :: atom()

  @doc """
  Returns a description of what this engine analyzes.
  """
  @callback description() :: String.t()

  @doc """
  Returns the categories of issues this engine can detect.
  """
  @callback categories() :: list(atom())

  @doc """
  Analyzes the given AST and returns analysis results.

  The AST is expected to be parsed using RubberDuck.Analysis.AST.
  Options can be used to configure the analysis behavior.
  """
  @callback analyze(ast_info :: AST.ast_info(), options :: options()) ::
              {:ok, analysis_result()} | {:error, term()}

  @doc """
  Analyzes raw source code when AST is not available.

  This is a fallback for when AST parsing fails or for text-based analysis.
  """
  @callback analyze_source(source :: String.t(), language :: atom(), options :: options()) ::
              {:ok, analysis_result()} | {:error, term()}

  @doc """
  Returns the default configuration for this engine.

  This can include severity thresholds, enabled rules, etc.
  """
  @callback default_config() :: map()

  @doc """
  Validates that a fix suggestion can be safely applied.
  """
  @callback validate_fix(issue :: issue(), suggestion :: fix_suggestion(), source :: String.t()) ::
              {:ok, fix_suggestion()} | {:error, String.t()}

  # Optional callbacks
  @optional_callbacks analyze_source: 3, validate_fix: 3

  @doc """
  Helper to create a standard issue structure.
  """
  def create_issue(type, severity, message, location, rule, category, metadata \\ %{}) do
    %{
      type: type,
      severity: severity,
      message: message,
      location: location,
      rule: rule,
      category: category,
      metadata: metadata
    }
  end

  @doc """
  Helper to create a fix suggestion.
  """
  def create_suggestion(description, diff \\ nil, auto_applicable \\ false) do
    %{
      description: description,
      diff: diff,
      auto_applicable: auto_applicable
    }
  end

  @doc """
  Sorts issues by severity (critical first) and then by line number.
  """
  def sort_issues(issues) do
    severity_order = %{critical: 0, high: 1, medium: 2, low: 3, info: 4}

    Enum.sort_by(issues, fn issue ->
      {Map.get(severity_order, issue.severity, 5), issue.location.line}
    end)
  end

  @doc """
  Groups issues by their type.
  """
  def group_by_type(issues) do
    Enum.group_by(issues, & &1.type)
  end

  @doc """
  Filters issues by minimum severity level.
  """
  def filter_by_severity(issues, min_severity) do
    severity_order = %{info: 0, low: 1, medium: 2, high: 3, critical: 4}
    min_level = Map.get(severity_order, min_severity, 0)

    Enum.filter(issues, fn issue ->
      issue_level = Map.get(severity_order, issue.severity, 0)
      issue_level >= min_level
    end)
  end
end
