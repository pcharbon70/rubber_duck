defmodule RubberDuck.RAG.RetrievedDocument do
  @moduledoc """
  Data structure representing a document retrieved during RAG processing.
  
  Contains the document content, metadata, relevance scoring, and
  embedding information needed for augmentation and generation.
  """

  defstruct [
    :id,
    :content,
    :metadata,
    :relevance_score,
    :source,
    :embeddings,
    :size_tokens,
    :retrieved_at,
    :chunk_index,
    :total_chunks,
    :highlights,
    :rerank_score
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    content: String.t(),
    metadata: map(),
    relevance_score: float(),
    source: String.t(),
    embeddings: list(float()) | nil,
    size_tokens: integer(),
    retrieved_at: DateTime.t(),
    chunk_index: integer() | nil,
    total_chunks: integer() | nil,
    highlights: list(String.t()),
    rerank_score: float() | nil
  }

  @doc """
  Creates a new retrieved document with validation.
  """
  def new(attrs) do
    content = attrs[:content] || ""
    
    %__MODULE__{
      id: attrs[:id] || generate_id(),
      content: content,
      metadata: attrs[:metadata] || %{},
      relevance_score: validate_score(attrs[:relevance_score] || 0.5),
      source: attrs[:source] || "unknown",
      embeddings: attrs[:embeddings],
      size_tokens: attrs[:size_tokens] || estimate_tokens(content),
      retrieved_at: attrs[:retrieved_at] || DateTime.utc_now(),
      chunk_index: attrs[:chunk_index],
      total_chunks: attrs[:total_chunks],
      highlights: attrs[:highlights] || [],
      rerank_score: attrs[:rerank_score]
    }
  end

  @doc """
  Updates the relevance score of the document.
  """
  def update_score(document, new_score) do
    %{document | relevance_score: validate_score(new_score)}
  end

  @doc """
  Updates the rerank score after reranking.
  """
  def update_rerank_score(document, rerank_score) do
    %{document | rerank_score: validate_score(rerank_score)}
  end

  @doc """
  Returns the effective score (rerank if available, otherwise relevance).
  """
  def effective_score(document) do
    document.rerank_score || document.relevance_score
  end

  @doc """
  Adds highlights to the document.
  """
  def add_highlights(document, highlights) when is_list(highlights) do
    %{document | highlights: document.highlights ++ highlights}
  end

  @doc """
  Truncates document content to fit within token limit.
  """
  def truncate(document, max_tokens) do
    if document.size_tokens <= max_tokens do
      document
    else
      truncated_content = truncate_to_tokens(document.content, max_tokens)
      
      %{document |
        content: truncated_content,
        size_tokens: max_tokens,
        metadata: Map.put(document.metadata, :truncated, true)
      }
    end
  end

  @doc """
  Checks if the document is a chunk of a larger document.
  """
  def chunked?(document) do
    document.chunk_index != nil and document.total_chunks != nil
  end

  @doc """
  Checks if this is the first chunk.
  """
  def first_chunk?(document) do
    chunked?(document) and document.chunk_index == 0
  end

  @doc """
  Checks if this is the last chunk.
  """
  def last_chunk?(document) do
    chunked?(document) and document.chunk_index == document.total_chunks - 1
  end

  @doc """
  Merges metadata from another document.
  """
  def merge_metadata(document, other_metadata) when is_map(other_metadata) do
    %{document | metadata: Map.merge(document.metadata, other_metadata)}
  end

  @doc """
  Creates a summary representation of the document.
  """
  def summary(document) do
    %{
      id: document.id,
      source: document.source,
      relevance_score: document.relevance_score,
      rerank_score: document.rerank_score,
      size_tokens: document.size_tokens,
      metadata: document.metadata,
      content_preview: String.slice(document.content, 0, 200) <> "..."
    }
  end

  @doc """
  Converts document to format suitable for context injection.
  """
  def to_context_format(document) do
    metadata_str = if map_size(document.metadata) > 0 do
      "Source: #{document.source} | #{format_metadata(document.metadata)}\n"
    else
      "Source: #{document.source}\n"
    end
    
    highlights_str = if document.highlights != [] do
      "\nKey points:\n" <> Enum.join(document.highlights, "\n- ")
    else
      ""
    end
    
    """
    #{metadata_str}
    #{document.content}
    #{highlights_str}
    """
  end

  @doc """
  Calculates similarity between two documents.
  """
  def similarity(doc1, doc2) do
    cond do
      doc1.embeddings && doc2.embeddings ->
        cosine_similarity(doc1.embeddings, doc2.embeddings)
        
      doc1.content == doc2.content ->
        1.0
        
      true ->
        text_similarity(doc1.content, doc2.content)
    end
  end

  # Private functions

  defp generate_id do
    "doc_" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp validate_score(score) when is_number(score) and score >= 0 and score <= 1 do
    score / 1  # Ensure float
  end
  defp validate_score(_), do: 0.5

  defp estimate_tokens(content) when is_binary(content) do
    # Rough estimation: 1 token ≈ 4 characters
    div(String.length(content), 4)
  end
  defp estimate_tokens(_), do: 0

  defp truncate_to_tokens(content, max_tokens) do
    # Rough approximation
    max_chars = max_tokens * 4
    
    if String.length(content) <= max_chars do
      content
    else
      # Try to truncate at sentence boundary
      truncated = String.slice(content, 0, max_chars)
      
      # Find last sentence end
      case Regex.scan(~r/[.!?]\s/, truncated) do
        [] -> truncated <> "..."
        matches ->
          {_, last_pos} = List.last(matches) |> hd()
          String.slice(content, 0, last_pos) <> "..."
      end
    end
  end

  defp format_metadata(metadata) do
    metadata
    |> Enum.reject(fn {_k, v} -> v == nil or v == "" end)
    |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
    |> Enum.join(" | ")
  end

  defp cosine_similarity(vec1, vec2) do
    if length(vec1) != length(vec2) do
      0.0
    else
      dot_product = Enum.zip(vec1, vec2)
      |> Enum.map(fn {a, b} -> a * b end)
      |> Enum.sum()
      
      mag1 = :math.sqrt(Enum.sum(Enum.map(vec1, &(&1 * &1))))
      mag2 = :math.sqrt(Enum.sum(Enum.map(vec2, &(&1 * &1))))
      
      if mag1 > 0 and mag2 > 0 do
        dot_product / (mag1 * mag2)
      else
        0.0
      end
    end
  end

  defp text_similarity(text1, text2) do
    # Simple Jaccard similarity on words
    words1 = text1 |> String.downcase() |> String.split() |> MapSet.new()
    words2 = text2 |> String.downcase() |> String.split() |> MapSet.new()
    
    intersection = MapSet.intersection(words1, words2) |> MapSet.size()
    union = MapSet.union(words1, words2) |> MapSet.size()
    
    if union > 0 do
      intersection / union
    else
      0.0
    end
  end
end