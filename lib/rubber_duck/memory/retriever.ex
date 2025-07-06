defmodule RubberDuck.Memory.Retriever do
  @moduledoc """
  Module for retrieving and searching across memory tiers.
  Provides unified search interface with ranking and relevance.
  """
  
  alias RubberDuck.Memory
  
  @doc """
  Search across all memory tiers for relevant information.
  Returns results ranked by relevance and recency.
  """
  def search_all_tiers(user_id, query, opts \\ []) do
    project_id = opts[:project_id]
    limit = opts[:limit] || 20
    semantic = opts[:semantic] || false
    
    # Perform parallel searches
    results = if semantic && opts[:query_embedding] do
      search_semantic_all_tiers(user_id, project_id, opts[:query_embedding], limit)
    else
      search_keyword_all_tiers(user_id, project_id, query, limit)
    end
    
    # Rank and merge results
    results
    |> merge_search_results()
    |> rank_results(query)
    |> Enum.take(limit)
  end
  
  @doc """
  Get context-aware memory for a specific session.
  Combines recent interactions with relevant summaries and knowledge.
  """
  def get_session_context(user_id, session_id, opts \\ []) do
    project_id = opts[:project_id]
    
    # Get recent interactions
    interactions = case Memory.get_recent_interactions(user_id, session_id) do
      {:ok, data} -> data
      _ -> []
    end
    
    # Get relevant summaries based on interaction topics
    summaries = get_relevant_summaries(user_id, interactions)
    
    # Get user profile
    profile = case Memory.get_user_profile(user_id) do
      {:ok, data} -> data
      _ -> nil
    end
    
    # Get relevant knowledge if project specified
    knowledge = if project_id do
      get_relevant_knowledge(user_id, project_id, interactions)
    else
      []
    end
    
    %{
      interactions: interactions,
      summaries: summaries,
      profile: profile,
      knowledge: knowledge,
      context_size: calculate_context_size(interactions, summaries, knowledge)
    }
  end
  
  @doc """
  Get memory timeline for a user.
  Shows memory evolution over time.
  """
  def get_memory_timeline(user_id, opts \\ []) do
    start_date = opts[:start_date] || DateTime.add(DateTime.utc_now(), -30, :day)
    end_date = opts[:end_date] || DateTime.utc_now()
    
    # Get all memory items within timeframe
    timeline = []
    
    # Add interactions
    interactions = case Memory.get_user_interactions(user_id) do
      {:ok, data} -> 
        data
        |> Enum.filter(&in_timeframe?(&1.inserted_at, start_date, end_date))
        |> Enum.map(&format_timeline_item(&1, :interaction))
      _ -> []
    end
    
    # Add summaries
    summaries = case Memory.get_user_summaries(user_id) do
      {:ok, data} ->
        data
        |> Enum.filter(&in_timeframe?(&1.created_at, start_date, end_date))
        |> Enum.map(&format_timeline_item(&1, :summary))
      _ -> []
    end
    
    # Combine and sort by timestamp
    (timeline ++ interactions ++ summaries)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end
  
  @doc """
  Get related memories based on a specific item.
  Uses semantic similarity and metadata matching.
  """
  def get_related_memories(user_id, memory_item, opts \\ []) do
    limit = opts[:limit] || 10
    
    # Extract search criteria from memory item
    search_terms = extract_search_terms(memory_item)
    tags = extract_tags(memory_item)
    
    # Search each tier for related items
    related = %{
      summaries: search_related_summaries(user_id, search_terms, tags),
      patterns: search_related_patterns(user_id, search_terms, memory_item),
      knowledge: search_related_knowledge(user_id, search_terms, tags, memory_item)
    }
    
    # Rank by relevance
    related
    |> flatten_results()
    |> rank_by_relevance(memory_item)
    |> Enum.take(limit)
  end
  
  # Private functions
  
  defp search_keyword_all_tiers(user_id, project_id, query, limit) do
    tasks = [
      Task.async(fn ->
        {:summaries, Memory.search_summaries(user_id, query, limit: limit)}
      end)
    ]
    
    tasks = if project_id do
      tasks ++ [
        Task.async(fn ->
          {:knowledge, Memory.search_knowledge_keyword(user_id, project_id, query, limit: limit)}
        end),
        Task.async(fn ->
          {:patterns, Memory.search_patterns_keyword(user_id, query, limit: limit)}
        end)
      ]
    else
      tasks ++ [
        Task.async(fn ->
          {:patterns, Memory.search_patterns_keyword(user_id, query, limit: limit)}
        end)
      ]
    end
    
    Task.await_many(tasks, 5000)
  end
  
  defp search_semantic_all_tiers(user_id, project_id, embedding, limit) do
    tasks = [
      Task.async(fn ->
        {:patterns, Memory.search_patterns_semantic(user_id, embedding, limit: limit)}
      end)
    ]
    
    tasks = if project_id do
      tasks ++ [
        Task.async(fn ->
          {:knowledge, Memory.search_knowledge_semantic(user_id, project_id, embedding, limit: limit)}
        end)
      ]
    else
      tasks
    end
    
    Task.await_many(tasks, 5000)
  end
  
  defp merge_search_results(results) do
    results
    |> Enum.reduce([], fn {_tier, {:ok, items}}, acc ->
      acc ++ items
    end)
  end
  
  defp rank_results(results, query) do
    query_terms = String.downcase(query) |> String.split()
    
    results
    |> Enum.map(fn item ->
      score = calculate_relevance_score(item, query_terms)
      {item, score}
    end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.map(&elem(&1, 0))
  end
  
  defp calculate_relevance_score(item, query_terms) do
    # Calculate score based on multiple factors
    content = get_searchable_content(item)
    
    # Term frequency score
    tf_score = query_terms
    |> Enum.map(fn term ->
      String.contains?(String.downcase(content), term)
    end)
    |> Enum.count(&(&1))
    |> Kernel./(length(query_terms))
    
    # Recency score
    recency_score = calculate_recency_score(item)
    
    # Usage/frequency score
    usage_score = get_usage_score(item)
    
    # Combined score
    tf_score * 0.5 + recency_score * 0.3 + usage_score * 0.2
  end
  
  defp get_searchable_content(item) do
    case item do
      %{content: content} -> content
      %{summary: summary} -> summary
      %{pattern_code: code} -> code
      _ -> ""
    end
  end
  
  defp calculate_recency_score(item) do
    timestamp = case item do
      %{last_accessed_at: ts} -> ts
      %{updated_at: ts} -> ts
      %{created_at: ts} -> ts
      _ -> DateTime.utc_now()
    end
    
    days_old = DateTime.diff(DateTime.utc_now(), timestamp, :day)
    :math.exp(-days_old / 30)  # Exponential decay
  end
  
  defp get_usage_score(item) do
    case item do
      %{usage_count: count} -> :math.log(count + 1) / 10
      %{frequency: freq} -> :math.log(freq + 1) / 10
      _ -> 0.1
    end
  end
  
  defp get_relevant_summaries(user_id, interactions) do
    # Extract topics from recent interactions
    topics = interactions
    |> Enum.map(&extract_topics/1)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.take(5)
    
    # Get summaries matching these topics
    topics
    |> Enum.flat_map(fn topic ->
      case Memory.search_summaries(user_id, topic, limit: 3) do
        {:ok, summaries} -> summaries
        _ -> []
      end
    end)
    |> Enum.uniq_by(& &1.id)
  end
  
  defp get_relevant_knowledge(user_id, project_id, interactions) do
    # Extract search terms from interactions
    terms = interactions
    |> Enum.map(&extract_search_terms/1)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.take(3)
    
    # Search knowledge base
    terms
    |> Enum.flat_map(fn term ->
      case Memory.search_knowledge_keyword(user_id, project_id, term, limit: 2) do
        {:ok, knowledge} -> knowledge
        _ -> []
      end
    end)
    |> Enum.uniq_by(& &1.id)
  end
  
  defp extract_topics(interaction) do
    # Simple topic extraction - in production use NLP
    interaction.content
    |> String.split()
    |> Enum.filter(&(String.length(&1) > 4))
    |> Enum.take(3)
  end
  
  defp extract_search_terms(item) do
    content = case item do
      %{content: c} -> c
      %{summary: s} -> s
      %{pattern_code: c} -> c
      _ -> ""
    end
    
    content
    |> String.split(~r/[\s,.:;!?]/)
    |> Enum.filter(&(String.length(&1) > 3))
    |> Enum.uniq()
  end
  
  defp extract_tags(item) do
    case item do
      %{tags: tags} -> tags
      %{metadata: %{tags: tags}} -> tags
      _ -> []
    end
  end
  
  defp in_timeframe?(timestamp, start_date, end_date) do
    DateTime.compare(timestamp, start_date) != :lt &&
    DateTime.compare(timestamp, end_date) != :gt
  end
  
  defp format_timeline_item(item, type) do
    %{
      id: item.id,
      type: type,
      timestamp: get_timestamp(item),
      content: get_summary_content(item),
      metadata: Map.get(item, :metadata, %{})
    }
  end
  
  defp get_timestamp(item) do
    case item do
      %{inserted_at: ts} -> ts
      %{created_at: ts} -> ts
      _ -> DateTime.utc_now()
    end
  end
  
  defp get_summary_content(item) do
    case item do
      %{content: c} -> String.slice(c, 0, 100) <> "..."
      %{summary: s} -> String.slice(s, 0, 100) <> "..."
      %{topic: t} -> t
      _ -> "Unknown"
    end
  end
  
  defp calculate_context_size(interactions, summaries, knowledge) do
    # Rough estimation of context size in tokens
    interaction_size = Enum.reduce(interactions, 0, fn i, acc ->
      acc + String.length(i.content || "")
    end)
    
    summary_size = Enum.reduce(summaries, 0, fn s, acc ->
      acc + String.length(s.summary || "")
    end)
    
    knowledge_size = Enum.reduce(knowledge, 0, fn k, acc ->
      acc + String.length(k.content || "")
    end)
    
    # Rough token estimation (4 chars per token)
    div(interaction_size + summary_size + knowledge_size, 4)
  end
  
  defp search_related_summaries(user_id, search_terms, _tags) do
    search_terms
    |> Enum.take(2)
    |> Enum.flat_map(fn term ->
      case Memory.search_summaries(user_id, term, limit: 3) do
        {:ok, results} -> results
        _ -> []
      end
    end)
    |> Enum.uniq_by(& &1.id)
  end
  
  defp search_related_patterns(user_id, search_terms, _memory_item) do
    search_terms
    |> Enum.take(2)
    |> Enum.flat_map(fn term ->
      case Memory.search_patterns_keyword(user_id, term, limit: 3) do
        {:ok, results} -> results
        _ -> []
      end
    end)
    |> Enum.uniq_by(& &1.id)
  end
  
  defp search_related_knowledge(user_id, search_terms, tags, memory_item) do
    project_id = get_project_id(memory_item)
    
    if project_id do
      search_terms
      |> Enum.take(2)
      |> Enum.flat_map(fn term ->
        case Memory.search_knowledge_keyword(user_id, project_id, term, tags: tags, limit: 3) do
          {:ok, results} -> results
          _ -> []
        end
      end)
      |> Enum.uniq_by(& &1.id)
    else
      []
    end
  end
  
  defp get_project_id(item) do
    case item do
      %{project_id: id} -> id
      %{metadata: %{project_id: id}} -> id
      _ -> nil
    end
  end
  
  defp flatten_results(results_map) do
    results_map
    |> Map.values()
    |> List.flatten()
  end
  
  defp rank_by_relevance(items, reference_item) do
    ref_terms = extract_search_terms(reference_item)
    ref_tags = extract_tags(reference_item)
    
    items
    |> Enum.map(fn item ->
      score = calculate_similarity_score(item, ref_terms, ref_tags)
      {item, score}
    end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.map(&elem(&1, 0))
  end
  
  defp calculate_similarity_score(item, ref_terms, ref_tags) do
    item_terms = extract_search_terms(item)
    item_tags = extract_tags(item)
    
    # Term overlap score
    term_overlap = length(ref_terms -- (ref_terms -- item_terms)) / max(length(ref_terms), 1)
    
    # Tag overlap score
    tag_overlap = length(ref_tags -- (ref_tags -- item_tags)) / max(length(ref_tags), 1)
    
    # Combined score
    term_overlap * 0.7 + tag_overlap * 0.3
  end
end
