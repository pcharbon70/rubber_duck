defmodule RubberDuck.Context.Strategies.RAG do
  @moduledoc """
  Retrieval Augmented Generation (RAG) context building strategy.

  Retrieves relevant code snippets, patterns, and knowledge from the
  memory system to augment the context for better generation.
  """

  @behaviour RubberDuck.Context.Builder

  alias RubberDuck.Memory
  alias RubberDuck.Embeddings

  @default_retrieval_limit 10

  @impl true
  def name(), do: :rag

  @impl true
  def supported_query_types(), do: [:generation, :question, :analysis, :refactoring]

  @impl true
  def build(query, opts) do
    user_id = Keyword.get(opts, :user_id)
    session_id = Keyword.get(opts, :session_id)
    project_id = Keyword.get(opts, :project_id)
    max_tokens = Keyword.get(opts, :max_tokens, 4000)

    # Generate embedding for the query
    with {:ok, query_embedding} <- Embeddings.Service.generate(query),
         # Retrieve relevant content from all memory tiers
         {:ok, retrieved_content} <- retrieve_relevant_content(query_embedding, user_id, project_id),
         # Get recent interactions for continuity
         {:ok, recent_context} <- get_recent_context(user_id, session_id),
         # Build the RAG context
         context <- build_rag_context(query, retrieved_content, recent_context, max_tokens) do
      {:ok, context}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def estimate_quality(query, opts) do
    # RAG is excellent for generation and knowledge-based queries
    cond do
      Keyword.has_key?(opts, :project_id) -> 0.9
      String.contains?(query, ["how", "what", "why", "explain", "generate", "create"]) -> 0.8
      # Longer queries benefit from RAG
      String.length(query) > 50 -> 0.7
      true -> 0.5
    end
  end

  # Private functions

  defp retrieve_relevant_content(query_embedding, user_id, project_id) do
    # Retrieve from different sources in parallel
    tasks = [
      Task.async(fn -> retrieve_code_patterns(query_embedding, user_id) end),
      Task.async(fn -> retrieve_knowledge(query_embedding, user_id, project_id) end),
      Task.async(fn -> retrieve_summaries(user_id) end)
    ]

    results = Task.await_many(tasks, 5000)

    # Combine and rank results
    all_content =
      results
      |> Enum.flat_map(fn
        {:ok, items} -> items
        _ -> []
      end)
      |> rank_by_relevance()
      |> Enum.take(@default_retrieval_limit)

    {:ok, all_content}
  end

  defp retrieve_code_patterns(_embedding, user_id) do
    # TODO: When pgvector is fully integrated, use semantic search
    # For now, use keyword search with a generic query
    case Memory.search_patterns_keyword(user_id, "") do
      {:ok, patterns} ->
        {:ok, patterns |> Enum.take(5) |> Enum.map(&format_code_pattern/1)}

      _ ->
        {:ok, []}
    end
  end

  defp retrieve_knowledge(_embedding, user_id, project_id) do
    # TODO: Semantic search when pgvector is ready
    # For now, use keyword search
    if project_id do
      case Memory.search_knowledge_keyword(user_id, project_id, "") do
        {:ok, knowledge_items} ->
          {:ok, knowledge_items |> Enum.take(5) |> Enum.map(&format_knowledge/1)}

        _ ->
          {:ok, []}
      end
    else
      # Without project_id, we can't search knowledge
      {:ok, []}
    end
  end

  defp retrieve_summaries(user_id) do
    case Memory.get_user_summaries(user_id) do
      {:ok, summaries} ->
        summaries
        # Only relevant summaries
        |> Enum.filter(&(&1.heat_score > 0.5))
        |> Enum.take(3)
        |> Enum.map(&format_summary/1)
        |> then(&{:ok, &1})

      _ ->
        {:ok, []}
    end
  end

  defp get_recent_context(user_id, session_id) when is_binary(user_id) and is_binary(session_id) do
    case Memory.get_recent_interactions(user_id, session_id) do
      {:ok, interactions} ->
        context =
          interactions
          |> Enum.take(3)
          |> Enum.map(& &1.content)
          |> Enum.join("\n")

        {:ok, context}

      _ ->
        {:ok, ""}
    end
  end

  defp get_recent_context(_, _), do: {:ok, ""}

  defp format_code_pattern(pattern) do
    %{
      type: :code_pattern,
      content: pattern.pattern_code,
      metadata: %{
        language: pattern.language,
        pattern_type: pattern.pattern_type,
        description: pattern.description
      },
      # TODO: Calculate actual similarity
      relevance_score: 0.8
    }
  end

  defp format_knowledge(knowledge) do
    %{
      type: :knowledge,
      content: knowledge.content,
      metadata: %{
        title: knowledge.title,
        knowledge_type: knowledge.knowledge_type,
        tags: knowledge.tags
      },
      relevance_score: knowledge.relevance_score
    }
  end

  defp format_summary(summary) do
    %{
      type: :summary,
      content: summary.summary,
      metadata: %{
        topic: summary.topic,
        pattern_type: summary.pattern_type,
        frequency: summary.frequency
      },
      relevance_score: summary.heat_score
    }
  end

  defp rank_by_relevance(items) do
    items
    |> Enum.sort_by(& &1.relevance_score, :desc)
  end

  defp build_rag_context(query, retrieved_content, recent_context, max_tokens) do
    # Reserve tokens for query and response
    available_tokens = max_tokens - 1000

    # Build context sections
    sections = []

    # Add recent context if available
    sections1 =
      if recent_context != "" do
        [{:recent, "## Recent Context\n#{recent_context}\n"} | sections]
      else
        sections
      end

    # Add retrieved content by type
    code_patterns = Enum.filter(retrieved_content, &(&1.type == :code_pattern))
    knowledge_items = Enum.filter(retrieved_content, &(&1.type == :knowledge))
    summaries = Enum.filter(retrieved_content, &(&1.type == :summary))

    sections2 =
      if length(code_patterns) > 0 do
        pattern_text = format_code_patterns_section(code_patterns)
        [{:patterns, pattern_text} | sections1]
      else
        sections1
      end

    sections3 =
      if length(knowledge_items) > 0 do
        knowledge_text = format_knowledge_section(knowledge_items)
        [{:knowledge, knowledge_text} | sections2]
      else
        sections2
      end

    sections4 =
      if length(summaries) > 0 do
        summary_text = format_summaries_section(summaries)
        [{:summaries, summary_text} | sections3]
      else
        sections3
      end

    # Add query
    sections5 = [{:query, "## Query\n#{query}\n"} | sections4]

    # Optimize sections to fit token limit
    optimized_content = optimize_sections(sections5, available_tokens)

    %{
      content: optimized_content,
      metadata: %{
        retrieved_count: length(retrieved_content),
        included_types: get_included_types(sections),
        truncated: String.contains?(optimized_content, "...")
      },
      token_count: estimate_tokens(optimized_content),
      strategy: :rag,
      sources:
        Enum.map(retrieved_content, fn item ->
          %{
            type: item.type,
            content: item.content,
            metadata: item.metadata
          }
        end)
    }
  end

  defp format_code_patterns_section(patterns) do
    """
    ## Relevant Code Patterns
    #{Enum.map_join(patterns, "\n\n", fn p -> """
      ### #{p.metadata.pattern_type} (#{p.metadata.language})
      #{p.metadata.description || ""}
      ```#{p.metadata.language}
      #{p.content}
      ```
      """ end)}
    """
  end

  defp format_knowledge_section(items) do
    """
    ## Relevant Knowledge
    #{Enum.map_join(items, "\n\n", fn k -> """
      ### #{k.metadata.title}
      Type: #{k.metadata.knowledge_type}
      Tags: #{Enum.join(k.metadata.tags, ", ")}

      #{k.content}
      """ end)}
    """
  end

  defp format_summaries_section(summaries) do
    """
    ## Pattern Summaries
    #{Enum.map_join(summaries, "\n", fn s -> "- **#{s.metadata.topic}**: #{s.content} (frequency: #{s.metadata.frequency})" end)}
    """
  end

  defp optimize_sections(sections, max_tokens) do
    # Calculate token usage for each section
    sections_with_tokens =
      Enum.map(sections, fn {type, content} ->
        {type, content, estimate_tokens(content)}
      end)

    # If within limit, return all
    total_tokens = Enum.sum(Enum.map(sections_with_tokens, &elem(&1, 2)))

    if total_tokens <= max_tokens do
      sections_with_tokens
      |> Enum.map(fn {_type, content, _tokens} -> content end)
      |> Enum.join("\n")
    else
      # Prioritize sections and truncate
      prioritize_and_truncate(sections_with_tokens, max_tokens)
    end
  end

  defp prioritize_and_truncate(sections, max_tokens) do
    # Priority order: query > patterns > recent > knowledge > summaries
    priority_order = [:query, :patterns, :recent, :knowledge, :summaries]

    {included, _remaining_tokens} =
      Enum.reduce(priority_order, {[], max_tokens}, fn type, {acc, tokens_left} ->
        case Enum.find(sections, fn {t, _, _} -> t == type end) do
          nil ->
            {acc, tokens_left}

          {^type, content, token_count} ->
            if token_count <= tokens_left do
              {[content | acc], tokens_left - token_count}
            else
              # Truncate to fit
              truncated = truncate_to_tokens(content, tokens_left, :end)
              {[truncated | acc], 0}
            end
        end
      end)

    included
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp get_included_types(sections) do
    sections
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(&(&1 != :query))
  end

  defp truncate_to_tokens(text, max_tokens, :end) do
    max_chars = max_tokens * 4

    if String.length(text) <= max_chars do
      text
    else
      String.slice(text, 0, max_chars - 3) <> "..."
    end
  end

  defp estimate_tokens(text) do
    div(String.length(text), 4)
  end
end
