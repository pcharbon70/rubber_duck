defmodule RubberDuck.Context.ContextEntry do
  @moduledoc """
  Data structure representing a single context entry.
  
  Context entries are the atomic units of context that are collected from
  various sources, prioritized, and optimized before being provided to LLMs.
  Each entry contains the actual content, metadata for scoring and filtering,
  and optimization state.
  """

  defstruct [
    :id,
    :source,
    :content,
    :metadata,
    :relevance_score,
    :timestamp,
    :ttl,
    :size_tokens,
    :compressed,
    :summarized,
    :original_content,
    :hash
  ]

  @type t :: %__MODULE__{
    id: String.t(),
    source: String.t(),
    content: String.t() | map(),
    metadata: map(),
    relevance_score: float(),
    timestamp: DateTime.t(),
    ttl: integer() | nil,
    size_tokens: integer(),
    compressed: boolean(),
    summarized: boolean(),
    original_content: String.t() | map() | nil,
    hash: String.t()
  }

  @doc """
  Creates a new context entry with the given attributes.
  """
  def new(attrs) do
    content = attrs[:content] || ""
    
    entry = %__MODULE__{
      id: attrs[:id] || generate_id(),
      source: attrs[:source] || "unknown",
      content: content,
      metadata: attrs[:metadata] || %{},
      relevance_score: attrs[:relevance_score] || 0.5,
      timestamp: attrs[:timestamp] || DateTime.utc_now(),
      ttl: attrs[:ttl],
      size_tokens: attrs[:size_tokens] || estimate_tokens(content),
      compressed: false,
      summarized: false,
      original_content: nil,
      hash: generate_hash(content)
    }
    
    validate_entry!(entry)
    entry
  end

  @doc """
  Compresses the context entry to reduce token usage.
  """
  def compress(entry) do
    if entry.compressed do
      entry
    else
      compressed_content = compress_content(entry.content)
      
      %{entry |
        content: compressed_content,
        compressed: true,
        original_content: entry.content,
        size_tokens: estimate_tokens(compressed_content)
      }
    end
  end

  @doc """
  Decompresses a compressed entry to restore original content.
  """
  def decompress(entry) do
    if entry.compressed and entry.original_content do
      %{entry |
        content: entry.original_content,
        compressed: false,
        original_content: nil,
        size_tokens: estimate_tokens(entry.original_content)
      }
    else
      entry
    end
  end

  @doc """
  Summarizes the context entry to a fraction of its original size.
  """
  def summarize(entry, ratio \\ 0.3) do
    if entry.summarized do
      entry
    else
      summarized_content = summarize_content(entry.content, ratio)
      
      %{entry |
        content: summarized_content,
        summarized: true,
        original_content: entry.original_content || entry.content,
        size_tokens: estimate_tokens(summarized_content),
        metadata: Map.put(entry.metadata, :summary_ratio, ratio)
      }
    end
  end

  @doc """
  Merges two context entries if they're from the same source.
  """
  def merge(entry1, entry2) do
    if entry1.source != entry2.source do
      raise ArgumentError, "Cannot merge entries from different sources"
    end
    
    merged_content = merge_contents(entry1.content, entry2.content)
    merged_metadata = Map.merge(entry1.metadata, entry2.metadata)
    
    %__MODULE__{
      id: generate_id(),
      source: entry1.source,
      content: merged_content,
      metadata: merged_metadata,
      relevance_score: max(entry1.relevance_score, entry2.relevance_score),
      timestamp: max_datetime(entry1.timestamp, entry2.timestamp),
      ttl: merge_ttl(entry1.ttl, entry2.ttl),
      size_tokens: estimate_tokens(merged_content),
      compressed: false,
      summarized: false,
      original_content: nil,
      hash: generate_hash(merged_content)
    }
  end

  @doc """
  Checks if the entry has expired based on its TTL.
  """
  def expired?(entry) do
    case entry.ttl do
      nil -> false
      ttl ->
        age = DateTime.diff(DateTime.utc_now(), entry.timestamp, :second)
        age > ttl
    end
  end

  @doc """
  Updates the relevance score of the entry.
  """
  def update_relevance(entry, new_score) when new_score >= 0 and new_score <= 1 do
    %{entry | relevance_score: new_score}
  end

  @doc """
  Adds metadata to the entry.
  """
  def add_metadata(entry, key, value) do
    %{entry | metadata: Map.put(entry.metadata, key, value)}
  end

  @doc """
  Converts the entry to a format suitable for LLM consumption.
  """
  def to_llm_format(entry) do
    content_str = content_to_string(entry.content)
    
    if entry.metadata != %{} do
      metadata_str = format_metadata(entry.metadata)
      "#{metadata_str}\n\n#{content_str}"
    else
      content_str
    end
  end

  @doc """
  Creates a hash of the entry for deduplication.
  """
  def content_hash(entry) do
    entry.hash
  end

  @doc """
  Checks if two entries have similar content.
  """
  def similar?(entry1, entry2, threshold \\ 0.85) do
    similarity_score(entry1.content, entry2.content) >= threshold
  end

  # Private functions

  defp generate_id do
    "ctx_" <> :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp generate_hash(content) do
    content_str = content_to_string(content)
    :crypto.hash(:sha256, content_str) |> Base.encode16(case: :lower)
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

  defp compress_content(content) when is_binary(content) do
    # Simple compression: remove extra whitespace and common words
    content
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/\b(the|a|an|and|or|but|in|on|at|to|for)\b/i, "")
    |> String.trim()
  end

  defp compress_content(content) when is_map(content) do
    # For maps, remove null values and empty strings
    content
    |> Enum.reject(fn {_k, v} -> v == nil or v == "" end)
    |> Map.new()
  end

  defp summarize_content(content, ratio) when is_binary(content) do
    target_length = round(String.length(content) * ratio)
    
    sentences = String.split(content, ~r/[.!?]+/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    
    # Take sentences until we reach target length
    {summary, _} = Enum.reduce_while(sentences, {"", 0}, fn sentence, {acc, len} ->
      new_len = len + String.length(sentence)
      
      if new_len > target_length and acc != "" do
        {:halt, {acc, len}}
      else
        {:cont, {acc <> sentence <> ". ", new_len}}
      end
    end)
    
    String.trim(summary)
  end

  defp summarize_content(content, _ratio) when is_map(content) do
    # For maps, keep only important fields
    important_keys = ~w(summary description name title purpose type id)a
    
    content
    |> Map.take(important_keys)
    |> Map.put(:_summarized, true)
  end

  defp merge_contents(content1, content2) when is_binary(content1) and is_binary(content2) do
    content1 <> "\n\n" <> content2
  end

  defp merge_contents(content1, content2) when is_map(content1) and is_map(content2) do
    Map.merge(content1, content2)
  end

  defp merge_contents(content1, _content2), do: content1

  defp content_to_string(content) when is_binary(content), do: content
  defp content_to_string(content) when is_map(content), do: Jason.encode!(content)
  defp content_to_string(content), do: inspect(content)

  defp format_metadata(metadata) do
    metadata
    |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
    |> Enum.join(", ")
    |> then(&"[#{&1}]")
  end

  defp max_datetime(dt1, dt2) do
    if DateTime.compare(dt1, dt2) == :gt, do: dt1, else: dt2
  end

  defp merge_ttl(nil, ttl2), do: ttl2
  defp merge_ttl(ttl1, nil), do: ttl1
  defp merge_ttl(ttl1, ttl2), do: min(ttl1, ttl2)

  defp similarity_score(content1, content2) do
    str1 = content_to_string(content1)
    str2 = content_to_string(content2)
    
    if str1 == str2 do
      1.0
    else
      # Simple Jaccard similarity
      tokens1 = MapSet.new(String.split(str1))
      tokens2 = MapSet.new(String.split(str2))
      
      intersection = MapSet.intersection(tokens1, tokens2) |> MapSet.size()
      union = MapSet.union(tokens1, tokens2) |> MapSet.size()
      
      if union > 0, do: intersection / union, else: 0.0
    end
  end

  defp validate_entry!(entry) do
    unless entry.relevance_score >= 0 and entry.relevance_score <= 1 do
      raise ArgumentError, "Relevance score must be between 0 and 1"
    end
    
    unless entry.size_tokens >= 0 do
      raise ArgumentError, "Size tokens must be non-negative"
    end
    
    entry
  end
end