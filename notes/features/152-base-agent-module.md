# Feature: Base Agent Module Enhancement

## Summary
Enhance the existing BaseAgent module to align with Jido framework best practices, adding lifecycle hooks, state management utilities, and testing helpers as specified in implementation plan section 15.1.2.

## Requirements
- [x] Enhance BaseAgent behaviour with Jido-compliant lifecycle hooks
- [x] Add common agent functions for signal emission and subscription
- [x] Implement robust state management with validation and persistence
- [x] Create comprehensive lifecycle hooks (pre_init, post_init, health_check, etc.)
- [x] Build testing utilities for agent development
- [ ] Maintain backward compatibility with existing TestAgent
- [x] Improve error handling and telemetry integration
- [x] Add state persistence and recovery mechanisms

## Research Summary
### Existing Usage Rules Checked
- No existing usage rules for agent patterns in the project
- Current BaseAgent already provides basic GenServer integration
- Telemetry integration already in place for basic events

### Documentation Reviewed
- Jido v1.2.0 Agent documentation: Agents use lifecycle callbacks and state schema validation
- Jido provides callbacks: on_before_validate_state, on_after_validate_state, on_before_run, on_after_run, on_error
- Agents defined with `use Jido.Agent` with name, schema, actions configuration
- Runtime module handles state transitions and command processing

### Existing Patterns Found
- Pattern 1: [lib/rubber_duck/jido/base_agent.ex:69] Current BaseAgent uses GenServer macro approach
- Pattern 2: [lib/rubber_duck/jido/base_agent.ex:98] Telemetry already integrated
- Pattern 3: [lib/rubber_duck/jido/signal_dispatcher.ex:52] Signal emission pattern established
- Pattern 4: [lib/rubber_duck/agents/supervisor.ex:36] Existing agent system has health_check pattern

### Technical Approach
1. **Enhance BaseAgent Behaviour**
   - Add lifecycle callbacks matching Jido patterns
   - Keep GenServer compatibility but add Jido-style hooks
   - Extend callback definitions with proper typespec
   - Add schema validation support

2. **Common Agent Functions**
   - Create emit_signal/2 helper for easy signal emission
   - Add subscribe/2 and unsubscribe/1 for signal patterns
   - Implement state persistence helpers using ETS/DETS
   - Add error handling utilities with retry logic
   - Create telemetry helper functions

3. **State Management System**
   - Define BaseState struct with common fields
   - Add state validation using NimbleOptions
   - Create state transformation helpers
   - Implement state snapshots and recovery
   - Add state history tracking

4. **Lifecycle Hooks Implementation**
   - Add pre_init/1 for setup before initialization
   - Implement post_init/1 for after successful init
   - Create pre_terminate/2 for cleanup preparation
   - Add health_check/1 for liveness probes
   - Implement metrics collection hooks

5. **Testing Utilities**
   - Create AgentCase test helper module
   - Add mock signal generation helpers
   - Implement state assertion macros
   - Create integration test support
   - Add performance benchmark helpers

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing TestAgent | High | Keep backward compatibility, test thoroughly |
| Complex state management overhead | Medium | Make features opt-in, provide simple defaults |
| Performance impact of hooks | Medium | Make hooks optional, measure impact |
| Confusion with existing Agent system | Low | Clear documentation and examples |
| State persistence failures | Medium | Implement fallback strategies, proper error handling |

## Implementation Checklist
- [x] Create RubberDuck.Agents.BaseAgent with Jido integration
- [x] Create RubberDuck.Jido.Agent.State module for state management
- [x] Implement RubberDuck.Jido.Agent.Helpers for common functions
- [x] Add lifecycle hooks (pre_init, post_init, health_check)
- [x] Create RubberDuck.Jido.Agent.TestHelper for testing
- [x] Implement signal handling and emission
- [x] Write comprehensive tests for all components
- [x] Add telemetry integration
- [x] Add documentation and examples
- [ ] Update existing TestAgent for backward compatibility
- [ ] Performance benchmarks

## Questions for Pascal
1. Should we fully adopt Jido's `use Jido.Agent` pattern or keep our GenServer approach?
2. Do we need state persistence for all agents or make it optional?
3. Should lifecycle hooks be mandatory or optional callbacks?
4. What level of schema validation is needed (NimbleOptions vs custom)?
5. Should we integrate with existing telemetry patterns or create new ones?

## Log
- Created feature branch: feature/15.1.2-base-agent-module
- Starting implementation with failing tests
- Reviewed official Jido documentation to understand proper patterns
- Created RubberDuck.Agents.BaseAgent that properly uses Jido.Agent
- Implemented state management, helpers, and lifecycle hooks
- Created comprehensive test suite that passes
- Integrated with SignalDispatcher for event handling
- Added telemetry support for monitoring

## Implementation Summary

### Key Design Decisions
1. **Jido Integration**: Used `use Jido.Agent` as the foundation rather than trying to replace it
2. **Lifecycle Hooks**: Implemented hooks through Jido's callback system (on_before_run, on_after_run, etc.)
3. **Signal Handling**: Created a RubberDuck-specific callback for handling signals that integrates with SignalDispatcher
4. **State Management**: Leveraged the existing Agent.State module for persistence
5. **Testing**: Created simple, direct tests that don't require GenServer processes

### Files Created/Modified
- `lib/rubber_duck/agents/base_agent.ex` - Main BaseAgent implementation
- `lib/rubber_duck/jido/agent/state.ex` - State management utilities
- `lib/rubber_duck/jido/agent/helpers.ex` - Helper functions
- `lib/rubber_duck/jido/agent/test_helper.ex` - Testing utilities
- `test/rubber_duck/agents/base_agent_test.exs` - Comprehensive test suite

### Next Steps
1. Update existing TestAgent to demonstrate backward compatibility
2. Create performance benchmarks
3. Document migration path for existing agents
4. Create more complex agent examples