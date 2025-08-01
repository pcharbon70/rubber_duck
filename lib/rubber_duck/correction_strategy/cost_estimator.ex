defmodule RubberDuck.CorrectionStrategy.CostEstimator do
  @moduledoc """
  Cost estimation engine for correction strategies.
  
  Provides comprehensive cost calculation including:
  - Time-based costs (LLM usage, processing time)
  - Resource costs (computational resources, human time)
  - Risk-adjusted costs (potential for additional errors)
  - ROI analysis and optimization recommendations
  """

  @doc """
  Calculates comprehensive cost estimate for a correction strategy.
  """
  def estimate_cost(strategy, error_context, cost_models, historical_data \\ %{}) do
    base_components = %{
      time_cost: calculate_time_cost(strategy, error_context, cost_models),
      resource_cost: calculate_resource_cost(strategy, error_context, cost_models),
      risk_cost: calculate_risk_cost(strategy, error_context, cost_models),
      opportunity_cost: calculate_opportunity_cost(strategy, error_context)
    }
    
    # Apply historical adjustments
    adjusted_components = apply_historical_adjustments(base_components, historical_data, strategy)
    
    # Calculate total cost
    total_cost = adjusted_components
    |> Map.values()
    |> Enum.sum()
    
    confidence = calculate_confidence(adjusted_components, historical_data, strategy)
    
    %{
      total_cost: total_cost,
      components: adjusted_components,
      confidence: confidence,
      breakdown: generate_cost_breakdown(adjusted_components),
      recommendations: generate_cost_recommendations(adjusted_components, strategy)
    }
  end

  @doc """
  Compares costs across multiple strategies for the same error.
  """
  def compare_strategies(strategies, error_context, cost_models, historical_data \\ %{}) do
    estimates = strategies
    |> Enum.map(fn {strategy_id, strategy} ->
      estimate = estimate_cost(strategy, error_context, cost_models, historical_data)
      {strategy_id, estimate}
    end)
    |> Map.new()
    
    # Calculate cost-effectiveness scores
    effectiveness_scores = calculate_effectiveness_scores(estimates, strategies)
    
    # Rank by cost-effectiveness
    rankings = rank_by_cost_effectiveness(estimates, effectiveness_scores)
    
    %{
      estimates: estimates,
      effectiveness_scores: effectiveness_scores,
      rankings: rankings,
      best_value: get_best_value_strategy(rankings)
    }
  end

  @doc """
  Updates cost models based on actual outcomes.
  """
  def update_cost_models(cost_models, actual_outcomes) do
    learning_rate = 0.1
    
    updated_models = cost_models
    |> update_time_model(actual_outcomes, learning_rate)
    |> update_resource_model(actual_outcomes, learning_rate)
    |> update_risk_model(actual_outcomes, learning_rate)
    
    {:ok, updated_models}
  end

  # Private Functions

  defp calculate_time_cost(strategy, error_context, cost_models) do
    time_model = cost_models["time_based"] || %{"base_rate" => 0.10}
    base_rate = time_model["base_rate"]
    
    # Base time estimate from strategy metadata
    base_time_seconds = (strategy.metadata["avg_execution_time"] || 2000) / 1000
    
    # Adjust for error complexity
    complexity_multiplier = get_complexity_multiplier(error_context)
    
    # Adjust for file size
    size_multiplier = get_size_multiplier(error_context)
    
    # Calculate LLM costs if strategy involves AI
    llm_cost = if uses_llm?(strategy) do
      calculate_llm_cost(error_context, strategy)
    else
      0.0
    end
    
    processing_time = base_time_seconds * complexity_multiplier * size_multiplier
    processing_cost = processing_time * base_rate
    
    processing_cost + llm_cost
  end

  defp calculate_resource_cost(strategy, error_context, cost_models) do
    resource_model = cost_models["resource_based"] || %{"cpu_rate" => 0.05, "memory_rate" => 0.02}
    
    # Estimate CPU usage
    cpu_intensity = get_cpu_intensity(strategy, error_context)
    cpu_cost = cpu_intensity * resource_model["cpu_rate"]
    
    # Estimate memory usage
    memory_usage = get_memory_usage(strategy, error_context)
    memory_cost = memory_usage * resource_model["memory_rate"]
    
    # Human resource cost if interactive
    human_cost = if requires_human_interaction?(strategy) do
      calculate_human_cost(strategy, error_context)
    else
      0.0
    end
    
    cpu_cost + memory_cost + human_cost
  end

  defp calculate_risk_cost(strategy, error_context, cost_models) do
    risk_model = cost_models["risk_based"] || %{"base_penalty" => 1.0}
    base_penalty = risk_model["base_penalty"]
    
    # Risk factors
    risk_factors = %{
      strategy_risk: get_strategy_risk_multiplier(strategy),
      context_risk: get_context_risk_multiplier(error_context),
      cascading_risk: get_cascading_risk_multiplier(error_context),
      rollback_risk: get_rollback_risk_multiplier(strategy)
    }
    
    # Calculate weighted risk cost
    total_risk_multiplier = risk_factors
    |> Map.values()
    |> Enum.sum()
    |> Kernel./(map_size(risk_factors))
    
    base_penalty * total_risk_multiplier
  end

  defp calculate_opportunity_cost(_strategy, error_context) do
    # Cost of not applying alternative strategies
    urgency = Map.get(error_context, "urgency", "medium")
    
    case urgency do
      "critical" -> 5.0
      "high" -> 2.0
      "medium" -> 1.0
      "low" -> 0.5
      _ -> 1.0
    end
  end

  defp apply_historical_adjustments(base_components, historical_data, strategy) do
    if map_size(historical_data) > 0 do
      historical_accuracy = get_historical_accuracy(historical_data, strategy)
      adjustment_factor = 1.0 + (1.0 - historical_accuracy) * 0.2
      
      base_components
      |> Enum.map(fn {component, cost} ->
        {component, cost * adjustment_factor}
      end)
      |> Map.new()
    else
      base_components
    end
  end

  defp calculate_confidence(components, historical_data, strategy) do
    # Base confidence from component reliability
    base_confidence = 0.7
    
    # Adjust based on historical accuracy
    historical_adjustment = if map_size(historical_data) > 0 do
      accuracy = get_historical_accuracy(historical_data, strategy)
      (accuracy - 0.5) * 0.4  # Scale to -0.2 to +0.2
    else
      -0.1  # Slight penalty for no historical data
    end
    
    # Adjust based on cost component variance
    variance_penalty = calculate_variance_penalty(components)
    
    min(1.0, max(0.0, base_confidence + historical_adjustment - variance_penalty))
  end

  defp get_complexity_multiplier(error_context) do
    complexity = Map.get(error_context, "complexity", "medium")
    
    case complexity do
      "low" -> 0.8
      "medium" -> 1.0
      "high" -> 1.5
      "critical" -> 2.0
      _ -> 1.0
    end
  end

  defp get_size_multiplier(error_context) do
    file_size = Map.get(error_context, "file_size", 500)
    
    cond do
      file_size < 100 -> 0.8
      file_size < 500 -> 1.0
      file_size < 1000 -> 1.2
      file_size < 5000 -> 1.5
      true -> 2.0
    end
  end

  defp uses_llm?(strategy) do
    strategy.metadata
    |> Map.get("requires_llm", false)
  end

  defp calculate_llm_cost(error_context, strategy) do
    # Estimate tokens needed
    context_size = Map.get(error_context, "context_size", 1000)
    strategy_complexity = Map.get(strategy.metadata, "llm_complexity", "medium")
    
    base_tokens = case strategy_complexity do
      "simple" -> 500
      "medium" -> 1500
      "complex" -> 3000
      _ -> 1500
    end
    
    estimated_tokens = base_tokens + (context_size * 0.5)
    
    # Token cost (example rate)
    token_rate = 0.002 / 1000  # $0.002 per 1K tokens
    estimated_tokens * token_rate
  end

  defp get_cpu_intensity(strategy, error_context) do
    base_intensity = strategy.metadata["cpu_intensity"] || "medium"
    
    multiplier = case base_intensity do
      "low" -> 1.0
      "medium" -> 2.0
      "high" -> 4.0
      _ -> 2.0
    end
    
    # Adjust for error context
    complexity_bonus = case Map.get(error_context, "complexity", "medium") do
      "low" -> 0.0
      "medium" -> 1.0
      "high" -> 2.0
      _ -> 1.0
    end
    
    multiplier + complexity_bonus
  end

  defp get_memory_usage(strategy, error_context) do
    base_usage = strategy.metadata["memory_usage"] || 1.0
    file_size = Map.get(error_context, "file_size", 500)
    
    # Memory scales with file size for parsing/analysis
    base_usage * (1 + file_size / 1000)
  end

  defp requires_human_interaction?(strategy) do
    strategy.prerequisites
    |> Enum.any?(fn prereq -> prereq == "user_available" end)
  end

  defp calculate_human_cost(strategy, error_context) do
    # Estimate human time required
    base_human_time = strategy.metadata["human_time_minutes"] || 10
    complexity_multiplier = get_complexity_multiplier(error_context)
    
    estimated_minutes = base_human_time * complexity_multiplier
    
    # Human cost rate ($/minute)
    human_rate = 0.50  # $30/hour rate
    estimated_minutes * human_rate
  end

  defp get_strategy_risk_multiplier(strategy) do
    risk_level = strategy.metadata["risk_level"] || "medium"
    
    case risk_level do
      "low" -> 1.0
      "medium" -> 1.3
      "high" -> 1.8
      "critical" -> 2.5
      _ -> 1.3
    end
  end

  defp get_context_risk_multiplier(error_context) do
    # Risk based on error location and impact
    criticality = Map.get(error_context, "criticality", "medium")
    
    case criticality do
      "low" -> 1.0
      "medium" -> 1.2
      "high" -> 1.5
      "critical" -> 2.0
      _ -> 1.2
    end
  end

  defp get_cascading_risk_multiplier(error_context) do
    # Risk of correction causing other issues
    interconnectedness = Map.get(error_context, "interconnectedness", "medium")
    
    case interconnectedness do
      "isolated" -> 1.0
      "low" -> 1.1
      "medium" -> 1.3
      "high" -> 1.6
      "critical" -> 2.0
      _ -> 1.3
    end
  end

  defp get_rollback_risk_multiplier(strategy) do
    rollback_difficulty = strategy.metadata["rollback_difficulty"] || "medium"
    
    case rollback_difficulty do
      "easy" -> 1.0
      "medium" -> 1.2
      "hard" -> 1.5
      "impossible" -> 2.0
      _ -> 1.2
    end
  end

  defp get_historical_accuracy(historical_data, strategy) do
    strategy_history = Map.get(historical_data, strategy.name, [])
    
    if length(strategy_history) > 0 do
      accurate_predictions = Enum.count(strategy_history, fn record ->
        predicted = record["predicted_cost"] || 0.0
        actual = record["actual_cost"] || 0.0
        
        # Within 20% is considered accurate
        if actual > 0 do
          abs(predicted - actual) / actual <= 0.2
        else
          predicted == 0.0
        end
      end)
      
      accurate_predictions / length(strategy_history)
    else
      0.5  # Default for no history
    end
  end

  defp calculate_variance_penalty(components) do
    costs = Map.values(components)
    
    if length(costs) > 1 do
      mean_cost = Enum.sum(costs) / length(costs)
      
      variance = costs
      |> Enum.map(fn cost -> :math.pow(cost - mean_cost, 2) end)
      |> Enum.sum()
      |> Kernel./(length(costs))
      
      # Normalize variance to penalty (0 to 0.2)
      min(0.2, variance / (mean_cost * mean_cost))
    else
      0.0
    end
  end

  defp generate_cost_breakdown(components) do
    total = Map.values(components) |> Enum.sum()
    
    if total > 0 do
      components
      |> Enum.map(fn {component, cost} ->
        percentage = (cost / total) * 100
        {component, %{cost: cost, percentage: Float.round(percentage, 1)}}
      end)
      |> Map.new()
    else
      %{}
    end
  end

  defp generate_cost_recommendations(components, _strategy) do
    recommendations = []
    
    # High time cost recommendation
    recommendations = if components.time_cost > 5.0 do
      [%{
        type: :cost_optimization,
        component: :time_cost,
        description: "Consider parallel processing or caching to reduce time costs",
        potential_savings: components.time_cost * 0.3
      } | recommendations]
    else
      recommendations
    end
    
    # High risk cost recommendation
    recommendations = if components.risk_cost > 2.0 do
      [%{
        type: :risk_mitigation,
        component: :risk_cost,
        description: "Implement additional validation steps to reduce risk",
        potential_savings: components.risk_cost * 0.4
      } | recommendations]
    else
      recommendations
    end
    
    recommendations
  end

  defp calculate_effectiveness_scores(estimates, strategies) do
    estimates
    |> Enum.map(fn {strategy_id, estimate} ->
      strategy = strategies[strategy_id]
      
      # Effectiveness = Success Rate / Cost
      effectiveness = if estimate.total_cost > 0 do
        strategy.success_rate / estimate.total_cost
      else
        strategy.success_rate
      end
      
      {strategy_id, effectiveness}
    end)
    |> Map.new()
  end

  defp rank_by_cost_effectiveness(estimates, effectiveness_scores) do
    effectiveness_scores
    |> Enum.sort_by(fn {_strategy_id, score} -> score end, :desc)
    |> Enum.with_index(1)
    |> Enum.map(fn {{strategy_id, score}, rank} ->
      estimate = estimates[strategy_id]
      
      %{
        rank: rank,
        strategy_id: strategy_id,
        effectiveness_score: score,
        total_cost: estimate.total_cost,
        confidence: estimate.confidence
      }
    end)
  end

  defp get_best_value_strategy(rankings) do
    case rankings do
      [best | _] -> best
      [] -> nil
    end
  end

  # Cost model updates
  defp update_time_model(cost_models, actual_outcomes, learning_rate) do
    time_model = cost_models["time_based"] || %{"base_rate" => 0.10}
    
    # Calculate average prediction error for time costs
    time_outcomes = Enum.filter(actual_outcomes, &Map.has_key?(&1, "actual_time_cost"))
    
    if length(time_outcomes) > 0 do
      avg_error = calculate_average_prediction_error(time_outcomes, "time_cost")
      
      # Adjust base rate
      current_rate = time_model["base_rate"]
      adjustment = avg_error * learning_rate
      new_rate = max(0.01, current_rate + adjustment)
      
      updated_time_model = %{time_model | "base_rate" => new_rate}
      %{cost_models | "time_based" => updated_time_model}
    else
      cost_models
    end
  end

  defp update_resource_model(cost_models, actual_outcomes, learning_rate) do
    resource_model = cost_models["resource_based"] || %{"cpu_rate" => 0.05, "memory_rate" => 0.02}
    
    # Update CPU rate
    cpu_outcomes = Enum.filter(actual_outcomes, &Map.has_key?(&1, "actual_cpu_cost"))
    updated_model = if length(cpu_outcomes) > 0 do
      cpu_error = calculate_average_prediction_error(cpu_outcomes, "cpu_cost")
      current_cpu_rate = resource_model["cpu_rate"]
      new_cpu_rate = max(0.01, current_cpu_rate + cpu_error * learning_rate)
      
      %{resource_model | "cpu_rate" => new_cpu_rate}
    else
      resource_model
    end
    
    # Update memory rate
    memory_outcomes = Enum.filter(actual_outcomes, &Map.has_key?(&1, "actual_memory_cost"))
    final_model = if length(memory_outcomes) > 0 do
      memory_error = calculate_average_prediction_error(memory_outcomes, "memory_cost")
      current_memory_rate = updated_model["memory_rate"]
      new_memory_rate = max(0.01, current_memory_rate + memory_error * learning_rate)
      
      %{updated_model | "memory_rate" => new_memory_rate}
    else
      updated_model
    end
    
    %{cost_models | "resource_based" => final_model}
  end

  defp update_risk_model(cost_models, actual_outcomes, learning_rate) do
    risk_model = cost_models["risk_based"] || %{"base_penalty" => 1.0}
    
    risk_outcomes = Enum.filter(actual_outcomes, &Map.has_key?(&1, "actual_risk_cost"))
    
    if length(risk_outcomes) > 0 do
      risk_error = calculate_average_prediction_error(risk_outcomes, "risk_cost")
      current_penalty = risk_model["base_penalty"]
      new_penalty = max(0.1, current_penalty + risk_error * learning_rate)
      
      updated_risk_model = %{risk_model | "base_penalty" => new_penalty}
      %{cost_models | "risk_based" => updated_risk_model}
    else
      cost_models
    end
  end

  defp calculate_average_prediction_error(outcomes, cost_type) do
    if length(outcomes) > 0 do
      total_error = outcomes
      |> Enum.map(fn outcome ->
        predicted = outcome["predicted_#{cost_type}"] || 0.0
        actual = outcome["actual_#{cost_type}"] || 0.0
        
        if actual > 0 do
          (predicted - actual) / actual
        else
          0.0
        end
      end)
      |> Enum.sum()
      
      total_error / length(outcomes)
    else
      0.0
    end
  end
end