defmodule RubberDuck.Enhancement.MetricsCollector do
  @moduledoc """
  Collects and aggregates metrics from enhancement techniques.
  
  Provides unified metrics collection across all enhancement techniques
  with support for custom metrics and aggregation strategies.
  """
  
  require Logger
  
  @type metric_value :: number() | String.t() | boolean() | map()
  @type metrics :: %{String.t() => metric_value()}
  
  @doc """
  Collects metrics from an enhancement result.
  
  Aggregates metrics from all applied techniques and calculates
  overall quality improvements.
  """
  @spec collect(map(), [atom()]) :: metrics()
  def collect(result, techniques_applied) do
    base_metrics = collect_base_metrics(result)
    technique_metrics = collect_technique_metrics(result, techniques_applied)
    quality_metrics = calculate_quality_metrics(result)
    
    base_metrics
    |> Map.merge(technique_metrics)
    |> Map.merge(quality_metrics)
    |> add_aggregated_metrics()
  end
  
  @doc """
  Aggregates metrics from multiple enhancement runs.
  
  Useful for A/B testing and performance tracking.
  """
  @spec aggregate([metrics()]) :: metrics()
  def aggregate(metrics_list) when is_list(metrics_list) do
    if Enum.empty?(metrics_list) do
      %{}
    else
      %{
        count: length(metrics_list),
        averages: calculate_averages(metrics_list),
        totals: calculate_totals(metrics_list),
        distributions: calculate_distributions(metrics_list),
        success_rate: calculate_success_rate(metrics_list)
      }
    end
  end
  
  @doc """
  Formats metrics for reporting.
  """
  @spec format_metrics(metrics()) :: String.t()
  def format_metrics(metrics) do
    metrics
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map(fn {key, value} -> format_metric(key, value) end)
    |> Enum.join("\n")
  end
  
  @doc """
  Exports metrics in a structured format.
  """
  @spec export(metrics(), :json | :csv | :prometheus) :: String.t()
  def export(metrics, :json) do
    Jason.encode!(metrics, pretty: true)
  end
  
  def export(metrics, :csv) do
    headers = Map.keys(metrics) |> Enum.sort() |> Enum.join(",")
    values = headers 
    |> String.split(",") 
    |> Enum.map(fn h -> Map.get(metrics, h, "") |> to_string() end)
    |> Enum.join(",")
    
    "#{headers}\n#{values}"
  end
  
  def export(metrics, :prometheus) do
    metrics
    |> Enum.map(fn {key, value} -> 
      prometheus_format(key, value)
    end)
    |> Enum.join("\n")
  end
  
  # Private functions
  
  defp collect_base_metrics(result) do
    %{
      "execution_time_ms" => Map.get(result, :duration_ms, 0),
      "content_length_original" => String.length(Map.get(result, :original, "")),
      "content_length_enhanced" => String.length(Map.get(result, :enhanced, "")),
      "techniques_count" => length(Map.get(result, :techniques_applied, [])),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end
  
  defp collect_technique_metrics(result, techniques_applied) do
    techniques_applied
    |> Enum.reduce(%{}, fn technique, acc ->
      technique_metrics = extract_technique_metrics(result, technique)
      Map.merge(acc, technique_metrics)
    end)
  end
  
  defp extract_technique_metrics(result, :cot) do
    context = Map.get(result, :context, %{})
    cot_chain = Map.get(context, :cot_chain, %{})
    
    %{
      "cot_steps_count" => length(Map.get(cot_chain, :steps, [])),
      "cot_reasoning_depth" => Map.get(cot_chain, :depth, 0),
      "cot_validation_passed" => Map.get(cot_chain, :valid, false)
    }
  end
  
  defp extract_technique_metrics(result, :rag) do
    context = Map.get(result, :context, %{})
    rag_sources = Map.get(context, :rag_sources, [])
    
    %{
      "rag_sources_count" => length(rag_sources),
      "rag_avg_relevance" => calculate_avg_relevance(rag_sources),
      "rag_retrieval_time_ms" => Map.get(context, :rag_retrieval_time, 0)
    }
  end
  
  defp extract_technique_metrics(result, :self_correction) do
    context = Map.get(result, :context, %{})
    corrections = Map.get(context, :corrections_applied, [])
    
    %{
      "self_correction_iterations" => Map.get(result, :iterations, 1),
      "self_correction_changes" => length(corrections),
      "self_correction_converged" => Map.get(context, :converged, false)
    }
  end
  
  defp extract_technique_metrics(_result, _technique), do: %{}
  
  defp calculate_quality_metrics(result) do
    original = Map.get(result, :original, "")
    enhanced = Map.get(result, :enhanced, "")
    
    %{
      "quality_improvement" => calculate_improvement_score(original, enhanced),
      "readability_score" => calculate_readability(enhanced),
      "completeness_score" => calculate_completeness(enhanced, result.context),
      "consistency_score" => calculate_consistency(enhanced)
    }
  end
  
  defp calculate_improvement_score(original, enhanced) do
    # Simple heuristic - in production, use more sophisticated metrics
    if String.length(enhanced) == 0 do
      0.0
    else
      length_ratio = String.length(enhanced) / max(String.length(original), 1)
      
      # Check for specific improvements
      improvements = [
        {has_better_structure?(original, enhanced), 0.2},
        {has_better_documentation?(original, enhanced), 0.15},
        {has_fewer_errors?(original, enhanced), 0.25},
        {has_better_naming?(original, enhanced), 0.1}
      ]
      
      base_score = Enum.reduce(improvements, 0.3, fn {condition, weight}, acc ->
        if condition, do: acc + weight, else: acc
      end)
      
      # Normalize based on length change
      if length_ratio > 2.0 do
        base_score * 0.8  # Penalty for excessive expansion
      else
        base_score
      end
    end
  end
  
  defp has_better_structure?(original, enhanced) do
    # Check for improved code structure
    String.split(enhanced, "\n") |> length() > String.split(original, "\n") |> length()
  end
  
  defp has_better_documentation?(original, enhanced) do
    # Check for documentation improvements
    doc_patterns = [~r/@doc/, ~r/"""/, ~r/##/, ~r/@moduledoc/]
    
    original_docs = count_pattern_matches(original, doc_patterns)
    enhanced_docs = count_pattern_matches(enhanced, doc_patterns)
    
    enhanced_docs > original_docs
  end
  
  defp has_fewer_errors?(original, enhanced) do
    error_patterns = [~r/error/i, ~r/bug/i, ~r/TODO/i, ~r/FIXME/i]
    
    original_errors = count_pattern_matches(original, error_patterns)
    enhanced_errors = count_pattern_matches(enhanced, error_patterns)
    
    enhanced_errors < original_errors
  end
  
  defp has_better_naming?(original, enhanced) do
    # Check for improved variable/function naming
    bad_names = [~r/\bx\b/, ~r/\btemp\b/, ~r/\bdata\b/, ~r/\bvar\d+\b/]
    
    original_bad = count_pattern_matches(original, bad_names)
    enhanced_bad = count_pattern_matches(enhanced, bad_names)
    
    enhanced_bad < original_bad
  end
  
  defp count_pattern_matches(text, patterns) do
    Enum.sum(Enum.map(patterns, fn pattern ->
      Regex.scan(pattern, text) |> length()
    end))
  end
  
  defp calculate_readability(content) do
    sentences = String.split(content, ~r/[.!?]+/)
    words = String.split(content, ~r/\s+/)
    
    if length(sentences) > 0 && length(words) > 0 do
      avg_sentence_length = length(words) / length(sentences)
      
      # Simple readability score
      cond do
        avg_sentence_length < 10 -> 0.7
        avg_sentence_length < 20 -> 0.9
        avg_sentence_length < 30 -> 0.6
        true -> 0.3
      end
    else
      0.5
    end
  end
  
  defp calculate_completeness(content, context) do
    # Check if content addresses the original task
    required_elements = Map.get(context, :required_elements, [])
    
    if Enum.empty?(required_elements) do
      # Default completeness based on content structure
      if String.length(content) > 100 && String.contains?(content, "\n") do
        0.8
      else
        0.5
      end
    else
      found_elements = Enum.count(required_elements, fn element ->
        String.contains?(content, element)
      end)
      
      found_elements / length(required_elements)
    end
  end
  
  defp calculate_consistency(content) do
    # Check for consistency in style and naming
    lines = String.split(content, "\n")
    
    # Check indentation consistency
    indentations = lines
    |> Enum.map(&count_leading_spaces/1)
    |> Enum.filter(&(&1 > 0))
    |> Enum.uniq()
    
    indent_score = if length(indentations) <= 3, do: 0.9, else: 0.6
    
    # Check naming consistency (simplified)
    naming_score = if has_consistent_naming?(content), do: 0.9, else: 0.7
    
    (indent_score + naming_score) / 2
  end
  
  defp count_leading_spaces(line) do
    String.length(line) - String.length(String.trim_leading(line))
  end
  
  defp has_consistent_naming?(content) do
    # Simple check - in production, use more sophisticated analysis
    !String.contains?(content, ["camelCase", "snake_case"]) ||
    (!String.contains?(content, "camelCase") || !String.contains?(content, "snake_case"))
  end
  
  defp calculate_avg_relevance(sources) do
    if Enum.empty?(sources) do
      0.0
    else
      scores = Enum.map(sources, fn source ->
        Map.get(source, :relevance_score, 0.5)
      end)
      
      Enum.sum(scores) / length(scores)
    end
  end
  
  defp add_aggregated_metrics(metrics) do
    # Add computed aggregate metrics
    Map.put(metrics, "overall_success", calculate_overall_success(metrics))
  end
  
  defp calculate_overall_success(metrics) do
    quality = Map.get(metrics, "quality_improvement", 0)
    readability = Map.get(metrics, "readability_score", 0)
    completeness = Map.get(metrics, "completeness_score", 0)
    
    (quality + readability + completeness) / 3 > 0.6
  end
  
  defp calculate_averages(metrics_list) do
    numeric_keys = metrics_list
    |> List.first(%{})
    |> Enum.filter(fn {_k, v} -> is_number(v) end)
    |> Enum.map(fn {k, _v} -> k end)
    
    Enum.reduce(numeric_keys, %{}, fn key, acc ->
      values = Enum.map(metrics_list, &Map.get(&1, key, 0))
      avg = Enum.sum(values) / length(values)
      Map.put(acc, key, avg)
    end)
  end
  
  defp calculate_totals(metrics_list) do
    numeric_keys = metrics_list
    |> List.first(%{})
    |> Enum.filter(fn {_k, v} -> is_number(v) end)
    |> Enum.map(fn {k, _v} -> k end)
    
    Enum.reduce(numeric_keys, %{}, fn key, acc ->
      values = Enum.map(metrics_list, &Map.get(&1, key, 0))
      Map.put(acc, key, Enum.sum(values))
    end)
  end
  
  defp calculate_distributions(metrics_list) do
    # Calculate distributions for key metrics
    %{
      "quality_improvement" => calculate_distribution(metrics_list, "quality_improvement"),
      "execution_time_ms" => calculate_distribution(metrics_list, "execution_time_ms")
    }
  end
  
  defp calculate_distribution(metrics_list, key) do
    values = Enum.map(metrics_list, &Map.get(&1, key, 0))
    
    if Enum.empty?(values) do
      %{}
    else
      %{
        min: Enum.min(values),
        max: Enum.max(values),
        median: calculate_median(values),
        p95: calculate_percentile(values, 0.95)
      }
    end
  end
  
  defp calculate_median(values) do
    sorted = Enum.sort(values)
    mid = div(length(sorted), 2)
    
    if rem(length(sorted), 2) == 0 do
      (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
    else
      Enum.at(sorted, mid)
    end
  end
  
  defp calculate_percentile(values, percentile) do
    sorted = Enum.sort(values)
    index = round(percentile * (length(sorted) - 1))
    Enum.at(sorted, index)
  end
  
  defp calculate_success_rate(metrics_list) do
    successful = Enum.count(metrics_list, &Map.get(&1, "overall_success", false))
    successful / length(metrics_list)
  end
  
  defp format_metric(key, value) when is_float(value) do
    "#{key}: #{Float.round(value, 3)}"
  end
  
  defp format_metric(key, value) when is_boolean(value) do
    "#{key}: #{value}"
  end
  
  defp format_metric(key, value) when is_map(value) do
    "#{key}: #{inspect(value, pretty: true)}"
  end
  
  defp format_metric(key, value) do
    "#{key}: #{value}"
  end
  
  defp prometheus_format(key, value) when is_number(value) do
    metric_name = String.replace(key, ~r/[^a-zA-Z0-9_]/, "_")
    "rubber_duck_enhancement_#{metric_name} #{value}"
  end
  
  defp prometheus_format(key, true) do
    metric_name = String.replace(key, ~r/[^a-zA-Z0-9_]/, "_")
    "rubber_duck_enhancement_#{metric_name} 1"
  end
  
  defp prometheus_format(key, false) do
    metric_name = String.replace(key, ~r/[^a-zA-Z0-9_]/, "_")
    "rubber_duck_enhancement_#{metric_name} 0"
  end
  
  defp prometheus_format(_key, _value), do: ""
end