defmodule RubberDuck.Jido.Actions.Correction.StrategySelectionAction do
  @moduledoc """
  Action for selecting optimal correction strategies based on error data and constraints.
  
  This action evaluates available strategies, calculates costs and confidence scores,
  and provides ranked recommendations for error correction.
  """
  
  use Jido.Action,
    name: "strategy_selection",
    description: "Select and rank correction strategies for detected errors",
    schema: [
      error_data: [
        type: :map,
        required: true,
        doc: "Error information including type, context, and severity"
      ],
      constraints: [
        type: :map,
        default: %{},
        doc: "Constraints for strategy selection (max_cost, confidence_threshold)"
      ],
      selection_id: [
        type: :string,
        required: true,
        doc: "Unique identifier for this selection request"
      ],
      include_alternatives: [
        type: :boolean,
        default: true,
        doc: "Include alternative strategies in addition to the top recommendation"
      ],
      max_strategies: [
        type: :integer,
        default: 5,
        doc: "Maximum number of strategies to return"
      ]
    ]
  
  require Logger
  
  @impl true
  def run(params, context) do
    agent = context.agent
    
    Logger.info("Processing strategy selection for error: #{params.error_data["error_id"]}")
    
    # Get applicable strategies from agent's library
    applicable_strategies = get_applicable_strategies(
      agent.state.strategy_library,
      params.error_data
    )
    
    # Calculate costs for each strategy
    cost_estimates = calculate_cost_estimates(
      applicable_strategies,
      agent.state.cost_models,
      params.error_data
    )
    
    # Calculate confidence scores
    confidence_scores = calculate_confidence_scores(
      applicable_strategies,
      agent.state.learning_data,
      params.error_data
    )
    
    # Rank strategies by composite score
    ranked_strategies = rank_strategies(
      applicable_strategies,
      cost_estimates,
      confidence_scores,
      params.constraints
    )
    |> Enum.take(params.max_strategies)
    
    # Select top recommendation
    recommendation = get_top_recommendation(ranked_strategies, params.constraints)
    
    # Update metrics
    metrics = update_selection_metrics(agent.state.performance_metrics)
    
    result = %{
      selection_id: params.selection_id,
      strategies: if(params.include_alternatives, do: ranked_strategies, else: [hd(ranked_strategies)]),
      cost_estimates: cost_estimates,
      confidence_scores: confidence_scores,
      recommendation: recommendation,
      metrics_updated: metrics,
      timestamp: DateTime.utc_now()
    }
    
    {:ok, result}
  rescue
    error ->
      Logger.error("Strategy selection failed: #{inspect(error)}")
      {:error, %{reason: :selection_failed, details: Exception.message(error)}}
  end
  
  # Private helper functions
  
  defp get_applicable_strategies(strategy_library, error_data) do
    strategy_library
    |> Enum.filter(fn {_id, strategy} ->
      matches_category?(strategy, error_data) and
      meets_constraints?(strategy, error_data)
    end)
  end
  
  defp matches_category?(strategy, error_data) do
    error_type = Map.get(error_data, "error_type", "unknown")
    strategy_category = strategy.category
    
    String.contains?(error_type, strategy_category) or
    strategy_category == "general" or
    (error_type == "syntax_error" and strategy_category == "syntax")
  end
  
  defp meets_constraints?(strategy, error_data) do
    strategy.constraints
    |> Enum.all?(fn constraint ->
      evaluate_constraint(constraint, error_data)
    end)
  end
  
  defp evaluate_constraint(constraint, error_data) do
    case constraint do
      "file_size < 1000" ->
        Map.get(error_data, "file_size", 0) < 1000
      
      "complexity == low" ->
        Map.get(error_data, "complexity", "medium") == "low"
      
      "complexity <= high" ->
        complexity = Map.get(error_data, "complexity", "medium")
        complexity in ["low", "medium", "high"]
      
      _ ->
        true
    end
  end
  
  defp calculate_cost_estimates(strategies, cost_models, error_data) do
    Enum.map(strategies, fn {strategy_id, strategy} ->
      cost = calculate_strategy_cost(cost_models, strategy, error_data)
      {strategy_id, cost}
    end)
    |> Map.new()
  end
  
  defp calculate_strategy_cost(cost_models, strategy, error_data) do
    base_cost = strategy.base_cost
    
    time_cost = base_cost * cost_models["time_based"]["weight"]
    
    complexity_multiplier = get_complexity_multiplier(cost_models, error_data)
    complexity_cost = base_cost * cost_models["complexity_based"]["weight"] * complexity_multiplier
    
    risk_multiplier = get_risk_multiplier(strategy)
    risk_cost = base_cost * cost_models["risk_based"]["weight"] * risk_multiplier
    
    time_cost + complexity_cost + risk_cost
  end
  
  defp get_complexity_multiplier(cost_models, error_data) do
    complexity = Map.get(error_data, "complexity", "medium")
    cost_models["complexity_based"]["multipliers"][complexity] || 1.0
  end
  
  defp get_risk_multiplier(strategy) do
    strategy_risk = strategy.metadata["risk_level"] || "medium"
    
    case strategy_risk do
      "low" -> 1.0
      "medium" -> 1.3
      "high" -> 1.8
      _ -> 1.0
    end
  end
  
  defp calculate_confidence_scores(strategies, learning_data, error_data) do
    Enum.map(strategies, fn {strategy_id, strategy} ->
      confidence = calculate_selection_confidence(learning_data, strategy, error_data)
      {strategy_id, confidence}
    end)
    |> Map.new()
  end
  
  defp calculate_selection_confidence(learning_data, strategy, _error_data) do
    base_confidence = strategy.success_rate
    historical_adjustment = get_historical_adjustment(learning_data, strategy)
    
    min(1.0, max(0.0, base_confidence + historical_adjustment))
  end
  
  defp get_historical_adjustment(learning_data, strategy) do
    outcome_history = learning_data["outcome_history"] || []
    
    relevant_outcomes = Enum.filter(outcome_history, fn outcome ->
      outcome["strategy_id"] == strategy.name
    end)
    
    if length(relevant_outcomes) > 0 do
      success_rate = Enum.count(relevant_outcomes, & &1["success"]) / length(relevant_outcomes)
      success_rate - strategy.success_rate
    else
      0.0
    end
  end
  
  defp rank_strategies(strategies, cost_estimates, confidence_scores, constraints) do
    max_cost = Map.get(constraints, "max_cost", 100.0)
    confidence_threshold = Map.get(constraints, "confidence_threshold", 0.5)
    
    strategies
    |> Enum.filter(fn {strategy_id, _strategy} ->
      cost_estimates[strategy_id] <= max_cost and
      confidence_scores[strategy_id] >= confidence_threshold
    end)
    |> Enum.map(fn {strategy_id, strategy} ->
      cost = cost_estimates[strategy_id]
      confidence = confidence_scores[strategy_id]
      composite_score = confidence / (1 + cost * 0.1)
      
      %{
        strategy_id: strategy_id,
        strategy: strategy,
        cost: cost,
        confidence: confidence,
        composite_score: composite_score
      }
    end)
    |> Enum.sort_by(& &1.composite_score, :desc)
  end
  
  defp get_top_recommendation(ranked_strategies, _constraints) do
    case ranked_strategies do
      [top_strategy | _] ->
        %{
          strategy_id: top_strategy.strategy_id,
          confidence: top_strategy.confidence,
          estimated_cost: top_strategy.cost,
          reasoning: "Highest composite score based on confidence and cost effectiveness"
        }
      
      [] ->
        %{
          strategy_id: nil,
          confidence: 0.0,
          estimated_cost: 0.0,
          reasoning: "No strategies meet the specified constraints"
        }
    end
  end
  
  defp update_selection_metrics(performance_metrics) do
    overall_metrics = performance_metrics["overall"] || %{
      "total_selections" => 0,
      "successful_corrections" => 0,
      "avg_selection_time" => 0.0,
      "cost_prediction_accuracy" => 0.0
    }
    
    %{overall_metrics | "total_selections" => overall_metrics["total_selections"] + 1}
  end
end