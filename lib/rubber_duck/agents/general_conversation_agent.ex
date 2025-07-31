defmodule RubberDuck.Agents.GeneralConversationAgent do
  @moduledoc """
  Autonomous agent for handling general conversations using Jido Actions pattern.
  
  This agent provides flexible conversation handling for queries that don't
  fit into specific categories. It manages conversation context, handles
  topic changes, and can hand off to specialized agents when needed.
  
  ## Actions
  
  The agent uses the following actions to handle different signal types:
  - `ConversationRequestAction`: Handles general conversation requests
  - `ContextSwitchAction`: Manages conversation context switching
  - `ClarificationResponseAction`: Processes user clarification responses
  - `GetConversationMetricsAction`: Returns current metrics and statistics
  
  ## Output Signals
  - `conversation.result`: Response to conversation
  - `conversation.clarification.request`: Request for clarification
  - `conversation.topic.change`: Notification of topic change
  - `conversation.context.switch`: Context has been switched
  - `conversation.handoff.request`: Request to hand off to specialized agent
  - `conversation.metrics`: Current metrics data
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "general_conversation",
    description: "Handles general conversations with flexible context management using Jido Actions",
    category: "conversation",
    schema: [
      active_conversations: [type: :map, default: %{}],
      conversation_history: [type: {:list, :map}, default: []],
      context_stack: [type: {:list, :map}, default: []],
      current_context: [type: :map, default: %{}],
      response_strategies: [type: :map, default: %{
        simple: true,
        detailed: false,
        technical: false,
        casual: true
      }],
      metrics: [type: :map, default: %{
        total_conversations: 0,
        context_switches: 0,
        clarifications_requested: 0,
        handoffs: 0,
        avg_response_time_ms: 0
      }],
      conversation_config: [type: :map, default: %{
        max_history_length: 100,
        context_timeout_ms: 300_000,  # 5 minutes
        enable_learning: true,
        enable_personalization: false
      }]
    ],
    actions: [
      RubberDuck.Jido.Actions.Conversation.General.ConversationRequestAction,
      RubberDuck.Jido.Actions.Conversation.General.ContextSwitchAction,
      RubberDuck.Jido.Actions.Conversation.General.ClarificationResponseAction,
      RubberDuck.Jido.Actions.Conversation.General.GetConversationMetricsAction
    ]

  require Logger

  # The agent now uses Jido Actions instead of handle_signal callbacks.
  # Signal handling is automatically routed to appropriate actions based on signal type.
  # 
  # Signal type to action mapping:
  # - "conversation_request" -> ConversationRequestAction
  # - "context_switch" -> ContextSwitchAction  
  # - "clarification_response" -> ClarificationResponseAction
  # - "get_conversation_metrics" -> GetConversationMetricsAction
  #
  # All business logic has been moved to the respective action modules
  # in lib/rubber_duck/jido/actions/conversation/general/
end