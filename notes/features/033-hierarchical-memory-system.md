# Feature: Hierarchical Memory System

## Summary
Implement a three-tier memory system (short-term, mid-term, long-term) using Ash and PostgreSQL to maintain context across interactions and provide personalized AI assistance.

## Requirements
- [ ] Create three-tier memory architecture with short-term (session-based), mid-term (pattern extraction), and long-term (persistent) storage
- [ ] Implement session-based short-term memory with automatic expiration after 20 interactions
- [ ] Build pattern extraction from short-term to mid-term memory including code patterns, error patterns, and usage patterns
- [ ] Create long-term memory for persistent storage of user preferences, code style patterns, and project knowledge
- [ ] Implement memory consolidation process to promote patterns between tiers
- [ ] Add search and retrieval capabilities with relevance scoring
- [ ] Set up memory persistence using PostgreSQL with AshPostgres
- [ ] Include privacy controls for sensitive data handling
- [ ] Support multi-user isolation with proper data separation

## Research Summary

### Existing Usage Rules Checked
- AshPostgres usage rules: 
  - Use `postgres do` block for table configuration
  - Define resources with proper attributes and actions
  - Use check constraints for domain invariants
  - Implement custom indexes for performance
  - Use code interfaces on domains for clean API
- Ash usage rules: 
  - Organize code around domains and resources
  - Use code interfaces instead of direct Ash calls
  - Put business logic inside actions
  - Each resource should be focused and well-named

### Documentation Reviewed
- AshPostgres: Full PostgreSQL data layer support with migrations, check constraints, custom indexes, and multitenancy
- Ash: Declarative resource modeling with actions, attributes, relationships, and domain organization
- Ash.DataLayer.Ets: Built-in ETS data layer for in-memory storage, ideal for testing and lightweight usage (no transaction support)
- pgvector: Available for vector embeddings if needed for pattern similarity search
- Smith/MemoryOS: Reference architecture for hierarchical memory systems with heat scores and FIFO migration

### Existing Patterns Found
- Domain pattern: `/home/ducky/code/rubber_duck/lib/rubber_duck/workspace.ex` - domains group related resources with code interfaces
- Resource pattern: `/home/ducky/code/rubber_duck/lib/rubber_duck/workspace/project.ex:1-42` - standard resource structure with postgres configuration
- No existing memory/session management found in codebase

### Technical Approach
1. **Domain Structure**: Create `RubberDuck.Memory` domain to group all memory-related resources
2. **Resources** (inspired by MemoryOS):
   - `Memory.Interaction` - Store raw interactions (short-term, ETS data layer)
   - `Memory.Summary` - Topic summaries and patterns (mid-term, ETS data layer)
   - `Memory.UserProfile` - Personal preferences and persistent info (long-term, PostgreSQL)
   - `Memory.CodePattern` - Code style patterns per language/project (long-term, PostgreSQL)
   - `Memory.Knowledge` - Project and domain knowledge (long-term, PostgreSQL)
3. **Storage Strategy**:
   - Short-term: ETS data layer for real-time conversation data, FIFO with 20-interaction limit
   - Mid-term: ETS data layer for recurring topic summaries, heat score-based retention
   - Long-term: PostgreSQL with AshPostgres for persistent personal/project data
4. **Memory Management Modules** (following MemoryOS architecture):
   - **Storage Module**: Handles tier-specific storage operations
   - **Update Module**: Manages memory migration between tiers using heat scores and FIFO
   - **Retrieval Module**: Semantic similarity and keyword matching across tiers
   - **Context Builder**: Constructs comprehensive context from retrieved memories
5. **Consolidation Strategy**:
   - Heat score calculation based on: frequency, recency, relevance
   - FIFO migration from STM to MTM when capacity reached
   - Importance-based promotion from MTM to LTM
6. **Search & Retrieval**: 
   - Semantic similarity using embeddings (future: pgvector)
   - Keyword matching for quick lookups
   - Cross-tier search with relevance scoring
7. **Privacy**: Sensitive data filtering, configurable retention policies, user data isolation

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| ETS memory growth | High | Implement automatic cleanup, limit entries per session |
| ETS data loss on restart | Medium | Regular consolidation to PostgreSQL, accept as tradeoff for performance |
| Performance degradation with large datasets | High | Add proper indexes for PostgreSQL, use ETS table limits |
| Privacy/security concerns | High | Filter sensitive data before long-term storage, audit logging |
| Complex consolidation logic | Medium | Start simple, iterate based on usage patterns |
| Migration complexity | Low | Only PostgreSQL resources need migrations |

## Implementation Checklist
- [ ] Create Memory domain module at `lib/rubber_duck/memory.ex`
- [ ] Create Interaction resource for short-term memory (ETS data layer)
- [ ] Create Summary resource for mid-term memory (ETS data layer)
- [ ] Create UserProfile resource for long-term memory (PostgreSQL)
- [ ] Create CodePattern resource for code patterns (PostgreSQL)
- [ ] Create Knowledge resource for project context (PostgreSQL)
- [ ] Implement Memory.Manager GenServer to coordinate memory tiers
- [ ] Create Memory.Storage module for tier-specific operations
- [ ] Create Memory.Updater module for migration and heat score logic
- [ ] Create Memory.Retriever module for cross-tier search
- [ ] Implement heat score calculation for memory importance
- [ ] Add FIFO and importance-based migration strategies
- [ ] Create search actions with semantic similarity support
- [ ] Implement privacy controls and retention policies
- [ ] Create code interfaces for clean API
- [ ] Write comprehensive tests for all memory operations
- [ ] Document memory system architecture and usage

## Log
- Created feature branch: `feature/3.3-hierarchical-memory-system`
- Starting implementation
- Confirmed: Use pgvector for semantic similarity search
- Confirmed: 20 interactions for short-term, 100 patterns for mid-term

## Questions for Pascal
1. Should we use pgvector for semantic similarity search or start with PostgreSQL full-text search?
2. What retention policies should we implement for each memory tier (e.g., 20 interactions for short-term, 100 patterns for mid-term)?
3. Should memory consolidation run on a schedule or be triggered by events?
4. Do we need real-time memory updates or is eventual consistency acceptable?
5. Should we implement memory export/import for user data portability?
6. Should ETS tables be private (process-scoped) or public for shared access across processes?