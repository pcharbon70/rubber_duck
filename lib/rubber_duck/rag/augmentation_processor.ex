defmodule RubberDuck.RAG.AugmentationProcessor do
  @moduledoc """
  Processing functions for document augmentation in the RAG pipeline.
  
  Provides deduplication, format standardization, summarization,
  and validation capabilities for retrieved documents.
  """

  alias RubberDuck.RAG.RetrievedDocument

  @doc """
  Deduplicates documents based on similarity threshold.
  """
  def deduplicate(documents, threshold \\ 0.85) do
    Enum.reduce(documents, [], fn doc, acc ->
      if similar_exists?(doc, acc, threshold) do
        # Merge with existing similar document
        merge_similar_document(doc, acc, threshold)
      else
        [doc | acc]
      end
    end)
    |> Enum.reverse()
  end

  @doc """
  Standardizes document format for consistent processing.
  """
  def standardize_format(document) do
    standardized_content = document.content
    |> normalize_whitespace()
    |> fix_encoding_issues()
    |> remove_special_characters()
    |> ensure_sentence_endings()
    
    %{document | 
      content: standardized_content,
      metadata: Map.put(document.metadata, :format_standardized, true)
    }
  end

  @doc """
  Summarizes a document to reduce token usage.
  """
  def summarize(document, max_ratio \\ 0.3) do
    target_tokens = round(document.size_tokens * max_ratio)
    
    summarized_content = if document.size_tokens > 500 do
      extract_key_sentences(document.content, target_tokens)
    else
      # Don't summarize small documents
      document.content
    end
    
    %{document |
      content: summarized_content,
      size_tokens: estimate_tokens(summarized_content),
      metadata: Map.merge(document.metadata, %{
        summarized: true,
        original_tokens: document.size_tokens,
        summary_ratio: max_ratio
      })
    }
  end

  @doc """
  Aggressively summarizes content for fallback scenarios.
  """
  def aggressive_summarize(context, target_ratio \\ 0.2) do
    # Take only the most relevant parts
    summarized_docs = context.documents
    |> Enum.take(3)  # Keep only top 3 documents
    |> Enum.map(fn doc ->
      summarize(doc, target_ratio)
    end)
    
    %{context | 
      documents: summarized_docs,
      total_tokens: calculate_total_tokens(summarized_docs),
      optimization_applied: [:aggressive_summary | context.optimization_applied]
    }
  end

  @doc """
  Validates document quality and content.
  """
  def validate_document(document) do
    validations = [
      {:min_content_length, String.length(document.content) >= 10},
      {:has_actual_content, not is_empty_content?(document.content)},
      {:valid_relevance, document.relevance_score > 0},
      {:not_error_page, not contains_error_indicators?(document.content)},
      {:language_check, is_valid_language?(document.content)}
    ]
    
    failed = Enum.filter(validations, fn {_, result} -> not result end)
    
    if length(failed) == 0 do
      true
    else
      # Log validation failures
      false
    end
  end

  @doc """
  Extracts key highlights from document content.
  """
  def extract_highlights(document, max_highlights \\ 3) do
    sentences = split_into_sentences(document.content)
    
    # Score sentences based on importance
    scored_sentences = Enum.map(sentences, fn sentence ->
      score = score_sentence_importance(sentence, document)
      {sentence, score}
    end)
    
    highlights = scored_sentences
    |> Enum.sort_by(fn {_, score} -> score end, :desc)
    |> Enum.take(max_highlights)
    |> Enum.map(fn {sentence, _} -> sentence end)
    
    RetrievedDocument.add_highlights(document, highlights)
  end

  @doc """
  Chunks a large document into smaller pieces.
  """
  def chunk_document(document, max_chunk_tokens \\ 500) do
    if document.size_tokens <= max_chunk_tokens do
      [document]
    else
      chunks = chunk_content(document.content, max_chunk_tokens)
      total_chunks = length(chunks)
      
      chunks
      |> Enum.with_index()
      |> Enum.map(fn {chunk_content, index} ->
        %{document |
          id: "#{document.id}_chunk_#{index}",
          content: chunk_content,
          size_tokens: estimate_tokens(chunk_content),
          chunk_index: index,
          total_chunks: total_chunks,
          metadata: Map.put(document.metadata, :chunked, true)
        }
      end)
    end
  end

  @doc """
  Merges document chunks back together.
  """
  def merge_chunks(chunks) do
    if length(chunks) <= 1 do
      hd(chunks || [%{}])
    else
      # Sort by chunk index
      sorted_chunks = Enum.sort_by(chunks, & &1.chunk_index)
      
      merged_content = sorted_chunks
      |> Enum.map(& &1.content)
      |> Enum.join("\n")
      
      base_doc = hd(sorted_chunks)
      
      %{base_doc |
        content: merged_content,
        size_tokens: estimate_tokens(merged_content),
        chunk_index: nil,
        total_chunks: nil,
        metadata: Map.delete(base_doc.metadata, :chunked)
      }
    end
  end

  # Private functions

  defp similar_exists?(document, existing_docs, threshold) do
    Enum.any?(existing_docs, fn existing ->
      RetrievedDocument.similarity(document, existing) >= threshold
    end)
  end

  defp merge_similar_document(new_doc, existing_docs, threshold) do
    # Find the most similar document
    {similar_doc, other_docs} = Enum.reduce(existing_docs, {nil, []}, fn doc, {best, others} ->
      similarity = RetrievedDocument.similarity(new_doc, doc)
      
      cond do
        similarity >= threshold and (best == nil or similarity > RetrievedDocument.similarity(new_doc, best)) ->
          if best, do: {doc, [best | others]}, else: {doc, others}
        true ->
          {best, [doc | others]}
      end
    end)
    
    if similar_doc do
      # Merge the documents
      merged = merge_documents(similar_doc, new_doc)
      [merged | other_docs]
    else
      [new_doc | existing_docs]
    end
  end

  defp merge_documents(doc1, doc2) do
    # Keep the higher relevance score
    relevance = max(doc1.relevance_score, doc2.relevance_score)
    
    # Merge metadata
    merged_metadata = Map.merge(doc1.metadata, doc2.metadata)
    |> Map.put(:merged, true)
    |> Map.put(:merge_count, (doc1.metadata[:merge_count] || 1) + 1)
    
    # Keep longer content (assuming more complete)
    content = if String.length(doc1.content) >= String.length(doc2.content) do
      doc1.content
    else
      doc2.content
    end
    
    %{doc1 |
      content: content,
      relevance_score: relevance,
      metadata: merged_metadata,
      size_tokens: estimate_tokens(content)
    }
  end

  defp normalize_whitespace(content) do
    content
    |> String.replace(~r/\r\n|\r/, "\n")
    |> String.replace(~r/\t/, "  ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp fix_encoding_issues(content) do
    # Fix common encoding issues
    content
    |> String.replace("â€™", "'")
    |> String.replace("â€œ", "\"")
    |> String.replace("â€", "\"")
    |> String.replace("â€"", "-")
  end

  defp remove_special_characters(content) do
    # Remove zero-width characters and other problematic chars
    String.replace(content, ~r/[\u200B-\u200D\uFEFF]/, "")
  end

  defp ensure_sentence_endings(content) do
    # Ensure content ends with proper punctuation
    if String.match?(content, ~r/[.!?]$/) do
      content
    else
      content <> "."
    end
  end

  defp extract_key_sentences(content, target_tokens) do
    sentences = split_into_sentences(content)
    
    # Score sentences
    scored = Enum.map(sentences, fn sentence ->
      score = score_sentence_importance(sentence, nil)
      {sentence, score, estimate_tokens(sentence)}
    end)
    |> Enum.sort_by(fn {_, score, _} -> score end, :desc)
    
    # Select sentences up to token limit
    {selected, _} = Enum.reduce(scored, {[], 0}, fn {sentence, _, tokens}, {acc, total} ->
      if total + tokens <= target_tokens do
        {[sentence | acc], total + tokens}
      else
        {acc, total}
      end
    end)
    
    # Return in original order
    selected
    |> Enum.reverse()
    |> Enum.join(" ")
  end

  defp split_into_sentences(content) do
    content
    |> String.split(~r/(?<=[.!?])\s+/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp score_sentence_importance(sentence, _document) do
    # Simple heuristic scoring
    score = 0.0
    
    # Length factor (not too short, not too long)
    word_count = length(String.split(sentence))
    score = score + cond do
      word_count < 5 -> 0.1
      word_count > 30 -> 0.3
      true -> 0.5
    end
    
    # Contains numbers or data
    if String.match?(sentence, ~r/\d+/) do
      score = score + 0.2
    end
    
    # Contains key terms
    key_terms = ~w(important significant critical essential key main primary)
    if Enum.any?(key_terms, &String.contains?(String.downcase(sentence), &1)) do
      score = score + 0.3
    end
    
    score
  end

  defp is_empty_content?(content) do
    cleaned = content
    |> String.replace(~r/\s+/, "")
    |> String.replace(~r/[[:punct:]]/, "")
    
    String.length(cleaned) < 5
  end

  defp contains_error_indicators?(content) do
    error_patterns = [
      "404", "not found", "error", "forbidden", "unauthorized",
      "access denied", "internal server error"
    ]
    
    content_lower = String.downcase(content)
    Enum.any?(error_patterns, &String.contains?(content_lower, &1))
  end

  defp is_valid_language?(content) do
    # Simple check for valid text content
    # In production, use proper language detection
    words = String.split(content)
    
    # Check if most words are actual words (contain letters)
    valid_words = Enum.count(words, &String.match?(&1, ~r/[a-zA-Z]/))
    
    valid_words / max(length(words), 1) > 0.7
  end

  defp chunk_content(content, max_chunk_tokens) do
    sentences = split_into_sentences(content)
    
    # Group sentences into chunks
    {chunks, current_chunk, _} = Enum.reduce(sentences, {[], [], 0}, 
      fn sentence, {chunks, current, tokens} ->
        sentence_tokens = estimate_tokens(sentence)
        
        if tokens + sentence_tokens > max_chunk_tokens and current != [] do
          # Start new chunk
          {[Enum.join(current, " ") | chunks], [sentence], sentence_tokens}
        else
          # Add to current chunk
          {chunks, current ++ [sentence], tokens + sentence_tokens}
        end
      end)
    
    # Add final chunk
    final_chunks = if current_chunk != [] do
      [Enum.join(current_chunk, " ") | chunks]
    else
      chunks
    end
    
    Enum.reverse(final_chunks)
  end

  defp estimate_tokens(content) when is_binary(content) do
    div(String.length(content), 4)
  end
  defp estimate_tokens(_), do: 0

  defp calculate_total_tokens(documents) do
    Enum.sum(Enum.map(documents, & &1.size_tokens))
  end
end