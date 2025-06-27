defmodule RubberDuckEngines.Engines.DocumentationEngine do
  @moduledoc """
  Analysis engine for documentation quality and generation.

  Analyzes existing documentation, identifies gaps, and provides
  suggestions for improving code documentation.
  """

  use RubberDuckEngines.Engine

  alias RubberDuckCore.Analysis

  @impl true
  def init_engine(config) do
    state = %{
      config: config,
      min_doc_coverage: Map.get(config, :min_doc_coverage, 80),
      metrics: %{
        analyses_performed: 0,
        documentation_gaps: 0
      }
    }

    {:ok, state}
  end

  @impl true
  def analyze(%Analysis{type: :documentation, input: input}, state) do
    content = Map.get(input, :code, "")

    try do
      analysis_result = analyze_documentation(content)
      coverage = calculate_coverage(analysis_result)
      gaps = identify_gaps(analysis_result)
      suggestions = generate_documentation_suggestions(gaps)

      result = %{
        coverage: coverage,
        gaps: gaps,
        suggestions: suggestions,
        quality_score: calculate_quality_score(analysis_result),
        missing_docs: analysis_result.missing_docs
      }

      # Update metrics
      new_metrics = %{
        state.metrics
        | analyses_performed: state.metrics.analyses_performed + 1,
          documentation_gaps: state.metrics.documentation_gaps + length(gaps)
      }

      new_state = %{state | metrics: new_metrics}

      {{:ok, result}, new_state}
    catch
      error -> {{:error, "Documentation analysis failed: #{inspect(error)}"}, state}
    end
  end

  def analyze(%Analysis{type: type}, state) do
    {{:error, "Unsupported analysis type: #{type}"}, state}
  end

  @impl true
  def capabilities do
    [
      %{
        name: :documentation_analysis,
        description: "Documentation quality analysis and gap identification",
        input_types: [:documentation],
        output_format: :coverage_report
      }
    ]
  end

  @impl true
  def health_check(state) do
    diagnostics = %{
      timestamp: DateTime.utc_now(),
      analyses_performed: state.metrics.analyses_performed,
      documentation_gaps: state.metrics.documentation_gaps,
      min_coverage_threshold: state.min_doc_coverage
    }

    {:healthy, diagnostics, state}
  end

  @impl true
  def handle_config_change(_new_config, state) do
    {:ok, state}
  end

  # Private functions for documentation analysis

  defp analyze_documentation(content) do
    lines = String.split(content, "\n")

    %{
      total_modules: count_modules(content),
      documented_modules: count_documented_modules(content),
      total_functions: count_functions(content),
      documented_functions: count_documented_functions(content),
      has_moduledoc: String.contains?(content, "@moduledoc"),
      missing_docs: find_missing_documentation(lines)
    }
  end

  defp count_modules(content) do
    content
    |> String.split("\n")
    |> Enum.count(&String.starts_with?(String.trim(&1), "defmodule "))
  end

  defp count_documented_modules(content) do
    lines = String.split(content, "\n")

    # Simple heuristic: look for @moduledoc after defmodule
    lines
    |> Enum.with_index()
    |> Enum.count(fn {line, index} ->
      if String.starts_with?(String.trim(line), "defmodule ") do
        # Check if there's a @moduledoc in the next few lines
        next_lines = Enum.slice(lines, index + 1, 5)
        Enum.any?(next_lines, &String.contains?(&1, "@moduledoc"))
      else
        false
      end
    end)
  end

  defp count_functions(content) do
    content
    |> String.split("\n")
    |> Enum.count(fn line ->
      trimmed = String.trim(line)
      String.starts_with?(trimmed, "def ") or String.starts_with?(trimmed, "defp ")
    end)
  end

  defp count_documented_functions(content) do
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index()
    |> Enum.count(fn {line, index} ->
      trimmed = String.trim(line)

      if String.starts_with?(trimmed, "def ") or String.starts_with?(trimmed, "defp ") do
        # Check if there's a @doc before this function
        prev_lines =
          if index > 0 do
            Enum.slice(lines, max(0, index - 5), 5)
          else
            []
          end

        Enum.any?(prev_lines, &String.contains?(&1, "@doc"))
      else
        false
      end
    end)
  end

  defp find_missing_documentation(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.reduce([], fn {line, line_number}, acc ->
      trimmed = String.trim(line)

      cond do
        String.starts_with?(trimmed, "defmodule ") ->
          module_name = extract_module_name(trimmed)

          # Check if @moduledoc follows
          if has_moduledoc_after?(lines, line_number) do
            acc
          else
            [
              %{
                type: :missing_moduledoc,
                line: line_number,
                module: module_name,
                suggestion: "Add @moduledoc to describe the module's purpose"
              }
              | acc
            ]
          end

        String.starts_with?(trimmed, "def ") ->
          function_name = extract_function_name(trimmed)

          # Check if @doc precedes
          if has_doc_before?(lines, line_number) do
            acc
          else
            [
              %{
                type: :missing_function_doc,
                line: line_number,
                function: function_name,
                suggestion: "Add @doc to describe the function's behavior and parameters"
              }
              | acc
            ]
          end

        true ->
          acc
      end
    end)
  end

  defp extract_module_name(line) do
    line
    |> String.replace("defmodule ", "")
    |> String.split(" ")
    |> hd()
  end

  defp extract_function_name(line) do
    line
    |> String.replace("def ", "")
    |> String.split("(")
    |> hd()
  end

  defp has_moduledoc_after?(lines, line_number) do
    next_lines = Enum.slice(lines, line_number, 5)
    Enum.any?(next_lines, &String.contains?(&1, "@moduledoc"))
  end

  defp has_doc_before?(lines, line_number) do
    if line_number > 1 do
      prev_lines = Enum.slice(lines, max(0, line_number - 6), 5)
      Enum.any?(prev_lines, &String.contains?(&1, "@doc"))
    else
      false
    end
  end

  defp calculate_coverage(analysis) do
    module_coverage =
      if analysis.total_modules > 0 do
        analysis.documented_modules / analysis.total_modules * 100
      else
        100
      end

    function_coverage =
      if analysis.total_functions > 0 do
        analysis.documented_functions / analysis.total_functions * 100
      else
        100
      end

    %{
      modules: Float.round(module_coverage, 1),
      functions: Float.round(function_coverage, 1),
      overall: Float.round((module_coverage + function_coverage) / 2, 1)
    }
  end

  defp identify_gaps(analysis) do
    gaps = []

    gaps =
      if analysis.total_modules > analysis.documented_modules do
        undocumented_modules = analysis.total_modules - analysis.documented_modules

        [
          %{
            type: :module_documentation,
            count: undocumented_modules,
            severity:
              if(undocumented_modules > analysis.total_modules / 2, do: :high, else: :medium),
            description: "#{undocumented_modules} module(s) missing documentation"
          }
          | gaps
        ]
      else
        gaps
      end

    gaps =
      if analysis.total_functions > analysis.documented_functions do
        undocumented_functions = analysis.total_functions - analysis.documented_functions

        [
          %{
            type: :function_documentation,
            count: undocumented_functions,
            severity:
              if(undocumented_functions > analysis.total_functions / 2, do: :high, else: :medium),
            description: "#{undocumented_functions} function(s) missing documentation"
          }
          | gaps
        ]
      else
        gaps
      end

    gaps
  end

  defp generate_documentation_suggestions(gaps) do
    gaps
    |> Enum.map(fn gap ->
      case gap.type do
        :module_documentation ->
          "Add @moduledoc documentation to describe module purpose and usage"

        :function_documentation ->
          "Add @doc documentation to describe function behavior, parameters, and return values"

        _ ->
          "Improve documentation coverage"
      end
    end)
    |> Enum.uniq()
  end

  defp calculate_quality_score(analysis) do
    coverage = calculate_coverage(analysis)

    # Base score from coverage
    base_score = coverage.overall

    # Bonus for having any documentation
    doc_bonus = if analysis.has_moduledoc, do: 10, else: 0

    # Cap at 100
    min(100, base_score + doc_bonus)
  end
end
