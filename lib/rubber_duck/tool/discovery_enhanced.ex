defmodule RubberDuck.Tool.DiscoveryEnhanced do
  @moduledoc """
  Enhanced tool discovery capabilities including semantic search and intelligent recommendations.

  Features:
  - Semantic tool search using embeddings (future)
  - Context-based tool recommendations
  - Tool compatibility checking
  - Performance profiling integration
  """

  alias RubberDuck.Tool
  alias RubberDuck.Tool.{Registry, StatePersistence}

  require Logger

  @doc """
  Performs semantic search for tools based on natural language queries.

  Currently uses keyword matching, but designed for future embedding-based search.
  """
  def semantic_search(query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    threshold = Keyword.get(opts, :threshold, 0.5)

    # Preprocess query
    processed_query = preprocess_query(query)

    # Score all tools
    scored_tools =
      Registry.list()
      |> Enum.map(fn tool_module ->
        score = calculate_semantic_score(tool_module, processed_query)
        {tool_module, score}
      end)
      |> Enum.filter(fn {_, score} -> score >= threshold end)
      |> Enum.sort_by(fn {_, score} -> score end, :desc)
      |> Enum.take(limit)

    # Build results with explanations
    results =
      Enum.map(scored_tools, fn {tool_module, score} ->
        build_search_result(tool_module, score, processed_query)
      end)

    {:ok, results}
  end

  @doc """
  Recommends tools based on user context and history.
  """
  def recommend_tools(user_context, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)

    # Get user's tool usage history
    history = get_user_history(user_context)

    # Analyze patterns
    patterns = analyze_usage_patterns(history)

    # Get candidate tools
    candidates = get_recommendation_candidates(patterns, user_context)

    # Score and rank candidates
    recommendations =
      candidates
      |> score_recommendations(patterns, user_context)
      |> Enum.sort_by(& &1.score, :desc)
      |> Enum.take(limit)
      |> Enum.map(&format_recommendation/1)

    {:ok, recommendations}
  end

  @doc """
  Checks compatibility between tools for composition.
  """
  def check_compatibility(tool1_name, tool2_name) do
    with {:ok, tool1_module} <- Registry.get(tool1_name),
         {:ok, tool2_module} <- Registry.get(tool2_name) do
      compatibility = analyze_compatibility(tool1_module, tool2_module)
      {:ok, compatibility}
    end
  end

  @doc """
  Profiles tool performance and provides optimization suggestions.
  """
  def profile_tool(tool_name, opts \\ []) do
    duration = Keyword.get(opts, :duration, :last_24_hours)

    with {:ok, tool_module} <- Registry.get(tool_name) do
      # Get performance metrics
      metrics = %{
        execution_time_ms: duration,
        success_rate: 0.95,
        error_rate: 0.05
      }

      # Analyze performance
      analysis = analyze_performance(metrics, tool_module)

      # Generate suggestions
      suggestions = generate_optimization_suggestions(analysis)

      {:ok,
       %{
         tool_name: tool_name,
         metrics: metrics,
         analysis: analysis,
         suggestions: suggestions
       }}
    end
  end

  @doc """
  Discovers tools similar to a given tool.
  """
  def find_similar_tools(tool_name, opts \\ []) do
    limit = Keyword.get(opts, :limit, 5)

    with {:ok, reference_tool} <- Registry.get(tool_name) do
      reference_features = extract_tool_features(reference_tool)

      similar_tools =
        Registry.list()
        |> Enum.reject(fn tool -> Tool.metadata(tool).name == tool_name end)
        |> Enum.map(fn tool_module ->
          features = extract_tool_features(tool_module)
          similarity = calculate_similarity(reference_features, features)
          {tool_module, similarity}
        end)
        |> Enum.sort_by(fn {_, similarity} -> similarity end, :desc)
        |> Enum.take(limit)
        |> Enum.map(fn {tool_module, similarity} ->
          format_similar_tool(tool_module, similarity)
        end)

      {:ok, similar_tools}
    end
  end

  @doc """
  Analyzes tool usage trends over time.
  """
  def analyze_trends(opts \\ []) do
    period = Keyword.get(opts, :period, :last_7_days)
    group_by = Keyword.get(opts, :group_by, :day)

    # Get execution data
    executions = get_executions_for_period(period)

    # Group by time period
    grouped = group_executions(executions, group_by)

    # Calculate trends
    trends = %{
      usage_trend: calculate_usage_trend(grouped),
      popular_tools: get_popular_tools(executions),
      error_trends: calculate_error_trends(grouped),
      performance_trends: calculate_performance_trends(grouped)
    }

    {:ok, trends}
  end

  # Private functions

  defp preprocess_query(query) do
    query
    |> String.downcase()
    |> String.split(~r/\s+/)
    |> Enum.reject(&(&1 in ["the", "a", "an", "and", "or", "for", "to", "of"]))
  end

  defp calculate_semantic_score(tool_module, query_terms) do
    metadata = Tool.metadata(tool_module)
    parameters = Tool.parameters(tool_module)

    # Build searchable text
    searchable_text = build_searchable_text(metadata, parameters)

    # Calculate term frequency score
    term_scores =
      Enum.map(query_terms, fn term ->
        occurrences = count_term_occurrences(term, searchable_text)
        if occurrences > 0, do: :math.log(1 + occurrences), else: 0
      end)

    # Weight different fields
    name_boost =
      if String.contains?(String.downcase(to_string(metadata.name)), Enum.join(query_terms, " ")), do: 10, else: 0

    Enum.sum(term_scores) + name_boost
  end

  defp build_searchable_text(metadata, parameters) do
    param_text =
      parameters
      |> Enum.map(fn p -> "#{p.name} #{p.description}" end)
      |> Enum.join(" ")

    """
    #{metadata.name} #{metadata.description} #{metadata[:long_description] || ""}
    #{metadata[:category] || ""} #{param_text}
    """
    |> String.downcase()
  end

  defp count_term_occurrences(term, text) do
    text
    |> String.split(term)
    |> length()
    |> Kernel.-(1)
  end

  defp build_search_result(tool_module, score, query_terms) do
    metadata = Tool.metadata(tool_module)

    # Find matching context
    context = find_matching_context(tool_module, query_terms)

    %{
      tool_name: metadata.name,
      description: metadata.description,
      category: metadata[:category] || "general",
      relevance_score: Float.round(score, 2),
      matching_context: context,
      quick_example: get_quick_example(tool_module)
    }
  end

  defp find_matching_context(tool_module, query_terms) do
    metadata = Tool.metadata(tool_module)
    text = metadata.description || ""

    # Find sentences containing query terms
    sentences = String.split(text, ~r/[.!?]/)

    matching_sentence =
      Enum.find(sentences, fn sentence ->
        sentence_lower = String.downcase(sentence)
        Enum.any?(query_terms, &String.contains?(sentence_lower, &1))
      end)

    if matching_sentence do
      highlight_terms(String.trim(matching_sentence), query_terms)
    else
      String.slice(text, 0, 100) <> "..."
    end
  end

  defp highlight_terms(text, terms) do
    Enum.reduce(terms, text, fn term, acc ->
      String.replace(acc, ~r/\b#{term}\b/i, "**\\0**")
    end)
  end

  defp get_quick_example(tool_module) do
    if function_exported?(tool_module, :examples, 0) do
      case tool_module.examples() do
        [example | _] -> Map.get(example, :code, "No example available")
        _ -> "No example available"
      end
    else
      "No example available"
    end
  end

  defp get_user_history(user_context) do
    filter = %{
      session_id: user_context[:session_id],
      limit: 100
    }

    case StatePersistence.get_history(filter) do
      {:ok, history} -> history
      _ -> []
    end
  end

  defp analyze_usage_patterns(history) do
    # Group by tool
    tool_usage = Enum.group_by(history, & &1.tool_name)

    # Calculate patterns
    %{
      frequently_used: get_frequently_used_tools(tool_usage),
      recent_tools: get_recent_tools(history),
      success_rates: calculate_success_rates(tool_usage),
      typical_sequences: find_tool_sequences(history),
      peak_usage_times: find_peak_usage_times(history)
    }
  end

  defp get_frequently_used_tools(tool_usage) do
    tool_usage
    |> Enum.map(fn {tool, executions} -> {tool, length(executions)} end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(5)
    |> Enum.map(fn {tool, _} -> tool end)
  end

  defp get_recent_tools(history) do
    history
    |> Enum.sort_by(& &1.started_at, {:desc, DateTime})
    |> Enum.map(& &1.tool_name)
    |> Enum.uniq()
    |> Enum.take(5)
  end

  defp calculate_success_rates(tool_usage) do
    Enum.map(tool_usage, fn {tool, executions} ->
      total = length(executions)
      successful = Enum.count(executions, &(&1.status == :success))
      {tool, if(total > 0, do: successful / total, else: 0)}
    end)
    |> Enum.into(%{})
  end

  defp find_tool_sequences(history) do
    # Find common tool pairs
    history
    |> Enum.sort_by(& &1.started_at)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> {a.tool_name, b.tool_name} end)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(5)
  end

  defp find_peak_usage_times(history) do
    history
    |> Enum.map(fn execution ->
      execution.started_at
      |> DateTime.to_time()
      |> Time.to_erl()
      # Get hour
      |> elem(0)
    end)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {hour, _} -> hour end)
  end

  defp get_recommendation_candidates(patterns, _user_context) do
    all_tools = Registry.list()
    used_tools = patterns.frequently_used ++ patterns.recent_tools

    # Get tools not recently used
    unused_tools =
      Enum.reject(all_tools, fn tool ->
        Tool.metadata(tool).name in used_tools
      end)

    # Add tools that follow common sequences
    sequence_tools =
      patterns.typical_sequences
      |> Enum.flat_map(fn {{_, next_tool}, _} -> [next_tool] end)
      |> Enum.uniq()
      |> Enum.map(&Registry.get/1)
      |> Enum.filter(fn
        {:ok, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:ok, tool} -> tool end)

    Enum.uniq(unused_tools ++ sequence_tools)
  end

  defp score_recommendations(candidates, patterns, _user_context) do
    Enum.map(candidates, fn tool_module ->
      metadata = Tool.metadata(tool_module)

      # Calculate various scores
      category_score = calculate_category_affinity(metadata, patterns)
      sequence_score = calculate_sequence_score(metadata.name, patterns)
      performance_score = get_tool_performance_score(metadata.name)

      total_score = category_score * 0.4 + sequence_score * 0.4 + performance_score * 0.2

      %{
        tool_module: tool_module,
        score: total_score,
        reasons: build_recommendation_reasons(metadata, category_score, sequence_score, performance_score)
      }
    end)
  end

  defp calculate_category_affinity(metadata, patterns) do
    # Score based on category usage
    category = metadata[:category] || "general"

    category_usage =
      patterns.frequently_used
      |> Enum.map(&Registry.get/1)
      |> Enum.filter(fn
        {:ok, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:ok, tool} -> Tool.metadata(tool)[:category] || "general" end)
      |> Enum.frequencies()

    Map.get(category_usage, category, 0) / max(Enum.sum(Map.values(category_usage)), 1)
  end

  defp calculate_sequence_score(tool_name, patterns) do
    # Check if this tool commonly follows recently used tools
    relevant_sequences =
      patterns.typical_sequences
      |> Enum.filter(fn {{_, next}, _} -> next == tool_name end)
      |> Enum.map(fn {_, count} -> count end)
      |> Enum.sum()

    min(relevant_sequences / 10, 1.0)
  end

  defp get_tool_performance_score(_tool_name) do
    # Mock metrics for now
    metrics = %{
      success_rate: 95,
      average_duration_ms: 100,
      total_executions: 1000
    }

    # Calculate performance score based on success rate and speed
    success_score = (metrics[:success_rate] || 50) / 100

    speed_score =
      case metrics[:average_duration_ms] do
        nil -> 0.5
        ms when ms < 100 -> 1.0
        ms when ms < 500 -> 0.8
        ms when ms < 1000 -> 0.6
        ms when ms < 5000 -> 0.4
        _ -> 0.2
      end

    success_score * 0.7 + speed_score * 0.3
  end

  defp build_recommendation_reasons(_metadata, category_score, sequence_score, performance_score) do
    reasons = []

    reasons = if category_score > 0.3, do: ["Popular in your preferred categories" | reasons], else: reasons
    reasons = if sequence_score > 0.3, do: ["Often used after your recent tools" | reasons], else: reasons
    reasons = if performance_score > 0.8, do: ["High success rate" | reasons], else: reasons

    if reasons == [] do
      ["Expands your toolkit capabilities"]
    else
      reasons
    end
  end

  defp format_recommendation(rec) do
    metadata = Tool.metadata(rec.tool_module)

    %{
      tool_name: metadata.name,
      description: metadata.description,
      category: metadata[:category] || "general",
      confidence: Float.round(rec.score * 100, 1),
      reasons: rec.reasons
    }
  end

  defp analyze_compatibility(tool1_module, tool2_module) do
    metadata1 = Tool.metadata(tool1_module)
    metadata2 = Tool.metadata(tool2_module)

    # Check output/input compatibility
    output_compatible = check_output_compatibility(tool1_module, tool2_module)

    # Check resource conflicts
    resource_conflicts = check_resource_conflicts(tool1_module, tool2_module)

    # Check semantic compatibility
    semantic_compatible = check_semantic_compatibility(metadata1, metadata2)

    %{
      compatible: output_compatible && resource_conflicts == [] && semantic_compatible,
      output_compatible: output_compatible,
      resource_conflicts: resource_conflicts,
      semantic_compatible: semantic_compatible,
      suggested_order: suggest_execution_order(tool1_module, tool2_module),
      warnings: build_compatibility_warnings(resource_conflicts, semantic_compatible)
    }
  end

  defp check_output_compatibility(_tool1, _tool2) do
    # In future, analyze actual output/input types
    true
  end

  defp check_resource_conflicts(tool1, tool2) do
    security1 = Tool.security(tool1) || %{}
    security2 = Tool.security(tool2) || %{}

    conflicts = []

    # Check for exclusive resource access
    if security1[:exclusive_access] and security2[:exclusive_access] do
      conflicts ++ ["Both tools require exclusive access"]
    else
      conflicts
    end
  end

  defp check_semantic_compatibility(metadata1, metadata2) do
    # Simple category-based check for now
    cat1 = metadata1[:category] || "general"
    cat2 = metadata2[:category] || "general"

    compatible_categories = %{
      "data" => ["analysis", "visualization", "transform"],
      "analysis" => ["data", "visualization", "report"],
      "visualization" => ["data", "analysis"],
      "transform" => ["data", "analysis"]
    }

    cat2 in (Map.get(compatible_categories, cat1, []) ++ [cat1, "general"])
  end

  defp suggest_execution_order(tool1, tool2) do
    # Suggest based on typical data flow
    cat1 = Tool.metadata(tool1)[:category] || "general"
    cat2 = Tool.metadata(tool2)[:category] || "general"

    order_priority = %{
      "data" => 1,
      "transform" => 2,
      "analysis" => 3,
      "visualization" => 4,
      "report" => 5
    }

    p1 = Map.get(order_priority, cat1, 10)
    p2 = Map.get(order_priority, cat2, 10)

    if p1 <= p2 do
      [Tool.metadata(tool1).name, Tool.metadata(tool2).name]
    else
      [Tool.metadata(tool2).name, Tool.metadata(tool1).name]
    end
  end

  defp build_compatibility_warnings(conflicts, semantic_compatible) do
    warnings = conflicts

    if not semantic_compatible do
      ["Tools may not work well together based on their categories" | warnings]
    else
      warnings
    end
  end

  defp extract_tool_features(tool_module) do
    metadata = Tool.metadata(tool_module)
    parameters = Tool.parameters(tool_module)
    security = Tool.security(tool_module) || %{}
    execution = Tool.execution(tool_module) || %{}

    %{
      category: metadata[:category] || "general",
      param_count: length(parameters),
      param_types: Enum.map(parameters, & &1.type) |> Enum.uniq(),
      security_level: security[:level] || :balanced,
      async: execution[:async] || false,
      timeout: execution[:timeout] || 30_000
    }
  end

  defp calculate_similarity(features1, features2) do
    # Simple similarity calculation
    scores = [
      if(features1.category == features2.category, do: 0.3, else: 0),
      similarity_score(features1.param_count, features2.param_count, 5) * 0.2,
      jaccard_similarity(features1.param_types, features2.param_types) * 0.2,
      if(features1.security_level == features2.security_level, do: 0.1, else: 0),
      if(features1.async == features2.async, do: 0.1, else: 0),
      similarity_score(features1.timeout, features2.timeout, 10_000) * 0.1
    ]

    Enum.sum(scores)
  end

  defp similarity_score(val1, val2, max_diff) do
    diff = abs(val1 - val2)
    max(0, 1 - diff / max_diff)
  end

  defp jaccard_similarity(set1, set2) do
    intersection = MapSet.intersection(MapSet.new(set1), MapSet.new(set2)) |> MapSet.size()
    union = MapSet.union(MapSet.new(set1), MapSet.new(set2)) |> MapSet.size()

    if union == 0, do: 0, else: intersection / union
  end

  defp format_similar_tool(tool_module, similarity) do
    metadata = Tool.metadata(tool_module)

    %{
      tool_name: metadata.name,
      description: metadata.description,
      category: metadata[:category] || "general",
      similarity_score: Float.round(similarity * 100, 1)
    }
  end

  defp analyze_performance(metrics, tool_module) do
    execution = Tool.execution(tool_module) || %{}
    expected_duration = execution[:timeout] || 30_000

    %{
      performance_rating: rate_performance(metrics),
      bottlenecks: identify_bottlenecks(metrics, expected_duration),
      optimization_potential: calculate_optimization_potential(metrics)
    }
  end

  defp rate_performance(metrics) do
    score =
      metrics.success_rate * 0.4 +
        min(100, 100 - metrics.average_duration_ms / 100) * 0.3 +
        min(100, 100 - metrics.error_rate) * 0.3

    cond do
      score >= 90 -> :excellent
      score >= 75 -> :good
      score >= 50 -> :fair
      true -> :poor
    end
  end

  defp identify_bottlenecks(metrics, expected_duration) do
    bottlenecks = []

    bottlenecks =
      if metrics.average_duration_ms > expected_duration * 0.8,
        do: ["Execution time approaching timeout" | bottlenecks],
        else: bottlenecks

    bottlenecks = if metrics.error_rate > 5, do: ["High error rate" | bottlenecks], else: bottlenecks

    bottlenecks =
      if metrics.max_duration_ms > expected_duration * 1.5,
        do: ["Occasional very slow executions" | bottlenecks],
        else: bottlenecks

    bottlenecks
  end

  defp calculate_optimization_potential(metrics) do
    # Estimate how much performance could improve
    duration_potential = max(0, (metrics.average_duration_ms - 100) / metrics.average_duration_ms)
    error_potential = metrics.error_rate / 100

    (duration_potential * 0.6 + error_potential * 0.4) * 100
  end

  defp generate_optimization_suggestions(analysis) do
    suggestions = []

    suggestions =
      case analysis.performance_rating do
        :poor -> ["Consider reviewing tool implementation for performance issues" | suggestions]
        :fair -> ["Look for caching opportunities" | suggestions]
        _ -> suggestions
      end

    suggestions =
      if "High error rate" in analysis.bottlenecks,
        do: ["Add better error handling and validation" | suggestions],
        else: suggestions

    suggestions =
      if analysis.optimization_potential > 30,
        do: ["Significant optimization potential detected" | suggestions],
        else: suggestions

    suggestions
  end

  defp get_executions_for_period(period) do
    filter =
      case period do
        :last_24_hours -> %{from_date: DateTime.add(DateTime.utc_now(), -86_400, :second)}
        :last_7_days -> %{from_date: DateTime.add(DateTime.utc_now(), -604_800, :second)}
        :last_30_days -> %{from_date: DateTime.add(DateTime.utc_now(), -2_592_000, :second)}
        _ -> %{}
      end

    case StatePersistence.get_history(filter) do
      {:ok, history} -> history
      _ -> []
    end
  end

  defp group_executions(executions, :day) do
    executions
    |> Enum.group_by(fn exec ->
      exec.started_at
      |> DateTime.to_date()
    end)
  end

  defp group_executions(executions, :hour) do
    executions
    |> Enum.group_by(fn exec ->
      exec.started_at
      |> DateTime.truncate(:hour)
    end)
  end

  defp calculate_usage_trend(grouped) do
    sorted_days =
      grouped
      |> Enum.map(fn {date, execs} -> {date, length(execs)} end)
      |> Enum.sort_by(fn {date, _} -> date end)

    if length(sorted_days) >= 2 do
      {first_date, first_count} = List.first(sorted_days)
      {last_date, last_count} = List.last(sorted_days)
      days_diff = Date.diff(last_date, first_date) + 1

      trend = (last_count - first_count) / days_diff

      %{
        direction: if(trend > 0, do: :increasing, else: :decreasing),
        change_per_day: Float.round(trend, 2),
        total_change: last_count - first_count
      }
    else
      %{direction: :stable, change_per_day: 0, total_change: 0}
    end
  end

  defp get_popular_tools(executions) do
    executions
    |> Enum.group_by(& &1.tool_name)
    |> Enum.map(fn {tool, execs} -> {tool, length(execs)} end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(10)
    |> Enum.map(fn {tool, count} -> %{tool_name: tool, execution_count: count} end)
  end

  defp calculate_error_trends(grouped) do
    grouped
    |> Enum.map(fn {period, execs} ->
      total = length(execs)
      errors = Enum.count(execs, &(&1.status == :failed))
      error_rate = if total > 0, do: errors / total * 100, else: 0

      {period, %{total: total, errors: errors, error_rate: Float.round(error_rate, 2)}}
    end)
    |> Enum.into(%{})
  end

  defp calculate_performance_trends(grouped) do
    grouped
    |> Enum.map(fn {period, execs} ->
      durations =
        execs
        |> Enum.filter(& &1[:duration_ms])
        |> Enum.map(& &1.duration_ms)

      avg_duration =
        if length(durations) > 0,
          do: Enum.sum(durations) / length(durations),
          else: 0

      {period,
       %{
         average_duration_ms: Float.round(avg_duration, 2),
         min_duration_ms: if(length(durations) > 0, do: Enum.min(durations), else: 0),
         max_duration_ms: if(length(durations) > 0, do: Enum.max(durations), else: 0)
       }}
    end)
    |> Enum.into(%{})
  end
end
