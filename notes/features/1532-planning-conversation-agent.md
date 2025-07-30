# Feature: Planning Conversation Agent

## Summary
Transform the existing PlanningConversation engine into an autonomous agent that handles plan creation through signal-based communication, integrating with the Planning domain for structured plan management.

## Requirements
- [ ] Create PlanningConversationAgent using Jido.Agent framework
- [ ] Migrate plan creation and validation logic from engine
- [ ] Implement signal-based conversation flow
- [ ] Add real-time validation with critic integration
- [ ] Support hierarchical plan decomposition
- [ ] Enable plan persistence and state management
- [ ] Provide feedback signals for UI updates
- [ ] Implement plan improvement and fixing flows
- [ ] Add conversation metrics and tracking

## Research Summary
### Existing Usage Rules Checked
- Jido usage rules: Agents use schemas, return tagged tuples, integrate with OTP
- BaseAgent pattern: Provides signal emission, state management, lifecycle hooks
- Ash Framework: Plan and Task resources with domain operations

### Documentation Reviewed
- PlanningConversation engine: Complex plan creation with LLM integration
- Critics system: Orchestrator for plan validation with multiple critics
- Plan improvement: PlanImprover and PlanFixer for automatic enhancement
- Hierarchical plans: Support for phases and nested tasks

### Existing Patterns Found
- PlanningConversation: lib/rubber_duck/engines/conversation/planning_conversation.ex - Current implementation
- Plan resources: Ash-based Plan and Task models with validation
- Critics: Validation orchestration with aggregated results
- Decomposer: Breaking down plans into tasks and phases

### Technical Approach
1. Create PlanningConversationAgent using BaseAgent
2. Define state schema for conversation tracking
3. Implement signal handlers for plan operations
4. Transform synchronous operations to signal-based flow
5. Add conversation state machine for multi-step planning
6. Emit signals for:
   - plan_creation_started
   - plan_validation_result
   - plan_improvement_suggestion
   - plan_creation_completed
   - plan_creation_failed
7. Integrate with existing Planning domain models
8. Add metrics for conversation quality and completion

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Complex state management for conversations | High | Use FSM pattern for conversation states |
| Breaking existing plan creation flow | High | Maintain backward compatibility wrapper |
| Signal ordering for multi-step flows | Medium | Add conversation ID correlation |
| Performance with large plan decomposition | Medium | Stream task creation signals |

## Implementation Checklist
- [ ] Create lib/rubber_duck/agents/planning_conversation_agent.ex
- [ ] Define agent schema with conversation state
- [ ] Implement signal handlers for plan operations
- [ ] Add conversation state machine
- [ ] Transform LLM interactions to async signals
- [ ] Implement validation signal flow
- [ ] Add plan improvement signals
- [ ] Create tests for agent behavior
- [ ] Update EssentialAgents to include new agent
- [ ] Document signal formats and flows

## Questions for Pascal
1. Should plan creation be fully async or support sync mode?
2. How should we handle long-running decomposition operations?
3. Should conversation history be persisted?
4. What metrics are most important for planning conversations?

## Log
- Created feature branch: feature/15.3.2-planning-conversation-agent
- Implemented PlanningConversationAgent with async signal handling
- Added comprehensive test suite
- Integrated with existing Planning domain models

## Signal Formats

### Input Signals

#### plan_creation_request
Initiates a new plan creation conversation.

```json
{
  "type": "plan_creation_request",
  "source": "client:123",
  "data": {
    "query": "Create a plan to implement user authentication with JWT",
    "context": {
      "language": "elixir",
      "framework": "phoenix",
      "user_preferences": {}
    },
    "conversation_id": "conv_unique_123",
    "user_id": "user_456"
  }
}
```

#### validate_plan_request
Requests validation of a specific plan.

```json
{
  "type": "validate_plan_request",
  "source": "client:123",
  "data": {
    "conversation_id": "conv_unique_123",
    "plan_id": "plan_789"
  }
}
```

#### improve_plan_request
Requests improvement of a plan based on validation warnings.

```json
{
  "type": "improve_plan_request",
  "source": "client:123",
  "data": {
    "conversation_id": "conv_unique_123",
    "plan_id": "plan_789",
    "validation_results": {
      "summary": "warning",
      "suggestions": ["Add more specific success criteria", "Break down large tasks"]
    }
  }
}
```

#### complete_conversation
Marks a planning conversation as complete.

```json
{
  "type": "complete_conversation",
  "source": "internal",
  "data": {
    "conversation_id": "conv_unique_123",
    "plan_id": "plan_789",
    "status": "completed"
  }
}
```

#### get_planning_metrics
Requests current planning metrics.

```json
{
  "type": "get_planning_metrics",
  "source": "monitoring:789"
}
```

### Output Signals

#### plan_creation_started
Emitted when a plan creation conversation begins.

```json
{
  "type": "plan_creation_started",
  "source": "agent:planning_conversation_main",
  "data": {
    "conversation_id": "conv_unique_123",
    "query": "Create a plan to implement user authentication with JWT",
    "user_id": "user_456"
  }
}
```

#### plan_created
Emitted when a plan is successfully created in the system.

```json
{
  "type": "plan_created",
  "source": "agent:planning_conversation_main",
  "data": {
    "conversation_id": "conv_unique_123",
    "plan_id": "plan_789",
    "plan_name": "Implement User Authentication - 1234567890",
    "plan_type": "feature"
  }
}
```

#### plan_validation_result
Emitted when plan validation is complete.

```json
{
  "type": "plan_validation_result",
  "source": "agent:planning_conversation_main",
  "data": {
    "conversation_id": "conv_unique_123",
    "plan_id": "plan_789",
    "validation_summary": "warning",
    "validation_results": {
      "summary": "warning",
      "suggestions": ["Add more specific success criteria"],
      "blocking_issues": [],
      "critics": {
        "completeness": "passed",
        "complexity": "warning",
        "dependency": "passed"
      }
    }
  }
}
```

#### plan_improvement_completed
Emitted when plan improvement is finished.

```json
{
  "type": "plan_improvement_completed",
  "source": "agent:planning_conversation_main",
  "data": {
    "conversation_id": "conv_unique_123",
    "original_plan_id": "plan_789",
    "improved_plan_id": "plan_790",
    "new_validation": {
      "summary": "passed"
    }
  }
}
```

#### plan_creation_completed
Emitted when the entire plan creation process is complete.

```json
{
  "type": "plan_creation_completed",
  "source": "agent:planning_conversation_main",
  "data": {
    "conversation_id": "conv_unique_123",
    "plan_id": "plan_790",
    "duration": 5432
  }
}
```

#### planning_metrics_response
Returns current planning metrics.

```json
{
  "type": "planning_metrics_response",
  "source": "agent:planning_conversation_main",
  "data": {
    "total_plans_created": 42,
    "active_conversations": 3,
    "completed_conversations": 39,
    "failed_conversations": 2,
    "validation_times": [1200, 1500, 980],
    "creation_times": [3000, 4500, 2800],
    "improvement_count": 15,
    "fix_count": 5
  }
}
```

### Error Signals

#### plan_creation_error
Emitted when plan creation fails at any stage.

```json
{
  "type": "plan_creation_error",
  "source": "agent:planning_conversation_main",
  "data": {
    "conversation_id": "conv_unique_123",
    "error": "{:missing_fields, [\"query\"]}"
  }
}
```

#### plan_extraction_failed
Emitted when LLM fails to extract plan information.

```json
{
  "type": "plan_extraction_failed",
  "source": "agent:planning_conversation_main",
  "data": {
    "conversation_id": "conv_unique_123",
    "error": "{:llm_error, \"Rate limit exceeded\"}"
  }
}
```

## Conversation Flow

1. **Plan Creation Flow**:
   ```
   plan_creation_request → plan_creation_started → [LLM extraction] → 
   plan_created → [validation] → plan_validation_result → 
   [improvement if needed] → plan_creation_completed
   ```

2. **Improvement Flow** (when validation has warnings):
   ```
   plan_validation_result (warning) → [auto-improvement] → 
   plan_improvement_completed → [re-validation] → plan_validation_result
   ```

3. **Fix Flow** (when validation fails):
   ```
   plan_validation_result (failed) → [auto-fix] → 
   plan_fix_completed → [re-validation] → plan_validation_result
   ```

## Integration Points

1. **Planning Domain**: Uses Ash-based Plan and Task resources
2. **Critics System**: Integrates with Orchestrator for validation
3. **LLM Service**: Async calls for plan extraction and improvement
4. **Signal Router**: All signals should be routed through RubberDuck.Jido.SignalRouter

## Usage Example

```elixir
# Start the agent (would be done by supervisor in production)
{:ok, agent} = PlanningConversationAgent.start_link(id: "planning_main")

# Send a plan creation request
signal = %{
  "type" => "plan_creation_request",
  "source" => "web_channel:123",
  "data" => %{
    "query" => "Help me create a plan to refactor our authentication system to use OAuth2",
    "context" => %{"current_auth" => "JWT", "target" => "OAuth2"},
    "conversation_id" => "conv_#{System.unique_integer()}",
    "user_id" => "user123"
  }
}

# Signal would be routed to agent, triggering the async plan creation flow
# Agent emits signals throughout the process for real-time UI updates
```

## Configuration

The agent supports several configuration options through its state:

- `max_tokens`: Maximum tokens for LLM calls (default: 3000)
- `temperature`: LLM temperature setting (default: 0.7)
- `timeout`: Operation timeout in ms (default: 60000)
- `auto_improve`: Automatically improve plans with warnings (default: true)
- `auto_fix`: Automatically fix failed plans (default: true)