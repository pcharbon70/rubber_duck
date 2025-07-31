defmodule RubberDuck.Jido.Actions.Conversation.Enhancement.GetEnhancementMetricsAction do
  @moduledoc """
  Action for retrieving enhancement metrics from the Enhancement Conversation Agent.
  
  This action collects and returns comprehensive enhancement metrics including:
  - Enhancement counts and success rates
  - Technique effectiveness statistics
  - Suggestion acceptance rates
  - Active enhancement information
  - Cache and history statistics
  """
  
  use Jido.Action,
    name: "get_enhancement_metrics",
    description: "Retrieves comprehensive enhancement metrics and statistics",
    schema: [
      include_history: [type: :boolean, default: false, doc: "Whether to include enhancement history details"],
      include_config: [type: :boolean, default: true, doc: "Whether to include configuration information"],
      include_cache: [type: :boolean, default: false, doc: "Whether to include cache details"]
    ]

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction

  @impl true
  def run(params, context) do
    agent = context.agent
    
    # Build comprehensive metrics
    metrics_data = %{
      # Core metrics from agent state
      metrics: agent.state.metrics,
      
      # Current activity
      active_enhancements: map_size(agent.state.active_enhancements),
      queue_size: length(agent.state.enhancement_queue),
      
      # History details (if requested)
      enhancement_history: if(params.include_history, do: agent.state.enhancement_history, else: nil),
      history_size: length(agent.state.enhancement_history),
      
      # Cache information (if requested)
      suggestion_cache: if(params.include_cache, do: agent.state.suggestion_cache, else: nil),
      cache_size: map_size(agent.state.suggestion_cache),
      validation_results_count: map_size(agent.state.validation_results),
      
      # Configuration (if requested)
      config: if(params.include_config, do: agent.state.enhancement_config, else: nil),
      
      timestamp: DateTime.utc_now()
    }
    
    # Emit metrics signal
    with {:ok, _} <- emit_metrics_signal(agent, metrics_data) do
      {:ok, %{
        metrics_collected: true,
        total_enhancements: agent.state.metrics.total_enhancements,
        active_enhancements: map_size(agent.state.active_enhancements),
        suggestion_acceptance_rate: calculate_acceptance_rate(agent.state.metrics)
      }, %{agent: agent}}
    end
  end

  # Private functions

  defp calculate_acceptance_rate(metrics) do
    if metrics.suggestions_generated > 0 do
      metrics.suggestions_accepted / metrics.suggestions_generated
    else
      0.0
    end
  end

  defp emit_metrics_signal(agent, metrics_data) do
    signal_params = %{
      signal_type: "conversation.enhancement.metrics",
      data: Map.merge(metrics_data, %{
        agent_type: "enhancement_conversation",
        collection_time: DateTime.utc_now()
      })
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end