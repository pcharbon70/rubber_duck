defmodule RubberDuck.Jido.Actions.Correction.StrategyFeedbackAction do
  @moduledoc """
  Action for processing strategy outcome feedback to improve future selections.
  
  This action updates the learning system based on actual correction outcomes,
  allowing the agent to improve its strategy selection accuracy over time.
  """
  
  use Jido.Action,
    name: "strategy_feedback",
    description: "Process correction outcome feedback for learning",
    schema: [
      strategy_id: [
        type: :string,
        required: true,
        doc: "Identifier of the strategy that was executed"
      ],
      success: [
        type: :boolean,
        required: true,
        doc: "Whether the correction was successful"
      ],
      actual_cost: [
        type: :float,
        required: true,
        doc: "Actual cost incurred during correction"
      ],
      execution_time: [
        type: :integer,
        required: true,
        doc: "Actual execution time in milliseconds"
      ],
      error_context: [
        type: :map,
        required: true,
        doc: "Original error context for correlation"
      ],
      feedback_id: [
        type: :string,
        required: true,
        doc: "Unique identifier for this feedback"
      ],
      predicted_cost: [
        type: :float,
        default: nil,
        doc: "Originally predicted cost for accuracy tracking"
      ],
      user_satisfaction: [
        type: {:in, [:satisfied, :neutral, :dissatisfied]},
        default: :neutral,
        doc: "User satisfaction with the correction"
      ]
    ]
  
  require Logger
  
  @impl true
  def run(params, context) do
    agent = context.agent
    
    Logger.info("Processing strategy outcome feedback for: #{params.strategy_id}")
    
    # Create outcome entry
    outcome_entry = build_outcome_entry(params)
    
    # Update learning data
    updated_learning_data = update_learning_data(
      agent.state.learning_data,
      outcome_entry
    )
    
    # Update performance metrics
    updated_metrics = update_performance_metrics(
      agent.state.performance_metrics,
      params
    )
    
    # Calculate learning insights
    insights = calculate_learning_insights(
      updated_learning_data,
      params.strategy_id
    )
    
    result = %{
      feedback_id: params.feedback_id,
      strategy_id: params.strategy_id,
      learning_applied: true,
      outcome_recorded: true,
      insights: insights,
      metrics_updated: updated_metrics,
      timestamp: DateTime.utc_now()
    }
    
    # Return updated state components for agent to merge
    {:ok, result, %{
      learning_data: updated_learning_data,
      performance_metrics: updated_metrics
    }}
  rescue
    error ->
      Logger.error("Strategy feedback processing failed: #{inspect(error)}")
      {:error, %{reason: :feedback_processing_failed, details: Exception.message(error)}}
  end
  
  # Private helper functions
  
  defp build_outcome_entry(params) do
    %{
      "strategy_id" => params.strategy_id,
      "success" => params.success,
      "actual_cost" => params.actual_cost,
      "predicted_cost" => params.predicted_cost,
      "execution_time" => params.execution_time,
      "error_context" => params.error_context,
      "user_satisfaction" => to_string(params.user_satisfaction),
      "timestamp" => DateTime.utc_now()
    }
  end
  
  defp update_learning_data(learning_data, outcome_entry) do
    current_history = Map.get(learning_data, "outcome_history", [])
    
    # Add new entry and keep last 1000 outcomes
    updated_history = [outcome_entry | current_history]
    |> Enum.take(1000)
    
    # Update pattern weights based on outcome
    updated_weights = update_pattern_weights(
      learning_data["pattern_weights"] || %{},
      outcome_entry,
      learning_data["adaptation_rate"] || 0.1
    )
    
    learning_data
    |> Map.put("outcome_history", updated_history)
    |> Map.put("pattern_weights", updated_weights)
  end
  
  defp update_pattern_weights(pattern_weights, outcome_entry, adaptation_rate) do
    strategy_id = outcome_entry["strategy_id"]
    success = outcome_entry["success"]
    
    # Get current weight or initialize
    current_weight = Map.get(pattern_weights, strategy_id, 0.5)
    
    # Apply simple reinforcement learning update
    adjustment = if success do
      adaptation_rate * (1.0 - current_weight)
    else
      -adaptation_rate * current_weight
    end
    
    new_weight = min(1.0, max(0.0, current_weight + adjustment))
    
    Map.put(pattern_weights, strategy_id, new_weight)
  end
  
  defp update_performance_metrics(performance_metrics, params) do
    strategy_id = params.strategy_id
    
    current_metrics = performance_metrics[strategy_id] || %{
      "success_count" => 0,
      "total_attempts" => 0,
      "avg_cost" => 0.0,
      "avg_execution_time" => 0.0,
      "satisfaction_scores" => %{
        "satisfied" => 0,
        "neutral" => 0,
        "dissatisfied" => 0
      }
    }
    
    # Update counts
    new_success_count = current_metrics["success_count"] + (if params.success, do: 1, else: 0)
    new_total_attempts = current_metrics["total_attempts"] + 1
    
    # Update averages with exponential moving average
    alpha = 0.1
    new_avg_cost = current_metrics["avg_cost"] * (1 - alpha) + params.actual_cost * alpha
    new_avg_time = current_metrics["avg_execution_time"] * (1 - alpha) + params.execution_time * alpha
    
    # Update satisfaction scores
    satisfaction_scores = current_metrics["satisfaction_scores"]
    satisfaction_key = to_string(params.user_satisfaction)
    updated_satisfaction = Map.update(satisfaction_scores, satisfaction_key, 1, &(&1 + 1))
    
    updated_metrics = %{
      "success_count" => new_success_count,
      "total_attempts" => new_total_attempts,
      "success_rate" => new_success_count / new_total_attempts,
      "avg_cost" => new_avg_cost,
      "avg_execution_time" => new_avg_time,
      "satisfaction_scores" => updated_satisfaction
    }
    
    # Update overall metrics
    overall_metrics = update_overall_metrics(performance_metrics["overall"] || %{}, params)
    
    performance_metrics
    |> Map.put(strategy_id, updated_metrics)
    |> Map.put("overall", overall_metrics)
  end
  
  defp update_overall_metrics(overall_metrics, params) do
    current_successful = overall_metrics["successful_corrections"] || 0
    current_total = overall_metrics["total_corrections"] || 0
    
    new_successful = current_successful + (if params.success, do: 1, else: 0)
    new_total = current_total + 1
    
    # Update cost prediction accuracy if we have a predicted cost
    accuracy_update = if params.predicted_cost do
      current_accuracy = overall_metrics["cost_prediction_accuracy"] || 0.5
      error_margin = abs(params.predicted_cost - params.actual_cost) / max(params.actual_cost, 0.01)
      is_accurate = error_margin <= 0.2
      
      # Exponential moving average for accuracy
      alpha = 0.05
      current_accuracy * (1 - alpha) + (if is_accurate, do: 1.0, else: 0.0) * alpha
    else
      overall_metrics["cost_prediction_accuracy"] || 0.5
    end
    
    %{
      "successful_corrections" => new_successful,
      "total_corrections" => new_total,
      "overall_success_rate" => new_successful / new_total,
      "cost_prediction_accuracy" => accuracy_update,
      "last_feedback_time" => DateTime.utc_now()
    }
  end
  
  defp calculate_learning_insights(learning_data, strategy_id) do
    outcome_history = learning_data["outcome_history"] || []
    pattern_weights = learning_data["pattern_weights"] || %{}
    
    # Get recent outcomes for this strategy
    recent_outcomes = outcome_history
    |> Enum.filter(& &1["strategy_id"] == strategy_id)
    |> Enum.take(10)
    
    if length(recent_outcomes) > 0 do
      recent_success_rate = Enum.count(recent_outcomes, & &1["success"]) / length(recent_outcomes)
      avg_recent_cost = Enum.sum(Enum.map(recent_outcomes, & &1["actual_cost"])) / length(recent_outcomes)
      
      %{
        recent_success_rate: recent_success_rate,
        avg_recent_cost: avg_recent_cost,
        current_weight: Map.get(pattern_weights, strategy_id, 0.5),
        trend: determine_trend(recent_outcomes),
        confidence_level: calculate_confidence_level(length(recent_outcomes))
      }
    else
      %{
        recent_success_rate: nil,
        avg_recent_cost: nil,
        current_weight: Map.get(pattern_weights, strategy_id, 0.5),
        trend: :insufficient_data,
        confidence_level: :low
      }
    end
  end
  
  defp determine_trend(recent_outcomes) do
    # Simple trend analysis based on recent success pattern
    recent_successes = recent_outcomes
    |> Enum.take(5)
    |> Enum.map(& &1["success"])
    
    older_successes = recent_outcomes
    |> Enum.drop(5)
    |> Enum.take(5)
    |> Enum.map(& &1["success"])
    
    if length(older_successes) > 0 do
      recent_rate = Enum.count(recent_successes, & &1) / length(recent_successes)
      older_rate = Enum.count(older_successes, & &1) / length(older_successes)
      
      cond do
        recent_rate > older_rate + 0.1 -> :improving
        recent_rate < older_rate - 0.1 -> :declining
        true -> :stable
      end
    else
      :insufficient_data
    end
  end
  
  defp calculate_confidence_level(sample_size) do
    cond do
      sample_size >= 20 -> :high
      sample_size >= 10 -> :medium
      sample_size >= 5 -> :low
      true -> :very_low
    end
  end
end