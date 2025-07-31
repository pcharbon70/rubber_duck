defmodule RubberDuck.Jido.Actions.Conversation.Planning.GetPlanningMetricsAction do
  @moduledoc """
  Action for retrieving planning metrics from the Planning Conversation Agent.
  
  This action collects and returns comprehensive planning metrics including:
  - Plan creation and completion statistics
  - Validation and improvement metrics
  - Performance timing data
  - Active conversation counts
  """
  
  use Jido.Action,
    name: "get_planning_metrics",
    description: "Retrieves comprehensive planning metrics and statistics",
    schema: [
      include_conversations: [type: :boolean, default: false, doc: "Whether to include active conversation details"],
      include_config: [type: :boolean, default: true, doc: "Whether to include configuration information"]
    ]

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction

  @impl true
  def run(params, context) do
    agent = context.agent
    
    # Build comprehensive metrics
    metrics_data = Map.merge(agent.state.metrics, %{
      # Active conversation details (if requested)
      active_conversations: if(params.include_conversations, do: agent.state.active_conversations, else: nil),
      
      # Configuration (if requested)
      config: if(params.include_config, do: agent.state.config, else: nil),
      
      # Validation cache info
      validation_cache_size: map_size(agent.state.validation_cache),
      
      # Agent status
      conversation_state: agent.state.conversation_state,
      
      timestamp: DateTime.utc_now()
    })
    
    # Emit metrics signal
    with {:ok, _} <- emit_metrics_signal(agent, metrics_data) do
      {:ok, %{
        metrics_collected: true,
        total_plans_created: agent.state.metrics.total_plans_created,
        active_conversations: agent.state.metrics.active_conversations
      }, %{agent: agent}}
    end
  end

  # Private functions

  defp emit_metrics_signal(agent, metrics_data) do
    signal_params = %{
      signal_type: "conversation.planning.metrics",
      data: Map.merge(metrics_data, %{
        agent_type: "planning_conversation",
        collection_time: DateTime.utc_now()
      })
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end