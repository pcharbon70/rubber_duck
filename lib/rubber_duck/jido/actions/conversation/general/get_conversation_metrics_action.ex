defmodule RubberDuck.Jido.Actions.Conversation.General.GetConversationMetricsAction do
  @moduledoc """
  Action for retrieving conversation metrics from the General Conversation Agent.
  
  This action collects and returns comprehensive metrics including:
  - Basic conversation metrics (total, active, completed)
  - Performance metrics (response times, context switches)
  - Current agent state information
  - Configuration details
  """
  
  use Jido.Action,
    name: "get_conversation_metrics",
    description: "Retrieves comprehensive conversation metrics and statistics",
    schema: [
      include_history: [type: :boolean, default: false, doc: "Whether to include conversation history details"],
      include_config: [type: :boolean, default: true, doc: "Whether to include configuration information"]
    ]

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction

  @impl true
  def run(params, context) do
    agent = context.agent
    
    # Calculate additional runtime metrics
    active_count = map_size(agent.state.active_conversations)
    total_messages = calculate_total_messages(agent.state.active_conversations)
    
    # Build comprehensive metrics
    metrics_data = %{
      # Core metrics from agent state
      metrics: agent.state.metrics,
      
      # Runtime calculations
      active_conversations: active_count,
      total_messages: total_messages,
      history_size: length(agent.state.conversation_history),
      context_stack_depth: length(agent.state.context_stack),
      
      # Configuration (if requested)
      config: if(params.include_config, do: agent.state.conversation_config, else: nil),
      
      # History details (if requested)
      conversation_history: if(params.include_history, do: agent.state.conversation_history, else: nil),
      
      # Agent status
      agent_status: %{
        id: agent.id,
        uptime_ms: calculate_uptime(agent),
        memory_usage: calculate_memory_usage(agent)
      },
      
      timestamp: DateTime.utc_now()
    }
    
    # Emit metrics signal
    with {:ok, _} <- emit_metrics_signal(agent, metrics_data) do
      {:ok, %{
        metrics_collected: true,
        active_conversations: active_count,
        total_messages: total_messages
      }, %{agent: agent}}
    end
  end

  # Private functions

  defp calculate_total_messages(active_conversations) do
    Enum.reduce(active_conversations, 0, fn {_id, conv}, acc ->
      acc + length(conv[:messages] || [])
    end)
  end

  defp calculate_uptime(_agent) do
    # This would ideally track agent start time
    # For now, using a placeholder calculation
    case Process.info(self(), :dictionary) do
      {:dictionary, dict} ->
        case Keyword.get(dict, :start_time) do
          nil -> 0
          start_time -> System.monotonic_time(:millisecond) - start_time
        end
      _ -> 0
    end
  end

  defp calculate_memory_usage(_agent) do
    # Get current process memory usage
    case Process.info(self(), :memory) do
      {:memory, memory} -> memory
      _ -> 0
    end
  end

  defp emit_metrics_signal(agent, metrics_data) do
    signal_params = %{
      signal_type: "conversation.metrics",
      data: Map.merge(metrics_data, %{
        agent_type: "general_conversation",
        collection_time: DateTime.utc_now()
      })
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end