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
  alias RubberDuck.CoT.Manager, as: ConversationManager
  alias RubberDuck.CoT.Chains.AnalysisChain
  alias RubberDuck.Engine.InputValidator

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
    with {:ok, validated} <- validate_input(input) do
      # Build CoT context
      cot_context = %{
        # Required LLM parameters
        provider: validated.provider,
        model: validated.model,
        user_id: validated.user_id,
        # Context
        code: validated.content,
        context: %{
          file_path: validated.file_path,
          analysis_type: get_analysis_type(validated.options),
          language: to_string(validated.language),
          project_context: Map.get(validated.options, :project_context, %{})
        }
      }

      Logger.debug("Executing CoT analysis chain for #{validated.file_path}")

      # Execute CoT analysis chain
      case ConversationManager.execute_chain(AnalysisChain, validated.content, cot_context) do
        {:ok, cot_session} ->
          analysis_result = extract_analysis_result_from_cot(cot_session)

          # Run traditional static analysis as well
          {:ok, static_results} = run_static_analysis(validated, state)

          # Merge CoT insights with static analysis
          merged_issues = merge_analysis_results(static_results, analysis_result)

          result = %{
            file: validated.file_path,
            language: validated.language,
            issues: merged_issues,
            patterns: analysis_result.patterns,
            suggestions: analysis_result.suggestions,
            priorities: analysis_result.priorities,
            metrics: calculate_comprehensive_metrics(static_results, analysis_result),
            summary: generate_comprehensive_summary(merged_issues, analysis_result)
          }

          {:ok, result}

        {:error, reason} ->
          Logger.error("CoT analysis chain error: #{inspect(reason)}")
          Logger.warning("Falling back to legacy analysis")

          # Fallback to existing implementation
          legacy_analyze(input, state)
      end
    end
  end

  # Legacy analysis function for fallback
  defp legacy_analyze(input, state) do
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
    case InputValidator.validate_llm_input(input, [:file_path]) do
      {:ok, validated} ->
        language = detect_language(path)
        validated = Map.merge(validated, %{
          language: language,
          content: read_file_content(path)
        })
        {:ok, validated}
      {:error, reason} ->
        {:error, reason}
    end
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

    opts = [
      provider: input.provider,  # Required from input
      model: input.model,        # Required from input
      messages: [
        %{"role" => "system", "content" => get_analysis_system_prompt()},
        %{"role" => "user", "content" => prompt}
      ],
      temperature: input.temperature || 0.3,
      max_tokens: input.max_tokens || state.config[:max_tokens] || 1024,
      user_id: input.user_id
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

  # CoT integration helpers

  defp get_analysis_type(options) do
    Map.get(options, :type, "comprehensive")
  end

  defp extract_analysis_result_from_cot(cot_session) do
    # Extract results from the CoT session steps
    understanding = get_cot_step_result(cot_session, :understand_code)
    patterns = get_cot_step_result(cot_session, :identify_patterns)
    issues = get_cot_step_result(cot_session, :analyze_issues)
    suggestions = get_cot_step_result(cot_session, :suggest_improvements)
    priorities = get_cot_step_result(cot_session, :prioritize_actions)

    # Parse and structure the results
    %{
      understanding: understanding,
      patterns: parse_cot_patterns(patterns),
      issues: parse_cot_issues(issues),
      suggestions: parse_cot_suggestions(suggestions),
      priorities: parse_cot_priorities(priorities),
      complexity: estimate_cot_complexity(understanding, patterns)
    }
  end

  defp get_cot_step_result(cot_session, step_name) do
    case Map.get(cot_session[:steps], step_name) do
      %{result: result} -> result
      _ -> nil
    end
  end

  defp parse_cot_patterns(patterns_text) when is_binary(patterns_text) do
    # Extract patterns from the text
    patterns_text
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, ["pattern", "design", "structure"]))
    |> Enum.map(&String.trim/1)
  end

  defp parse_cot_patterns(_), do: []

  defp parse_cot_issues(issues_text) when is_binary(issues_text) do
    # Extract issues from the text
    issues_text
    |> String.split("\n")
    |> Enum.filter(&String.match?(&1, ~r/^\d+\./))
    |> Enum.map(fn line ->
      %{
        type: determine_issue_severity(line),
        category: determine_issue_category(line),
        message: String.replace(line, ~r/^\d+\.\s*/, ""),
        # CoT doesn't provide line numbers
        line: 1,
        column: 1,
        from_cot: true
      }
    end)
  end

  defp parse_cot_issues(_), do: []

  defp parse_cot_suggestions(suggestions_text) when is_binary(suggestions_text) do
    # Extract suggestions from the text
    suggestions_text
    |> String.split("\n")
    |> Enum.filter(&String.match?(&1, ~r/^\d+\./))
    |> Enum.map(&String.replace(&1, ~r/^\d+\.\s*/, ""))
  end

  defp parse_cot_suggestions(_), do: []

  defp parse_cot_priorities(priorities_text) when is_binary(priorities_text) do
    # Extract priority actions from the text
    %{
      critical: extract_priority_level(priorities_text, "critical"),
      high: extract_priority_level(priorities_text, "high"),
      medium: extract_priority_level(priorities_text, "medium"),
      low: extract_priority_level(priorities_text, "low")
    }
  end

  defp parse_cot_priorities(_), do: %{critical: [], high: [], medium: [], low: []}

  defp extract_priority_level(text, level) do
    text
    |> String.downcase()
    |> String.split(level)
    |> Enum.at(1, "")
    |> String.split("\n")
    |> Enum.take(5)
    |> Enum.filter(&String.contains?(&1, ["-", "*", "•"]))
    |> Enum.map(&String.trim/1)
  end

  defp determine_issue_severity(line) do
    cond do
      String.contains?(String.downcase(line), ["error", "bug", "security", "critical"]) -> :error
      String.contains?(String.downcase(line), ["warning", "performance", "deprecated"]) -> :warning
      true -> :info
    end
  end

  defp determine_issue_category(line) do
    cond do
      String.contains?(String.downcase(line), ["security", "vulnerability"]) -> :security
      String.contains?(String.downcase(line), ["performance", "slow", "memory"]) -> :performance
      String.contains?(String.downcase(line), ["style", "formatting", "convention"]) -> :style
      String.contains?(String.downcase(line), ["complexity", "maintainability"]) -> :complexity
      String.contains?(String.downcase(line), ["documentation", "doc", "comment"]) -> :documentation
      true -> :general
    end
  end

  defp estimate_cot_complexity(understanding, patterns) do
    # Simple heuristic for complexity estimation
    factors = [
      if(String.contains?(understanding || "", ["complex", "nested", "intricate"]), do: 2, else: 0),
      if(String.contains?(patterns || "", ["recursion", "callback", "metaprogramming"]), do: 3, else: 0),
      if(String.contains?(understanding || "", ["simple", "straightforward", "basic"]), do: -1, else: 0)
    ]

    base_complexity = 1
    Enum.sum([base_complexity | factors]) |> max(1) |> min(10)
  end

  defp merge_analysis_results(static_results, cot_analysis) do
    # Combine static analysis results with CoT insights
    cot_issues = cot_analysis.issues

    # Add CoT issues that don't duplicate static results
    unique_cot_issues =
      Enum.filter(cot_issues, fn cot_issue ->
        not Enum.any?(static_results, fn static_issue ->
          similar_issue?(static_issue, cot_issue)
        end)
      end)

    static_results ++ unique_cot_issues
  end

  defp similar_issue?(issue1, issue2) do
    # Simple similarity check based on message content
    String.jaro_distance(issue1.message, issue2.message) > 0.8
  end

  defp calculate_comprehensive_metrics(static_results, cot_analysis) do
    base_metrics = calculate_metrics(static_results)

    Map.merge(base_metrics, %{
      complexity_score: cot_analysis.complexity,
      patterns_found: length(cot_analysis.patterns),
      suggestions_count: length(cot_analysis.suggestions),
      has_critical_issues: length(cot_analysis.priorities.critical) > 0
    })
  end

  defp generate_comprehensive_summary(issues, cot_analysis) do
    base_summary = generate_summary(issues)

    priority_summary =
      if length(cot_analysis.priorities.critical) > 0 do
        "\nCritical issues require immediate attention!"
      else
        ""
      end

    pattern_summary =
      if length(cot_analysis.patterns) > 0 do
        "\nDetected patterns: #{Enum.join(Enum.take(cot_analysis.patterns, 3), ", ")}"
      else
        ""
      end

    base_summary <> priority_summary <> pattern_summary
  end
end
