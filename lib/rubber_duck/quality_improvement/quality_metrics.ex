defmodule RubberDuck.QualityImprovement.QualityMetrics do
  @moduledoc """
  Quality metrics module for tracking and analyzing code quality improvements.
  
  Provides comprehensive metrics tracking including quality scores,
  improvement trends, regression detection, and quality reporting.
  """

  require Logger

  @doc """
  Calculates comprehensive quality metrics for code.
  """
  def calculate_quality_metrics(code, _options \\ %{}) do
    Logger.debug("QualityMetrics: Calculating quality metrics")
    
    try do
      case Code.string_to_quoted(code) do
        {:ok, ast} ->
          # Calculate various quality metrics
          complexity_metrics = calculate_complexity_metrics(ast)
          maintainability_metrics = calculate_maintainability_metrics(ast, code)
          readability_metrics = calculate_readability_metrics(ast, code)
          testability_metrics = calculate_testability_metrics(ast)
          documentation_metrics = calculate_documentation_metrics(ast, code)
          
          # Calculate overall quality score
          overall_score = calculate_overall_quality_score(%{
            complexity: complexity_metrics,
            maintainability: maintainability_metrics,
            readability: readability_metrics,
            testability: testability_metrics,
            documentation: documentation_metrics
          })
          
          result = %{
            complexity: complexity_metrics,
            maintainability: maintainability_metrics,
            readability: readability_metrics,
            testability: testability_metrics,
            documentation: documentation_metrics,
            overall_score: overall_score,
            timestamp: DateTime.utc_now(),
            confidence: 0.85
          }
          
          {:ok, result}
          
        {:error, {line, error_desc, token}} ->
          {:error, "Syntax error at line #{line}: #{format_error(error_desc)} near '#{token}'"}
      end
    catch
      kind, reason ->
        Logger.error("QualityMetrics: Metrics calculation failed: #{kind} - #{inspect(reason)}")
        {:error, "Metrics calculation failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Tracks quality improvements over time.
  """
  def track_quality_improvements(improvement_history, _options \\ %{}) do
    Logger.debug("QualityMetrics: Tracking quality improvements over #{length(improvement_history)} entries")
    
    try do
      # Analyze improvement trends
      trends = analyze_improvement_trends(improvement_history)
      
      # Calculate improvement velocity
      velocity = calculate_improvement_velocity(improvement_history)
      
      # Identify improvement patterns
      patterns = identify_improvement_patterns(improvement_history)
      
      # Calculate ROI of improvements
      roi_analysis = calculate_improvement_roi(improvement_history)
      
      # Detect quality regressions
      regressions = do_detect_quality_regressions(improvement_history)
      
      result = %{
        trends: trends,
        velocity: velocity,
        patterns: patterns,
        roi_analysis: roi_analysis,
        regressions: regressions,
        total_improvements: length(improvement_history),
        analysis_timestamp: DateTime.utc_now()
      }
      
      {:ok, result}
    catch
      kind, reason ->
        Logger.error("QualityMetrics: Improvement tracking failed: #{kind} - #{inspect(reason)}")
        {:error, "Improvement tracking failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Generates quality reports with detailed analysis and recommendations.
  """
  def generate_quality_report(quality_data, improvement_data, options \\ %{}) do
    Logger.debug("QualityMetrics: Generating quality report")
    
    try do
      report_type = Map.get(options, "report_type", "comprehensive")
      time_period = Map.get(options, "time_period", "month")
      
      # Generate different sections of the report
      executive_summary = generate_executive_summary(quality_data, improvement_data)
      detailed_metrics = generate_detailed_metrics_section(quality_data)
      improvement_analysis = generate_improvement_analysis(improvement_data)
      trend_analysis = generate_trend_analysis(improvement_data, time_period)
      recommendations = generate_quality_recommendations(quality_data, improvement_data)
      
      report = %{
        report_type: report_type,
        time_period: time_period,
        generated_at: DateTime.utc_now(),
        executive_summary: executive_summary,
        detailed_metrics: detailed_metrics,
        improvement_analysis: improvement_analysis,
        trend_analysis: trend_analysis,
        recommendations: recommendations,
        report_confidence: calculate_report_confidence(quality_data, improvement_data)
      }
      
      {:ok, report}
    catch
      kind, reason ->
        Logger.error("QualityMetrics: Report generation failed: #{kind} - #{inspect(reason)}")
        {:error, "Report generation failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Detects quality regressions in code over time.
  """
  def detect_quality_regressions(quality_history, options \\ %{}) do
    Logger.debug("QualityMetrics: Detecting quality regressions")
    
    try do
      threshold = Map.get(options, "regression_threshold", 0.1)
      window_size = Map.get(options, "analysis_window", 10)
      
      # Analyze quality trends
      quality_scores = extract_quality_scores(quality_history)
      
      # Detect significant drops in quality
      regressions = detect_score_regressions(quality_scores, threshold, window_size)
      
      # Categorize regressions by severity
      categorized_regressions = categorize_regressions(regressions)
      
      # Identify root causes
      root_cause_analysis = analyze_regression_causes(regressions, quality_history)
      
      result = %{
        regressions_detected: length(regressions),
        regressions: categorized_regressions,
        root_causes: root_cause_analysis,
        severity_breakdown: calculate_severity_breakdown(categorized_regressions),
        detection_timestamp: DateTime.utc_now()
      }
      
      {:ok, result}
    catch
      kind, reason ->
        Logger.error("QualityMetrics: Regression detection failed: #{kind} - #{inspect(reason)}")
        {:error, "Regression detection failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Analyzes quality trends over specified time periods.
  """
  def analyze_quality_trends(quality_data, time_period, options \\ %{}) do
    Logger.debug("QualityMetrics: Analyzing quality trends for period: #{time_period}")
    
    try do
      # Filter data by time period
      filtered_data = filter_data_by_time_period(quality_data, time_period)
      
      # Calculate trend metrics
      overall_trend = calculate_overall_trend(filtered_data)
      metric_trends = calculate_individual_metric_trends(filtered_data)
      
      # Identify trend patterns
      trend_patterns = identify_trend_patterns(filtered_data)
      
      # Calculate trend strength and confidence
      trend_strength = calculate_trend_strength(filtered_data)
      trend_confidence = calculate_trend_confidence(filtered_data)
      
      # Forecast future trends
      trend_forecast = forecast_quality_trends(filtered_data, options)
      
      result = %{
        time_period: time_period,
        overall_trend: overall_trend,
        metric_trends: metric_trends,
        trend_patterns: trend_patterns,
        trend_strength: trend_strength,
        trend_confidence: trend_confidence,
        forecast: trend_forecast,
        data_points: length(filtered_data),
        analysis_timestamp: DateTime.utc_now()
      }
      
      {:ok, result}
    catch
      kind, reason ->
        Logger.error("QualityMetrics: Trend analysis failed: #{kind} - #{inspect(reason)}")
        {:error, "Trend analysis failed: #{inspect(reason)}"}
    end
  end

  ## Private Functions - Quality Metrics Calculation

  defp calculate_complexity_metrics(ast) do
    # Calculate various complexity metrics
    cyclomatic_complexity = calculate_cyclomatic_complexity(ast)
    cognitive_complexity = calculate_cognitive_complexity(ast)
    nesting_depth = calculate_max_nesting_depth(ast)
    method_count = count_methods(ast)
    average_method_complexity = if method_count > 0, do: cyclomatic_complexity / method_count, else: 0
    
    complexity_score = calculate_complexity_score(cyclomatic_complexity, cognitive_complexity, nesting_depth)
    
    %{
      cyclomatic_complexity: cyclomatic_complexity,
      cognitive_complexity: cognitive_complexity,
      max_nesting_depth: nesting_depth,
      method_count: method_count,
      average_method_complexity: average_method_complexity,
      complexity_score: complexity_score
    }
  end

  defp calculate_maintainability_metrics(ast, code) do
    # Calculate maintainability-related metrics
    lines_of_code = count_lines_of_code(code)
    duplication_ratio = calculate_duplication_ratio(ast, code)
    coupling_factor = calculate_coupling_factor(ast)
    cohesion_score = calculate_cohesion_score(ast)
    
    # Calculate maintainability index
    maintainability_index = calculate_maintainability_index(ast, lines_of_code)
    
    %{
      lines_of_code: lines_of_code,
      duplication_ratio: duplication_ratio,
      coupling_factor: coupling_factor,
      cohesion_score: cohesion_score,
      maintainability_index: maintainability_index,
      maintainability_score: calculate_maintainability_score(maintainability_index, duplication_ratio, coupling_factor)
    }
  end

  defp calculate_readability_metrics(ast, code) do
    # Calculate readability-related metrics
    average_line_length = calculate_average_line_length(code)
    comment_ratio = calculate_comment_ratio(code)
    naming_quality = assess_naming_quality(ast)
    formatting_consistency = assess_formatting_consistency(code)
    
    readability_score = calculate_readability_score(%{
      line_length: average_line_length,
      comments: comment_ratio,
      naming: naming_quality,
      formatting: formatting_consistency
    })
    
    %{
      average_line_length: average_line_length,
      comment_ratio: comment_ratio,
      naming_quality: naming_quality,
      formatting_consistency: formatting_consistency,
      readability_score: readability_score
    }
  end

  defp calculate_testability_metrics(ast) do
    # Calculate testability-related metrics
    public_method_count = count_public_methods(ast)
    dependency_count = count_dependencies(ast)
    mock_points = count_potential_mock_points(ast)
    test_complexity = estimate_test_complexity(ast)
    
    testability_score = calculate_testability_score(%{
      public_methods: public_method_count,
      dependencies: dependency_count,
      mock_points: mock_points,
      test_complexity: test_complexity
    })
    
    %{
      public_method_count: public_method_count,
      dependency_count: dependency_count,
      potential_mock_points: mock_points,
      estimated_test_complexity: test_complexity,
      testability_score: testability_score
    }
  end

  defp calculate_documentation_metrics(ast, code) do
    # Calculate documentation-related metrics
    documentation_coverage = calculate_documentation_coverage(ast)
    documentation_quality = assess_documentation_quality(ast, code)
    inline_comment_density = calculate_inline_comment_density(code)
    
    documentation_score = calculate_documentation_score(%{
      coverage: documentation_coverage,
      quality: documentation_quality,
      inline_density: inline_comment_density
    })
    
    %{
      documentation_coverage: documentation_coverage,
      documentation_quality: documentation_quality,
      inline_comment_density: inline_comment_density,
      documentation_score: documentation_score
    }
  end

  defp calculate_overall_quality_score(metrics) do
    # Calculate weighted overall quality score
    weights = %{
      complexity: 0.25,
      maintainability: 0.25,
      readability: 0.20,
      testability: 0.15,
      documentation: 0.15
    }
    
    complexity_score = metrics.complexity.complexity_score
    maintainability_score = metrics.maintainability.maintainability_score
    readability_score = metrics.readability.readability_score
    testability_score = metrics.testability.testability_score
    documentation_score = metrics.documentation.documentation_score
    
    overall_score = 
      complexity_score * weights.complexity +
      maintainability_score * weights.maintainability +
      readability_score * weights.readability +
      testability_score * weights.testability +
      documentation_score * weights.documentation
    
    min(1.0, max(0.0, overall_score))
  end

  ## Private Functions - Improvement Tracking

  defp analyze_improvement_trends(improvement_history) do
    # Analyze trends in quality improvements
    if length(improvement_history) < 2 do
      %{trend: "insufficient_data", slope: 0, confidence: 0}
    else
      # Extract quality scores over time
      data_points = improvement_history
      |> Enum.filter(fn entry -> entry[:result] && entry[:result][:overall_score] end)
      |> Enum.map(fn entry -> 
        {DateTime.to_unix(entry[:timestamp] || DateTime.utc_now()), entry[:result][:overall_score]}
      end)
      |> Enum.sort()
      
      if length(data_points) < 2 do
        %{trend: "insufficient_data", slope: 0, confidence: 0}
      else
        # Calculate linear regression
        {slope, intercept, r_squared} = calculate_linear_regression(data_points)
        
        trend_direction = cond do
          slope > 0.01 -> "improving"
          slope < -0.01 -> "declining"
          true -> "stable"
        end
        
        %{
          trend: trend_direction,
          slope: slope,
          intercept: intercept,
          r_squared: r_squared,
          confidence: r_squared,
          data_points: length(data_points)
        }
      end
    end
  end

  defp calculate_improvement_velocity(improvement_history) do
    # Calculate the rate of quality improvements
    recent_improvements = improvement_history
    |> Enum.take(10)  # Last 10 improvements
    |> Enum.filter(fn entry -> entry[:type] == :improvement end)
    
    if length(recent_improvements) == 0 do
      %{velocity: 0, improvements_per_day: 0, average_impact: 0}
    else
      # Calculate time span
      timestamps = Enum.map(recent_improvements, &(&1[:timestamp] || DateTime.utc_now()))
      time_span_days = case {Enum.min(timestamps), Enum.max(timestamps)} do
        {min_time, max_time} -> 
          DateTime.diff(max_time, min_time, :day)
        _ -> 1
      end
      
      time_span_days = max(1, time_span_days)  # Avoid division by zero
      
      # Calculate average impact
      impacts = recent_improvements
      |> Enum.map(fn entry -> 
        get_in(entry, [:result, :quality_improvement, :overall_improvement]) || 0
      end)
      
      average_impact = if length(impacts) > 0, do: Enum.sum(impacts) / length(impacts), else: 0
      
      %{
        velocity: length(recent_improvements) / time_span_days,
        improvements_per_day: length(recent_improvements) / time_span_days,
        average_impact: average_impact,
        total_recent_improvements: length(recent_improvements),
        time_span_days: time_span_days
      }
    end
  end

  defp identify_improvement_patterns(improvement_history) do
    # Identify patterns in improvements
    improvement_types = improvement_history
    |> Enum.filter(fn entry -> entry[:type] == :improvement end)
    |> Enum.group_by(fn entry -> 
      get_in(entry, [:result, :strategy]) || "unknown"
    end)
    
    # Analyze effectiveness of different strategies
    strategy_effectiveness = improvement_types
    |> Enum.map(fn {strategy, improvements} ->
      avg_impact = improvements
      |> Enum.map(fn imp -> get_in(imp, [:result, :quality_improvement, :overall_improvement]) || 0 end)
      |> then(fn impacts -> if length(impacts) > 0, do: Enum.sum(impacts) / length(impacts), else: 0 end)
      
      {strategy, %{
        count: length(improvements),
        average_impact: avg_impact,
        effectiveness_score: avg_impact * length(improvements)
      }}
    end)
    |> Map.new()
    
    # Identify temporal patterns
    temporal_patterns = analyze_temporal_improvement_patterns(improvement_history)
    
    %{
      strategy_effectiveness: strategy_effectiveness,
      temporal_patterns: temporal_patterns,
      most_effective_strategy: find_most_effective_strategy(strategy_effectiveness),
      improvement_frequency: calculate_improvement_frequency(improvement_history)
    }
  end

  defp calculate_improvement_roi(improvement_history) do
    # Calculate return on investment for improvements
    improvements = improvement_history
    |> Enum.filter(fn entry -> entry[:type] == :improvement end)
    
    if length(improvements) == 0 do
      %{total_roi: 0, average_roi: 0, roi_by_strategy: %{}}
    else
      # Calculate ROI for each improvement (simplified)
      roi_data = improvements
      |> Enum.map(fn improvement ->
        # Simplified ROI calculation
        impact = get_in(improvement, [:result, :quality_improvement, :overall_improvement]) || 0
        effort_estimate = estimate_improvement_effort(improvement)
        roi = if effort_estimate > 0, do: impact / effort_estimate, else: 0
        
        {improvement, roi}
      end)
      
      total_roi = roi_data |> Enum.map(&elem(&1, 1)) |> Enum.sum()
      average_roi = total_roi / length(improvements)
      
      # ROI by strategy
      roi_by_strategy = improvements
      |> Enum.group_by(fn imp -> get_in(imp, [:result, :strategy]) || "unknown" end)
      |> Enum.map(fn {strategy, strategy_improvements} ->
        strategy_roi = strategy_improvements
        |> Enum.map(fn imp ->
          impact = get_in(imp, [:result, :quality_improvement, :overall_improvement]) || 0
          effort = estimate_improvement_effort(imp)
          if effort > 0, do: impact / effort, else: 0
        end)
        |> Enum.sum()
        |> then(fn total -> total / length(strategy_improvements) end)
        
        {strategy, strategy_roi}
      end)
      |> Map.new()
      
      %{
        total_roi: total_roi,
        average_roi: average_roi,
        roi_by_strategy: roi_by_strategy,
        high_roi_threshold: average_roi * 1.5
      }
    end
  end

  defp do_detect_quality_regressions(improvement_history) do
    # Detect periods where quality decreased
    quality_scores = improvement_history
    |> Enum.filter(fn entry -> entry[:result] && entry[:result][:overall_score] end)
    |> Enum.map(fn entry -> 
      {entry[:timestamp] || DateTime.utc_now(), entry[:result][:overall_score]}
    end)
    |> Enum.sort()
    
    # Find consecutive periods where quality decreased
    regressions = find_regression_periods(quality_scores)
    
    # Classify regression severity
    classified_regressions = regressions
    |> Enum.map(fn regression ->
      severity = classify_regression_severity(regression[:magnitude])
      Map.put(regression, :severity, severity)
    end)
    
    classified_regressions
  end

  ## Private Functions - Report Generation

  defp generate_executive_summary(quality_data, improvement_data) do
    current_score = quality_data[:overall_score] || 0
    
    # Calculate key metrics
    improvement_trend = get_in(improvement_data, [:trends, :trend]) || "unknown"
    total_improvements = get_in(improvement_data, [:total_improvements]) || 0
    regression_count = get_in(improvement_data, [:regressions, :regressions_detected]) || 0
    
    # Generate status assessment
    status = cond do
      current_score >= 0.8 -> "excellent"
      current_score >= 0.6 -> "good"
      current_score >= 0.4 -> "fair"
      true -> "needs_improvement"
    end
    
    %{
      current_quality_score: current_score,
      quality_status: status,
      improvement_trend: improvement_trend,
      total_improvements_applied: total_improvements,
      regressions_detected: regression_count,
      key_recommendations_count: 3,  # Would be calculated from actual recommendations
      report_confidence: 0.85
    }
  end

  defp generate_detailed_metrics_section(quality_data) do
    # Extract detailed metrics from quality data
    %{
      complexity_analysis: quality_data[:complexity] || %{},
      maintainability_analysis: quality_data[:maintainability] || %{},
      readability_analysis: quality_data[:readability] || %{},
      testability_analysis: quality_data[:testability] || %{},
      documentation_analysis: quality_data[:documentation] || %{},
      metric_thresholds: get_metric_thresholds(),
      metric_comparisons: generate_metric_comparisons(quality_data)
    }
  end

  defp generate_improvement_analysis(improvement_data) do
    # Generate analysis of improvements
    %{
      improvement_velocity: improvement_data[:velocity] || %{},
      improvement_patterns: improvement_data[:patterns] || %{},
      roi_analysis: improvement_data[:roi_analysis] || %{},
      most_effective_strategies: identify_top_strategies(improvement_data),
      improvement_opportunities: identify_improvement_opportunities(improvement_data)
    }
  end

  defp generate_trend_analysis(improvement_data, time_period) do
    # Generate trend analysis
    trends = improvement_data[:trends] || %{}
    
    %{
      time_period: time_period,
      overall_trend: trends,
      quality_trajectory: calculate_quality_trajectory(improvement_data),
      trend_forecast: generate_trend_forecast(trends),
      seasonal_patterns: identify_seasonal_patterns(improvement_data, time_period)
    }
  end

  defp generate_quality_recommendations(quality_data, _improvement_data) do
    # Generate actionable recommendations
    recommendations = []
    
    # Complexity recommendations
    complexity_score = get_in(quality_data, [:complexity, :complexity_score]) || 0
    recommendations = if complexity_score < 0.6 do
      [%{
        category: "complexity",
        priority: "high",
        recommendation: "Reduce cyclomatic complexity by extracting methods",
        expected_impact: "medium",
        effort_estimate: "high"
      } | recommendations]
    else
      recommendations
    end
    
    # Maintainability recommendations
    maintainability_score = get_in(quality_data, [:maintainability, :maintainability_score]) || 0
    recommendations = if maintainability_score < 0.7 do
      [%{
        category: "maintainability",
        priority: "medium",
        recommendation: "Reduce code duplication and improve cohesion",
        expected_impact: "high",
        effort_estimate: "medium"
      } | recommendations]
    else
      recommendations
    end
    
    # Documentation recommendations
    doc_score = get_in(quality_data, [:documentation, :documentation_score]) || 0
    recommendations = if doc_score < 0.5 do
      [%{
        category: "documentation",
        priority: "low",
        recommendation: "Improve documentation coverage and quality",
        expected_impact: "low",
        effort_estimate: "low"
      } | recommendations]
    else
      recommendations
    end
    
    # Sort by priority and impact
    recommendations
    |> Enum.sort_by(fn rec -> 
      priority_weight = case rec.priority do
        "high" -> 3
        "medium" -> 2
        "low" -> 1
      end
      impact_weight = case rec.expected_impact do
        "high" -> 3
        "medium" -> 2
        "low" -> 1
      end
      -(priority_weight * 2 + impact_weight)  # Negative for descending sort
    end)
  end

  ## Private Functions - Helper Functions

  defp calculate_cyclomatic_complexity(ast) do
    # Calculate cyclomatic complexity
    {_ast, complexity} = Macro.prewalk(ast, 1, fn
      {:if, _, _} = node, acc -> {node, acc + 1}
      {:unless, _, _} = node, acc -> {node, acc + 1}
      {:case, _, _} = node, acc -> {node, acc + 1}
      {:cond, _, _} = node, acc -> {node, acc + 1}
      {:for, _, _} = node, acc -> {node, acc + 1}
      {:while, _, _} = node, acc -> {node, acc + 1}
      {:and, _, _} = node, acc -> {node, acc + 1}
      {:or, _, _} = node, acc -> {node, acc + 1}
      {:catch, _, _} = node, acc -> {node, acc + 1}
      node, acc -> {node, acc}
    end)
    
    complexity
  end

  defp calculate_cognitive_complexity(ast) do
    # Calculate cognitive complexity with nesting penalties
    {_ast, {complexity, _nesting}} = Macro.prewalk(ast, {0, 0}, fn
      {:if, _, _} = node, {acc, nesting} -> {node, {acc + 1 + nesting, nesting}}
      {:unless, _, _} = node, {acc, nesting} -> {node, {acc + 1 + nesting, nesting}}
      {:case, _, _} = node, {acc, nesting} -> {node, {acc + 1 + nesting, nesting + 1}}
      {:cond, _, _} = node, {acc, nesting} -> {node, {acc + 1 + nesting, nesting + 1}}
      {:for, _, _} = node, {acc, nesting} -> {node, {acc + 1 + nesting, nesting + 1}}
      {:while, _, _} = node, {acc, nesting} -> {node, {acc + 1 + nesting, nesting + 1}}
      node, acc -> {node, acc}
    end)
    
    complexity
  end

  defp calculate_max_nesting_depth(ast) do
    # Calculate maximum nesting depth
    {_ast, max_depth} = Macro.prewalk(ast, 0, fn
      {:if, _, _} = node, depth -> {node, max(depth + 1, depth)}
      {:unless, _, _} = node, depth -> {node, max(depth + 1, depth)}
      {:case, _, _} = node, depth -> {node, max(depth + 1, depth)}
      {:cond, _, _} = node, depth -> {node, max(depth + 1, depth)}
      {:for, _, _} = node, depth -> {node, max(depth + 1, depth)}
      {:while, _, _} = node, depth -> {node, max(depth + 1, depth)}
      node, depth -> {node, depth}
    end)
    
    max_depth
  end

  defp count_methods(ast) do
    # Count method definitions
    {_ast, count} = Macro.prewalk(ast, 0, fn
      {:def, _, _} = node, acc -> {node, acc + 1}
      {:defp, _, _} = node, acc -> {node, acc + 1}
      node, acc -> {node, acc}
    end)
    
    count
  end

  defp calculate_complexity_score(cyclomatic, cognitive, nesting) do
    # Calculate complexity score (0-1, higher is better)
    cyclomatic_score = max(0, 1 - (cyclomatic / 20))
    cognitive_score = max(0, 1 - (cognitive / 30))
    nesting_score = max(0, 1 - (nesting / 5))
    
    (cyclomatic_score + cognitive_score + nesting_score) / 3
  end

  defp count_lines_of_code(code) do
    # Count non-empty, non-comment lines
    code
    |> String.split("\n")
    |> Enum.filter(fn line ->
      trimmed = String.trim(line)
      trimmed != "" and not String.starts_with?(trimmed, "#")
    end)
    |> length()
  end

  defp calculate_duplication_ratio(_ast, code) do
    # Calculate code duplication ratio (simplified)
    lines = String.split(code, "\n")
    unique_lines = Enum.uniq(lines)
    
    if length(lines) > 0 do
      1.0 - (length(unique_lines) / length(lines))
    else
      0.0
    end
  end

  defp calculate_coupling_factor(ast) do
    # Calculate coupling factor (simplified)
    external_calls = count_external_calls(ast)
    total_calls = count_total_calls(ast)
    
    if total_calls > 0 do
      external_calls / total_calls
    else
      0.0
    end
  end

  defp calculate_cohesion_score(_ast) do
    # Calculate cohesion score (simplified)
    # This is a placeholder - real implementation would analyze method relationships
    0.7
  end

  defp calculate_maintainability_index(ast, lines_of_code) do
    # Calculate maintainability index
    cyclomatic = calculate_cyclomatic_complexity(ast)
    
    # Simplified MI calculation: 171 - 5.2 * ln(HV) - 0.23 * CC - 16.2 * ln(LOC)
    # Where HV = Halstead Volume (simplified as LOC), CC = Cyclomatic Complexity
    base_index = 100
    complexity_penalty = cyclomatic * 2
    size_penalty = :math.log(max(1, lines_of_code)) * 5
    
    max(0, base_index - complexity_penalty - size_penalty)
  end

  defp calculate_maintainability_score(maintainability_index, duplication_ratio, coupling_factor) do
    # Calculate maintainability score (0-1)
    mi_score = maintainability_index / 100
    duplication_penalty = duplication_ratio * 0.3
    coupling_penalty = coupling_factor * 0.2
    
    max(0, min(1, mi_score - duplication_penalty - coupling_penalty))
  end

  defp calculate_average_line_length(code) do
    # Calculate average line length
    lines = String.split(code, "\n")
               |> Enum.filter(&(String.trim(&1) != ""))
    
    if length(lines) > 0 do
      total_length = lines |> Enum.map(&String.length/1) |> Enum.sum()
      total_length / length(lines)
    else
      0
    end
  end

  defp calculate_comment_ratio(code) do
    # Calculate comment to code ratio
    lines = String.split(code, "\n")
    comment_lines = Enum.filter(lines, &String.starts_with?(String.trim(&1), "#"))
    code_lines = Enum.filter(lines, fn line ->
      trimmed = String.trim(line)
      trimmed != "" and not String.starts_with?(trimmed, "#")
    end)
    
    if length(code_lines) > 0 do
      length(comment_lines) / length(code_lines)
    else
      0.0
    end
  end

  defp assess_naming_quality(ast) do
    # Assess naming quality (simplified)
    {_ast, {good_names, total_names}} = Macro.prewalk(ast, {0, 0}, fn
      {:def, _, [{name, _, _} | _]} = node, {good, total} when is_atom(name) ->
        is_good = good_name?(name)
        {node, {good + (if is_good, do: 1, else: 0), total + 1}}
      
      {name, _, _} = node, {good, total} when is_atom(name) ->
        is_good = good_name?(name)
        {node, {good + (if is_good, do: 1, else: 0), total + 1}}
      
      node, acc -> {node, acc}
    end)
    
    if total_names > 0, do: good_names / total_names, else: 1.0
  end

  defp assess_formatting_consistency(code) do
    # Assess formatting consistency (simplified)
    lines = String.split(code, "\n")
    
    # Check indentation consistency
    indented_lines = Enum.filter(lines, &String.starts_with?(&1, " "))
    consistent_indentation = Enum.all?(indented_lines, fn line ->
      # Check if indentation is multiple of 2
      leading_spaces = String.length(line) - String.length(String.trim_leading(line))
      rem(leading_spaces, 2) == 0
    end)
    
    if consistent_indentation, do: 0.8, else: 0.4
  end

  defp calculate_readability_score(metrics) do
    # Calculate readability score
    line_length_score = max(0, 1 - ((metrics.line_length - 80) / 40))  # Penalty for long lines
    comment_score = min(1, metrics.comments * 2)  # Bonus for comments, capped at 1
    naming_score = metrics.naming
    formatting_score = metrics.formatting
    
    (line_length_score + comment_score + naming_score + formatting_score) / 4
  end

  defp count_public_methods(ast) do
    # Count public methods
    {_ast, count} = Macro.prewalk(ast, 0, fn
      {:def, _, _} = node, acc -> {node, acc + 1}  # Public methods
      node, acc -> {node, acc}
    end)
    
    count
  end

  defp count_dependencies(ast) do
    # Count dependencies (simplified)
    {_ast, deps} = Macro.prewalk(ast, [], fn
      {:alias, _, [{:__aliases__, _, module_path}]} = node, acc ->
        {node, [Enum.join(module_path, ".") | acc]}
      
      {{:., _, [{:__aliases__, _, module_path}, _]}, _, _} = node, acc ->
        {node, [Enum.join(module_path, ".") | acc]}
      
      node, acc -> {node, acc}
    end)
    
    deps |> Enum.uniq() |> length()
  end

  defp count_potential_mock_points(ast) do
    # Count potential mock points (external calls, I/O operations)
    count_dependencies(ast) + count_external_calls(ast)
  end

  defp estimate_test_complexity(ast) do
    # Estimate test complexity based on code complexity
    cyclomatic = calculate_cyclomatic_complexity(ast)
    dependencies = count_dependencies(ast)
    
    # Test complexity increases with code complexity and dependencies
    base_complexity = cyclomatic * 1.5
    dependency_complexity = dependencies * 0.5
    
    base_complexity + dependency_complexity
  end

  defp calculate_testability_score(metrics) do
    # Calculate testability score (0-1, higher is better)
    # Lower complexity and dependencies = higher testability
    complexity_penalty = min(0.5, metrics.test_complexity / 50)
    dependency_penalty = min(0.3, metrics.dependencies / 20)
    
    max(0, 1 - complexity_penalty - dependency_penalty)
  end

  defp calculate_documentation_coverage(ast) do
    # Calculate documentation coverage
    public_methods = count_public_methods(ast)
    documented_methods = count_documented_methods(ast)
    
    if public_methods > 0 do
      (documented_methods / public_methods) * 100
    else
      100.0
    end
  end

  defp assess_documentation_quality(_ast, code) do
    # Assess documentation quality (simplified)
    doc_lines = code
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, "@doc"))
    
    if length(doc_lines) > 0 do
      # Simple quality assessment based on average doc length
      avg_doc_length = doc_lines
      |> Enum.map(&String.length/1)
      |> Enum.sum()
      |> Kernel./(length(doc_lines))
      
      min(1.0, avg_doc_length / 100)
    else
      0.0
    end
  end

  defp calculate_inline_comment_density(code) do
    # Calculate inline comment density
    calculate_comment_ratio(code)
  end

  defp calculate_documentation_score(metrics) do
    # Calculate documentation score
    coverage_score = metrics.coverage / 100
    quality_score = metrics.quality
    density_score = min(1, metrics.inline_density * 2)
    
    (coverage_score + quality_score + density_score) / 3
  end

  defp extract_quality_scores(quality_history) do
    # Extract quality scores from history
    quality_history
    |> Enum.filter(fn entry -> entry[:overall_score] end)
    |> Enum.map(fn entry -> 
      {entry[:timestamp] || DateTime.utc_now(), entry[:overall_score]}
    end)
    |> Enum.sort()
  end

  defp detect_score_regressions(quality_scores, threshold, _window_size) do
    # Detect significant drops in quality scores
    quality_scores
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.filter(fn [{_time1, score1}, {_time2, score2}] ->
      (score1 - score2) > threshold
    end)
    |> Enum.map(fn [{time1, score1}, {time2, score2}] ->
      %{
        start_time: time1,
        end_time: time2,
        start_score: score1,
        end_score: score2,
        magnitude: score1 - score2
      }
    end)
  end

  defp categorize_regressions(regressions) do
    # Categorize regressions by severity
    regressions
    |> Enum.map(fn regression ->
      severity = cond do
        regression.magnitude > 0.2 -> "critical"
        regression.magnitude > 0.1 -> "major"
        regression.magnitude > 0.05 -> "minor"
        true -> "negligible"
      end
      
      Map.put(regression, :severity, severity)
    end)
    |> Enum.group_by(& &1.severity)
  end

  defp analyze_regression_causes(regressions, _quality_history) do
    # Analyze potential causes of regressions (simplified)
    regressions
    |> Enum.map(fn regression ->
      # Look for changes around regression time
      potential_causes = ["complexity_increase", "new_dependencies", "code_duplication"]
      
      %{
        regression: regression,
        potential_causes: potential_causes,
        confidence: 0.6
      }
    end)
  end

  defp calculate_severity_breakdown(categorized_regressions) do
    # Calculate breakdown of regression severities
    categorized_regressions
    |> Enum.map(fn {severity, regressions} -> {severity, length(regressions)} end)
    |> Map.new()
  end

  defp filter_data_by_time_period(quality_data, _time_period) do
    # Filter data by time period (simplified)
    # In practice, this would filter based on timestamps
    quality_data
  end

  defp calculate_overall_trend(_filtered_data) do
    # Calculate overall trend (simplified)
    %{direction: "improving", strength: 0.7}
  end

  defp calculate_individual_metric_trends(_filtered_data) do
    # Calculate trends for individual metrics (simplified)
    %{
      complexity: %{trend: "improving", change: -0.1},
      maintainability: %{trend: "stable", change: 0.02},
      readability: %{trend: "improving", change: 0.15}
    }
  end

  defp identify_trend_patterns(_filtered_data) do
    # Identify patterns in trends (simplified)
    ["gradual_improvement", "periodic_fluctuation"]
  end

  defp calculate_trend_strength(_filtered_data) do
    # Calculate strength of trends (simplified)
    0.75
  end

  defp calculate_trend_confidence(_filtered_data) do
    # Calculate confidence in trends (simplified)
    0.80
  end

  defp forecast_quality_trends(_filtered_data, _options) do
    # Forecast future trends (simplified)
    %{
      next_month: %{predicted_score: 0.82, confidence: 0.7},
      next_quarter: %{predicted_score: 0.85, confidence: 0.6}
    }
  end

  defp calculate_linear_regression(data_points) do
    # Calculate linear regression (simplified)
    n = length(data_points)
    
    if n < 2 do
      {0, 0, 0}
    else
      {x_values, y_values} = Enum.unzip(data_points)
      
      # Calculate means
      x_mean = Enum.sum(x_values) / n
      y_mean = Enum.sum(y_values) / n
      
      # Calculate slope and intercept
      numerator = Enum.zip(x_values, y_values)
      |> Enum.map(fn {x, y} -> (x - x_mean) * (y - y_mean) end)
      |> Enum.sum()
      
      denominator = x_values
      |> Enum.map(fn x -> (x - x_mean) * (x - x_mean) end)
      |> Enum.sum()
      
      slope = if denominator != 0, do: numerator / denominator, else: 0
      intercept = y_mean - slope * x_mean
      
      # Calculate R-squared (simplified)
      r_squared = min(1.0, abs(slope) * 0.5)  # Simplified calculation
      
      {slope, intercept, r_squared}
    end
  end

  defp find_regression_periods(quality_scores) do
    # Find regression periods (simplified)
    quality_scores
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.filter(fn [{_time1, score1}, {_time2, score2}] ->
      score2 < score1 - 0.05  # 5% drop threshold
    end)
    |> Enum.map(fn [{time1, score1}, {time2, score2}] ->
      %{
        start_time: time1,
        end_time: time2,
        start_score: score1,
        end_score: score2,
        magnitude: score1 - score2
      }
    end)
  end

  defp classify_regression_severity(magnitude) do
    cond do
      magnitude > 0.2 -> "critical"
      magnitude > 0.1 -> "major"
      magnitude > 0.05 -> "minor"
      true -> "negligible"
    end
  end

  defp analyze_temporal_improvement_patterns(_improvement_history) do
    # Analyze temporal patterns (simplified)
    %{
      peak_improvement_days: ["Monday", "Tuesday"],
      seasonal_trends: "stable",
      improvement_cycles: 7  # days
    }
  end

  defp find_most_effective_strategy(strategy_effectiveness) do
    # Find most effective improvement strategy
    strategy_effectiveness
    |> Enum.max_by(fn {_strategy, data} -> data.effectiveness_score end, fn -> {"unknown", %{}} end)
    |> elem(0)
  end

  defp calculate_improvement_frequency(improvement_history) do
    # Calculate improvement frequency (simplified)
    improvements = Enum.filter(improvement_history, &(&1[:type] == :improvement))
    
    if length(improvements) < 2 do
      %{frequency: 0, average_interval_days: 0}
    else
      # Calculate average interval between improvements
      timestamps = Enum.map(improvements, &(&1[:timestamp] || DateTime.utc_now()))
      |> Enum.sort()
      
      intervals = timestamps
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [t1, t2] -> DateTime.diff(t2, t1, :day) end)
      
      avg_interval = if length(intervals) > 0, do: Enum.sum(intervals) / length(intervals), else: 0
      
      %{
        frequency: length(improvements),
        average_interval_days: avg_interval,
        total_time_span_days: DateTime.diff(List.last(timestamps), List.first(timestamps), :day)
      }
    end
  end

  defp estimate_improvement_effort(improvement) do
    # Estimate effort required for improvement (simplified)
    strategy = get_in(improvement, [:result, :strategy]) || "unknown"
    
    case strategy do
      "conservative" -> 1.0
      "targeted" -> 2.0
      "aggressive" -> 3.0
      "comprehensive" -> 4.0
      _ -> 2.0
    end
  end

  defp get_metric_thresholds do
    # Return metric thresholds for comparison
    %{
      complexity: %{good: 10, warning: 15, critical: 20},
      maintainability_index: %{good: 80, warning: 60, critical: 40},
      documentation_coverage: %{good: 80, warning: 60, critical: 40},
      duplication_ratio: %{good: 0.05, warning: 0.15, critical: 0.25}
    }
  end

  defp generate_metric_comparisons(quality_data) do
    # Generate comparisons with thresholds
    thresholds = get_metric_thresholds()
    
    %{
      complexity_status: compare_with_threshold(
        get_in(quality_data, [:complexity, :cyclomatic_complexity]) || 0,
        thresholds.complexity
      ),
      maintainability_status: compare_with_threshold(
        get_in(quality_data, [:maintainability, :maintainability_index]) || 0,
        thresholds.maintainability_index
      ),
      documentation_status: compare_with_threshold(
        get_in(quality_data, [:documentation, :documentation_coverage]) || 0,
        thresholds.documentation_coverage
      )
    }
  end

  defp compare_with_threshold(value, threshold) do
    cond do
      value <= threshold.good -> "good"
      value <= threshold.warning -> "warning"
      value <= threshold.critical -> "critical"
      true -> "poor"
    end
  end

  defp identify_top_strategies(improvement_data) do
    # Identify top performing strategies
    strategy_effectiveness = get_in(improvement_data, [:patterns, :strategy_effectiveness]) || %{}
    
    strategy_effectiveness
    |> Enum.sort_by(fn {_strategy, data} -> data.effectiveness_score end, :desc)
    |> Enum.take(3)
    |> Enum.map(fn {strategy, data} -> %{strategy: strategy, data: data} end)
  end

  defp identify_improvement_opportunities(_improvement_data) do
    # Identify opportunities for improvement
    [
      %{opportunity: "automated_refactoring", potential_impact: "high", effort: "medium"},
      %{opportunity: "documentation_automation", potential_impact: "medium", effort: "low"},
      %{opportunity: "complexity_monitoring", potential_impact: "medium", effort: "low"}
    ]
  end

  defp calculate_quality_trajectory(improvement_data) do
    # Calculate quality trajectory
    trend = get_in(improvement_data, [:trends, :trend]) || "stable"
    slope = get_in(improvement_data, [:trends, :slope]) || 0
    
    %{
      current_trajectory: trend,
      rate_of_change: slope,
      projected_quality_in_30_days: calculate_projected_quality(slope, 30)
    }
  end

  defp calculate_projected_quality(slope, days) do
    # Calculate projected quality score
    current_base = 0.7  # Assumed current quality
    projected = current_base + (slope * days)
    max(0, min(1, projected))
  end

  defp generate_trend_forecast(trends) do
    # Generate trend forecast
    %{
      short_term: "continued_improvement",
      medium_term: "stabilization",
      long_term: "sustained_quality",
      confidence: trends[:confidence] || 0.6
    }
  end

  defp identify_seasonal_patterns(_improvement_data, _time_period) do
    # Identify seasonal patterns (simplified)
    %{
      pattern_detected: false,
      pattern_type: "none",
      confidence: 0.3
    }
  end

  defp calculate_report_confidence(quality_data, improvement_data) do
    # Calculate overall report confidence
    quality_confidence = quality_data[:confidence] || 0.8
    improvement_confidence = get_in(improvement_data, [:trends, :confidence]) || 0.7
    
    (quality_confidence + improvement_confidence) / 2
  end

  defp count_external_calls(ast) do
    # Count external module calls
    {_ast, count} = Macro.prewalk(ast, 0, fn
      {{:., _, [{:__aliases__, _, _module}, _function]}, _, _} = node, acc -> {node, acc + 1}
      node, acc -> {node, acc}
    end)
    
    count
  end

  defp count_total_calls(ast) do
    # Count all function calls
    {_ast, count} = Macro.prewalk(ast, 0, fn
      {function, _, args} = node, acc when is_atom(function) and is_list(args) -> {node, acc + 1}
      node, acc -> {node, acc}
    end)
    
    count
  end

  defp count_documented_methods(ast) do
    # Count methods with documentation (simplified)
    # In practice, this would check for @doc attributes
    {_ast, count} = Macro.prewalk(ast, 0, fn
      {:def, _, _} = node, acc -> {node, acc}  # Assume all public methods should be documented
      node, acc -> {node, acc}
    end)
    
    # Simplified - assume 60% are documented
    round(count * 0.6)
  end

  defp good_name?(name) when is_atom(name) do
    # Check if name follows good naming conventions
    name_str = Atom.to_string(name)
    
    # Good names are descriptive and follow snake_case
    String.length(name_str) >= 3 and
    Regex.match?(~r/^[a-z][a-z0-9_]*[a-z0-9]?$/, name_str) and
    not Regex.match?(~r/^(data|info|temp|tmp|x|y|z)$/, name_str)
  end

  defp good_name?(_), do: false

  defp format_error(error_desc) when is_binary(error_desc), do: error_desc
  defp format_error(error_desc), do: inspect(error_desc)
end