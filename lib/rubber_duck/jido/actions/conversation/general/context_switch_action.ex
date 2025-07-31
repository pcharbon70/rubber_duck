defmodule RubberDuck.Jido.Actions.Conversation.General.ContextSwitchAction do
  @moduledoc """
  Action for handling conversation context switches.
  
  This action manages context switching by:
  - Preserving conversation history when requested
  - Updating conversation context
  - Managing context stack
  - Emitting context switch notifications
  """
  
  use Jido.Action,
    name: "context_switch",
    description: "Handles conversation context switching with history preservation",
    schema: [
      conversation_id: [type: :string, required: true, doc: "Conversation identifier"],
      new_context: [type: :map, required: true, doc: "New context to switch to"],
      preserve_history: [type: :boolean, default: true, doc: "Whether to preserve current context in stack"]
    ]

  require Logger
  
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}

  @impl true
  def run(params, context) do
    agent = context.agent
    
    case agent.state.active_conversations[params.conversation_id] do
      nil ->
        Logger.warning("Context switch requested for non-existent conversation: #{params.conversation_id}")
        {:ok, %{switched: false, reason: "conversation_not_found"}, %{agent: agent}}
      
      conversation ->
        with {:ok, updated_agent} <- update_context_stack(agent, conversation, params.preserve_history),
             {:ok, final_agent} <- update_conversation_context(updated_agent, params),
             {:ok, metrics_agent} <- update_switch_metrics(final_agent),
             {:ok, _} <- emit_context_switch_signal(metrics_agent, conversation, params) do
          {:ok, %{switched: true, conversation_id: params.conversation_id}, %{agent: metrics_agent}}
        end
    end
  end

  # Private functions

  defp update_context_stack(agent, conversation, preserve_history) do
    if preserve_history do
      new_stack = [conversation.context | Enum.take(agent.state.context_stack, 9)]
      state_updates = %{context_stack: new_stack}
      
      case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
        {:ok, _, %{agent: updated_agent}} -> {:ok, updated_agent}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, agent}
    end
  end

  defp update_conversation_context(agent, params) do
    conversation = agent.state.active_conversations[params.conversation_id]
    
    updated_conversation = %{conversation |
      context: params.new_context,
      context_switched_at: System.monotonic_time(:millisecond)
    }
    
    state_updates = %{
      active_conversations: Map.put(agent.state.active_conversations, params.conversation_id, updated_conversation)
    }
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} -> {:ok, updated_agent}
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_switch_metrics(agent) do
    state_updates = %{
      metrics: update_in(agent.state.metrics.context_switches, &(&1 + 1))
    }
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} -> {:ok, updated_agent}
      {:error, reason} -> {:error, reason}
    end
  end

  defp emit_context_switch_signal(agent, original_conversation, params) do
    signal_params = %{
      signal_type: "conversation.context.switch",
      data: %{
        conversation_id: params.conversation_id,
        previous_context: original_conversation.context,
        new_context: params.new_context,
        preserved_history: params.preserve_history,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end