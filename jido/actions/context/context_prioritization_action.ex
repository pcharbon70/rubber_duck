defmodule RubberDuck.Jido.Actions.Context.ContextPrioritizationAction do
  @moduledoc """
  Action for intelligent prioritization of context entries using multiple scoring algorithms.

  This action implements sophisticated prioritization strategies for context entries,
  including relevance scoring, temporal weighting, importance assessment, and 
  custom scoring algorithms for specific use cases.

  ## Parameters

  - `entries` - List of context entries to prioritize (required)
  - `request` - Context request information for scoring context (required)
  - `strategy` - Prioritization strategy to use (default: :balanced)
  - `weights` - Custom weights for scoring factors (default: balanced weights)
  - `boost_rules` - Rules for boosting specific entry types (default: [])
  - `penalty_rules` - Rules for penalizing specific entry types (default: [])
  - `max_entries` - Maximum number of entries to return (default: nil for all)
  - `min_score` - Minimum score threshold for inclusion (default: 0.0)

  ## Returns

  - `{:ok, result}` - Prioritization completed successfully with scored entries
  - `{:error, reason}` - Prioritization failed

  ## Example

      params = %{
        entries: context_entries,
        request: context_request,
        strategy: :code_focused,
        weights: %{relevance: 0.5, recency: 0.2, importance: 0.3},
        max_entries: 50
      }

      {:ok, result} = ContextPrioritizationAction.run(params, context)
  """

  use Jido.Action,
    name: "context_prioritization",
    description: "Intelligent prioritization of context entries using multiple scoring algorithms",
    schema: [
      entries: [
        type: :list,
        required: true,
        doc: "List of context entries to prioritize"
      ],
      request: [
        type: :map,
        required: true,
        doc: "Context request information for scoring context"
      ],
      strategy: [
        type: :atom,
        default: :balanced,
        doc: "Prioritization strategy (balanced, relevance_focused, recency_focused, code_focused, memory_focused)"
      ],
      weights: [
        type: :map,
        default: %{},
        doc: "Custom weights for scoring factors"
      ],
      boost_rules: [
        type: :list,
        default: [],
        doc: "Rules for boosting specific entry types"
      ],
      penalty_rules: [
        type: :list,
        default: [],
        doc: "Rules for penalizing specific entry types"
      ],
      max_entries: [
        type: :integer,
        default: nil,
        doc: "Maximum number of entries to return"
      ],
      min_score: [
        type: :float,
        default: 0.0,
        doc: "Minimum score threshold for inclusion"
      ],
      diversity_factor: [
        type: :float,
        default: 0.0,
        doc: "Factor for promoting content diversity (0.0-1.0)"
      ],
      temporal_decay: [
        type: :boolean,
        default: true,
        doc: "Whether to apply temporal decay to scores"
      ]
    ]

  require Logger

  alias RubberDuck.Context.ContextEntry

  @impl true
  def run(params, context) do
    Logger.info("Starting context prioritization with strategy: #{params.strategy}")

    with {:ok, scoring_config} <- build_scoring_config(params),
         {:ok, scored_entries} <- score_all_entries(params.entries, params.request, scoring_config),
         {:ok, boosted_entries} <- apply_boost_rules(scored_entries, params.boost_rules),
         {:ok, penalized_entries} <- apply_penalty_rules(boosted_entries, params.penalty_rules),
         {:ok, diversified_entries} <- apply_diversity_filter(penalized_entries, params.diversity_factor),
         {:ok, filtered_entries} <- apply_filters(diversified_entries, params),
         {:ok, sorted_entries} <- sort_by_score(filtered_entries) do
      
      result = %{
        prioritized_entries: sorted_entries,
        total_entries: length(sorted_entries),
        original_count: length(params.entries),
        strategy_used: params.strategy,
        scoring_config: scoring_config,
        statistics: calculate_score_statistics(sorted_entries),
        metadata: %{
          prioritized_at: DateTime.utc_now(),
          weights_used: scoring_config.weights,
          diversity_applied: params.diversity_factor > 0.0
        }
      }

      {:ok, result}
    else
      {:error, reason} -> 
        Logger.error("Context prioritization failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Scoring configuration

  defp build_scoring_config(params) do
    base_weights = get_strategy_weights(params.strategy)
    custom_weights = params.weights || %{}
    
    final_weights = Map.merge(base_weights, custom_weights)
    |> normalize_weights()
    
    config = %{
      strategy: params.strategy,
      weights: final_weights,
      temporal_decay: params.temporal_decay,
      purpose: params.request.purpose || "general"
    }
    
    {:ok, config}
  end

  defp get_strategy_weights(:balanced) do
    %{
      relevance: 0.4,
      recency: 0.3,
      importance: 0.2,
      source_quality: 0.1
    }
  end

  defp get_strategy_weights(:relevance_focused) do
    %{
      relevance: 0.6,
      recency: 0.2,
      importance: 0.15,
      source_quality: 0.05
    }
  end

  defp get_strategy_weights(:recency_focused) do
    %{
      relevance: 0.3,
      recency: 0.5,
      importance: 0.15,
      source_quality: 0.05
    }
  end

  defp get_strategy_weights(:code_focused) do
    %{
      relevance: 0.4,
      recency: 0.2,
      importance: 0.25,
      source_quality: 0.15
    }
  end

  defp get_strategy_weights(:memory_focused) do
    %{
      relevance: 0.5,
      recency: 0.35,
      importance: 0.1,
      source_quality: 0.05
    }
  end

  defp get_strategy_weights(_), do: get_strategy_weights(:balanced)

  defp normalize_weights(weights) do
    total = weights |> Map.values() |> Enum.sum()
    
    if total > 0 do
      Map.new(weights, fn {k, v} -> {k, v / total} end)
    else
      get_strategy_weights(:balanced)
    end
  end

  # Entry scoring

  defp score_all_entries(entries, request, config) do
    scored_entries = Enum.map(entries, fn entry ->
      score = calculate_comprehensive_score(entry, request, config)
      {entry, score}
    end)
    
    {:ok, scored_entries}
  end

  defp calculate_comprehensive_score(entry, request, config) do
    relevance_score = calculate_relevance_score(entry, request) * config.weights.relevance
    recency_score = calculate_recency_score(entry, config.temporal_decay) * config.weights.recency
    importance_score = calculate_importance_score(entry, request) * config.weights.importance
    source_quality_score = calculate_source_quality_score(entry) * config.weights.source_quality
    
    base_score = relevance_score + recency_score + importance_score + source_quality_score
    
    # Apply purpose-specific adjustments
    purpose_adjusted = apply_purpose_adjustments(base_score, entry, config.purpose)
    
    # Ensure score is between 0 and 1
    max(0.0, min(1.0, purpose_adjusted))
  end

  defp calculate_relevance_score(entry, request) do
    # Use the entry's built-in relevance score as base
    base_relevance = entry.relevance_score || 0.5
    
    # Boost based on content matching
    content_boost = calculate_content_matching_boost(entry, request)
    
    # Boost based on metadata matching  
    metadata_boost = calculate_metadata_matching_boost(entry, request)
    
    min(1.0, base_relevance + content_boost + metadata_boost)
  end

  defp calculate_content_matching_boost(entry, request) do
    content_str = entry_content_to_string(entry)
    purpose_keywords = extract_purpose_keywords(request.purpose || "general")
    
    # Simple keyword matching boost
    matching_keywords = Enum.count(purpose_keywords, fn keyword ->
      String.contains?(String.downcase(content_str), String.downcase(keyword))
    end)
    
    if length(purpose_keywords) > 0 do
      (matching_keywords / length(purpose_keywords)) * 0.2
    else
      0.0
    end
  end

  defp calculate_metadata_matching_boost(entry, request) do
    filters = request.filters || %{}
    preferences = request.preferences || %{}
    
    # Check metadata matches
    metadata_matches = Enum.count(filters, fn {key, value} ->
      entry_value = get_nested_metadata(entry.metadata, key)
      entry_value == value
    end)
    
    preference_matches = Enum.count(preferences, fn {key, value} ->
      entry_value = get_nested_metadata(entry.metadata, key)
      entry_value == value
    end)
    
    total_criteria = map_size(filters) + map_size(preferences)
    
    if total_criteria > 0 do
      ((metadata_matches + preference_matches) / total_criteria) * 0.15
    else
      0.0
    end
  end

  defp calculate_recency_score(entry, apply_temporal_decay) do
    base_score = case DateTime.diff(DateTime.utc_now(), entry.timestamp, :minute) do
      age when age < 5 -> 1.0
      age when age < 30 -> 0.9
      age when age < 60 -> 0.7
      age when age < 1440 -> 0.5  # 24 hours
      age when age < 10080 -> 0.3  # 1 week
      _ -> 0.1
    end
    
    if apply_temporal_decay do
      # Apply exponential decay for very old content
      age_hours = DateTime.diff(DateTime.utc_now(), entry.timestamp, :hour)
      decay_factor = :math.exp(-age_hours / 168.0)  # Decay over a week
      base_score * decay_factor
    else
      base_score
    end
  end

  defp calculate_importance_score(entry, request) do
    # Base importance from metadata
    base_importance = Map.get(entry.metadata, :importance, 0.5)
    
    # Source-type importance adjustments
    source_adjustment = case Map.get(entry.metadata, :source_type) do
      :memory -> 0.1  # Memory is often important for context
      :code_analysis -> 0.05
      :documentation -> 0.0
      :conversation -> 0.05
      :planning -> 0.1
      _ -> 0.0
    end
    
    # Size-based importance (larger content might be more important)
    size_adjustment = case entry.size_tokens do
      tokens when tokens > 1000 -> 0.1
      tokens when tokens > 500 -> 0.05
      _ -> 0.0
    end
    
    # Priority from request
    priority_adjustment = case request.priority do
      :critical -> 0.15
      :high -> 0.1
      :normal -> 0.0
      :low -> -0.05
    end
    
    min(1.0, base_importance + source_adjustment + size_adjustment + priority_adjustment)
  end

  defp calculate_source_quality_score(entry) do
    # Base quality from source metadata
    base_quality = Map.get(entry.metadata, :source_quality, 0.7)
    
    # Adjustments based on entry characteristics
    compression_penalty = if entry.compressed, do: -0.1, else: 0.0
    summarization_penalty = if entry.summarized, do: -0.05, else: 0.0
    
    # Hash consistency (content integrity)
    hash_bonus = if entry.hash && String.length(entry.hash) > 0, do: 0.05, else: 0.0
    
    min(1.0, max(0.0, base_quality + compression_penalty + summarization_penalty + hash_bonus))
  end

  defp apply_purpose_adjustments(score, entry, purpose) do
    case purpose do
      "code_generation" -> 
        if Map.get(entry.metadata, :source_type) == :code_analysis do
          score * 1.2  # Boost code-related content
        else
          score
        end
        
      "debugging" ->
        if Map.get(entry.metadata, :type) in [:error, :issue, :bug] do
          score * 1.3  # Boost error-related content
        else
          score
        end
        
      "planning" ->
        if Map.get(entry.metadata, :source_type) == :planning do
          score * 1.15  # Boost planning content
        else
          score
        end
        
      _ -> score
    end
  end

  # Boost and penalty rules

  defp apply_boost_rules(scored_entries, boost_rules) do
    boosted = Enum.map(scored_entries, fn {entry, score} ->
      boost_factor = calculate_boost_factor(entry, boost_rules)
      {entry, score * boost_factor}
    end)
    
    {:ok, boosted}
  end

  defp apply_penalty_rules(scored_entries, penalty_rules) do
    penalized = Enum.map(scored_entries, fn {entry, score} ->
      penalty_factor = calculate_penalty_factor(entry, penalty_rules)
      {entry, score * penalty_factor}
    end)
    
    {:ok, penalized}
  end

  defp calculate_boost_factor(entry, boost_rules) do
    Enum.reduce(boost_rules, 1.0, fn rule, acc ->
      if matches_rule?(entry, rule) do
        acc * (rule.factor || 1.2)
      else
        acc
      end
    end)
  end

  defp calculate_penalty_factor(entry, penalty_rules) do
    Enum.reduce(penalty_rules, 1.0, fn rule, acc ->
      if matches_rule?(entry, rule) do
        acc * (rule.factor || 0.8)
      else
        acc
      end
    end)
  end

  defp matches_rule?(entry, rule) do
    case rule.type do
      :metadata_match ->
        entry.metadata[rule.key] == rule.value
        
      :content_contains ->
        content_str = entry_content_to_string(entry)
        String.contains?(String.downcase(content_str), String.downcase(rule.pattern))
        
      :source_type ->
        Map.get(entry.metadata, :source_type) == rule.source_type
        
      :age_threshold ->
        age_minutes = DateTime.diff(DateTime.utc_now(), entry.timestamp, :minute)
        case rule.operator do
          :lt -> age_minutes < rule.threshold
          :gt -> age_minutes > rule.threshold
          :eq -> age_minutes == rule.threshold
        end
        
      _ -> false
    end
  end

  # Diversity filtering

  defp apply_diversity_filter(scored_entries, diversity_factor) when diversity_factor <= 0.0 do
    {:ok, scored_entries}
  end

  defp apply_diversity_filter(scored_entries, diversity_factor) do
    # Group entries by content similarity and select diverse representatives
    diversified = promote_content_diversity(scored_entries, diversity_factor)
    {:ok, diversified}
  end

  defp promote_content_diversity(scored_entries, diversity_factor) do
    # Sort by score first
    sorted = Enum.sort_by(scored_entries, fn {_entry, score} -> score end, :desc)
    
    # Apply diversity selection
    {selected, _} = Enum.reduce(sorted, {[], []}, fn {entry, score}, {acc, seen_contents} ->
      if should_include_for_diversity?(entry, seen_contents, diversity_factor) do
        {[{entry, score} | acc], [entry_content_signature(entry) | seen_contents]}
      else
        {acc, seen_contents}
      end
    end)
    
    Enum.reverse(selected)
  end

  defp should_include_for_diversity?(entry, seen_contents, diversity_factor) do
    signature = entry_content_signature(entry)
    
    # Calculate similarity to already seen content
    max_similarity = Enum.map(seen_contents, fn seen ->
      content_similarity(signature, seen)
    end)
    |> Enum.max(fn -> 0.0 end)
    
    # Include if similarity is below threshold (adjusted by diversity factor)
    threshold = 0.9 - (diversity_factor * 0.3)  # More diversity = lower threshold
    max_similarity < threshold
  end

  defp entry_content_signature(entry) do
    content_str = entry_content_to_string(entry)
    
    # Create a simple signature based on content words
    content_str
    |> String.downcase()
    |> String.split(~r/\W+/)
    |> Enum.filter(&(String.length(&1) > 3))
    |> MapSet.new()
  end

  defp content_similarity(sig1, sig2) do
    intersection = MapSet.intersection(sig1, sig2) |> MapSet.size()
    union = MapSet.union(sig1, sig2) |> MapSet.size()
    
    if union > 0, do: intersection / union, else: 0.0
  end

  # Filtering and sorting

  defp apply_filters(scored_entries, params) do
    filtered = scored_entries
    |> filter_by_min_score(params.min_score)
    |> limit_entries(params.max_entries)
    
    {:ok, filtered}
  end

  defp filter_by_min_score(scored_entries, min_score) do
    Enum.filter(scored_entries, fn {_entry, score} -> score >= min_score end)
  end

  defp limit_entries(scored_entries, nil), do: scored_entries
  defp limit_entries(scored_entries, max_entries) do
    Enum.take(scored_entries, max_entries)
  end

  defp sort_by_score(scored_entries) do
    sorted = Enum.sort_by(scored_entries, fn {_entry, score} -> score end, :desc)
    |> Enum.map(fn {entry, _score} -> entry end)
    
    {:ok, sorted}
  end

  # Statistics and analysis

  defp calculate_score_statistics(entries) do
    if Enum.empty?(entries) do
      %{count: 0, mean: 0.0, median: 0.0, std_dev: 0.0}
    else
      # Note: entries are already sorted, so scores need to be recalculated for stats
      # For now, return basic statistics
      %{
        count: length(entries),
        mean: 0.0,  # Would need to recalculate scores
        median: 0.0,
        std_dev: 0.0,
        source_distribution: calculate_source_distribution(entries)
      }
    end
  end

  defp calculate_source_distribution(entries) do
    entries
    |> Enum.group_by(fn entry -> entry.source end)
    |> Map.new(fn {source, entries} -> {source, length(entries)} end)
  end

  # Helper functions

  defp extract_purpose_keywords(purpose) do
    case purpose do
      "code_generation" -> ["code", "function", "class", "method", "variable", "implementation"]
      "debugging" -> ["error", "bug", "issue", "problem", "exception", "failure"]
      "planning" -> ["plan", "strategy", "goal", "objective", "requirement", "task"]
      "documentation" -> ["docs", "documentation", "guide", "manual", "help", "tutorial"]
      _ -> []
    end
  end

  defp entry_content_to_string(entry) do
    case entry.content do
      content when is_binary(content) -> content
      content when is_map(content) -> Jason.encode!(content)
      content -> inspect(content)
    end
  end

  defp get_nested_metadata(metadata, key) when is_binary(key) do
    keys = String.split(key, ".")
    get_in(metadata, Enum.map(keys, &String.to_atom/1))
  end
  defp get_nested_metadata(metadata, key), do: Map.get(metadata, key)
end