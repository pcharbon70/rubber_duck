defmodule RubberDuck.Jido.Actions.Correction.CostEstimationAction do
  @moduledoc """
  Action for estimating costs of correction strategies.
  
  This action provides detailed cost analysis including time, resources,
  risk factors, and ROI calculations for correction approaches.
  """
  
  use Jido.Action,
    name: "cost_estimation",
    description: "Estimate costs for correction strategies",
    schema: [
      error_context: [
        type: :map,
        required: true,
        doc: "Context information about the error"
      ],
      strategies: [
        type: {:list, :string},
        required: true,
        doc: "List of strategy IDs to estimate costs for"
      ],
      estimation_id: [
        type: :string,
        required: true,
        doc: "Unique identifier for this estimation request"
      ],
      include_breakdown: [
        type: :boolean,
        default: true,
        doc: "Include detailed cost breakdown"
      ],
      include_roi: [
        type: :boolean,
        default: true,
        doc: "Include return on investment calculations"
      ],
      confidence_threshold: [
        type: :float,
        default: 0.7,
        doc: "Minimum confidence threshold for estimates"
      ]
    ]
  
  require Logger
  
  @impl true
  def run(params, context) do
    agent = context.agent
    
    Logger.info("Processing cost estimation for #{length(params.strategies)} strategies")
    
    # Calculate cost estimates for each strategy
    cost_estimates = params.strategies
    |> Enum.map(fn strategy_id ->
      estimate_strategy_cost(
        strategy_id,
        agent.state.strategy_library,
        agent.state.cost_models,
        agent.state.learning_data,
        params.error_context,
        params
      )
    end)
    |> Map.new()
    
    # Calculate aggregate metrics
    aggregate = calculate_aggregate_metrics(cost_estimates)
    
    # Generate recommendations
    recommendations = generate_cost_recommendations(
      cost_estimates,
      params.confidence_threshold
    )
    
    result = %{
      estimation_id: params.estimation_id,
      cost_estimates: cost_estimates,
      aggregate_metrics: aggregate,
      recommendations: recommendations,
      timestamp: DateTime.utc_now()
    }
    
    {:ok, result}
  rescue
    error ->
      Logger.error("Cost estimation failed: #{inspect(error)}")
      {:error, %{reason: :estimation_failed, details: Exception.message(error)}}
  end
  
  # Private helper functions
  
  defp estimate_strategy_cost(strategy_id, strategy_library, cost_models, learning_data, error_context, params) do
    strategy = strategy_library[strategy_id]
    
    if strategy do
      # Calculate base cost
      base_cost = calculate_base_cost(strategy, cost_models, error_context)
      
      # Calculate confidence
      confidence = calculate_cost_confidence(learning_data, strategy_id, error_context)
      
      # Estimate execution time
      time_estimate = estimate_execution_time(strategy, error_context)
      
      # Calculate resource requirements
      resource_cost = calculate_resource_cost(strategy, error_context)
      
      # Calculate risk factors
      risk_assessment = assess_risk_factors(strategy, error_context)
      
      # Build estimate
      estimate = %{
        estimated_cost: base_cost,
        confidence: confidence,
        time_estimate: time_estimate,
        resource_cost: resource_cost,
        risk_assessment: risk_assessment
      }
      
      # Add breakdown if requested
      estimate = if params.include_breakdown do
        Map.put(estimate, :breakdown, build_cost_breakdown(
          strategy,
          cost_models,
          error_context,
          base_cost
        ))
      else
        estimate
      end
      
      # Add ROI if requested
      estimate = if params.include_roi do
        Map.put(estimate, :roi_analysis, calculate_roi(
          strategy,
          base_cost,
          error_context
        ))
      else
        estimate
      end
      
      {strategy_id, estimate}
    else
      {strategy_id, %{
        error: "Strategy not found",
        estimated_cost: 0.0,
        confidence: 0.0
      }}
    end
  end
  
  defp calculate_base_cost(strategy, cost_models, error_context) do
    base = strategy.base_cost
    
    # Apply cost model factors
    time_factor = cost_models["time_based"]["weight"]
    time_cost = base * time_factor
    
    complexity_factor = get_complexity_multiplier(cost_models, error_context)
    complexity_cost = base * cost_models["complexity_based"]["weight"] * complexity_factor
    
    risk_factor = get_risk_multiplier(strategy)
    risk_cost = base * cost_models["risk_based"]["weight"] * risk_factor
    
    # Additional factors
    urgency_factor = get_urgency_multiplier(error_context)
    scale_factor = get_scale_multiplier(error_context)
    
    total = (time_cost + complexity_cost + risk_cost) * urgency_factor * scale_factor
    
    Float.round(total, 2)
  end
  
  defp get_complexity_multiplier(cost_models, error_context) do
    complexity = Map.get(error_context, "complexity", "medium")
    cost_models["complexity_based"]["multipliers"][complexity] || 1.0
  end
  
  defp get_risk_multiplier(strategy) do
    risk_level = strategy.metadata["risk_level"] || "medium"
    
    case risk_level do
      "low" -> 1.0
      "medium" -> 1.3
      "high" -> 1.8
      "critical" -> 2.5
      _ -> 1.0
    end
  end
  
  defp get_urgency_multiplier(error_context) do
    urgency = Map.get(error_context, "urgency", "normal")
    
    case urgency do
      "low" -> 0.8
      "normal" -> 1.0
      "high" -> 1.3
      "critical" -> 1.6
      _ -> 1.0
    end
  end
  
  defp get_scale_multiplier(error_context) do
    affected_lines = Map.get(error_context, "affected_lines", 1)
    affected_files = Map.get(error_context, "affected_files", 1)
    
    # Simple scale calculation
    line_factor = :math.log(max(affected_lines, 1) + 1) / :math.log(100)
    file_factor = :math.log(max(affected_files, 1) + 1) / :math.log(10)
    
    1.0 + (line_factor * 0.3) + (file_factor * 0.2)
  end
  
  defp calculate_cost_confidence(learning_data, strategy_id, _error_context) do
    outcome_history = learning_data["outcome_history"] || []
    
    relevant_predictions = Enum.filter(outcome_history, fn outcome ->
      outcome["strategy_id"] == strategy_id
    end)
    
    if length(relevant_predictions) >= 5 do
      # Calculate prediction accuracy
      accurate_predictions = Enum.count(relevant_predictions, fn outcome ->
        predicted = outcome["predicted_cost"] || 0.0
        actual = outcome["actual_cost"] || 0.0
        
        # Within 20% is considered accurate
        abs(predicted - actual) / max(actual, 0.01) <= 0.2
      end)
      
      accuracy = accurate_predictions / length(relevant_predictions)
      
      # Adjust confidence based on sample size
      sample_factor = min(1.0, length(relevant_predictions) / 20)
      accuracy * sample_factor
    else
      # Low confidence for strategies with little history
      0.3
    end
  end
  
  defp estimate_execution_time(strategy, error_context) do
    base_time = strategy.metadata["avg_execution_time"] || 2000
    
    complexity_factor = case Map.get(error_context, "complexity", "medium") do
      "low" -> 0.7
      "medium" -> 1.0
      "high" -> 1.5
      "critical" -> 2.0
      _ -> 1.0
    end
    
    size_factor = get_scale_multiplier(error_context)
    
    estimated = round(base_time * complexity_factor * size_factor)
    
    %{
      estimated_ms: estimated,
      estimated_seconds: estimated / 1000,
      confidence: 0.75
    }
  end
  
  defp calculate_resource_cost(strategy, error_context) do
    %{
      cpu_units: estimate_cpu_units(strategy, error_context),
      memory_mb: estimate_memory_usage(strategy, error_context),
      io_operations: estimate_io_operations(strategy, error_context),
      network_calls: estimate_network_calls(strategy),
      estimated_tokens: estimate_token_usage(strategy, error_context)
    }
  end
  
  defp estimate_cpu_units(strategy, error_context) do
    base_cpu = strategy.metadata["base_cpu_units"] || 1.0
    complexity = Map.get(error_context, "complexity", "medium")
    
    multiplier = case complexity do
      "low" -> 0.5
      "medium" -> 1.0
      "high" -> 2.0
      _ -> 1.0
    end
    
    base_cpu * multiplier
  end
  
  defp estimate_memory_usage(strategy, error_context) do
    base_memory = strategy.metadata["base_memory_mb"] || 50
    file_size = Map.get(error_context, "file_size", 1000)
    
    # Rough estimate based on file size
    additional_memory = file_size / 1000 * 10
    base_memory + additional_memory
  end
  
  defp estimate_io_operations(strategy, error_context) do
    affected_files = Map.get(error_context, "affected_files", 1)
    strategy.metadata["io_operations_per_file"] || 3 * affected_files
  end
  
  defp estimate_network_calls(strategy) do
    strategy.metadata["network_calls"] || 0
  end
  
  defp estimate_token_usage(strategy, error_context) do
    if strategy.metadata["uses_llm"] do
      file_size = Map.get(error_context, "file_size", 1000)
      # Rough token estimate
      file_size / 4 + 500  # base tokens for prompt
    else
      0
    end
  end
  
  defp assess_risk_factors(strategy, error_context) do
    %{
      risk_level: strategy.metadata["risk_level"] || "medium",
      potential_side_effects: identify_side_effects(strategy, error_context),
      rollback_difficulty: assess_rollback_difficulty(strategy),
      confidence_level: calculate_risk_confidence(strategy, error_context),
      mitigation_strategies: suggest_mitigations(strategy)
    }
  end
  
  defp identify_side_effects(strategy, error_context) do
    side_effects = []
    
    side_effects = if strategy.metadata["modifies_code"] do
      ["Code modifications may affect dependent modules" | side_effects]
    else
      side_effects
    end
    
    side_effects = if Map.get(error_context, "affects_api", false) do
      ["API changes may affect external consumers" | side_effects]
    else
      side_effects
    end
    
    side_effects
  end
  
  defp assess_rollback_difficulty(strategy) do
    if strategy.metadata["reversible"] do
      "easy"
    else
      strategy.metadata["rollback_difficulty"] || "medium"
    end
  end
  
  defp calculate_risk_confidence(strategy, _error_context) do
    # Based on strategy success rate and metadata
    base_confidence = strategy.success_rate
    risk_adjustment = case strategy.metadata["risk_level"] do
      "low" -> 0.1
      "medium" -> 0.0
      "high" -> -0.1
      _ -> 0.0
    end
    
    min(1.0, max(0.0, base_confidence + risk_adjustment))
  end
  
  defp suggest_mitigations(strategy) do
    strategy.metadata["mitigation_strategies"] || [
      "Create backup before applying correction",
      "Test in isolated environment first",
      "Review changes before committing"
    ]
  end
  
  defp build_cost_breakdown(strategy, cost_models, error_context, total_cost) do
    base = strategy.base_cost
    
    time_component = base * cost_models["time_based"]["weight"]
    complexity_component = base * cost_models["complexity_based"]["weight"] * 
                          get_complexity_multiplier(cost_models, error_context)
    risk_component = base * cost_models["risk_based"]["weight"] * 
                    get_risk_multiplier(strategy)
    
    %{
      base_cost: base,
      time_component: Float.round(time_component, 2),
      complexity_component: Float.round(complexity_component, 2),
      risk_component: Float.round(risk_component, 2),
      urgency_multiplier: get_urgency_multiplier(error_context),
      scale_multiplier: Float.round(get_scale_multiplier(error_context), 2),
      total: Float.round(total_cost, 2)
    }
  end
  
  defp calculate_roi(strategy, cost, error_context) do
    # Estimate value of fixing the error
    severity = Map.get(error_context, "severity", "medium")
    base_value = case severity do
      "low" -> 5.0
      "medium" -> 15.0
      "high" -> 50.0
      "critical" -> 100.0
      _ -> 10.0
    end
    
    # Adjust for business impact
    business_impact = Map.get(error_context, "business_impact", 1.0)
    adjusted_value = base_value * business_impact
    
    # Calculate ROI
    roi = if cost > 0 do
      (adjusted_value - cost) / cost * 100
    else
      100.0
    end
    
    %{
      estimated_value: Float.round(adjusted_value, 2),
      estimated_cost: Float.round(cost, 2),
      roi_percentage: Float.round(roi, 1),
      payback_period: calculate_payback_period(cost, adjusted_value),
      recommendation: roi_recommendation(roi)
    }
  end
  
  defp calculate_payback_period(cost, value) do
    if value > cost do
      "immediate"
    else
      "longer term"
    end
  end
  
  defp roi_recommendation(roi) do
    cond do
      roi >= 100 -> "Highly recommended - excellent ROI"
      roi >= 50 -> "Recommended - good ROI"
      roi >= 0 -> "Consider - positive ROI"
      roi >= -20 -> "Questionable - marginal ROI"
      true -> "Not recommended - negative ROI"
    end
  end
  
  defp calculate_aggregate_metrics(cost_estimates) do
    estimates = Map.values(cost_estimates)
    |> Enum.reject(& Map.has_key?(&1, :error))
    
    if length(estimates) > 0 do
      costs = Enum.map(estimates, & &1.estimated_cost)
      confidences = Enum.map(estimates, & &1.confidence)
      
      %{
        min_cost: Enum.min(costs),
        max_cost: Enum.max(costs),
        avg_cost: Float.round(Enum.sum(costs) / length(costs), 2),
        total_cost: Float.round(Enum.sum(costs), 2),
        avg_confidence: Float.round(Enum.sum(confidences) / length(confidences), 2),
        strategy_count: length(estimates)
      }
    else
      %{
        error: "No valid estimates available"
      }
    end
  end
  
  defp generate_cost_recommendations(cost_estimates, confidence_threshold) do
    valid_estimates = cost_estimates
    |> Enum.reject(fn {_id, est} -> Map.has_key?(est, :error) end)
    |> Enum.filter(fn {_id, est} -> est.confidence >= confidence_threshold end)
    |> Enum.sort_by(fn {_id, est} -> est.estimated_cost end)
    
    case valid_estimates do
      [{best_id, best} | rest] ->
        alternatives = Enum.take(rest, 2)
        |> Enum.map(fn {id, est} -> 
          %{strategy_id: id, cost: est.estimated_cost, confidence: est.confidence}
        end)
        
        %{
          best_value: %{
            strategy_id: best_id,
            cost: best.estimated_cost,
            confidence: best.confidence,
            reason: "Lowest cost with acceptable confidence"
          },
          alternatives: alternatives,
          total_strategies_evaluated: map_size(cost_estimates)
        }
        
      [] ->
        %{
          error: "No strategies meet confidence threshold",
          threshold: confidence_threshold
        }
    end
  end
end