defmodule RubberDuck.Engines.Completion.Incremental do
  @moduledoc """
  Incremental completion support for real-time updates.
  
  This module provides functionality to update completions as the user types,
  without regenerating the entire completion set. It maintains a completion
  session and efficiently updates suggestions based on character changes.
  
  ## Features
  
  - Character-by-character filtering
  - Fuzzy matching support
  - Completion session management
  - Efficient re-ranking
  - Partial completion acceptance
  """
  
  alias RubberDuck.Engines.Completion
  
  @type session :: %{
    id: String.t(),
    original_completions: [Completion.completion_result()],
    current_completions: [Completion.completion_result()],
    original_prefix: String.t(),
    current_prefix: String.t(),
    started_at: DateTime.t(),
    last_updated: DateTime.t(),
    metadata: map()
  }
  
  @type update_type :: :append | :delete | :replace
  
  @doc """
  Start a new incremental completion session.
  
  This creates a session that tracks the original completions and allows
  for efficient updates as the user types.
  """
  @spec start_session([Completion.completion_result()], String.t(), keyword()) :: session()
  def start_session(completions, prefix, opts \\ []) do
    session_id = generate_session_id()
    
    %{
      id: session_id,
      original_completions: completions,
      current_completions: completions,
      original_prefix: prefix,
      current_prefix: prefix,
      started_at: DateTime.utc_now(),
      last_updated: DateTime.utc_now(),
      metadata: %{
        fuzzy_matching: Keyword.get(opts, :fuzzy_matching, true),
        case_sensitive: Keyword.get(opts, :case_sensitive, false),
        max_typos: Keyword.get(opts, :max_typos, 2)
      }
    }
  end
  
  @doc """
  Update the session based on user input changes.
  
  Efficiently filters and re-ranks completions based on the change type
  and new prefix.
  """
  @spec update_session(session(), String.t(), update_type()) :: session()
  def update_session(session, new_prefix, update_type) do
    # Determine what changed
    change = analyze_change(session.current_prefix, new_prefix, update_type)
    
    # Update completions based on change
    updated_completions = case change do
      {:append, chars} ->
        # Filter existing completions
        filter_completions_incremental(session.current_completions, chars, session)
        
      {:delete, _count} ->
        # Restore from original and re-filter
        restore_and_filter(session, new_prefix)
        
      :replace ->
        # Full re-filter from original
        filter_from_original(session, new_prefix)
    end
    
    # Re-rank based on new context
    ranked_completions = rerank_completions(updated_completions, new_prefix, session)
    
    %{session |
      current_completions: ranked_completions,
      current_prefix: new_prefix,
      last_updated: DateTime.utc_now()
    }
  end
  
  @doc """
  Check if a session is still valid.
  
  Sessions expire after a certain time or if the context changes too much.
  """
  @spec session_valid?(session(), keyword()) :: boolean()
  def session_valid?(session, opts \\ []) do
    max_age = Keyword.get(opts, :max_age_seconds, 300)  # 5 minutes
    _max_deviation = Keyword.get(opts, :max_deviation, 10)  # characters
    
    age = DateTime.diff(DateTime.utc_now(), session.started_at, :second)
    deviation = String.jaro_distance(session.original_prefix, session.current_prefix)
    
    age < max_age and deviation > 0.5
  end
  
  @doc """
  Accept a partial completion and update the session.
  
  When a user accepts part of a completion (e.g., by pressing Tab),
  update the session to continue from that point.
  """
  @spec accept_partial(session(), String.t()) :: session()
  def accept_partial(session, accepted_text) do
    new_prefix = session.current_prefix <> accepted_text
    
    # Update completions to account for accepted text
    updated_completions = session.current_completions
    |> Enum.map(fn completion ->
      if String.starts_with?(completion.text, accepted_text) do
        remaining = String.slice(completion.text, String.length(accepted_text)..-1//1)
        %{completion | text: remaining}
      else
        completion
      end
    end)
    |> Enum.filter(fn %{text: text} -> text != "" end)
    
    %{session |
      current_completions: updated_completions,
      current_prefix: new_prefix,
      last_updated: DateTime.utc_now()
    }
  end
  
  @doc """
  Get completion suggestions from the current session.
  """
  @spec get_suggestions(session(), keyword()) :: [Completion.completion_result()]
  def get_suggestions(session, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)
    min_score = Keyword.get(opts, :min_score, 0.5)
    
    session.current_completions
    |> Enum.filter(fn %{score: score} -> score >= min_score end)
    |> Enum.take(limit)
  end
  
  # Private functions
  
  defp generate_session_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
  
  defp analyze_change(old_prefix, new_prefix, update_type) do
    case update_type do
      :append ->
        chars_added = String.slice(new_prefix, String.length(old_prefix)..-1//1)
        {:append, chars_added}
        
      :delete ->
        count = String.length(old_prefix) - String.length(new_prefix)
        {:delete, count}
        
      :replace ->
        :replace
    end
  end
  
  defp filter_completions_incremental(completions, new_chars, session) do
    case_sensitive = session.metadata.case_sensitive
    
    Enum.filter(completions, fn %{text: text} ->
      if case_sensitive do
        String.starts_with?(text, new_chars)
      else
        String.downcase(text) |> String.starts_with?(String.downcase(new_chars))
      end
    end)
  end
  
  defp restore_and_filter(session, new_prefix) do
    typed_suffix = String.slice(
      new_prefix, 
      String.length(session.original_prefix)..-1//1
    )
    
    filter_with_prefix(session.original_completions, typed_suffix, session)
  end
  
  defp filter_from_original(session, new_prefix) do
    if String.starts_with?(new_prefix, session.original_prefix) do
      typed_suffix = String.slice(
        new_prefix,
        String.length(session.original_prefix)..-1//1
      )
      filter_with_prefix(session.original_completions, typed_suffix, session)
    else
      # Context changed too much, return empty
      []
    end
  end
  
  defp filter_with_prefix(completions, prefix, session) do
    if session.metadata.fuzzy_matching do
      fuzzy_filter(completions, prefix, session)
    else
      exact_filter(completions, prefix, session)
    end
  end
  
  defp exact_filter(completions, prefix, session) do
    case_sensitive = session.metadata.case_sensitive
    
    Enum.filter(completions, fn %{text: text} ->
      if case_sensitive do
        String.starts_with?(text, prefix)
      else
        String.downcase(text) |> String.starts_with?(String.downcase(prefix))
      end
    end)
  end
  
  defp fuzzy_filter(completions, prefix, session) do
    max_typos = session.metadata.max_typos
    
    completions
    |> Enum.map(fn completion ->
      score = calculate_fuzzy_score(completion.text, prefix, max_typos)
      {completion, score}
    end)
    |> Enum.filter(fn {_, score} -> score > 0 end)
    |> Enum.map(fn {completion, fuzzy_score} ->
      # Adjust completion score based on fuzzy match quality
      %{completion | score: completion.score * fuzzy_score}
    end)
  end
  
  defp calculate_fuzzy_score(text, prefix, max_typos) do
    # Simple fuzzy scoring based on:
    # 1. Prefix match
    # 2. Character presence
    # 3. Order preservation
    
    text_lower = String.downcase(text)
    prefix_lower = String.downcase(prefix)
    
    cond do
      # Exact prefix match
      String.starts_with?(text_lower, prefix_lower) ->
        1.0
        
      # All characters present in order
      chars_in_order?(text_lower, prefix_lower) ->
        0.8
        
      # Some characters missing but within typo tolerance
      typo_distance(text_lower, prefix_lower) <= max_typos ->
        0.6
        
      # No good match
      true ->
        0.0
    end
  end
  
  defp chars_in_order?(text, prefix) do
    prefix_chars = String.graphemes(prefix)
    
    {_, found_all} = Enum.reduce(prefix_chars, {text, true}, fn char, {remaining, found} ->
      if found do
        case String.split(remaining, char, parts: 2) do
          [_before, after_match] -> {after_match, true}
          [_] -> {remaining, false}
        end
      else
        {remaining, false}
      end
    end)
    
    found_all
  end
  
  defp typo_distance(text, prefix) do
    # Simple edit distance calculation
    # In production, use a proper Levenshtein distance algorithm
    prefix_chars = String.graphemes(prefix)
    text_chars = String.graphemes(text)
    
    missing_chars = prefix_chars -- text_chars
    length(missing_chars)
  end
  
  defp rerank_completions(completions, new_prefix, session) do
    # Re-rank based on:
    # 1. Match quality with new prefix
    # 2. Original score
    # 3. Recency (prefer completions that were ranked high originally)
    
    completions
    |> Enum.with_index()
    |> Enum.map(fn {completion, original_index} ->
      new_score = calculate_updated_score(completion, new_prefix, original_index, session)
      %{completion | score: new_score}
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end
  
  defp calculate_updated_score(completion, prefix, original_index, _session) do
    base_score = completion.score
    
    # Boost for exact prefix match
    prefix_boost = if String.starts_with?(completion.text, prefix), do: 1.2, else: 1.0
    
    # Small penalty for lower original ranking
    rank_penalty = 1.0 - (original_index * 0.01)
    
    # Length match bonus
    length_ratio = String.length(prefix) / String.length(completion.text)
    length_bonus = if length_ratio > 0.3 and length_ratio < 0.8, do: 1.1, else: 1.0
    
    base_score * prefix_boost * rank_penalty * length_bonus
  end
end