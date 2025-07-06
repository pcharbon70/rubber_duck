defmodule RubberDuck.RAG.Reranker do
  @moduledoc """
  Document reranking system for the RAG pipeline.
  
  Implements various reranking strategies to improve retrieval quality:
  - Cross-encoder reranking using LLM
  - Diversity-aware reranking
  - MMR (Maximal Marginal Relevance)
  - Query-specific reranking
  """
  
  require Logger
  alias RubberDuck.LLM.Service, as: LLMService
  alias RubberDuck.Embeddings
  
  @type rerank_strategy :: :cross_encoder | :diversity | :mmr | :query_specific
  @type ranked_result :: %{
    content: String.t(),
    metadata: map(),
    score: float(),
    rerank_score: float(),
    rerank_reason: String.t()
  }
  
  @doc """
  Reranks a list of retrieval results using the specified strategy.
  
  Options:
  - strategy: :cross_encoder | :diversity | :mmr | :query_specific (default: :cross_encoder)
  - query: the original query used for retrieval
  - limit: number of results to return after reranking
  - diversity_threshold: for diversity reranking (default: 0.8)
  - lambda: for MMR reranking (default: 0.5)
  """
  @spec rerank(list(map()), keyword()) :: {:ok, [ranked_result()]} | {:error, term()}
  def rerank(results, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :cross_encoder)
    
    case strategy do
      :cross_encoder -> cross_encoder_rerank(results, opts)
      :diversity -> diversity_rerank(results, opts)
      :mmr -> mmr_rerank(results, opts)
      :query_specific -> query_specific_rerank(results, opts)
      _ -> {:error, :invalid_strategy}
    end
  end
  
  @doc """
  Cross-encoder reranking using an LLM to score query-document pairs.
  
  More accurate than bi-encoder (embedding) similarity but slower.
  """
  @spec cross_encoder_rerank(list(map()), keyword()) :: {:ok, [ranked_result()]} | {:error, term()}
  def cross_encoder_rerank(results, opts) do
    query = Keyword.fetch!(opts, :query)
    limit = Keyword.get(opts, :limit, 10)
    
    # Score each result with the LLM
    scored_results = results
    |> Enum.take(20)  # Limit to top 20 for efficiency
    |> Enum.map(fn result ->
      Task.async(fn ->
        score_with_llm(query, result)
      end)
    end)
    |> Task.await_many(10_000)
    
    # Sort by new scores and take top results
    reranked = scored_results
    |> Enum.sort_by(& &1.rerank_score, :desc)
    |> Enum.take(limit)
    
    {:ok, reranked}
  end
  
  @doc """
  Diversity-aware reranking to reduce redundancy in results.
  
  Penalizes documents that are too similar to already selected ones.
  """
  @spec diversity_rerank(list(map()), keyword()) :: {:ok, [ranked_result()]} | {:error, term()}
  def diversity_rerank(results, opts) do
    limit = Keyword.get(opts, :limit, 10)
    diversity_threshold = Keyword.get(opts, :diversity_threshold, 0.8)
    
    # Greedy selection with diversity penalty
    {reranked, _} = Enum.reduce_while(results, {[], []}, fn result, {selected, embeddings} ->
      if length(selected) >= limit do
        {:halt, {selected, embeddings}}
      else
        # Check similarity with already selected documents
        result_embedding = get_result_embedding(result)
        
        is_diverse = Enum.all?(embeddings, fn selected_embedding ->
          similarity = Embeddings.Service.cosine_similarity(result_embedding, selected_embedding)
          similarity < diversity_threshold
        end)
        
        if is_diverse do
          enhanced_result = result
          |> Map.put(:rerank_score, result.score)
          |> Map.put(:rerank_reason, "Diverse content")
          
          {:cont, {selected ++ [enhanced_result], embeddings ++ [result_embedding]}}
        else
          {:cont, {selected, embeddings}}
        end
      end
    end)
    
    {:ok, reranked}
  end
  
  @doc """
  Maximal Marginal Relevance (MMR) reranking.
  
  Balances relevance to the query with diversity among results.
  """
  @spec mmr_rerank(list(map()), keyword()) :: {:ok, [ranked_result()]} | {:error, term()}
  def mmr_rerank(results, opts) do
    query = Keyword.fetch!(opts, :query)
    limit = Keyword.get(opts, :limit, 10)
    lambda = Keyword.get(opts, :lambda, 0.5)
    
    with {:ok, query_embedding} <- Embeddings.Service.generate(query) do
      # Initialize with empty selected set
      {reranked, _} = Enum.reduce_while(results, {[], results}, fn _, {selected, remaining} ->
        if length(selected) >= limit || length(remaining) == 0 do
          {:halt, {selected, remaining}}
        else
          # Calculate MMR score for each remaining document
          mmr_scores = Enum.map(remaining, fn doc ->
            doc_embedding = get_result_embedding(doc)
            
            # Relevance to query
            query_sim = Embeddings.Service.cosine_similarity(query_embedding, doc_embedding)
            
            # Max similarity to already selected documents
            max_doc_sim = if length(selected) > 0 do
              selected
              |> Enum.map(fn sel_doc ->
                sel_embedding = get_result_embedding(sel_doc)
                Embeddings.Service.cosine_similarity(doc_embedding, sel_embedding)
              end)
              |> Enum.max()
            else
              0.0
            end
            
            # MMR score
            mmr_score = lambda * query_sim - (1 - lambda) * max_doc_sim
            
            {doc, mmr_score}
          end)
          
          # Select document with highest MMR score
          {best_doc, best_score} = Enum.max_by(mmr_scores, fn {_, score} -> score end)
          
          enhanced_doc = best_doc
          |> Map.put(:rerank_score, best_score)
          |> Map.put(:rerank_reason, "MMR selection")
          
          new_remaining = Enum.reject(remaining, fn doc -> doc == best_doc end)
          
          {:cont, {selected ++ [enhanced_doc], new_remaining}}
        end
      end)
      
      {:ok, reranked}
    end
  end
  
  @doc """
  Query-specific reranking based on query type and intent.
  
  Applies different ranking strategies based on the detected query type.
  """
  @spec query_specific_rerank(list(map()), keyword()) :: {:ok, [ranked_result()]} | {:error, term()}
  def query_specific_rerank(results, opts) do
    query = Keyword.fetch!(opts, :query)
    limit = Keyword.get(opts, :limit, 10)
    
    # Detect query type
    query_type = detect_query_type(query)
    
    # Apply appropriate reranking based on query type
    reranked = case query_type do
      :factual ->
        # Prioritize authoritative sources and exact matches
        rerank_factual_query(results, query)
      
      :exploratory ->
        # Prioritize diversity and coverage
        {:ok, diverse_results} = diversity_rerank(results, opts)
        diverse_results
      
      :implementation ->
        # Prioritize code examples and practical content
        rerank_implementation_query(results, query)
      
      _ ->
        # Default to score-based ranking
        results
        |> Enum.map(fn r -> 
          Map.merge(r, %{rerank_score: r.score, rerank_reason: "Default ranking"})
        end)
    end
    |> Enum.take(limit)
    
    {:ok, reranked}
  end
  
  # Private functions
  
  defp score_with_llm(query, result) do
    prompt = """
    Rate the relevance of the following document to the query on a scale of 0-10.
    Consider:
    - Direct answer to the query
    - Contextual relevance
    - Information quality
    
    Query: #{query}
    
    Document:
    #{String.slice(result.content, 0, 500)}
    
    Provide only a numeric score between 0 and 10.
    """
    
    case LLMService.completion(%{
      model: "claude-3-haiku-20240307",
      prompt: prompt,
      max_tokens: 10
    }) do
      {:ok, response} ->
        score = parse_llm_score(response.content)
        
        result
        |> Map.put(:rerank_score, score / 10.0)
        |> Map.put(:rerank_reason, "LLM cross-encoder score: #{score}/10")
      
      _ ->
        # Fallback to original score
        result
        |> Map.put(:rerank_score, result.score)
        |> Map.put(:rerank_reason, "Failed to score with LLM")
    end
  end
  
  defp parse_llm_score(response) do
    case Float.parse(String.trim(response)) do
      {score, _} when score >= 0 and score <= 10 -> score
      _ -> 5.0  # Default middle score
    end
  end
  
  defp get_result_embedding(result) do
    # Try to get embedding from metadata or generate if needed
    case get_in(result, [:metadata, :embedding]) do
      nil ->
        case Embeddings.Service.generate(result.content) do
          {:ok, embedding} -> embedding
          _ -> []
        end
      
      embedding -> embedding
    end
  end
  
  defp detect_query_type(query) do
    query_lower = String.downcase(query)
    
    cond do
      # Factual queries
      String.contains?(query_lower, ["what is", "define", "explain", "how does"]) ->
        :factual
      
      # Implementation queries
      String.contains?(query_lower, ["how to", "implement", "code", "example"]) ->
        :implementation
      
      # Exploratory queries
      String.contains?(query_lower, ["options", "alternatives", "compare", "vs"]) ->
        :exploratory
      
      true ->
        :general
    end
  end
  
  defp rerank_factual_query(results, query) do
    query_terms = String.split(String.downcase(query), ~r/\s+/)
    
    results
    |> Enum.map(fn result ->
      content_lower = String.downcase(result.content)
      
      # Calculate exact match score
      exact_matches = Enum.count(query_terms, fn term ->
        String.contains?(content_lower, term)
      end)
      
      # Check for definition patterns
      has_definition = String.contains?(content_lower, ["is a", "refers to", "defined as"])
      
      # Calculate rerank score
      rerank_score = result.score * 0.6 + 
                      (exact_matches / length(query_terms)) * 0.3 +
                      (if has_definition, do: 0.1, else: 0)
      
      result
      |> Map.put(:rerank_score, rerank_score)
      |> Map.put(:rerank_reason, "Factual query ranking")
    end)
    |> Enum.sort_by(& &1.rerank_score, :desc)
  end
  
  defp rerank_implementation_query(results, _query) do
    results
    |> Enum.map(fn result ->
      content = result.content
      
      # Check for code indicators
      has_code = String.contains?(content, ["```", "def ", "defmodule", "function", "=>"])
      has_example = String.contains?(String.downcase(content), ["example", "usage", "sample"])
      has_steps = String.contains?(content, ["1.", "2.", "step", "first", "then"])
      
      # Calculate implementation score
      impl_score = 0.0
      impl_score = if has_code, do: impl_score + 0.4, else: impl_score
      impl_score = if has_example, do: impl_score + 0.3, else: impl_score
      impl_score = if has_steps, do: impl_score + 0.2, else: impl_score
      
      rerank_score = result.score * 0.4 + impl_score * 0.6
      
      result
      |> Map.put(:rerank_score, rerank_score)
      |> Map.put(:rerank_reason, "Implementation query ranking")
    end)
    |> Enum.sort_by(& &1.rerank_score, :desc)
  end
end