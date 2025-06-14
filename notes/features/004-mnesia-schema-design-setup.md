# Feature: Mnesia Schema Design and Setup

## Summary
Design and implement the core Mnesia database schema that will store AI assistant context, conversations, and analysis data across the distributed cluster, replacing current in-memory GenServer state.

## Requirements
- [ ] Design table schemas for ai_context, code_analysis_cache, and llm_interaction
- [ ] Implement Mnesia initialization and schema creation
- [ ] Configure table replication strategies for different data types
- [ ] Set up table indexes for optimal query performance
- [ ] Create database migration and upgrade procedures
- [ ] Implement backup and recovery mechanisms
- [ ] Maintain API compatibility with existing GenServers
- [ ] Support distributed transactions across cluster nodes
- [ ] Ensure proper data consistency models (CP vs AP)
- [ ] Add comprehensive test coverage for distributed scenarios

## Research Summary
### Existing Usage Rules Checked
- No existing database dependencies in mix.exs
- Standard Elixir/OTP Mnesia patterns apply
- Current clustering infrastructure ready for Mnesia integration

### Documentation Reviewed
- Mnesia User Guide for distributed database design
- Erlang/OTP Mnesia documentation for table design and replication
- Distributed systems patterns for consistency models

### Existing Patterns Found
- **ContextManager state**: `%{sessions: %{session_id => session_data}, start_time: timestamp}` at lib/rubber_duck/context_manager.ex:122-127
- **ModelCoordinator state**: `%{models: %{}, stats: %{}, config: %{}}` at lib/rubber_duck/model_coordinator.ex:117-124
- **Session structure**: `%{session_id, messages: [], metadata: %{}, created_at: DateTime}` at lib/rubber_duck/context_manager.ex:109-114
- **Model structure**: `%{name, type, endpoint, capabilities, health_status, health_reason, registered_at}` at lib/rubber_duck/model_coordinator.ex:129-135
- **NodeMonitor state**: `%{connected_nodes, subscribers, node_history, config}` at lib/rubber_duck/node_monitor.ex:97-103

### Technical Approach
1. **Schema Design**: Map existing GenServer state structures to Mnesia table schemas
2. **Table Strategy**: 
   - `sessions` table for ContextManager data (bag table for distributed access)
   - `models` table for ModelCoordinator registry (set table for uniqueness)
   - `model_stats` table for usage statistics (set table with frequent updates)
   - `cluster_nodes` table for NodeMonitor history (ordered_set for temporal queries)
3. **Replication Strategy**:
   - Sessions: ram_copies on all nodes (frequently accessed, can lose on restart)
   - Models: disc_copies on all nodes (persistent, critical configuration)
   - Stats: disc_only_copies on subset of nodes (large data, write-heavy)
   - Cluster metadata: ram_copies (ephemeral, rebuilds on startup)
4. **Migration Strategy**: Create MnesiaManager GenServer to initialize and manage schema
5. **API Preservation**: Maintain exact same public APIs for ContextManager and ModelCoordinator
6. **Transaction Patterns**: Replace direct state access with Mnesia transactions

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Schema changes break existing APIs | High | Thorough testing, gradual migration, API compatibility layer |
| Mnesia initialization fails across nodes | High | Robust error handling, fallback to local mode, retry mechanisms |
| Performance degradation from transactions | Medium | Optimize table types, indexing, benchmark against current performance |
| Data loss during node failures | Medium | Proper replication strategies, backup procedures, recovery testing |
| Complex distributed debugging | Medium | Comprehensive logging, Mnesia observer integration, test tooling |

## Implementation Checklist
- [ ] Add Mnesia to application configuration
- [ ] Create MnesiaManager GenServer for schema management
- [ ] Design and implement sessions table schema
- [ ] Design and implement models table schema  
- [ ] Design and implement model_stats table schema
- [ ] Design and implement cluster_nodes table schema
- [ ] Implement table initialization and migration procedures
- [ ] Configure replication strategies for each table type
- [ ] Add table indexes for query optimization
- [ ] Create backup and recovery procedures
- [ ] Update ContextManager to use Mnesia transactions
- [ ] Update ModelCoordinator to use Mnesia transactions
- [ ] Update NodeMonitor to use Mnesia for history
- [ ] Write comprehensive tests for distributed scenarios
- [ ] Write tests for schema migration and upgrades
- [ ] Write tests for backup and recovery procedures
- [ ] Performance benchmark against current implementation
- [ ] Integration test with existing cluster infrastructure
- [ ] Verify API compatibility with existing tests

## Questions
1. Should we implement a gradual migration strategy or replace all state at once?
2. What consistency model should we use for different data types (CP vs AP)?
3. How should we handle Mnesia initialization order across cluster nodes?
4. What backup frequency and retention policy should we implement?