defmodule RubberDuck.Jido.Actions.Context.ContextCompressionAction do
  @moduledoc """
  Action for compressing and optimizing context entries to reduce token usage.

  This action implements multiple compression strategies including deduplication,
  content compression, summarization, and intelligent truncation while preserving
  the most important information.

  ## Parameters

  - `entries` - List of context entries to compress (required)
  - `max_tokens` - Target maximum token count after compression (required)
  - `strategy` - Compression strategy to use (default: :balanced)
  - `preserve_ratio` - Ratio of content to preserve (0.0-1.0, default: 0.7)
  - `dedup_threshold` - Similarity threshold for deduplication (default: 0.85)
  - `compression_level` - Aggressiveness of compression (default: :moderate)
  - `preserve_sources` - Source types to prioritize for preservation (default: [])
  - `summary_ratio` - Target ratio for summarization (default: 0.3)

  ## Returns

  - `{:ok, result}` - Compression completed successfully
  - `{:error, reason}` - Compression failed

  ## Example

      params = %{
        entries: context_entries,
        max_tokens: 3000,
        strategy: :aggressive,
        preserve_ratio: 0.6,
        preserve_sources: [:memory, :code_analysis]
      }

      {:ok, result} = ContextCompressionAction.run(params, context)
  """

  use Jido.Action,
    name: "context_compression",
    description: "Compress and optimize context entries to reduce token usage",
    schema: [
      entries: [
        type: :list,
        required: true,
        doc: "List of context entries to compress"
      ],
      max_tokens: [
        type: :integer,
        required: true,
        doc: "Target maximum token count after compression"
      ],
      strategy: [
        type: :atom,
        default: :balanced,
        doc: "Compression strategy (aggressive, balanced, conservative, smart)"
      ],
      preserve_ratio: [
        type: :float,
        default: 0.7,
        doc: "Ratio of content to preserve (0.0-1.0)"
      ],
      dedup_threshold: [
        type: :float,
        default: 0.85,
        doc: "Similarity threshold for deduplication (0.0-1.0)"
      ],
      compression_level: [
        type: :atom,
        default: :moderate,
        doc: "Aggressiveness of compression (light, moderate, aggressive)"
      ],
      preserve_sources: [
        type: {:list, :atom},
        default: [],
        doc: "Source types to prioritize for preservation"
      ],
      summary_ratio: [
        type: :float,
        default: 0.3,
        doc: "Target ratio for summarization (0.0-1.0)"
      ],
      enable_smart_truncation: [
        type: :boolean,
        default: true,
        doc: "Enable intelligent content truncation"
      ],
      maintain_structure: [
        type: :boolean,
        default: true,
        doc: "Maintain content structure during compression"
      ]
    ]

  require Logger

  alias RubberDuck.Context.ContextEntry

  @impl true
  def run(params, context) do
    Logger.info("Starting context compression with strategy: #{params.strategy}, target: #{params.max_tokens} tokens")

    initial_tokens = calculate_total_tokens(params.entries)
    
    if initial_tokens <= params.max_tokens do
      # Already within limits
      result = %{
        compressed_entries: params.entries,
        original_count: length(params.entries),
        final_count: length(params.entries),
        original_tokens: initial_tokens,
        final_tokens: initial_tokens,
        compression_ratio: 1.0,
        strategies_applied: [],
        metadata: %{
          compressed_at: DateTime.utc_now(),
          no_compression_needed: true
        }
      }
      
      {:ok, result}
    else
      with {:ok, compression_plan} <- build_compression_plan(params, initial_tokens),
           {:ok, compressed_entries} <- apply_compression_pipeline(params.entries, compression_plan),
           {:ok, final_result} <- finalize_compression_result(params.entries, compressed_entries, compression_plan) do
        
        {:ok, final_result}
      else
        {:error, reason} ->
          Logger.error("Context compression failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # Compression planning

  defp build_compression_plan(params, current_tokens) do
    reduction_needed = current_tokens - params.max_tokens
    reduction_ratio = reduction_needed / current_tokens
    
    plan = %{
      strategy: params.strategy,
      target_tokens: params.max_tokens,
      current_tokens: current_tokens,
      reduction_needed: reduction_needed,
      reduction_ratio: reduction_ratio,
      pipeline: build_compression_pipeline(params, reduction_ratio)
    }
    
    {:ok, plan}
  end

  defp build_compression_pipeline(params, reduction_ratio) do
    case params.strategy do
      :aggressive -> build_aggressive_pipeline(params, reduction_ratio)
      :balanced -> build_balanced_pipeline(params, reduction_ratio)
      :conservative -> build_conservative_pipeline(params, reduction_ratio)
      :smart -> build_smart_pipeline(params, reduction_ratio)
      _ -> build_balanced_pipeline(params, reduction_ratio)
    end
  end

  defp build_aggressive_pipeline(params, reduction_ratio) do
    [
      {:deduplication, %{threshold: params.dedup_threshold}},
      {:content_compression, %{level: :aggressive, preserve_structure: params.maintain_structure}},
      {:summarization, %{ratio: params.summary_ratio, selective: true}},
      {:smart_truncation, %{preserve_ratio: params.preserve_ratio, preserve_sources: params.preserve_sources}},
      {:final_truncation, %{target_ratio: 1.0 - reduction_ratio}}
    ]
  end

  defp build_balanced_pipeline(params, reduction_ratio) do
    [
      {:deduplication, %{threshold: params.dedup_threshold}},
      {:content_compression, %{level: params.compression_level, preserve_structure: params.maintain_structure}},
      {:selective_summarization, %{ratio: params.summary_ratio, preserve_sources: params.preserve_sources}},
      {:smart_truncation, %{preserve_ratio: params.preserve_ratio, preserve_sources: params.preserve_sources}}
    ]
  end

  defp build_conservative_pipeline(params, _reduction_ratio) do
    [
      {:deduplication, %{threshold: max(params.dedup_threshold, 0.9)}},
      {:content_compression, %{level: :light, preserve_structure: true}},
      {:smart_truncation, %{preserve_ratio: max(params.preserve_ratio, 0.8), preserve_sources: params.preserve_sources}}
    ]
  end

  defp build_smart_pipeline(params, reduction_ratio) do
    # Adaptive pipeline based on reduction needs
    cond do
      reduction_ratio < 0.2 -> [
        {:deduplication, %{threshold: params.dedup_threshold}},
        {:content_compression, %{level: :light, preserve_structure: params.maintain_structure}}
      ]
      
      reduction_ratio < 0.5 -> [
        {:deduplication, %{threshold: params.dedup_threshold}},
        {:content_compression, %{level: :moderate, preserve_structure: params.maintain_structure}},
        {:selective_summarization, %{ratio: params.summary_ratio * 1.5, preserve_sources: params.preserve_sources}}
      ]
      
      true -> [
        {:deduplication, %{threshold: params.dedup_threshold - 0.1}},
        {:content_compression, %{level: :aggressive, preserve_structure: false}},
        {:summarization, %{ratio: params.summary_ratio, selective: true}},
        {:smart_truncation, %{preserve_ratio: params.preserve_ratio * 0.8, preserve_sources: params.preserve_sources}}
      ]
    end
  end

  # Compression pipeline execution

  defp apply_compression_pipeline(entries, plan) do
    Logger.info("Applying compression pipeline with #{length(plan.pipeline)} steps")
    
    {final_entries, _} = Enum.reduce(plan.pipeline, {entries, []}, fn {step, config}, {current_entries, applied_steps} ->
      Logger.debug("Applying compression step: #{step}")
      
      case apply_compression_step(step, current_entries, config) do
        {:ok, compressed_entries} ->
          {compressed_entries, [step | applied_steps]}
          
        {:error, reason} ->
          Logger.warning("Compression step #{step} failed: #{inspect(reason)}")
          {current_entries, applied_steps}
      end
    end)
    
    {:ok, final_entries}
  end

  defp apply_compression_step(:deduplication, entries, config) do
    deduplicated = deduplicate_entries(entries, config.threshold)
    {:ok, deduplicated}
  end

  defp apply_compression_step(:content_compression, entries, config) do
    compressed = Enum.map(entries, fn entry ->
      apply_content_compression(entry, config)
    end)
    {:ok, compressed}
  end

  defp apply_compression_step(:summarization, entries, config) do
    summarized = Enum.map(entries, fn entry ->
      if should_summarize_entry?(entry, config) do
        ContextEntry.summarize(entry, config.ratio)
      else
        entry
      end
    end)
    {:ok, summarized}
  end

  defp apply_compression_step(:selective_summarization, entries, config) do
    # Only summarize entries not from preserved sources
    summarized = Enum.map(entries, fn entry ->
      source_type = Map.get(entry.metadata, :source_type)
      
      if source_type not in config.preserve_sources and should_summarize_entry?(entry, config) do
        ContextEntry.summarize(entry, config.ratio)
      else
        entry
      end
    end)
    {:ok, summarized}
  end

  defp apply_compression_step(:smart_truncation, entries, config) do
    truncated = apply_smart_truncation(entries, config)
    {:ok, truncated}
  end

  defp apply_compression_step(:final_truncation, entries, config) do
    target_count = round(length(entries) * config.target_ratio)
    truncated = Enum.take(entries, max(1, target_count))
    {:ok, truncated}
  end

  defp apply_compression_step(unknown_step, entries, _config) do
    Logger.warning("Unknown compression step: #{unknown_step}")
    {:ok, entries}
  end

  # Deduplication

  defp deduplicate_entries(entries, threshold) do
    Enum.reduce(entries, [], fn entry, acc ->
      if similar_entry_exists?(entry, acc, threshold) do
        acc
      else
        [entry | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp similar_entry_exists?(entry, entries, threshold) do
    Enum.any?(entries, fn existing ->
      ContextEntry.similar?(entry, existing, threshold)
    end)
  end

  # Content compression

  defp apply_content_compression(entry, config) do
    case config.level do
      :light -> apply_light_compression(entry, config)
      :moderate -> apply_moderate_compression(entry, config)
      :aggressive -> apply_aggressive_compression(entry, config)
      _ -> entry
    end
  end

  defp apply_light_compression(entry, config) do
    if entry.size_tokens > 200 do
      compressed_content = compress_whitespace(entry.content)
      
      %{entry |
        content: compressed_content,
        size_tokens: estimate_tokens(compressed_content),
        compressed: true,
        original_content: entry.original_content || entry.content
      }
    else
      entry
    end
  end

  defp apply_moderate_compression(entry, config) do
    if entry.size_tokens > 100 do
      compressed_content = entry.content
      |> compress_whitespace()
      |> remove_redundant_words()
      |> (fn content -> if config.preserve_structure, do: content, else: flatten_structure(content) end).()
      
      %{entry |
        content: compressed_content,
        size_tokens: estimate_tokens(compressed_content),
        compressed: true,
        original_content: entry.original_content || entry.content
      }
    else
      entry
    end
  end

  defp apply_aggressive_compression(entry, config) do
    compressed_content = entry.content
    |> compress_whitespace()
    |> remove_redundant_words()
    |> remove_stop_words()
    |> abbreviate_common_terms()
    |> (fn content -> if config.preserve_structure, do: content, else: flatten_structure(content) end).()
    
    %{entry |
      content: compressed_content,
      size_tokens: estimate_tokens(compressed_content),
      compressed: true,
      original_content: entry.original_content || entry.content
    }
  end

  # Content compression helpers

  defp compress_whitespace(content) when is_binary(content) do
    content
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/\n\s*\n/, "\n")
    |> String.trim()
  end

  defp compress_whitespace(content), do: content

  defp remove_redundant_words(content) when is_binary(content) do
    # Remove repeated words within sentences
    content
    |> String.split(".")
    |> Enum.map(&remove_word_repetition/1)
    |> Enum.join(".")
  end

  defp remove_redundant_words(content), do: content

  defp remove_word_repetition(sentence) do
    words = String.split(sentence)
    
    {unique_words, _} = Enum.reduce(words, {[], MapSet.new()}, fn word, {acc, seen} ->
      normalized = String.downcase(word)
      if MapSet.member?(seen, normalized) do
        {acc, seen}
      else
        {[word | acc], MapSet.put(seen, normalized)}
      end
    end)
    
    unique_words |> Enum.reverse() |> Enum.join(" ")
  end

  defp remove_stop_words(content) when is_binary(content) do
    stop_words = ~w(the a an and or but in on at to for of with by from up about into through during before after above below between among)
    
    content
    |> String.split()
    |> Enum.reject(fn word -> 
      String.downcase(word) in stop_words and String.length(word) < 4
    end)
    |> Enum.join(" ")
  end

  defp remove_stop_words(content), do: content

  defp abbreviate_common_terms(content) when is_binary(content) do
    abbreviations = %{
      "function" => "fn",
      "variable" => "var",
      "parameter" => "param",
      "argument" => "arg",
      "implementation" => "impl",
      "configuration" => "config",
      "documentation" => "doc",
      "specification" => "spec"
    }
    
    Enum.reduce(abbreviations, content, fn {full, abbrev}, acc ->
      String.replace(acc, ~r/\b#{full}\b/i, abbrev)
    end)
  end

  defp abbreviate_common_terms(content), do: content

  defp flatten_structure(content) when is_map(content) do
    # Convert nested structure to flat string
    content
    |> Map.values()
    |> Enum.join(" ")
    |> compress_whitespace()
  end

  defp flatten_structure(content), do: content

  # Smart truncation

  defp apply_smart_truncation(entries, config) do
    # Sort entries by importance (preserve high-importance entries)
    sorted_entries = Enum.sort_by(entries, &calculate_preservation_score(&1, config), :desc)
    
    # Calculate how many entries to keep
    target_count = round(length(entries) * config.preserve_ratio)
    
    kept_entries = Enum.take(sorted_entries, max(1, target_count))
    
    Logger.debug("Smart truncation: kept #{length(kept_entries)} of #{length(entries)} entries")
    
    kept_entries
  end

  defp calculate_preservation_score(entry, config) do
    base_score = entry.relevance_score || 0.5
    
    # Boost for preserved source types
    source_boost = if Map.get(entry.metadata, :source_type) in config.preserve_sources do
      0.3
    else
      0.0
    end
    
    # Boost for larger content (might be more important)
    size_boost = case entry.size_tokens do
      tokens when tokens > 500 -> 0.2
      tokens when tokens > 200 -> 0.1
      _ -> 0.0
    end
    
    # Penalty for already compressed content
    compression_penalty = if entry.compressed, do: -0.1, else: 0.0
    
    min(1.0, base_score + source_boost + size_boost + compression_penalty)
  end

  # Summarization helpers

  defp should_summarize_entry?(entry, config) do
    # Don't summarize if already summarized
    not entry.summarized and
    # Don't summarize very small entries
    entry.size_tokens > 100 and
    # Apply selective criteria if specified
    (not Map.get(config, :selective, false) or entry.size_tokens > 300)
  end

  # Result finalization

  defp finalize_compression_result(original_entries, compressed_entries, plan) do
    original_tokens = calculate_total_tokens(original_entries)
    final_tokens = calculate_total_tokens(compressed_entries)
    
    result = %{
      compressed_entries: compressed_entries,
      original_count: length(original_entries),
      final_count: length(compressed_entries),
      original_tokens: original_tokens,
      final_tokens: final_tokens,
      compression_ratio: if(original_tokens > 0, do: final_tokens / original_tokens, else: 1.0),
      reduction_achieved: original_tokens - final_tokens,
      strategies_applied: Enum.map(plan.pipeline, fn {step, _} -> step end),
      metadata: %{
        compressed_at: DateTime.utc_now(),
        target_tokens: plan.target_tokens,
        target_achieved: final_tokens <= plan.target_tokens,
        compression_details: build_compression_details(compressed_entries)
      }
    }
    
    {:ok, result}
  end

  defp build_compression_details(entries) do
    %{
      compressed_count: Enum.count(entries, & &1.compressed),
      summarized_count: Enum.count(entries, & &1.summarized),
      avg_tokens_per_entry: if(length(entries) > 0, do: calculate_total_tokens(entries) / length(entries), else: 0),
      source_distribution: calculate_source_distribution(entries)
    }
  end

  defp calculate_source_distribution(entries) do
    entries
    |> Enum.group_by(fn entry -> entry.source end)
    |> Map.new(fn {source, entries} -> {source, length(entries)} end)
  end

  # Helper functions

  defp calculate_total_tokens(entries) do
    Enum.sum(Enum.map(entries, & &1.size_tokens))
  end

  defp estimate_tokens(content) when is_binary(content) do
    # Rough estimation: 1 token ≈ 4 characters
    div(String.length(content), 4)
  end

  defp estimate_tokens(content) when is_map(content) do
    content
    |> Jason.encode!()
    |> estimate_tokens()
  end

  defp estimate_tokens(_), do: 0
end