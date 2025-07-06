defmodule RubberDuck.Context.AdaptiveSelector do
  @moduledoc """
  Intelligently selects the best context building strategy based on query analysis.
  
  Learns from feedback to improve strategy selection over time.
  """

  use GenServer
  require Logger

  alias RubberDuck.Context.Strategies.{FIM, RAG, LongContext}
  alias RubberDuck.Context.Scorer

  @strategies [FIM, RAG, LongContext]
  @learning_rate 0.1

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Selects the best strategy for the given query and options.
  """
  def select_strategy(query, opts \\ []) do
    GenServer.call(__MODULE__, {:select_strategy, query, opts})
  end

  @doc """
  Records feedback about strategy performance to improve future selections.
  """
  def record_feedback(query, strategy, score) do
    GenServer.cast(__MODULE__, {:record_feedback, query, strategy, score})
  end

  @doc """
  Gets performance statistics for strategies.
  """
  def get_stats() do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Initialize performance tracking
    :ets.new(:strategy_performance, [:set, :public, :named_table])
    
    state = %{
      # Track strategy performance by query type
      performance_history: %{},
      # Feature weights for query classification
      feature_weights: initialize_feature_weights()
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call({:select_strategy, query, opts}, _from, state) do
    # Extract query features
    features = extract_query_features(query, opts)
    
    # Get strategy scores
    strategy_scores = evaluate_strategies(features, opts, state)
    
    # Select best strategy
    {best_strategy, confidence} = select_best_strategy(strategy_scores)
    
    # Log selection
    Logger.debug("Selected strategy #{best_strategy} with confidence #{confidence}")
    
    {:reply, {:ok, best_strategy, confidence}, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = compile_statistics(state)
    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:record_feedback, query, strategy, score}, state) do
    # Extract features from the query
    features = extract_query_features(query, [])
    
    # Update performance history
    updated_state = update_performance(state, features, strategy, score)
    
    # Adjust feature weights based on feedback
    updated_state = adjust_weights(updated_state, features, strategy, score)
    
    {:noreply, updated_state}
  end

  # Private functions

  defp initialize_feature_weights() do
    %{
      query_length: 0.1,
      has_code_context: 0.3,
      has_cursor_position: 0.4,
      is_completion: 0.5,
      is_generation: 0.3,
      is_analysis: 0.2,
      has_multiple_files: 0.3,
      context_size: 0.2,
      has_project_context: 0.25
    }
  end

  defp extract_query_features(query, opts) do
    %{
      query_length: categorize_length(String.length(query)),
      has_code_context: Keyword.has_key?(opts, :file_content),
      has_cursor_position: Keyword.has_key?(opts, :cursor_position),
      is_completion: is_completion_query?(query),
      is_generation: is_generation_query?(query),
      is_analysis: is_analysis_query?(query),
      has_multiple_files: length(Keyword.get(opts, :files, [])) > 1,
      context_size: categorize_context_size(opts),
      has_project_context: Keyword.has_key?(opts, :project_id)
    }
  end

  defp categorize_length(length) do
    cond do
      length < 20 -> :short
      length < 100 -> :medium
      true -> :long
    end
  end

  defp categorize_context_size(opts) do
    max_tokens = Keyword.get(opts, :max_tokens, 4000)
    cond do
      max_tokens < 8000 -> :small
      max_tokens < 32000 -> :medium
      true -> :large
    end
  end

  defp is_completion_query?(query) do
    completion_keywords = ~w(complete finish continue fill implement next)
    query_lower = String.downcase(query)
    Enum.any?(completion_keywords, &String.contains?(query_lower, &1))
  end

  defp is_generation_query?(query) do
    generation_keywords = ~w(create generate build make write develop design implement)
    query_lower = String.downcase(query)
    Enum.any?(generation_keywords, &String.contains?(query_lower, &1))
  end

  defp is_analysis_query?(query) do
    analysis_keywords = ~w(analyze explain why how what understand review debug investigate)
    query_lower = String.downcase(query)
    Enum.any?(analysis_keywords, &String.contains?(query_lower, &1))
  end

  defp evaluate_strategies(features, opts, state) do
    @strategies
    |> Enum.map(fn strategy_module ->
      # Get base quality estimate from strategy
      base_score = strategy_module.estimate_quality("", opts)
      
      # Adjust based on features and learned weights
      feature_score = calculate_feature_score(
        features, 
        strategy_module.name(), 
        state.feature_weights
      )
      
      # Get historical performance
      historical_score = get_historical_performance(
        features,
        strategy_module.name(),
        state.performance_history
      )
      
      # Combine scores
      total_score = combine_scores(base_score, feature_score, historical_score)
      
      {strategy_module, total_score}
    end)
  end

  defp calculate_feature_score(features, strategy, weights) do
    # Calculate weighted score based on features
    feature_scores = 
      case strategy do
        :fim ->
          %{
            has_cursor_position: 1.0,
            has_code_context: 0.9,
            is_completion: 1.0,
            is_generation: 0.3,
            is_analysis: 0.2
          }
        
        :rag ->
          %{
            has_project_context: 1.0,
            is_generation: 0.9,
            is_analysis: 0.8,
            has_multiple_files: 0.7,
            query_length: if(features.query_length == :long, do: 0.8, else: 0.5)
          }
        
        :long_context ->
          %{
            context_size: if(features.context_size == :large, do: 1.0, else: 0.3),
            has_multiple_files: 1.0,
            is_analysis: 0.9,
            is_generation: 0.7
          }
      end
    
    # Calculate weighted sum
    Enum.reduce(features, 0.0, fn {feature, value}, acc ->
      feature_weight = Map.get(weights, feature, 0.0)
      strategy_score = Map.get(feature_scores, feature, 0.5)
      
      # Binary features
      if is_boolean(value) do
        if value, do: acc + feature_weight * strategy_score, else: acc
      else
        # Categorical features
        acc + feature_weight * strategy_score
      end
    end)
  end

  defp get_historical_performance(features, strategy, history) do
    # Look up similar queries in history
    key = generate_history_key(features)
    
    case Map.get(history, {key, strategy}) do
      nil -> 0.5  # No history, neutral score
      performance -> performance.average_score
    end
  end

  defp generate_history_key(features) do
    # Create a simplified key for similar queries
    {
      features.is_completion,
      features.is_generation,
      features.is_analysis,
      features.has_code_context,
      features.context_size
    }
  end

  defp combine_scores(base, feature, historical) do
    # Weighted combination with emphasis on historical performance
    base * 0.3 + feature * 0.3 + historical * 0.4
  end

  defp select_best_strategy(strategy_scores) do
    {best_strategy, best_score} = 
      Enum.max_by(strategy_scores, fn {_, score} -> score end)
    
    # Calculate confidence based on score difference
    scores = Enum.map(strategy_scores, &elem(&1, 1))
    second_best = scores -- [best_score] |> Enum.max(fn -> 0.0 end)
    
    confidence = 
      cond do
        best_score - second_best > 0.3 -> :high
        best_score - second_best > 0.1 -> :medium
        true -> :low
      end
    
    {best_strategy.name(), confidence}
  end

  defp update_performance(state, features, strategy, score) do
    key = {generate_history_key(features), strategy}
    
    current = Map.get(state.performance_history, key, %{
      total_score: 0.0,
      count: 0,
      average_score: 0.5
    })
    
    updated = %{
      total_score: current.total_score + score,
      count: current.count + 1,
      average_score: (current.total_score + score) / (current.count + 1)
    }
    
    %{state | 
      performance_history: Map.put(state.performance_history, key, updated)
    }
  end

  defp adjust_weights(state, features, strategy, score) do
    # Simple gradient update based on performance
    performance_delta = score - 0.7  # Target performance
    
    updated_weights = 
      Enum.reduce(features, state.feature_weights, fn {feature, value}, weights ->
        if is_boolean(value) and value do
          current_weight = Map.get(weights, feature, 0.0)
          # Increase weight if performance is good, decrease if bad
          new_weight = current_weight + @learning_rate * performance_delta
          # Clamp between 0 and 1
          Map.put(weights, feature, max(0.0, min(1.0, new_weight)))
        else
          weights
        end
      end)
    
    %{state | feature_weights: updated_weights}
  end

  defp compile_statistics(state) do
    strategy_stats = 
      Enum.reduce(state.performance_history, %{}, fn {{_features, strategy}, perf}, acc ->
        Map.update(acc, strategy, perf, fn existing ->
          %{
            total_score: existing.total_score + perf.total_score,
            count: existing.count + perf.count,
            average_score: (existing.total_score + perf.total_score) / 
                          (existing.count + perf.count)
          }
        end)
      end)
    
    %{
      strategy_performance: strategy_stats,
      total_selections: Enum.sum(Enum.map(strategy_stats, fn {_, stats} -> stats.count end)),
      feature_weights: state.feature_weights
    }
  end
end