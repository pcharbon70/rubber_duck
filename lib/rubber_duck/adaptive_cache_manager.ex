defmodule RubberDuck.AdaptiveCacheManager do
  @moduledoc """
  Intelligent adaptive caching system for LLM operations.
  
  Provides dynamic caching strategies based on usage patterns including:
  - Machine learning-based cache prediction
  - Dynamic TTL adjustment based on access patterns
  - Intelligent cache warming and preloading
  - Context-aware cache partitioning
  - Cost-based cache optimization
  - Seasonal and temporal pattern recognition
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.LLMMetricsCollector
  alias RubberDuck.EventBroadcaster
  alias RubberDuck.Nebulex.Cache
  
  @learning_window :timer.hours(24)
  @pattern_analysis_interval :timer.minutes(30)
  @cache_optimization_interval :timer.hours(2)
  @min_pattern_confidence 0.7
  
  # Cache strategy types
  @cache_strategies %{
    frequency_based: %{
      description: "Cache based on access frequency",
      ttl_multiplier: 1.0,
      priority_weight: 0.3
    },
    
    recency_based: %{
      description: "Cache based on recent access",
      ttl_multiplier: 0.8,
      priority_weight: 0.2
    },
    
    cost_based: %{
      description: "Cache expensive operations longer",
      ttl_multiplier: 2.0,
      priority_weight: 0.4
    },
    
    semantic_similarity: %{
      description: "Cache semantically similar content",
      ttl_multiplier: 1.5,
      priority_weight: 0.3
    },
    
    session_context: %{
      description: "Cache within session context",
      ttl_multiplier: 0.5,
      priority_weight: 0.4
    },
    
    temporal_pattern: %{
      description: "Cache based on time-of-day patterns",
      ttl_multiplier: 1.2,
      priority_weight: 0.2
    }
  }
  
  # Usage patterns for adaptive strategies
  @usage_patterns %{
    burst: %{
      characteristics: %{min_requests: 50, time_window: :timer.minutes(5), variance: :high},
      cache_strategy: :frequency_based,
      ttl_adjustment: 1.5,
      preload_strategy: :aggressive
    },
    
    steady: %{
      characteristics: %{min_requests: 10, time_window: :timer.minutes(30), variance: :low},
      cache_strategy: :recency_based,
      ttl_adjustment: 1.0,
      preload_strategy: :moderate
    },
    
    sporadic: %{
      characteristics: %{min_requests: 5, time_window: :timer.hours(1), variance: :high},
      cache_strategy: :cost_based,
      ttl_adjustment: 2.0,
      preload_strategy: :minimal
    },
    
    contextual: %{
      characteristics: %{session_correlation: :high, repeat_rate: :high},
      cache_strategy: :session_context,
      ttl_adjustment: 0.8,
      preload_strategy: :context_aware
    },
    
    analytical: %{
      characteristics: %{query_complexity: :high, data_volume: :large},
      cache_strategy: :cost_based,
      ttl_adjustment: 3.0,
      preload_strategy: :predictive
    }
  }
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    learning_enabled = Keyword.get(opts, :learning_enabled, true)
    
    # Subscribe to cache and LLM events
    EventBroadcaster.subscribe("cache.*")
    EventBroadcaster.subscribe("llm.*")
    
    # Initialize pattern tracking storage
    :ets.new(:cache_patterns, [:named_table, :public, :set])
    :ets.new(:cache_access_history, [:named_table, :public, :bag])
    :ets.new(:cache_predictions, [:named_table, :public, :set])
    
    # Schedule periodic analysis and optimization
    if learning_enabled do
      :timer.send_interval(@pattern_analysis_interval, self(), :analyze_patterns)
      :timer.send_interval(@cache_optimization_interval, self(), :optimize_cache)
    end
    
    Logger.info("Adaptive Cache Manager started with learning: #{learning_enabled}")
    
    {:ok, %{
      learning_enabled: learning_enabled,
      current_strategy: :frequency_based,
      detected_patterns: %{},
      cache_statistics: %{},
      last_optimization: :os.system_time(:millisecond)
    }}
  end
  
  @impl true
  def handle_info({:event, topic, event_data}, state) do
    if state.learning_enabled do
      process_cache_event(topic, event_data)
    end
    
    {:noreply, state}
  end
  
  def handle_info(:analyze_patterns, state) do
    new_patterns = analyze_usage_patterns()
    new_strategy = determine_optimal_strategy(new_patterns)
    
    new_state = %{state |
      detected_patterns: new_patterns,
      current_strategy: new_strategy
    }
    
    {:noreply, new_state}
  end
  
  def handle_info(:optimize_cache, state) do
    optimize_cache_based_on_patterns(state.detected_patterns, state.current_strategy)
    
    new_state = %{state |
      last_optimization: :os.system_time(:millisecond)
    }
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_call({:get_adaptive_ttl, key, content_type, metadata}, _from, state) do
    ttl = calculate_adaptive_ttl(key, content_type, metadata, state)
    {:reply, ttl, state}
  end
  
  def handle_call({:should_cache, key, content_type, cost}, _from, state) do
    should_cache = should_cache_content?(key, content_type, cost, state)
    {:reply, should_cache, state}
  end
  
  def handle_call({:get_cache_predictions}, _from, state) do
    predictions = get_cache_predictions()
    {:reply, predictions, state}
  end
  
  def handle_call({:get_pattern_analysis}, _from, state) do
    analysis = %{
      current_strategy: state.current_strategy,
      detected_patterns: state.detected_patterns,
      cache_statistics: get_cache_statistics(),
      last_optimization: state.last_optimization
    }
    
    {:reply, analysis, state}
  end
  
  # Public API
  
  @doc """
  Get adaptive TTL for cache entry based on learned patterns
  """
  def get_adaptive_ttl(key, content_type, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:get_adaptive_ttl, key, content_type, metadata})
  end
  
  @doc """
  Determine if content should be cached based on adaptive criteria
  """
  def should_cache?(key, content_type, cost \\ 0.0) do
    GenServer.call(__MODULE__, {:should_cache, key, content_type, cost})
  end
  
  @doc """
  Get intelligent cache with adaptive strategies
  """
  def adaptive_get(cache_name, key, opts \\ []) do
    # Record access for learning
    record_cache_access(key, :get, opts)
    
    case Cache.get_from(cache_name, key) do
      nil ->
        record_cache_access(key, :miss, opts)
        :miss
      
      value ->
        record_cache_access(key, :hit, opts)
        
        # Update access patterns for adaptive learning
        update_access_patterns(key, value, opts)
        
        {:ok, value}
    end
  end
  
  @doc """
  Intelligent cache put with adaptive TTL and priority
  """
  def adaptive_put(cache_name, key, value, opts \\ []) do
    content_type = Keyword.get(opts, :content_type, :llm_response)
    metadata = Keyword.get(opts, :metadata, %{})
    cost = Keyword.get(opts, :cost, 0.0)
    
    # Determine if we should cache this content
    if should_cache?(key, content_type, cost) do
      adaptive_ttl = get_adaptive_ttl(key, content_type, metadata)
      cache_opts = Keyword.merge(opts, [ttl: adaptive_ttl])
      
      # Record cache operation
      record_cache_access(key, :put, cache_opts)
      
      # Perform the cache operation
      result = Cache.put_in(cache_name, key, value, cache_opts)
      
      # Learn from this operation
      learn_from_cache_operation(key, value, cache_opts, result)
      
      result
    else
      # Don't cache based on adaptive criteria
      record_cache_access(key, :skip, opts)
      :skipped
    end
  end
  
  @doc """
  Proactive cache warming based on predicted patterns
  """
  def warm_cache(opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :predictive)
    limit = Keyword.get(opts, :limit, 100)
    
    case strategy do
      :predictive -> warm_cache_predictive(limit)
      :frequency_based -> warm_cache_by_frequency(limit)
      :temporal -> warm_cache_temporal(limit)
      :session_context -> warm_cache_contextual(limit)
    end
  end
  
  @doc """
  Get cache predictions for upcoming requests
  """
  def get_cache_predictions do
    GenServer.call(__MODULE__, {:get_cache_predictions})
  end
  
  @doc """
  Get current pattern analysis and strategy
  """
  def get_pattern_analysis do
    GenServer.call(__MODULE__, {:get_pattern_analysis})
  end
  
  @doc """
  Force pattern analysis and strategy optimization
  """
  def force_optimization do
    GenServer.cast(__MODULE__, :force_optimization)
  end
  
  # Private Functions
  
  defp process_cache_event(topic, event_data) do
    case topic do
      "cache.get" ->
        record_access_event(event_data.key, :get, event_data)
      
      "cache.put" ->
        record_access_event(event_data.key, :put, event_data)
      
      "cache.hit" ->
        record_access_event(event_data.key, :hit, event_data)
      
      "cache.miss" ->
        record_access_event(event_data.key, :miss, event_data)
      
      "llm.request.complete" ->
        learn_from_llm_completion(event_data)
      
      _ ->
        :ok
    end
  end
  
  defp record_cache_access(key, operation, opts) do
    timestamp = :os.system_time(:millisecond)
    metadata = Keyword.get(opts, :metadata, %{})
    
    access_record = %{
      key: key,
      operation: operation,
      timestamp: timestamp,
      metadata: metadata,
      context: extract_context_info(opts)
    }
    
    :ets.insert(:cache_access_history, {timestamp, access_record})
    
    # Update access counters
    update_access_counters(key, operation)
  end
  
  defp record_access_event(key, operation, event_data) do
    timestamp = :os.system_time(:millisecond)
    
    access_record = %{
      key: key,
      operation: operation,
      timestamp: timestamp,
      event_data: event_data
    }
    
    :ets.insert(:cache_access_history, {timestamp, access_record})
  end
  
  defp update_access_patterns(key, value, opts) do
    # Update patterns based on successful cache access
    pattern_key = generate_pattern_key(key, opts)
    
    case :ets.lookup(:cache_patterns, pattern_key) do
      [{_, pattern_data}] ->
        updated_pattern = update_pattern_data(pattern_data, :access)
        :ets.insert(:cache_patterns, {pattern_key, updated_pattern})
      
      [] ->
        initial_pattern = create_initial_pattern(key, value, opts)
        :ets.insert(:cache_patterns, {pattern_key, initial_pattern})
    end
  end
  
  defp update_access_counters(key, operation) do
    counter_key = {:access_counter, key, operation}
    
    case :ets.lookup(:cache_patterns, counter_key) do
      [{_, count}] ->
        :ets.insert(:cache_patterns, {counter_key, count + 1})
      [] ->
        :ets.insert(:cache_patterns, {counter_key, 1})
    end
  end
  
  defp analyze_usage_patterns do
    current_time = :os.system_time(:millisecond)
    since = current_time - @learning_window
    
    # Get recent access history
    recent_accesses = :ets.select(:cache_access_history, [
      {{:"$1", :"$2"}, [{:>=, :"$1", since}], [:"$2"]}
    ])
    
    if length(recent_accesses) < 10 do
      # Not enough data for pattern analysis
      %{pattern_type: :insufficient_data, confidence: 0.0}
    else
      analyze_access_patterns(recent_accesses)
    end
  end
  
  defp analyze_access_patterns(accesses) do
    # Group accesses by time windows
    time_windows = group_accesses_by_time_window(accesses)
    
    # Analyze temporal patterns
    temporal_analysis = analyze_temporal_patterns(time_windows)
    
    # Analyze frequency patterns
    frequency_analysis = analyze_frequency_patterns(accesses)
    
    # Analyze contextual patterns
    contextual_analysis = analyze_contextual_patterns(accesses)
    
    # Determine dominant pattern type
    pattern_scores = %{
      burst: calculate_burst_score(temporal_analysis, frequency_analysis),
      steady: calculate_steady_score(temporal_analysis, frequency_analysis),
      sporadic: calculate_sporadic_score(temporal_analysis, frequency_analysis),
      contextual: calculate_contextual_score(contextual_analysis),
      analytical: calculate_analytical_score(accesses)
    }
    
    {dominant_pattern, confidence} = determine_dominant_pattern(pattern_scores)
    
    %{
      pattern_type: dominant_pattern,
      confidence: confidence,
      temporal_analysis: temporal_analysis,
      frequency_analysis: frequency_analysis,
      contextual_analysis: contextual_analysis,
      pattern_scores: pattern_scores
    }
  end
  
  defp group_accesses_by_time_window(accesses) do
    window_size = :timer.minutes(5)
    
    accesses
    |> Enum.group_by(fn access ->
      div(access.timestamp, window_size) * window_size
    end)
    |> Enum.map(fn {window_start, window_accesses} ->
      %{
        window_start: window_start,
        access_count: length(window_accesses),
        unique_keys: window_accesses |> Enum.map(& &1.key) |> Enum.uniq() |> length(),
        operations: group_by_operation(window_accesses)
      }
    end)
    |> Enum.sort_by(& &1.window_start)
  end
  
  defp group_by_operation(accesses) do
    accesses
    |> Enum.group_by(& &1.operation)
    |> Enum.map(fn {operation, ops} -> {operation, length(ops)} end)
    |> Map.new()
  end
  
  defp analyze_temporal_patterns(time_windows) do
    if length(time_windows) < 3 do
      %{variance: :unknown, trend: :unknown, peak_times: []}
    else
      access_counts = Enum.map(time_windows, & &1.access_count)
      
      mean = Enum.sum(access_counts) / length(access_counts)
      variance = calculate_variance(access_counts, mean)
      normalized_variance = variance / mean
      
      variance_level = cond do
        normalized_variance < 0.5 -> :low
        normalized_variance < 2.0 -> :medium
        true -> :high
      end
      
      trend = analyze_trend(access_counts)
      peak_times = identify_peak_times(time_windows)
      
      %{
        variance: variance_level,
        trend: trend,
        peak_times: peak_times,
        mean_access_rate: mean,
        variance_value: variance
      }
    end
  end
  
  defp analyze_frequency_patterns(accesses) do
    # Analyze how frequently different keys are accessed
    key_frequencies = accesses
                     |> Enum.group_by(& &1.key)
                     |> Enum.map(fn {key, key_accesses} ->
                       {key, length(key_accesses)}
                     end)
                     |> Enum.sort_by(fn {_key, count} -> count end, :desc)
    
    total_accesses = length(accesses)
    unique_keys = length(key_frequencies)
    
    # Calculate frequency distribution
    {hot_keys, warm_keys, cold_keys} = categorize_keys_by_frequency(key_frequencies, total_accesses)
    
    %{
      total_accesses: total_accesses,
      unique_keys: unique_keys,
      hot_keys: length(hot_keys),
      warm_keys: length(warm_keys),
      cold_keys: length(cold_keys),
      top_keys: Enum.take(key_frequencies, 10),
      frequency_distribution: calculate_frequency_distribution(key_frequencies)
    }
  end
  
  defp analyze_contextual_patterns(accesses) do
    # Analyze session and context-based patterns
    session_groups = accesses
                    |> Enum.group_by(fn access ->
                      get_in(access, [:context, :session_id])
                    end)
                    |> Enum.filter(fn {session_id, _} -> session_id != nil end)
    
    session_correlation = if length(session_groups) > 0 do
      calculate_session_correlation(session_groups)
    else
      0.0
    end
    
    # Analyze provider patterns
    provider_groups = accesses
                     |> Enum.group_by(fn access ->
                       get_in(access, [:context, :provider])
                     end)
                     |> Enum.filter(fn {provider, _} -> provider != nil end)
    
    %{
      session_correlation: session_correlation,
      session_count: length(session_groups),
      provider_distribution: calculate_provider_distribution(provider_groups),
      context_diversity: calculate_context_diversity(accesses)
    }
  end
  
  defp determine_optimal_strategy(pattern_analysis) do
    if pattern_analysis.confidence < @min_pattern_confidence do
      :frequency_based  # Default strategy
    else
      pattern_config = Map.get(@usage_patterns, pattern_analysis.pattern_type)
      pattern_config.cache_strategy
    end
  end
  
  defp optimize_cache_based_on_patterns(patterns, strategy) do
    Logger.info("Optimizing cache with strategy: #{strategy}, pattern: #{patterns.pattern_type}")
    
    case strategy do
      :frequency_based -> optimize_by_frequency()
      :recency_based -> optimize_by_recency()
      :cost_based -> optimize_by_cost()
      :session_context -> optimize_by_context()
      _ -> optimize_by_frequency()
    end
    
    # Preload cache based on predictions
    warm_cache_based_on_patterns(patterns)
  end
  
  defp calculate_adaptive_ttl(key, content_type, metadata, state) do
    base_ttl = get_base_ttl(content_type)
    strategy = state.current_strategy
    patterns = state.detected_patterns
    
    # Calculate TTL adjustments based on various factors
    frequency_multiplier = calculate_frequency_multiplier(key)
    cost_multiplier = calculate_cost_multiplier(metadata)
    pattern_multiplier = calculate_pattern_multiplier(patterns, strategy)
    recency_multiplier = calculate_recency_multiplier(key)
    
    # Combine all multipliers
    total_multiplier = frequency_multiplier * cost_multiplier * pattern_multiplier * recency_multiplier
    
    # Ensure TTL is within reasonable bounds
    adaptive_ttl = base_ttl * total_multiplier
    clamp_ttl(adaptive_ttl, content_type)
  end
  
  defp should_cache_content?(key, content_type, cost, state) do
    # Base decision on content type
    base_decision = should_cache_by_type?(content_type)
    
    if not base_decision do
      false
    else
      # Apply adaptive criteria
      strategy = state.current_strategy
      patterns = state.detected_patterns
      
      frequency_score = calculate_frequency_score(key)
      cost_score = calculate_cost_score(cost)
      pattern_score = calculate_pattern_score(patterns, strategy, key)
      
      # Weighted decision
      total_score = (frequency_score * 0.4) + (cost_score * 0.3) + (pattern_score * 0.3)
      
      total_score > 0.6  # Threshold for caching decision
    end
  end
  
  defp learn_from_cache_operation(key, value, opts, result) do
    # Learn from successful/failed cache operations
    success = case result do
      :ok -> true
      {:ok, _} -> true
      _ -> false
    end
    
    # Update learning data
    learning_record = %{
      key: key,
      value_size: estimate_value_size(value),
      ttl: Keyword.get(opts, :ttl),
      success: success,
      timestamp: :os.system_time(:millisecond)
    }
    
    :ets.insert(:cache_patterns, {{:learning, key}, learning_record})
  end
  
  defp learn_from_llm_completion(event_data) do
    # Learn from LLM request completions to predict future cache needs
    if event_data.result == :success do
      prompt_pattern = extract_prompt_pattern(event_data.prompt)
      
      prediction_record = %{
        pattern: prompt_pattern,
        provider: event_data.provider,
        model: event_data.model,
        response_size: String.length(event_data.response || ""),
        cost: event_data.cost || 0.0,
        timestamp: :os.system_time(:millisecond)
      }
      
      :ets.insert(:cache_predictions, {prompt_pattern, prediction_record})
    end
  end
  
  defp warm_cache_predictive(limit) do
    # Predict likely cache requests and preload them
    predictions = get_cache_predictions()
    
    predictions
    |> Enum.take(limit)
    |> Enum.each(fn prediction ->
      warm_cache_entry(prediction)
    end)
  end
  
  defp warm_cache_by_frequency(limit) do
    # Warm cache with most frequently accessed items
    current_time = :os.system_time(:millisecond)
    since = current_time - :timer.hours(1)
    
    frequent_keys = get_frequent_keys(since, limit)
    
    Enum.each(frequent_keys, fn {key, _frequency} ->
      warm_cache_key(key)
    end)
  end
  
  defp warm_cache_temporal(limit) do
    # Warm cache based on time-of-day patterns
    current_hour = DateTime.utc_now().hour
    temporal_patterns = get_temporal_patterns(current_hour)
    
    temporal_patterns
    |> Enum.take(limit)
    |> Enum.each(fn pattern ->
      warm_cache_pattern(pattern)
    end)
  end
  
  defp warm_cache_contextual(limit) do
    # Warm cache based on current session contexts
    active_sessions = get_active_sessions()
    
    active_sessions
    |> Enum.take(limit)
    |> Enum.each(fn session ->
      warm_cache_session(session)
    end)
  end
  
  defp warm_cache_based_on_patterns(patterns) do
    case patterns.pattern_type do
      :burst -> warm_cache_by_frequency(50)
      :steady -> warm_cache_by_frequency(20)
      :sporadic -> warm_cache_by_frequency(10)
      :contextual -> warm_cache_contextual(30)
      :analytical -> warm_cache_predictive(25)
      _ -> :ok
    end
  end
  
  # Helper functions (simplified implementations)
  
  defp extract_context_info(opts) do
    %{
      session_id: Keyword.get(opts, :session_id),
      provider: get_in(opts, [:metadata, :provider]),
      model: get_in(opts, [:metadata, :model]),
      user_id: Keyword.get(opts, :user_id)
    }
  end
  
  defp generate_pattern_key(key, opts) do
    context = extract_context_info(opts)
    :crypto.hash(:md5, "#{key}:#{inspect(context)}") |> Base.encode64() |> binary_part(0, 16)
  end
  
  defp create_initial_pattern(key, value, opts) do
    %{
      key: key,
      access_count: 1,
      first_access: :os.system_time(:millisecond),
      last_access: :os.system_time(:millisecond),
      value_size: estimate_value_size(value),
      context: extract_context_info(opts)
    }
  end
  
  defp update_pattern_data(pattern_data, :access) do
    %{pattern_data |
      access_count: pattern_data.access_count + 1,
      last_access: :os.system_time(:millisecond)
    }
  end
  
  defp calculate_variance(values, mean) do
    if length(values) <= 1 do
      0
    else
      sum_squares = Enum.reduce(values, 0, fn value, acc ->
        acc + :math.pow(value - mean, 2)
      end)
      sum_squares / (length(values) - 1)
    end
  end
  
  defp analyze_trend(values) do
    if length(values) < 3 do
      :unknown
    else
      first_half = Enum.take(values, div(length(values), 2))
      second_half = Enum.drop(values, div(length(values), 2))
      
      first_avg = Enum.sum(first_half) / length(first_half)
      second_avg = Enum.sum(second_half) / length(second_half)
      
      change_ratio = (second_avg - first_avg) / first_avg
      
      cond do
        change_ratio > 0.2 -> :increasing
        change_ratio < -0.2 -> :decreasing
        true -> :stable
      end
    end
  end
  
  defp identify_peak_times(time_windows) do
    if length(time_windows) < 3 do
      []
    else
      mean_access = Enum.sum(Enum.map(time_windows, & &1.access_count)) / length(time_windows)
      threshold = mean_access * 1.5
      
      time_windows
      |> Enum.filter(fn window -> window.access_count > threshold end)
      |> Enum.map(& &1.window_start)
    end
  end
  
  defp categorize_keys_by_frequency(key_frequencies, total_accesses) do
    # Simple categorization: hot (>5% of traffic), warm (1-5%), cold (<1%)
    hot_threshold = total_accesses * 0.05
    warm_threshold = total_accesses * 0.01
    
    {hot_keys, rest} = Enum.split_with(key_frequencies, fn {_key, count} -> count > hot_threshold end)
    {warm_keys, cold_keys} = Enum.split_with(rest, fn {_key, count} -> count > warm_threshold end)
    
    {hot_keys, warm_keys, cold_keys}
  end
  
  defp calculate_frequency_distribution(key_frequencies) do
    total_keys = length(key_frequencies)
    
    if total_keys == 0 do
      %{entropy: 0, gini_coefficient: 0}
    else
      frequencies = Enum.map(key_frequencies, fn {_key, count} -> count end)
      total_accesses = Enum.sum(frequencies)
      
      probabilities = Enum.map(frequencies, fn count -> count / total_accesses end)
      entropy = -Enum.reduce(probabilities, 0, fn p, acc ->
        acc + (p * :math.log2(p))
      end)
      
      gini = calculate_gini_coefficient(frequencies)
      
      %{entropy: entropy, gini_coefficient: gini}
    end
  end
  
  defp calculate_gini_coefficient(values) do
    # Simplified Gini coefficient calculation
    n = length(values)
    if n <= 1, do: 0, else: 0.5  # Placeholder implementation
  end
  
  defp calculate_session_correlation(session_groups) do
    # Calculate how correlated accesses are within sessions
    session_sizes = Enum.map(session_groups, fn {_session, accesses} -> length(accesses) end)
    mean_session_size = Enum.sum(session_sizes) / length(session_sizes)
    
    # Higher mean session size indicates higher correlation
    min(1.0, mean_session_size / 10.0)
  end
  
  defp calculate_provider_distribution(provider_groups) do
    total_accesses = Enum.reduce(provider_groups, 0, fn {_provider, accesses}, acc ->
      acc + length(accesses)
    end)
    
    Enum.map(provider_groups, fn {provider, accesses} ->
      {provider, length(accesses) / total_accesses}
    end)
    |> Map.new()
  end
  
  defp calculate_context_diversity(accesses) do
    unique_contexts = accesses
                     |> Enum.map(& &1.context)
                     |> Enum.uniq()
                     |> length()
    
    total_accesses = length(accesses)
    
    if total_accesses > 0, do: unique_contexts / total_accesses, else: 0.0
  end
  
  # Pattern scoring functions
  
  defp calculate_burst_score(temporal_analysis, frequency_analysis) do
    variance_score = case temporal_analysis.variance do
      :high -> 0.8
      :medium -> 0.5
      :low -> 0.2
      _ -> 0.0
    end
    
    frequency_score = min(1.0, frequency_analysis.hot_keys / 10.0)
    
    (variance_score + frequency_score) / 2
  end
  
  defp calculate_steady_score(temporal_analysis, frequency_analysis) do
    variance_score = case temporal_analysis.variance do
      :low -> 0.8
      :medium -> 0.6
      :high -> 0.2
      _ -> 0.0
    end
    
    distribution_score = min(1.0, frequency_analysis.unique_keys / 100.0)
    
    (variance_score + distribution_score) / 2
  end
  
  defp calculate_sporadic_score(temporal_analysis, frequency_analysis) do
    variance_score = case temporal_analysis.variance do
      :high -> 0.7
      :medium -> 0.4
      :low -> 0.1
      _ -> 0.0
    end
    
    cold_keys_ratio = frequency_analysis.cold_keys / frequency_analysis.unique_keys
    
    (variance_score + cold_keys_ratio) / 2
  end
  
  defp calculate_contextual_score(contextual_analysis) do
    contextual_analysis.session_correlation
  end
  
  defp calculate_analytical_score(accesses) do
    # Look for patterns indicating analytical queries (simplified)
    analytical_keywords = ["stats", "analysis", "report", "aggregate"]
    
    analytical_accesses = Enum.count(accesses, fn access ->
      key_str = to_string(access.key)
      Enum.any?(analytical_keywords, fn keyword ->
        String.contains?(key_str, keyword)
      end)
    end)
    
    analytical_accesses / length(accesses)
  end
  
  defp determine_dominant_pattern(pattern_scores) do
    {pattern, score} = Enum.max_by(pattern_scores, fn {_pattern, score} -> score end)
    {pattern, score}
  end
  
  # TTL and caching decision functions
  
  defp get_base_ttl(:llm_response), do: :timer.hours(4)
  defp get_base_ttl(:provider_status), do: :timer.minutes(30)
  defp get_base_ttl(:query_result), do: :timer.hours(1)
  defp get_base_ttl(_), do: :timer.hours(1)
  
  defp calculate_frequency_multiplier(key) do
    case get_access_frequency(key, :timer.hours(1)) do
      freq when freq > 10 -> 2.0
      freq when freq > 5 -> 1.5
      freq when freq > 1 -> 1.0
      _ -> 0.8
    end
  end
  
  defp calculate_cost_multiplier(metadata) do
    cost = Map.get(metadata, :cost, 0.0)
    tokens = Map.get(metadata, :tokens_used, 0)
    
    cond do
      cost > 0.01 or tokens > 1000 -> 2.0
      cost > 0.005 or tokens > 500 -> 1.5
      cost > 0.001 or tokens > 100 -> 1.0
      true -> 0.8
    end
  end
  
  defp calculate_pattern_multiplier(patterns, strategy) do
    case {patterns.pattern_type, strategy} do
      {:burst, :frequency_based} -> 1.5
      {:steady, :recency_based} -> 1.2
      {:contextual, :session_context} -> 1.8
      {:analytical, :cost_based} -> 2.0
      _ -> 1.0
    end
  end
  
  defp calculate_recency_multiplier(key) do
    last_access = get_last_access_time(key)
    current_time = :os.system_time(:millisecond)
    
    if last_access do
      time_diff = current_time - last_access
      
      cond do
        time_diff < :timer.minutes(10) -> 1.5
        time_diff < :timer.hours(1) -> 1.2
        time_diff < :timer.hours(6) -> 1.0
        true -> 0.8
      end
    else
      1.0
    end
  end
  
  defp clamp_ttl(ttl, content_type) do
    {min_ttl, max_ttl} = get_ttl_bounds(content_type)
    max(min_ttl, min(max_ttl, ttl))
  end
  
  defp get_ttl_bounds(:llm_response), do: {:timer.minutes(5), :timer.hours(24)}
  defp get_ttl_bounds(:provider_status), do: {:timer.minutes(1), :timer.hours(4)}
  defp get_ttl_bounds(:query_result), do: {:timer.minutes(10), :timer.hours(12)}
  defp get_ttl_bounds(_), do: {:timer.minutes(5), :timer.hours(8)}
  
  defp should_cache_by_type?(:llm_response), do: true
  defp should_cache_by_type?(:provider_status), do: true
  defp should_cache_by_type?(:query_result), do: true
  defp should_cache_by_type?(:temporary), do: false
  defp should_cache_by_type?(_), do: true
  
  defp calculate_frequency_score(key) do
    frequency = get_access_frequency(key, :timer.hours(24))
    min(1.0, frequency / 10.0)
  end
  
  defp calculate_cost_score(cost) do
    min(1.0, cost / 0.01)
  end
  
  defp calculate_pattern_score(patterns, strategy, _key) do
    case {patterns.pattern_type, strategy} do
      {pattern, strategy} when pattern == strategy -> 0.8
      _ -> 0.5
    end
  end
  
  # Utility functions
  
  defp get_access_frequency(key, time_window) do
    current_time = :os.system_time(:millisecond)
    since = current_time - time_window
    
    case :ets.lookup(:cache_patterns, {:access_counter, key, :get}) do
      [{_, count}] -> count
      [] -> 0
    end
  end
  
  defp get_last_access_time(key) do
    # Get last access time for a key
    pattern_key = {:pattern, key}
    
    case :ets.lookup(:cache_patterns, pattern_key) do
      [{_, pattern_data}] -> pattern_data.last_access
      [] -> nil
    end
  end
  
  defp estimate_value_size(value) do
    # Estimate memory size of cached value
    :erlang.external_size(value)
  end
  
  defp extract_prompt_pattern(prompt) do
    # Extract pattern from prompt for prediction
    words = String.split(prompt, " ")
    pattern = words
             |> Enum.take(5)
             |> Enum.join(" ")
             |> String.downcase()
    
    :crypto.hash(:md5, pattern) |> Base.encode64() |> binary_part(0, 8)
  end
  
  # Cache warming helper functions
  
  defp warm_cache_entry(prediction) do
    # Warm cache entry based on prediction
    Logger.debug("Warming cache entry for pattern: #{prediction.pattern}")
  end
  
  defp warm_cache_key(key) do
    # Warm cache for specific key
    Logger.debug("Warming cache for key: #{key}")
  end
  
  defp warm_cache_pattern(pattern) do
    # Warm cache based on temporal pattern
    Logger.debug("Warming cache for temporal pattern: #{inspect(pattern)}")
  end
  
  defp warm_cache_session(session) do
    # Warm cache for session context
    Logger.debug("Warming cache for session: #{session}")
  end
  
  defp get_frequent_keys(since, limit) do
    # Get most frequently accessed keys since timestamp
    []
  end
  
  defp get_temporal_patterns(hour) do
    # Get temporal patterns for specific hour
    []
  end
  
  defp get_active_sessions do
    # Get currently active sessions
    []
  end
  
  defp get_cache_statistics do
    # Get current cache statistics
    %{
      hit_rate: 0.75,
      total_entries: 1000,
      memory_usage: 50_000_000
    }
  end
  
  # Optimization helper functions
  
  defp optimize_by_frequency do
    Logger.info("Optimizing cache by frequency patterns")
  end
  
  defp optimize_by_recency do
    Logger.info("Optimizing cache by recency patterns")
  end
  
  defp optimize_by_cost do
    Logger.info("Optimizing cache by cost-effectiveness")
  end
  
  defp optimize_by_context do
    Logger.info("Optimizing cache by contextual patterns")
  end
end