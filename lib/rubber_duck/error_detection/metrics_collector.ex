defmodule RubberDuck.ErrorDetection.MetricsCollector do
  @moduledoc """
  Metrics collection and analysis for error detection performance.
  
  Provides comprehensive metrics tracking for:
  - Detection accuracy and performance
  - False positive and negative rates
  - Pattern recognition effectiveness
  - System coverage and completeness
  - Optimization recommendations
  """

  require Logger

  @doc """
  Collects comprehensive detection metrics.
  """
  def collect_detection_metrics(base_metrics) do
    %{
      detection_performance: calculate_detection_performance(base_metrics),
      accuracy_metrics: calculate_accuracy_metrics(base_metrics),
      coverage_metrics: calculate_coverage_metrics(base_metrics),
      efficiency_metrics: calculate_efficiency_metrics(base_metrics),
      trend_analysis: calculate_trend_analysis(base_metrics),
      optimization_recommendations: generate_optimization_recommendations(base_metrics)
    }
  end

  @doc """
  Tracks detection accuracy over time.
  """
  def track_accuracy(metrics, detection_result, actual_result) do
    is_correct = evaluate_detection_correctness(detection_result, actual_result)
    
    updated_metrics = %{metrics |
      total_detections: metrics.total_detections + 1,
      correct_detections: metrics.correct_detections + (if is_correct, do: 1, else: 0),
      detection_accuracy: calculate_accuracy_rate(
        metrics.correct_detections + (if is_correct, do: 1, else: 0),
        metrics.total_detections + 1
      )
    }
    
    # Update confusion matrix
    update_confusion_matrix(updated_metrics, detection_result, actual_result)
  end

  @doc """
  Analyzes false positive patterns.
  """
  def analyze_false_positives(false_positives) do
    %{
      total_false_positives: length(false_positives),
      false_positive_rate: calculate_false_positive_rate(false_positives),
      common_patterns: identify_common_false_positive_patterns(false_positives),
      category_breakdown: categorize_false_positives(false_positives),
      severity_distribution: analyze_severity_distribution(false_positives),
      recommendations: generate_false_positive_recommendations(false_positives)
    }
  end

  @doc """
  Measures detection latency and performance.
  """
  def measure_performance(start_time, end_time, content_size, errors_found) do
    detection_time_ms = DateTime.diff(end_time, start_time, :millisecond)
    
    %{
      detection_time_ms: detection_time_ms,
      throughput_chars_per_sec: calculate_throughput(content_size, detection_time_ms),
      errors_per_second: calculate_error_detection_rate(errors_found, detection_time_ms),
      performance_rating: rate_performance(detection_time_ms, content_size),
      efficiency_score: calculate_efficiency_score(detection_time_ms, errors_found)
    }
  end

  @doc """
  Calculates system coverage metrics.
  """
  def calculate_coverage(monitored_components, total_components) do
    coverage_percentage = (map_size(monitored_components) / total_components) * 100
    
    %{
      coverage_percentage: coverage_percentage,
      monitored_components: map_size(monitored_components),
      total_components: total_components,
      uncovered_components: total_components - map_size(monitored_components),
      coverage_gaps: identify_coverage_gaps(monitored_components, total_components),
      coverage_quality: assess_coverage_quality(monitored_components)
    }
  end

  @doc """
  Generates optimization recommendations based on metrics.
  """
  def generate_recommendations(metrics, performance_data, coverage_data) do
    recommendations = []
    
    # Performance recommendations
    recommendations = recommendations ++ analyze_performance_recommendations(performance_data)
    
    # Accuracy recommendations
    recommendations = recommendations ++ analyze_accuracy_recommendations(metrics)
    
    # Coverage recommendations
    recommendations = recommendations ++ analyze_coverage_recommendations(coverage_data)
    
    # Pattern optimization recommendations
    recommendations = recommendations ++ analyze_pattern_recommendations(metrics)
    
    %{
      recommendations: recommendations,
      priority_actions: filter_priority_recommendations(recommendations),
      estimated_improvements: estimate_improvement_impact(recommendations)
    }
  end

  # Private Implementation Functions

  # Detection Performance Metrics
  defp calculate_detection_performance(metrics) do
    %{
      total_detections: metrics.total_detections,
      successful_detections: metrics.errors_found,
      detection_rate: safe_divide(metrics.errors_found, metrics.total_detections),
      average_detection_time: metrics.avg_detection_time,
      peak_detection_time: Map.get(metrics, :peak_detection_time, 0),
      detection_throughput: calculate_detection_throughput(metrics)
    }
  end

  defp calculate_detection_throughput(metrics) do
    if metrics.avg_detection_time > 0 do
      1000 / metrics.avg_detection_time  # Detections per second
    else
      0
    end
  end

  # Accuracy Metrics
  defp calculate_accuracy_metrics(metrics) do
    %{
      overall_accuracy: metrics.detection_accuracy,
      precision: calculate_precision(metrics),
      recall: calculate_recall(metrics),
      f1_score: calculate_f1_score(metrics),
      false_positive_rate: calculate_fp_rate(metrics),
      false_negative_rate: calculate_fn_rate(metrics)
    }
  end

  defp calculate_precision(metrics) do
    true_positives = Map.get(metrics, :true_positives, 0)
    false_positives = Map.get(metrics, :false_positives, 0)
    
    safe_divide(true_positives, true_positives + false_positives)
  end

  defp calculate_recall(metrics) do
    true_positives = Map.get(metrics, :true_positives, 0)
    false_negatives = Map.get(metrics, :false_negatives, 0)
    
    safe_divide(true_positives, true_positives + false_negatives)
  end

  defp calculate_f1_score(metrics) do
    precision = calculate_precision(metrics)
    recall = calculate_recall(metrics)
    
    if precision + recall > 0 do
      2 * (precision * recall) / (precision + recall)
    else
      0
    end
  end

  defp calculate_fp_rate(metrics) do
    false_positives = Map.get(metrics, :false_positives, 0)
    true_negatives = Map.get(metrics, :true_negatives, 0)
    
    safe_divide(false_positives, false_positives + true_negatives)
  end

  defp calculate_fn_rate(metrics) do
    false_negatives = Map.get(metrics, :false_negatives, 0)
    true_positives = Map.get(metrics, :true_positives, 0)
    
    safe_divide(false_negatives, false_negatives + true_positives)
  end

  # Coverage Metrics
  defp calculate_coverage_metrics(metrics) do
    %{
      code_coverage: Map.get(metrics, :code_coverage, 0),
      error_type_coverage: Map.get(metrics, :error_type_coverage, 0),
      pattern_coverage: Map.get(metrics, :pattern_coverage, 0),
      temporal_coverage: Map.get(metrics, :temporal_coverage, 0),
      system_component_coverage: Map.get(metrics, :system_component_coverage, 0)
    }
  end

  # Efficiency Metrics
  defp calculate_efficiency_metrics(metrics) do
    %{
      detection_efficiency: calculate_detection_efficiency(metrics),
      resource_utilization: calculate_resource_utilization(metrics),
      cost_per_detection: calculate_cost_per_detection(metrics),
      time_to_detection: Map.get(metrics, :avg_detection_time, 0),
      scalability_factor: calculate_scalability_factor(metrics)
    }
  end

  defp calculate_detection_efficiency(metrics) do
    errors_found = metrics.errors_found
    total_processing_time = Map.get(metrics, :total_processing_time, 1)
    
    errors_found / total_processing_time
  end

  defp calculate_resource_utilization(metrics) do
    %{
      cpu_utilization: Map.get(metrics, :cpu_usage, 0),
      memory_utilization: Map.get(metrics, :memory_usage, 0),
      io_utilization: Map.get(metrics, :io_usage, 0)
    }
  end

  defp calculate_cost_per_detection(metrics) do
    total_cost = Map.get(metrics, :total_processing_cost, 0)
    total_detections = max(1, metrics.total_detections)
    
    total_cost / total_detections
  end

  defp calculate_scalability_factor(metrics) do
    # Simple scalability metric based on performance degradation
    base_performance = Map.get(metrics, :base_performance, 1)
    current_performance = Map.get(metrics, :current_performance, 1)
    
    current_performance / base_performance
  end

  # Trend Analysis
  defp calculate_trend_analysis(metrics) do
    %{
      accuracy_trend: calculate_accuracy_trend(metrics),
      performance_trend: calculate_performance_trend(metrics),
      error_frequency_trend: calculate_error_frequency_trend(metrics),
      false_positive_trend: calculate_false_positive_trend(metrics)
    }
  end

  defp calculate_accuracy_trend(metrics) do
    historical_accuracy = Map.get(metrics, :historical_accuracy, [])
    
    if length(historical_accuracy) >= 2 do
      recent_accuracy = Enum.take(historical_accuracy, -5)
      calculate_trend_direction(recent_accuracy)
    else
      :insufficient_data
    end
  end

  defp calculate_performance_trend(metrics) do
    historical_performance = Map.get(metrics, :historical_performance, [])
    
    if length(historical_performance) >= 2 do
      recent_performance = Enum.take(historical_performance, -5)
      calculate_trend_direction(recent_performance)
    else
      :insufficient_data
    end
  end

  defp calculate_error_frequency_trend(metrics) do
    historical_frequencies = Map.get(metrics, :historical_error_frequencies, [])
    
    if length(historical_frequencies) >= 2 do
      recent_frequencies = Enum.take(historical_frequencies, -5)
      calculate_trend_direction(recent_frequencies)
    else
      :insufficient_data
    end
  end

  defp calculate_false_positive_trend(metrics) do
    historical_fp_rates = Map.get(metrics, :historical_fp_rates, [])
    
    if length(historical_fp_rates) >= 2 do
      recent_rates = Enum.take(historical_fp_rates, -5)
      calculate_trend_direction(recent_rates)
    else
      :insufficient_data
    end
  end

  defp calculate_trend_direction(values) when length(values) < 2, do: :insufficient_data

  defp calculate_trend_direction(values) do
    # Simple linear regression to determine trend
    n = length(values)
    sum_x = div(n * (n + 1), 2)
    sum_y = Enum.sum(values)
    sum_xy = values |> Enum.with_index(1) |> Enum.map(fn {y, x} -> x * y end) |> Enum.sum()
    sum_x2 = div(n * (n + 1) * (2 * n + 1), 6)
    
    slope = (n * sum_xy - sum_x * sum_y) / (n * sum_x2 - sum_x * sum_x)
    
    cond do
      slope > 0.05 -> :improving
      slope < -0.05 -> :degrading
      true -> :stable
    end
  end

  # Optimization Recommendations
  defp generate_optimization_recommendations(metrics) do
    recommendations = []
    
    # Check accuracy
    recommendations = if metrics.detection_accuracy < 0.8 do
      [%{
        type: :accuracy_improvement,
        priority: :high,
        description: "Detection accuracy is below 80%. Consider tuning detection parameters.",
        estimated_impact: :high
      } | recommendations]
    else
      recommendations
    end
    
    # Check false positive rate
    fp_rate = calculate_fp_rate(metrics)
    recommendations = if fp_rate > 0.1 do
      [%{
        type: :false_positive_reduction,
        priority: :medium,
        description: "False positive rate is above 10%. Review detection patterns.",
        estimated_impact: :medium
      } | recommendations]
    else
      recommendations
    end
    
    # Check performance
    recommendations = if metrics.avg_detection_time > 5000 do
      [%{
        type: :performance_optimization,
        priority: :high,
        description: "Average detection time exceeds 5 seconds. Optimize detection algorithms.",
        estimated_impact: :high
      } | recommendations]
    else
      recommendations
    end
    
    recommendations
  end

  # Performance Analysis
  defp analyze_performance_recommendations(performance_data) do
    recommendations = []
    
    # Check detection latency
    avg_latency = Map.get(performance_data, :avg_detection_time, 0)
    recommendations = if avg_latency > 2000 do
      [%{
        type: :latency_optimization,
        priority: :high,
        description: "High detection latency detected. Consider parallel processing.",
        action: "Implement concurrent detection algorithms"
      } | recommendations]
    else
      recommendations
    end
    
    # Check throughput
    throughput = Map.get(performance_data, :throughput, 0)
    recommendations = if throughput < 100 do
      [%{
        type: :throughput_improvement,
        priority: :medium,
        description: "Low detection throughput. Optimize pattern matching.",
        action: "Review and optimize regex patterns"
      } | recommendations]
    else
      recommendations
    end
    
    recommendations
  end

  defp analyze_accuracy_recommendations(metrics) do
    recommendations = []
    
    precision = calculate_precision(metrics)
    recall = calculate_recall(metrics)
    
    # Low precision
    recommendations = if precision < 0.8 do
      [%{
        type: :precision_improvement,
        priority: :high,
        description: "Low precision (#{Float.round(precision, 2)}). Many false positives detected.",
        action: "Refine detection patterns to reduce false positives"
      } | recommendations]
    else
      recommendations
    end
    
    # Low recall
    recommendations = if recall < 0.7 do
      [%{
        type: :recall_improvement,
        priority: :high,
        description: "Low recall (#{Float.round(recall, 2)}). Missing many actual errors.",
        action: "Expand detection patterns to catch more error types"
      } | recommendations]
    else
      recommendations
    end
    
    recommendations
  end

  defp analyze_coverage_recommendations(coverage_data) do
    recommendations = []
    
    coverage_percentage = Map.get(coverage_data, :coverage_percentage, 0)
    
    recommendations = if coverage_percentage < 80 do
      [%{
        type: :coverage_expansion,
        priority: :medium,
        description: "System coverage is #{Float.round(coverage_percentage, 1)}%. Expand monitoring.",
        action: "Add detection for uncovered components"
      } | recommendations]
    else
      recommendations
    end
    
    recommendations
  end

  defp analyze_pattern_recommendations(metrics) do
    pattern_matches = Map.get(metrics, :pattern_matches, 0)
    total_detections = max(1, metrics.total_detections)
    pattern_effectiveness = pattern_matches / total_detections
    
    if pattern_effectiveness < 0.5 do
      [%{
        type: :pattern_optimization,
        priority: :medium,
        description: "Pattern matching effectiveness is low (#{Float.round(pattern_effectiveness, 2)}).",
        action: "Review and update detection patterns"
      }]
    else
      []
    end
  end

  # Helper Functions
  defp safe_divide(_numerator, 0), do: 0
  defp safe_divide(numerator, denominator), do: numerator / denominator

  defp calculate_accuracy_rate(correct, total) when total > 0, do: correct / total
  defp calculate_accuracy_rate(_correct, _total), do: 0

  defp evaluate_detection_correctness(detection_result, actual_result) do
    # Simple correctness evaluation
    detected_errors = Map.get(detection_result, :errors, [])
    actual_errors = Map.get(actual_result, :errors, [])
    
    # For now, just check if the number of errors matches
    length(detected_errors) == length(actual_errors)
  end

  defp update_confusion_matrix(metrics, _detection_result, _actual_result) do
    # Update confusion matrix based on detection vs actual results
    # This is a simplified implementation
    metrics
  end

  defp calculate_false_positive_rate(false_positives) do
    # Calculate false positive rate based on historical data
    total_detections = Map.get(false_positives, :total_detections, 1)
    fp_count = Map.get(false_positives, :count, 0)
    
    fp_count / total_detections
  end

  defp identify_common_false_positive_patterns(false_positives) do
    # Identify common patterns in false positives
    patterns = Map.get(false_positives, :patterns, [])
    
    patterns
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_pattern, count} -> count end, :desc)
    |> Enum.take(5)
  end

  defp categorize_false_positives(false_positives) do
    # Categorize false positives by type
    categories = Map.get(false_positives, :categories, [])
    
    Enum.frequencies(categories)
  end

  defp analyze_severity_distribution(false_positives) do
    # Analyze severity distribution of false positives
    severities = Map.get(false_positives, :severities, [])
    
    Enum.frequencies(severities)
  end

  defp generate_false_positive_recommendations(false_positives) do
    common_patterns = identify_common_false_positive_patterns(false_positives)
    
    Enum.map(common_patterns, fn {pattern, count} ->
      %{
        type: :false_positive_reduction,
        pattern: pattern,
        frequency: count,
        recommendation: "Review and refine detection rule for pattern: #{pattern}"
      }
    end)
  end

  defp calculate_throughput(content_size, detection_time_ms) when detection_time_ms > 0 do
    content_size / (detection_time_ms / 1000)  # Characters per second
  end
  defp calculate_throughput(_content_size, _detection_time_ms), do: 0

  defp calculate_error_detection_rate(errors_found, detection_time_ms) when detection_time_ms > 0 do
    errors_found / (detection_time_ms / 1000)  # Errors per second
  end
  defp calculate_error_detection_rate(_errors_found, _detection_time_ms), do: 0

  defp rate_performance(detection_time_ms, content_size) do
    # Rate performance based on time and content size
    time_per_char = detection_time_ms / max(1, content_size)
    
    cond do
      time_per_char < 0.1 -> :excellent
      time_per_char < 0.5 -> :good
      time_per_char < 1.0 -> :fair
      true -> :poor
    end
  end

  defp calculate_efficiency_score(detection_time_ms, errors_found) do
    # Simple efficiency score: errors found per unit time
    if detection_time_ms > 0 do
      (errors_found / detection_time_ms) * 1000  # Scale to per second
    else
      0
    end
  end

  defp identify_coverage_gaps(_monitored_components, _total_components) do
    # Identify components not covered by monitoring
    ["component_a", "component_b"]  # Placeholder
  end

  defp assess_coverage_quality(_monitored_components) do
    # Assess the quality of coverage for monitored components
    %{
      deep_coverage: 0.8,
      shallow_coverage: 0.2,
      overall_quality: 0.7
    }
  end

  defp filter_priority_recommendations(recommendations) do
    Enum.filter(recommendations, &(&1.priority == :high))
  end

  defp estimate_improvement_impact(recommendations) do
    # Estimate the potential impact of implementing recommendations
    total_recommendations = length(recommendations)
    high_impact = Enum.count(recommendations, &(Map.get(&1, :estimated_impact) == :high))
    
    %{
      total_recommendations: total_recommendations,
      high_impact_count: high_impact,
      estimated_accuracy_improvement: high_impact * 0.05,  # 5% per high-impact recommendation
      estimated_performance_improvement: high_impact * 0.1  # 10% per high-impact recommendation
    }
  end
end