# Feature: Memory and Context Agents Migration (16.3.1)

## Summary
Migrate the ContextBuilderAgent from direct signal handling to Jido-compliant action-based architecture, and create a comprehensive Context Actions library for memory and context management workflows.

## Requirements
- [ ] Remove direct `handle_signal/2` implementations from ContextBuilderAgent
- [ ] Extract context building logic into reusable Jido Actions
- [ ] Implement priority-based context assembly through Actions
- [ ] Add compression and optimization Actions
- [ ] Create context validation pipeline
- [ ] Maintain all existing functionality (source management, caching, streaming)
- [ ] Follow Jido pure function patterns with tagged tuple returns
- [ ] Implement proper error handling and state validation
- [ ] Support signal-based communication for event-driven architecture
- [ ] Ensure performance through optimized context operations

## Research Summary

### Existing Usage Rules Checked
- Jido framework: Pure functions, tagged tuples, schema validation, OTP integration
- BaseAgent patterns: State schema, signal mappings, action composition
- Context system: Entry, Source, Request structures already well-designed

### Documentation Reviewed
- ContextBuilderAgent: Complex agent with 14 direct signal handlers, sophisticated caching and streaming
- Context modules: Well-structured ContextEntry, ContextSource, ContextRequest with comprehensive functionality
- Jido patterns: Action-based architecture, Agent state management, Signal processing

### Existing Patterns Found
- ContextBuilderAgent: lib/rubber_duck/agents/context_builder_agent.ex - Uses BaseAgent but has direct signal handling
- Context system: lib/rubber_duck/context/*.ex - Well-structured data models ready for action integration
- BaseAgent: lib/rubber_duck/agents/base_agent.ex - Agent framework wrapper

### Technical Approach

#### Phase 1: Agent Migration Analysis
**Current State**: ContextBuilderAgent uses BaseAgent but has 14 direct `handle_signal/2` implementations
**Issues**: Direct signal handling instead of action-based routing, complex business logic mixed with agent code
**Migration Strategy**: Extract all signal handling logic into dedicated Actions, implement signal-to-action mapping

#### Phase 2: Action Extraction Strategy
1. **ContextAssemblyAction** - Extract `build_context`, `update_context` logic
2. **ContextPrioritizationAction** - Extract prioritization and scoring algorithms  
3. **ContextCompressionAction** - Extract compression, deduplication, summarization
4. **ContextValidationAction** - Extract context quality validation
5. **ContextCacheAction** - Extract caching, invalidation, cleanup logic

#### Phase 3: Signal Mapping Architecture
Map existing signals to appropriate actions:
- `build_context` → ContextAssemblyAction
- `update_context` → ContextAssemblyAction (update mode)
- `stream_context` → ContextAssemblyAction (streaming mode)
- `invalidate_context` → ContextCacheAction
- `register_source`/`update_source`/`remove_source` → ContextSourceManagementAction
- `set_priorities`/`configure_limits` → ContextConfigurationAction
- `get_metrics` → ContextMetricsAction

#### Phase 4: State Schema Migration
Convert existing state structure to validated schema:
- sources, cache, active_builds, priorities, metrics, config → proper schema validation
- Lifecycle hooks for cache cleanup and metrics updates
- Health check integration

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking context building API | High | Maintain signal compatibility through action routing |
| Performance degradation from action overhead | Medium | Benchmark context assembly performance, optimize critical paths |
| Complex state migration | Medium | Gradual migration with comprehensive testing |
| Cache invalidation issues | Medium | Careful testing of cache management actions |
| Streaming context complexity | Low | Follow established streaming patterns from GenerationAgent |

## Implementation Checklist
- [ ] Create feature branch feature/16.3.1-memory-context-agents-migration
- [ ] Create Context Actions (ContextAssemblyAction, ContextPrioritizationAction, ContextCompressionAction, ContextValidationAction, ContextCacheAction)
- [ ] Migrate ContextBuilderAgent to pure signal-to-action routing
- [ ] Implement state schema validation for ContextBuilderAgent
- [ ] Add lifecycle hooks for cache management and metrics
- [ ] Create comprehensive tests for all Actions
- [ ] Verify no regressions in context building functionality  
- [ ] Performance test context assembly workflows
- [ ] Update documentation and examples

## Questions for Pascal
1. Should we preserve the existing streaming context API or enhance it with new capabilities?
2. Are there specific performance requirements for context assembly that we should target?
3. Should we add new context optimization techniques beyond the existing compression/summarization?
4. How should we handle backward compatibility for any external context API consumers?

## Log

### 2024-08-02 - Research Phase Completed
- Analyzed ContextBuilderAgent: Uses BaseAgent but has 14 direct signal handlers
- Reviewed Context data structures: Well-designed, ready for action integration
- Identified migration strategy: Extract signal handling to Actions, implement signal mapping
- Created feature branch: feature/16.3.1-memory-context-agents-migration
- Ready to begin Action creation and Agent migration