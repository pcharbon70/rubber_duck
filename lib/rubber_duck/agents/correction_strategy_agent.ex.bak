defmodule RubberDuck.Agents.CorrectionStrategyAgent do
  @moduledoc """
  Correction Strategy Agent for intelligent strategy selection and cost estimation.
  
  This agent provides comprehensive strategy selection, cost estimation, and learning
  capabilities for error correction workflows, working in conjunction with the Error
  Detection Agent to recommend optimal correction approaches.
  
  ## Features
  
  - Multi-criteria strategy selection with cost-effectiveness ranking
  - Comprehensive cost estimation (time, resources, risk, ROI)
  - Learning system that tracks strategy outcomes and improves selection accuracy
  - A/B testing framework for strategy comparison and optimization
  - Real-time strategy recommendations with confidence scoring
  - Integration with Error Detection Agent for seamless workflow
  
  ## Signals
  
  ### Input Signals
  - `strategy_selection_request` - Request strategy recommendations for detected errors
  - `strategy_outcome_feedback` - Learn from correction outcomes and improve selection
  - `cost_estimation_request` - Provide cost estimates for correction strategies
  - `strategy_library_update` - Update or add new correction strategies
  - `performance_metrics_request` - Request strategy performance analytics
  
  ### Output Signals
  - `strategy_selection_result` - Selected strategies with rankings and cost estimates
  - `cost_estimation_result` - Detailed cost analysis for correction approaches
  - `strategy_learning_update` - Updates based on correction outcomes
  - `performance_metrics_report` - Strategy effectiveness and learning analytics
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "correction_strategy",
    description: "Strategy selection and cost estimation for error corrections",
    category: "correction",
    schema: [
      strategy_status: [type: :atom, values: [:idle, :analyzing, :selecting, :learning], default: :idle],
      active_evaluations: [type: :map, default: %{}],
      strategy_library: [type: :map, default: %{
        "syntax_fix_basic" => %{
          name: "Basic Syntax Fix",
          category: "syntax",
          description: "Automated fixing of common syntax errors",
          base_cost: 2.0,
          success_rate: 0.85,
          prerequisites: [],
          constraints: ["file_size < 1000", "complexity == low"],
          metadata: %{
            "supported_languages" => ["elixir", "javascript", "python"],
            "avg_execution_time" => 1500,
            "risk_level" => "low"
          }
        },
        "logic_fix_guided" => %{
          name: "Guided Logic Fix",
          category: "logic",
          description: "Interactive logic error correction with user guidance",
          base_cost: 8.0,
          success_rate: 0.75,
          prerequisites: ["user_available"],
          constraints: ["complexity <= high"],
          metadata: %{
            "supported_languages" => ["elixir"],
            "avg_execution_time" => 5000,
            "risk_level" => "medium"
          }
        }
      }],
      cost_models: [type: :map, default: %{
        "time_based" => %{
          "weight" => 0.4,
          "base_rate" => 0.10  # Cost per second
        },
        "complexity_based" => %{
          "weight" => 0.3,
          "multipliers" => %{"low" => 1.0, "medium" => 1.5, "high" => 2.0}
        },
        "risk_based" => %{
          "weight" => 0.3,
          "multipliers" => %{"low" => 1.0, "medium" => 1.3, "high" => 1.8}
        }
      }],
      learning_data: [type: :map, default: %{
        "outcome_history" => [],
        "pattern_weights" => %{},
        "adaptation_rate" => 0.1
      }],
      performance_metrics: [type: :map, default: %{
        "overall" => %{
          "total_selections" => 0,
          "successful_corrections" => 0,
          "avg_selection_time" => 0.0,
          "cost_prediction_accuracy" => 0.0
        }
      }]
    ]

  require Logger

  # Signal Handlers

  def handle_signal(agent, %{"type" => "strategy_selection_request"} = signal) do
    %{
      "data" => %{
        "error_data" => error_data,
        "constraints" => constraints
      }
    } = signal
    
    selection_id = signal["id"]
    
    Logger.info("Processing strategy selection request for error: #{error_data["error_id"]}")
    
    # Update agent status
    agent = %{agent | state: %{agent.state | strategy_status: :selecting}}
    
    # Track active evaluation
    evaluation_info = %{
      error_data: error_data,
      constraints: constraints,
      started_at: DateTime.utc_now(),
      status: :in_progress
    }
    
    agent = put_in(agent.state.active_evaluations[selection_id], evaluation_info)
    
    # Perform strategy selection
    selection_result = select_strategies(agent, error_data, constraints)
    
    # Update metrics
    agent = update_selection_metrics(agent, selection_id, selection_result)
    
    # Emit selection result
    result_signal = Jido.Signal.new!(%{
      type: "correction.strategy.selection.result",
      source: "agent:#{agent.id}",
      data: %{
        selection_id: selection_id,
        strategies: selection_result.strategies,
        cost_estimates: selection_result.cost_estimates,
        confidence_scores: selection_result.confidence_scores,
        recommendation: selection_result.recommendation,
        timestamp: DateTime.utc_now()
      }
    })
    
    emit_signal(agent, result_signal)
    
    # Update evaluation status before cleanup
    agent = put_in(agent.state.active_evaluations[selection_id].status, :completed)
    
    # Clean up active evaluation  
    agent = %{agent | state: %{agent.state | 
      strategy_status: :idle,
      active_evaluations: Map.delete(agent.state.active_evaluations, selection_id)
    }}
    
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "strategy_outcome_feedback"} = signal) do
    %{
      "data" => outcome_data
    } = signal
    
    feedback_id = signal["id"]
    
    Logger.info("Processing strategy outcome feedback for: #{outcome_data["strategy_id"]}")
    
    # Update agent status
    agent = %{agent | state: %{agent.state | strategy_status: :learning}}
    
    # Process learning feedback
    agent = process_learning_feedback(agent, outcome_data)
    
    # Update performance metrics
    agent = update_performance_metrics(agent, outcome_data)
    
    # Emit learning confirmation
    learning_signal = Jido.Signal.new!(%{
      type: "correction.strategy.learning.updated",
      source: "agent:#{agent.id}",
      data: %{
        feedback_id: feedback_id,
        strategy_id: outcome_data["strategy_id"],
        learning_applied: true,
        timestamp: DateTime.utc_now()
      }
    })
    
    emit_signal(agent, learning_signal)
    
    # Reset status
    agent = %{agent | state: %{agent.state | strategy_status: :idle}}
    
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "cost_estimation_request"} = signal) do
    %{
      "data" => %{
        "error_context" => error_context,
        "strategies" => strategies
      }
    } = signal
    
    estimation_id = signal["id"]
    
    Logger.info("Processing cost estimation request for #{length(strategies)} strategies")
    
    # Calculate cost estimates
    cost_estimates = calculate_cost_estimates(agent, error_context, strategies)
    
    # Emit cost estimation result
    cost_signal = Jido.Signal.new!(%{
      type: "correction.strategy.cost.estimation.result",
      source: "agent:#{agent.id}",
      data: %{
        estimation_id: estimation_id,
        cost_estimates: cost_estimates,
        timestamp: DateTime.utc_now()
      }
    })
    
    emit_signal(agent, cost_signal)
    
    {:ok, agent}
  end

  def handle_signal(agent, %{"type" => "performance_metrics_request"} = signal) do
    metrics_id = signal["id"]
    
    # Collect comprehensive performance metrics
    detailed_metrics = collect_performance_metrics(agent.state.performance_metrics)
    
    # Emit metrics report
    metrics_signal = Jido.Signal.new!(%{
      type: "correction.strategy.performance.metrics.report",
      source: "agent:#{agent.id}",
      data: %{
        metrics_id: metrics_id,
        metrics: detailed_metrics,
        collection_timestamp: DateTime.utc_now()
      }
    })
    
    emit_signal(agent, metrics_signal)
    
    {:ok, agent}
  end

  # Default signal handler
  def handle_signal(agent, signal) do
    Logger.warning("Unhandled signal type: #{signal["type"]}")
    {:ok, agent}
  end

  # Public API Functions

  @doc """
  Estimates costs for correction strategies given error context.
  """
  def estimate_costs(agent, error_context) do
    available_strategies = get_applicable_strategies(agent.state.strategy_library, error_context)
    
    cost_estimates = available_strategies
    |> Enum.map(fn {strategy_id, strategy} ->
      estimated_cost = calculate_strategy_cost(agent.state.cost_models, strategy, error_context)
      confidence = calculate_cost_confidence(agent.state.learning_data, strategy_id, error_context)
      time_estimate = estimate_execution_time(strategy, error_context)
      
      {strategy_id, %{
        "estimated_cost" => estimated_cost,
        "confidence" => confidence,
        "time_estimate" => time_estimate,
        "base_cost" => strategy.base_cost,
        "risk_multiplier" => get_risk_multiplier(strategy, error_context)
      }}
    end)
    |> Map.new()
    
    {:ok, cost_estimates}
  end

  # Private Implementation Functions

  defp select_strategies(agent, error_data, constraints) do
    # Get applicable strategies
    applicable_strategies = get_applicable_strategies(agent.state.strategy_library, error_data)
    
    # Calculate costs for each strategy
    cost_estimates = Enum.map(applicable_strategies, fn {strategy_id, strategy} ->
      cost = calculate_strategy_cost(agent.state.cost_models, strategy, error_data)
      {strategy_id, cost}
    end) |> Map.new()
    
    # Calculate confidence scores
    confidence_scores = Enum.map(applicable_strategies, fn {strategy_id, strategy} ->
      confidence = calculate_selection_confidence(agent.state.learning_data, strategy, error_data)
      {strategy_id, confidence}
    end) |> Map.new()
    
    # Rank strategies by composite score
    ranked_strategies = rank_strategies(applicable_strategies, cost_estimates, confidence_scores, constraints)
    
    # Select top recommendation
    recommendation = get_top_recommendation(ranked_strategies, constraints)
    
    %{
      strategies: ranked_strategies,
      cost_estimates: cost_estimates,
      confidence_scores: confidence_scores,
      recommendation: recommendation
    }
  end

  defp get_applicable_strategies(strategy_library, error_context) do
    strategy_library
    |> Enum.filter(fn {_id, strategy} ->
      matches_category?(strategy, error_context) and
      meets_constraints?(strategy, error_context)
    end)
  end

  defp matches_category?(strategy, error_context) do
    error_type = Map.get(error_context, "error_type", "unknown")
    strategy_category = strategy.category
    
    # Basic category matching - could be enhanced with more sophisticated logic
    String.contains?(error_type, strategy_category) or
    strategy_category == "general" or
    (error_type == "syntax_error" and strategy_category == "syntax")
  end

  defp meets_constraints?(strategy, error_context) do
    strategy.constraints
    |> Enum.all?(fn constraint ->
      evaluate_constraint(constraint, error_context)
    end)
  end

  defp evaluate_constraint(constraint, error_context) do
    # Simple constraint evaluation - could be enhanced with a proper constraint language
    case constraint do
      "file_size < 1000" ->
        Map.get(error_context, "file_size", 0) < 1000
      
      "complexity == low" ->
        Map.get(error_context, "complexity", "medium") == "low"
      
      "complexity <= high" ->
        complexity = Map.get(error_context, "complexity", "medium")
        complexity in ["low", "medium", "high"]
      
      _ ->
        true  # Unknown constraints default to true
    end
  end

  defp calculate_strategy_cost(cost_models, strategy, error_context) do
    base_cost = strategy.base_cost
    
    # Apply cost model multipliers
    time_cost = base_cost * cost_models["time_based"]["weight"]
    
    complexity_multiplier = get_complexity_multiplier(cost_models, error_context)
    complexity_cost = base_cost * cost_models["complexity_based"]["weight"] * complexity_multiplier
    
    risk_multiplier = get_risk_multiplier(strategy, error_context) 
    risk_cost = base_cost * cost_models["risk_based"]["weight"] * risk_multiplier
    
    time_cost + complexity_cost + risk_cost
  end

  defp get_complexity_multiplier(cost_models, error_context) do
    complexity = Map.get(error_context, "complexity", "medium")
    cost_models["complexity_based"]["multipliers"][complexity] || 1.0
  end

  defp get_risk_multiplier(strategy, _error_context) do
    strategy_risk = strategy.metadata["risk_level"] || "medium"
    
    case strategy_risk do
      "low" -> 1.0
      "medium" -> 1.3
      "high" -> 1.8
      _ -> 1.0
    end
  end

  defp calculate_selection_confidence(learning_data, strategy, error_context) do
    # Base confidence from strategy success rate
    base_confidence = strategy.success_rate
    
    # Adjust based on historical performance for similar contexts
    historical_adjustment = get_historical_adjustment(learning_data, strategy, error_context)
    
    # Ensure confidence stays within bounds
    min(1.0, max(0.0, base_confidence + historical_adjustment))
  end

  defp get_historical_adjustment(learning_data, strategy, _error_context) do
    # Simple historical adjustment - could be enhanced with ML techniques
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
      
      # Composite score: higher confidence, lower cost is better
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

  defp calculate_cost_estimates(agent, error_context, strategies) do
    strategies
    |> Enum.map(fn strategy_id ->
      strategy = agent.state.strategy_library[strategy_id]
      
      if strategy do
        cost = calculate_strategy_cost(agent.state.cost_models, strategy, error_context)
        confidence = calculate_cost_confidence(agent.state.learning_data, strategy_id, error_context)
        time_estimate = estimate_execution_time(strategy, error_context)
        
        {strategy_id, %{
          estimated_cost: cost,
          confidence: confidence,
          time_estimate: time_estimate
        }}
      else
        {strategy_id, %{
          estimated_cost: 0.0,
          confidence: 0.0,
          time_estimate: 0,
          error: "Strategy not found"
        }}
      end
    end)
    |> Map.new()
  end

  defp calculate_cost_confidence(learning_data, strategy_id, _error_context) do
    # Simple confidence calculation based on historical accuracy
    outcome_history = learning_data["outcome_history"] || []
    
    relevant_predictions = Enum.filter(outcome_history, fn outcome ->
      outcome["strategy_id"] == strategy_id
    end)
    
    if length(relevant_predictions) > 0 do
      accurate_predictions = Enum.count(relevant_predictions, fn outcome ->
        predicted_cost = outcome["predicted_cost"] || 0.0
        actual_cost = outcome["actual_cost"] || 0.0
        
        # Consider prediction accurate if within 20%
        abs(predicted_cost - actual_cost) / max(actual_cost, 0.01) <= 0.2
      end)
      
      accurate_predictions / length(relevant_predictions)
    else
      0.5  # Default confidence for new strategies
    end
  end

  defp estimate_execution_time(strategy, error_context) do
    base_time = strategy.metadata["avg_execution_time"] || 2000
    
    # Adjust based on complexity
    complexity_multiplier = case Map.get(error_context, "complexity", "medium") do
      "low" -> 0.8
      "medium" -> 1.0
      "high" -> 1.5
      _ -> 1.0
    end
    
    round(base_time * complexity_multiplier)
  end

  defp process_learning_feedback(agent, outcome_data) do
    # Update outcome history
    outcome_entry = %{
      "strategy_id" => outcome_data["strategy_id"],
      "success" => outcome_data["success"],
      "actual_cost" => outcome_data["actual_cost"],
      "execution_time" => outcome_data["execution_time"],
      "error_context" => outcome_data["error_context"],
      "timestamp" => DateTime.utc_now()
    }
    
    learning_data = agent.state.learning_data
    current_history = Map.get(learning_data, "outcome_history", [])
    updated_history = [outcome_entry | current_history]
    |> Enum.take(1000)  # Keep last 1000 outcomes
    
    updated_learning_data = Map.put(learning_data, "outcome_history", updated_history)
    
    %{agent | state: %{agent.state | learning_data: updated_learning_data}}
  end

  defp update_performance_metrics(agent, outcome_data) do
    strategy_id = outcome_data["strategy_id"]
    success = outcome_data["success"]
    
    current_metrics = agent.state.performance_metrics[strategy_id] || %{
      "success_count" => 0,
      "total_attempts" => 0,
      "avg_cost" => 0.0
    }
    
    new_success_count = current_metrics["success_count"] + (if success, do: 1, else: 0)
    new_total_attempts = current_metrics["total_attempts"] + 1
    
    # Update average cost with exponential moving average
    actual_cost = outcome_data["actual_cost"] || 0.0
    alpha = 0.1  # Learning rate
    new_avg_cost = current_metrics["avg_cost"] * (1 - alpha) + actual_cost * alpha
    
    updated_metrics = %{
      "success_count" => new_success_count,
      "total_attempts" => new_total_attempts,
      "avg_cost" => new_avg_cost
    }
    
    performance_metrics = Map.put(agent.state.performance_metrics, strategy_id, updated_metrics)
    
    %{agent | state: %{agent.state | performance_metrics: performance_metrics}}
  end

  defp update_selection_metrics(agent, _selection_id, _selection_result) do
    # Update overall selection metrics
    overall_metrics = agent.state.performance_metrics["overall"] || %{
      "total_selections" => 0,
      "successful_corrections" => 0,
      "avg_selection_time" => 0.0,
      "cost_prediction_accuracy" => 0.0
    }
    
    updated_overall = %{overall_metrics | 
      "total_selections" => overall_metrics["total_selections"] + 1
    }
    
    performance_metrics = Map.put(agent.state.performance_metrics, "overall", updated_overall)
    
    %{agent | state: %{agent.state | performance_metrics: performance_metrics}}
  end

  defp collect_performance_metrics(performance_metrics) do
    %{
      overall_metrics: performance_metrics["overall"] || %{},
      strategy_metrics: Map.delete(performance_metrics, "overall"),
      collection_timestamp: DateTime.utc_now()
    }
  end

  # Health check implementation
  @impl true
  def health_check(agent) do
    issues = []
    
    # Check agent status
    issues = if agent.state.strategy_status == :idle do
      issues
    else
      ["Agent not in idle state" | issues]
    end
    
    # Check strategy library
    issues = if map_size(agent.state.strategy_library) > 0 do
      issues
    else
      ["Empty strategy library" | issues]
    end
    
    # Check cost models
    issues = if map_size(agent.state.cost_models) > 0 do
      issues
    else
      ["Missing cost models" | issues]
    end
    
    if length(issues) == 0 do
      {:healthy, %{
        status: "All systems operational",
        strategy_count: map_size(agent.state.strategy_library),
        last_check: DateTime.utc_now()
      }}
    else
      {:unhealthy, %{issues: issues, last_check: DateTime.utc_now()}}
    end
  end
end