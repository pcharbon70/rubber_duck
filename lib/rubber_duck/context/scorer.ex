defmodule RubberDuck.Context.Scorer do
  @moduledoc """
  Scores context quality based on relevance, diversity, and completeness.

  Helps evaluate and compare different context building strategies.
  """

  @doc """
  Calculates an overall quality score for a context.

  Returns a score between 0.0 and 1.0 based on multiple factors:
  - Relevance: How well the context matches the query
  - Diversity: Variety of information sources
  - Completeness: Coverage of query requirements
  - Recency: Freshness of included information
  """
  def score(context, query, opts \\ []) do
    weights = Keyword.get(opts, :weights, default_weights())

    scores = %{
      relevance: calculate_relevance(context, query),
      diversity: calculate_diversity(context),
      completeness: calculate_completeness(context, query),
      recency: calculate_recency(context)
    }

    # Weighted average
    total_score =
      Enum.reduce(scores, 0.0, fn {metric, score}, acc ->
        acc + score * Map.get(weights, metric, 0.25)
      end)

    %{
      total: Float.round(total_score, 2),
      breakdown: scores,
      metadata: analyze_context(context)
    }
  end

  @doc """
  Compares multiple contexts and returns them ranked by quality.
  """
  def rank_contexts(contexts, query, opts \\ []) do
    contexts
    |> Enum.map(fn context ->
      score_result = score(context, query, opts)
      {context, score_result}
    end)
    |> Enum.sort_by(fn {_, score_result} -> score_result.total end, :desc)
  end

  @doc """
  Suggests improvements for a context based on its scores.
  """
  def suggest_improvements(context, query, score_result) do
    suggestions = []

    # Check each metric
    suggestions =
      if score_result.breakdown.relevance < 0.6 do
        ["Include more query-specific information" | suggestions]
      else
        suggestions
      end

    suggestions =
      if score_result.breakdown.diversity < 0.5 do
        ["Add more diverse information sources" | suggestions]
      else
        suggestions
      end

    suggestions =
      if score_result.breakdown.completeness < 0.6 do
        ["Expand context to cover more aspects of the query" | suggestions]
      else
        suggestions
      end

    suggestions =
      if score_result.breakdown.recency < 0.5 do
        ["Include more recent information" | suggestions]
      else
        suggestions
      end

    # Context-specific suggestions
    metadata = score_result.metadata

    suggestions =
      if metadata.token_density > 0.8 do
        ["Consider more concise representation" | suggestions]
      else
        suggestions
      end

    suggestions =
      if metadata.source_count < 3 do
        ["Include additional context sources" | suggestions]
      else
        suggestions
      end

    suggestions
  end

  # Private functions

  defp default_weights() do
    %{
      relevance: 0.4,
      diversity: 0.2,
      completeness: 0.25,
      recency: 0.15
    }
  end

  defp calculate_relevance(context, query) do
    # Simple keyword matching for now
    # TODO: Use embeddings for semantic similarity

    query_terms =
      query
      |> String.downcase()
      |> String.split(~r/\W+/, trim: true)
      |> MapSet.new()

    context_terms =
      context.content
      |> String.downcase()
      |> String.split(~r/\W+/, trim: true)
      |> Enum.frequencies()

    # Calculate coverage and frequency
    coverage =
      Enum.count(query_terms, fn term ->
        Map.has_key?(context_terms, term)
      end) / max(MapSet.size(query_terms), 1)

    # Bonus for high frequency of query terms
    frequency_bonus =
      Enum.reduce(query_terms, 0, fn term, acc ->
        acc + min(Map.get(context_terms, term, 0) / 10, 0.1)
      end)

    min(coverage + frequency_bonus, 1.0)
  end

  defp calculate_diversity(context) do
    sources = context.sources || []

    # Score based on number and variety of sources
    source_types =
      sources
      |> Enum.map(& &1.type)
      |> Enum.uniq()
      |> length()

    source_count = length(sources)

    # Ideal: 3-5 different source types, 5-10 total sources
    type_score = min(source_types / 5, 1.0)

    count_score =
      cond do
        source_count < 3 -> source_count / 3
        source_count <= 10 -> 1.0
        # Penalty for too many
        true -> 1.0 - (source_count - 10) / 20
      end

    (type_score + count_score) / 2
  end

  defp calculate_completeness(context, query) do
    # Analyze if context addresses different aspects of the query

    # Check for question words
    question_aspects = analyze_question_aspects(query)
    covered_aspects = check_covered_aspects(context.content, question_aspects)

    aspect_coverage =
      if map_size(question_aspects) > 0 do
        Enum.count(covered_aspects, & &1) / map_size(question_aspects)
      else
        # No specific aspects to cover
        1.0
      end

    # Check for code-related completeness
    code_coverage =
      if String.contains?(query, ["code", "implement", "function", "class"]) do
        check_code_completeness(context)
      else
        1.0
      end

    (aspect_coverage + code_coverage) / 2
  end

  defp calculate_recency(context) do
    # Score based on metadata timestamps if available
    metadata = context.metadata || %{}
    sources = context.sources || []

    # Check for recency indicators
    has_recent_context = Map.get(metadata, :context_included, false)
    has_history = Enum.any?(sources, &(&1.type == :recent_interactions))

    # Base score
    base_score = 0.5

    score =
      cond do
        has_recent_context and has_history -> 1.0
        has_recent_context or has_history -> 0.8
        true -> base_score
      end

    # Boost for specific strategy
    case context.strategy do
      # FIM always uses recent context
      :fim -> score
      # RAG may use older patterns
      :rag -> score * 0.9
      # Long context includes history
      :long_context -> score * 0.95
      _ -> score * 0.7
    end
  end

  defp analyze_question_aspects(query) do
    aspects = %{}

    # What/How/Why/When/Where questions
    aspects =
      cond do
        String.contains?(query, "what") -> Map.put(aspects, :what, true)
        String.contains?(query, "how") -> Map.put(aspects, :how, true)
        String.contains?(query, "why") -> Map.put(aspects, :why, true)
        String.contains?(query, "when") -> Map.put(aspects, :when, true)
        String.contains?(query, "where") -> Map.put(aspects, :where, true)
        true -> aspects
      end

    # Technical aspects
    aspects1 = if String.contains?(query, ["implement", "create", "build"]) do
      Map.put(aspects, :implementation, true)
    else
      aspects
    end

    aspects2 = if String.contains?(query, ["error", "bug", "issue", "problem"]) do
      Map.put(aspects1, :troubleshooting, true)
    else
      aspects1
    end

    if String.contains?(query, ["performance", "optimize", "speed"]) do
      Map.put(aspects2, :performance, true)
    else
      aspects2
    end
  end

  defp check_covered_aspects(content, aspects) do
    content_lower = String.downcase(content)

    Map.new(aspects, fn {aspect, _} ->
      covered =
        case aspect do
          :what -> String.contains?(content_lower, ["is", "are", "definition", "means"])
          :how -> String.contains?(content_lower, ["steps", "process", "method", "approach"])
          :why -> String.contains?(content_lower, ["because", "reason", "purpose", "rationale"])
          :when -> String.contains?(content_lower, ["time", "when", "after", "before", "during"])
          :where -> String.contains?(content_lower, ["location", "where", "file", "module"])
          :implementation -> String.contains?(content_lower, ["code", "function", "class", "```"])
          :troubleshooting -> String.contains?(content_lower, ["error", "fix", "solution", "resolve"])
          :performance -> String.contains?(content_lower, ["performance", "speed", "optimize", "efficient"])
          _ -> false
        end

      {aspect, covered}
    end)
  end

  defp check_code_completeness(context) do
    content = context.content

    # Check for code blocks
    has_code_blocks = String.contains?(content, "```")

    # Check for code patterns in sources
    has_code_patterns =
      Enum.any?(context.sources || [], fn source ->
        source.type in [:code_pattern, :file, :current_file]
      end)

    # Check for implementation details
    has_implementation_details =
      String.contains?(content, ["function", "def", "class", "module", "import", "require"])

    score = 0.0
    score = if has_code_blocks, do: score + 0.4, else: score
    score = if has_code_patterns, do: score + 0.4, else: score
    score = if has_implementation_details, do: score + 0.2, else: score

    min(score, 1.0)
  end

  defp analyze_context(context) do
    %{
      token_count: context.token_count || 0,
      token_density: calculate_token_density(context),
      source_count: length(context.sources || []),
      strategy: context.strategy,
      has_code: String.contains?(context.content, "```"),
      section_count: count_sections(context.content)
    }
  end

  defp calculate_token_density(context) do
    # Ratio of tokens to unique information
    tokens = context.token_count || 0

    unique_lines =
      context.content
      |> String.split("\n")
      |> Enum.uniq()
      |> length()

    if unique_lines > 0 do
      Float.round(tokens / unique_lines / 10, 2)
    else
      0.0
    end
  end

  defp count_sections(content) do
    content
    |> String.split(~r/^##\s+/m)
    |> length()
    # Subtract 1 for the first split part
    |> Kernel.-(1)
    |> max(0)
  end
end
