# Feature: Core Domain Models with Ash (Section 1.3)

## Summary
Implement the fundamental domain models using Ash Framework, including Project, CodeFile, and AnalysisResult resources with their relationships and actions.

## Requirements
- [x] Create Ash Domain module `RubberDuck.Workspace`
- [x] Implement `Project` resource with UUID primary key, name, description, configuration JSON field, timestamps, and default CRUD actions
- [x] Implement `CodeFile` resource with UUID primary key, file path, content, language, AST cache (JSONB), embeddings array, relationship to Project, and custom semantic search action
- [x] Implement `AnalysisResult` resource with UUID primary key, analysis type, results attributes, severity level enum, relationship to CodeFile, and timestamp tracking
- [ ] Create Ash Registry module (not needed in Ash 3.0)
- [ ] Configure Ash authorization policies (deferred to later phase)
- [ ] Set up Ash API module (replaced by domain code interfaces)
- [x] Generate Ash migrations
- [ ] Create factory modules for testing (optional, deferred)
- [x] Write comprehensive tests for all resources

## Research Summary
### Existing Usage Rules Checked
- Ash Framework usage rules: 
  - Organize code around domains and resources
  - Use code interfaces on domains to define the contract
  - Put business logic inside actions rather than external modules
  - Use resources to model domain entities
  - Prefer domain code interfaces over direct Ash calls

### Documentation Reviewed
- Ash Domains: Domains group related resources, provide centralized code interface, similar to Phoenix Contexts
- Ash Resources: Static definitions of entities with attributes, actions, relationships
- Ash Actions: CRUD operations with business logic, validations, changes
- Ash Relationships: belongs_to, has_one, has_many, many_to_many
- AshPostgres: Already configured in RubberDuck.Repo with necessary extensions including pgvector

### Existing Patterns Found
- Repo setup: lib/rubber_duck/repo.ex - AshPostgres.Repo configured with extensions
- PostgreSQL extensions test: test/rubber_duck/repo_extensions_test.exs - Shows testing patterns

### Technical Approach
1. Create domain module `RubberDuck.Workspace` to group Project, CodeFile, and AnalysisResult resources
2. Define resources with Ash.Resource DSL including:
   - Attributes with proper types and constraints
   - Relationships between resources
   - Actions (using defaults where appropriate, custom actions for semantic search)
   - AshPostgres data layer configuration
3. Use code interfaces on the domain for clean API
4. Leverage pgvector extension for embeddings in CodeFile
5. Use JSONB for flexible configuration and AST cache storage
6. Follow Ash patterns for testing using Ash.Test utilities

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| pgvector integration complexity | Medium | Use existing pgvector extension, follow Ash attribute patterns |
| Semantic search implementation | High | Start with basic vector similarity, enhance iteratively |
| Migration conflicts | Low | Use ash.codegen for migrations, test thoroughly |
| Complex relationships | Medium | Start simple, add constraints incrementally |

## Implementation Checklist
- [x] Create lib/rubber_duck/workspace.ex domain module
- [x] Create lib/rubber_duck/workspace/project.ex resource
- [x] Create lib/rubber_duck/workspace/code_file.ex resource  
- [x] Create lib/rubber_duck/workspace/analysis_result.ex resource
- [x] Add code interfaces to domain
- [x] Run ash.codegen to generate migrations
- [ ] Create test/support/factory.ex with Ash.Generator (optional, deferred)
- [x] Write test/rubber_duck/workspace/project_test.exs
- [x] Write test/rubber_duck/workspace/code_file_test.exs
- [x] Write test/rubber_duck/workspace/analysis_result_test.exs
- [x] Verify all tests pass
- [x] Check for compilation warnings

## Questions for Pascal
1. Should we implement soft deletes for any of these resources?
2. What specific fields should be in the Project configuration JSON?
3. Should the semantic search action return similarity scores?
4. Do we need any specific authorization policies at this stage?
5. Should we add any indexes beyond what Ash generates automatically?

## Log
- Created feature branch: feature/1.3-core-domain-models
- Set up todo tracking for all implementation tasks
- Created failing test for Project resource
- Generated domain module RubberDuck.Workspace
- Generated Project resource with attributes and actions
- Added code interfaces to domain (partial - Project only)
- Error: Database table doesn't exist yet - need to generate migrations
- Generated migrations using ash.codegen
- Ran migrations successfully
- Tests passing for Project resource (2 tests)
- Generated CodeFile resource with relationships and embeddings support
- Generated AnalysisResult resource with severity enum
- Added complete code interfaces for all resources to domain
- Generated second migration for CodeFile and AnalysisResult tables
- Fixed test database setup issues
- Updated resources to accept foreign keys directly (attribute_writable? true)
- Fixed atom vs string issue for severity field
- All tests passing (14 tests, 1 skipped for future pgvector)
- No compilation warnings

## Implementation Summary

Successfully implemented all three core domain models with Ash Framework:

1. **Project** - Stores project metadata with configuration as JSONB
2. **CodeFile** - Stores source code with embeddings (array of floats for now) and AST cache
3. **AnalysisResult** - Stores analysis results with flexible JSONB structure

Key implementation details:
- Used `attribute_writable? true` on belongs_to relationships to allow direct foreign key assignment
- Configured custom create/update actions with explicit accept lists
- Severity field uses atoms (:low, :medium, :high, :critical) instead of strings
- Semantic search action created but implementation deferred until pgvector integration
- All tests passing with comprehensive coverage
- Clean code with no compilation warnings

Next steps:
- Implement proper pgvector support for semantic search when ready
- Consider creating factory module for test data generation
- Add authorization policies when authentication is implemented