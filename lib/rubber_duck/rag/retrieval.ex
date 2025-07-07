defmodule RubberDuck.RAG.Retrieval do
  @moduledoc """
  Advanced retrieval strategies for the RAG pipeline.

  Implements multiple retrieval approaches including:
  - Semantic similarity search using embeddings
  - Hybrid search combining semantic and keyword matching
  - Contextual retrieval considering conversation history
  - Multi-hop retrieval for complex queries
  """

  require Logger
  alias RubberDuck.RAG.VectorStore
  alias RubberDuck.Embeddings

  @type retrieval_strategy :: :semantic | :hybrid | :contextual | :multi_hop
  @type retrieval_result :: %{
          content: String.t(),
          metadata: map(),
          score: float(),
          source: atom()
        }

  @default_limit 10
  @default_threshold 0.7

  @doc """
  Retrieves relevant documents based on a query and strategy.

  Options:
  - strategy: :semantic | :hybrid | :contextual | :multi_hop (default: :hybrid)
  - limit: number of results to return (default: 10)
  - threshold: minimum similarity score (default: 0.7)
  - context: additional context for retrieval
  - project_id: filter by project
  """
  @spec retrieve(String.t(), keyword()) :: {:ok, [retrieval_result()]} | {:error, term()}
  def retrieve(query, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :hybrid)

    case strategy do
      :semantic -> semantic_retrieval(query, opts)
      :hybrid -> hybrid_retrieval(query, opts)
      :contextual -> contextual_retrieval(query, opts)
      :multi_hop -> multi_hop_retrieval(query, opts)
      _ -> {:error, :invalid_strategy}
    end
  end

  @doc """
  Performs semantic retrieval using vector embeddings.

  Uses cosine similarity to find the most relevant documents.
  """
  @spec semantic_retrieval(String.t(), keyword()) :: {:ok, [retrieval_result()]} | {:error, term()}
  def semantic_retrieval(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    threshold = Keyword.get(opts, :threshold, @default_threshold)
    project_id = Keyword.get(opts, :project_id)

    with {:ok, query_embedding} <- Embeddings.Service.generate(query),
         {:ok, results} <-
           VectorStore.similarity_search(query_embedding,
             limit: limit,
             threshold: threshold,
             project_id: project_id
           ) do
      enhanced_results =
        Enum.map(results, fn result ->
          Map.put(result, :source, :semantic)
        end)

      {:ok, enhanced_results}
    end
  end

  @doc """
  Performs hybrid retrieval combining semantic and keyword search.

  Merges results from both approaches with reranking.
  """
  @spec hybrid_retrieval(String.t(), keyword()) :: {:ok, [retrieval_result()]} | {:error, term()}
  def hybrid_retrieval(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    _project_id = Keyword.get(opts, :project_id)

    # Run both searches in parallel
    tasks = [
      Task.async(fn ->
        semantic_retrieval(query, Keyword.put(opts, :limit, limit * 2))
      end),
      Task.async(fn ->
        keyword_retrieval(query, Keyword.put(opts, :limit, limit * 2))
      end)
    ]

    case Task.await_many(tasks, 5000) do
      [{:ok, semantic_results}, {:ok, keyword_results}] ->
        # Merge and rerank results
        merged =
          merge_retrieval_results(semantic_results, keyword_results)
          |> apply_reciprocal_rank_fusion()
          |> Enum.take(limit)

        {:ok, merged}

      _ ->
        {:error, :retrieval_failed}
    end
  end

  @doc """
  Performs contextual retrieval considering conversation history.

  Enhances the query with context from recent interactions.
  """
  @spec contextual_retrieval(String.t(), keyword()) :: {:ok, [retrieval_result()]} | {:error, term()}
  def contextual_retrieval(query, opts \\ []) do
    context = Keyword.get(opts, :context, %{})
    limit = Keyword.get(opts, :limit, @default_limit)

    # Enhance query with context
    enhanced_query = enhance_query_with_context(query, context)

    # Use hybrid retrieval with enhanced query
    with {:ok, results} <- hybrid_retrieval(enhanced_query, opts) do
      # Re-score based on contextual relevance
      rescored =
        rescore_with_context(results, query, context)
        |> Enum.take(limit)

      {:ok, rescored}
    end
  end

  @doc """
  Performs multi-hop retrieval for complex queries.

  Iteratively retrieves and expands the search based on initial results.
  """
  @spec multi_hop_retrieval(String.t(), keyword()) :: {:ok, [retrieval_result()]} | {:error, term()}
  def multi_hop_retrieval(query, opts \\ []) do
    max_hops = Keyword.get(opts, :max_hops, 2)
    limit = Keyword.get(opts, :limit, @default_limit)

    # First hop
    with {:ok, initial_results} <- hybrid_retrieval(query, Keyword.put(opts, :limit, limit * 2)) do
      # Extract entities and concepts from initial results
      expanded_queries = extract_expansion_queries(initial_results, query)

      # Perform additional hops if needed
      all_results =
        if max_hops > 1 && length(expanded_queries) > 0 do
          hop_results = perform_additional_hops(expanded_queries, opts, max_hops - 1)
          merge_hop_results([initial_results | hop_results])
        else
          initial_results
        end

      # Final ranking
      final_results =
        all_results
        |> Enum.uniq_by(& &1.content)
        |> rescore_multi_hop(query)
        |> Enum.take(limit)

      {:ok, final_results}
    end
  end

  # Private functions

  defp keyword_retrieval(query, opts) do
    # Simple keyword search implementation
    # In production, this would use more sophisticated text search
    VectorStore.search(query, Keyword.put(opts, :strategy, :keyword))
  end

  defp merge_retrieval_results(semantic_results, keyword_results) do
    # Group by content to avoid duplicates
    all_results = semantic_results ++ keyword_results

    all_results
    |> Enum.group_by(& &1.content)
    |> Enum.map(fn {_content, duplicates} ->
      # Merge scores and metadata
      merged =
        Enum.reduce(duplicates, %{}, fn result, acc ->
          acc
          |> Map.put(:content, result.content)
          |> Map.update(:metadata, result.metadata, &Map.merge(&1, result.metadata))
          |> Map.update(:scores, %{}, fn scores ->
            Map.put(scores, result.source, result.score)
          end)
          |> Map.put(:sources, Enum.uniq([result.source | Map.get(acc, :sources, [])]))
        end)

      # Calculate combined score
      Map.put(merged, :score, calculate_combined_score(merged.scores))
    end)
  end

  defp apply_reciprocal_rank_fusion(results) do
    # Reciprocal Rank Fusion (RRF) for combining rankings
    # Standard RRF constant
    k = 60

    results
    |> Enum.with_index(1)
    |> Enum.map(fn {result, rank} ->
      rrf_score = 1.0 / (k + rank)
      Map.update(result, :score, rrf_score, fn score -> score * 0.7 + rrf_score * 0.3 end)
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  defp enhance_query_with_context(query, context) do
    # Extract key terms from context
    context_terms = extract_context_terms(context)

    if length(context_terms) > 0 do
      "#{query} #{Enum.join(context_terms, " ")}"
    else
      query
    end
  end

  defp extract_context_terms(context) do
    # Extract relevant terms from conversation history
    history = Map.get(context, :conversation_history, [])

    history
    # Last 3 messages
    |> Enum.take(3)
    |> Enum.flat_map(fn message ->
      message
      |> String.split(~r/\s+/)
      |> Enum.filter(&important_term?/1)
    end)
    |> Enum.uniq()
    |> Enum.take(5)
  end

  defp important_term?(term) do
    # Simple heuristic for important terms
    String.length(term) > 3 && !String.contains?(term, ["the", "and", "or", "is", "are"])
  end

  defp rescore_with_context(results, _query, context) do
    # Re-score based on contextual relevance
    recent_topics = Map.get(context, :recent_topics, [])

    Enum.map(results, fn result ->
      context_boost = calculate_context_boost(result, recent_topics)
      Map.update(result, :score, 0, fn score -> score * (1 + context_boost) end)
    end)
    |> Enum.sort_by(& &1.score, :desc)
  end

  defp calculate_context_boost(result, recent_topics) do
    # Calculate boost based on topic overlap
    content_words = String.split(String.downcase(result.content), ~r/\s+/)

    overlap_count =
      Enum.count(recent_topics, fn topic ->
        Enum.any?(content_words, &String.contains?(&1, String.downcase(topic)))
      end)

    min(0.5, overlap_count * 0.1)
  end

  defp extract_expansion_queries(results, original_query) do
    # Extract entities and concepts for query expansion
    results
    |> Enum.take(3)
    |> Enum.flat_map(fn result ->
      extract_key_phrases(result.content, original_query)
    end)
    |> Enum.uniq()
    |> Enum.take(3)
  end

  defp extract_key_phrases(content, original_query) do
    # Simple key phrase extraction
    # In production, use NLP libraries or LLM for better extraction
    words = String.split(String.downcase(content), ~r/\s+/)
    query_words = String.split(String.downcase(original_query), ~r/\s+/)

    words
    |> Enum.reject(fn word ->
      String.length(word) < 4 || Enum.member?(query_words, word)
    end)
    |> Enum.take(2)
  end

  defp perform_additional_hops(queries, opts, remaining_hops) do
    queries
    |> Enum.map(fn query ->
      Task.async(fn ->
        case hybrid_retrieval(query, opts) do
          {:ok, results} -> results
          _ -> []
        end
      end)
    end)
    |> Task.await_many(5000)
    |> List.flatten()
    |> then(fn results ->
      if remaining_hops > 0 && length(results) > 0 do
        new_queries = extract_expansion_queries(results, "")
        [results | perform_additional_hops(new_queries, opts, remaining_hops - 1)]
      else
        [results]
      end
    end)
  end

  defp merge_hop_results(hop_results) do
    hop_results
    |> List.flatten()
    |> Enum.uniq_by(& &1.content)
  end

  defp rescore_multi_hop(results, original_query) do
    # Re-score based on relevance to original query
    with {:ok, query_embedding} <- Embeddings.Service.generate(original_query) do
      results
      |> Enum.map(fn result ->
        # Calculate similarity to original query
        result_embedding = Map.get(result.metadata, :embedding, [])

        similarity =
          if length(result_embedding) > 0 do
            Embeddings.Service.cosine_similarity(query_embedding, result_embedding)
          else
            result.score
          end

        Map.put(result, :score, similarity)
      end)
      |> Enum.sort_by(& &1.score, :desc)
    else
      _ -> Enum.sort_by(results, & &1.score, :desc)
    end
  end

  defp calculate_combined_score(scores) do
    # Weighted combination of different score types
    semantic_weight = 0.7
    keyword_weight = 0.3

    semantic_score = Map.get(scores, :semantic, 0)
    keyword_score = Map.get(scores, :keyword, 0)

    semantic_score * semantic_weight + keyword_score * keyword_weight
  end
end
