defmodule RubberDuck.RAG.AugmentedContext do
  @moduledoc """
  Data structure representing augmented context for generation.
  
  Contains processed and optimized documents along with summary
  information and metadata for efficient LLM consumption.
  """

  defstruct [
    :query_id,
    :documents,
    :summary,
    :metadata,
    :total_tokens,
    :optimization_applied,
    :created_at,
    :quality_score,
    :token_distribution
  ]

  @type t :: %__MODULE__{
    query_id: String.t(),
    documents: list(RubberDuck.RAG.RetrievedDocument.t()),
    summary: String.t(),
    metadata: map(),
    total_tokens: integer(),
    optimization_applied: list(atom()),
    created_at: DateTime.t(),
    quality_score: float() | nil,
    token_distribution: map()
  }

  alias RubberDuck.RAG.RetrievedDocument

  @doc """
  Creates a new augmented context.
  """
  def new(attrs) do
    documents = attrs[:documents] || []
    
    %__MODULE__{
      query_id: attrs[:query_id] || generate_id(),
      documents: documents,
      summary: attrs[:summary] || "",
      metadata: attrs[:metadata] || %{},
      total_tokens: attrs[:total_tokens] || calculate_total_tokens(documents),
      optimization_applied: attrs[:optimization_applied] || [],
      created_at: DateTime.utc_now(),
      quality_score: attrs[:quality_score],
      token_distribution: attrs[:token_distribution] || calculate_token_distribution(documents)
    }
  end

  @doc """
  Adds a document to the context.
  """
  def add_document(context, document) do
    updated_docs = context.documents ++ [document]
    
    %{context |
      documents: updated_docs,
      total_tokens: context.total_tokens + document.size_tokens,
      token_distribution: update_token_distribution(context.token_distribution, document)
    }
  end

  @doc """
  Removes documents below a relevance threshold.
  """
  def filter_by_relevance(context, min_score) do
    filtered_docs = Enum.filter(context.documents, fn doc ->
      RetrievedDocument.effective_score(doc) >= min_score
    end)
    
    %{context |
      documents: filtered_docs,
      total_tokens: calculate_total_tokens(filtered_docs),
      token_distribution: calculate_token_distribution(filtered_docs),
      optimization_applied: [:relevance_filter | context.optimization_applied]
    }
  end

  @doc """
  Sorts documents by relevance score.
  """
  def sort_by_relevance(context) do
    sorted_docs = Enum.sort_by(context.documents, &RetrievedDocument.effective_score/1, :desc)
    
    %{context | documents: sorted_docs}
  end

  @doc """
  Truncates context to fit within token limit.
  """
  def fit_to_limit(context, max_tokens) do
    if context.total_tokens <= max_tokens do
      context
    else
      {kept_docs, _} = Enum.reduce(context.documents, {[], 0}, fn doc, {acc, tokens} ->
        if tokens + doc.size_tokens <= max_tokens do
          {[doc | acc], tokens + doc.size_tokens}
        else
          # Try to fit a truncated version
          remaining = max_tokens - tokens
          if remaining > 100 do  # Minimum useful size
            truncated = RetrievedDocument.truncate(doc, remaining)
            {[truncated | acc], tokens + truncated.size_tokens}
          else
            {acc, tokens}
          end
        end
      end)
      
      kept_docs = Enum.reverse(kept_docs)
      
      %{context |
        documents: kept_docs,
        total_tokens: calculate_total_tokens(kept_docs),
        token_distribution: calculate_token_distribution(kept_docs),
        optimization_applied: [:token_limit | context.optimization_applied]
      }
    end
  end

  @doc """
  Generates a context summary.
  """
  def generate_summary(context) do
    doc_count = length(context.documents)
    sources = context.documents
    |> Enum.map(& &1.source)
    |> Enum.uniq()
    |> Enum.join(", ")
    
    avg_relevance = if doc_count > 0 do
      total = Enum.sum(Enum.map(context.documents, &RetrievedDocument.effective_score/1))
      Float.round(total / doc_count, 2)
    else
      0.0
    end
    
    summary = """
    Context Summary:
    - Documents: #{doc_count}
    - Total tokens: #{context.total_tokens}
    - Sources: #{sources}
    - Avg relevance: #{avg_relevance}
    - Optimizations: #{Enum.join(context.optimization_applied, ", ")}
    """
    
    %{context | summary: summary}
  end

  @doc """
  Converts context to prompt format.
  """
  def to_prompt_format(context, template \\ :default) do
    case template do
      :default ->
        build_default_prompt(context)
        
      :numbered ->
        build_numbered_prompt(context)
        
      :structured ->
        build_structured_prompt(context)
        
      custom when is_function(custom) ->
        custom.(context)
    end
  end

  @doc """
  Calculates quality score for the context.
  """
  def calculate_quality_score(context) do
    if length(context.documents) == 0 do
      0.0
    else
      # Factors: relevance, coverage, diversity
      relevance_score = calculate_avg_relevance(context)
      coverage_score = calculate_coverage_score(context)
      diversity_score = calculate_diversity_score(context)
      
      # Weighted average
      score = relevance_score * 0.5 + coverage_score * 0.3 + diversity_score * 0.2
      
      %{context | quality_score: Float.round(score, 2)}
    end
  end

  @doc """
  Validates context for generation readiness.
  """
  def valid?(context) do
    context.total_tokens > 0 and
    length(context.documents) > 0 and
    context.query_id != nil
  end

  @doc """
  Returns context statistics.
  """
  def stats(context) do
    %{
      document_count: length(context.documents),
      total_tokens: context.total_tokens,
      avg_tokens_per_doc: if(length(context.documents) > 0, 
        do: div(context.total_tokens, length(context.documents)), 
        else: 0),
      sources: context.documents |> Enum.map(& &1.source) |> Enum.uniq() |> length(),
      quality_score: context.quality_score,
      optimizations: context.optimization_applied,
      token_distribution: context.token_distribution
    }
  end

  # Private functions

  defp generate_id do
    "ctx_" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp calculate_total_tokens(documents) do
    Enum.sum(Enum.map(documents, & &1.size_tokens))
  end

  defp calculate_token_distribution(documents) do
    documents
    |> Enum.group_by(& &1.source)
    |> Map.new(fn {source, docs} ->
      {source, Enum.sum(Enum.map(docs, & &1.size_tokens))}
    end)
  end

  defp update_token_distribution(distribution, document) do
    Map.update(distribution, document.source, document.size_tokens, 
      &(&1 + document.size_tokens))
  end

  defp build_default_prompt(context) do
    doc_sections = Enum.map(context.documents, fn doc ->
      RetrievedDocument.to_context_format(doc)
    end)
    
    """
    Based on the following context, please provide a comprehensive response.

    CONTEXT:
    #{Enum.join(doc_sections, "\n---\n")}
    
    Please answer based on the above context.
    """
  end

  defp build_numbered_prompt(context) do
    doc_sections = context.documents
    |> Enum.with_index(1)
    |> Enum.map(fn {doc, idx} ->
      "[#{idx}] #{RetrievedDocument.to_context_format(doc)}"
    end)
    
    """
    Based on the following numbered context documents, please provide a comprehensive response.

    CONTEXT DOCUMENTS:
    #{Enum.join(doc_sections, "\n\n")}
    
    Please answer based on the above context, citing document numbers when relevant.
    """
  end

  defp build_structured_prompt(context) do
    sources = context.documents
    |> Enum.group_by(& &1.source)
    |> Enum.map(fn {source, docs} ->
      content = Enum.map(docs, & &1.content) |> Enum.join("\n\n")
      "## #{source}\n#{content}"
    end)
    
    """
    Based on the following structured context from multiple sources:

    #{Enum.join(sources, "\n\n")}
    
    Please synthesize the information from all sources to provide a comprehensive response.
    """
  end

  defp calculate_avg_relevance(context) do
    scores = Enum.map(context.documents, &RetrievedDocument.effective_score/1)
    
    if length(scores) > 0 do
      Enum.sum(scores) / length(scores)
    else
      0.0
    end
  end

  defp calculate_coverage_score(context) do
    # Higher score for more diverse sources and document count
    doc_count_score = min(length(context.documents) / 10, 1.0)
    source_diversity = length(Enum.uniq(Enum.map(context.documents, & &1.source))) / 5
    
    (doc_count_score + min(source_diversity, 1.0)) / 2
  end

  defp calculate_diversity_score(context) do
    # Measure content diversity using simple heuristic
    if length(context.documents) < 2 do
      0.0
    else
      # Calculate pairwise similarities
      similarities = for doc1 <- context.documents,
                        doc2 <- context.documents,
                        doc1.id < doc2.id do
        RetrievedDocument.similarity(doc1, doc2)
      end
      
      if length(similarities) > 0 do
        avg_similarity = Enum.sum(similarities) / length(similarities)
        1.0 - avg_similarity  # Higher diversity = lower similarity
      else
        0.5
      end
    end
  end
end