defmodule RubberDuck.Jido.Actions.Analysis.StyleCheckAction do
  @moduledoc """
  Enhanced action for code style and formatting verification.
  
  This action provides:
  - Multi-file style checking
  - Configurable style rules
  - Auto-fixable violation detection
  - Violation summarization and reporting
  - Style guide compliance checking
  - Formatting consistency analysis
  """
  
  use Jido.Action,
    name: "style_check_v2",
    description: "Performs comprehensive code style and formatting verification",
    schema: [
      file_paths: [
        type: {:list, :string},
        required: true,
        doc: "List of file paths to check for style violations"
      ],
      style_rules: [
        type: {:in, [:default, :strict, :relaxed, :custom]},
        default: :default,
        doc: "Style rule set to apply"
      ],
      custom_rules: [
        type: :map,
        default: %{},
        doc: "Custom style rules configuration"
      ],
      detect_auto_fixable: [
        type: :boolean,
        default: true,
        doc: "Identify which violations can be auto-fixed"
      ],
      check_formatting: [
        type: :boolean,
        default: true,
        doc: "Check code formatting consistency"
      ],
      max_line_length: [
        type: :integer,
        default: 120,
        doc: "Maximum allowed line length"
      ]
    ]

  alias RubberDuck.Analysis.Style
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    try do
      # Get style rules configuration
      style_config = get_style_configuration(params)
      
      # Check each file for style violations
      all_violations = check_files_for_violations(params.file_paths, style_config, agent)
      
      # Categorize violations
      categorized = categorize_violations(all_violations)
      
      # Identify auto-fixable violations if requested
      {auto_fixable, manual_fix} = if params.detect_auto_fixable do
        partition_auto_fixable(all_violations)
      else
        {[], all_violations}
      end
      
      # Generate summary statistics
      summary = generate_violation_summary(categorized)
      
      # Generate fix suggestions
      fix_suggestions = generate_fix_suggestions(categorized)
      
      result = %{
        file_paths: params.file_paths,
        violations: all_violations,
        auto_fixable: auto_fixable,
        manual_fix_required: manual_fix,
        summary: summary,
        fix_suggestions: fix_suggestions,
        style_score: calculate_style_score(all_violations, length(params.file_paths)),
        categories: categorized,
        confidence: 0.95,
        timestamp: DateTime.utc_now()
      }
      
      Logger.info("Style check completed",
        files_checked: length(params.file_paths),
        violations_found: length(all_violations),
        auto_fixable: length(auto_fixable)
      )
      
      {:ok, result}
      
    rescue
      error ->
        Logger.error("Style check failed: #{inspect(error)}")
        {:error, {:style_check_failed, error}}
    end
  end
  
  # Private helper functions
  
  defp get_style_configuration(params) do
    base_config = case params.style_rules do
      :default -> default_style_rules()
      :strict -> strict_style_rules()
      :relaxed -> relaxed_style_rules()
      :custom -> %{}
    end
    
    Map.merge(base_config, params.custom_rules)
    |> Map.put(:max_line_length, params.max_line_length)
    |> Map.put(:check_formatting, params.check_formatting)
  end
  
  defp default_style_rules do
    %{
      line_length: true,
      trailing_whitespace: true,
      indentation: :spaces_2,
      naming_convention: :snake_case,
      module_doc: :required,
      function_doc: :public_only,
      parentheses_in_zero_arity: false,
      pipe_chain_start: true,
      single_quote_strings: false,
      max_function_length: 50,
      max_module_length: 500
    }
  end
  
  defp strict_style_rules do
    %{
      line_length: true,
      trailing_whitespace: true,
      indentation: :spaces_2,
      naming_convention: :snake_case,
      module_doc: :required,
      function_doc: :required,
      parentheses_in_zero_arity: true,
      pipe_chain_start: true,
      single_quote_strings: true,
      max_function_length: 30,
      max_module_length: 300,
      max_complexity: 10,
      enforce_pattern_matching: true
    }
  end
  
  defp relaxed_style_rules do
    %{
      line_length: false,
      trailing_whitespace: true,
      indentation: :any,
      naming_convention: :snake_case,
      module_doc: :optional,
      function_doc: :optional,
      parentheses_in_zero_arity: false,
      pipe_chain_start: false,
      single_quote_strings: false,
      max_function_length: 100,
      max_module_length: 1000
    }
  end
  
  defp check_files_for_violations(file_paths, style_config, agent) do
    engine_config = get_engine_config(agent, :style)
    
    file_paths
    |> Enum.flat_map(fn file_path ->
      check_single_file(file_path, style_config, engine_config)
    end)
  end
  
  defp check_single_file(file_path, style_config, engine_config) do
    case Style.analyze(file_path, Map.merge(engine_config, %{rules: style_config})) do
      {:ok, result} ->
        result.violations
        |> Enum.map(fn violation ->
          %{
            file_path: file_path,
            rule: violation.rule || :unknown,
            line: violation.line || 0,
            column: violation.column || 0,
            message: violation.message || "Style violation detected",
            severity: violation.severity || :warning,
            auto_fixable: violation.auto_fixable || false,
            category: categorize_rule(violation.rule)
          }
        end)
      
      {:error, reason} ->
        Logger.warning("Failed to check style for #{file_path}: #{inspect(reason)}")
        []
    end
  end
  
  defp categorize_rule(rule) do
    cond do
      rule in [:line_length, :trailing_whitespace, :indentation] -> :formatting
      rule in [:naming_convention, :module_name, :function_name] -> :naming
      rule in [:module_doc, :function_doc, :type_spec] -> :documentation
      rule in [:parentheses_in_zero_arity, :pipe_chain_start] -> :syntax
      rule in [:max_function_length, :max_module_length, :max_complexity] -> :complexity
      true -> :other
    end
  end
  
  defp categorize_violations(violations) do
    violations
    |> Enum.group_by(& &1.category)
    |> Map.new(fn {category, cat_violations} ->
      {category, %{
        violations: cat_violations,
        count: length(cat_violations),
        severity_breakdown: severity_breakdown(cat_violations)
      }}
    end)
  end
  
  defp severity_breakdown(violations) do
    violations
    |> Enum.group_by(& &1.severity)
    |> Map.new(fn {severity, sev_violations} -> {severity, length(sev_violations)} end)
  end
  
  defp partition_auto_fixable(violations) do
    Enum.split_with(violations, & &1.auto_fixable)
  end
  
  defp generate_violation_summary(categorized) do
    total_violations = categorized
      |> Map.values()
      |> Enum.reduce(0, fn cat_data, acc -> acc + cat_data.count end)
    
    %{
      total_violations: total_violations,
      by_category: Map.new(categorized, fn {cat, data} -> {cat, data.count} end),
      most_common_category: find_most_common_category(categorized),
      severity_distribution: aggregate_severities(categorized),
      top_violations: find_top_violations(categorized)
    }
  end
  
  defp find_most_common_category(categorized) do
    case Enum.max_by(categorized, fn {_, data} -> data.count end, fn -> nil end) do
      nil -> nil
      {category, _} -> category
    end
  end
  
  defp aggregate_severities(categorized) do
    categorized
    |> Map.values()
    |> Enum.reduce(%{}, fn cat_data, acc ->
      Enum.reduce(cat_data.severity_breakdown, acc, fn {severity, count}, acc2 ->
        Map.update(acc2, severity, count, &(&1 + count))
      end)
    end)
  end
  
  defp find_top_violations(categorized) do
    all_violations = categorized
      |> Map.values()
      |> Enum.flat_map(& &1.violations)
    
    all_violations
    |> Enum.group_by(& &1.rule)
    |> Enum.map(fn {rule, rule_violations} -> {rule, length(rule_violations)} end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(5)
    |> Enum.map(fn {rule, count} -> %{rule: rule, count: count} end)
  end
  
  defp generate_fix_suggestions(categorized) do
    suggestions = []
    
    # Formatting suggestions
    suggestions = case categorized[:formatting] do
      nil -> suggestions
      %{count: count} when count > 10 ->
        ["Run `mix format` to automatically fix #{count} formatting violations" | suggestions]
      %{count: count} when count > 0 ->
        ["Consider running `mix format` to fix formatting issues" | suggestions]
      _ -> suggestions
    end
    
    # Documentation suggestions
    suggestions = case categorized[:documentation] do
      nil -> suggestions
      %{count: count} when count > 0 ->
        ["Add missing documentation to improve code maintainability (#{count} violations)" | suggestions]
      _ -> suggestions
    end
    
    # Naming suggestions
    suggestions = case categorized[:naming] do
      nil -> suggestions
      %{count: count} when count > 0 ->
        ["Review naming conventions - #{count} naming violations found" | suggestions]
      _ -> suggestions
    end
    
    # Complexity suggestions
    suggestions = case categorized[:complexity] do
      nil -> suggestions
      %{count: count} when count > 0 ->
        ["Refactor complex code - #{count} complexity violations detected" | suggestions]
      _ -> suggestions
    end
    
    if Enum.empty?(suggestions) do
      ["Code style is excellent! No significant issues found."]
    else
      suggestions
    end
  end
  
  defp calculate_style_score(violations, files_checked) do
    # Calculate a style score from 0-100
    # Higher score = better style compliance
    
    if files_checked == 0 do
      100.0
    else
      base_score = 100.0
    
    # Deduct points based on violations and their severity
    deductions = Enum.reduce(violations, 0, fn violation, acc ->
      case violation.severity do
        :error -> acc + 5
        :warning -> acc + 2
        :info -> acc + 1
        _ -> acc + 1
      end
    end)
    
      # Normalize by files checked
      normalized_deductions = deductions / files_checked * 5
      
      score = max(0, base_score - normalized_deductions)
      Float.round(score, 2)
    end
  end
  
  defp get_engine_config(agent, engine_type) do
    get_in(agent.state, [:engines, engine_type, :config]) || %{}
  end
end