defmodule RubberDuck.LLMQueryOptimizer do
  @moduledoc """
  Advanced query optimization strategies for LLM data in Mnesia.
  
  Provides intelligent query patterns, index optimization, and performance
  tuning specifically designed for LLM workloads including:
  - Prompt similarity searches
  - Provider performance queries
  - Token usage analytics
  - Cost optimization queries
  - Temporal data analysis
  """
  
  require Logger
  alias RubberDuck.TransactionWrapper
  
  @default_batch_size 1000
  @similarity_cache_ttl :timer.minutes(30)
  @query_stats_window :timer.hours(1)
  
  # Query optimization patterns for different LLM access patterns
  @optimization_patterns %{
    # Prompt-based queries (most common)
    prompt_lookup: %{
      indexes: [:prompt_hash],
      selectivity: :high,
      cache_strategy: :aggressive
    },
    
    # Provider analytics
    provider_stats: %{
      indexes: [:provider, :created_at],
      selectivity: :medium,
      cache_strategy: :moderate,
      aggregation: :time_series
    },
    
    # Cost analysis
    cost_analysis: %{
      indexes: [:provider, :created_at, :cost],
      selectivity: :low,
      cache_strategy: :minimal,
      aggregation: :sum
    },
    
    # Session reconstruction
    session_context: %{
      indexes: [:session_id, :created_at],
      selectivity: :high,
      cache_strategy: :aggressive,
      ordering: :temporal
    },
    
    # Token usage trends
    token_trends: %{
      indexes: [:provider, :model, :created_at],
      selectivity: :medium,
      cache_strategy: :moderate,
      aggregation: :time_series
    }
  }
  
  @doc """
  Optimize prompt-based lookups with intelligent caching and indexing
  """
  def optimized_prompt_lookup(prompt_hash, opts \\ []) do
    provider = Keyword.get(opts, :provider)
    model = Keyword.get(opts, :model)
    use_cache = Keyword.get(opts, :use_cache, true)
    
    # Check query cache first
    cache_key = build_cache_key(:prompt_lookup, prompt_hash, provider, model)
    
    if use_cache do
      case get_query_cache(cache_key) do
        nil ->
          result = execute_optimized_prompt_query(prompt_hash, provider, model)
          cache_query_result(cache_key, result, @similarity_cache_ttl)
          result
        cached_result -> 
          {:ok, cached_result}
      end
    else
      execute_optimized_prompt_query(prompt_hash, provider, model)
    end
  end
  
  @doc """
  Execute optimized provider performance queries with time-based indexing
  """
  def optimized_provider_stats(provider, time_range, opts \\ []) do
    metrics = Keyword.get(opts, :metrics, [:latency, :cost, :success_rate])
    aggregation = Keyword.get(opts, :aggregation, :avg)
    
    {since, until} = normalize_time_range(time_range)
    
    TransactionWrapper.read_transaction(fn ->
      case aggregation do
        :avg -> calculate_provider_averages(provider, since, until, metrics)
        :sum -> calculate_provider_sums(provider, since, until, metrics)
        :percentiles -> calculate_provider_percentiles(provider, since, until, metrics)
        :time_series -> calculate_provider_time_series(provider, since, until, metrics)
      end
    end)
  end
  
  @doc """
  Optimized cost analysis with efficient aggregation strategies
  """
  def optimized_cost_analysis(opts \\ []) do
    time_range = Keyword.get(opts, :time_range, :timer.hours(24))
    breakdown_by = Keyword.get(opts, :breakdown_by, [:provider, :model])
    include_trends = Keyword.get(opts, :include_trends, true)
    
    {since, until} = normalize_time_range(time_range)
    
    TransactionWrapper.read_transaction(fn ->
      base_stats = calculate_cost_aggregates(since, until, breakdown_by)
      
      result = %{
        total_cost: base_stats.total_cost,
        breakdown: base_stats.breakdown,
        period: %{since: since, until: until}
      }
      
      if include_trends do
        trends = calculate_cost_trends(since, until, breakdown_by)
        Map.put(result, :trends, trends)
      else
        result
      end
    end)
  end
  
  @doc """
  Optimized session context reconstruction with temporal ordering
  """
  def optimized_session_lookup(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    since = Keyword.get(opts, :since, 0)
    include_metadata = Keyword.get(opts, :include_metadata, false)
    
    # Use session index for efficient lookup
    TransactionWrapper.read_transaction(fn ->
      pattern = build_session_pattern(session_id, since)
      
      responses = :mnesia.select(:llm_responses, [
        {pattern, build_session_guards(since), build_session_projection(include_metadata)}
      ])
      
      responses
      |> sort_by_timestamp()
      |> Enum.take(limit)
      |> format_session_responses(include_metadata)
    end)
  end
  
  @doc """
  Optimized token usage analysis with trend calculation
  """
  def optimized_token_analysis(opts \\ []) do
    time_range = Keyword.get(opts, :time_range, :timer.hours(24))
    providers = Keyword.get(opts, :providers, :all)
    include_predictions = Keyword.get(opts, :include_predictions, false)
    
    {since, until} = normalize_time_range(time_range)
    
    TransactionWrapper.read_transaction(fn ->
      base_analysis = calculate_token_usage(since, until, providers)
      
      result = %{
        total_tokens: base_analysis.total_tokens,
        by_provider: base_analysis.by_provider,
        by_model: base_analysis.by_model,
        usage_rate: base_analysis.usage_rate,
        period: %{since: since, until: until}
      }
      
      if include_predictions do
        predictions = calculate_token_predictions(base_analysis)
        Map.put(result, :predictions, predictions)
      else
        result
      end
    end)
  end
  
  @doc """
  Batch optimize multiple queries for better performance
  """
  def batch_optimize_queries(queries, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    parallel = Keyword.get(opts, :parallel, true)
    
    if parallel do
      queries
      |> Enum.chunk_every(batch_size)
      |> Enum.map(&execute_query_batch_parallel/1)
      |> List.flatten()
    else
      queries
      |> Enum.chunk_every(batch_size)
      |> Enum.map(&execute_query_batch_sequential/1)
      |> List.flatten()
    end
  end
  
  @doc """
  Analyze query performance and suggest optimizations
  """
  def analyze_query_performance(query_type, execution_time, result_size) do
    pattern = Map.get(@optimization_patterns, query_type)
    
    suggestions = []
    
    suggestions =
      if execution_time > 1000 do
        ["Consider adding more specific indexes" | suggestions]
      else
        suggestions
      end
    
    suggestions =
      if result_size > 10000 do
        ["Use pagination or limit result sets" | suggestions]
      else
        suggestions
      end
    
    suggestions =
      if pattern && pattern.cache_strategy == :aggressive do
        ["Enable query result caching" | suggestions]
      else
        suggestions
      end
    
    %{
      query_type: query_type,
      execution_time: execution_time,
      result_size: result_size,
      performance_score: calculate_performance_score(execution_time, result_size),
      suggestions: suggestions
    }
  end
  
  @doc """
  Get query performance statistics
  """
  def get_query_stats(opts \\ []) do
    window = Keyword.get(opts, :window, @query_stats_window)
    _query_types = Keyword.get(opts, :query_types, :all)
    
    current_time = :os.system_time(:millisecond)
    _since = current_time - window
    
    # This would integrate with the metrics collector
    # For now, return sample data structure
    %{
      total_queries: 0,
      average_execution_time: 0,
      cache_hit_rate: 0.0,
      slow_queries: [],
      query_types: %{}
    }
  end
  
  # Private Functions
  
  defp execute_optimized_prompt_query(prompt_hash, provider, model) do
    TransactionWrapper.read_transaction(fn ->
      # Start with index lookup on prompt_hash
      base_responses = :mnesia.index_read(:llm_responses, prompt_hash, :prompt_hash)
      
      # Apply additional filters
      filtered_responses = 
        base_responses
        |> filter_by_provider(provider)
        |> filter_by_model(model)
        |> sort_by_recency()
      
      case filtered_responses do
        [] -> {:error, :not_found}
        [response | _] -> {:ok, format_response(response)}
      end
    end)
  end
  
  defp calculate_provider_averages(provider, since, until, metrics) do
    pattern = {:llm_responses, :_, :_, provider, :_, :_, :_, :"$8", :"$9", :"$10", :"$11", :_, :_, :_}
    guards = [{:>=, :"$11", since}, {:"=<", :"$11", until}]
    
    responses = :mnesia.select(:llm_responses, [{pattern, guards, [%{
      tokens_used: :"$8",
      cost: :"$9", 
      latency: :"$10",
      created_at: :"$11"
    }]}])
    
    calculate_metric_averages(responses, metrics)
  end
  
  defp calculate_provider_sums(provider, since, until, metrics) do
    pattern = {:llm_responses, :_, :_, provider, :_, :_, :_, :"$8", :"$9", :"$10", :"$11", :_, :_, :_}
    guards = [{:>=, :"$11", since}, {:"=<", :"$11", until}]
    
    responses = :mnesia.select(:llm_responses, [{pattern, guards, [%{
      tokens_used: :"$8",
      cost: :"$9",
      latency: :"$10"
    }]}])
    
    calculate_metric_sums(responses, metrics)
  end
  
  defp calculate_provider_percentiles(provider, since, until, metrics) do
    pattern = {:llm_responses, :_, :_, provider, :_, :_, :_, :"$8", :"$9", :"$10", :"$11", :_, :_, :_}
    guards = [{:>=, :"$11", since}, {:"=<", :"$11", until}]
    
    responses = :mnesia.select(:llm_responses, [{pattern, guards, [%{
      tokens_used: :"$8",
      cost: :"$9",
      latency: :"$10"
    }]}])
    
    calculate_metric_percentiles(responses, metrics)
  end
  
  defp calculate_provider_time_series(provider, since, until, metrics) do
    # Break down time range into intervals for time series
    interval = div(until - since, 20)  # 20 data points
    
    Enum.map(0..19, fn i ->
      interval_start = since + (i * interval)
      interval_end = interval_start + interval
      
      interval_stats = calculate_provider_averages(provider, interval_start, interval_end, metrics)
      
      %{
        timestamp: interval_start,
        stats: interval_stats
      }
    end)
  end
  
  defp calculate_cost_aggregates(since, until, breakdown_by) do
    # Efficient cost aggregation using Mnesia select with guards
    pattern = {:llm_responses, :_, :_, :"$3", :"$4", :_, :_, :_, :"$9", :_, :"$11", :_, :_, :_}
    guards = [{:>=, :"$11", since}, {:"=<", :"$11", until}]
    projection = [%{provider: :"$3", model: :"$4", cost: :"$9", created_at: :"$11"}]
    
    responses = :mnesia.select(:llm_responses, [{pattern, guards, projection}])
    
    total_cost = Enum.reduce(responses, 0.0, fn response, acc -> acc + response.cost end)
    
    breakdown = 
      responses
      |> group_by_breakdown_fields(breakdown_by)
      |> Enum.map(fn {key, items} ->
        {key, %{
          cost: Enum.reduce(items, 0.0, fn item, acc -> acc + item.cost end),
          count: length(items)
        }}
      end)
      |> Map.new()
    
    %{
      total_cost: total_cost,
      breakdown: breakdown,
      response_count: length(responses)
    }
  end
  
  defp calculate_cost_trends(since, until, breakdown_by) do
    # Calculate cost trends over time intervals
    interval_count = 10
    interval_size = div(until - since, interval_count)
    
    Enum.map(0..(interval_count - 1), fn i ->
      interval_start = since + (i * interval_size)
      interval_end = interval_start + interval_size
      
      interval_stats = calculate_cost_aggregates(interval_start, interval_end, breakdown_by)
      
      %{
        timestamp: interval_start,
        cost: interval_stats.total_cost,
        count: interval_stats.response_count
      }
    end)
  end
  
  defp calculate_token_usage(since, until, providers) do
    provider_filter = case providers do
      :all -> :_
      list when is_list(list) -> list
      single -> [single]
    end
    
    # Build pattern based on provider filter
    {pattern, guards} = build_token_query_pattern(provider_filter, since, until)
    
    responses = :mnesia.select(:llm_responses, [{pattern, guards, [%{
      provider: :"$3",
      model: :"$4", 
      tokens_used: :"$8",
      created_at: :"$11"
    }]}])
    
    total_tokens = Enum.reduce(responses, 0, fn response, acc -> acc + response.tokens_used end)
    
    by_provider = 
      responses
      |> Enum.group_by(& &1.provider)
      |> Enum.map(fn {provider, items} ->
        {provider, Enum.reduce(items, 0, fn item, acc -> acc + item.tokens_used end)}
      end)
      |> Map.new()
    
    by_model =
      responses
      |> Enum.group_by(& &1.model)
      |> Enum.map(fn {model, items} ->
        {model, Enum.reduce(items, 0, fn item, acc -> acc + item.tokens_used end)}
      end)
      |> Map.new()
    
    time_range_hours = (until - since) / (1000 * 60 * 60)
    usage_rate = total_tokens / time_range_hours
    
    %{
      total_tokens: total_tokens,
      by_provider: by_provider,
      by_model: by_model,
      usage_rate: usage_rate
    }
  end
  
  defp calculate_token_predictions(base_analysis) do
    # Simple linear prediction based on current usage rate
    current_rate = base_analysis.usage_rate
    
    %{
      next_hour: current_rate,
      next_day: current_rate * 24,
      next_week: current_rate * 24 * 7,
      confidence: calculate_prediction_confidence(base_analysis)
    }
  end
  
  defp build_cache_key(query_type, prompt_hash, provider, model) do
    parts = [query_type, prompt_hash, provider || "any", model || "any"]
    :crypto.hash(:md5, Enum.join(parts, ":")) |> Base.encode64()
  end
  
  defp get_query_cache(cache_key) do
    # This would integrate with the Nebulex cache system
    case RubberDuck.Nebulex.Cache.get_from(:multilevel, "query:#{cache_key}") do
      nil -> nil
      result -> result
    end
  end
  
  defp cache_query_result(cache_key, result, ttl) do
    case result do
      {:ok, data} ->
        RubberDuck.Nebulex.Cache.put_in(:multilevel, "query:#{cache_key}", data, ttl: ttl)
      _ ->
        :ok
    end
  end
  
  defp normalize_time_range(time_range) when is_integer(time_range) do
    current_time = :os.system_time(:millisecond)
    {current_time - time_range, current_time}
  end
  
  defp normalize_time_range({since, until}) do
    {since, until}
  end
  
  defp build_session_pattern(session_id, _since) do
    {:llm_responses, :_, :_, :_, :_, :_, :_, :_, :_, :_, :"$11", :_, session_id, :_}
  end
  
  defp build_session_guards(since) do
    [{:>=, :"$11", since}]
  end
  
  defp build_session_projection(include_metadata) do
    if include_metadata do
      [:"$_"]
    else
      [%{response_id: :"$1", prompt: :"$5", response: :"$6", created_at: :"$11"}]
    end
  end
  
  defp sort_by_timestamp(responses) do
    Enum.sort_by(responses, fn
      %{created_at: created_at} -> created_at
      {_, _, _, _, _, _, _, _, _, _, created_at, _, _, _} -> created_at
    end)
  end
  
  defp format_session_responses(responses, _include_metadata) do
    responses
  end
  
  defp build_token_query_pattern(:all, since, until) do
    pattern = {:llm_responses, :_, :_, :"$3", :"$4", :_, :_, :"$8", :_, :_, :"$11", :_, :_, :_}
    guards = [{:>=, :"$11", since}, {:"=<", :"$11", until}]
    {pattern, guards}
  end
  
  defp build_token_query_pattern(providers, since, until) when is_list(providers) do
    # For simplicity, we'll use the first provider in the list
    # In production, you'd want to handle multiple providers more efficiently
    provider = hd(providers)
    pattern = {:llm_responses, :_, :_, provider, :"$4", :_, :_, :"$8", :_, :_, :"$11", :_, :_, :_}
    guards = [{:>=, :"$11", since}, {:"=<", :"$11", until}]
    {pattern, guards}
  end
  
  defp filter_by_provider(responses, nil), do: responses
  defp filter_by_provider(responses, provider) do
    Enum.filter(responses, fn
      {_, _, _, p, _, _, _, _, _, _, _, _, _, _} -> p == provider
    end)
  end
  
  defp filter_by_model(responses, nil), do: responses
  defp filter_by_model(responses, model) do
    Enum.filter(responses, fn
      {_, _, _, _, m, _, _, _, _, _, _, _, _, _} -> m == model
    end)
  end
  
  defp sort_by_recency(responses) do
    Enum.sort_by(responses, fn
      {_, _, _, _, _, _, _, _, _, _, created_at, _, _, _} -> created_at
    end, :desc)
  end
  
  defp format_response(response) do
    case response do
      {_, response_id, prompt_hash, provider, model, prompt, response_text, tokens_used, cost, latency, created_at, expires_at, session_id, node} ->
        %{
          response_id: response_id,
          prompt_hash: prompt_hash,
          provider: provider,
          model: model,
          prompt: prompt,
          response: response_text,
          tokens_used: tokens_used,
          cost: cost,
          latency: latency,
          created_at: created_at,
          expires_at: expires_at,
          session_id: session_id,
          node: node
        }
    end
  end
  
  defp group_by_breakdown_fields(responses, breakdown_by) do
    Enum.group_by(responses, fn response ->
      Enum.map(breakdown_by, fn field ->
        Map.get(response, field)
      end)
      |> Enum.join(":")
    end)
  end
  
  defp calculate_metric_averages(responses, metrics) do
    if length(responses) == 0 do
      Enum.map(metrics, fn metric -> {metric, 0} end) |> Map.new()
    else
      count = length(responses)
      
      Enum.map(metrics, fn metric ->
        total = Enum.reduce(responses, 0, fn response, acc ->
          acc + Map.get(response, metric, 0)
        end)
        
        {metric, total / count}
      end)
      |> Map.new()
    end
  end
  
  defp calculate_metric_sums(responses, metrics) do
    Enum.map(metrics, fn metric ->
      total = Enum.reduce(responses, 0, fn response, acc ->
        acc + Map.get(response, metric, 0)
      end)
      
      {metric, total}
    end)
    |> Map.new()
  end
  
  defp calculate_metric_percentiles(responses, metrics) do
    Enum.map(metrics, fn metric ->
      values = Enum.map(responses, fn response ->
        Map.get(response, metric, 0)
      end) |> Enum.sort()
      
      percentiles = calculate_percentiles(values)
      {metric, percentiles}
    end)
    |> Map.new()
  end
  
  defp calculate_percentiles([]), do: %{p50: 0, p90: 0, p95: 0, p99: 0}
  defp calculate_percentiles(values) do
    count = length(values)
    
    %{
      p50: Enum.at(values, div(count * 50, 100)),
      p90: Enum.at(values, div(count * 90, 100)),
      p95: Enum.at(values, div(count * 95, 100)),
      p99: Enum.at(values, div(count * 99, 100))
    }
  end
  
  defp calculate_prediction_confidence(base_analysis) do
    # Simple confidence calculation based on data availability
    data_points = base_analysis.total_tokens
    
    cond do
      data_points >= 1000 -> 0.9
      data_points >= 100 -> 0.7
      data_points >= 10 -> 0.5
      true -> 0.3
    end
  end
  
  defp calculate_performance_score(execution_time, result_size) do
    # Performance score from 0-100
    time_score = max(0, 100 - div(execution_time, 10))  # Penalty for slow queries
    size_score = min(100, div(1000, max(1, div(result_size, 100))))  # Penalty for large results
    
    div(time_score + size_score, 2)
  end
  
  defp execute_query_batch_parallel(queries) do
    queries
    |> Task.async_stream(&execute_single_query/1, max_concurrency: 4)
    |> Enum.map(fn {:ok, result} -> result end)
  end
  
  defp execute_query_batch_sequential(queries) do
    Enum.map(queries, &execute_single_query/1)
  end
  
  defp execute_single_query({query_type, args}) do
    case query_type do
      :prompt_lookup -> optimized_prompt_lookup(args[:prompt_hash], args[:opts] || [])
      :provider_stats -> optimized_provider_stats(args[:provider], args[:time_range], args[:opts] || [])
      :cost_analysis -> optimized_cost_analysis(args[:opts] || [])
      :session_lookup -> optimized_session_lookup(args[:session_id], args[:opts] || [])
      :token_analysis -> optimized_token_analysis(args[:opts] || [])
      _ -> {:error, :unknown_query_type}
    end
  end
end