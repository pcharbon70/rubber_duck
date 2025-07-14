# RubberDuck Implementation Plan - Part 2 (Phases 5-9)

This document contains the detailed implementation plans for Phases 5-9 of the RubberDuck project. For the overall project status and Phases 1-4, see the [main implementation plan](implementation_plan.md).

## Table of Contents
5. [Phase 5: Real-time Communication & UI](#phase-5-real-time-communication--ui)
6. [Phase 6: Conversational AI System](#phase-6-conversational-ai-system)
7. [Phase 7: Planning Enhancement System](#phase-7-planning-enhancement-system)
8. [Phase 8: MCP (Model Context Protocol) Integration](#phase-8-mcp-model-context-protocol-integration)
9. [Phase 9: Advanced Features & Production Readiness](#phase-9-advanced-features--production-readiness)

---

## Phase 5: Real-time Communication & UI

This phase implements the user-facing interfaces including Phoenix Channels for real-time communication, LiveView for the web interface, and a sophisticated CLI/TUI. These interfaces provide interactive access to all the coding assistant capabilities with dynamic LLM configuration support.

### 5.1 Phoenix Channels Setup

Implement WebSocket-based real-time communication for streaming code completions and live updates.

#### Tasks:
- [ ] 5.1.1 Configure Phoenix endpoint for WebSocket support
- [ ] 5.1.2 Create `RubberDuckWeb.UserSocket` module
- [ ] 5.1.3 Implement authentication for socket connections
- [ ] 5.1.4 Create `RubberDuckWeb.CodeChannel`:
  - [ ] 5.1.4.1 Handle join with project authorization
  - [ ] 5.1.4.2 Implement completion streaming
  - [ ] 5.1.4.3 Add presence tracking
  - [ ] 5.1.4.4 Handle collaborative editing events
- [ ] 5.1.5 Set up channel tests infrastructure
- [ ] 5.1.6 Implement reconnection logic
- [ ] 5.1.7 Add channel metrics and monitoring
- [ ] 5.1.8 Create channel rate limiting
- [ ] 5.1.9 Build message queuing for offline users
- [ ] 5.1.10 Document channel protocol

#### Unit Tests:
Create tests in `test/rubber_duck_web/channels/code_channel_test.exs` to verify:
- [ ] 5.1.11 Test channel join with authentication
- [ ] 5.1.12 Test completion streaming in chunks
- [ ] 5.1.13 Test completion error handling
- [ ] 5.1.14 Test cursor position broadcasting
- [ ] 5.1.15 Test user presence tracking
- [ ] 5.1.16 Test message queuing for offline users
- [ ] 5.1.17 Test rate limiting enforcement

### 5.2 Unified Command Abstraction Layer ✅ Completed

Implement a centralized command processing system that provides consistent behavior across all client interfaces (CLI, LiveView, TUI, WebSocket), eliminating code duplication and enabling seamless command execution regardless of the client type.

**Status**: Successfully implemented and integrated with WebSocket CLI channel. All channel tests passing.

#### Tasks:

**Command Structure and Context:**
- [x] 5.2.1 Create `RubberDuck.Commands.Command` struct:
  - [x] 5.2.1.1 Define command name and subcommand fields
  - [x] 5.2.1.2 Add args and options maps
  - [x] 5.2.1.3 Include client_type identifier
  - [x] 5.2.1.4 Add output format specification
- [x] 5.2.2 Create `RubberDuck.Commands.Context` struct:
  - [x] 5.2.2.1 User identification and session tracking
  - [x] 5.2.2.2 Project and conversation context
  - [x] 5.2.2.3 Permission list management
  - [x] 5.2.2.4 Metadata storage for extensions

**Command Parser with Optimus:**
- [x] 5.2.3 Create `RubberDuck.Commands.Parser` module:
  - [x] 5.2.3.1 Define Optimus specification for all commands
  - [x] 5.2.3.2 Implement CLI input parsing
  - [x] 5.2.3.3 Add WebSocket message parsing
  - [x] 5.2.3.4 Create LiveView params parsing
  - [x] 5.2.3.5 Build TUI input parsing
- [x] 5.2.4 Configure command specifications:
  - [x] 5.2.4.1 `analyze` command with file/directory args
  - [x] 5.2.4.2 `generate` command with description and language
  - [x] 5.2.4.3 `complete` command with position info
  - [x] 5.2.4.4 `refactor` command with instruction
  - [x] 5.2.4.5 `test` command with framework options
  - [x] 5.2.4.6 `llm` command with dynamic configuration subcommands
  - [x] 5.2.4.7 `health` command for server monitoring
- [x] 5.2.5 Add command validation:
  - [x] 5.2.5.1 Required argument checking
  - [x] 5.2.5.2 Option type validation
  - [x] 5.2.5.3 Mutually exclusive option handling
  - [x] 5.2.5.4 Default value application

**Central Command Processor:**
- [x] 5.2.6 Create `RubberDuck.Commands.Processor` GenServer:
  - [x] 5.2.6.1 Initialize with handler registry
  - [x] 5.2.6.2 Load validators and formatters
  - [x] 5.2.6.3 Set up telemetry hooks
  - [x] 5.2.6.4 Configure timeout handling
- [x] 5.2.7 Implement command execution pipeline:
  - [x] 5.2.7.1 Command validation stage
  - [x] 5.2.7.2 Authorization checking
  - [x] 5.2.7.3 Handler execution with timeout
  - [x] 5.2.7.4 Response formatting
  - [x] 5.2.7.5 Error handling and recovery
- [x] 5.2.8 Add execution features:
  - [x] 5.2.8.1 Async command support
  - [x] 5.2.8.2 Command cancellation
  - [x] 5.2.8.3 Progress reporting
  - [ ] 5.2.8.4 Result caching

**Command Handlers:**
- [x] 5.2.9 Create handler behavior and implementations:
  - [x] 5.2.9.1 Define `RubberDuck.Commands.Handler` behaviour
  - [x] 5.2.9.2 `Handlers.Analyze` for code analysis
  - [x] 5.2.9.3 `Handlers.Generate` for code generation
  - [x] 5.2.9.4 `Handlers.Complete` for completions
  - [x] 5.2.9.5 `Handlers.Refactor` for refactoring
  - [x] 5.2.9.6 `Handlers.Test` for test generation
  - [x] 5.2.9.7 `Handlers.LLM` for provider management with dynamic configuration
  - [x] 5.2.9.8 `Handlers.Health` for health checks with provider status
- [x] 5.2.10 Integrate handlers with existing engines:
  - [x] 5.2.10.1 Connect to Phase 2 engine system
  - [x] 5.2.10.2 Use Phase 3 LLM services with dynamic configuration
  - [x] 5.2.10.3 Access Phase 3 memory system
  - [ ] 5.2.10.4 Trigger Phase 4 workflows

**Response Formatters:**
- [x] 5.2.11 Create `RubberDuck.Commands.Formatters` module:
  - [x] 5.2.11.1 JSON formatter for all result types
  - [x] 5.2.11.2 Text formatter with templates
  - [x] 5.2.11.3 Table formatter using TableRex
  - [x] 5.2.11.4 Markdown formatter for rich clients
- [x] 5.2.12 Implement client-specific formatting:
  - [x] 5.2.12.1 CLI-optimized text output
  - [x] 5.2.12.2 LiveView HTML formatting
  - [x] 5.2.12.3 TUI ANSI formatting
  - [x] 5.2.12.4 WebSocket structured messages

**Client Adapters:**
- [x] 5.2.13 Create adapter modules for each client:
  - [x] 5.2.13.1 `Adapters.CLI` for command-line interface
  - [x] 5.2.13.2 `Adapters.WebSocket` for Phoenix channels
  - [x] 5.2.13.3 `Adapters.LiveView` for web interface
  - [x] 5.2.13.4 `Adapters.TUI` for terminal UI
- [x] 5.2.14 Implement adapter features:
  - [x] 5.2.14.1 Context building from client state
  - [x] 5.2.14.2 Error handling per client type
  - [x] 5.2.14.3 Streaming support where applicable
  - [x] 5.2.14.4 Client-specific authentication

**Integration and Extensions:**
- [ ] 5.2.15 Create Ash Framework bridge: (Not implemented - per user decision)
  - [ ] 5.2.15.1 Map commands to Ash actions
  - [ ] 5.2.15.2 Use Ash authorization policies
  - [ ] 5.2.15.3 Track command execution in resources
  - [ ] 5.2.15.4 Enable GraphQL command access
- [ ] 5.2.16 Add advanced features: (Not implemented - per user decision)
  - [ ] 5.2.16.1 Command composition support
  - [ ] 5.2.16.2 Macro command definitions
  - [ ] 5.2.16.3 Command history tracking
  - [ ] 5.2.16.4 Command aliasing system

#### Unit Tests:

**Parser Tests** (`test/rubber_duck/commands/parser_test.exs`):
- [x] 5.2.17 Test CLI argument parsing for all commands
- [x] 5.2.18 Test WebSocket message parsing
- [x] 5.2.19 Test validation error handling
- [x] 5.2.20 Test default value application
- [x] 5.2.21 Test unknown command handling

**Processor Tests** (`test/rubber_duck/commands/processor_test.exs`):
- [x] 5.2.22 Test command execution pipeline
- [x] 5.2.23 Test authorization enforcement
- [x] 5.2.24 Test timeout handling
- [x] 5.2.25 Test concurrent command execution
- [x] 5.2.26 Test error recovery

**Handler Tests** (`test/rubber_duck/commands/handlers/`):
- [x] 5.2.27 Test each command handler implementation
- [x] 5.2.28 Test handler integration with engines
- [x] 5.2.29 Test async command handling
- [x] 5.2.30 Test command cancellation
- [x] 5.2.31 Test LLM handler with dynamic configuration
- [x] 5.2.32 Test health handler with provider monitoring

**Formatter Tests** (`test/rubber_duck/commands/formatters_test.exs`):
- [x] 5.2.33 Test JSON formatting for all result types
- [x] 5.2.34 Test table formatting with edge cases
- [x] 5.2.35 Test client-specific formatting
- [x] 5.2.36 Test error formatting

**Integration Tests** (`test/rubber_duck/commands/integration_test.exs`):
- [x] 5.2.37 Test complete command flow for each client
- [x] 5.2.38 Test command authorization scenarios
- [x] 5.2.39 Test cross-client command consistency
- [x] 5.2.40 Test performance under load

**Channel Integration Tests** (`test/rubber_duck_web/channels/cli_channel_test.exs`):
- [x] 5.2.41 Test WebSocket channel integration with unified command system
- [x] 5.2.42 Test async command execution through channels
- [x] 5.2.43 Test error handling and response formatting
- [x] 5.2.44 Test all commands through channel interface

#### Implementation Notes:

**Architecture Decisions:**
- Implemented Command and Context structs as core data structures for all command processing
- Used Optimus for CLI parsing, with custom parsers for WebSocket, LiveView, and TUI formats
- Built GenServer-based Processor with handler registry pattern for extensibility
- Created Handler behavior to ensure consistent implementation across all commands
- Implemented comprehensive formatters supporting JSON, text, table, and markdown output
- Built client-specific adapters to provide convenient interfaces for each client type

**Key Features Implemented:**
- Unified command structure working across CLI, WebSocket, LiveView, and TUI interfaces
- Async command execution with progress tracking and cancellation support
- Multi-format output supporting different client needs
- Authorization and validation pipeline ensuring security
- Integration with existing engine systems and LLM services
- Comprehensive error handling and recovery mechanisms
- Dynamic LLM configuration support through new commands

**Integration Highlights:**
- Successfully migrated WebSocket CLI channel to use unified command system
- All 17 channel tests passing after implementation
- Removed old command-specific handlers in favor of unified approach
- Maintained backward compatibility while eliminating code duplication

**Not Implemented (Per User Decision):**
- Ash Framework bridge (5.2.15) - Not needed for current requirements
- Advanced features like command composition and macros (5.2.16) - Not needed initially

**Files Created/Modified:**
- Core modules: `lib/rubber_duck/commands/` (command.ex, context.ex, parser.ex, processor.ex, handler.ex, formatters.ex)
- Handlers: `lib/rubber_duck/commands/handlers/` (analyze.ex, generate.ex, complete.ex, refactor.ex, test.ex, llm.ex, health.ex)
- Adapters: `lib/rubber_duck/commands/adapters/` (cli.ex, websocket.ex, liveview.ex, tui.ex)
- Tests: Comprehensive test coverage with 72 tests across all modules
- Updated: `lib/rubber_duck_web/channels/cli_channel.ex` to use unified system

See `notes/features/001-unified-command-abstraction-layer.md` for detailed implementation documentation.

### 5.3 Dynamic LLM Configuration System ✅ Completed

Implement dynamic LLM provider and model configuration that allows runtime switching of providers and models through CLI commands and configuration files.

**Status**: Successfully implemented complete dynamic LLM configuration system with CLI commands and centralized configuration management.

#### Tasks:

**LLM Configuration Management:**
- [x] 5.3.1 Create `RubberDuck.LLM.Config` module:
  - [x] 5.3.1.1 Unified configuration API for provider/model selection
  - [x] 5.3.1.2 Merge CLI config with application config
  - [x] 5.3.1.3 Priority system (CLI > app config)
  - [x] 5.3.1.4 Model validation and availability checking
- [x] 5.3.2 Extend `RubberDuck.CLIClient.Auth` module:
  - [x] 5.3.2.1 LLM configuration storage in CLI config file
  - [x] 5.3.2.2 Provider and model persistence functions
  - [x] 5.3.2.3 JSON configuration management
  - [x] 5.3.2.4 Default provider tracking

**CLI Command Extensions:**
- [x] 5.3.3 Add new LLM subcommands to parser:
  - [x] 5.3.3.1 `llm set-model <provider> <model>` - Set model for provider
  - [x] 5.3.3.2 `llm set-default <provider>` - Set default provider
  - [x] 5.3.3.3 `llm list-models [provider]` - List available models
  - [x] 5.3.3.4 Enhanced `llm status` with model information
- [x] 5.3.4 Update LLM command handler:
  - [x] 5.3.4.1 Process new configuration commands
  - [x] 5.3.4.2 Integrate with Config module
  - [x] 5.3.4.3 Provide user feedback and validation
  - [x] 5.3.4.4 Handle configuration errors gracefully

**Engine Integration:**
- [x] 5.3.5 Update all AI engines for dynamic configuration:
  - [x] 5.3.5.1 Generation Engine - Remove hardcoded model selection
  - [x] 5.3.5.2 Analysis Engine - Use dynamic provider/model selection
  - [x] 5.3.5.3 Refactoring Engine - Dynamic configuration integration
  - [x] 5.3.5.4 Test Generation Engine - Provider-aware generation
  - [x] 5.3.5.5 Completion Engine - Dynamic model selection
- [x] 5.3.6 Create configuration validation:
  - [x] 5.3.6.1 Provider availability checking
  - [x] 5.3.6.2 Model compatibility validation
  - [x] 5.3.6.3 Fallback strategies for missing configs

**CLI Configuration Format:**
```json
{
  "api_key": "...",
  "server_url": "...",
  "llm": {
    "default_provider": "ollama",
    "providers": {
      "ollama": {"model": "codellama"},
      "openai": {"model": "gpt-4"},
      "anthropic": {"model": "claude-3-sonnet"}
    }
  }
}
```

#### Unit Tests:

**Configuration Tests** (`test/rubber_duck/llm/config_test.exs`):
- [x] 5.3.7 Test provider model retrieval from CLI config
- [x] 5.3.8 Test fallback to application config
- [x] 5.3.9 Test current provider and model selection
- [x] 5.3.10 Test model validation logic
- [x] 5.3.11 Test configuration merging priorities

**CLI Auth Tests** (`test/rubber_duck/cli_client/auth_test.exs`):
- [x] 5.3.12 Test LLM configuration storage and retrieval
- [x] 5.3.13 Test provider model updates
- [x] 5.3.14 Test default provider setting
- [x] 5.3.15 Test configuration persistence

**Engine Integration Tests**:
- [x] 5.3.16 Test generation engine with dynamic configuration
- [x] 5.3.17 Test analysis engine provider selection
- [x] 5.3.18 Test all engines use dynamic configuration
- [x] 5.3.19 Test engine fallback on configuration errors

#### Implementation Notes:

**Architecture Decisions:**
- Created centralized `LLM.Config` module for unified configuration management
- Extended existing CLI config system rather than creating separate storage
- Implemented priority-based configuration merging (CLI > app config)
- Updated all engines to use dynamic configuration instead of hardcoded models

**Key Features Implemented:**
- Complete dynamic LLM provider and model configuration
- CLI commands for runtime configuration changes
- Persistent configuration storage in CLI config file
- Integration with all existing AI engines
- Configuration validation and error handling
- Backward compatibility with existing configurations

**Configuration Priority System:**
1. CLI configuration file (`~/.rubber_duck/config.json`)
2. Application configuration (`config/*.exs`)
3. Default fallbacks

**Integration Highlights:**
- All AI engines now use `Config.get_current_provider_and_model/0`
- Removed hardcoded model selection throughout the codebase
- Comprehensive test coverage for all configuration scenarios
- Seamless integration with existing command system

**Files Created/Modified:**
- New module: `lib/rubber_duck/llm/config.ex`
- Enhanced: `lib/rubber_duck/cli_client/auth.ex` with LLM config functions
- Updated: All engine modules to use dynamic configuration
- Enhanced: `lib/rubber_duck/commands/parser.ex` with new LLM subcommands
- Enhanced: `lib/rubber_duck/commands/handlers/llm.ex` with configuration commands
- Tests: Comprehensive test coverage for dynamic configuration

See `notes/features/004-dynamic-llm-configuration.md` for detailed implementation documentation.

### 5.4 LiveView Interface

Build a comprehensive Phoenix LiveView application for real-time collaborative coding with integrated AI assistance, following the architecture design that combines code editing and LLM chat capabilities.

#### Tasks:

**Core LiveView Infrastructure:**
- [ ] 5.4.1 Create `RubberDuckWeb.CodingSessionLive` module as main coordinator
- [ ] 5.4.2 Implement Phoenix PubSub subscriptions:
  - [ ] 5.4.2.1 Project-level updates (`project:#{project_id}`)
  - [ ] 5.4.2.2 Editor updates (`editor:#{project_id}`)
  - [ ] 5.4.2.3 Chat updates (`chat:#{project_id}`)
- [ ] 5.4.3 Set up WebSocket channel subscription for coding sessions
- [ ] 5.4.4 Implement state management:
  - [ ] 5.4.4.1 Project and file state
  - [ ] 5.4.4.2 Conversation and message streams
  - [ ] 5.4.4.3 Editor content with debouncing
  - [ ] 5.4.4.4 Streaming status indicators

**Monaco Editor Component:**
- [ ] 5.4.5 Create `RubberDuckWeb.Components.MonacoEditorComponent`
- [ ] 5.4.6 Implement Monaco Editor integration:
  - [ ] 5.4.6.1 JavaScript hooks for editor mounting
  - [ ] 5.4.6.2 Syntax highlighting with language detection
  - [ ] 5.4.6.3 Real-time collaborative editing
  - [ ] 5.4.6.4 External update handling
  - [ ] 5.4.6.5 Code suggestions overlay
- [ ] 5.4.7 Add editor configuration:
  - [ ] 5.4.7.1 Theme support (vs-dark default)
  - [ ] 5.4.7.2 Font and display preferences
  - [ ] 5.4.7.3 Language-specific settings
- [ ] 5.4.8 Implement AI suggestion integration:
  - [ ] 5.4.8.1 Suggestion display overlay
  - [ ] 5.4.8.2 Apply/dismiss functionality
  - [ ] 5.4.8.3 Incremental completion updates

**Chat Panel Component:**
- [ ] 5.4.9 Create `RubberDuckWeb.Components.ChatPanelComponent`
- [ ] 5.4.10 Implement chat functionality:
  - [ ] 5.4.10.1 Message streaming with typing indicators
  - [ ] 5.4.10.2 LLM response streaming support
  - [ ] 5.4.10.3 Context-aware prompting
  - [ ] 5.4.10.4 Message history with timestamps
- [ ] 5.4.11 Integrate with Phase 3 systems:
  - [ ] 5.4.11.1 LLM Service for completions with dynamic configuration
  - [ ] 5.4.11.2 Memory Manager for context
  - [ ] 5.4.11.3 Context Builder for prompts

**File Tree Component:**
- [ ] 5.4.12 Create `RubberDuckWeb.Components.FileTreeComponent`
- [ ] 5.4.13 Implement file navigation:
  - [ ] 5.4.13.1 Project file listing
  - [ ] 5.4.13.2 File selection handling
  - [ ] 5.4.13.3 Current file highlighting
  - [ ] 5.4.13.4 File type icons

**Context Panel Component:**
- [ ] 5.4.14 Create `RubberDuckWeb.Components.ContextPanelComponent`
- [ ] 5.4.15 Display project context information:
  - [ ] 5.4.15.1 Current analysis results
  - [ ] 5.4.15.2 Code metrics
  - [ ] 5.4.15.3 Relevant documentation
  - [ ] 5.4.15.4 LLM provider status with dynamic configuration

**JavaScript Integration:**
- [ ] 5.4.16 Create Monaco Editor hooks (`assets/js/hooks/monaco_editor.js`):
  - [ ] 5.4.16.1 Editor mounting and configuration
  - [ ] 5.4.16.2 Content change debouncing
  - [ ] 5.4.16.3 Cursor position tracking
  - [ ] 5.4.16.4 Completion provider registration
- [ ] 5.4.17 Implement live_monaco_editor integration
- [ ] 5.4.18 Add collaborative cursor support

**Real-time Features:**
- [ ] 5.4.19 Implement file content synchronization:
  - [ ] 5.4.19.1 Debounced auto-save
  - [ ] 5.4.19.2 Conflict resolution
  - [ ] 5.4.19.3 Multi-user awareness
- [ ] 5.4.20 Add presence tracking for collaboration
- [ ] 5.4.21 Create real-time analysis updates

**Integration with Existing Systems:**
- [ ] 5.4.22 Connect to Phase 2 engines:
  - [ ] 5.4.22.1 Code Analysis Engine integration
  - [ ] 5.4.22.2 Suggestion Engine for completions
- [ ] 5.4.23 Integrate Phase 4 workflows:
  - [ ] 5.4.23.1 Trigger analysis workflows
  - [ ] 5.4.23.2 Display workflow results
- [ ] 5.4.24 Add telemetry events for UI interactions
- [ ] 5.4.25 Integrate with unified command system:
  - [ ] 5.4.25.1 Command execution through LiveView
  - [ ] 5.4.25.2 Dynamic LLM configuration in UI
  - [ ] 5.4.25.3 Real-time command feedback

#### Unit Tests:

**CodingSessionLive Tests** (`test/rubber_duck_web/live/coding_session_live_test.exs`):
- [ ] 5.4.26 Test mount with project authorization
- [ ] 5.4.27 Test PubSub subscription setup
- [ ] 5.4.28 Test file selection and content loading
- [ ] 5.4.29 Test editor content change handling
- [ ] 5.4.30 Test file save functionality
- [ ] 5.4.31 Test real-time update broadcasting

**Component Tests** (`test/rubber_duck_web/components/`):
- [ ] 5.4.32 Test Monaco Editor component rendering
- [ ] 5.4.33 Test Chat Panel message streaming
- [ ] 5.4.34 Test File Tree navigation
- [ ] 5.4.35 Test suggestion application
- [ ] 5.4.36 Test context panel updates

**Integration Tests** (`test/rubber_duck_web/live/integration_test.exs`):
- [ ] 5.4.37 Test complete coding session flow
- [ ] 5.4.38 Test multi-user collaboration
- [ ] 5.4.39 Test LLM response streaming
- [ ] 5.4.40 Test code analysis integration
- [ ] 5.4.41 Test memory persistence across sessions

**JavaScript Hook Tests** (`test/assets/js/hooks/`):
- [ ] 5.4.42 Test Monaco Editor mounting
- [ ] 5.4.43 Test content synchronization
- [ ] 5.4.44 Test completion provider
- [ ] 5.4.45 Test external update handling
- [ ] 5.4.46 Test cursor position broadcasting

### 5.5 WebSocket CLI Client Implementation ✅ Completed

Transform the CLI from mix task-based to a standalone WebSocket client that communicates with the running Phoenix server, eliminating compilation overhead and maintaining server state.

**Status**: Successfully implemented complete WebSocket CLI client with comprehensive dynamic LLM configuration support.

#### Tasks:
- [x] 5.5.1 Add WebSocket client dependencies:
  - [x] 5.5.1.1 `phoenix_gen_socket_client` for WebSocket communication
  - [x] 5.5.1.2 `websocket_client` for transport layer
- [x] 5.5.2 Create Phoenix Channel infrastructure:
  - [x] 5.5.2.1 `CLIChannel` for handling all CLI commands
  - [x] 5.5.2.2 Update `UserSocket` with CLI channel and API key auth
  - [x] 5.5.2.3 Implement channel message handlers for each command type
- [x] 5.5.3 Build WebSocket client architecture:
  - [x] 5.5.3.1 `CLIClient.Client` GenServer for connection management
  - [x] 5.5.3.2 `CLIClient.Transport` for Phoenix.Channels.GenSocketClient
  - [x] 5.5.3.3 Automatic reconnection on disconnect
  - [x] 5.5.3.4 Request/response correlation for async operations
- [x] 5.5.4 Implement authentication system:
  - [x] 5.5.4.1 `CLIClient.Auth` for API key management
  - [x] 5.5.4.2 Secure storage in `~/.rubber_duck/config.json`
  - [x] 5.5.4.3 `Mix.Tasks.RubberDuck.Auth` for key generation
  - [x] 5.5.4.4 Environment variable support
  - [x] 5.5.4.5 LLM configuration storage and management
- [x] 5.5.5 Create command handlers:
  - [x] 5.5.5.1 `analyze` - Code analysis via WebSocket
  - [x] 5.5.5.2 `generate` - Code generation with streaming
  - [x] 5.5.5.3 `complete` - Code completions
  - [x] 5.5.5.4 `refactor` - Code refactoring
  - [x] 5.5.5.5 `test` - Test generation
  - [x] 5.5.5.6 `llm` - LLM provider management with dynamic configuration
  - [x] 5.5.5.7 `health` - Server health monitoring with provider status
- [x] 5.5.6 Implement streaming support:
  - [x] 5.5.6.1 Stream message protocol (start/data/end)
  - [x] 5.5.6.2 Progress indicators for long operations
  - [x] 5.5.6.3 Real-time output display
- [x] 5.5.7 Build escript packaging:
  - [x] 5.5.7.1 Configure escript in mix.exs
  - [x] 5.5.7.2 `CLIClient.Main` entry point with Optimus
  - [x] 5.5.7.3 Embedded Elixir runtime
  - [x] 5.5.7.4 Binary distribution at `bin/rubber_duck`
- [x] 5.5.8 Add output formatting:
  - [x] 5.5.8.1 Plain text formatter (default)
  - [x] 5.5.8.2 JSON formatter for automation
  - [x] 5.5.8.3 Table formatter with column alignment
  - [x] 5.5.8.4 Format-specific rendering for each command
- [x] 5.5.9 Implement health check feature:
  - [x] 5.5.9.1 Server uptime tracking
  - [x] 5.5.9.2 Memory usage statistics
  - [x] 5.5.9.3 Connection counting
  - [x] 5.5.9.4 Provider health status with dynamic configuration
- [x] 5.5.10 Add comprehensive LLM configuration commands:
  - [x] 5.5.10.1 `llm status` - Show provider status and current models
  - [x] 5.5.10.2 `llm set-model` - Set model for specific provider
  - [x] 5.5.10.3 `llm set-default` - Set default provider
  - [x] 5.5.10.4 `llm list-models` - List available models
  - [x] 5.5.10.5 Provider connection management commands

#### Unit Tests:
Created comprehensive tests:
- [x] 5.5.11 Test channel join and authentication
- [x] 5.5.12 Test all command handlers (analyze, generate, complete, etc.)
- [x] 5.5.13 Test streaming message protocol
- [x] 5.5.14 Test LLM provider management commands with dynamic configuration
- [x] 5.5.15 Test health check response format with provider status
- [x] 5.5.16 Test connection failure and reconnection
- [x] 5.5.17 Test API key authentication flow
- [x] 5.5.18 Test LLM configuration persistence and retrieval
- [x] 5.5.19 Test dynamic model selection commands

#### Implementation Highlights:
- Successfully transformed CLI from mix tasks to WebSocket client
- Provides instant command execution without compilation
- Persistent server connection with automatic reconnection
- Real-time streaming for long operations
- Distributable binary with embedded Elixir runtime
- Complete dynamic LLM configuration through CLI commands
- Comprehensive health monitoring including provider status
- Integration with unified command system

See `notes/features/002-websocket-cli-client-integration.md` for implementation details.

### 5.6 Enhanced REPL Interface ✅ Completed

Transform the CLI conversation experience with a comprehensive REPL (Read-Eval-Print Loop) interface that provides an interactive, stateful environment for AI-assisted development.

**Status**: Successfully implemented complete REPL interface with multi-line input, slash commands, context management, and session persistence.

#### Tasks:
- [x] 5.6.1 Create REPL command specification:
  - [x] 5.6.1.1 Add `repl` command to CLI client main module
  - [x] 5.6.1.2 Define options (type, model, resume, no_welcome)
  - [x] 5.6.1.3 Integrate with existing command routing system
- [x] 5.6.2 Implement `RubberDuck.CLIClient.REPLHandler` module:
  - [x] 5.6.2.1 Interactive input loop with IO.gets
  - [x] 5.6.2.2 State management using Agent
  - [x] 5.6.2.3 WebSocket connection reuse
  - [x] 5.6.2.4 Session persistence
- [x] 5.6.3 Build multi-line input support:
  - [x] 5.6.3.1 Triple quote `"""` delimiter detection
  - [x] 5.6.3.2 Backslash `\` line continuation
  - [x] 5.6.3.3 Input buffering and assembly
  - [x] 5.6.3.4 Proper line break preservation
- [x] 5.6.4 Implement comprehensive slash commands:
  - [x] 5.6.4.1 `/help` - Display available commands
  - [x] 5.6.4.2 `/exit` or `/quit` - Exit REPL
  - [x] 5.6.4.3 `/clear` - Clear screen
  - [x] 5.6.4.4 `/info` - Show session information
  - [x] 5.6.4.5 `/history` - Display conversation history
  - [x] 5.6.4.6 `/save [filename]` - Save conversation
  - [x] 5.6.4.7 `/recent` - List recent conversations
  - [x] 5.6.4.8 `/switch <id>` - Switch conversation
- [x] 5.6.5 Add context management commands:
  - [x] 5.6.5.1 `/context` - Show current context files
  - [x] 5.6.5.2 `/context add <file>` - Add file to context
  - [x] 5.6.5.3 `/context remove <file>` - Remove from context
  - [x] 5.6.5.4 `/context clear` - Clear all context
  - [x] 5.6.5.5 Context persistence across sessions
- [x] 5.6.6 Create integrated command support:
  - [x] 5.6.6.1 `/analyze <file>` - Run analysis in context
  - [x] 5.6.6.2 `/generate <prompt>` - Generate code
  - [x] 5.6.6.3 `/refactor <instruction>` - Refactor with context
  - [x] 5.6.6.4 `/test <file>` - Generate tests
- [x] 5.6.7 Implement session management:
  - [x] 5.6.7.1 Auto-save on exit
  - [x] 5.6.7.2 Session state persistence
  - [x] 5.6.7.3 Resume last or specific conversation
  - [x] 5.6.7.4 Conversation ID extraction and reuse
- [x] 5.6.8 Add user experience enhancements:
  - [x] 5.6.8.1 Colored prompts and output
  - [x] 5.6.8.2 Streaming response display
  - [x] 5.6.8.3 Error handling with recovery
  - [x] 5.6.8.4 Welcome message with tips
  - [x] 5.6.8.5 Exit confirmation for unsaved changes

#### Unit Tests:
- [x] 5.6.9 Test REPL command parsing and routing
- [x] 5.6.10 Test multi-line input assembly
- [x] 5.6.11 Test slash command execution
- [x] 5.6.12 Test context file management
- [x] 5.6.13 Test session persistence and resumption
- [x] 5.6.14 Test conversation switching
- [x] 5.6.15 Test integrated command execution

#### Implementation Highlights:
- Direct message input without `send` command repetition
- Stateful conversation management with persistence
- Rich context awareness for better AI responses
- Seamless integration with existing CLI commands
- Enhanced user experience with multi-line support
- Comprehensive slash command system
- Session auto-save and recovery capabilities

The REPL interface significantly improves the conversational experience by eliminating the need for repeated `send` commands and providing a natural, interactive environment for AI-assisted development.

### 5.7 TUI (Terminal UI) Implementation with Go and Bubble Tea ✅ ~90% Complete

Build a modern terminal user interface using Go and the Bubble Tea framework, leveraging the Elm Architecture for predictable state management and seamless Phoenix WebSocket integration with chat-focused interface.

**Current Status**: The TUI implementation is approximately 90% complete with recent chat-focused interface implementation. Core functionality including the Model-View-Update architecture, Phoenix WebSocket integration, UI components, and comprehensive testing infrastructure have been implemented.

**Recent Major Update**: Successfully implemented chat-focused interface where chat is the primary view and file tree/editor are optional toggleable panels.

#### Tasks:

**Project Setup and Dependencies:**
- [x] 5.6.1 Create Go module `github.com/rubber_duck/tui`
- [x] 5.6.2 Add dependencies to `go.mod`:
  - [x] 5.6.2.1 `github.com/charmbracelet/bubbletea` - Core TUI framework
  - [x] 5.6.2.2 `github.com/charmbracelet/bubbles` - Component library
  - [x] 5.6.2.3 `github.com/charmbracelet/lipgloss` - Styling system
  - [x] 5.6.2.4 `github.com/nshafer/phx` - Phoenix channels client
  - [ ] 5.6.2.5 `github.com/alecthomas/chroma` - Syntax highlighting
- [x] 5.6.3 Set up project structure:
  - [x] 5.6.3.1 `cmd/rubber_duck_tui/main.go` - Entry point
  - [x] 5.6.3.2 `internal/ui/` - UI components
  - [x] 5.6.3.3 `internal/phoenix/` - WebSocket integration
  - [x] 5.6.3.4 `internal/commands/` - Command system

**Core Architecture Implementation:**
- [x] 5.6.4 Implement base Model-Update-View architecture:
  - [x] 5.6.4.1 Define `Model` struct with application state
  - [x] 5.6.4.2 Create message types for all events
  - [x] 5.6.4.3 Implement `Update` function for state transitions
  - [x] 5.6.4.4 Build `View` function with Lipgloss layouts
- [x] 5.6.5 Create state management system:
  - [x] 5.6.5.1 File tree state and operations
  - [x] 5.6.5.2 Editor state with content tracking
  - [x] 5.6.5.3 Output pane state for results
  - [x] 5.6.5.4 WebSocket connection state
  - [x] 5.6.5.5 Chat state with message history
  - [x] 5.6.5.6 Panel visibility state for dynamic layout

**Chat-Focused Interface Implementation:**
- [x] 5.6.6 Implement chat component (`internal/ui/chat.go`):
  - [x] 5.6.6.1 Scrollable message history using viewport
  - [x] 5.6.6.2 Multi-line input with textarea
  - [x] 5.6.6.3 Message type support (user, assistant, system, error)
  - [x] 5.6.6.4 Timestamp and author tracking
  - [x] 5.6.6.5 Theme integration and styling
- [x] 5.6.7 Create dynamic layout system:
  - [x] 5.6.7.1 Chat takes remaining space after optional panels
  - [x] 5.6.7.2 Automatic width calculation based on visible components
  - [x] 5.6.7.3 Minimum width enforcement for usability
  - [x] 5.6.7.4 Panel toggle functionality
- [x] 5.6.8 Add keyboard controls for chat interface:
  - [x] 5.6.8.1 `Ctrl+F`: Toggle file tree visibility
  - [x] 5.6.8.2 `Ctrl+E`: Toggle editor visibility
  - [x] 5.6.8.3 `Ctrl+/`: Focus chat input
  - [x] 5.6.8.4 `Tab`: Cycle through visible panes
  - [x] 5.6.8.5 `Enter`: Send message
  - [x] 5.6.8.6 `Ctrl+Enter`: Newline in chat

**Phoenix WebSocket Integration:**
- [x] 5.6.9 Implement Phoenix channel client:
  - [x] 5.6.9.1 Connection management with auto-reconnect
  - [x] 5.6.9.2 Channel join/leave operations
  - [x] 5.6.9.3 Message serialization/deserialization
  - [x] 5.6.9.4 Event subscription system
- [x] 5.6.10 Create WebSocket command adapters:
  - [x] 5.6.10.1 File analysis commands
  - [x] 5.6.10.2 Code generation commands
  - [x] 5.6.10.3 Completion requests
  - [x] 5.6.10.4 Refactoring operations
  - [x] 5.6.10.5 Chat message integration
- [x] 5.6.11 Implement streaming support:
  - [x] 5.6.11.1 Stream start/data/end message handling
  - [x] 5.6.11.2 Progressive output rendering
  - [ ] 5.6.11.3 Stream cancellation
  - [ ] 5.6.11.4 Error recovery

**UI Component Development:**
- [x] 5.6.12 Build file tree component:
  - [x] 5.6.12.1 Recursive tree rendering with Lipgloss
  - [x] 5.6.12.2 Expand/collapse functionality
  - [x] 5.6.12.3 File type icons and styling
  - [x] 5.6.12.4 Keyboard navigation (j/k, enter)
  - [x] 5.6.12.5 File selection events
- [x] 5.6.13 Create code editor component:
  - [x] 5.6.13.1 Integrate Bubbles textarea
  - [ ] 5.6.13.2 Syntax highlighting with Chroma
  - [x] 5.6.13.3 Line numbers and cursor position
  - [x] 5.6.13.4 Content change tracking
  - [ ] 5.6.13.5 Auto-save functionality
- [x] 5.6.14 Implement output/results pane:
  - [x] 5.6.14.1 Scrollable viewport with Bubbles
  - [x] 5.6.14.2 Formatted analysis results
  - [x] 5.6.14.3 Error display with styling
  - [x] 5.6.14.4 Progress indicators
  - [ ] 5.6.14.5 Clear and filter options
- [x] 5.6.15 Build command palette:
  - [x] 5.6.15.1 Fuzzy search with text input
  - [x] 5.6.15.2 Command list with descriptions
  - [x] 5.6.15.3 Keyboard shortcuts display
  - [x] 5.6.15.4 Command execution system
  - [ ] 5.6.15.5 Recent commands history

**Layout and Navigation:**
- [x] 5.6.16 Implement responsive layout system:
  - [x] 5.6.16.1 Dynamic layout with chat as primary pane
  - [x] 5.6.16.2 Dynamic width calculation
  - [x] 5.6.16.3 Terminal resize handling
  - [x] 5.6.16.4 Minimum size constraints
- [x] 5.6.17 Create navigation system:
  - [x] 5.6.17.1 Tab cycling between panes
  - [x] 5.6.17.2 Vim-style navigation keys
  - [x] 5.6.17.3 Focus indicators
  - [x] 5.6.17.4 Panel-specific controls
  - [ ] 5.6.17.5 Mouse support where available
- [x] 5.6.18 Add status bar:
  - [x] 5.6.18.1 Connection status indicator
  - [x] 5.6.18.2 Current file path
  - [x] 5.6.18.3 Operation progress
  - [x] 5.6.18.4 Key hints and active panels

**Advanced Features:**
- [x] 5.6.19 Implement modal dialogs:
  - [x] 5.6.19.1 Confirmation dialogs
  - [x] 5.6.19.2 Input prompts
  - [x] 5.6.19.3 Settings dialog
  - [x] 5.6.19.4 Help overlay
- [x] 5.6.20 Add command integration:
  - [x] 5.6.20.1 Messages starting with `/` parsed as commands
  - [x] 5.6.20.2 Regular messages sent as chat commands
  - [x] 5.6.20.3 Integration with existing command router
  - [x] 5.6.20.4 Echo functionality for testing
- [ ] 5.6.21 Add theming support:
  - [ ] 5.6.21.1 Color scheme definitions
  - [ ] 5.6.21.2 Dark/light mode toggle
  - [ ] 5.6.21.3 Custom style configuration
- [ ] 5.6.22 Create performance optimizations:
  - [ ] 5.6.22.1 Render caching for static components
  - [ ] 5.6.22.2 Debounced file operations
  - [ ] 5.6.22.3 Lazy loading for large files
  - [ ] 5.6.22.4 Virtual scrolling for file tree

#### Unit Tests:
Create tests in `tui/internal/ui/*_test.go` files to verify:
- [x] 5.6.23 Test Model initialization and state
- [x] 5.6.24 Test Update function message handling
- [x] 5.6.25 Test View rendering without errors
- [x] 5.6.26 Test WebSocket connection lifecycle
- [x] 5.6.27 Test chat component functionality
- [x] 5.6.28 Test dynamic layout calculations
- [x] 5.6.29 Test panel toggle operations
- [x] 5.6.30 Test keyboard shortcut handling
- [ ] 5.6.31 Test file tree navigation operations
- [ ] 5.6.32 Test editor content synchronization
- [ ] 5.6.33 Test command palette filtering
- [ ] 5.6.34 Test error recovery mechanisms

#### Integration Tests:
Create tests in `tui/test/integration_test.go` to verify:
- [x] 5.6.35 Test full TUI startup and initialization
- [x] 5.6.36 Test Phoenix channel communication
- [x] 5.6.37 Test file analysis workflow
- [x] 5.6.38 Test code generation streaming
- [x] 5.6.39 Test chat-focused interface workflow
- [x] 5.6.40 Test panel visibility toggling
- [ ] 5.6.41 Test concurrent operations
- [ ] 5.6.42 Test reconnection after disconnect
- [ ] 5.6.43 Test state persistence

#### Implementation Highlights:

**Chat-Focused Architecture:**
- Implemented chat as the primary interface with optional file tree and editor panels
- Created seamless integration between chat messages and command execution
- Built dynamic layout system that adapts based on panel visibility
- Added comprehensive keyboard shortcuts for efficient navigation

**Key Features Implemented:**
- Complete chat component with scrollable history and multi-line input
- Dynamic layout system with toggleable panels
- Integration with unified command system through chat interface
- Comprehensive modal dialog system
- Full Phoenix WebSocket integration with mock interface for development
- Extensive test coverage with both unit and integration tests

See `tui/notes/features/001-chat-focused-interface.md` for detailed implementation documentation.

### 5.7 System Error Handling Enhancement ✅ Completed

Implement comprehensive error handling and reporting system improvements to ensure robust system operation.

**Status**: Successfully implemented Tower error reporting configuration fixes and system stability improvements.

#### Tasks:
- [x] 5.7.1 Fix Tower error reporting configuration:
  - [x] 5.7.1.1 Correct Tower reporter configuration format in dev.exs and prod.exs
  - [x] 5.7.1.2 Change from keyword list to map format for reporters
  - [x] 5.7.1.3 Use correct Tower.EphemeralReporter instead of non-existent Tower.LogReporter
  - [x] 5.7.1.4 Move reporter-specific options to separate config blocks
- [x] 5.7.2 Create comprehensive error testing:
  - [x] 5.7.2.1 Add test to validate Tower configuration format
  - [x] 5.7.2.2 Ensure reporters are configured as module atoms
  - [x] 5.7.2.3 Verify reporter module availability
- [x] 5.7.3 Improve system stability:
  - [x] 5.7.3.1 Fix command processor startup in application supervision tree
  - [x] 5.7.3.2 Resolve JSON encoding issues in CLI channels
  - [x] 5.7.3.3 Add proper error handling for double JSON encoding

#### Implementation Details:

**Tower Configuration Fixes:**
```elixir
# Before (incorrect):
config :tower,
  reporters: [
    [module: Tower.LogReporter, level: :error]  # Keyword list - wrong
  ]

# After (correct):
config :tower,
  reporters: [Tower.EphemeralReporter],  # Module atom - correct
  log_level: :error                      # Separate config option
```

**Files Modified:**
- `config/dev.exs` - Fixed Tower reporter configuration
- `config/prod.exs` - Fixed TowerEmail configuration and examples
- `test/rubber_duck/tower_config_test.exs` - Added configuration validation test
- `lib/rubber_duck/application.ex` - Fixed Commands.Processor supervision
- `lib/rubber_duck_web/channels/cli_channel.ex` - Fixed JSON encoding issues

See `notes/fixes/001-tower-reporter-configuration.md` for detailed fix documentation.

### 5.8 Phase 5 Integration Tests

Create comprehensive integration tests in `test/integration/phase_5_test.exs` to verify:
- [ ] 5.8.1 Test LiveView and Channel coordination
- [ ] 5.8.2 Test CLI triggers real-time updates
- [ ] 5.8.3 Test settings sync across interfaces
- [ ] 5.8.4 Test analysis results consistency
- [ ] 5.8.5 Test multiple concurrent WebSocket connections
- [ ] 5.8.6 Test LiveView rapid update handling
- [ ] 5.8.7 Test TUI state management with chat interface
- [ ] 5.8.8 Test dynamic LLM configuration across all interfaces
- [ ] 5.8.9 Test unified command system consistency
- [ ] 5.8.10 Test error handling and recovery mechanisms

---

## Phase 6: Conversational AI System

This phase implements a memory-enhanced conversational AI system that provides natural language interaction across all client interfaces (CLI, LiveView, TUI, WebSocket). The system integrates with the 3-tier memory architecture to maintain context and supports both chat and command-based interactions.

### 6.1 Memory-Enhanced Conversation Engine

Implement the core conversation engine using GenServer architecture with ETS-based short-term memory and pattern extraction capabilities.

#### Tasks:
- [ ] 6.1.1 Create `RubberDuck.Conversation.Engine` GenServer:
  - [ ] 6.1.1.1 Process-per-conversation isolation
  - [ ] 6.1.1.2 ETS table initialization for short-term memory
  - [ ] 6.1.1.3 Context window management
  - [ ] 6.1.1.4 Last activity tracking
- [ ] 6.1.2 Implement conversation state management:
  - [ ] 6.1.2.1 Message storage in ETS with timestamps
  - [ ] 6.1.2.2 Context window updates with relevance scoring
  - [ ] 6.1.2.3 Pattern extraction triggers
  - [ ] 6.1.2.4 State persistence hooks
- [ ] 6.1.3 Create `RubberDuck.Conversation.PatternExtractor`:
  - [ ] 6.1.3.1 Sliding window buffer implementation
  - [ ] 6.1.3.2 Intent extraction from messages
  - [ ] 6.1.3.3 Pattern frequency analysis
  - [ ] 6.1.3.4 Mid-term storage persistence
- [ ] 6.1.4 Build context retrieval system:
  - [ ] 6.1.4.1 Recent message retrieval from ETS
  - [ ] 6.1.4.2 Pattern matching from mid-term memory
  - [ ] 6.1.4.3 Long-term context integration
  - [ ] 6.1.4.4 Context relevance scoring
- [ ] 6.1.5 Implement conversation lifecycle:
  - [ ] 6.1.5.1 Conversation initialization
  - [ ] 6.1.5.2 Automatic cleanup after inactivity
  - [ ] 6.1.5.3 State snapshots for recovery
  - [ ] 6.1.5.4 Graceful shutdown handling
- [ ] 6.1.6 Create Registry-based process tracking
- [ ] 6.1.7 Add telemetry instrumentation
- [ ] 6.1.8 Implement conversation metrics collection
- [ ] 6.1.9 Create conversation export functionality
- [ ] 6.1.10 Add conversation search capabilities

#### Unit Tests:
- [ ] 6.1.11 Test conversation engine initialization
- [ ] 6.1.12 Test message storage and retrieval
- [ ] 6.1.13 Test pattern extraction accuracy
- [ ] 6.1.14 Test context window management
- [ ] 6.1.15 Test conversation lifecycle and cleanup

### 6.2 Multi-Client Phoenix Channel Architecture

Build Phoenix Channels infrastructure supporting heterogeneous clients with adaptive formatting and real-time communication.

#### Tasks:
- [ ] 6.2.1 Create `RubberDuckWeb.ConversationChannel`:
  - [ ] 6.2.1.1 Client type detection on join
  - [ ] 6.2.1.2 Capability negotiation
  - [ ] 6.2.1.3 Format configuration per client
  - [ ] 6.2.1.4 Conversation engine connection
- [ ] 6.2.2 Implement message handling:
  - [ ] 6.2.2.1 Command message processing
  - [ ] 6.2.2.2 Chat message processing
  - [ ] 6.2.2.3 Mixed input handling
  - [ ] 6.2.2.4 Stream message support
- [ ] 6.2.3 Build response formatting system:
  - [ ] 6.2.3.1 Text formatting for CLI
  - [ ] 6.2.3.2 HTML formatting for LiveView
  - [ ] 6.2.3.3 ANSI formatting for TUI
  - [ ] 6.2.3.4 JSON formatting for WebSocket
- [ ] 6.2.4 Create shared communication protocol:
  - [ ] 6.2.4.1 MessagePack serialization setup
  - [ ] 6.2.4.2 Version negotiation protocol
  - [ ] 6.2.4.3 Graceful degradation logic
  - [ ] 6.2.4.4 Protocol documentation
- [ ] 6.2.5 Implement broadcast mechanisms:
  - [ ] 6.2.5.1 Selective client broadcasting
  - [ ] 6.2.5.2 Presence-aware messaging
  - [ ] 6.2.5.3 Typing indicators
  - [ ] 6.2.5.4 Read receipts
- [ ] 6.2.6 Add channel authorization
- [ ] 6.2.7 Create rate limiting per channel
- [ ] 6.2.8 Implement channel metrics
- [ ] 6.2.9 Build channel state recovery
- [ ] 6.2.10 Add channel event logging

#### Unit Tests:
- [ ] 6.2.11 Test channel join with different clients
- [ ] 6.2.12 Test message routing and processing
- [ ] 6.2.13 Test format adaptation
- [ ] 6.2.14 Test broadcast mechanisms
- [ ] 6.2.15 Test rate limiting enforcement

### 6.3 Conversational Context Management

Implement sophisticated context management with DynamicSupervisor orchestration and memory system integration.

#### Tasks:
- [ ] 6.3.1 Create `RubberDuck.Conversation.Supervisor`:
  - [ ] 6.3.1.1 DynamicSupervisor configuration
  - [ ] 6.3.1.2 Child spec definitions
  - [ ] 6.3.1.3 Restart strategies
  - [ ] 6.3.1.4 Process monitoring
- [ ] 6.3.2 Build `RubberDuck.Conversation.MemoryBridge`:
  - [ ] 6.3.2.1 Short-term ETS storage integration
  - [ ] 6.3.2.2 Mid-term pattern buffer management
  - [ ] 6.3.2.3 Long-term PostgreSQL persistence
  - [ ] 6.3.2.4 Significance evaluation logic
- [ ] 6.3.3 Implement `RubberDuck.ConversationPresence`:
  - [ ] 6.3.3.1 User tracking per conversation
  - [ ] 6.3.3.2 Multi-client presence support
  - [ ] 6.3.3.3 Participant listing
  - [ ] 6.3.3.4 Connection metadata tracking
- [ ] 6.3.4 Create `RubberDuck.Conversation.Recovery`:
  - [ ] 6.3.4.1 Snapshot loading from PostgreSQL
  - [ ] 6.3.4.2 Event replay mechanisms
  - [ ] 6.3.4.3 State reconstruction logic
  - [ ] 6.3.4.4 Fallback strategies
- [ ] 6.3.5 Build context aggregation system
- [ ] 6.3.6 Implement context pruning strategies
- [ ] 6.3.7 Add context export/import
- [ ] 6.3.8 Create context analytics
- [ ] 6.3.9 Build context versioning
- [ ] 6.3.10 Add context encryption

#### Unit Tests:
- [ ] 6.3.11 Test supervisor lifecycle management
- [ ] 6.3.12 Test memory bridge operations
- [ ] 6.3.13 Test presence tracking accuracy
- [ ] 6.3.14 Test recovery mechanisms
- [ ] 6.3.15 Test context aggregation

### 6.4 Command-Chat Hybrid Interface

Build intelligent intent classification and command suggestion system for seamless mixed interactions.

#### Tasks:
- [ ] 6.4.1 Create `RubberDuck.Conversation.HybridInterface`:
  - [ ] 6.4.1.1 Command pattern recognition
  - [ ] 6.4.1.2 Natural language classification
  - [ ] 6.4.1.3 Mixed intent extraction
  - [ ] 6.4.1.4 Context-aware processing
- [ ] 6.4.2 Implement command extraction:
  - [ ] 6.4.2.1 Regex-based command matching
  - [ ] 6.4.2.2 Keyword detection logic
  - [ ] 6.4.2.3 LLM-based intent analysis
  - [ ] 6.4.2.4 Command argument parsing
- [ ] 6.4.3 Build `RubberDuck.Conversation.CommandSuggester`:
  - [ ] 6.4.3.1 Prefix-based filtering
  - [ ] 6.4.3.2 Context relevance scoring
  - [ ] 6.4.3.3 Usage history integration
  - [ ] 6.4.3.4 Project-aware suggestions
- [ ] 6.4.4 Create unified command execution:
  - [ ] 6.4.4.1 Command processor integration
  - [ ] 6.4.4.2 Context injection
  - [ ] 6.4.4.3 Result formatting
  - [ ] 6.4.4.4 Error handling
- [ ] 6.4.5 Implement chat processing:
  - [ ] 6.4.5.1 LLM service integration with dynamic configuration
  - [ ] 6.4.5.2 Context enhancement
  - [ ] 6.4.5.3 Response streaming
  - [ ] 6.4.5.4 Feedback collection
- [ ] 6.4.6 Add command history tracking
- [ ] 6.4.7 Create command aliases system
- [ ] 6.4.8 Build command help system
- [ ] 6.4.9 Implement command shortcuts
- [ ] 6.4.10 Add command templates

#### Unit Tests:
- [ ] 6.4.11 Test intent classification accuracy
- [ ] 6.4.12 Test command extraction
- [ ] 6.4.13 Test suggestion relevance
- [ ] 6.4.14 Test mixed input handling
- [ ] 6.4.15 Test command execution flow

### 6.5 Performance & Security Implementation

Optimize performance with ETS configurations and implement comprehensive security measures.

#### Tasks:
- [ ] 6.5.1 Configure ETS optimization:
  - [ ] 6.5.1.1 Read/write concurrency flags
  - [ ] 6.5.1.2 Memory limits per table
  - [ ] 6.5.1.3 Compaction scheduling
  - [ ] 6.5.1.4 Performance monitoring
- [ ] 6.5.2 Implement rate limiting:
  - [ ] 6.5.2.1 Hammer integration
  - [ ] 6.5.2.2 Per-user limits (100/hour)
  - [ ] 6.5.2.3 Per-conversation limits
  - [ ] 6.5.2.4 Adaptive throttling
- [ ] 6.5.3 Add authentication system:
  - [ ] 6.5.3.1 Token generation
  - [ ] 6.5.3.2 Token validation
  - [ ] 6.5.3.3 Session management
  - [ ] 6.5.3.4 Multi-factor support
- [ ] 6.5.4 Create encryption layer:
  - [ ] 6.5.4.1 AES-256-GCM implementation
  - [ ] 6.5.4.2 Key rotation system
  - [ ] 6.5.4.3 Encrypted storage
  - [ ] 6.5.4.4 Secure transmission
- [ ] 6.5.5 Build monitoring infrastructure:
  - [ ] 6.5.5.1 Telemetry events
  - [ ] 6.5.5.2 Metrics aggregation
  - [ ] 6.5.5.3 Alert configuration
  - [ ] 6.5.5.4 Dashboard creation
- [ ] 6.5.6 Implement circuit breakers
- [ ] 6.5.7 Add request validation
- [ ] 6.5.8 Create audit logging
- [ ] 6.5.9 Build anomaly detection
- [ ] 6.5.10 Add compliance features

#### Unit Tests:
- [ ] 6.5.11 Test ETS performance under load
- [ ] 6.5.12 Test rate limiting accuracy
- [ ] 6.5.13 Test authentication flows
- [ ] 6.5.14 Test encryption/decryption
- [ ] 6.5.15 Test monitoring accuracy

### 6.6 Phase 6 Integration Tests

Create comprehensive integration tests in `test/integration/phase_6_test.exs` to verify:
- [ ] 6.6.1 Test end-to-end conversation flow
- [ ] 6.6.2 Test multi-client concurrent conversations
- [ ] 6.6.3 Test memory system integration
- [ ] 6.6.4 Test command-chat switching
- [ ] 6.6.5 Test 1K+ concurrent conversations
- [ ] 6.6.6 Test sub-100ms response latency
- [ ] 6.6.7 Test recovery after crashes
- [ ] 6.6.8 Test security measures
- [ ] 6.6.9 Test dynamic LLM configuration in conversations
- [ ] 6.6.10 Test unified command integration

---

## Phase 7: Planning Enhancement System

This phase implements a sophisticated planning system based on the LLM-Modulo framework, where LLMs generate plans that are validated by external critics. The system provides hierarchical task decomposition, repository-level planning, and dynamic execution with ReAct-based adaptation.

### 7.1 Planning Domain & Resources

Set up the core Ash domain and resources for the planning system, including plan tracking, task management, and validation results.

#### Tasks:
- [ ] 7.1.1 Create Planning domain module with Ash.Domain
- [ ] 7.1.2 Design Plan resource with attributes:
  - [ ] 7.1.2.1 Basic fields (id, name, description, type, status)
  - [ ] 7.1.2.2 Context storage (project context, dependencies, constraints)
  - [ ] 7.1.2.3 Validation results and execution history
  - [ ] 7.1.2.4 Timestamps and metadata
- [ ] 7.1.3 Design Task resource with attributes:
  - [ ] 7.1.3.1 Task details (name, description, complexity, status)
  - [ ] 7.1.3.2 Dependencies and ordering information
  - [ ] 7.1.3.3 Success criteria and validation rules
  - [ ] 7.1.3.4 Execution metadata and results
- [ ] 7.1.4 Create Constraint resource for plan constraints
- [ ] 7.1.5 Create Validation resource for tracking validation results
- [ ] 7.1.6 Set up relationships between resources
- [ ] 7.1.7 Create database migrations for planning tables
- [ ] 7.1.8 Implement Ash actions for CRUD operations
- [ ] 7.1.9 Add authorization policies for plan access
- [ ] 7.1.10 Create GraphQL API for planning resources

#### Unit Tests:
- [ ] 7.1.11 Test Plan resource creation and validation
- [ ] 7.1.12 Test Task resource with dependency management
- [ ] 7.1.13 Test constraint enforcement
- [ ] 7.1.14 Test validation result tracking
- [ ] 7.1.15 Test authorization policies

### 7.2 Task Decomposition Engine

Implement the task decomposition engine that breaks down high-level requests into actionable tasks using LLM-guided decomposition with validation.

#### Tasks:
- [ ] 7.2.1 Create TaskDecomposer engine using RubberDuck.Engine behavior
- [ ] 7.2.2 Implement decomposition strategies:
  - [ ] 7.2.2.1 Linear decomposition for simple tasks
  - [ ] 7.2.2.2 Hierarchical decomposition for complex features
  - [ ] 7.2.2.3 Tree-of-Thought decomposition for exploratory tasks
- [ ] 7.2.3 Integrate with CoT for reasoning during decomposition
- [ ] 7.2.4 Create planning-specific prompt templates
- [ ] 7.2.5 Implement dependency graph builder
- [ ] 7.2.6 Add task complexity estimation
- [ ] 7.2.7 Create success criteria generator
- [ ] 7.2.8 Implement task validation with critics
- [ ] 7.2.9 Add support for iterative refinement
- [ ] 7.2.10 Create planning pattern library
- [ ] 7.2.11 Integrate with dynamic LLM configuration

#### Unit Tests:
- [ ] 7.2.12 Test simple task decomposition
- [ ] 7.2.13 Test complex feature decomposition
- [ ] 7.2.14 Test dependency graph generation
- [ ] 7.2.15 Test complexity estimation accuracy
- [ ] 7.2.16 Test iterative refinement process

### 7.3 Critics System (Hard & Soft Critics)

Implement the external critics system for plan validation, including hard critics for correctness and soft critics for quality.

#### Tasks:
- [ ] 7.3.1 Define CriticBehaviour for critic implementations
- [ ] 7.3.2 Implement HardCritic module:
  - [ ] 7.3.2.1 Syntax validation using AST parser
  - [ ] 7.3.2.2 Dependency validation and cycle detection
  - [ ] 7.3.2.3 Constraint satisfaction checking
  - [ ] 7.3.2.4 Feasibility analysis
  - [ ] 7.3.2.5 Resource requirement validation
- [ ] 7.3.3 Implement SoftCritic module:
  - [ ] 7.3.3.1 Code style and convention checking
  - [ ] 7.3.3.2 Best practice validation
  - [ ] 7.3.3.3 Performance impact analysis
  - [ ] 7.3.3.4 Security consideration checking
- [ ] 7.3.4 Create critic orchestrator for running multiple critics
- [ ] 7.3.5 Implement validation result aggregation
- [ ] 7.3.6 Add critic configuration system
- [ ] 7.3.7 Create custom critic plugin support
- [ ] 7.3.8 Implement validation caching
- [ ] 7.3.9 Add validation explanation generation
- [ ] 7.3.10 Create validation dashboard UI

#### Unit Tests:
- [ ] 7.3.11 Test syntax validation critic
- [ ] 7.3.12 Test dependency cycle detection
- [ ] 7.3.13 Test constraint satisfaction
- [ ] 7.3.14 Test soft critic suggestions
- [ ] 7.3.15 Test critic orchestration

### 7.4 ReAct-Based Execution Framework

Build the ReAct (Reasoning-Acting) execution framework for dynamic plan execution with observation and adaptation.

#### Tasks:
- [ ] 7.4.1 Create PlanExecutor GenServer
- [ ] 7.4.2 Implement ReAct loop:
  - [ ] 7.4.2.1 Thought generation for task analysis
  - [ ] 7.4.2.2 Action execution with monitoring
  - [ ] 7.4.2.3 Observation collection and analysis
  - [ ] 7.4.2.4 Dynamic plan adjustment
- [ ] 7.4.3 Integrate with existing workflow engine
- [ ] 7.4.4 Add execution state management
- [ ] 7.4.5 Implement failure recovery strategies
- [ ] 7.4.6 Create execution monitoring hooks
- [ ] 7.4.7 Add real-time progress tracking
- [ ] 7.4.8 Implement rollback capabilities
- [ ] 7.4.9 Create execution history tracking
- [ ] 7.4.10 Add execution analytics
- [ ] 7.4.11 Integrate with dynamic LLM configuration

#### Unit Tests:
- [ ] 7.4.12 Test basic ReAct execution loop
- [ ] 7.4.13 Test failure recovery
- [ ] 7.4.14 Test dynamic plan adjustment
- [ ] 7.4.15 Test rollback functionality
- [ ] 7.4.16 Test concurrent task execution

### 7.5 Repository-Level Planning

Implement repository-wide planning capabilities for multi-file changes and architectural modifications.

#### Tasks:
- [ ] 7.5.1 Create RepositoryPlanner module
- [ ] 7.5.2 Implement change impact analysis:
  - [ ] 7.5.2.1 File dependency graph building
  - [ ] 7.5.2.2 Change propagation analysis
  - [ ] 7.5.2.3 Risk assessment for changes
- [ ] 7.5.3 Build change sequencing algorithm
- [ ] 7.5.4 Implement parallel change detection
- [ ] 7.5.5 Create migration plan generator
- [ ] 7.5.6 Add test impact analysis
- [ ] 7.5.7 Implement change preview system
- [ ] 7.5.8 Create conflict resolution strategies
- [ ] 7.5.9 Add architectural pattern detection
- [ ] 7.5.10 Implement change validation pipeline

#### Unit Tests:
- [ ] 7.5.11 Test impact analysis accuracy
- [ ] 7.5.12 Test change sequencing
- [ ] 7.5.13 Test parallel change detection
- [ ] 7.5.14 Test migration plan generation
- [ ] 7.5.15 Test conflict resolution

### 7.6 Planning DSL with Spark

Create a domain-specific language for defining plans using the Spark framework.

#### Tasks:
- [ ] 7.6.1 Design Planning DSL structure
- [ ] 7.6.2 Implement Spark DSL sections:
  - [ ] 7.6.2.1 Plan section for plan metadata
  - [ ] 7.6.2.2 Task entity for task definitions
  - [ ] 7.6.2.3 Constraint entity for constraints
  - [ ] 7.6.2.4 Validation entity for custom validators
- [ ] 7.6.3 Create DSL compiler
- [ ] 7.6.4 Implement DSL validation
- [ ] 7.6.5 Add DSL to Ash resource transformation
- [ ] 7.6.6 Create DSL documentation generator
- [ ] 7.6.7 Implement DSL migration support
- [ ] 7.6.8 Add DSL syntax highlighting
- [ ] 7.6.9 Create example plan templates
- [ ] 7.6.10 Build DSL testing framework

#### Unit Tests:
- [ ] 7.6.11 Test DSL parsing
- [ ] 7.6.12 Test DSL compilation
- [ ] 7.6.13 Test DSL validation
- [ ] 7.6.14 Test resource transformation
- [ ] 7.6.15 Test DSL error handling

---


## Phase 8: MCP (Model Context Protocol) Integration

This phase implements comprehensive Model Context Protocol (MCP) support, enabling RubberDuck to connect with a vast ecosystem of external tools and data sources while exposing its own capabilities through standardized interfaces. MCP acts as a universal adapter for AI systems, solving the integration complexity problem and enabling powerful new workflows.

### 8.1 MCP Client Implementation

Implement the MCP client infrastructure using Hermes MCP, enabling RubberDuck to connect to and utilize external MCP servers for enhanced functionality.

#### Tasks:
- [ ] 8.1.1 Add Hermes MCP dependency to mix.exs
- [ ] 8.1.2 Create `RubberDuck.MCP.Client` module structure
- [ ] 8.1.3 Implement transport adapters:
  - [ ] 8.1.3.1 STDIO transport for local MCP servers
  - [ ] 8.1.3.2 HTTP/SSE transport for remote servers
  - [ ] 8.1.3.3 WebSocket transport for real-time connections
- [ ] 8.1.4 Build client supervisor with OTP patterns:
  - [ ] 8.1.4.1 DynamicSupervisor for client spawning
  - [ ] 8.1.4.2 Registry for client tracking
  - [ ] 8.1.4.3 Connection pool management
- [ ] 8.1.5 Create capability negotiation:
  - [ ] 8.1.5.1 Tool discovery
  - [ ] 8.1.5.2 Resource enumeration
  - [ ] 8.1.5.3 Prompt template retrieval
- [ ] 8.1.6 Implement authentication mechanisms:
  - [ ] 8.1.6.1 OAuth 2.1 support
  - [ ] 8.1.6.2 API key authentication
  - [ ] 8.1.6.3 Certificate-based auth
- [ ] 8.1.7 Add client health monitoring:
  - [ ] 8.1.7.1 Heartbeat implementation
  - [ ] 8.1.7.2 Automatic reconnection
  - [ ] 8.1.7.3 Circuit breaker per server
- [ ] 8.1.8 Create request/response correlation
- [ ] 8.1.9 Implement client-side caching
- [ ] 8.1.10 Add telemetry for MCP operations

#### Unit Tests:
Create tests in `test/rubber_duck/mcp/client_test.exs` to verify:
- [ ] 8.1.11 Test client initialization with different transports
- [ ] 8.1.12 Test capability negotiation protocol
- [ ] 8.1.13 Test tool discovery and invocation
- [ ] 8.1.14 Test resource access patterns
- [ ] 8.1.15 Test authentication flows
- [ ] 8.1.16 Test reconnection on disconnect
- [ ] 8.1.17 Test concurrent requests handling
- [ ] 8.1.18 Test circuit breaker behavior

### 8.2 MCP Server Implementation

Create RubberDuck's own MCP server to expose its capabilities as standardized tools that other AI systems can leverage.

#### Tasks:
- [ ] 8.2.1 Create `RubberDuck.MCP.Server` module
- [ ] 8.2.2 Implement server transports:
  - [ ] 8.2.2.1 STDIO server for local access
  - [ ] 8.2.2.2 HTTP/SSE server with Plug
  - [ ] 8.2.2.3 WebSocket server integration
- [ ] 8.2.3 Build tool exposure framework:
  - [ ] 8.2.3.1 AST parsing tools
  - [ ] 8.2.3.2 Code analysis tools
  - [ ] 8.2.3.3 Code generation tools
  - [ ] 8.2.3.4 Memory access tools
- [ ] 8.2.4 Create resource providers:
  - [ ] 8.2.4.1 Project file resources
  - [ ] 8.2.4.2 Analysis result resources
  - [ ] 8.2.4.3 Memory context resources
- [ ] 8.2.5 Implement prompt templates:
  - [ ] 8.2.5.1 Code review prompts
  - [ ] 8.2.5.2 Refactoring prompts
  - [ ] 8.2.5.3 Documentation prompts
- [ ] 8.2.6 Add server authorization:
  - [ ] 8.2.6.1 Per-tool permissions
  - [ ] 8.2.6.2 Resource access control
  - [ ] 8.2.6.3 Rate limiting per client
- [ ] 8.2.7 Create server health endpoints
- [ ] 8.2.8 Implement server-side logging
- [ ] 8.2.9 Add connection management
- [ ] 8.2.10 Build server configuration DSL

#### Unit Tests:
Create tests in `test/rubber_duck/mcp/server_test.exs` to verify:
- [ ] 8.2.11 Test server initialization and startup
- [ ] 8.2.12 Test tool registration and exposure
- [ ] 8.2.13 Test resource provider functionality
- [ ] 8.2.14 Test authorization enforcement
- [ ] 8.2.15 Test concurrent client handling
- [ ] 8.2.16 Test rate limiting behavior
- [ ] 8.2.17 Test health check responses

### 8.3 MCP Tool Registry

Build a comprehensive registry system for managing MCP tools from various sources with capability-based discovery.

#### Tasks:
- [ ] 8.3.1 Create `RubberDuck.MCP.Registry` module
- [ ] 8.3.2 Implement tool cataloging:
  - [ ] 8.3.2.1 Internal tool registration
  - [ ] 8.3.2.2 External tool discovery
  - [ ] 8.3.2.3 Tool metadata storage
- [ ] 8.3.3 Build capability indexing:
  - [ ] 8.3.3.1 Semantic capability matching
  - [ ] 8.3.3.2 Input/output type tracking
  - [ ] 8.3.3.3 Performance characteristics
- [ ] 8.3.4 Create tool composition engine:
  - [ ] 8.3.4.1 Sequential tool chaining
  - [ ] 8.3.4.2 Parallel tool execution
  - [ ] 8.3.4.3 Conditional tool selection
- [ ] 8.3.5 Add tool versioning support
- [ ] 8.3.6 Implement tool quality metrics:
  - [ ] 8.3.6.1 Success rate tracking
  - [ ] 8.3.6.2 Latency monitoring
  - [ ] 8.3.6.3 Error rate analysis
- [ ] 8.3.7 Create tool recommendation system
- [ ] 8.3.8 Build tool testing framework
- [ ] 8.3.9 Add tool documentation generator
- [ ] 8.3.10 Implement tool deprecation handling

#### Unit Tests:
Create tests in `test/rubber_duck/mcp/registry_test.exs` to verify:
- [ ] 8.3.11 Test tool registration and retrieval
- [ ] 8.3.12 Test capability-based discovery
- [ ] 8.3.13 Test tool composition patterns
- [ ] 8.3.14 Test quality metrics tracking
- [ ] 8.3.15 Test recommendation accuracy
- [ ] 8.3.16 Test version compatibility

### 8.4 MCP Integration with Existing Systems

Create seamless integration between MCP and RubberDuck's existing architecture, enhancing rather than replacing current functionality.

#### Tasks:
- [ ] 8.4.1 Integrate with LLM providers:
  - [ ] 8.4.1.1 Add MCP to provider abstraction
  - [ ] 8.4.1.2 Expose provider capabilities via MCP
  - [ ] 8.4.1.3 Enable MCP-based provider selection with dynamic configuration
- [ ] 8.4.2 Connect to memory system:
  - [ ] 8.4.2.1 Expose memory as MCP resources
  - [ ] 8.4.2.2 Enable MCP tool memory updates
  - [ ] 8.4.2.3 Create memory synchronization
- [ ] 8.4.3 Enhance workflow system:
  - [ ] 8.4.3.1 Add MCP tool steps to Reactor
  - [ ] 8.4.3.2 Create MCP-aware workflows
  - [ ] 8.4.3.3 Enable dynamic MCP tool selection
- [ ] 8.4.4 Extend engine system:
  - [ ] 8.4.4.1 Create MCP engine adapter
  - [ ] 8.4.4.2 Enable engines as MCP tools
  - [ ] 8.4.4.3 Add MCP-based engine discovery
- [ ] 8.4.5 Update context building:
  - [ ] 8.4.5.1 Include MCP tool states
  - [ ] 8.4.5.2 Add MCP resource context
  - [ ] 8.4.5.3 Enable MCP-aware prompts
- [ ] 8.4.6 Enhance agent system:
  - [ ] 8.4.6.1 Give agents MCP tool access
  - [ ] 8.4.6.2 Create MCP-specialized agents
  - [ ] 8.4.6.3 Enable agent tool learning
- [ ] 8.4.7 Update CLI for MCP commands with unified command system
- [ ] 8.4.8 Add LiveView MCP tool browser
- [ ] 8.4.9 Create MCP debugging tools
- [ ] 8.4.10 Build integration test suite

#### Unit Tests:
Create tests in `test/rubber_duck/mcp/integration_test.exs` to verify:
- [ ] 8.4.11 Test LLM provider MCP integration
- [ ] 8.4.12 Test memory system integration
- [ ] 8.4.13 Test workflow MCP steps
- [ ] 8.4.14 Test engine MCP adaptation
- [ ] 8.4.15 Test context enhancement
- [ ] 8.4.16 Test agent MCP usage
- [ ] 8.4.17 Test end-to-end MCP flows

### 8.5 MCP Security & Performance

Implement comprehensive security measures and performance optimizations for MCP integration.

#### Tasks:
- [ ] 8.5.1 Implement security measures:
  - [ ] 8.5.1.1 Input validation for all MCP calls
  - [ ] 8.5.1.2 Command injection prevention
  - [ ] 8.5.1.3 Path traversal protection
  - [ ] 8.5.1.4 Secrets management
- [ ] 8.5.2 Add authentication layer:
  - [ ] 8.5.2.1 mTLS for server connections
  - [ ] 8.5.2.2 JWT token validation
  - [ ] 8.5.2.3 API key rotation
- [ ] 8.5.3 Create audit logging:
  - [ ] 8.5.3.1 Tool invocation tracking
  - [ ] 8.5.3.2 Resource access logging
  - [ ] 8.5.3.3 Security event monitoring
- [ ] 8.5.4 Implement performance optimization:
  - [ ] 8.5.4.1 Connection pooling
  - [ ] 8.5.4.2 Request batching
  - [ ] 8.5.4.3 Result caching
  - [ ] 8.5.4.4 Lazy loading
- [ ] 8.5.5 Add rate limiting:
  - [ ] 8.5.5.1 Per-tool rate limits
  - [ ] 8.5.5.2 Global rate limiting
  - [ ] 8.5.5.3 Adaptive throttling
- [ ] 8.5.6 Create monitoring dashboard:
  - [ ] 8.5.6.1 MCP metrics visualization
  - [ ] 8.5.6.2 Performance analytics
  - [ ] 8.5.6.3 Security alerts
- [ ] 8.5.7 Implement failover strategies
- [ ] 8.5.8 Add request prioritization
- [ ] 8.5.9 Create security scanner
- [ ] 8.5.10 Build performance profiler

#### Unit Tests:
Create tests in `test/rubber_duck/mcp/security_test.exs` to verify:
- [ ] 8.5.11 Test input validation effectiveness
- [ ] 8.5.12 Test injection attack prevention
- [ ] 8.5.13 Test authentication mechanisms
- [ ] 8.5.14 Test audit logging completeness
- [ ] 8.5.15 Test rate limiting enforcement
- [ ] 8.5.16 Test performance under load
- [ ] 8.5.17 Test failover behavior

### 8.6 Advanced MCP Patterns

Implement sophisticated MCP usage patterns that showcase the protocol's full potential for AI-assisted development.

#### Tasks:
- [ ] 8.6.1 Create multi-tool workflows:
  - [ ] 8.6.1.1 GitHub + AWS integration
  - [ ] 8.6.1.2 Database + API composition
  - [ ] 8.6.1.3 Browser + Code analysis
- [ ] 8.6.2 Build reactive MCP systems:
  - [ ] 8.6.2.1 Event-driven tool activation
  - [ ] 8.6.2.2 Proactive context updates
  - [ ] 8.6.2.3 Automatic tool suggestions
- [ ] 8.6.3 Implement sampling patterns:
  - [ ] 8.6.3.1 Tool-initiated LLM calls with dynamic configuration
  - [ ] 8.6.3.2 Iterative refinement loops
  - [ ] 8.6.3.3 Multi-step reasoning
- [ ] 8.6.4 Create federated MCP networks:
  - [ ] 8.6.4.1 Cross-server tool sharing
  - [ ] 8.6.4.2 Distributed tool execution
  - [ ] 8.6.4.3 Consensus mechanisms
- [ ] 8.6.5 Build MCP marketplace integration:
  - [ ] 8.6.5.1 Tool discovery service
  - [ ] 8.6.5.2 Quality ratings
  - [ ] 8.6.5.3 Usage analytics
- [ ] 8.6.6 Add MCP-based plugins
- [ ] 8.6.7 Create MCP workflow templates
- [ ] 8.6.8 Implement MCP best practices
- [ ] 8.6.9 Build MCP testing harness
- [ ] 8.6.10 Create MCP documentation

#### Unit Tests:
Create tests in `test/rubber_duck/mcp/advanced_test.exs` to verify:
- [ ] 8.6.11 Test multi-tool coordination
- [ ] 8.6.12 Test reactive system behavior
- [ ] 8.6.13 Test sampling pattern execution
- [ ] 8.6.14 Test federated operations
- [ ] 8.6.15 Test marketplace integration
- [ ] 8.6.16 Test advanced error handling

### 8.7 Phase 8 Integration Tests

Create comprehensive integration tests in `test/integration/phase_8_test.exs` to verify:
- [ ] 8.7.1 Test complete MCP client-server communication
- [ ] 8.7.2 Test tool discovery and invocation pipeline
- [ ] 8.7.3 Test MCP integration with existing systems
- [ ] 8.7.4 Test security measures effectiveness
- [ ] 8.7.5 Test performance optimization impact
- [ ] 8.7.6 Test advanced pattern implementations
- [ ] 8.7.7 Test multi-server MCP scenarios
- [ ] 8.7.8 Test MCP-enhanced code generation quality
- [ ] 8.7.9 Test MCP tool composition workflows
- [ ] 8.7.10 Test failover and recovery mechanisms

---

## Phase 9: Advanced Features & Production Readiness

This final phase implements production-critical features including background job processing, security measures, deployment configurations, and performance optimizations. This phase ensures the system is ready for real-world usage at scale.

### 9.1 Background Job Processing with Oban

Implement asynchronous job processing for resource-intensive operations like project indexing and batch analysis.

#### Tasks:
- [ ] 9.1.1 Add Oban dependency and configuration
- [ ] 9.1.2 Create Oban database migrations
- [ ] 9.1.3 Set up job queues:
  - [ ] 9.1.3.1 `:indexing` - File and project indexing
  - [ ] 9.1.3.2 `:analysis` - Code analysis jobs
  - [ ] 9.1.3.3 `:generation` - Batch code generation
  - [ ] 9.1.3.4 `:notification` - User notifications
- [ ] 9.1.4 Implement job workers:
  - [ ] 9.1.4.1 `ProjectIndexer` - Index entire projects
  - [ ] 9.1.4.2 `FileAnalyzer` - Analyze individual files
  - [ ] 9.1.4.3 `BatchGenerator` - Generate multiple files
  - [ ] 9.1.4.4 `ReportGenerator` - Create analysis reports
- [ ] 9.1.5 Add job scheduling for periodic tasks
- [ ] 9.1.6 Implement job progress tracking
- [ ] 9.1.7 Create job retry strategies
- [ ] 9.1.8 Build job monitoring dashboard
- [ ] 9.1.9 Add job priority system
- [ ] 9.1.10 Set up job telemetry

#### Unit Tests:
Create tests in `test/rubber_duck/workers/` directory to verify:

**ProjectIndexer Tests** (`project_indexer_test.exs`):
- [ ] 9.1.11 Test indexing all project files
- [ ] 9.1.12 Test handling large projects with batching
- [ ] 9.1.13 Test recovery from partial failures
- [ ] 9.1.14 Test progress tracking updates
- [ ] 9.1.15 Test file change detection
- [ ] 9.1.16 Test concurrent indexing safety

### 9.2 Security Implementation

Implement comprehensive security measures including authentication, authorization, input validation, and rate limiting.

#### Tasks:
- [ ] 9.2.1 Implement authentication system:
  - [ ] 9.2.1.1 JWT token generation
  - [ ] 9.2.1.2 API key management
  - [ ] 9.2.1.3 OAuth2 integration
  - [ ] 9.2.1.4 Session management
- [ ] 9.2.2 Add authorization layer:
  - [ ] 9.2.2.1 Role-based access control (RBAC)
  - [ ] 9.2.2.2 Project-level permissions
  - [ ] 9.2.2.3 Resource-level authorization
- [ ] 9.2.3 Create input validation:
  - [ ] 9.2.3.1 Code injection prevention
  - [ ] 9.2.3.2 Path traversal protection
  - [ ] 9.2.3.3 Size limits enforcement
- [ ] 9.2.4 Implement rate limiting:
  - [ ] 9.2.4.1 Token bucket per user
  - [ ] 9.2.4.2 Endpoint-specific limits
  - [ ] 9.2.4.3 DDoS protection
- [ ] 9.2.5 Add security scanning:
  - [ ] 9.2.5.1 Dependency vulnerability checks
  - [ ] 9.2.5.2 Code security analysis
- [ ] 9.2.6 Set up audit logging
- [ ] 9.2.7 Implement data encryption at rest

#### Unit Tests:
Create tests in `test/rubber_duck/security/` directory:

**Authentication Tests** (`authentication_test.exs`):
- [ ] 9.2.8 Test JWT token generation and verification
- [ ] 9.2.9 Test token expiration handling
- [ ] 9.2.10 Test API key validation
- [ ] 9.2.11 Test OAuth2 flow
- [ ] 9.2.12 Test session management
- [ ] 9.2.13 Test multi-factor authentication

**Authorization Tests** (`authorization_test.exs`):
- [ ] 9.2.14 Test project permission enforcement
- [ ] 9.2.15 Test role-based access
- [ ] 9.2.16 Test resource-level permissions
- [ ] 9.2.17 Test permission inheritance
- [ ] 9.2.18 Test cross-project isolation
- [ ] 9.2.19 Test admin overrides

**Input Validation Tests** (`validation_test.exs`):
- [ ] 9.2.20 Test path traversal prevention
- [ ] 9.2.21 Test code input sanitization
- [ ] 9.2.22 Test size limit enforcement
- [ ] 9.2.23 Test injection attack prevention
- [ ] 9.2.24 Test file type validation
- [ ] 9.2.25 Test rate limiting

### 9.3 Monitoring and Observability

Implement comprehensive monitoring, logging, and observability features for production operations.

#### Tasks:
- [ ] 9.3.1 Set up Telemetry integration:
  - [ ] 9.3.1.1 Define telemetry events
  - [ ] 9.3.1.2 Create metric reporters
  - [ ] 9.3.1.3 Add custom measurements
- [ ] 9.3.2 Implement structured logging:
  - [ ] 9.3.2.1 JSON log formatting
  - [ ] 9.3.2.2 Log aggregation setup
  - [ ] 9.3.2.3 Correlation ID tracking
- [ ] 9.3.3 Create health check endpoints:
  - [ ] 9.3.3.1 Database connectivity
  - [ ] 9.3.3.2 LLM provider status with dynamic configuration
  - [ ] 9.3.3.3 Memory usage
  - [ ] 9.3.3.4 Job queue health
- [ ] 9.3.4 Add performance monitoring:
  - [ ] 9.3.4.1 Request duration tracking
  - [ ] 9.3.4.2 Database query analysis
  - [ ] 9.3.4.3 Memory profiling
- [ ] 9.3.5 Set up error tracking:
  - [ ] 9.3.5.1 Tower integration with proper configuration
  - [ ] 9.3.5.2 Error aggregation
  - [ ] 9.3.5.3 Alert configuration
- [ ] 9.3.6 Build metrics dashboard
- [ ] 9.3.7 Implement distributed tracing
- [ ] 9.3.8 Create SLO monitoring
- [ ] 9.3.9 Add LLM enhancement metrics:
  - [ ] 9.3.9.1 CoT reasoning quality tracking
  - [ ] 9.3.9.2 RAG retrieval precision monitoring
  - [ ] 9.3.9.3 Self-correction effectiveness metrics
  - [ ] 9.3.9.4 Enhancement technique A/B testing
  - [ ] 9.3.9.5 Dynamic configuration usage analytics

#### Unit Tests:
Create tests in `test/rubber_duck/monitoring/` directory:

**Telemetry Tests** (`telemetry_test.exs`):
- [ ] 9.3.10 Test completion event emission
- [ ] 9.3.11 Test LLM request latency tracking
- [ ] 9.3.12 Test custom metric recording
- [ ] 9.3.13 Test event metadata inclusion
- [ ] 9.3.14 Test metric aggregation
- [ ] 9.3.15 Test performance measurements
- [ ] 9.3.16 Test LLM enhancement metrics

**Health Check Tests** (`health_test.exs`):
- [ ] 9.3.17 Test comprehensive health endpoint
- [ ] 9.3.18 Test detailed health with issues
- [ ] 9.3.19 Test individual component checks
- [ ] 9.3.20 Test health status aggregation
- [ ] 9.3.21 Test timeout handling
- [ ] 9.3.22 Test graceful degradation

**Metrics Tests** (`metrics_test.exs`):
- [ ] 9.3.23 Test request metric tracking
- [ ] 9.3.24 Test memory usage monitoring
- [ ] 9.3.25 Test business metric collection
- [ ] 9.3.26 Test metric persistence
- [ ] 9.3.27 Test dashboard data aggregation
- [ ] 9.3.28 Test alert triggering

### 9.4 Deployment and Scaling

Implement deployment configurations and scaling strategies for production environments.

#### Tasks:
- [ ] 9.4.1 Create Docker configuration:
  - [ ] 9.4.1.1 Multi-stage Dockerfile
  - [ ] 9.4.1.2 Docker Compose setup
  - [ ] 9.4.1.3 Health check configuration
  - [ ] 9.4.1.4 Volume management
  - [ ] 9.4.1.5 MCP server containerization
- [ ] 9.4.2 Set up Kubernetes deployment:
  - [ ] 9.4.2.1 Deployment manifests
  - [ ] 9.4.2.2 Service configuration
  - [ ] 9.4.2.3 Ingress rules
  - [ ] 9.4.2.4 ConfigMaps and Secrets
  - [ ] 9.4.2.5 MCP service mesh integration
- [ ] 9.4.3 Implement clustering:
  - [ ] 9.4.3.1 libcluster configuration
  - [ ] 9.4.3.2 Node discovery
  - [ ] 9.4.3.3 Distributed Erlang setup
  - [ ] 9.4.3.4 State synchronization
  - [ ] 9.4.3.5 MCP registry distribution
- [ ] 9.4.4 Add horizontal scaling:
  - [ ] 9.4.4.1 Load balancer configuration
  - [ ] 9.4.4.2 Session affinity
  - [ ] 9.4.4.3 Autoscaling rules
  - [ ] 9.4.4.4 MCP connection pooling
- [ ] 9.4.5 Create database migrations strategy
- [ ] 9.4.6 Set up blue-green deployment
- [ ] 9.4.7 Implement feature flags
- [ ] 9.4.8 Add CDN configuration
- [ ] 9.4.9 Create backup and restore procedures
- [ ] 9.4.10 Build disaster recovery plan

#### Unit Tests:
Create tests in `test/rubber_duck/deployment/` directory:

**Clustering Tests** (`clustering_test.exs`):
- [ ] 9.4.11 Test node discovery and connection
- [ ] 9.4.12 Test state synchronization across nodes
- [ ] 9.4.13 Test node failure handling
- [ ] 9.4.14 Test load distribution
- [ ] 9.4.15 Test cluster reformation
- [ ] 9.4.16 Test split-brain resolution

**Deployment Tests** (`deployment_test.exs`):
- [ ] 9.4.17 Test Docker image build
- [ ] 9.4.18 Test Kubernetes manifest validity
- [ ] 9.4.19 Test configuration management
- [ ] 9.4.20 Test secret handling
- [ ] 9.4.21 Test rollback procedures
- [ ] 9.4.22 Test zero-downtime deployment

**Feature Flag Tests** (`feature_flags_test.exs`):
- [ ] 9.4.23 Test feature toggle functionality
- [ ] 9.4.24 Test gradual rollout percentages
- [ ] 9.4.25 Test user-specific flags
- [ ] 9.4.26 Test flag persistence
- [ ] 9.4.27 Test A/B testing support
- [ ] 9.4.28 Test flag inheritance

### 9.5 Phase 9 Integration Tests

Create comprehensive integration tests in `test/integration/phase_9_test.exs` to verify:
- [ ] 9.5.1 Test end-to-end secure workflow with monitoring
- [ ] 9.5.2 Test high load handling with rate limiting
- [ ] 9.5.3 Test monitoring captures system health
- [ ] 9.5.4 Test graceful degradation when services fail
- [ ] 9.5.5 Test distributed deployment scenario
- [ ] 9.5.6 Test backup and restore procedures
- [ ] 9.5.7 Test feature flag integration
- [ ] 9.5.8 Test MCP server scaling
- [ ] 9.5.9 Test security controls with MCP
- [ ] 9.5.10 Test production readiness criteria

### 9.6 Final System Integration Tests

Create final system tests in `test/integration/complete_system_test.exs` to verify:
- [ ] 9.6.1 Test full coding assistant workflow from project creation to code generation
- [ ] 9.6.2 Test system behavior under sustained load
- [ ] 9.6.3 Test monitoring and alerting pipeline
- [ ] 9.6.4 Test multi-user collaboration scenarios
- [ ] 9.6.5 Test disaster recovery procedures
- [ ] 9.6.6 Test performance meets SLOs
- [ ] 9.6.7 Test security controls are effective
- [ ] 9.6.8 Test MCP integration enhances code quality
- [ ] 9.6.9 Test planning system with MCP tools
- [ ] 9.6.10 Test complete system resilience
- [ ] 9.6.11 Test dynamic LLM configuration system integration
- [ ] 9.6.12 Test unified command system across all interfaces
- [ ] 9.6.13 Test chat-focused TUI integration
- [ ] 9.6.14 Test error handling and recovery mechanisms

---

## Implementation Status Summary

### ✅ Completed Features:
1. **Unified Command Abstraction Layer** - Complete command processing system across all client interfaces
2. **Dynamic LLM Configuration System** - Runtime provider and model switching with CLI commands
3. **WebSocket CLI Client** - Standalone binary with real-time server communication
4. **Chat-Focused TUI Interface** - Modern terminal UI with toggleable panels and chat focus
5. **System Error Handling** - Tower configuration fixes and comprehensive error management

### 🚧 In Progress:
- **TUI Implementation** - ~90% complete, needs syntax highlighting and performance optimizations
- **LiveView Interface** - Not started, depends on completed command system

### 📋 Planned:
- **Conversational AI System** (Phase 6)
- **Planning Enhancement System** (Phase 7) 
- **MCP Integration** (Phase 8)
- **Production Readiness** (Phase 9)

### 🔗 Recent Integration Highlights:
- Successfully integrated dynamic LLM configuration across all AI engines
- Updated CLI user guide with comprehensive dynamic configuration documentation
- Fixed Tower error reporting for improved system stability
- Implemented comprehensive test coverage for all major systems
- Created seamless integration between chat interface and command system
