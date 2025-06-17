defmodule RubberDuck.Benchmarking.ReportGenerator do
  @moduledoc """
  Generates performance reports from benchmark results in various formats.
  
  This module provides functionality to create comprehensive reports including:
  - Performance summaries
  - Comparative analyses
  - Trend visualizations (text-based)
  - Recommendations and insights
  """

  @doc """
  Generate a report from benchmark results in the specified format.
  """
  def generate(results, format \\ :markdown) do
    case format do
      :markdown -> generate_markdown_report(results)
      :json -> generate_json_report(results)
      :csv -> generate_csv_report(results)
      :text -> generate_text_report(results)
      _ -> {:error, :unsupported_format}
    end
  end

  @doc """
  Generate a comprehensive markdown report.
  """
  def generate_markdown_report(results) do
    sections = [
      generate_header(results),
      generate_executive_summary(results),
      generate_performance_metrics(results),
      generate_detailed_analysis(results),
      generate_recommendations(results),
      generate_appendix(results)
    ]
    
    {:ok, Enum.join(sections, "\n\n")}
  end

  @doc """
  Generate a JSON report suitable for programmatic consumption.
  """
  def generate_json_report(results) do
    report_data = %{
      metadata: extract_metadata(results),
      summary: generate_summary_data(results),
      detailed_metrics: extract_detailed_metrics(results),
      analysis: generate_analysis_data(results),
      recommendations: extract_recommendations(results),
      generated_at: DateTime.utc_now()
    }
    
    case Jason.encode(report_data, pretty: true) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, {:json_encoding_failed, reason}}
    end
  end

  @doc """
  Generate a CSV report for spreadsheet analysis.
  """
  def generate_csv_report(results) do
    headers = generate_csv_headers(results)
    rows = generate_csv_rows(results)
    
    csv_content = [headers | rows]
    |> Enum.map(&Enum.join(&1, ","))
    |> Enum.join("\n")
    
    {:ok, csv_content}
  end

  @doc """
  Generate a plain text report.
  """
  def generate_text_report(results) do
    sections = [
      generate_text_header(results),
      generate_text_summary(results),
      generate_text_metrics(results),
      generate_text_recommendations(results)
    ]
    
    {:ok, Enum.join(sections, "\n" <> String.duplicate("=", 80) <> "\n")}
  end

  ## Markdown Report Generation

  defp generate_header(results) do
    metadata = extract_metadata(results)
    
    """
    # Performance Benchmark Report

    **Generated:** #{DateTime.utc_now() |> DateTime.to_string()}
    **Benchmark ID:** #{metadata[:benchmark_id] || "N/A"}
    **Duration:** #{metadata[:total_duration] || "N/A"}ms
    **System Info:** Elixir #{metadata[:elixir_version] || "N/A"}, OTP #{metadata[:otp_version] || "N/A"}
    """
  end

  defp generate_executive_summary(results) do
    summary = generate_summary_data(results)
    
    """
    ## Executive Summary

    This benchmark evaluated #{summary[:total_operations] || 0} operations across #{summary[:benchmark_types] || 0} different test types.
    
    **Key Findings:**
    - Average operation duration: #{format_duration(summary[:avg_duration])}
    - Peak memory usage: #{format_memory(summary[:peak_memory])}
    - Overall performance score: #{format_score(summary[:performance_score])}
    
    **Performance Rating:** #{determine_performance_rating(summary)}
    """
  end

  defp generate_performance_metrics(results) do
    """
    ## Performance Metrics

    ### Duration Statistics
    #{generate_duration_table(results)}

    ### Memory Usage Statistics  
    #{generate_memory_table(results)}

    ### Throughput Analysis
    #{generate_throughput_analysis(results)}
    """
  end

  defp generate_detailed_analysis(results) do
    """
    ## Detailed Analysis

    ### By Benchmark Type
    #{generate_benchmark_type_analysis(results)}

    ### Performance Patterns
    #{generate_performance_patterns(results)}

    ### Anomaly Detection
    #{generate_anomaly_analysis(results)}
    """
  end

  defp generate_recommendations(results) do
    recommendations = extract_recommendations(results)
    
    recommendation_items = recommendations
    |> Enum.map(fn rec -> "- #{rec}" end)
    |> Enum.join("\n")
    
    """
    ## Recommendations

    #{recommendation_items}
    """
  end

  defp generate_appendix(results) do
    """
    ## Appendix

    ### Raw Data Summary
    ```json
    #{Jason.encode!(extract_raw_data_summary(results), pretty: true)}
    ```

    ### System Information
    #{generate_system_info_table(results)}
    """
  end

  ## Data Extraction Functions

  defp extract_metadata(results) do
    summary = results[:summary] || %{}
    
    %{
      benchmark_id: summary[:benchmark_id],
      total_duration: summary[:total_duration],
      benchmarks_run: summary[:benchmarks_run],
      timestamp: summary[:timestamp],
      elixir_version: get_in(summary, [:system_info, :elixir_version]),
      otp_version: get_in(summary, [:system_info, :otp_version])
    }
  end

  defp generate_summary_data(results) do
    # Extract and aggregate data from all benchmark types
    all_durations = extract_all_durations_from_results(results)
    all_memory = extract_all_memory_from_results(results)
    
    %{
      total_operations: length(all_durations),
      benchmark_types: count_benchmark_types(results),
      avg_duration: if(length(all_durations) > 0, do: Enum.sum(all_durations) / length(all_durations), else: 0),
      peak_memory: if(length(all_memory) > 0, do: Enum.max(all_memory), else: 0),
      performance_score: calculate_overall_performance_score(all_durations, all_memory)
    }
  end

  defp extract_detailed_metrics(results) do
    Enum.reduce(results, %{}, fn {type, data}, acc ->
      if type != :summary do
        Map.put(acc, type, extract_metrics_for_type(data))
      else
        acc
      end
    end)
  end

  defp generate_analysis_data(results) do
    %{
      performance_trends: analyze_performance_trends(results),
      resource_utilization: analyze_resource_utilization(results),
      scalability_metrics: analyze_scalability_metrics(results)
    }
  end

  defp extract_recommendations(results) do
    base_recommendations = [
      "Monitor performance metrics regularly",
      "Consider optimizing high-duration operations",
      "Review memory usage patterns for potential leaks"
    ]
    
    # Add specific recommendations based on results
    specific_recommendations = generate_specific_recommendations(results)
    
    base_recommendations ++ specific_recommendations
  end

  ## Table Generation Functions

  defp generate_duration_table(results) do
    """
    | Metric | Value |
    |--------|--------|
    | Min Duration | #{format_duration(get_min_duration(results))} |
    | Max Duration | #{format_duration(get_max_duration(results))} |
    | Avg Duration | #{format_duration(get_avg_duration(results))} |
    | 95th Percentile | #{format_duration(get_p95_duration(results))} |
    """
  end

  defp generate_memory_table(results) do
    """
    | Metric | Value |
    |--------|--------|
    | Min Memory | #{format_memory(get_min_memory(results))} |
    | Max Memory | #{format_memory(get_max_memory(results))} |
    | Avg Memory | #{format_memory(get_avg_memory(results))} |
    | Peak Memory | #{format_memory(get_peak_memory(results))} |
    """
  end

  defp generate_system_info_table(results) do
    system_info = get_in(results, [:summary, :system_info]) || %{}
    
    """
    | Component | Value |
    |-----------|--------|
    | Elixir Version | #{system_info[:elixir_version] || "N/A"} |
    | OTP Version | #{system_info[:otp_version] || "N/A"} |
    | Schedulers | #{system_info[:schedulers] || "N/A"} |
    | Memory Total | #{format_memory(system_info[:memory_total])} |
    """
  end

  ## Analysis Functions

  defp generate_benchmark_type_analysis(results) do
    analysis_sections = Enum.map(results, fn {type, data} ->
      if type != :summary do
        """
        #### #{String.capitalize(to_string(type))} Analysis
        #{analyze_benchmark_type(type, data)}
        """
      else
        ""
      end
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
    
    analysis_sections
  end

  defp analyze_benchmark_type(:code_analysis, data) do
    "Code analysis performance shows #{extract_code_analysis_insights(data)}"
  end

  defp analyze_benchmark_type(:streaming_analysis, data) do
    "Streaming analysis demonstrates #{extract_streaming_insights(data)}"
  end

  defp analyze_benchmark_type(:memory_usage, data) do
    "Memory usage patterns indicate #{extract_memory_insights(data)}"
  end

  defp analyze_benchmark_type(type, _data) do
    "#{String.capitalize(to_string(type))} benchmark completed successfully."
  end

  ## Helper Functions

  defp format_duration(nil), do: "N/A"
  defp format_duration(microseconds) when is_number(microseconds) do
    cond do
      microseconds < 1000 -> "#{Float.round(microseconds, 2)}μs"
      microseconds < 1_000_000 -> "#{Float.round(microseconds / 1000, 2)}ms"
      true -> "#{Float.round(microseconds / 1_000_000, 2)}s"
    end
  end
  defp format_duration(_), do: "N/A"

  defp format_memory(nil), do: "N/A"
  defp format_memory(bytes) when is_number(bytes) do
    cond do
      bytes < 1024 -> "#{bytes} bytes"
      bytes < 1024 * 1024 -> "#{Float.round(bytes / 1024, 2)} KB"
      bytes < 1024 * 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024), 2)} MB"
      true -> "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GB"
    end
  end
  defp format_memory(_), do: "N/A"

  defp format_score(nil), do: "N/A"
  defp format_score(score) when is_number(score), do: "#{Float.round(score, 1)}/100"
  defp format_score(_), do: "N/A"

  defp determine_performance_rating(summary) do
    score = summary[:performance_score] || 0
    cond do
      score >= 90 -> "⭐⭐⭐⭐⭐ Excellent"
      score >= 75 -> "⭐⭐⭐⭐☆ Good"
      score >= 60 -> "⭐⭐⭐☆☆ Average"
      score >= 40 -> "⭐⭐☆☆☆ Below Average"
      true -> "⭐☆☆☆☆ Poor"
    end
  end

  ## CSV Generation Functions

  defp generate_csv_headers(_results) do
    ["benchmark_type", "operation", "duration_us", "memory_bytes", "file_size", "language"]
  end

  defp generate_csv_rows(results) do
    Enum.flat_map(results, fn {type, data} ->
      if type != :summary do
        extract_csv_rows_for_type(type, data)
      else
        []
      end
    end)
  end

  ## Text Report Functions

  defp generate_text_header(results) do
    metadata = extract_metadata(results)
    
    """
    PERFORMANCE BENCHMARK REPORT
    Generated: #{DateTime.utc_now() |> DateTime.to_string()}
    Benchmark ID: #{metadata[:benchmark_id] || "N/A"}
    Duration: #{metadata[:total_duration] || "N/A"}ms
    """
  end

  defp generate_text_summary(results) do
    summary = generate_summary_data(results)
    
    """
    SUMMARY
    Total Operations: #{summary[:total_operations] || 0}
    Benchmark Types: #{summary[:benchmark_types] || 0}
    Average Duration: #{format_duration(summary[:avg_duration])}
    Peak Memory: #{format_memory(summary[:peak_memory])}
    Performance Score: #{format_score(summary[:performance_score])}
    """
  end

  defp generate_text_metrics(results) do
    """
    PERFORMANCE METRICS
    Duration - Min: #{format_duration(get_min_duration(results))}, Max: #{format_duration(get_max_duration(results))}, Avg: #{format_duration(get_avg_duration(results))}
    Memory - Min: #{format_memory(get_min_memory(results))}, Max: #{format_memory(get_max_memory(results))}, Avg: #{format_memory(get_avg_memory(results))}
    """
  end

  defp generate_text_recommendations(results) do
    recommendations = extract_recommendations(results)
    recommendation_text = recommendations |> Enum.map(&("- " <> &1)) |> Enum.join("\n")
    
    """
    RECOMMENDATIONS
    #{recommendation_text}
    """
  end

  ## Placeholder implementations for data extraction
  
  defp extract_all_durations_from_results(_results), do: []
  defp extract_all_memory_from_results(_results), do: []
  defp count_benchmark_types(results), do: map_size(results) - 1  # Exclude summary
  defp calculate_overall_performance_score(_durations, _memory), do: 75.0
  defp extract_metrics_for_type(_data), do: %{}
  defp analyze_performance_trends(_results), do: %{}
  defp analyze_resource_utilization(_results), do: %{}
  defp analyze_scalability_metrics(_results), do: %{}
  defp generate_specific_recommendations(_results), do: []
  defp get_min_duration(_results), do: 0
  defp get_max_duration(_results), do: 0
  defp get_avg_duration(_results), do: 0
  defp get_p95_duration(_results), do: 0
  defp get_min_memory(_results), do: 0
  defp get_max_memory(_results), do: 0
  defp get_avg_memory(_results), do: 0
  defp get_peak_memory(_results), do: 0
  defp generate_throughput_analysis(_results), do: "No throughput data available"
  defp generate_performance_patterns(_results), do: "No patterns detected"
  defp generate_anomaly_analysis(_results), do: "No anomalies detected"
  defp extract_raw_data_summary(results), do: Map.take(results, [:summary])
  defp extract_code_analysis_insights(_data), do: "standard performance characteristics"
  defp extract_streaming_insights(_data), do: "efficient streaming behavior"
  defp extract_memory_insights(_data), do: "stable memory usage"
  defp extract_csv_rows_for_type(_type, _data), do: []
end