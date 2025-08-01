defmodule RubberDuck.Context.ContextOptimizer do
  @moduledoc """
  Optimization strategies for context entries to fit within token limits.
  
  This module provides various optimization techniques including compression,
  summarization, deduplication, and intelligent truncation to ensure context
  fits within LLM token constraints while preserving maximum value.
  """

  alias RubberDuck.Context.ContextEntry
  require Logger

  @default_config %{
    compression_threshold: 1000,
    dedup_threshold: 0.85,
    summary_ratio: 0.3,
    min_relevance_score: 0.2,
    chunk_size: 500
  }

  @doc """
  Optimizes a list of context entries to fit within token limit.
  """
  def optimize(entries, max_tokens, config \\ %{}) do
    config = Map.merge(@default_config, config)
    
    entries
    |> remove_expired()
    |> deduplicate(config.dedup_threshold)
    |> apply_compression(config)
    |> fit_to_limit(max_tokens, config)
  end

  @doc """
  Removes duplicate or highly similar entries.
  """
  def deduplicate(entries, threshold \\ 0.85) do
    Enum.reduce(entries, [], fn entry, acc ->
      if similar_exists?(entry, acc, threshold) do
        Logger.debug("Deduplicating entry #{entry.id}")
        acc
      else
        [entry | acc]
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Compresses entries that exceed the threshold.
  """
  def apply_compression(entries, config) do
    threshold = config[:compression_threshold] || 1000
    
    Enum.map(entries, fn entry ->
      if entry.size_tokens > threshold and not entry.compressed do
        ContextEntry.compress(entry)
      else
        entry
      end
    end)
  end

  @doc """
  Summarizes entries to reduce token count.
  """
  def apply_summarization(entries, target_ratio \\ 0.5) do
    Enum.map(entries, fn entry ->
      if should_summarize?(entry) do
        ContextEntry.summarize(entry, target_ratio)
      else
        entry
      end
    end)
  end

  @doc """
  Fits entries within token limit using various strategies.
  """
  def fit_to_limit(entries, max_tokens, config) do
    current_tokens = calculate_total_tokens(entries)
    
    cond do
      current_tokens <= max_tokens ->
        entries
        
      current_tokens <= max_tokens * 1.5 ->
        # Minor optimization needed
        entries
        |> filter_by_relevance(config.min_relevance_score)
        |> truncate_to_limit(max_tokens)
        
      true ->
        # Major optimization needed
        entries
        |> prioritize_entries(max_tokens)
        |> apply_aggressive_optimization(max_tokens, config)
    end
  end

  @doc """
  Chunks entries for streaming delivery.
  """
  def chunk_for_streaming(entries, chunk_size \\ 500) do
    entries
    |> Enum.reduce({[], 0, []}, fn entry, {current_chunk, current_size, chunks} ->
      entry_size = entry.size_tokens
      
      if current_size + entry_size > chunk_size and current_chunk != [] do
        # Start new chunk
        {[entry], entry_size, [Enum.reverse(current_chunk) | chunks]}
      else
        # Add to current chunk
        {[entry | current_chunk], current_size + entry_size, chunks}
      end
    end)
    |> then(fn {last_chunk, _, chunks} ->
      if last_chunk != [] do
        [Enum.reverse(last_chunk) | chunks]
      else
        chunks
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Merges overlapping entries from the same source.
  """
  def merge_related(entries) do
    entries
    |> Enum.group_by(& &1.source)
    |> Enum.flat_map(fn {_source, source_entries} ->
      merge_source_entries(source_entries)
    end)
  end

  @doc """
  Calculates token usage statistics.
  """
  def calculate_stats(entries) do
    total_tokens = calculate_total_tokens(entries)
    
    %{
      total_entries: length(entries),
      total_tokens: total_tokens,
      avg_tokens_per_entry: if(length(entries) > 0, do: total_tokens / length(entries), else: 0),
      compressed_count: Enum.count(entries, & &1.compressed),
      summarized_count: Enum.count(entries, & &1.summarized),
      sources: entries |> Enum.map(& &1.source) |> Enum.uniq() |> length()
    }
  end

  @doc """
  Estimates optimization potential for a set of entries.
  """
  def estimate_optimization_potential(entries) do
    current_tokens = calculate_total_tokens(entries)
    
    # Estimate tokens after optimization
    estimated_after_dedup = estimate_after_dedup(entries)
    estimated_after_compression = estimate_after_compression(entries)
    estimated_after_summary = estimate_after_summary(entries)
    
    %{
      current_tokens: current_tokens,
      estimated_after_dedup: estimated_after_dedup,
      estimated_after_compression: estimated_after_compression,
      estimated_after_summary: estimated_after_summary,
      potential_savings: current_tokens - estimated_after_summary,
      savings_percentage: (current_tokens - estimated_after_summary) / current_tokens * 100
    }
  end

  # Private functions

  defp remove_expired(entries) do
    Enum.reject(entries, &ContextEntry.expired?/1)
  end

  defp similar_exists?(entry, existing_entries, threshold) do
    Enum.any?(existing_entries, fn existing ->
      ContextEntry.similar?(entry, existing, threshold)
    end)
  end

  defp should_summarize?(entry) do
    # Summarize if large and not already optimized
    entry.size_tokens > 500 and 
    not entry.summarized and 
    not entry.compressed
  end

  defp calculate_total_tokens(entries) do
    Enum.sum(Enum.map(entries, & &1.size_tokens))
  end

  defp filter_by_relevance(entries, min_score) do
    Enum.filter(entries, fn entry ->
      entry.relevance_score >= min_score
    end)
  end

  defp truncate_to_limit(entries, max_tokens) do
    {kept, _} = Enum.reduce(entries, {[], 0}, fn entry, {acc, total} ->
      if total + entry.size_tokens <= max_tokens do
        {[entry | acc], total + entry.size_tokens}
      else
        {acc, total}
      end
    end)
    
    Enum.reverse(kept)
  end

  defp prioritize_entries(entries, max_tokens) do
    # Sort by relevance and recency
    sorted = Enum.sort_by(entries, fn entry ->
      recency_score = calculate_recency_score(entry.timestamp)
      {entry.relevance_score * recency_score, entry.timestamp}
    end, :desc)
    
    # Take entries that fit
    truncate_to_limit(sorted, max_tokens)
  end

  defp apply_aggressive_optimization(entries, max_tokens, config) do
    # Step 1: Summarize all entries
    summarized = apply_summarization(entries, config.summary_ratio)
    
    if calculate_total_tokens(summarized) <= max_tokens do
      summarized
    else
      # Step 2: Keep only high-relevance entries
      high_relevance = filter_by_relevance(summarized, 0.7)
      
      if calculate_total_tokens(high_relevance) <= max_tokens do
        high_relevance
      else
        # Step 3: Truncate to fit
        truncate_to_limit(high_relevance, max_tokens)
      end
    end
  end

  defp calculate_recency_score(timestamp) do
    age_minutes = DateTime.diff(DateTime.utc_now(), timestamp, :minute)
    
    cond do
      age_minutes < 5 -> 1.0
      age_minutes < 30 -> 0.9
      age_minutes < 60 -> 0.7
      age_minutes < 1440 -> 0.5
      true -> 0.3
    end
  end

  defp merge_source_entries(entries) do
    # Group by content similarity
    groups = group_similar_entries(entries)
    
    # Merge each group
    Enum.map(groups, fn group ->
      if length(group) == 1 do
        hd(group)
      else
        merge_entry_group(group)
      end
    end)
  end

  defp group_similar_entries(entries) do
    Enum.reduce(entries, [], fn entry, groups ->
      matching_group = Enum.find_index(groups, fn group ->
        Enum.any?(group, fn member ->
          ContextEntry.similar?(entry, member, 0.7)
        end)
      end)
      
      case matching_group do
        nil ->
          # Start new group
          [[entry] | groups]
          
        index ->
          # Add to existing group
          List.update_at(groups, index, &[entry | &1])
      end
    end)
  end

  defp merge_entry_group(entries) do
    # Take the most recent entry as base
    base = Enum.max_by(entries, & &1.timestamp, DateTime)
    
    # Merge metadata from all entries
    merged_metadata = Enum.reduce(entries, %{}, fn entry, acc ->
      Map.merge(acc, entry.metadata)
    end)
    
    # Use highest relevance score
    max_relevance = Enum.map(entries, & &1.relevance_score) |> Enum.max()
    
    %{base |
      metadata: merged_metadata,
      relevance_score: max_relevance,
      size_tokens: estimate_merged_size(entries)
    }
  end

  defp estimate_merged_size(entries) do
    # Estimate size reduction from merging
    total = Enum.sum(Enum.map(entries, & &1.size_tokens))
    round(total * 0.7)  # Assume 30% reduction from merging
  end

  defp estimate_after_dedup(entries) do
    # Estimate 20% reduction from deduplication
    unique_hashes = entries
    |> Enum.map(&ContextEntry.content_hash/1)
    |> Enum.uniq()
    |> length()
    
    reduction_factor = unique_hashes / length(entries)
    round(calculate_total_tokens(entries) * reduction_factor)
  end

  defp estimate_after_compression(entries) do
    compressible = Enum.filter(entries, fn entry ->
      entry.size_tokens > 1000 and not entry.compressed
    end)
    
    compression_savings = Enum.sum(Enum.map(compressible, fn entry ->
      entry.size_tokens * 0.3  # Assume 30% compression
    end))
    
    calculate_total_tokens(entries) - round(compression_savings)
  end

  defp estimate_after_summary(entries) do
    summarizable = Enum.filter(entries, fn entry ->
      entry.size_tokens > 500 and not entry.summarized
    end)
    
    summary_savings = Enum.sum(Enum.map(summarizable, fn entry ->
      entry.size_tokens * 0.7  # Assume 70% reduction
    end))
    
    calculate_total_tokens(entries) - round(summary_savings)
  end
end