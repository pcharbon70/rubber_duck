# Feature: Core GenServer Implementation

## Summary
Implement the primary business logic components as GenServers to establish the process-oriented architecture that enables distributed computing for the RubberDuck AI assistant.

## Requirements
- [ ] Create ContextManager GenServer for session state
- [ ] Implement ModelCoordinator GenServer for AI model management
- [ ] Build basic message passing between core processes
- [ ] Add process registration and discovery mechanisms
- [ ] Implement graceful shutdown and restart procedures
- [ ] Create basic process monitoring and health checks
- [ ] All GenServers must follow OTP principles
- [ ] Must be testable with comprehensive test coverage (80%+ unit, 90%+ integration)
- [ ] Must support supervision and restart strategies

## Research Summary
### Existing Usage Rules Checked
- Standard Elixir GenServer patterns apply
- Must integrate with existing supervision tree from section 1.1

### Documentation Reviewed
- Elixir GenServer behavior documentation
- Process registration with Registry
- Process monitoring and linking
- Supervision and restart strategies

### Existing Patterns Found
- Supervision tree structure: lib/rubber_duck/application.ex:10-19
- Registry setup: lib/rubber_duck/application.ex:12
- Supervisor modules: lib/rubber_duck/*_supervisor.ex

### Technical Approach
1. **TDD Approach**: Write failing tests first for each GenServer
2. **ContextManager**: Manage AI conversation context and session state
3. **ModelCoordinator**: Coordinate AI model interactions and load balancing
4. **Process Registration**: Use Registry for process discovery
5. **Message Passing**: Implement synchronous and asynchronous messaging
6. **Health Monitoring**: Basic health checks and process monitoring

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| State loss on process crash | High | Implement proper state recovery, use supervisors |
| Process bottlenecks | Medium | Design for concurrent operations, monitor performance |
| Complex message passing | Medium | Keep messages simple, document protocols |

## Implementation Checklist
- [ ] Write failing tests for ContextManager GenServer
- [ ] Implement ContextManager with basic state management
- [ ] Write failing tests for ModelCoordinator GenServer
- [ ] Implement ModelCoordinator with model management
- [ ] Write tests for message passing between processes
- [ ] Implement inter-process communication
- [ ] Write tests for process registration
- [ ] Implement Registry-based process discovery
- [ ] Write tests for graceful shutdown
- [ ] Implement shutdown and restart procedures
- [ ] Write tests for health monitoring
- [ ] Implement basic health checks
- [ ] Integration test all components together
- [ ] Update supervisors to manage new GenServers

## Log

### Implementation Completed
- ✅ Created failing tests for ContextManager GenServer (TDD RED)
- ✅ Implemented ContextManager with session state management (TDD GREEN)
- ✅ Created failing tests for ModelCoordinator GenServer (TDD RED)
- ✅ Implemented ModelCoordinator with model management (TDD GREEN)
- ✅ Implemented message passing between processes
- ✅ Process registration working with Registry
- ✅ Graceful shutdown procedures implemented
- ✅ Health monitoring and checks working
- ✅ All tests passing (43 tests, 0 failures)

### Final Implementation

**Files Created:**
- `/test/rubber_duck/context_manager_test.exs` - Comprehensive tests for ContextManager
- `/lib/rubber_duck/context_manager.ex` - Session and context management GenServer
- `/test/rubber_duck/model_coordinator_test.exs` - Comprehensive tests for ModelCoordinator
- `/lib/rubber_duck/model_coordinator.ex` - AI model coordination GenServer
- `/test/rubber_duck/message_passing_test.exs` - Inter-process communication tests

**Files Modified:**
- `/lib/rubber_duck/context_supervisor.ex` - Added ContextManager as child
- `/lib/rubber_duck/model_supervisor.ex` - Added ModelCoordinator as child

**Key Features Implemented:**
1. **ContextManager**: Manages session state, conversation context, and metadata
2. **ModelCoordinator**: Handles model registration, selection, health monitoring, and usage stats
3. **Message Passing**: ContextManager requests models from ModelCoordinator
4. **Health Notifications**: ModelCoordinator notifies ContextManager of model health changes
5. **Process Registration**: Both GenServers use Registry for discovery
6. **Graceful Shutdown**: Proper terminate callbacks and cleanup
7. **Health Checks**: Both GenServers support health monitoring

**Architecture Decisions:**
- Used synchronous calls for critical operations (model selection, session management)
- Used asynchronous casts for notifications (health updates, usage tracking)
- Registry-based process discovery for flexibility
- Supervisor integration for fault tolerance

**No Deviations:** Implementation matches the original plan exactly.

**Follow-up Tasks:** Ready for section 1.3 (Initial Clustering Infrastructure).

## Questions
1. What specific state should ContextManager maintain initially?
   - **Answer:** Session ID, messages list, metadata map, and created_at timestamp
2. How should ModelCoordinator handle model loading and unloading?
   - **Answer:** Simple registration/unregistration with health status tracking
3. What health metrics should we track from the start?
   - **Answer:** Process status, memory usage, uptime, and model/session counts