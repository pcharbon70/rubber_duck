defmodule RubberDuck.Agents.EnhancementConversationAgent do
  @moduledoc """
  Autonomous agent for handling enhancement conversations using Jido Actions pattern.
  
  This agent manages code and content enhancement requests through
  asynchronous signal-based communication. It coordinates with the
  existing enhancement system to apply techniques like CoT, RAG,
  and self-correction.
  
  ## Actions
  
  The agent uses the following actions to handle different signal types:
  - `EnhancementRequestAction`: Processes content enhancement requests
  - `FeedbackReceivedAction`: Handles user feedback on suggestions
  - `GetEnhancementMetricsAction`: Returns enhancement metrics and statistics
  
  ## Output Signals
  - `conversation.enhancement.result`: Final enhanced content with suggestions
  - `conversation.enhancement.progress`: Progress updates during enhancement
  - `conversation.enhancement.suggestion_generated`: Individual enhancement suggestions
  - `conversation.enhancement.technique_selection`: Selected enhancement techniques
  - `conversation.enhancement.validation_request`: Request validation of enhancements
  - `conversation.enhancement.metrics`: Current metrics data
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "enhancement_conversation",
    description: "Handles code and content enhancement conversations with technique coordination using Jido Actions",
    category: "conversation",
    schema: [
      enhancement_queue: [type: {:list, :map}, default: []],
      active_enhancements: [type: :map, default: %{}],
      enhancement_history: [type: {:list, :map}, default: []],
      suggestion_cache: [type: :map, default: %{}],
      validation_results: [type: :map, default: %{}],
      metrics: [type: :map, default: %{
        total_enhancements: 0,
        suggestions_generated: 0,
        suggestions_accepted: 0,
        avg_improvement_score: 0.0,
        technique_effectiveness: %{}
      }],
      enhancement_config: [type: :map, default: %{
        default_techniques: [:cot, :self_correction],
        max_suggestions: 5,
        validation_enabled: true,
        ab_testing_enabled: false
      }]
    ],
    actions: [
      RubberDuck.Jido.Actions.Conversation.Enhancement.EnhancementRequestAction,
      RubberDuck.Jido.Actions.Conversation.Enhancement.FeedbackReceivedAction,
      RubberDuck.Jido.Actions.Conversation.Enhancement.GetEnhancementMetricsAction
    ]

  require Logger

  # The agent now uses Jido Actions instead of handle_signal callbacks.
  # Signal handling is automatically routed to appropriate actions based on signal type.
  # 
  # Signal type to action mapping:
  # - "enhancement_request" -> EnhancementRequestAction
  # - "feedback_received" -> FeedbackReceivedAction
  # - "get_enhancement_metrics" -> GetEnhancementMetricsAction
  #
  # Additional signal handlers for workflow coordination:
  # - "validation_response": Processes validation results from external validators
  #
  # All business logic has been moved to the respective action modules
  # in lib/rubber_duck/jido/actions/conversation/enhancement/
end