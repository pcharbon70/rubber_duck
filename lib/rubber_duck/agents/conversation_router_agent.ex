defmodule RubberDuck.Agents.ConversationRouterAgent do
  @moduledoc """
  Autonomous agent that routes incoming conversations to appropriate engines using Jido Actions pattern.
  
  This agent:
  - Classifies incoming queries using QuestionClassifier
  - Routes conversations based on intent and complexity
  - Maintains routing metrics and circuit breakers
  - Emits routing decisions as signals
  - Supports dynamic routing rules
  
  ## Actions
  
  The agent uses the following actions to handle different signal types:
  - `ConversationRouteRequestAction`: Routes conversations to appropriate engines
  - `UpdateRoutingRulesAction`: Updates routing rules dynamically
  - `GetRoutingMetricsAction`: Returns routing metrics and statistics
  
  ## Output Signals
  - `conversation.route.response`: Routing decision with classification
  - `conversation.route.error`: Routing errors and failures
  - `conversation.routing.metrics`: Routing metrics and statistics
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "conversation_router",
    description: "Routes conversations to appropriate engines based on intent and complexity using Jido Actions",
    schema: [
      # Routing configuration
      routing_table: [
        type: :map,
        default: %{
          simple: "simple_conversation",
          complex: "complex_conversation",
          analysis: "analysis_conversation",
          generation: "generation_conversation",
          problem_solver: "problem_solver",
          multi_step: "multi_step_conversation",
          planning: "planning_conversation"
        }
      ],
      
      # Routing rules - can be updated dynamically
      routing_rules: [
        type: {:list, :map},
        default: [
          %{
            keywords: ["plan", "planning", "roadmap", "strategy", "organize", "decompose", "task list", "project"],
            route: :planning,
            priority: 100
          },
          %{
            keywords: ["analyze", "review", "check", "inspect", "examine"],
            route: :analysis,
            priority: 90
          },
          %{
            keywords: ["generate", "create", "write", "build", "implement"],
            exclude: ["plan", "roadmap"],
            route: :generation,
            priority: 90
          },
          %{
            keywords: ["debug", "fix", "error", "issue", "problem", "troubleshoot"],
            route: :problem_solver,
            priority: 85
          }
        ]
      ],
      
      # Circuit breaker configuration
      circuit_breakers: [type: :map, default: %{}],
      circuit_breaker_config: [
        type: :map,
        default: %{
          failure_threshold: 5,
          reset_timeout: 60_000,
          half_open_requests: 3
        }
      ],
      
      # Metrics
      metrics: [
        type: :map,
        default: %{
          total_requests: 0,
          routes_used: %{},
          classification_times: [],
          routing_times: [],
          failures: %{}
        }
      ],
      
      # Context preservation
      context_cache: [type: :map, default: %{}],
      context_ttl: [type: :pos_integer, default: 300_000], # 5 minutes
      
      # Default route for unmatched queries
      default_route: [type: :atom, default: :complex]
    ],
    actions: [
      RubberDuck.Jido.Actions.Conversation.Router.ConversationRouteRequestAction,
      RubberDuck.Jido.Actions.Conversation.Router.UpdateRoutingRulesAction,
      RubberDuck.Jido.Actions.Conversation.Router.GetRoutingMetricsAction
    ]

  require Logger

  # The agent now uses Jido Actions instead of handle_signal callbacks.
  # Signal handling is automatically routed to appropriate actions based on signal type.
  # 
  # Signal type to action mapping:
  # - "conversation_route_request" -> ConversationRouteRequestAction
  # - "update_routing_rules" -> UpdateRoutingRulesAction
  # - "get_routing_metrics" -> GetRoutingMetricsAction
  #
  # All business logic has been moved to the respective action modules
  # in lib/rubber_duck/jido/actions/conversation/router/
end