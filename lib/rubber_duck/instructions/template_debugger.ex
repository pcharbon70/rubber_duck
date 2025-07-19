defmodule RubberDuck.Instructions.TemplateDebugger do
  @moduledoc """
  Template debugging utilities for instruction templates.

  Provides comprehensive debugging features including:
  - Variable inspection
  - Template parsing validation
  - Execution tracing
  - Performance profiling
  - Error context analysis
  """

  alias RubberDuck.Instructions.{TemplateProcessor, TemplateInheritance}

  @type debug_info :: %{
          variables: map(),
          template_info: map(),
          render_time: non_neg_integer(),
          errors: [String.t()],
          warnings: [String.t()]
        }

  @doc """
  Processes a template with comprehensive debugging information.

  Returns both the processed result and detailed debug information.
  """
  @spec debug_template(String.t(), map(), keyword()) ::
          {:ok, String.t(), debug_info()} | {:error, term(), debug_info()}
  def debug_template(template_content, variables \\ %{}, opts \\ []) do
    start_time = System.monotonic_time(:microsecond)

    debug_info = %{
      variables: variables,
      template_info: analyze_template(template_content),
      render_time: 0,
      errors: [],
      warnings: []
    }

    case TemplateProcessor.process_template(template_content, variables, opts) do
      {:ok, result} ->
        end_time = System.monotonic_time(:microsecond)
        final_debug = %{debug_info | render_time: end_time - start_time}
        {:ok, result, final_debug}

      {:error, error} ->
        end_time = System.monotonic_time(:microsecond)
        final_debug = %{debug_info | render_time: end_time - start_time, errors: [format_error(error)]}
        {:error, error, final_debug}
    end
  end

  @doc """
  Analyzes a template structure and provides detailed information.
  """
  @spec analyze_template(String.t()) :: map()
  def analyze_template(template_content) do
    %{
      size: String.length(template_content),
      line_count: count_lines(template_content),
      variables: extract_variables(template_content),
      blocks: extract_blocks_info(template_content),
      includes: extract_includes_info(template_content),
      extends: extract_extends_info(template_content),
      complexity: calculate_complexity(template_content),
      security_score: analyze_security(template_content)
    }
  end

  @doc """
  Validates template syntax and provides detailed error information.
  """
  @spec validate_syntax(String.t()) :: {:ok, map()} | {:error, map()}
  def validate_syntax(template_content) do
    errors = []
    warnings = []

    # Check for common syntax errors
    {errors, warnings} = check_liquid_syntax(template_content, errors, warnings)
    {errors, warnings} = check_block_matching(template_content, errors, warnings)
    {errors, warnings} = check_variable_syntax(template_content, errors, warnings)

    if Enum.empty?(errors) do
      {:ok, %{warnings: warnings, info: "Template syntax is valid"}}
    else
      {:error, %{errors: errors, warnings: warnings}}
    end
  end

  @doc """
  Traces template execution step by step.
  """
  @spec trace_execution(String.t(), map()) :: {:ok, [map()]} | {:error, term()}
  def trace_execution(template_content, variables) do
    _steps = []

    # Step 1: Parse template
    step1 = %{
      step: "parse",
      description: "Parsing template structure",
      input: template_content,
      variables: variables
    }

    # Step 2: Extract inheritance info
    step2 =
      case TemplateInheritance.parse_extends(template_content) do
        {:ok, nil} ->
          %{step: "inheritance", description: "No inheritance detected", extends: nil}

        {:ok, parent} ->
          %{step: "inheritance", description: "Extends #{parent}", extends: parent}

        {:error, error} ->
          %{step: "inheritance", description: "Inheritance error", error: error}
      end

    # Step 3: Analyze blocks
    {:ok, blocks} = TemplateInheritance.extract_blocks(template_content)
    step3 = %{step: "blocks", description: "Found #{map_size(blocks)} blocks", blocks: blocks}

    {:ok, [step1, step2, step3]}
  end

  @doc """
  Profiles template performance and identifies bottlenecks.
  """
  @spec profile_template(String.t(), map(), keyword()) :: map()
  def profile_template(template_content, variables, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 100)

    times =
      1..iterations
      |> Enum.map(fn _ ->
        start_time = System.monotonic_time(:microsecond)
        TemplateProcessor.process_template(template_content, variables, opts)
        end_time = System.monotonic_time(:microsecond)
        end_time - start_time
      end)

    %{
      iterations: iterations,
      total_time: Enum.sum(times),
      average_time: Enum.sum(times) / iterations,
      min_time: Enum.min(times),
      max_time: Enum.max(times),
      percentiles: calculate_percentiles(times),
      template_size: String.length(template_content),
      variable_count: map_size(variables)
    }
  end

  @doc """
  Generates a comprehensive template report.
  """
  @spec generate_report(String.t(), map(), keyword()) :: String.t()
  def generate_report(template_content, variables \\ %{}, opts \\ []) do
    analysis = analyze_template(template_content)

    case validate_syntax(template_content) do
      {:ok, syntax_info} ->
        generate_success_report(analysis, syntax_info, variables, opts)

      {:error, syntax_info} ->
        generate_error_report(analysis, syntax_info, variables, opts)
    end
  end

  # Private functions

  defp count_lines(content) do
    String.split(content, "\n") |> length()
  end

  defp extract_variables(content) do
    ~r/\{\{\s*([a-zA-Z_][a-zA-Z0-9_\.]*)\s*\}\}/
    |> Regex.scan(content)
    |> Enum.map(fn [_, var] -> var end)
    |> Enum.uniq()
  end

  defp extract_blocks_info(content) do
    {:ok, blocks} = TemplateInheritance.extract_blocks(content)

    blocks
    |> Map.to_list()
    |> Enum.map(fn {name, block_content} ->
      %{name: name, size: String.length(block_content), lines: count_lines(block_content)}
    end)
  end

  defp extract_includes_info(content) do
    case TemplateInheritance.parse_includes(content) do
      {:ok, includes} -> includes
      {:error, _} -> []
    end
  end

  defp extract_extends_info(content) do
    case TemplateInheritance.parse_extends(content) do
      {:ok, extends} -> extends
      {:error, _} -> nil
    end
  end

  defp calculate_complexity(content) do
    # Simple complexity calculation based on control structures
    control_patterns = [
      ~r/\{%\s*if\s+/,
      ~r/\{%\s*for\s+/,
      ~r/\{%\s*unless\s+/,
      ~r/\{%\s*case\s+/,
      ~r/\{%\s*include\s+/,
      ~r/\{%\s*extends\s+/
    ]

    Enum.reduce(control_patterns, 0, fn pattern, acc ->
      acc + length(Regex.scan(pattern, content))
    end)
  end

  defp analyze_security(content) do
    # Basic security analysis - returns score from 0-100
    dangerous_patterns = [
      ~r/\bSystem\./,
      ~r/\bFile\./,
      ~r/\bIO\./,
      ~r/\beval\b/i,
      ~r/\bexec\b/i
    ]

    danger_count = Enum.count(dangerous_patterns, &Regex.match?(&1, content))
    max(0, 100 - danger_count * 20)
  end

  defp check_liquid_syntax(content, errors, warnings) do
    # Check for unmatched braces
    open_braces = length(Regex.scan(~r/\{\{/, content))
    close_braces = length(Regex.scan(~r/\}\}/, content))

    errors =
      if open_braces != close_braces do
        ["Unmatched braces: #{open_braces} opening, #{close_braces} closing" | errors]
      else
        errors
      end

    # Check for unmatched tags
    open_tags = length(Regex.scan(~r/\{%/, content))
    close_tags = length(Regex.scan(~r/%\}/, content))

    errors =
      if open_tags != close_tags do
        ["Unmatched tags: #{open_tags} opening, #{close_tags} closing" | errors]
      else
        errors
      end

    {errors, warnings}
  end

  defp check_block_matching(content, errors, warnings) do
    # Check for unmatched blocks
    if_blocks = length(Regex.scan(~r/\{%\s*if\s+/, content))
    endif_blocks = length(Regex.scan(~r/\{%\s*endif\s*%\}/, content))

    errors =
      if if_blocks != endif_blocks do
        ["Unmatched if blocks: #{if_blocks} opening, #{endif_blocks} closing" | errors]
      else
        errors
      end

    {errors, warnings}
  end

  defp check_variable_syntax(content, errors, warnings) do
    # Check for malformed variables
    malformed = Regex.scan(~r/\{\{[^}]*\{\{|\}\}[^{]*\}\}/, content)

    errors =
      if length(malformed) > 0 do
        ["Malformed variable syntax detected in #{length(malformed)} locations" | errors]
      else
        errors
      end

    {errors, warnings}
  end

  defp calculate_percentiles(times) do
    sorted = Enum.sort(times)
    count = length(sorted)

    %{
      p50: percentile(sorted, count, 0.5),
      p90: percentile(sorted, count, 0.9),
      p95: percentile(sorted, count, 0.95),
      p99: percentile(sorted, count, 0.99)
    }
  end

  defp percentile(sorted_list, count, percentile) do
    index = round(count * percentile) - 1
    Enum.at(sorted_list, max(0, index))
  end

  defp format_error(error) do
    case error do
      %{message: message} -> message
      error when is_binary(error) -> error
      error -> inspect(error)
    end
  end

  defp generate_success_report(analysis, syntax_info, _variables, _opts) do
    """
    # Template Analysis Report

    ## Overview
    - Template size: #{analysis.size} characters
    - Line count: #{analysis.line_count}
    - Complexity score: #{analysis.complexity}
    - Security score: #{analysis.security_score}/100

    ## Structure
    - Variables: #{length(analysis.variables)} (#{Enum.join(analysis.variables, ", ")})
    - Blocks: #{length(analysis.blocks)}
    - Includes: #{length(analysis.includes)}
    - Extends: #{analysis.extends || "None"}

    ## Validation
    ✅ Syntax validation passed
    #{if length(syntax_info.warnings) > 0, do: "⚠️  Warnings: #{Enum.join(syntax_info.warnings, "; ")}", else: ""}

    ## Recommendations
    #{generate_recommendations(analysis)}
    """
  end

  defp generate_error_report(analysis, syntax_info, _variables, _opts) do
    """
    # Template Analysis Report

    ## Overview
    - Template size: #{analysis.size} characters
    - Line count: #{analysis.line_count}
    - Complexity score: #{analysis.complexity}
    - Security score: #{analysis.security_score}/100

    ## Validation Errors
    ❌ Syntax validation failed
    #{Enum.map(syntax_info.errors, fn error -> "- #{error}" end) |> Enum.join("\n")}

    #{if length(syntax_info.warnings) > 0, do: "## Warnings\n#{Enum.map(syntax_info.warnings, fn warning -> "- #{warning}" end) |> Enum.join("\n")}", else: ""}

    ## Recommendations
    1. Fix syntax errors before using template
    2. Review template structure for potential issues
    """
  end

  defp generate_recommendations(analysis) do
    recommendations = []

    recommendations =
      if analysis.complexity > 20 do
        ["Consider breaking down complex template into smaller components" | recommendations]
      else
        recommendations
      end

    recommendations =
      if analysis.security_score < 80 do
        ["Review template for potential security issues" | recommendations]
      else
        recommendations
      end

    recommendations =
      if analysis.size > 10_000 do
        ["Consider optimizing template size for better performance" | recommendations]
      else
        recommendations
      end

    if Enum.empty?(recommendations) do
      "No specific recommendations - template looks good!"
    else
      Enum.with_index(recommendations, 1)
      |> Enum.map(fn {rec, i} -> "#{i}. #{rec}" end)
      |> Enum.join("\n")
    end
  end
end
