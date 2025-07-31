defmodule RubberDuck.Jido.Actions.Conversation.Enhancement.FeedbackReceivedAction do
  @moduledoc """
  Action for handling user feedback on enhancement suggestions.
  
  This action processes user feedback by:
  - Recording suggestion acceptance/rejection
  - Updating technique effectiveness metrics
  - Learning from user preferences
  - Storing feedback history for analysis
  """
  
  use Jido.Action,
    name: "feedback_received",
    description: "Handles user feedback on enhancement suggestions for learning and metrics",
    schema: [
      request_id: [type: :string, required: true, doc: "Enhancement request identifier"],
      suggestion_id: [type: :string, required: true, doc: "Suggestion identifier"],
      feedback: [type: :map, required: true, doc: "User feedback data"],
      accepted: [type: :boolean, required: true, doc: "Whether suggestion was accepted"]
    ]

  require Logger
  
  alias RubberDuck.Jido.Actions.Base.UpdateStateAction

  @impl true
  def run(params, context) do
    agent = context.agent
    
    # Update metrics based on feedback
    with {:ok, metrics_agent} <- update_suggestion_metrics(agent, params),
         {:ok, effectiveness_agent} <- update_technique_effectiveness(metrics_agent, params),
         {:ok, final_agent} <- store_feedback_history(effectiveness_agent, params) do
      
      Logger.info("Enhancement feedback received",
        request_id: params.request_id,
        accepted: params.accepted
      )
      
      {:ok, %{
        feedback_processed: true,
        request_id: params.request_id,
        suggestion_id: params.suggestion_id,
        accepted: params.accepted
      }, %{agent: final_agent}}
    end
  end

  # Private functions

  defp update_suggestion_metrics(agent, params) do
    updated_metrics = %{agent.state.metrics |
      suggestions_generated: agent.state.metrics.suggestions_generated + 1,
      suggestions_accepted: if(params.accepted, 
        do: agent.state.metrics.suggestions_accepted + 1, 
        else: agent.state.metrics.suggestions_accepted
      )
    }
    
    # Update running average
    total = updated_metrics.suggestions_generated
    score = if params.accepted, do: 1.0, else: 0.0
    avg_improvement = if total > 1 do
      (agent.state.metrics.avg_improvement_score * (total - 1) + score) / total
    else
      score
    end
    
    final_metrics = %{updated_metrics | avg_improvement_score: avg_improvement}
    
    state_updates = %{metrics: final_metrics}
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} -> {:ok, updated_agent}
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_technique_effectiveness(agent, params) do
    # Find the technique used for this suggestion (simplified - would need proper tracking)
    technique = :unknown
    
    effectiveness_delta = case params.feedback["rating"] do
      rating when is_number(rating) -> rating / 5.0
      "positive" -> 0.1
      "negative" -> -0.1
      _ -> 0.0
    end
    
    current_effectiveness = get_in(agent.state.metrics.technique_effectiveness, [technique]) || 0.5
    
    # Exponential moving average
    alpha = 0.1
    new_effectiveness = current_effectiveness * (1 - alpha) + effectiveness_delta * alpha
    
    updated_technique_effectiveness = Map.put(
      agent.state.metrics.technique_effectiveness,
      technique,
      new_effectiveness
    )
    
    updated_metrics = %{agent.state.metrics | 
      technique_effectiveness: updated_technique_effectiveness
    }
    
    state_updates = %{metrics: updated_metrics}
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} -> {:ok, updated_agent}
      {:error, reason} -> {:error, reason}
    end
  end

  defp store_feedback_history(agent, params) do
    feedback_entry = %{
      request_id: params.request_id,
      suggestion_id: params.suggestion_id,
      feedback: params.feedback,
      accepted: params.accepted,
      timestamp: DateTime.utc_now()
    }
    
    updated_history = [feedback_entry | agent.state.enhancement_history]
    
    state_updates = %{enhancement_history: updated_history}
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} -> {:ok, updated_agent}
      {:error, reason} -> {:error, reason}
    end
  end
end