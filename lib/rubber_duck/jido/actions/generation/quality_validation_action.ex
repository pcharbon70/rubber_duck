defmodule RubberDuck.Jido.Actions.Generation.QualityValidationAction do
  @moduledoc """
  Action for validating the quality of generated code.

  This action provides comprehensive quality validation including syntax
  checking, security analysis, complexity assessment, and style verification
  to ensure generated code meets quality standards.

  ## Parameters

  - `code` - Code to validate (required)
  - `language` - Programming language (default: :elixir)
  - `validation_types` - Types of validation to perform (default: [:syntax, :style, :security])
  - `quality_standards` - Quality standards to enforce (default: :standard)
  - `context` - Additional context for validation

  ## Returns

  - `{:ok, result}` - Validation completed with results and recommendations
  - `{:error, reason}` - Validation failed

  ## Example

      params = %{
        code: "defmodule Test do\\n  def hello, do: :world\\nend",
        language: :elixir,
        validation_types: [:syntax, :style, :security, :complexity]
      }

      {:ok, result} = QualityValidationAction.run(params, context)
  """

  use Jido.Action,
    name: "quality_validation",
    description: "Validate the quality of generated code",
    schema: [
      code: [
        type: :string,
        required: true,
        doc: "Code to validate"
      ],
      language: [
        type: :atom,
        default: :elixir,
        doc: "Programming language"
      ],
      validation_types: [
        type: {:list, :atom},
        default: [:syntax, :style, :security],
        doc: "Types of validation to perform"
      ],
      quality_standards: [
        type: :atom,
        default: :standard,
        doc: "Quality standards to enforce (strict, standard, relaxed)"
      ],
      context: [
        type: :map,
        default: %{},
        doc: "Additional context for validation"
      ]
    ]

  require Logger

  @impl true
  def run(params, context) do
    Logger.info("Starting quality validation for #{params.language} code")

    validation_results = params.validation_types
    |> Enum.map(&perform_validation(&1, params, context))
    |> Enum.reduce(%{}, &merge_validation_results/2)

    overall_score = calculate_overall_score(validation_results)
    recommendations = generate_recommendations(validation_results, params)

    result = %{
      overall_score: overall_score,
      passed: overall_score >= get_passing_threshold(params.quality_standards),
      validations: validation_results,
      recommendations: recommendations,
      metadata: %{
        validated_at: DateTime.utc_now(),
        language: params.language,
        validation_types: params.validation_types,
        quality_standards: params.quality_standards,
        code_length: String.length(params.code)
      }
    }

    {:ok, result}
  end

  # Private functions

  defp perform_validation(:syntax, params, _context) do
    %{syntax: validate_syntax(params.code, params.language)}
  end

  defp perform_validation(:style, params, _context) do
    %{style: validate_style(params.code, params.language, params.quality_standards)}
  end

  defp perform_validation(:security, params, _context) do
    %{security: validate_security(params.code, params.language)}
  end

  defp perform_validation(:complexity, params, _context) do
    %{complexity: validate_complexity(params.code, params.language)}
  end

  defp perform_validation(:performance, params, _context) do
    %{performance: validate_performance(params.code, params.language)}
  end

  defp perform_validation(unknown_type, _params, _context) do
    Logger.warning("Unknown validation type: #{unknown_type}")
    %{}
  end

  defp validate_syntax(code, :elixir) do
    case Code.string_to_quoted(code) do
      {:ok, _ast} ->
        %{
          valid: true,
          score: 100,
          issues: [],
          message: "Syntax is valid"
        }
      
      {:error, {meta, message, token}} ->
        %{
          valid: false,
          score: 0,
          issues: [%{
            type: :syntax_error,
            line: Keyword.get(meta, :line, 1),
            column: Keyword.get(meta, :column, 1),
            message: "#{message} #{inspect(token)}"
          }],
          message: "Syntax errors found"
        }
    end
  end

  defp validate_syntax(_code, _language) do
    # For other languages, assume valid or integrate external validators
    %{
      valid: true,
      score: 100,
      issues: [],
      message: "Syntax validation not implemented for this language"
    }
  end

  defp validate_style(code, :elixir, quality_standards) do
    issues = []
    
    # Check for common style issues
    issues = check_line_length(code, issues, quality_standards)
    issues = check_naming_conventions(code, issues)
    issues = check_module_organization(code, issues)
    issues = check_function_complexity(code, issues)
    
    score = calculate_style_score(issues, quality_standards)
    
    %{
      valid: score >= 70,
      score: score,
      issues: issues,
      message: if(score >= 70, do: "Style is acceptable", else: "Style issues found")
    }
  end

  defp validate_style(_code, _language, _standards) do
    %{
      valid: true,
      score: 100,
      issues: [],
      message: "Style validation not implemented for this language"
    }
  end

  defp validate_security(code, :elixir) do
    issues = []
    
    # Check for common security issues
    issues = check_code_injection(code, issues)
    issues = check_unsafe_functions(code, issues)
    issues = check_input_validation(code, issues)
    
    score = calculate_security_score(issues)
    
    %{
      valid: score >= 80,
      score: score,
      issues: issues,
      message: if(score >= 80, do: "No major security issues", else: "Security issues found")
    }
  end

  defp validate_security(_code, _language) do
    %{
      valid: true,
      score: 100,
      issues: [],
      message: "Security validation not implemented for this language"
    }
  end

  defp validate_complexity(code, :elixir) do
    lines = String.split(code, "\n")
    function_count = count_functions(code)
    nesting_depth = calculate_max_nesting_depth(code)
    
    complexity_score = calculate_complexity_score(lines, function_count, nesting_depth)
    
    %{
      valid: complexity_score <= 10,
      score: max(0, 100 - complexity_score * 5),
      complexity_score: complexity_score,
      metrics: %{
        lines_of_code: length(lines),
        function_count: function_count,
        max_nesting_depth: nesting_depth
      },
      message: get_complexity_message(complexity_score)
    }
  end

  defp validate_complexity(_code, _language) do
    %{
      valid: true,
      score: 100,
      complexity_score: 1,
      metrics: %{},
      message: "Complexity validation not implemented for this language"
    }
  end

  defp validate_performance(code, :elixir) do
    issues = []
    
    # Check for performance anti-patterns
    issues = check_inefficient_patterns(code, issues)
    issues = check_memory_usage(code, issues)
    
    score = calculate_performance_score(issues)
    
    %{
      valid: score >= 70,
      score: score,
      issues: issues,
      message: if(score >= 70, do: "No major performance issues", else: "Performance issues found")
    }
  end

  defp validate_performance(_code, _language) do
    %{
      valid: true,
      score: 100,
      issues: [],
      message: "Performance validation not implemented for this language"
    }
  end

  # Style checking helpers

  defp check_line_length(code, issues, quality_standards) do
    max_length = case quality_standards do
      :strict -> 80
      :standard -> 98
      :relaxed -> 120
    end
    
    code
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce(issues, fn {line, line_num}, acc ->
      if String.length(line) > max_length do
        [%{
          type: :line_too_long,
          line: line_num,
          message: "Line exceeds #{max_length} characters",
          severity: :warning
        } | acc]
      else
        acc
      end
    end)
  end

  defp check_naming_conventions(code, issues) do
    # Check for snake_case function names
    snake_case_violations = Regex.scan(~r/def\s+([A-Z][a-zA-Z_]*)\s*\(/, code)
    
    snake_case_violations
    |> Enum.reduce(issues, fn [_full, function_name], acc ->
      [%{
        type: :naming_convention,
        message: "Function '#{function_name}' should use snake_case",
        severity: :warning
      } | acc]
    end)
  end

  defp check_module_organization(_code, issues) do
    # TODO: Implement module organization checks
    issues
  end

  defp check_function_complexity(_code, issues) do
    # TODO: Implement function complexity checks
    issues
  end

  # Security checking helpers

  defp check_code_injection(code, issues) do
    # Check for potential code injection patterns
    if String.contains?(code, ["Code.eval_string", "System.cmd"]) do
      [%{
        type: :code_injection_risk,
        message: "Potential code injection vulnerability detected",
        severity: :error
      } | issues]
    else
      issues
    end
  end

  defp check_unsafe_functions(code, issues) do
    unsafe_patterns = [
      "String.to_atom",
      ":erlang.binary_to_term",
      "File.write!"
    ]
    
    unsafe_patterns
    |> Enum.reduce(issues, fn pattern, acc ->
      if String.contains?(code, pattern) do
        [%{
          type: :unsafe_function,
          message: "Use of potentially unsafe function: #{pattern}",
          severity: :warning
        } | acc]
      else
        acc
      end
    end)
  end

  defp check_input_validation(_code, issues) do
    # TODO: Implement input validation checks
    issues
  end

  # Complexity calculation helpers

  defp count_functions(code) do
    Regex.scan(~r/def\s+\w+/, code) |> length()
  end

  defp calculate_max_nesting_depth(code) do
    lines = String.split(code, "\n")
    
    lines
    |> Enum.reduce({0, 0}, fn line, {current_depth, max_depth} ->
      # Count do/case/if/cond/try blocks
      opens = count_block_opens(line)
      closes = count_block_closes(line)
      
      new_depth = current_depth + opens - closes
      {new_depth, max(max_depth, new_depth)}
    end)
    |> elem(1)
  end

  defp count_block_opens(line) do
    opens = [" do", " do ", "case ", "if ", "cond ", "try "]
    Enum.count(opens, &String.contains?(line, &1))
  end

  defp count_block_closes(line) do
    String.trim(line) |> String.starts_with?("end") |> if(do: 1, else: 0)
  end

  defp calculate_complexity_score(lines, function_count, nesting_depth) do
    base_complexity = max(1, function_count)
    line_factor = length(lines) / 10
    nesting_factor = nesting_depth * 2
    
    round(base_complexity + line_factor + nesting_factor)
  end

  # Performance checking helpers

  defp check_inefficient_patterns(code, issues) do
    # Check for ++ on large lists
    if String.contains?(code, "++") do
      [%{
        type: :inefficient_list_concatenation,
        message: "Consider using [item | list] instead of list ++ [item]",
        severity: :info
      } | issues]
    else
      issues
    end
  end

  defp check_memory_usage(_code, issues) do
    # TODO: Implement memory usage checks
    issues
  end

  # Scoring helpers

  defp merge_validation_results(validation_result, acc) do
    Map.merge(acc, validation_result)
  end

  defp calculate_overall_score(validation_results) do
    scores = validation_results
    |> Map.values()
    |> Enum.map(&(&1.score))
    
    if Enum.empty?(scores) do
      0
    else
      Enum.sum(scores) / length(scores)
    end
  end

  defp calculate_style_score(issues, quality_standards) do
    base_score = 100
    penalty_per_issue = case quality_standards do
      :strict -> 10
      :standard -> 5
      :relaxed -> 3
    end
    
    max(0, base_score - length(issues) * penalty_per_issue)
  end

  defp calculate_security_score(issues) do
    base_score = 100
    
    security_penalty = issues
    |> Enum.reduce(0, fn issue, acc ->
      case issue.severity do
        :error -> acc + 30
        :warning -> acc + 15
        :info -> acc + 5
      end
    end)
    
    max(0, base_score - security_penalty)
  end

  defp calculate_performance_score(issues) do
    base_score = 100
    penalty = length(issues) * 10
    max(0, base_score - penalty)
  end

  defp get_passing_threshold(:strict), do: 90
  defp get_passing_threshold(:standard), do: 70
  defp get_passing_threshold(:relaxed), do: 50

  defp get_complexity_message(score) when score <= 5, do: "Low complexity"
  defp get_complexity_message(score) when score <= 10, do: "Moderate complexity"
  defp get_complexity_message(score) when score <= 20, do: "High complexity"
  defp get_complexity_message(_), do: "Very high complexity"

  defp generate_recommendations(validation_results, _params) do
    validation_results
    |> Map.values()
    |> Enum.flat_map(&extract_recommendations/1)
    |> Enum.uniq()
  end

  defp extract_recommendations(%{issues: issues}) do
    issues
    |> Enum.map(&issue_to_recommendation/1)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_recommendations(_), do: []

  defp issue_to_recommendation(%{type: :line_too_long}) do
    "Consider breaking long lines into multiple lines for better readability"
  end

  defp issue_to_recommendation(%{type: :naming_convention}) do
    "Use snake_case for function names and variables"
  end

  defp issue_to_recommendation(%{type: :code_injection_risk}) do
    "Avoid dynamic code evaluation; use safer alternatives"
  end

  defp issue_to_recommendation(%{type: :unsafe_function}) do
    "Review usage of potentially unsafe functions and add proper validation"
  end

  defp issue_to_recommendation(%{type: :inefficient_list_concatenation}) do
    "Use cons operator [item | list] for better performance with lists"
  end

  defp issue_to_recommendation(_), do: nil
end