defmodule RubberDuck.Agents.PlanningConversationAgent do
  @moduledoc """
  Autonomous agent that handles planning conversations through Jido Actions pattern.
  
  This agent:
  - Creates plans from natural language queries
  - Validates plans using the Critics system
  - Manages conversation state for multi-step planning
  - Emits signals for real-time UI updates
  - Supports plan improvement and fixing flows
  
  ## Actions
  
  The agent uses the following actions to handle different signal types:
  - `PlanCreationRequestAction`: Initiates plan creation from natural language
  - `ValidatePlanRequestAction`: Starts plan validation with Critics system
  - `GetPlanningMetricsAction`: Returns planning metrics and statistics
  
  ## Output Signals
  - `conversation.plan.creation_started`: Plan creation has begun
  - `conversation.plan.creation_completed`: Plan creation completed successfully
  - `conversation.plan.creation_error`: Plan creation failed
  - `conversation.plan.validation_result`: Plan validation results
  - `conversation.planning.metrics`: Planning metrics and statistics
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "planning_conversation",
    description: "Handles plan creation and validation conversations using Jido Actions",
    schema: [
      # Conversation state tracking
      conversation_state: [
        type: :atom,
        default: :idle,
        values: [:idle, :active, :processing]
      ],
      
      # Active conversations map
      active_conversations: [
        type: :map,
        default: %{}
      ],
      
      # Plan creation configuration
      config: [
        type: :map,
        default: %{
          max_tokens: 3000,
          temperature: 0.7,
          timeout: 60_000,
          auto_improve: true,
          auto_fix: true
        }
      ],
      
      # Metrics
      metrics: [
        type: :map,
        default: %{
          total_plans_created: 0,
          active_conversations: 0,
          completed_conversations: 0,
          failed_conversations: 0,
          validation_times: [],
          creation_times: [],
          improvement_count: 0,
          fix_count: 0
        }
      ],
      
      # Validation results cache
      validation_cache: [type: :map, default: %{}]
    ],
    actions: [
      RubberDuck.Jido.Actions.Conversation.Planning.PlanCreationRequestAction,
      RubberDuck.Jido.Actions.Conversation.Planning.ValidatePlanRequestAction,
      RubberDuck.Jido.Actions.Conversation.Planning.GetPlanningMetricsAction
    ]

  require Logger

  # The agent now uses Jido Actions instead of handle_signal callbacks.
  # Signal handling is automatically routed to appropriate actions based on signal type.
  # 
  # Signal type to action mapping:
  # - "plan_creation_request" -> PlanCreationRequestAction
  # - "validate_plan_request" -> ValidatePlanRequestAction
  # - "get_planning_metrics" -> GetPlanningMetricsAction
  #
  # Additional signal handlers for internal workflow coordination:
  # - "improve_plan_request": Triggers plan improvement flow
  # - "complete_conversation": Finalizes conversation and updates metrics
  # - "plan_created": Internal signal when plan creation completes
  # - "plan_validation_complete": Internal signal when validation finishes
  #
  # All business logic has been moved to the respective action modules
  # in lib/rubber_duck/jido/actions/conversation/planning/
end