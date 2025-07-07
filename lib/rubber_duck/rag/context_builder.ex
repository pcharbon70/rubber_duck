defmodule RubberDuck.RAG.ContextBuilder do
  @moduledoc """
  Enhanced context preparation for the RAG pipeline.

  Builds rich, structured context from retrieved documents with:
  - Intelligent summarization
  - Citation tracking
  - Context compression
  - Relevance filtering
  - Structure preservation
  """

  require Logger
  alias RubberDuck.LLM.Service, as: LLMService
  alias RubberDuck.Context.Optimizer

  @type context_options :: %{
          max_tokens: integer(),
          include_citations: boolean(),
          summarize: boolean(),
          preserve_structure: boolean(),
          relevance_threshold: float()
        }

  @type built_context :: %{
          content: String.t(),
          citations: list(map()),
          metadata: map(),
          token_count: integer()
        }

  @default_options %{
    max_tokens: 4000,
    include_citations: true,
    summarize: true,
    preserve_structure: true,
    relevance_threshold: 0.5
  }

  @doc """
  Builds optimized context from retrieved documents.

  Takes raw retrieval results and prepares them for LLM consumption.
  """
  @spec build_context(list(map()), String.t(), map()) :: {:ok, built_context()} | {:error, term()}
  def build_context(retrieved_docs, query, options \\ %{}) do
    opts = Map.merge(@default_options, options)

    # Filter by relevance threshold
    relevant_docs = filter_by_relevance(retrieved_docs, opts.relevance_threshold)

    # Build initial context sections
    sections = build_context_sections(relevant_docs, query, opts)

    # Optimize for token limit
    optimized_sections = optimize_sections(sections, opts.max_tokens)

    # Format final context
    context = format_context(optimized_sections, opts)

    # Add citations if requested
    final_context =
      if opts.include_citations do
        add_citations(context, relevant_docs)
      else
        context
      end

    {:ok, final_context}
  end

  @doc """
  Builds context with progressive summarization.

  Summarizes less relevant content more aggressively.
  """
  @spec build_progressive_context(list(map()), String.t(), map()) :: {:ok, built_context()} | {:error, term()}
  def build_progressive_context(retrieved_docs, query, options \\ %{}) do
    opts = Map.merge(@default_options, options)

    # Sort by relevance
    sorted_docs = Enum.sort_by(retrieved_docs, & &1.score, :desc)

    # Apply progressive summarization
    {context_parts, citations} =
      sorted_docs
      |> Enum.with_index()
      |> Enum.reduce({[], []}, fn {{doc, idx}, {parts, cites}}, _acc ->
        # More aggressive summarization for lower-ranked docs
        summarization_level = calculate_summarization_level(idx, length(sorted_docs))

        processed = process_document(doc, query, summarization_level, opts)

        {parts ++ [processed.content], cites ++ [processed.citation]}
      end)

    # Build final context
    context = %{
      content: Enum.join(context_parts, "\n\n"),
      citations: citations,
      metadata: %{
        doc_count: length(sorted_docs),
        summarization_applied: true
      },
      token_count: Optimizer.count_tokens(Enum.join(context_parts))
    }

    {:ok, context}
  end

  @doc """
  Builds structured context preserving document organization.

  Maintains headings, lists, and other structural elements.
  """
  @spec build_structured_context(list(map()), String.t(), map()) :: {:ok, built_context()} | {:error, term()}
  def build_structured_context(retrieved_docs, query, options \\ %{}) do
    opts = Map.merge(@default_options, options)

    # Group documents by type/source
    grouped_docs = group_documents_by_type(retrieved_docs)

    # Build structured sections
    sections =
      Enum.map(grouped_docs, fn {type, docs} ->
        build_typed_section(type, docs, query, opts)
      end)

    # Merge sections with proper formatting
    merged_context = merge_structured_sections(sections, opts)

    {:ok, merged_context}
  end

  # Private functions

  defp filter_by_relevance(docs, threshold) do
    Enum.filter(docs, fn doc ->
      Map.get(doc, :score, 0) >= threshold
    end)
  end

  defp build_context_sections(docs, query, opts) do
    docs
    |> Enum.map(fn doc ->
      %{
        content: extract_relevant_content(doc, query, opts),
        source: doc.metadata.source,
        score: doc.score,
        tokens: Optimizer.count_tokens(doc.content)
      }
    end)
  end

  defp extract_relevant_content(doc, query, opts) do
    if opts.summarize && doc.score < 0.7 do
      summarize_content(doc.content, query)
    else
      doc.content
    end
  end

  defp summarize_content(content, query) do
    prompt = """
    Summarize the following content, focusing on information relevant to this query: "#{query}"

    Content:
    #{String.slice(content, 0, 1000)}

    Provide a concise summary (2-3 sentences) highlighting the most relevant information.
    """

    case LLMService.completion(%{
           model: "claude-3-haiku-20240307",
           prompt: prompt,
           max_tokens: 150
         }) do
      {:ok, response} -> response.content
      _ -> String.slice(content, 0, 200) <> "..."
    end
  end

  defp optimize_sections(sections, max_tokens) do
    total_tokens = Enum.sum(Enum.map(sections, & &1.tokens))

    if total_tokens <= max_tokens do
      sections
    else
      # Compress sections proportionally
      compression_ratio = max_tokens / total_tokens

      Enum.map(sections, fn section ->
        target_tokens = round(section.tokens * compression_ratio)
        compressed_content = compress_content(section.content, target_tokens)

        %{section | content: compressed_content, tokens: Optimizer.count_tokens(compressed_content)}
      end)
    end
  end

  defp compress_content(content, target_tokens) do
    # Simple compression by truncation
    # In production, use more sophisticated compression
    words = String.split(content, ~r/\s+/)
    # Approximate
    words_per_token = 0.75
    target_words = round(target_tokens * words_per_token)

    words
    |> Enum.take(target_words)
    |> Enum.join(" ")
  end

  defp format_context(sections, opts) do
    formatted_sections =
      if opts.preserve_structure do
        format_with_structure(sections)
      else
        format_plain(sections)
      end

    %{
      content: formatted_sections,
      metadata: %{
        section_count: length(sections),
        total_tokens: Enum.sum(Enum.map(sections, & &1.tokens))
      },
      token_count: Optimizer.count_tokens(formatted_sections)
    }
  end

  defp format_with_structure(sections) do
    sections
    |> Enum.with_index(1)
    |> Enum.map(fn {section, idx} ->
      """
      ## Source #{idx}: #{section.source}

      #{section.content}
      """
    end)
    |> Enum.join("\n")
  end

  defp format_plain(sections) do
    sections
    |> Enum.map(& &1.content)
    |> Enum.join("\n\n---\n\n")
  end

  defp add_citations(context, docs) do
    citations =
      docs
      |> Enum.with_index(1)
      |> Enum.map(fn {doc, idx} ->
        %{
          id: idx,
          source: get_in(doc, [:metadata, :source]) || "Unknown",
          relevance_score: doc.score,
          excerpt: String.slice(doc.content, 0, 100) <> "..."
        }
      end)

    Map.put(context, :citations, citations)
  end

  defp calculate_summarization_level(index, total_docs) do
    cond do
      index < total_docs * 0.3 -> :none
      index < total_docs * 0.6 -> :light
      true -> :aggressive
    end
  end

  defp process_document(doc, query, summarization_level, _opts) do
    content =
      case summarization_level do
        :none -> doc.content
        :light -> lightly_summarize(doc.content, query)
        :aggressive -> aggressively_summarize(doc.content, query)
      end

    %{
      content: content,
      citation: %{
        source: get_in(doc, [:metadata, :source]),
        score: doc.score
      }
    }
  end

  defp lightly_summarize(content, query) do
    # Extract most relevant paragraphs
    paragraphs = String.split(content, ~r/\n\n/)
    query_terms = String.split(String.downcase(query), ~r/\s+/)

    relevant_paragraphs =
      paragraphs
      |> Enum.filter(fn para ->
        para_lower = String.downcase(para)
        Enum.any?(query_terms, &String.contains?(para_lower, &1))
      end)
      |> Enum.take(3)

    if length(relevant_paragraphs) > 0 do
      Enum.join(relevant_paragraphs, "\n\n")
    else
      String.slice(content, 0, 300) <> "..."
    end
  end

  defp aggressively_summarize(content, query) do
    # Use LLM for aggressive summarization
    summarize_content(content, query)
  end

  defp group_documents_by_type(docs) do
    Enum.group_by(docs, fn doc ->
      cond do
        String.contains?(doc.content, ["def ", "defmodule"]) -> :code
        String.contains?(get_in(doc, [:metadata, :source]) || "", ".md") -> :documentation
        true -> :general
      end
    end)
  end

  defp build_typed_section(type, docs, query, opts) do
    header =
      case type do
        :code -> "## Code Examples"
        :documentation -> "## Documentation"
        :general -> "## Related Information"
      end

    content =
      docs
      |> Enum.map(fn doc ->
        process_by_type(doc, type, query, opts)
      end)
      |> Enum.join("\n\n")

    %{
      header: header,
      content: content,
      type: type
    }
  end

  defp process_by_type(doc, :code, _query, _opts) do
    # Preserve code formatting
    "```elixir\n#{doc.content}\n```"
  end

  defp process_by_type(doc, _type, query, opts) do
    extract_relevant_content(doc, query, opts)
  end

  defp merge_structured_sections(sections, _opts) do
    content =
      sections
      |> Enum.map(fn section ->
        "#{section.header}\n\n#{section.content}"
      end)
      |> Enum.join("\n\n")

    %{
      content: content,
      citations: [],
      metadata: %{
        sections: Enum.map(sections, & &1.type)
      },
      token_count: Optimizer.count_tokens(content)
    }
  end
end
