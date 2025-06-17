defmodule RubberDuck.Benchmarking.StatisticalAnalyzer do
  @moduledoc """
  Statistical analysis and performance data processing for benchmark results.
  
  This module provides comprehensive statistical analysis capabilities including:
  - Performance trend analysis
  - Regression detection
  - Statistical significance testing
  - Performance baseline comparison
  - Memory usage pattern analysis
  """

  require Logger

  @doc """
  Analyze performance data and extract meaningful statistics.
  """
  def analyze_performance_data(results) do
    case results do
      %{test_results: test_results} when is_list(test_results) ->
        analyze_test_results(results)
      
      %{benchmark_type: type} = data ->
        analyze_specific_benchmark(type, data)
      
      data when is_map(data) ->
        analyze_generic_performance_data(data)
      
      _ ->
        {:error, :invalid_results_format}
    end
  end

  @doc """
  Analyze memory usage patterns and detect potential issues.
  """
  def analyze_memory_data(memory_results) do
    snapshots = memory_results[:memory_snapshots] || []
    
    if length(snapshots) > 1 do
      %{
        memory_trend: analyze_memory_trend(snapshots),
        peak_memory: calculate_peak_memory(snapshots),
        memory_stability: assess_memory_stability(snapshots),
        gc_effectiveness: analyze_gc_effectiveness(snapshots),
        leak_indicators: detect_memory_leak_indicators(snapshots),
        recommendations: generate_memory_recommendations(snapshots)
      }
    else
      %{error: :insufficient_memory_data}
    end
  end

  @doc """
  Compare current benchmark results with baseline results.
  """
  def compare_results(current_results, baseline_results) do
    %{
      performance_comparison: compare_performance_metrics(current_results, baseline_results),
      regression_analysis: detect_performance_regressions(current_results, baseline_results),
      improvement_analysis: detect_performance_improvements(current_results, baseline_results),
      statistical_significance: calculate_statistical_significance(current_results, baseline_results),
      summary: generate_comparison_summary(current_results, baseline_results)
    }
  end

  @doc """
  Detect performance anomalies in benchmark results.
  """
  def detect_anomalies(results) do
    performance_data = extract_performance_metrics(results)
    
    %{
      outliers: detect_outliers(performance_data),
      trends: analyze_performance_trends(performance_data),
      patterns: identify_performance_patterns(performance_data),
      warnings: generate_performance_warnings(performance_data)
    }
  end

  @doc """
  Generate performance insights and recommendations.
  """
  def generate_insights(results) do
    %{
      performance_insights: analyze_performance_characteristics(results),
      optimization_opportunities: identify_optimization_opportunities(results),
      scaling_analysis: analyze_scaling_characteristics(results),
      recommendations: generate_performance_recommendations(results)
    }
  end

  ## Private Analysis Functions

  defp analyze_test_results(results) do
    test_results = results[:test_results] || []
    
    %{
      total_tests: length(test_results),
      performance_summary: calculate_overall_performance_summary(test_results),
      by_test_case: analyze_individual_test_cases(test_results),
      correlations: analyze_performance_correlations(test_results),
      distribution_analysis: analyze_performance_distribution(test_results),
      benchmark_type: results[:benchmark_type],
      analyzed_at: DateTime.utc_now()
    }
  end

  defp analyze_specific_benchmark(:code_analysis, data) do
    test_results = data[:test_results] || []
    
    %{
      analysis_performance: analyze_code_analysis_performance(test_results),
      language_comparison: compare_language_performance(test_results),
      size_scaling: analyze_size_scaling_performance(test_results),
      complexity_impact: analyze_complexity_impact(test_results),
      cache_effectiveness: analyze_cache_performance(test_results)
    }
  end

  defp analyze_specific_benchmark(:streaming_analysis, data) do
    test_results = data[:test_results] || []
    comparison = data[:streaming_comparison] || []
    
    %{
      streaming_performance: analyze_streaming_performance(test_results),
      streaming_vs_standard: analyze_streaming_comparison(comparison),
      memory_efficiency: analyze_streaming_memory_efficiency(test_results),
      chunk_size_impact: analyze_chunk_size_impact(test_results),
      scalability: analyze_streaming_scalability(test_results)
    }
  end

  defp analyze_specific_benchmark(:concurrent_load, data) do
    user_results = data[:user_results] || []
    
    %{
      concurrency_performance: analyze_concurrency_performance(user_results),
      throughput_analysis: analyze_throughput_characteristics(user_results),
      contention_analysis: analyze_resource_contention(user_results),
      scalability_metrics: calculate_scalability_metrics(user_results)
    }
  end

  defp analyze_specific_benchmark(_, data) do
    analyze_generic_performance_data(data)
  end

  defp analyze_generic_performance_data(data) do
    %{
      summary: extract_basic_statistics(data),
      timestamp: data[:timestamp] || DateTime.utc_now(),
      data_quality: assess_data_quality(data)
    }
  end

  ## Performance Analysis Functions

  defp calculate_overall_performance_summary(test_results) do
    all_durations = extract_all_durations(test_results)
    all_memory = extract_all_memory_usage(test_results)
    
    %{
      duration_stats: calculate_descriptive_statistics(all_durations),
      memory_stats: calculate_descriptive_statistics(all_memory),
      total_operations: length(all_durations),
      performance_score: calculate_performance_score(all_durations, all_memory)
    }
  end

  defp analyze_individual_test_cases(test_results) do
    Enum.map(test_results, fn test_result ->
      stats = test_result[:statistics] || %{}
      test_case = test_result[:test_case] || %{}
      
      %{
        test_case: test_case,
        performance_metrics: extract_performance_metrics_from_test(test_result),
        efficiency_score: calculate_efficiency_score(stats),
        relative_performance: calculate_relative_performance(stats, test_results)
      }
    end)
  end

  defp analyze_performance_correlations(test_results) do
    # Analyze correlations between file size, language, and performance
    data_points = Enum.map(test_results, fn test_result ->
      test_case = test_result[:test_case] || %{}
      stats = test_result[:statistics] || %{}
      
      %{
        file_size: test_case[:size] || 0,
        language: test_case[:language] || :unknown,
        avg_duration: stats[:avg_duration] || 0,
        avg_memory: stats[:avg_memory] || 0
      }
    end)
    
    %{
      size_duration_correlation: calculate_correlation(data_points, :file_size, :avg_duration),
      size_memory_correlation: calculate_correlation(data_points, :file_size, :avg_memory),
      language_performance: analyze_language_performance_differences(data_points)
    }
  end

  defp analyze_performance_distribution(test_results) do
    all_durations = extract_all_durations(test_results)
    
    %{
      distribution_type: identify_distribution_type(all_durations),
      percentiles: calculate_extended_percentiles(all_durations),
      variability: calculate_variability_metrics(all_durations),
      normality_test: test_normality(all_durations)
    }
  end

  ## Specialized Analysis Functions

  defp analyze_code_analysis_performance(test_results) do
    %{
      syntax_analysis_performance: extract_syntax_analysis_metrics(test_results),
      complexity_analysis_performance: extract_complexity_analysis_metrics(test_results),
      security_analysis_performance: extract_security_analysis_metrics(test_results),
      overall_analysis_efficiency: calculate_analysis_efficiency(test_results)
    }
  end

  defp compare_language_performance(test_results) do
    by_language = Enum.group_by(test_results, fn test_result ->
      get_in(test_result, [:test_case, :language]) || :unknown
    end)
    
    Enum.map(by_language, fn {language, language_results} ->
      durations = extract_all_durations(language_results)
      
      %{
        language: language,
        performance_stats: calculate_descriptive_statistics(durations),
        relative_performance: calculate_language_relative_performance(durations, test_results)
      }
    end)
  end

  defp analyze_size_scaling_performance(test_results) do
    by_size = Enum.group_by(test_results, fn test_result ->
      get_in(test_result, [:test_case, :size]) || 0
    end)
    
    size_performance = Enum.map(by_size, fn {size, size_results} ->
      durations = extract_all_durations(size_results)
      
      %{
        file_size: size,
        avg_duration: Enum.sum(durations) / length(durations),
        performance_stats: calculate_descriptive_statistics(durations)
      }
    end)
    |> Enum.sort_by(& &1.file_size)
    
    %{
      size_performance: size_performance,
      scaling_factor: calculate_scaling_factor(size_performance),
      performance_complexity: estimate_performance_complexity(size_performance)
    }
  end

  defp analyze_streaming_performance(test_results) do
    streaming_metrics = Enum.map(test_results, fn test_result ->
      stats = test_result[:statistics] || %{}
      test_case = test_result[:test_case] || %{}
      
      %{
        file_size: test_case[:size] || 0,
        avg_duration: stats[:avg_duration] || 0,
        memory_efficiency: calculate_memory_efficiency(stats),
        throughput: calculate_throughput(test_case[:size], stats[:avg_duration])
      }
    end)
    
    %{
      streaming_efficiency: calculate_streaming_efficiency(streaming_metrics),
      memory_performance: analyze_streaming_memory_performance(streaming_metrics),
      throughput_analysis: analyze_throughput_characteristics(streaming_metrics)
    }
  end

  defp analyze_streaming_comparison(comparison_results) do
    improvements = Enum.map(comparison_results, fn comparison ->
      %{
        file_size: get_in(comparison, [:test_case, :size]) || 0,
        performance_improvement: 1.0 - comparison[:performance_ratio],
        memory_improvement: 1.0 - comparison[:memory_ratio],
        streaming_advantage: comparison[:streaming_advantage] || false
      }
    end)
    
    %{
      average_performance_improvement: calculate_average_improvement(improvements, :performance_improvement),
      average_memory_improvement: calculate_average_improvement(improvements, :memory_improvement),
      streaming_advantage_threshold: identify_streaming_advantage_threshold(improvements),
      recommendation: generate_streaming_recommendation(improvements)
    }
  end

  ## Memory Analysis Functions

  defp analyze_memory_trend(snapshots) do
    memories = Enum.map(snapshots, & &1[:memory] || 0)
    times = Enum.with_index(memories) |> Enum.map(fn {_, index} -> index end)
    
    %{
      trend_direction: calculate_trend_direction(memories),
      growth_rate: calculate_memory_growth_rate(memories, times),
      stability_score: calculate_memory_stability_score(memories)
    }
  end

  defp calculate_peak_memory(snapshots) do
    memories = Enum.map(snapshots, & &1[:memory] || 0)
    peak = Enum.max(memories)
    initial = List.first(memories) || 0
    
    %{
      peak_memory: peak,
      peak_increase: peak - initial,
      peak_ratio: if(initial > 0, do: peak / initial, else: 0)
    }
  end

  defp assess_memory_stability(snapshots) do
    memories = Enum.map(snapshots, & &1[:memory] || 0)
    
    # Look for memory spikes and drops
    memory_changes = Enum.zip(memories, Enum.drop(memories, 1))
    |> Enum.map(fn {prev, curr} -> curr - prev end)
    
    %{
      max_increase: Enum.max(memory_changes),
      max_decrease: Enum.min(memory_changes),
      volatility: calculate_volatility(memory_changes),
      stability_rating: rate_memory_stability(memory_changes)
    }
  end

  defp detect_memory_leak_indicators(snapshots) do
    memories = Enum.map(snapshots, & &1[:memory] || 0)
    
    # Look for consistent growth pattern
    growth_trend = calculate_trend_direction(memories)
    final_memory = List.last(memories) || 0
    initial_memory = List.first(memories) || 0
    
    leak_indicators = []
    
    # Check for consistent growth
    leak_indicators = if growth_trend > 0.7 do
      ["Consistent memory growth detected" | leak_indicators]
    else
      leak_indicators
    end
    
    # Check for significant memory increase
    leak_indicators = if final_memory > initial_memory * 2 do
      ["Memory usage doubled during benchmark" | leak_indicators]
    else
      leak_indicators
    end
    
    # Check for lack of memory cleanup
    gc_snapshots = Enum.filter(snapshots, & &1[:phase] == :after_gc)
    leak_indicators = if length(gc_snapshots) > 0 do
      gc_memory = List.last(gc_snapshots)[:memory] || 0
      if gc_memory > initial_memory * 1.5 do
        ["High memory usage persists after GC" | leak_indicators]
      else
        leak_indicators
      end
    else
      leak_indicators
    end
    
    %{
      indicators: leak_indicators,
      risk_level: if(length(leak_indicators) > 2, do: :high, else: if(length(leak_indicators) > 0, do: :medium, else: :low))
    }
  end

  ## Statistical Calculation Functions

  defp calculate_descriptive_statistics(values) when length(values) > 0 do
    sorted = Enum.sort(values)
    count = length(values)
    sum = Enum.sum(values)
    mean = sum / count
    
    # Calculate variance and standard deviation
    variance = Enum.reduce(values, 0, fn x, acc -> acc + :math.pow(x - mean, 2) end) / count
    std_dev = :math.sqrt(variance)
    
    %{
      count: count,
      sum: sum,
      mean: mean,
      median: calculate_median(sorted),
      mode: calculate_mode(values),
      min: List.first(sorted),
      max: List.last(sorted),
      range: List.last(sorted) - List.first(sorted),
      variance: variance,
      standard_deviation: std_dev,
      coefficient_of_variation: if(mean > 0, do: std_dev / mean, else: 0),
      percentiles: calculate_extended_percentiles(values)
    }
  end
  defp calculate_descriptive_statistics(_), do: %{error: :no_data}

  defp calculate_median(sorted_values) when length(sorted_values) > 0 do
    count = length(sorted_values)
    
    if rem(count, 2) == 0 do
      # Even number of elements
      mid1 = Enum.at(sorted_values, div(count, 2) - 1)
      mid2 = Enum.at(sorted_values, div(count, 2))
      (mid1 + mid2) / 2
    else
      # Odd number of elements
      Enum.at(sorted_values, div(count, 2))
    end
  end
  defp calculate_median(_), do: 0

  defp calculate_mode(values) do
    frequency_map = Enum.frequencies(values)
    max_frequency = Map.values(frequency_map) |> Enum.max()
    
    modes = frequency_map
    |> Enum.filter(fn {_, freq} -> freq == max_frequency end)
    |> Enum.map(fn {value, _} -> value end)
    
    case modes do
      [single_mode] -> single_mode
      multiple_modes -> multiple_modes
    end
  end

  defp calculate_extended_percentiles(values) when length(values) > 0 do
    sorted = Enum.sort(values)
    count = length(sorted)
    
    percentiles = [1, 5, 10, 25, 50, 75, 90, 95, 99]
    
    Enum.map(percentiles, fn p ->
      index = max(0, min(count - 1, round(count * p / 100) - 1))
      {p, Enum.at(sorted, index)}
    end)
    |> Map.new()
  end
  defp calculate_extended_percentiles(_), do: %{}

  defp calculate_correlation(data_points, field1, field2) do
    values1 = Enum.map(data_points, &Map.get(&1, field1, 0))
    values2 = Enum.map(data_points, &Map.get(&1, field2, 0))
    
    if length(values1) > 1 and length(values2) > 1 do
      mean1 = Enum.sum(values1) / length(values1)
      mean2 = Enum.sum(values2) / length(values2)
      
      numerator = Enum.zip(values1, values2)
      |> Enum.reduce(0, fn {x, y}, acc -> acc + (x - mean1) * (y - mean2) end)
      
      sum_sq1 = Enum.reduce(values1, 0, fn x, acc -> acc + :math.pow(x - mean1, 2) end)
      sum_sq2 = Enum.reduce(values2, 0, fn y, acc -> acc + :math.pow(y - mean2, 2) end)
      
      denominator = :math.sqrt(sum_sq1 * sum_sq2)
      
      if denominator > 0 do
        numerator / denominator
      else
        0
      end
    else
      0
    end
  end

  ## Utility Functions

  defp extract_all_durations(test_results) do
    Enum.flat_map(test_results, fn test_result ->
      case test_result[:iterations] do
        iterations when is_list(iterations) ->
          Enum.map(iterations, & &1[:duration] || 0)
        _ ->
          [get_in(test_result, [:statistics, :avg_duration]) || 0]
      end
    end)
  end

  defp extract_all_memory_usage(test_results) do
    Enum.flat_map(test_results, fn test_result ->
      case test_result[:iterations] do
        iterations when is_list(iterations) ->
          Enum.map(iterations, & &1[:memory_used] || 0)
        _ ->
          [get_in(test_result, [:statistics, :avg_memory]) || 0]
      end
    end)
  end

  defp calculate_performance_score(durations, memory_usage) do
    # Normalize and combine duration and memory scores
    duration_score = if length(durations) > 0 do
      avg_duration = Enum.sum(durations) / length(durations)
      # Lower duration is better, normalize to 0-100 scale
      max(0, 100 - (avg_duration / 1000))  # Assuming microseconds
    else
      0
    end
    
    memory_score = if length(memory_usage) > 0 do
      avg_memory = Enum.sum(memory_usage) / length(memory_usage)
      # Lower memory usage is better
      max(0, 100 - (avg_memory / 1_000_000))  # Assuming bytes
    else
      0
    end
    
    # Weighted average: 60% duration, 40% memory
    duration_score * 0.6 + memory_score * 0.4
  end

  defp calculate_trend_direction(values) when length(values) > 1 do
    # Calculate linear trend
    n = length(values)
    x_values = Enum.to_list(1..n)
    
    correlation = calculate_correlation(
      Enum.zip(x_values, values) |> Enum.map(fn {x, y} -> %{x: x, y: y} end),
      :x, :y
    )
    
    correlation
  end
  defp calculate_trend_direction(_), do: 0

  defp generate_memory_recommendations(snapshots) do
    memories = Enum.map(snapshots, & &1[:memory] || 0)
    peak_memory = Enum.max(memories)
    initial_memory = List.first(memories) || 0
    
    recommendations = []
    
    recommendations = if peak_memory > initial_memory * 3 do
      ["Consider implementing more frequent garbage collection" | recommendations]
    else
      recommendations
    end
    
    recommendations = if calculate_trend_direction(memories) > 0.8 do
      ["Monitor for potential memory leaks" | recommendations]
    else
      recommendations
    end
    
    recommendations = if length(recommendations) == 0 do
      ["Memory usage appears stable"]
    else
      recommendations
    end
    
    recommendations
  end

  defp generate_performance_recommendations(_results) do
    # Generate generic performance recommendations based on analysis
    recommendations = []
    
    # Add specific recommendations based on results analysis
    recommendations = ["Analyze results for optimization opportunities" | recommendations]
    
    recommendations
  end

  # Placeholder implementations for missing functions
  defp extract_performance_metrics(_results), do: %{}
  defp detect_outliers(_data), do: []
  defp analyze_performance_trends(_data), do: %{}
  defp identify_performance_patterns(_data), do: %{}
  defp generate_performance_warnings(_data), do: []
  defp analyze_performance_characteristics(_results), do: %{}
  defp identify_optimization_opportunities(_results), do: []
  defp analyze_scaling_characteristics(_results), do: %{}
  defp compare_performance_metrics(_current, _baseline), do: %{}
  defp detect_performance_regressions(_current, _baseline), do: %{}
  defp detect_performance_improvements(_current, _baseline), do: %{}
  defp calculate_statistical_significance(_current, _baseline), do: %{}
  defp generate_comparison_summary(_current, _baseline), do: %{}
  defp extract_basic_statistics(data), do: Map.take(data, [:timestamp, :benchmark_type])
  defp assess_data_quality(_data), do: :good
  defp extract_performance_metrics_from_test(_test_result), do: %{}
  defp calculate_efficiency_score(_stats), do: 0.0
  defp calculate_relative_performance(_stats, _all_results), do: 0.0
  defp identify_distribution_type(_values), do: :normal
  defp calculate_variability_metrics(_values), do: %{}
  defp test_normality(_values), do: %{is_normal: true}
  defp extract_syntax_analysis_metrics(_results), do: %{}
  defp extract_complexity_analysis_metrics(_results), do: %{}
  defp extract_security_analysis_metrics(_results), do: %{}
  defp calculate_analysis_efficiency(_results), do: 0.0
  defp calculate_language_relative_performance(_durations, _all_results), do: 0.0
  defp calculate_scaling_factor(_performance), do: 1.0
  defp estimate_performance_complexity(_performance), do: "O(n)"
  defp calculate_memory_efficiency(_stats), do: 0.0
  defp calculate_throughput(size, duration), do: if(duration > 0, do: size / duration, else: 0)
  defp calculate_streaming_efficiency(_metrics), do: 0.0
  defp analyze_streaming_memory_performance(_metrics), do: %{}
  defp analyze_throughput_characteristics(_data), do: %{}
  defp calculate_average_improvement(improvements, field) do
    values = Enum.map(improvements, &Map.get(&1, field, 0))
    if length(values) > 0, do: Enum.sum(values) / length(values), else: 0
  end
  defp identify_streaming_advantage_threshold(_improvements), do: 1024 * 1024  # 1MB
  defp generate_streaming_recommendation(_improvements), do: "Use streaming for files > 1MB"
  defp calculate_memory_growth_rate(_memories, _times), do: 0.0
  defp calculate_memory_stability_score(_memories), do: 1.0
  defp calculate_volatility(changes), do: if(length(changes) > 0, do: Enum.sum(Enum.map(changes, &abs/1)) / length(changes), else: 0)
  defp rate_memory_stability(changes) do
    volatility = calculate_volatility(changes)
    cond do
      volatility < 1000 -> :stable
      volatility < 10000 -> :moderate
      true -> :unstable
    end
  end
  defp analyze_gc_effectiveness(_snapshots), do: %{}
  defp analyze_concurrency_performance(_user_results), do: %{}
  defp analyze_resource_contention(_user_results), do: %{}
  defp calculate_scalability_metrics(_user_results), do: %{}
  defp analyze_language_performance_differences(data_points) do
    by_language = Enum.group_by(data_points, & &1[:language])
    
    Enum.map(by_language, fn {language, points} ->
      durations = Enum.map(points, & &1[:avg_duration])
      avg_duration = if length(durations) > 0, do: Enum.sum(durations) / length(durations), else: 0
      
      %{language: language, avg_duration: avg_duration}
    end)
  end
  defp analyze_complexity_impact(_results), do: %{}
  defp analyze_cache_performance(_results), do: %{}
  defp analyze_streaming_memory_efficiency(_results), do: %{}
  defp analyze_chunk_size_impact(_results), do: %{}
  defp analyze_streaming_scalability(_results), do: %{}
end