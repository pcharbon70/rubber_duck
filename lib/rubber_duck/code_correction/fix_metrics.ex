defmodule RubberDuck.CodeCorrection.FixMetrics do
  @moduledoc """
  Fix metrics module for tracking code correction performance and quality.
  
  Collects and analyzes metrics about code fixes including success rates,
  quality improvements, and performance impact.
  """

  require Logger

  @doc """
  Calculates comprehensive metrics for a code fix.
  """
  def calculate_fix_metrics(fix_result, error_data, validation_result) do
    %{
      success_metrics: calculate_success_metrics(fix_result, validation_result),
      quality_metrics: calculate_quality_metrics(fix_result, error_data),
      performance_metrics: calculate_performance_metrics(fix_result),
      complexity_metrics: calculate_complexity_metrics(fix_result, error_data),
      impact_metrics: calculate_impact_metrics(fix_result, error_data)
    }
  end

  @doc """
  Tracks metrics for a completed correction.
  """
  def track_correction_metrics(correction_info, metrics_store) do
    metrics = extract_correction_metrics(correction_info)
    
    updated_store = update_metrics_store(metrics_store, metrics)
    
    # Calculate derived metrics
    updated_store = calculate_derived_metrics(updated_store)
    
    updated_store
  end

  @doc """
  Generates a metrics report for a time period.
  """
  def generate_metrics_report(metrics_store, time_range) do
    filtered_data = filter_by_time_range(metrics_store, time_range)
    
    %{
      summary: generate_summary_metrics(filtered_data),
      trends: analyze_trends(filtered_data),
      patterns: identify_patterns(filtered_data),
      recommendations: generate_recommendations(filtered_data)
    }
  end

  ## Private Functions - Metric Calculations

  defp calculate_success_metrics(fix_result, validation_result) do
    %{
      fix_applied: true,
      validation_passed: validation_result.valid,
      confidence_score: fix_result[:confidence] || 0.8,
      validation_confidence: validation_result.confidence,
      overall_success: validation_result.valid and (fix_result[:confidence] || 0.8) > 0.7
    }
  end

  defp calculate_quality_metrics(fix_result, error_data) do
    original_code = error_data["code"]
    fixed_code = fix_result.fixed_code || fix_result[:fixed_code]
    
    %{
      readability_change: calculate_readability_change(original_code, fixed_code),
      maintainability_change: calculate_maintainability_change(original_code, fixed_code),
      consistency_improvement: calculate_consistency_improvement(original_code, fixed_code),
      documentation_change: calculate_documentation_change(original_code, fixed_code),
      test_coverage_impact: estimate_test_coverage_impact(fix_result)
    }
  end

  defp calculate_performance_metrics(fix_result) do
    %{
      fix_execution_time: fix_result[:duration_ms] || 0,
      validation_time: fix_result[:validation_time] || 0,
      total_processing_time: (fix_result[:duration_ms] || 0) + (fix_result[:validation_time] || 0),
      resource_usage: estimate_resource_usage(fix_result)
    }
  end

  defp calculate_complexity_metrics(fix_result, error_data) do
    original_code = error_data["code"]
    fixed_code = fix_result.fixed_code || fix_result[:fixed_code]
    
    %{
      cyclomatic_complexity_change: calculate_complexity_change(original_code, fixed_code),
      cognitive_complexity_change: calculate_cognitive_complexity_change(original_code, fixed_code),
      nesting_depth_change: calculate_nesting_depth_change(original_code, fixed_code),
      function_length_change: calculate_function_length_change(original_code, fixed_code)
    }
  end

  defp calculate_impact_metrics(fix_result, error_data) do
    %{
      lines_changed: count_lines_changed(fix_result),
      functions_affected: count_functions_affected(fix_result),
      modules_impacted: estimate_module_impact(fix_result),
      breaking_change_risk: assess_breaking_change_risk(fix_result, error_data),
      user_impact: estimate_user_impact(fix_result)
    }
  end

  ## Private Functions - Quality Calculations

  defp calculate_readability_change(original_code, fixed_code) do
    original_score = calculate_readability_score(original_code)
    fixed_score = calculate_readability_score(fixed_code)
    
    %{
      original: original_score,
      fixed: fixed_score,
      change: fixed_score - original_score,
      percentage_change: if(original_score > 0, do: (fixed_score - original_score) / original_score * 100, else: 0)
    }
  end

  defp calculate_readability_score(code) do
    lines = String.split(code, "\n")
    
    # Factors that improve readability (higher is better)
    avg_line_length = calculate_average_line_length(lines)
    line_length_score = max(0, 1 - (avg_line_length - 40) / 80)  # Optimal around 40 chars
    
    # Function and variable naming
    naming_score = calculate_naming_quality(code)
    
    # Comments and documentation
    comment_ratio = calculate_comment_ratio(lines)
    comment_score = min(1, comment_ratio * 4)  # 25% comments is ideal
    
    # Overall readability score (0-1)
    (line_length_score + naming_score + comment_score) / 3
  end

  defp calculate_maintainability_change(original_code, fixed_code) do
    original_score = calculate_maintainability_score(original_code)
    fixed_score = calculate_maintainability_score(fixed_code)
    
    %{
      original: original_score,
      fixed: fixed_score,
      change: fixed_score - original_score,
      improved: fixed_score > original_score
    }
  end

  defp calculate_maintainability_score(code) do
    # Simplified maintainability index
    _lines = String.split(code, "\n")
    
    # Factors
    modularity = calculate_modularity_score(code)
    coupling = calculate_coupling_score(code)
    cohesion = calculate_cohesion_score(code)
    
    # Maintainability score (0-1)
    (modularity + (1 - coupling) + cohesion) / 3
  end

  defp calculate_consistency_improvement(original_code, fixed_code) do
    # Check various consistency aspects
    aspects = [
      naming_consistency(original_code, fixed_code),
      formatting_consistency(original_code, fixed_code),
      pattern_consistency(original_code, fixed_code)
    ]
    
    improvements = Enum.count(aspects, & &1.improved)
    
    %{
      aspects_improved: improvements,
      total_aspects: length(aspects),
      improvement_ratio: improvements / length(aspects),
      details: aspects
    }
  end

  defp calculate_documentation_change(original_code, fixed_code) do
    original_docs = count_documentation(original_code)
    fixed_docs = count_documentation(fixed_code)
    
    %{
      original_doc_lines: original_docs.total_lines,
      fixed_doc_lines: fixed_docs.total_lines,
      moduledocs_added: fixed_docs.moduledocs - original_docs.moduledocs,
      docstrings_added: fixed_docs.docstrings - original_docs.docstrings,
      comments_added: fixed_docs.comments - original_docs.comments
    }
  end

  ## Private Functions - Complexity Calculations

  defp calculate_complexity_change(original_code, fixed_code) do
    original_complexity = calculate_cyclomatic_complexity(original_code)
    fixed_complexity = calculate_cyclomatic_complexity(fixed_code)
    
    %{
      original: original_complexity,
      fixed: fixed_complexity,
      change: fixed_complexity - original_complexity,
      improved: fixed_complexity < original_complexity
    }
  end

  defp calculate_cyclomatic_complexity(code) do
    # Simplified cyclomatic complexity calculation
    # Count decision points
    decision_keywords = ~w(if unless case cond and or && ||)
    
    decision_keywords
    |> Enum.map(fn keyword ->
      Regex.scan(~r/\b#{keyword}\b/, code) |> length()
    end)
    |> Enum.sum()
    |> Kernel.+(1)  # Base complexity
  end

  defp calculate_cognitive_complexity_change(original_code, fixed_code) do
    # Cognitive complexity considers nesting and code structure
    original = calculate_cognitive_complexity(original_code)
    fixed = calculate_cognitive_complexity(fixed_code)
    
    %{
      original: original,
      fixed: fixed,
      change: fixed - original,
      improved: fixed < original
    }
  end

  defp calculate_cognitive_complexity(code) do
    lines = String.split(code, "\n")
    
    {complexity, _} = Enum.reduce(lines, {0, 0}, fn line, {complexity, nesting} ->
      # Update nesting level
      nesting = cond do
        line =~ ~r/\b(if|unless|case|cond|for|with)\b/ -> nesting + 1
        line =~ ~r/\bend\b/ -> max(0, nesting - 1)
        true -> nesting
      end
      
      # Add complexity based on nesting
      line_complexity = if line =~ ~r/\b(if|unless|case|cond)\b/ do
        1 + nesting
      else
        0
      end
      
      {complexity + line_complexity, nesting}
    end)
    
    complexity
  end

  ## Private Functions - Helper Functions

  defp calculate_average_line_length(lines) do
    non_empty_lines = Enum.filter(lines, &(String.trim(&1) != ""))
    
    if length(non_empty_lines) > 0 do
      total_length = non_empty_lines
      |> Enum.map(&String.length/1)
      |> Enum.sum()
      
      total_length / length(non_empty_lines)
    else
      0
    end
  end

  defp calculate_naming_quality(code) do
    # Extract identifiers
    identifiers = extract_identifiers(code)
    
    if length(identifiers) > 0 do
      good_names = Enum.count(identifiers, &good_identifier_name?/1)
      good_names / length(identifiers)
    else
      0.5  # Default
    end
  end

  defp extract_identifiers(code) do
    # Extract function and variable names
    ~r/\b(def|defp|defmodule)\s+([a-zA-Z_]\w*)/
    |> Regex.scan(code)
    |> Enum.map(fn [_, _, name] -> name end)
  end

  defp good_identifier_name?(name) do
    # Check if name follows good practices
    String.length(name) >= 3 and
    name =~ ~r/^[a-z]/ and
    name =~ ~r/^[a-z_]+$/ and
    not String.ends_with?(name, "_")
  end

  defp calculate_comment_ratio(lines) do
    comment_lines = Enum.count(lines, &(String.trim(&1) =~ ~r/^#/))
    total_lines = length(lines)
    
    if total_lines > 0 do
      comment_lines / total_lines
    else
      0
    end
  end

  defp calculate_modularity_score(code) do
    # Count modules and functions
    _modules = Regex.scan(~r/defmodule/, code) |> length()
    functions = Regex.scan(~r/def(?:p?)\s/, code) |> length()
    
    # Higher modularity = more, smaller functions
    if functions > 0 do
      avg_lines_per_function = String.split(code, "\n") |> length() |> Kernel./(functions)
      
      # Ideal is around 10 lines per function
      ideal_ratio = 10
      deviation = abs(avg_lines_per_function - ideal_ratio) / ideal_ratio
      
      max(0, 1 - deviation)
    else
      0.5
    end
  end

  defp calculate_coupling_score(_code) do
    # Simplified - would analyze module dependencies
    0.3  # Lower is better
  end

  defp calculate_cohesion_score(_code) do
    # Simplified - would analyze function relationships
    0.7  # Higher is better
  end

  defp naming_consistency(original_code, fixed_code) do
    # Check naming convention consistency
    original_style = detect_naming_style(original_code)
    fixed_style = detect_naming_style(fixed_code)
    
    %{
      improved: fixed_style.consistency > original_style.consistency,
      original_consistency: original_style.consistency,
      fixed_consistency: fixed_style.consistency
    }
  end

  defp detect_naming_style(code) do
    identifiers = extract_identifiers(code)
    
    if length(identifiers) > 0 do
      snake_case = Enum.count(identifiers, &(&1 =~ ~r/^[a-z]+(_[a-z]+)*$/))
      consistency = snake_case / length(identifiers)
      
      %{style: :snake_case, consistency: consistency}
    else
      %{style: :unknown, consistency: 0}
    end
  end

  defp formatting_consistency(_original_code, _fixed_code) do
    # Simplified - would check indentation, spacing, etc.
    %{improved: true, aspect: :formatting}
  end

  defp pattern_consistency(_original_code, _fixed_code) do
    # Simplified - would check code patterns
    %{improved: true, aspect: :patterns}
  end

  defp count_documentation(code) do
    lines = String.split(code, "\n")
    
    %{
      total_lines: Enum.count(lines, &(&1 =~ ~r/@(module)?doc/)),
      moduledocs: Regex.scan(~r/@moduledoc/, code) |> length(),
      docstrings: Regex.scan(~r/@doc/, code) |> length(),
      comments: Enum.count(lines, &(&1 =~ ~r/^\s*#/))
    }
  end

  defp calculate_nesting_depth_change(original_code, fixed_code) do
    original_depth = calculate_max_nesting_depth(original_code)
    fixed_depth = calculate_max_nesting_depth(fixed_code)
    
    %{
      original: original_depth,
      fixed: fixed_depth,
      change: fixed_depth - original_depth,
      improved: fixed_depth < original_depth
    }
  end

  defp calculate_max_nesting_depth(code) do
    lines = String.split(code, "\n")
    
    {max_depth, _, _} = Enum.reduce(lines, {0, 0, []}, fn line, {max_depth, current_depth, stack} ->
      cond do
        line =~ ~r/\b(def|defp|if|unless|case|cond|for|with)\b/ ->
          new_depth = current_depth + 1
          {max(max_depth, new_depth), new_depth, [:block | stack]}
          
        line =~ ~r/\bend\b/ and stack != [] ->
          [_ | rest] = stack
          {max_depth, max(0, current_depth - 1), rest}
          
        true ->
          {max_depth, current_depth, stack}
      end
    end)
    
    max_depth
  end

  defp calculate_function_length_change(original_code, fixed_code) do
    original_lengths = extract_function_lengths(original_code)
    fixed_lengths = extract_function_lengths(fixed_code)
    
    %{
      original_avg: calculate_average(original_lengths),
      fixed_avg: calculate_average(fixed_lengths),
      original_max: Enum.max(original_lengths, fn -> 0 end),
      fixed_max: Enum.max(fixed_lengths, fn -> 0 end)
    }
  end

  defp extract_function_lengths(code) do
    # Simplified - would parse functions properly
    code
    |> String.split(~r/\bdef(?:p?)\s/)
    |> Enum.drop(1)
    |> Enum.map(fn func ->
      func
      |> String.split(~r/\bend\b/)
      |> List.first()
      |> String.split("\n")
      |> length()
    end)
  end

  defp calculate_average(list) when length(list) > 0 do
    Enum.sum(list) / length(list)
  end
  defp calculate_average(_), do: 0

  defp estimate_test_coverage_impact(_fix_result) do
    # Simplified estimation
    %{
      likely_impact: :positive,
      estimated_change: 0.05,
      confidence: 0.6
    }
  end

  defp estimate_resource_usage(_fix_result) do
    %{
      cpu_usage: :low,
      memory_usage: :low,
      io_usage: :minimal
    }
  end

  defp count_lines_changed(fix_result) do
    changes = fix_result[:changes] || []
    length(changes)
  end

  defp count_functions_affected(fix_result) do
    # Count unique functions in changes
    fix_result[:changes]
    |> Enum.map(& &1[:function])
    |> Enum.uniq()
    |> Enum.reject(&is_nil/1)
    |> length()
  end

  defp estimate_module_impact(_fix_result) do
    # Simplified estimation
    1
  end

  defp assess_breaking_change_risk(fix_result, _error_data) do
    risk_factors = []
    
    # Check for API changes
    risk_factors = if fix_result[:type] == :refactoring do
      [:refactoring | risk_factors]
    else
      risk_factors
    end
    
    # Check for function signature changes
    changes = fix_result[:changes] || []
    risk_factors = if Enum.any?(changes, &(&1[:type] == :function_signature)) do
      [:signature_change | risk_factors]
    else
      risk_factors
    end
    
    %{
      risk_level: calculate_risk_level(risk_factors),
      factors: risk_factors
    }
  end

  defp calculate_risk_level(factors) do
    case length(factors) do
      0 -> :low
      1 -> :medium
      _ -> :high
    end
  end

  defp estimate_user_impact(_fix_result) do
    %{
      user_visible: false,
      requires_migration: false,
      documentation_needed: true
    }
  end

  ## Private Functions - Metrics Store

  defp extract_correction_metrics(correction_info) do
    %{
      correction_id: correction_info.correction_id,
      timestamp: correction_info.completed_at || correction_info.started_at,
      success: correction_info.status == :completed,
      duration_ms: correction_info[:duration_ms] || 0,
      fix_type: correction_info.fix_result[:type],
      confidence: correction_info.fix_result[:confidence] || 0,
      validation_passed: correction_info.validation_result[:valid] || false
    }
  end

  defp update_metrics_store(store, metrics) do
    Map.update(store, :corrections, [metrics], &[metrics | &1])
  end

  defp calculate_derived_metrics(store) do
    corrections = Map.get(store, :corrections, [])
    
    if length(corrections) > 0 do
      success_count = Enum.count(corrections, & &1.success)
      total_count = length(corrections)
      
      Map.merge(store, %{
        total_corrections: total_count,
        successful_corrections: success_count,
        success_rate: success_count / total_count,
        avg_duration: calculate_average(Enum.map(corrections, & &1.duration_ms)),
        avg_confidence: calculate_average(Enum.map(corrections, & &1.confidence))
      })
    else
      store
    end
  end

  defp filter_by_time_range(store, :all), do: store
  
  defp filter_by_time_range(store, time_range) do
    cutoff = calculate_cutoff_time(time_range)
    
    filtered_corrections = store[:corrections]
    |> Enum.filter(fn correction ->
      DateTime.compare(correction.timestamp, cutoff) == :gt
    end)
    
    Map.put(store, :corrections, filtered_corrections)
    |> calculate_derived_metrics()
  end

  defp calculate_cutoff_time(time_range) do
    case time_range do
      :hour -> DateTime.add(DateTime.utc_now(), -3600, :second)
      :day -> DateTime.add(DateTime.utc_now(), -86400, :second)
      :week -> DateTime.add(DateTime.utc_now(), -604800, :second)
      :month -> DateTime.add(DateTime.utc_now(), -2592000, :second)
      _ -> DateTime.add(DateTime.utc_now(), -86400, :second)
    end
  end

  defp generate_summary_metrics(data) do
    %{
      total_corrections: data[:total_corrections] || 0,
      success_rate: data[:success_rate] || 0,
      avg_duration_ms: data[:avg_duration] || 0,
      avg_confidence: data[:avg_confidence] || 0,
      validation_pass_rate: calculate_validation_pass_rate(data)
    }
  end

  defp calculate_validation_pass_rate(data) do
    corrections = data[:corrections] || []
    
    if length(corrections) > 0 do
      passed = Enum.count(corrections, & &1.validation_passed)
      passed / length(corrections)
    else
      0
    end
  end

  defp analyze_trends(data) do
    corrections = data[:corrections] || []
    
    if length(corrections) >= 10 do
      # Group by time periods
      hourly_groups = group_by_hour(corrections)
      
      %{
        success_rate_trend: calculate_trend(hourly_groups, :success_rate),
        duration_trend: calculate_trend(hourly_groups, :avg_duration),
        volume_trend: calculate_trend(hourly_groups, :count)
      }
    else
      %{insufficient_data: true}
    end
  end

  defp group_by_hour(corrections) do
    corrections
    |> Enum.group_by(fn correction ->
      correction.timestamp
      |> DateTime.truncate(:second)
      |> DateTime.to_string()
      |> String.slice(0, 13)  # YYYY-MM-DD HH
    end)
    |> Enum.map(fn {hour, group} ->
      success_count = Enum.count(group, & &1.success)
      
      %{
        hour: hour,
        count: length(group),
        success_rate: if(length(group) > 0, do: success_count / length(group), else: 0),
        avg_duration: calculate_average(Enum.map(group, & &1.duration_ms))
      }
    end)
    |> Enum.sort_by(& &1.hour)
  end

  defp calculate_trend(data_points, metric) do
    if length(data_points) < 2 do
      :insufficient_data
    else
      values = Enum.map(data_points, &Map.get(&1, metric))
      first_half = Enum.take(values, div(length(values), 2))
      second_half = Enum.drop(values, div(length(values), 2))
      
      first_avg = calculate_average(first_half)
      second_avg = calculate_average(second_half)
      
      cond do
        second_avg > first_avg * 1.1 -> :increasing
        second_avg < first_avg * 0.9 -> :decreasing
        true -> :stable
      end
    end
  end

  defp identify_patterns(data) do
    corrections = data[:corrections] || []
    
    %{
      common_fix_types: identify_common_fix_types(corrections),
      failure_patterns: identify_failure_patterns(corrections),
      performance_patterns: identify_performance_patterns(corrections)
    }
  end

  defp identify_common_fix_types(corrections) do
    corrections
    |> Enum.group_by(& &1.fix_type)
    |> Enum.map(fn {type, group} -> {type, length(group)} end)
    |> Enum.sort_by(fn {_type, count} -> count end, :desc)
    |> Enum.take(5)
  end

  defp identify_failure_patterns(corrections) do
    failed = Enum.filter(corrections, &(not &1.success))
    
    if length(failed) > 0 do
      %{
        total_failures: length(failed),
        failure_rate: length(failed) / length(corrections),
        common_failure_types: failed
        |> Enum.group_by(& &1.fix_type)
        |> Enum.map(fn {type, group} -> {type, length(group)} end)
        |> Enum.sort_by(fn {_type, count} -> count end, :desc)
      }
    else
      %{no_failures: true}
    end
  end

  defp identify_performance_patterns(corrections) do
    avg_duration = calculate_average(Enum.map(corrections, & &1.duration_ms))
    
    slow_corrections = Enum.filter(corrections, &(&1.duration_ms > avg_duration * 2))
    
    %{
      avg_duration: avg_duration,
      slow_correction_count: length(slow_corrections),
      slow_correction_types: slow_corrections
      |> Enum.group_by(& &1.fix_type)
      |> Enum.map(fn {type, group} -> {type, length(group)} end)
    }
  end

  defp generate_recommendations(data) do
    recommendations = []
    
    # Success rate recommendations
    success_rate = data[:success_rate] || 0
    recommendations = if success_rate < 0.8 do
      ["Investigate failure patterns - success rate is #{round(success_rate * 100)}%" | recommendations]
    else
      recommendations
    end
    
    # Performance recommendations
    avg_duration = data[:avg_duration] || 0
    recommendations = if avg_duration > 5000 do
      ["Consider optimizing fix performance - average duration is #{avg_duration}ms" | recommendations]
    else
      recommendations
    end
    
    # Pattern-based recommendations
    patterns = identify_patterns(data)
    recommendations = if patterns.failure_patterns[:failure_rate] > 0.2 do
      ["High failure rate detected for certain fix types" | recommendations]
    else
      recommendations
    end
    
    if Enum.empty?(recommendations) do
      ["System performing well - no immediate actions needed"]
    else
      recommendations
    end
  end
end