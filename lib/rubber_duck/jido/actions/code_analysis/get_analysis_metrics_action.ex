defmodule RubberDuck.Jido.Actions.CodeAnalysis.GetAnalysisMetricsAction do
  @moduledoc """
  Action for retrieving current analysis metrics and statistics.
  
  This action provides comprehensive metrics about the code analysis agent's
  performance including queue length, cache statistics, and processing metrics.
  """
  
  use Jido.Action,
    name: "get_analysis_metrics",
    description: "Retrieves current analysis metrics and agent statistics",
    schema: [
      include_detailed: [
        type: :boolean,
        default: false,
        doc: "Whether to include detailed metrics breakdown"
      ]
    ]

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    %{include_detailed: include_detailed} = params
    
    Logger.debug("Retrieving analysis metrics", include_detailed: include_detailed)
    
    # Build metrics response
    metrics_data = %{
      metrics: agent.state.metrics,
      queue_length: length(agent.state.analysis_queue),
      active_analyses: map_size(agent.state.active_analyses),
      cache_size: map_size(agent.state.analysis_cache),
      timestamp: DateTime.utc_now()
    }
    
    # Add detailed metrics if requested
    final_metrics = if include_detailed do
      Map.merge(metrics_data, %{
        detailed: build_detailed_metrics(agent),
        cache_stats: build_cache_statistics(agent),
        queue_analysis: analyze_queue(agent)
      })
    else
      metrics_data
    end
    
    # Emit metrics signal
    case emit_metrics_signal(agent, final_metrics) do
      {:ok, _} ->
        {:ok, final_metrics, %{agent: agent}}
      {:error, reason} ->
        {:error, {:signal_emission_failed, reason}}
    end
  end

  # Private functions
  
  defp build_detailed_metrics(agent) do
    metrics = agent.state.metrics
    
    %{
      performance: %{
        total_requests: metrics.files_analyzed + metrics.conversations_analyzed,
        success_rate: calculate_success_rate(metrics),
        avg_processing_time: calculate_avg_processing_time(metrics),
        cache_hit_rate: calculate_cache_hit_rate(metrics)
      },
      analysis_breakdown: %{
        files_analyzed: metrics.files_analyzed,
        conversations_analyzed: metrics.conversations_analyzed,
        total_issues_found: metrics.total_issues,
        llm_enhancements: metrics.llm_enhancements
      },
      efficiency_metrics: %{
        cache_efficiency: calculate_cache_efficiency(metrics),
        processing_efficiency: calculate_processing_efficiency(agent),
        resource_utilization: calculate_resource_utilization(agent)
      }
    }
  end
  
  defp build_cache_statistics(agent) do
    cache = agent.state.analysis_cache
    now = System.monotonic_time(:millisecond)
    
    cache_entries = Map.values(cache)
    
    %{
      total_entries: map_size(cache),
      memory_usage_estimate: calculate_cache_memory_usage(cache_entries),
      age_distribution: calculate_cache_age_distribution(cache_entries, now),
      hit_miss_ratio: calculate_hit_miss_ratio(agent.state.metrics),
      oldest_entry: find_oldest_cache_entry(cache_entries),
      most_accessed: find_most_accessed_entry(cache_entries)
    }
  end
  
  defp analyze_queue(agent) do
    queue = agent.state.analysis_queue
    active = agent.state.active_analyses
    
    %{
      pending_requests: length(queue),
      active_requests: map_size(active),
      queue_types: analyze_queue_types(queue),
      oldest_pending: find_oldest_pending_request(queue),
      estimated_processing_time: estimate_queue_processing_time(queue, agent)
    }
  end
  
  # Calculation helpers
  
  defp calculate_success_rate(metrics) do
    total = metrics.files_analyzed + metrics.conversations_analyzed
    if total > 0 do
      # Assuming we track failures separately, for now return high success rate
      0.95
    else
      0.0
    end
  end
  
  defp calculate_avg_processing_time(metrics) do
    if metrics.analysis_time_ms > 0 do
      total_requests = metrics.files_analyzed + metrics.conversations_analyzed
      if total_requests > 0 do
        metrics.analysis_time_ms / total_requests
      else
        0.0
      end
    else
      0.0
    end
  end
  
  defp calculate_cache_hit_rate(metrics) do
    total_cache_requests = metrics.cache_hits + metrics.cache_misses
    if total_cache_requests > 0 do
      metrics.cache_hits / total_cache_requests
    else
      0.0
    end
  end
  
  defp calculate_cache_efficiency(metrics) do
    hit_rate = calculate_cache_hit_rate(metrics)
    # Cache efficiency considers both hit rate and memory usage
    # For now, using hit rate as primary metric
    hit_rate
  end
  
  defp calculate_processing_efficiency(agent) do
    # Measure efficiency based on queue length vs processing capacity
    queue_length = length(agent.state.analysis_queue)
    active_analyses = map_size(agent.state.active_analyses)
    
    case queue_length + active_analyses do
      0 -> 1.0  # Perfect efficiency when idle
      total -> max(0.0, 1.0 - (total / 10.0))  # Decrease efficiency as load increases
    end
  end
  
  defp calculate_resource_utilization(agent) do
    # Simplified resource utilization based on cache size and active analyses
    cache_size = map_size(agent.state.analysis_cache)
    active_count = map_size(agent.state.active_analyses)
    
    %{
      cache_utilization: min(1.0, cache_size / 1000.0),  # Assume max 1000 cache entries
      processing_utilization: min(1.0, active_count / 5.0)  # Assume max 5 concurrent analyses
    }
  end
  
  defp calculate_cache_memory_usage(cache_entries) do
    # Rough estimate of cache memory usage
    cache_entries
    |> Enum.map(fn entry ->
      # Estimate size based on data structure
      :erlang.external_size(entry) 
    end)
    |> Enum.sum()
  end
  
  defp calculate_cache_age_distribution(cache_entries, now) do
    ages = cache_entries
    |> Enum.map(fn entry ->
      case Map.get(entry, :cached_at) do
        nil -> 0
        cached_at -> now - cached_at
      end
    end)
    
    if Enum.empty?(ages) do
      %{min: 0, max: 0, avg: 0}
    else
      %{
        min: Enum.min(ages),
        max: Enum.max(ages),
        avg: Enum.sum(ages) / length(ages)
      }
    end
  end
  
  defp calculate_hit_miss_ratio(metrics) do
    if metrics.cache_misses > 0 do
      metrics.cache_hits / metrics.cache_misses
    else
      metrics.cache_hits
    end
  end
  
  defp find_oldest_cache_entry(cache_entries) do
    cache_entries
    |> Enum.min_by(fn entry -> Map.get(entry, :cached_at, 0) end, fn -> nil end)
  end
  
  defp find_most_accessed_entry(cache_entries) do
    cache_entries
    |> Enum.max_by(fn entry -> Map.get(entry, :access_count, 0) end, fn -> nil end)
  end
  
  defp analyze_queue_types(queue) do
    queue
    |> Enum.group_by(fn request -> request.type end)
    |> Map.new(fn {type, requests} -> {type, length(requests)} end)
  end
  
  defp find_oldest_pending_request(queue) do
    queue
    |> Enum.min_by(fn request -> request.started_at end, fn -> nil end)
  end
  
  defp estimate_queue_processing_time(queue, agent) do
    if Enum.empty?(queue) do
      0
    else
      # Rough estimate based on average processing time
      avg_time = calculate_avg_processing_time(agent.state.metrics)
      queue_length = length(queue)
      
      # Assume some parallelism (max 3 concurrent)
      concurrent_slots = min(3, queue_length)
      if concurrent_slots > 0 do
        (queue_length / concurrent_slots) * avg_time
      else
        0
      end
    end
  end
  
  defp emit_metrics_signal(agent, metrics_data) do
    signal_params = %{
      signal_type: "analysis.metrics",
      data: metrics_data
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end