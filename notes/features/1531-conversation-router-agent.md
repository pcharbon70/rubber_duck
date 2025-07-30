# Feature: Conversation Router Agent

## Summary
Transform the existing ConversationRouter module into an autonomous agent that can classify incoming queries and route them to appropriate conversation engines through signal-based coordination.

## Requirements
- [ ] Create ConversationRouterAgent using Jido.Agent framework
- [ ] Implement conversation classification using existing QuestionClassifier
- [ ] Add signal-based routing to replace direct engine calls
- [ ] Maintain routing state and metrics
- [ ] Support dynamic routing rules and load balancing
- [ ] Enable intent detection with confidence scoring
- [ ] Preserve conversation context across routing decisions
- [ ] Implement circuit breaking for failing routes
- [ ] Add routing analytics and monitoring

## Research Summary
### Existing Usage Rules Checked
- Jido usage rules: Agents should use schemas for validation, return tagged tuples, use OTP supervision
- BaseAgent pattern: Use `use RubberDuck.Agents.BaseAgent` for common functionality
- Signal handling: Agents should implement handle_signal/2 for processing signals

### Documentation Reviewed
- Jido.Agent: Stateful orchestrators with OTP GenServer integration
- RubberDuck.Agents.BaseAgent: Provides signal emission, health checks, state persistence
- Signal patterns: CloudEvents-compatible format with type, source, data fields

### Existing Patterns Found
- ConversationRouter module: lib/rubber_duck/engines/conversation/conversation_router.ex - Current implementation to transform
- BaseAgent usage: lib/rubber_duck/agents/base_agent.ex:77 - Standard agent pattern
- Signal routing: lib/rubber_duck/jido/signal_router.ex - Existing signal infrastructure
- QuestionClassifier: lib/rubber_duck/cot/question_classifier.ex - Reusable classification logic

### Technical Approach
1. Create ConversationRouterAgent using BaseAgent pattern
2. Define state schema for routing tables, metrics, and context
3. Implement handle_signal/2 for processing routing requests
4. Transform classify_query and select_engine logic to work with signals
5. Emit routing decision signals instead of direct engine calls
6. Add signal patterns for:
   - conversation_route_request
   - conversation_route_response
   - routing_metrics_update
   - circuit_breaker_triggered
7. Implement dynamic routing rules through state updates
8. Add metrics collection for routing decisions

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing conversation flow | High | Maintain backward compatibility during transition |
| Signal ordering issues | Medium | Implement request ID tracking and correlation |
| Performance overhead from signals | Medium | Add caching for repeated classifications |
| Loss of synchronous routing | Low | Provide sync wrapper for critical paths |

## Implementation Checklist
- [ ] Create lib/rubber_duck/agents/conversation_router_agent.ex
- [ ] Define agent schema with routing state
- [ ] Implement signal handlers for routing requests
- [ ] Transform classification logic to agent actions
- [ ] Add routing decision emission
- [ ] Implement metrics collection
- [ ] Add circuit breaker logic
- [ ] Create tests for agent behavior
- [ ] Update supervisor to include new agent
- [ ] Document signal formats and routing patterns

## Questions for Zach
1. Should we maintain synchronous routing API for backward compatibility?
2. What metrics are most important for routing decisions?
3. Should routing rules be configurable at runtime through signals?
4. How should we handle routing failures - fallback to default engine or error?

## Log
- Created feature branch: feature/15.3.1-conversation-router-agent
- Set up todo tracking with 10 implementation tasks
- Implemented ConversationRouterAgent with full signal handling
- Added comprehensive test suite
- Integrated with application supervisor via EssentialAgents module

## Signal Formats

### Input Signals

#### conversation_route_request
Routes an incoming conversation query to the appropriate engine.

```json
{
  "type": "conversation_route_request",
  "source": "client:123",
  "data": {
    "query": "The user's question or request",
    "context": {
      "user_id": "optional-user-id",
      "session_id": "optional-session-id",
      "previous_route": "optional-previous-route"
    },
    "request_id": "unique-request-id"
  }
}
```

#### update_routing_rules
Updates the dynamic routing rules at runtime.

```json
{
  "type": "update_routing_rules",
  "source": "admin:456",
  "data": {
    "rules": [
      {
        "keywords": ["plan", "planning", "roadmap"],
        "exclude": ["unplan", "no plan"],
        "route": "planning",
        "priority": 100
      }
    ]
  }
}
```

#### get_routing_metrics
Requests current routing metrics.

```json
{
  "type": "get_routing_metrics",
  "source": "monitoring:789"
}
```

### Output Signals

#### conversation_route_response
Returns the routing decision for a conversation.

```json
{
  "type": "conversation_route_response",
  "source": "agent:conversation_router_main",
  "data": {
    "request_id": "unique-request-id",
    "route": "planning_conversation",
    "classification": {
      "complexity": "multi_step",
      "question_type": "planning",
      "intent": "planning",
      "confidence": 0.95,
      "explanation": "Query contains planning keywords and multi-step intent"
    },
    "context_id": "user123:session456"
  }
}
```

#### conversation_route_error
Emitted when routing fails.

```json
{
  "type": "conversation_route_error",
  "source": "agent:conversation_router_main",
  "data": {
    "request_id": "unique-request-id",
    "error": "{:missing_fields, [\"query\"]}"
  }
}
```

#### routing_metrics_response
Returns current routing metrics.

```json
{
  "type": "routing_metrics_response",
  "source": "agent:conversation_router_main",
  "data": {
    "total_requests": 1234,
    "routes_used": {
      "simple": 500,
      "complex": 300,
      "planning": 234,
      "analysis": 100,
      "generation": 100
    },
    "classification_times": [45, 32, 28, 51],
    "routing_times": [50, 35, 30, 55],
    "failures": {
      "{:missing_fields, [\"request_id\"]}": 5,
      "{:circuit_breaker_open, :complex}": 2
    }
  }
}
```

## Integration Points

1. **Signal Router**: The agent emits signals that should be handled by the RubberDuck.Jido.SignalRouter
2. **Question Classifier**: Uses RubberDuck.CoT.QuestionClassifier for query analysis
3. **Conversation Engines**: Routes to engines defined in routing_table
4. **Metrics System**: Integrates with telemetry for monitoring

## Usage Example

```elixir
# Agent is automatically started by EssentialAgents on application boot

# To send a routing request via signal (from another component):
signal = %{
  "type" => "conversation_route_request",
  "source" => "web_channel:123",
  "data" => %{
    "query" => "Help me plan a new authentication system",
    "context" => %{"user_id" => "user123"},
    "request_id" => "req_#{System.unique_integer()}"
  }
}

# Signal would be routed through SignalRouter to the agent
# Agent responds with conversation_route_response signal
```