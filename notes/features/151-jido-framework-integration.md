# Feature: Jido Framework Integration

## Summary
Integrate the Jido autonomous agent framework as the foundation for transforming RubberDuck into a distributed agent-based system, including CloudEvents-based signal routing and workflow engine integration.

## Requirements
- [ ] Add Jido framework (~> 1.2.0) and CloudEvents library to dependencies
- [ ] Configure Jido application settings with agent supervision options
- [ ] Initialize Jido runtime with supervisor, registry, and signal dispatcher
- [ ] Create agent namespace structure and documentation templates
- [ ] Set up development tools including dashboard and monitoring
- [ ] Ensure compatibility with existing Agent system (RubberDuck.Agents)
- [ ] Maintain backward compatibility with current supervision tree
- [ ] Support for CloudEvents specification for signal messaging

## Research Summary
### Existing Usage Rules Checked
- No existing usage rules found for Jido or CloudEvents in the project
- Existing Agent system uses DynamicSupervisor pattern (RubberDuck.Agents.Supervisor)
- Current supervision tree follows OTP best practices with Registry-based discovery

### Documentation Reviewed
- Jido v1.2.0: Autonomous agent framework for Elixir with distributed behavior support
- CloudEvents specification: Standardized event format for interoperability
- Jido features: Actions, Agents, Workflows, Sensors as core primitives
- Built on Elixir's actor model with fault tolerance and scalability
- Supports running 10k agents at 25KB each

### Existing Patterns Found
- Pattern 1: [lib/rubber_duck/application.ex:40-41] Existing Agent system with Registry
- Pattern 2: [lib/rubber_duck/agents/supervisor.ex:29] DynamicSupervisor usage
- Pattern 3: [lib/rubber_duck/telemetry/supervisor.ex:9] Standard Supervisor pattern
- Pattern 4: Multiple Registry instances for different subsystems (CircuitBreaker, Engine, FileWatcher, etc.)
- Pattern 5: Telemetry integration throughout the application

### Technical Approach
1. **Dependency Management**
   - Add `{:jido, "~> 1.2.0"}` to mix.exs dependencies
   - Add CloudEvents library (either `{:cloudevents, "~> 0.6.1"}` or custom implementation)
   - Update mix.lock after fetching dependencies

2. **Configuration Setup**
   - Create Jido configuration in config/config.exs
   - Configure agent supervision strategies (max_restarts, max_seconds)
   - Set up signal routing parameters
   - Define workflow engine settings
   - Add telemetry configuration for Jido events

3. **Runtime Integration**
   - Add Jido supervisor to application.ex children list
   - Position after existing Agent system to maintain compatibility
   - Initialize Jido registry with unique name to avoid conflicts
   - Set up signal dispatcher as a separate supervised process
   - Create health check endpoints for monitoring

4. **Namespace Organization**
   - Create lib/rubber_duck/jido directory for Jido-specific modules
   - Keep separate from existing lib/rubber_duck/agents to avoid conflicts
   - Establish clear naming conventions (e.g., Jido.Agents vs existing Agents)
   - Create documentation templates for Jido agents
   - Set up test structure mirroring the namespace

5. **Development Tools**
   - Configure Jido dashboard for local development
   - Add to existing monitoring infrastructure
   - Integrate with RubberDuck.Telemetry system
   - Create debugging helpers specific to signal flow
   - Add performance profiling for agent interactions

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Conflict with existing Agent system | High | Use separate namespaces and registries, maintain clear boundaries |
| Dependency version conflicts | Medium | Check compatibility with existing deps, use specific versions |
| Performance impact of additional supervision | Medium | Monitor resource usage, configure appropriate limits |
| Learning curve for Jido patterns | Medium | Create comprehensive documentation and examples |
| Signal routing overhead | Low | Use efficient CloudEvents implementation, batch where possible |

## Implementation Checklist
- [ ] Add Jido and CloudEvents to mix.exs dependencies
- [ ] Create config/jido.exs configuration file
- [ ] Update config/config.exs to import Jido config
- [ ] Modify lib/rubber_duck/application.ex to add Jido supervisor
- [ ] Create lib/rubber_duck/jido directory structure
- [ ] Implement base agent module templates
- [ ] Set up signal router with CloudEvents support
- [ ] Create workflow engine integration
- [ ] Add telemetry handlers for Jido events
- [ ] Write comprehensive tests for initialization
- [ ] Update documentation with Jido setup instructions
- [ ] Verify no regressions in existing Agent system

## Questions for Pascal
1. Should we migrate the existing Agent system to Jido immediately or maintain both during transition?
2. Are there specific CloudEvents features/bindings we need to prioritize (HTTP, Kafka, etc.)?
3. Should Jido agents be in a separate OTP app or within the main RubberDuck app?
4. What are the performance requirements for agent count and memory usage?
5. Do we need to implement custom Jido behaviors or use the defaults initially?

## Log
- Created feature branch: feature/15.1.1-jido-framework-integration
- Starting implementation with dependency addition
- Added Jido (~> 1.2.0) and CloudEvents (~> 0.6.1) to mix.exs
- Successfully fetched dependencies - Jido comes with several sub-dependencies including:
  - abacus (math expressions)
  - backoff (retry strategies)
  - jido_signal (signal handling)
  - quantum (job scheduling)
  - typed_struct (struct definitions)
- Created config/jido.exs with comprehensive configuration
- Updated config/config.exs to import Jido configuration
- Successfully compiled - noted some warnings from CloudEvents about optional Avrora dependency
- Created failing tests for Jido integration
- Implemented base Jido infrastructure:
  - RubberDuck.Jido - Main interface module
  - RubberDuck.Jido.Supervisor - Main supervisor
  - RubberDuck.Jido.AgentSupervisor - DynamicSupervisor for agents
  - RubberDuck.Jido.SignalDispatcher - CloudEvents signal routing
  - RubberDuck.Jido.BaseAgent - Base behaviour for agents
  - RubberDuck.Jido.WorkflowEngine - Placeholder for workflows
  - TestAgent - Simple test implementation
- Added Jido.Supervisor to application.ex supervision tree
- All tests passing! Jido framework successfully integrated

## Final Implementation

Successfully integrated the Jido autonomous agent framework into RubberDuck. The implementation provides:

1. **Complete Jido Infrastructure**:
   - Main Jido interface module for agent creation and management
   - Supervisor hierarchy with proper fault tolerance
   - CloudEvents-based signal dispatcher for agent communication
   - Base agent behaviour for creating custom agents
   - Registry-based agent discovery

2. **Key Features Implemented**:
   - Dynamic agent spawning with configurable options
   - Signal routing with pattern-based subscriptions
   - Telemetry integration for monitoring
   - Configuration-driven setup for different environments
   - Placeholder for workflow engine (future implementation)

3. **Compatibility**:
   - Coexists with existing Agent system using separate namespaces
   - No breaking changes to existing functionality
   - Clear separation of concerns between Jido and legacy agents

4. **Test Coverage**:
   - All integration tests passing
   - Supervisor starts successfully
   - Registry available for agent discovery
   - Signal dispatcher operational
   - Basic agent creation working

## Deviations from Plan

- Used TestAgent instead of full BaseAgent implementation due to callback conflicts (to be resolved in future iterations)
- Workflow engine left as placeholder for future implementation
- Some warnings remain due to behaviour conflicts (non-blocking)

## Follow-up Tasks Needed

1. Resolve BaseAgent behaviour conflicts with GenServer
2. Implement concrete agent types (PlannerAgent, AnalyzerAgent, etc.)
3. Add workflow engine functionality
4. Create migration guide from existing Agent system
5. Add performance benchmarks
6. Implement signal persistence for replay capability