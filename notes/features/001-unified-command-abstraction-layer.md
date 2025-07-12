# Feature: Unified Command Abstraction Layer

## Summary
Implement a centralized command processing system that provides consistent behavior across all client interfaces (CLI, LiveView, TUI, WebSocket), eliminating code duplication and enabling seamless command execution regardless of the client type.

## Requirements
- [ ] Create unified command and context structs that work across all client interfaces
- [ ] Implement command parser using Optimus that handles CLI, WebSocket, LiveView, and TUI inputs
- [ ] Build central command processor GenServer with handler registry and execution pipeline
- [ ] Support async command execution with progress updates for long-running operations
- [ ] Create command handlers for analyze, generate, complete, refactor, test, llm, and health commands
- [ ] Implement response formatters supporting JSON, text, table, and markdown formats
- [ ] Create client adapters for CLI, WebSocket, LiveView, and TUI interfaces
- [ ] Integrate with existing engine system, LLM services, and memory management
- [ ] Remove task-based commands from `lib/rubber_duck/cli/commands/`
- [ ] Migrate WebSocket-based commands to use the new unified system
- [ ] Update all tests to work with the new abstraction layer
- [ ] Use existing API key authentication (no additional authorization needed)

## Research Summary
### Existing Usage Rules Checked
- Reactor: Command workflows can be triggered through the unified processor
- Spark: Could potentially use DSL for command definitions in the future

### Documentation Reviewed
- Optimus: Command-line parsing library already in use, supports subcommands and validation
- GenServer: For stateful command processor with registry
- Phoenix Channels: Already have CLIChannel that needs to be integrated
- TableRex: For table formatting (already a dependency)

### Existing Patterns Found
- Command pattern: `lib/rubber_duck/cli/commands/*.ex` - existing commands follow a `run/2` interface
- CLI client: `lib/rubber_duck/cli_client/commands/*.ex` - WebSocket-based commands with similar structure
- Channel handlers: `lib/rubber_duck_web/channels/cli_channel.ex:37-50` - handle_in pattern for commands
- Formatter: `lib/rubber_duck/cli_client/formatter.ex` - existing formatting logic for different output types
- Main entry: `lib/rubber_duck/cli_client/main.ex:39-100` - Optimus parsing already implemented

### Technical Approach
1. **Phase 1 - Core Structures**: Create command and context structs in `lib/rubber_duck/commands/`
2. **Phase 2 - Parser**: Build unified parser that can handle different client input formats
3. **Phase 3 - Processor**: Implement GenServer-based processor with handler registry
4. **Phase 4 - Handlers**: Create handler behavior and implement for each command
5. **Phase 5 - Formatters**: Build formatter module with client-specific output
6. **Phase 6 - Adapters**: Create adapters to bridge existing clients to new system
7. **Phase 7 - Migration**: Refactor existing commands to use new handlers
8. **Phase 8 - Integration**: Update CLIChannel and other interfaces to use unified system

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking existing WebSocket CLI clients | High | Test thoroughly with existing CLI client before removing old handlers |
| Performance regression | Medium | Benchmark command execution before/after, optimize hot paths |
| Complex migration path | Medium | Migrate one command at a time with tests |
| State management complexity | Low | Use Registry for process tracking, keep processor stateless where possible |

## Implementation Checklist
- [ ] Create `lib/rubber_duck/commands/command.ex` with struct definition
- [ ] Create `lib/rubber_duck/commands/context.ex` with context struct
- [ ] Create `lib/rubber_duck/commands/parser.ex` with Optimus-based parsing
- [ ] Create `lib/rubber_duck/commands/processor.ex` GenServer
- [ ] Create `lib/rubber_duck/commands/handler.ex` behavior
- [ ] Create handler implementations in `lib/rubber_duck/commands/handlers/`
- [ ] Create `lib/rubber_duck/commands/formatters.ex` module
- [ ] Create adapter modules in `lib/rubber_duck/commands/adapters/`
- [ ] Update CLIChannel to use new command processor
- [ ] Remove task-based commands from `lib/rubber_duck/cli/commands/`
- [ ] Migrate WebSocket CLI commands to new handlers
- [ ] Update all command tests
- [ ] Add integration tests for unified system
- [ ] Update documentation

## Decisions Made
1. Command composition (chaining) - NOT needed in initial implementation
2. Async execution - YES, the command processor will support async execution with progress updates
3. Authorization - Current API key authentication is sufficient
4. Ash Framework bridge - NOT needed, skip section 5.2.15 from implementation plan
5. Macro command definitions - NOT needed, skip section 5.2.16.2 from implementation plan

## Log
- Created feature branch: feature/unified-command-abstraction-layer
- Set up TodoWrite tracking for all implementation tasks
- Starting with core structs: Command and Context
- Created failing tests for Command struct
- Implemented Command and Context structs with validation
- Tests passing for basic struct creation and validation
- Created failing tests for Parser module
- Implemented Parser with Optimus CLI parsing, WebSocket message parsing, and LiveView params parsing
- All parser tests passing - can parse commands from different client types into unified Command structs