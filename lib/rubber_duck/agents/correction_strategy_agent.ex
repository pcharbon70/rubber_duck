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
    ],
    actions: [
      RubberDuck.Jido.Actions.Correction.StrategySelectionAction,
      RubberDuck.Jido.Actions.Correction.StrategyFeedbackAction,
      RubberDuck.Jido.Actions.Correction.CostEstimationAction,
      RubberDuck.Jido.Actions.Correction.PerformanceMetricsAction
    ]

  require Logger

  # Signal-to-Action Mappings
  # This replaces all handle_signal callbacks with Jido action routing
  
  @impl true
  def signal_mappings do
    %{
      "strategy_selection_request" => {RubberDuck.Jido.Actions.Correction.StrategySelectionAction, &extract_selection_params/1},
      "strategy_outcome_feedback" => {RubberDuck.Jido.Actions.Correction.StrategyFeedbackAction, &extract_feedback_params/1},
      "cost_estimation_request" => {RubberDuck.Jido.Actions.Correction.CostEstimationAction, &extract_estimation_params/1},
      "performance_metrics_request" => {RubberDuck.Jido.Actions.Correction.PerformanceMetricsAction, &extract_metrics_params/1}
    }
  end
  
  # Parameter extraction functions for signal-to-action mapping
  
  defp extract_selection_params(%{"data" => data, "id" => id}) do
    %{
      error_data: data["error_data"],
      constraints: data["constraints"] || %{},
      selection_id: id,
      include_alternatives: Map.get(data, "include_alternatives", true),
      max_strategies: Map.get(data, "max_strategies", 5)
    }
  end
  
  defp extract_feedback_params(%{"data" => data, "id" => id}) do
    %{
      strategy_id: data["strategy_id"],
      success: data["success"],
      actual_cost: data["actual_cost"],
      execution_time: data["execution_time"],
      error_context: data["error_context"],
      feedback_id: id,
      predicted_cost: Map.get(data, "predicted_cost"),
      user_satisfaction: parse_satisfaction(Map.get(data, "user_satisfaction", "neutral"))
    }
  end
  
  defp extract_estimation_params(%{"data" => data, "id" => id}) do
    %{
      error_context: data["error_context"],
      strategies: data["strategies"],
      estimation_id: id,
      include_breakdown: Map.get(data, "include_breakdown", true),
      include_roi: Map.get(data, "include_roi", true),
      confidence_threshold: Map.get(data, "confidence_threshold", 0.7)
    }
  end
  
  defp extract_metrics_params(%{"data" => data, "id" => id}) do
    data = data || %{}
    %{
      metrics_id: id,
      time_range: parse_time_range(Map.get(data, "time_range", "all_time")),
      include_strategies: Map.get(data, "include_strategies", []),
      include_trends: Map.get(data, "include_trends", true),
      include_predictions: Map.get(data, "include_predictions", true),
      group_by: parse_group_by(Map.get(data, "group_by", "strategy"))
    }
  end
  
  # Parsing helper functions
  
  defp parse_satisfaction("satisfied"), do: :satisfied
  defp parse_satisfaction("dissatisfied"), do: :dissatisfied
  defp parse_satisfaction(_), do: :neutral
  
  defp parse_time_range("last_24_hours"), do: :last_24_hours
  defp parse_time_range("last_7_days"), do: :last_7_days
  defp parse_time_range("last_30_days"), do: :last_30_days
  defp parse_time_range(_), do: :all_time
  
  defp parse_group_by("error_type"), do: :error_type
  defp parse_group_by("complexity"), do: :complexity
  defp parse_group_by("time_period"), do: :time_period
  defp parse_group_by(_), do: :strategy
  
  # Lifecycle hooks for Jido compliance
  
  @impl true
  def on_before_init(config) do
    # Initialize strategy library if not provided
    library = Map.get(config, :strategy_library) || default_strategy_library()
    Map.put(config, :strategy_library, library)
  end
  
  @impl true
  def on_after_start(agent) do
    Logger.info("Correction Strategy Agent started successfully",
      name: agent.name,
      strategies: map_size(agent.state.strategy_library)
    )
    agent
  end
  
  @impl true
  def on_after_run(agent, action, result) do
    # Update agent state based on action results
    case action do
      RubberDuck.Jido.Actions.Correction.StrategyFeedbackAction ->
        # Merge updated state from feedback action
        case result do
          {:ok, _result, state_updates} ->
            new_state = Map.merge(agent.state, state_updates)
            {:ok, %{agent | state: new_state}}
          _ ->
            {:ok, agent}
        end
      _ ->
        {:ok, agent}
    end
  end
  
  defp default_strategy_library do
    %{
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
          "risk_level" => "low",
          "reversible" => true,
          "modifies_code" => true
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
          "risk_level" => "medium",
          "reversible" => false,
          "modifies_code" => true,
          "uses_llm" => true
        }
      }
    }
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
  # Note: Most logic has been moved to Actions for better testability and reusability

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