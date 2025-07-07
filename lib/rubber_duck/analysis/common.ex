defmodule RubberDuck.Analysis.Common do
  @moduledoc """
  Common types, utilities, and constants for code analysis engines.

  Provides shared functionality for issue detection, metric calculation,
  and result formatting across all analysis engines.
  """

  alias RubberDuck.Analysis.AST

  # Severity levels from least to most severe
  @severities [:info, :low, :medium, :high, :critical]

  # Common issue categories
  @categories %{
    complexity: "Code Complexity",
    maintainability: "Maintainability",
    security: "Security",
    performance: "Performance",
    style: "Code Style",
    correctness: "Correctness",
    design: "Design",
    documentation: "Documentation"
  }

  # Elixir-specific code smell types based on research
  @elixir_smells %{
    # Design-related smells
    genserver_envy: %{
      category: :design,
      severity: :medium,
      message: "Using Task/Agent for general purpose functionality instead of GenServer"
    },
    unsupervised_process: %{
      category: :design,
      severity: :high,
      message: "Process created outside of a supervision tree"
    },
    agent_obsession: %{
      category: :design,
      severity: :medium,
      message: "Multiple modules directly manipulating the same Agent"
    },
    large_messages: %{
      category: :performance,
      severity: :medium,
      message: "Passing large data structures between processes"
    },

    # Low-level concerns
    long_function: %{
      category: :complexity,
      severity: :medium,
      message: "Function exceeds recommended length (10 lines)"
    },
    long_parameter_list: %{
      category: :complexity,
      severity: :low,
      message: "Function has too many parameters (> 4)"
    },
    complex_branching: %{
      category: :complexity,
      severity: :medium,
      message: "Excessive branching complexity (nested cases, multiple conditions)"
    },
    primitive_obsession: %{
      category: :design,
      severity: :low,
      message: "Overuse of primitive types instead of custom structs"
    },

    # Traditional smells adapted for Elixir
    duplicated_code: %{
      category: :maintainability,
      severity: :medium,
      message: "Similar code found in multiple locations"
    },
    dead_code: %{
      category: :maintainability,
      severity: :low,
      message: "Unused function or module"
    },
    dynamic_atom_creation: %{
      category: :security,
      severity: :high,
      message: "Creating atoms dynamically can lead to memory exhaustion"
    }
  }

  @doc """
  Returns all supported severity levels.
  """
  def severities, do: @severities

  @doc """
  Returns all issue categories with descriptions.
  """
  def categories, do: @categories

  @doc """
  Returns Elixir-specific code smell definitions.
  """
  def elixir_smells, do: @elixir_smells

  @doc """
  Calculates cyclomatic complexity for a function AST.

  Counts decision points: if, case, cond, &&, ||, try
  """
  def calculate_cyclomatic_complexity(function_ast) do
    # Start with 1 for the function itself
    complexity = 1

    # Count decision points
    complexity + count_decision_points(function_ast)
  end

  defp count_decision_points(ast) do
    count = 0

    # Use AST traversal to count decision structures
    Macro.prewalk(ast, count, fn
      # Conditional structures
      {:if, _, _}, acc -> {ast, acc + 1}
      {:unless, _, _}, acc -> {ast, acc + 1}
      {:case, _, _}, acc -> {ast, acc + 1}
      {:cond, _, _}, acc -> {ast, acc + 1}
      # Boolean operators
      {:and, _, _}, acc -> {ast, acc + 1}
      {:or, _, _}, acc -> {ast, acc + 1}
      # Pattern matching in function heads counts as branches
      {:->, _, _}, acc -> {ast, acc + 1}
      # Try/catch blocks
      {:try, _, _}, acc -> {ast, acc + 1}
      # Default: no increment
      node, acc -> {node, acc}
    end)
    |> elem(1)
  end

  @doc """
  Calculates the depth of nested structures in AST.
  """
  def calculate_nesting_depth(ast) do
    calculate_max_depth(ast, 0)
  end

  defp calculate_max_depth(ast, current_depth) when is_tuple(ast) do
    case ast do
      {:case, _, [_, [do: clauses]]} ->
        clause_depth =
          Enum.map(clauses, fn {:->, _, [_, body]} ->
            calculate_max_depth(body, current_depth + 1)
          end)
          |> Enum.max(fn -> current_depth + 1 end)

        clause_depth

      {:if, _, [_, [do: do_block, else: else_block]]} ->
        max(
          calculate_max_depth(do_block, current_depth + 1),
          calculate_max_depth(else_block, current_depth + 1)
        )

      {:cond, _, [[do: clauses]]} ->
        clause_depth =
          Enum.map(clauses, fn {:->, _, [_, body]} ->
            calculate_max_depth(body, current_depth + 1)
          end)
          |> Enum.max(fn -> current_depth + 1 end)

        clause_depth

      {_, _, children} when is_list(children) ->
        children
        |> Enum.map(&calculate_max_depth(&1, current_depth))
        |> Enum.max(fn -> current_depth end)

      _ ->
        current_depth
    end
  end

  defp calculate_max_depth(ast, current_depth) when is_list(ast) do
    ast
    |> Enum.map(&calculate_max_depth(&1, current_depth))
    |> Enum.max(fn -> current_depth end)
  end

  defp calculate_max_depth(_, current_depth), do: current_depth

  @doc """
  Extracts location information from AST metadata.
  """
  def extract_location(ast_node, file_path) do
    case ast_node do
      {_, meta, _} when is_list(meta) ->
        %{
          file: file_path,
          line: Keyword.get(meta, :line, 0),
          column: Keyword.get(meta, :column, nil),
          end_line: Keyword.get(meta, :end_line, nil),
          end_column: Keyword.get(meta, :end_column, nil)
        }

      _ ->
        %{file: file_path, line: 0, column: nil, end_line: nil, end_column: nil}
    end
  end

  @doc """
  Formats an issue for display.
  """
  def format_issue(issue) do
    severity_color =
      case issue.severity do
        :critical -> :red
        :high -> :light_red
        :medium -> :yellow
        :low -> :light_yellow
        :info -> :light_cyan
      end

    location =
      if issue.location.column do
        "#{issue.location.file}:#{issue.location.line}:#{issue.location.column}"
      else
        "#{issue.location.file}:#{issue.location.line}"
      end

    """
    #{IO.ANSI.format([severity_color, "[#{String.upcase(to_string(issue.severity))}]", :reset])}
    #{issue.message}
    Location: #{location}
    Rule: #{issue.rule}
    Category: #{issue.category}
    """
  end

  @doc """
  Checks if a function name follows Elixir conventions.
  """
  def valid_function_name?(name) when is_atom(name) do
    name_str = Atom.to_string(name)

    # Should be snake_case, may end with ? or !
    Regex.match?(~r/^[a-z][a-z0-9_]*[?!]?$/, name_str)
  end

  @doc """
  Checks if a module name follows Elixir conventions.
  """
  def valid_module_name?(name) when is_atom(name) do
    name
    |> Module.split()
    |> Enum.all?(&valid_module_part?/1)
  end

  defp valid_module_part?(part) do
    # Each part should be PascalCase
    Regex.match?(~r/^[A-Z][A-Za-z0-9]*$/, part)
  end

  @doc """
  Detects if a value is a hardcoded secret pattern.
  """
  def potential_secret?(value) when is_binary(value) do
    # Check for common secret patterns
    secret_patterns = [
      ~r/api[_-]?key/i,
      ~r/api[_-]?secret/i,
      ~r/password/i,
      ~r/passwd/i,
      ~r/private[_-]?key/i,
      ~r/secret[_-]?key/i,
      ~r/auth[_-]?token/i,
      ~r/access[_-]?token/i,
      # Long hex strings
      ~r/[a-f0-9]{32,}/i
    ]

    Enum.any?(secret_patterns, &Regex.match?(&1, value))
  end

  def potential_secret?(_), do: false
end

