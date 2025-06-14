defmodule RubberDuck.ILP.Context.LRUEviction do
  @moduledoc """
  LRU eviction with semantic relevance scoring for context management.
  Implements intelligent eviction strategies that consider both recency and semantic importance.
  """
  use GenServer
  require Logger

  defstruct [
    :access_order,
    :semantic_scores,
    :eviction_strategy,
    :max_cache_size,
    :eviction_threshold,
    :scoring_weights,
    :metrics
  ]

  @eviction_strategies [:lru, :semantic_weighted, :hybrid, :predictive]
  @default_max_cache_size 1000
  @default_eviction_threshold 0.85

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records access to a context for LRU tracking.
  """
  def record_access(context_id, access_metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:record_access, context_id, access_metadata})
  end

  @doc """
  Updates semantic relevance score for a context.
  """
  def update_semantic_score(context_id, score, score_metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:update_semantic_score, context_id, score, score_metadata})
  end

  @doc """
  Determines which contexts should be evicted to reach target cache size.
  """
  def determine_evictions(current_size, target_size) do
    GenServer.call(__MODULE__, {:determine_evictions, current_size, target_size})
  end

  @doc """
  Gets the eviction priority for a specific context.
  """
  def get_eviction_priority(context_id) do
    GenServer.call(__MODULE__, {:get_eviction_priority, context_id})
  end

  @doc """
  Performs bulk eviction based on current strategy.
  """
  def perform_eviction(contexts_to_evict) do
    GenServer.call(__MODULE__, {:perform_eviction, contexts_to_evict})
  end

  @doc """
  Gets LRU and eviction metrics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Updates eviction strategy and parameters.
  """
  def update_strategy(strategy, opts \\ []) do
    GenServer.call(__MODULE__, {:update_strategy, strategy, opts})
  end

  @doc """
  Analyzes access patterns to predict future usage.
  """
  def analyze_access_patterns do
    GenServer.call(__MODULE__, :analyze_access_patterns)
  end

  @impl true
  def init(opts) do
    Logger.info("Starting LRU Eviction Manager with semantic scoring")
    
    state = %__MODULE__{
      access_order: %{},
      semantic_scores: %{},
      eviction_strategy: Keyword.get(opts, :strategy, :hybrid),
      max_cache_size: Keyword.get(opts, :max_cache_size, @default_max_cache_size),
      eviction_threshold: Keyword.get(opts, :eviction_threshold, @default_eviction_threshold),
      scoring_weights: initialize_scoring_weights(opts),
      metrics: initialize_metrics()
    }
    
    {:ok, state}
  end

  @impl true
  def handle_cast({:record_access, context_id, access_metadata}, state) do
    timestamp = System.monotonic_time(:millisecond)
    
    access_info = %{
      last_accessed: timestamp,
      access_count: get_access_count(state.access_order, context_id) + 1,
      access_pattern: determine_access_pattern(state.access_order, context_id),
      metadata: access_metadata
    }
    
    new_access_order = Map.put(state.access_order, context_id, access_info)
    new_metrics = update_access_metrics(state.metrics, access_metadata)
    
    new_state = %{state | 
      access_order: new_access_order,
      metrics: new_metrics
    }
    
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:update_semantic_score, context_id, score, score_metadata}, state) do
    semantic_info = %{
      relevance_score: score,
      calculated_at: System.monotonic_time(:millisecond),
      score_type: score_metadata[:type] || :general,
      factors: score_metadata[:factors] || [],
      confidence: score_metadata[:confidence] || 0.5
    }
    
    new_semantic_scores = Map.put(state.semantic_scores, context_id, semantic_info)
    new_state = %{state | semantic_scores: new_semantic_scores}
    
    {:noreply, new_state}
  end

  @impl true
  def handle_call({:determine_evictions, current_size, target_size}, _from, state) do
    if current_size <= target_size do
      {:reply, {:ok, []}, state}
    else
      eviction_count = current_size - target_size
      
      case determine_eviction_candidates(state, eviction_count) do
        {:ok, candidates} ->
          new_metrics = update_eviction_metrics(state.metrics, length(candidates))
          new_state = %{state | metrics: new_metrics}
          {:reply, {:ok, candidates}, new_state}
        
        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call({:get_eviction_priority, context_id}, _from, state) do
    priority = calculate_eviction_priority(context_id, state)
    {:reply, {:ok, priority}, state}
  end

  @impl true
  def handle_call({:perform_eviction, contexts_to_evict}, _from, state) do
    # Remove evicted contexts from tracking
    new_access_order = Map.drop(state.access_order, contexts_to_evict)
    new_semantic_scores = Map.drop(state.semantic_scores, contexts_to_evict)
    
    eviction_stats = %{
      evicted_count: length(contexts_to_evict),
      evicted_at: System.monotonic_time(:millisecond),
      strategy_used: state.eviction_strategy
    }
    
    new_metrics = Map.put(state.metrics, :last_eviction, eviction_stats)
    
    new_state = %{state |
      access_order: new_access_order,
      semantic_scores: new_semantic_scores,
      metrics: new_metrics
    }
    
    {:reply, {:ok, eviction_stats}, new_state}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    enhanced_metrics = enhance_metrics_with_calculations(state.metrics, state)
    {:reply, enhanced_metrics, state}
  end

  @impl true
  def handle_call({:update_strategy, strategy, opts}, _from, state) do
    if strategy in @eviction_strategies do
      new_scoring_weights = update_scoring_weights(state.scoring_weights, opts)
      
      new_state = %{state |
        eviction_strategy: strategy,
        scoring_weights: new_scoring_weights,
        max_cache_size: Keyword.get(opts, :max_cache_size, state.max_cache_size),
        eviction_threshold: Keyword.get(opts, :eviction_threshold, state.eviction_threshold)
      }
      
      {:reply, {:ok, :strategy_updated}, new_state}
    else
      {:reply, {:error, :invalid_strategy}, state}
    end
  end

  @impl true
  def handle_call(:analyze_access_patterns, _from, state) do
    analysis = perform_access_pattern_analysis(state)
    {:reply, {:ok, analysis}, state}
  end

  # Private functions

  defp determine_eviction_candidates(state, eviction_count) do
    all_contexts = get_all_tracked_contexts(state)
    
    case state.eviction_strategy do
      :lru ->
        candidates = select_lru_candidates(state, all_contexts, eviction_count)
        {:ok, candidates}
      
      :semantic_weighted ->
        candidates = select_semantic_weighted_candidates(state, all_contexts, eviction_count)
        {:ok, candidates}
      
      :hybrid ->
        candidates = select_hybrid_candidates(state, all_contexts, eviction_count)
        {:ok, candidates}
      
      :predictive ->
        candidates = select_predictive_candidates(state, all_contexts, eviction_count)
        {:ok, candidates}
      
      _ ->
        {:error, :unsupported_strategy}
    end
  end

  defp select_lru_candidates(state, contexts, eviction_count) do
    contexts
    |> Enum.map(fn context_id ->
      access_info = Map.get(state.access_order, context_id, %{last_accessed: 0})
      {context_id, access_info.last_accessed}
    end)
    |> Enum.sort_by(fn {_id, last_accessed} -> last_accessed end)
    |> Enum.take(eviction_count)
    |> Enum.map(fn {context_id, _timestamp} -> context_id end)
  end

  defp select_semantic_weighted_candidates(state, contexts, eviction_count) do
    contexts
    |> Enum.map(fn context_id ->
      semantic_score = get_semantic_score(state.semantic_scores, context_id)
      {context_id, semantic_score}
    end)
    |> Enum.sort_by(fn {_id, score} -> score end)
    |> Enum.take(eviction_count)
    |> Enum.map(fn {context_id, _score} -> context_id end)
  end

  defp select_hybrid_candidates(state, contexts, eviction_count) do
    current_time = System.monotonic_time(:millisecond)
    
    contexts
    |> Enum.map(fn context_id ->
      priority = calculate_hybrid_priority(context_id, state, current_time)
      {context_id, priority}
    end)
    |> Enum.sort_by(fn {_id, priority} -> priority end)
    |> Enum.take(eviction_count)
    |> Enum.map(fn {context_id, _priority} -> context_id end)
  end

  defp select_predictive_candidates(state, contexts, eviction_count) do
    # Use access pattern analysis to predict future usage
    access_patterns = perform_access_pattern_analysis(state)
    
    contexts
    |> Enum.map(fn context_id ->
      prediction_score = calculate_prediction_score(context_id, access_patterns, state)
      {context_id, prediction_score}
    end)
    |> Enum.sort_by(fn {_id, score} -> score end)
    |> Enum.take(eviction_count)
    |> Enum.map(fn {context_id, _score} -> context_id end)
  end

  defp calculate_eviction_priority(context_id, state) do
    case state.eviction_strategy do
      :lru ->
        calculate_lru_priority(context_id, state)
      
      :semantic_weighted ->
        calculate_semantic_priority(context_id, state)
      
      :hybrid ->
        calculate_hybrid_priority(context_id, state, System.monotonic_time(:millisecond))
      
      :predictive ->
        access_patterns = perform_access_pattern_analysis(state)
        calculate_prediction_score(context_id, access_patterns, state)
    end
  end

  defp calculate_lru_priority(context_id, state) do
    access_info = Map.get(state.access_order, context_id)
    
    case access_info do
      nil -> 0.0  # Never accessed - highest priority for eviction
      %{last_accessed: last_accessed} ->
        current_time = System.monotonic_time(:millisecond)
        time_since_access = current_time - last_accessed
        
        # Higher time since access = higher eviction priority
        min(1.0, time_since_access / (24 * 60 * 60 * 1000))  # Normalize to 24 hours
    end
  end

  defp calculate_semantic_priority(context_id, state) do
    semantic_info = Map.get(state.semantic_scores, context_id)
    
    case semantic_info do
      nil -> 1.0  # No semantic score - highest priority for eviction
      %{relevance_score: score} ->
        # Lower relevance = higher eviction priority
        1.0 - min(1.0, max(0.0, score))
    end
  end

  defp calculate_hybrid_priority(context_id, state, current_time) do
    weights = state.scoring_weights
    
    # LRU component
    lru_priority = calculate_lru_priority(context_id, state)
    
    # Semantic component
    semantic_priority = calculate_semantic_priority(context_id, state)
    
    # Access frequency component
    access_info = Map.get(state.access_order, context_id, %{access_count: 0})
    max_access_count = get_max_access_count(state.access_order)
    frequency_priority = if max_access_count > 0 do
      1.0 - (access_info.access_count / max_access_count)
    else
      0.5
    end
    
    # Size component (if available in metadata)
    size_priority = get_size_priority(context_id, state)
    
    # Weighted combination
    weights.lru * lru_priority +
    weights.semantic * semantic_priority +
    weights.frequency * frequency_priority +
    weights.size * size_priority
  end

  defp calculate_prediction_score(context_id, access_patterns, state) do
    # Predict future access likelihood based on patterns
    pattern_info = Map.get(access_patterns.individual_patterns, context_id, %{})
    
    # Base score from access frequency
    base_score = calculate_semantic_priority(context_id, state)
    
    # Adjust based on access pattern
    pattern_adjustment = case pattern_info[:pattern_type] do
      :regular -> -0.2  # Regular access - less likely to evict
      :declining -> 0.3  # Declining access - more likely to evict
      :sporadic -> 0.1   # Sporadic access - slightly more likely to evict
      :recent_spike -> -0.1  # Recent spike - less likely to evict
      _ -> 0.0
    end
    
    # Time-based adjustment
    time_adjustment = case pattern_info[:trend] do
      :increasing -> -0.1
      :decreasing -> 0.2
      :stable -> 0.0
      _ -> 0.0
    end
    
    min(1.0, max(0.0, base_score + pattern_adjustment + time_adjustment))
  end

  defp get_all_tracked_contexts(state) do
    access_contexts = Map.keys(state.access_order)
    semantic_contexts = Map.keys(state.semantic_scores)
    
    (access_contexts ++ semantic_contexts)
    |> Enum.uniq()
  end

  defp get_access_count(access_order, context_id) do
    case Map.get(access_order, context_id) do
      nil -> 0
      %{access_count: count} -> count
      _ -> 0
    end
  end

  defp get_max_access_count(access_order) do
    access_order
    |> Map.values()
    |> Enum.map(fn info -> Map.get(info, :access_count, 0) end)
    |> Enum.max(fn -> 1 end)
  end

  defp get_semantic_score(semantic_scores, context_id) do
    case Map.get(semantic_scores, context_id) do
      nil -> 0.5  # Default middle score
      %{relevance_score: score} -> score
      _ -> 0.5
    end
  end

  defp get_size_priority(context_id, state) do
    # Try to get size from access metadata
    access_info = Map.get(state.access_order, context_id, %{})
    size = get_in(access_info, [:metadata, :size]) || 0
    
    # Larger contexts have higher eviction priority (assuming size matters)
    if size > 0 do
      min(1.0, size / 10000)  # Normalize to 10KB
    else
      0.0
    end
  end

  defp determine_access_pattern(access_order, context_id) do
    case Map.get(access_order, context_id) do
      nil -> :new
      %{access_count: count} when count < 3 -> :infrequent
      %{access_count: count} when count < 10 -> :moderate
      _ -> :frequent
    end
  end

  defp perform_access_pattern_analysis(state) do
    current_time = System.monotonic_time(:millisecond)
    
    # Analyze individual context patterns
    individual_patterns = state.access_order
    |> Enum.map(fn {context_id, access_info} ->
      pattern = analyze_individual_pattern(access_info, current_time)
      {context_id, pattern}
    end)
    |> Enum.into(%{})
    
    # Calculate global patterns
    global_stats = calculate_global_access_stats(state.access_order, current_time)
    
    %{
      individual_patterns: individual_patterns,
      global_stats: global_stats,
      analysis_timestamp: current_time
    }
  end

  defp analyze_individual_pattern(access_info, current_time) do
    time_since_last = current_time - access_info.last_accessed
    
    pattern_type = cond do
      access_info.access_count > 10 && time_since_last < 3600000 -> :regular  # < 1 hour
      access_info.access_count > 5 && time_since_last > 86400000 -> :declining  # > 1 day
      access_info.access_count < 3 -> :sporadic
      time_since_last < 300000 -> :recent_spike  # < 5 minutes
      true -> :normal
    end
    
    %{
      pattern_type: pattern_type,
      access_frequency: access_info.access_count,
      recency: time_since_last,
      trend: determine_trend(access_info)
    }
  end

  defp determine_trend(access_info) do
    # Simplified trend analysis
    case access_info do
      %{access_count: count} when count > 10 -> :stable
      %{access_count: count} when count > 5 -> :increasing
      _ -> :decreasing
    end
  end

  defp calculate_global_access_stats(access_order, current_time) do
    if map_size(access_order) == 0 do
      %{avg_access_count: 0, avg_recency: 0, total_contexts: 0}
    else
      total_accesses = access_order
      |> Map.values()
      |> Enum.sum(fn info -> Map.get(info, :access_count, 0) end)
      
      total_recency = access_order
      |> Map.values()
      |> Enum.sum(fn info -> current_time - Map.get(info, :last_accessed, current_time) end)
      
      context_count = map_size(access_order)
      
      %{
        avg_access_count: total_accesses / context_count,
        avg_recency: total_recency / context_count,
        total_contexts: context_count
      }
    end
  end

  defp initialize_scoring_weights(opts) do
    %{
      lru: Keyword.get(opts, :lru_weight, 0.4),
      semantic: Keyword.get(opts, :semantic_weight, 0.3),
      frequency: Keyword.get(opts, :frequency_weight, 0.2),
      size: Keyword.get(opts, :size_weight, 0.1)
    }
  end

  defp update_scoring_weights(current_weights, opts) do
    %{
      lru: Keyword.get(opts, :lru_weight, current_weights.lru),
      semantic: Keyword.get(opts, :semantic_weight, current_weights.semantic),
      frequency: Keyword.get(opts, :frequency_weight, current_weights.frequency),
      size: Keyword.get(opts, :size_weight, current_weights.size)
    }
  end

  defp initialize_metrics do
    %{
      total_accesses_recorded: 0,
      total_evictions_performed: 0,
      avg_eviction_priority: 0,
      strategy_effectiveness: %{},
      created_at: System.monotonic_time(:millisecond)
    }
  end

  defp update_access_metrics(metrics, _access_metadata) do
    %{metrics | total_accesses_recorded: metrics.total_accesses_recorded + 1}
  end

  defp update_eviction_metrics(metrics, eviction_count) do
    %{metrics | total_evictions_performed: metrics.total_evictions_performed + eviction_count}
  end

  defp enhance_metrics_with_calculations(metrics, state) do
    current_cache_size = map_size(state.access_order)
    utilization = current_cache_size / state.max_cache_size
    
    Map.merge(metrics, %{
      current_cache_size: current_cache_size,
      max_cache_size: state.max_cache_size,
      cache_utilization: utilization,
      eviction_strategy: state.eviction_strategy,
      contexts_with_semantic_scores: map_size(state.semantic_scores)
    })
  end
end