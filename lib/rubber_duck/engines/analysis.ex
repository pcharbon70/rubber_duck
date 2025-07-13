defmodule RubberDuck.Engines.Analysis do
  @moduledoc """
  Code analysis engine that combines static analysis with LLM-enhanced insights.

  This engine analyzes code for:
  - Code quality issues
  - Security vulnerabilities
  - Performance problems
  - Style violations
  - Complexity metrics

  It integrates with the existing analysis workflow while adding LLM capabilities
  for deeper insights and explanations.
  """

  @behaviour RubberDuck.Engine

  require Logger

  alias RubberDuck.LLM
  alias RubberDuck.LLM.Config

  @impl true
  def init(config) do
    state = %{
      config: config,
      analyzers: load_analyzers(config)
    }

    {:ok, state}
  end

  @impl true
  def execute(input, state) do
    with {:ok, validated} <- validate_input(input),
         {:ok, static_results} <- run_static_analysis(validated, state),
         {:ok, enhanced_results} <- enhance_with_llm(static_results, validated, state) do
      result = %{
        file: validated.file_path,
        language: validated.language,
        issues: enhanced_results,
        metrics: calculate_metrics(static_results),
        summary: generate_summary(enhanced_results)
      }

      {:ok, result}
    end
  end

  @impl true
  def capabilities do
    [:code_analysis, :security_scanning, :style_checking, :complexity_analysis]
  end

  defp validate_input(%{file_path: path} = input) when is_binary(path) do
    language = detect_language(path)

    validated = %{
      file_path: path,
      language: language,
      content: read_file_content(path),
      options: Map.get(input, :options, %{})
    }

    {:ok, validated}
  end

  defp validate_input(_), do: {:error, :invalid_input}

  defp detect_language(path) do
    case Path.extname(path) do
      ".ex" -> :elixir
      ".exs" -> :elixir
      ".js" -> :javascript
      ".py" -> :python
      _ -> :unknown
    end
  end

  defp read_file_content(path) do
    case File.read(path) do
      {:ok, content} -> content
      {:error, _} -> ""
    end
  end

  defp run_static_analysis(input, state) do
    # Run appropriate analyzers based on language
    results =
      case input.language do
        :elixir -> run_elixir_analysis(input, state)
        :javascript -> run_javascript_analysis(input, state)
        :python -> run_python_analysis(input, state)
        _ -> []
      end

    {:ok, results}
  end

  defp run_elixir_analysis(input, _state) do
    issues = []

    # Check for common Elixir issues
    content = input.content
    lines = String.split(content, "\n")

    # Check for unused variables
    unused_vars = find_unused_variables(content)

    issues =
      issues ++
        Enum.map(unused_vars, fn var ->
          %{
            type: :warning,
            category: :unused_variable,
            message: "Unused variable: #{var.name}",
            line: var.line,
            column: var.column
          }
        end)

    # Check for missing documentation
    missing_docs = find_missing_documentation(content)
    issues = issues ++ missing_docs

    # Check for code smells
    smells = detect_code_smells(content, lines)
    issues = issues ++ smells

    issues
  end

  defp run_javascript_analysis(_input, _state) do
    # Placeholder for JavaScript analysis
    []
  end

  defp run_python_analysis(_input, _state) do
    # Placeholder for Python analysis
    []
  end

  defp find_unused_variables(content) do
    # Simple pattern matching for unused variables
    # In a real implementation, would use AST analysis

    ~r/_\w+\s*=/
    |> Regex.scan(content)
    |> Enum.map(fn [match] ->
      %{
        name: String.trim(match, " ="),
        # Would calculate actual line
        line: 1,
        column: 1
      }
    end)
  end

  defp find_missing_documentation(content) do
    # Check for public functions without @doc
    issues = []

    if String.contains?(content, "def ") and not String.contains?(content, "@doc") do
      issues ++
        [
          %{
            type: :info,
            category: :documentation,
            message: "Public functions should have @doc documentation",
            line: 1,
            column: 1
          }
        ]
    else
      issues
    end
  end

  defp detect_code_smells(_content, lines) do
    issues = []

    # Check for long functions
    function_lengths = analyze_function_lengths(lines)

    issues =
      issues ++
        Enum.flat_map(function_lengths, fn {_func, length, line} ->
          if length > 20 do
            [
              %{
                type: :warning,
                category: :complexity,
                message: "Function is too long (#{length} lines). Consider breaking it up.",
                line: line,
                column: 1
              }
            ]
          else
            []
          end
        end)

    # Check for deeply nested code
    max_nesting = calculate_max_nesting(lines)

    if max_nesting > 3 do
      issues ++
        [
          %{
            type: :warning,
            category: :complexity,
            message: "Code has deep nesting (level #{max_nesting}). Consider refactoring.",
            line: 1,
            column: 1
          }
        ]
    else
      issues
    end
  end

  defp analyze_function_lengths(lines) do
    # Simple function length analysis
    lines
    |> Enum.with_index(1)
    |> Enum.reduce({[], nil, 0}, fn {line, line_num}, {results, current_func, start_line} ->
      cond do
        String.match?(line, ~r/^\s*def\s+/) ->
          func_name = extract_function_name(line)

          if current_func do
            # End previous function
            length = line_num - start_line
            {[{current_func, length, start_line} | results], func_name, line_num}
          else
            {results, func_name, line_num}
          end

        String.match?(line, ~r/^\s*end\s*$/) and current_func ->
          # End current function
          length = line_num - start_line + 1
          {[{current_func, length, start_line} | results], nil, 0}

        true ->
          {results, current_func, start_line}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp extract_function_name(line) do
    case Regex.run(~r/def\s+(\w+)/, line) do
      [_, name] -> name
      _ -> "unknown"
    end
  end

  defp calculate_max_nesting(lines) do
    lines
    |> Enum.map(&calculate_indentation/1)
    |> Enum.max(fn -> 0 end)
    # Assuming 2-space indentation
    |> div(2)
  end

  defp calculate_indentation(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, spaces] -> String.length(spaces)
      _ -> 0
    end
  end

  defp enhance_with_llm(static_results, input, state) do
    # Group issues by type for batch processing
    grouped_issues = Enum.group_by(static_results, & &1.category)

    # Enhance each group with LLM insights
    enhanced_issues =
      Enum.flat_map(grouped_issues, fn {category, issues} ->
        case enhance_issue_group(category, issues, input, state) do
          {:ok, enhanced} -> enhanced
          # Fall back to original issues
          {:error, _} -> issues
        end
      end)

    {:ok, enhanced_issues}
  end

  defp enhance_issue_group(category, issues, input, state) do
    prompt = build_analysis_prompt(category, issues, input)

    # Get current provider and model from configuration
    {provider, model} = Config.get_current_provider_and_model()

    opts = [
      provider: provider,
      model: model,
      messages: [
        %{"role" => "system", "content" => get_analysis_system_prompt()},
        %{"role" => "user", "content" => prompt}
      ],
      temperature: 0.3,
      max_tokens: state.config[:max_tokens] || 1024
    ]

    case LLM.Service.completion(opts) do
      {:ok, response} ->
        enhanced = parse_llm_analysis(response, issues)
        {:ok, enhanced}

      {:error, reason} ->
        Logger.debug("LLM analysis failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_analysis_prompt(category, issues, input) do
    issue_descriptions =
      Enum.map(issues, fn issue ->
        "Line #{issue.line}: #{issue.message}"
      end)
      |> Enum.join("\n")

    """
    Analyze the following #{category} issues in #{input.language} code:

    #{issue_descriptions}

    For each issue, provide:
    1. A brief explanation of why it's a problem
    2. A suggested fix
    3. The potential impact if not fixed

    Keep explanations concise and actionable.
    """
  end

  defp get_analysis_system_prompt do
    """
    You are a code analysis expert. Provide clear, actionable insights about code issues.
    Focus on practical solutions and real-world impact.
    Be concise but thorough in your explanations.
    """
  end

  defp parse_llm_analysis(response, original_issues) do
    content = get_in(response.choices, [Access.at(0), :message, "content"]) || ""

    # Simple parsing - in production would be more sophisticated
    insights = String.split(content, "\n\n")

    original_issues
    |> Enum.zip(insights)
    |> Enum.map(fn {issue, insight} ->
      Map.merge(issue, %{
        explanation: insight,
        enhanced: true
      })
    end)
  end

  defp calculate_metrics(results) do
    %{
      total_issues: length(results),
      by_type: Enum.frequencies_by(results, & &1.type),
      by_category: Enum.frequencies_by(results, & &1.category)
    }
  end

  defp generate_summary(results) do
    total = length(results)
    critical = Enum.count(results, &(&1.type == :error))
    warnings = Enum.count(results, &(&1.type == :warning))

    """
    Found #{total} issues: #{critical} errors, #{warnings} warnings.
    Main concerns: #{summarize_categories(results)}.
    """
  end

  defp summarize_categories(results) do
    results
    |> Enum.map(& &1.category)
    |> Enum.uniq()
    |> Enum.map(&Atom.to_string/1)
    |> Enum.map(&String.replace(&1, "_", " "))
    |> Enum.join(", ")
  end

  defp load_analyzers(config) do
    # Load configured analyzers
    Keyword.get(config, :analyzers, [:static, :security, :style])
  end
end
