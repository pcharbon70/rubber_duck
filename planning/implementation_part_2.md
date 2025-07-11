# RubberDuck Implementation Plan - Part 2 (Phases 5-8)

This document contains the detailed implementation plans for Phases 5-8 of the RubberDuck project. For the overall project status and Phases 1-4, see the [main implementation plan](implementation_plan.md).

## Table of Contents
5. [Phase 5: Real-time Communication & UI](#phase-5-real-time-communication--ui)
6. [Phase 6: Planning Enhancement System](#phase-6-planning-enhancement-system)
7. [Phase 7: MCP (Model Context Protocol) Integration](#phase-7-mcp-model-context-protocol-integration)
8. [Phase 8: Advanced Features & Production Readiness](#phase-8-advanced-features--production-readiness)

---

## Phase 5: Real-time Communication & UI

This phase implements the user-facing interfaces including Phoenix Channels for real-time communication, LiveView for the web interface, and a sophisticated CLI/TUI. These interfaces provide interactive access to all the coding assistant capabilities.

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

### 5.2 LiveView Interface

Build a comprehensive Phoenix LiveView application for real-time collaborative coding with integrated AI assistance, following the architecture design that combines code editing and LLM chat capabilities.

#### Tasks:

**Core LiveView Infrastructure:**
- [ ] 5.2.1 Create `RubberDuckWeb.CodingSessionLive` module as main coordinator
- [ ] 5.2.2 Implement Phoenix PubSub subscriptions:
  - [ ] 5.2.2.1 Project-level updates (`project:#{project_id}`)
  - [ ] 5.2.2.2 Editor updates (`editor:#{project_id}`)
  - [ ] 5.2.2.3 Chat updates (`chat:#{project_id}`)
- [ ] 5.2.3 Set up WebSocket channel subscription for coding sessions
- [ ] 5.2.4 Implement state management:
  - [ ] 5.2.4.1 Project and file state
  - [ ] 5.2.4.2 Conversation and message streams
  - [ ] 5.2.4.3 Editor content with debouncing
  - [ ] 5.2.4.4 Streaming status indicators

**Monaco Editor Component:**
- [ ] 5.2.5 Create `RubberDuckWeb.Components.MonacoEditorComponent`
- [ ] 5.2.6 Implement Monaco Editor integration:
  - [ ] 5.2.6.1 JavaScript hooks for editor mounting
  - [ ] 5.2.6.2 Syntax highlighting with language detection
  - [ ] 5.2.6.3 Real-time collaborative editing
  - [ ] 5.2.6.4 External update handling
  - [ ] 5.2.6.5 Code suggestions overlay
- [ ] 5.2.7 Add editor configuration:
  - [ ] 5.2.7.1 Theme support (vs-dark default)
  - [ ] 5.2.7.2 Font and display preferences
  - [ ] 5.2.7.3 Language-specific settings
- [ ] 5.2.8 Implement AI suggestion integration:
  - [ ] 5.2.8.1 Suggestion display overlay
  - [ ] 5.2.8.2 Apply/dismiss functionality
  - [ ] 5.2.8.3 Incremental completion updates

**Chat Panel Component:**
- [ ] 5.2.9 Create `RubberDuckWeb.Components.ChatPanelComponent`
- [ ] 5.2.10 Implement chat functionality:
  - [ ] 5.2.10.1 Message streaming with typing indicators
  - [ ] 5.2.10.2 LLM response streaming support
  - [ ] 5.2.10.3 Context-aware prompting
  - [ ] 5.2.10.4 Message history with timestamps
- [ ] 5.2.11 Integrate with Phase 3 systems:
  - [ ] 5.2.11.1 LLM Service for completions
  - [ ] 5.2.11.2 Memory Manager for context
  - [ ] 5.2.11.3 Context Builder for prompts

**File Tree Component:**
- [ ] 5.2.12 Create `RubberDuckWeb.Components.FileTreeComponent`
- [ ] 5.2.13 Implement file navigation:
  - [ ] 5.2.13.1 Project file listing
  - [ ] 5.2.13.2 File selection handling
  - [ ] 5.2.13.3 Current file highlighting
  - [ ] 5.2.13.4 File type icons

**Context Panel Component:**
- [ ] 5.2.14 Create `RubberDuckWeb.Components.ContextPanelComponent`
- [ ] 5.2.15 Display project context information:
  - [ ] 5.2.15.1 Current analysis results
  - [ ] 5.2.15.2 Code metrics
  - [ ] 5.2.15.3 Relevant documentation

**JavaScript Integration:**
- [ ] 5.2.16 Create Monaco Editor hooks (`assets/js/hooks/monaco_editor.js`):
  - [ ] 5.2.16.1 Editor mounting and configuration
  - [ ] 5.2.16.2 Content change debouncing
  - [ ] 5.2.16.3 Cursor position tracking
  - [ ] 5.2.16.4 Completion provider registration
- [ ] 5.2.17 Implement live_monaco_editor integration
- [ ] 5.2.18 Add collaborative cursor support

**Real-time Features:**
- [ ] 5.2.19 Implement file content synchronization:
  - [ ] 5.2.19.1 Debounced auto-save
  - [ ] 5.2.19.2 Conflict resolution
  - [ ] 5.2.19.3 Multi-user awareness
- [ ] 5.2.20 Add presence tracking for collaboration
- [ ] 5.2.21 Create real-time analysis updates

**Integration with Existing Systems:**
- [ ] 5.2.22 Connect to Phase 2 engines:
  - [ ] 5.2.22.1 Code Analysis Engine integration
  - [ ] 5.2.22.2 Suggestion Engine for completions
- [ ] 5.2.23 Integrate Phase 4 workflows:
  - [ ] 5.2.23.1 Trigger analysis workflows
  - [ ] 5.2.23.2 Display workflow results
- [ ] 5.2.24 Add telemetry events for UI interactions

#### Unit Tests:

**CodingSessionLive Tests** (`test/rubber_duck_web/live/coding_session_live_test.exs`):
- [ ] 5.2.25 Test mount with project authorization
- [ ] 5.2.26 Test PubSub subscription setup
- [ ] 5.2.27 Test file selection and content loading
- [ ] 5.2.28 Test editor content change handling
- [ ] 5.2.29 Test file save functionality
- [ ] 5.2.30 Test real-time update broadcasting

**Component Tests** (`test/rubber_duck_web/components/`):
- [ ] 5.2.31 Test Monaco Editor component rendering
- [ ] 5.2.32 Test Chat Panel message streaming
- [ ] 5.2.33 Test File Tree navigation
- [ ] 5.2.34 Test suggestion application
- [ ] 5.2.35 Test context panel updates

**Integration Tests** (`test/rubber_duck_web/live/integration_test.exs`):
- [ ] 5.2.36 Test complete coding session flow
- [ ] 5.2.37 Test multi-user collaboration
- [ ] 5.2.38 Test LLM response streaming
- [ ] 5.2.39 Test code analysis integration
- [ ] 5.2.40 Test memory persistence across sessions

**JavaScript Hook Tests** (`test/assets/js/hooks/`):
- [ ] 5.2.41 Test Monaco Editor mounting
- [ ] 5.2.42 Test content synchronization
- [ ] 5.2.43 Test completion provider
- [ ] 5.2.44 Test external update handling
- [ ] 5.2.45 Test cursor position broadcasting

### 5.3 WebSocket CLI Client Implementation ✅ Completed

Transform the CLI from mix task-based to a standalone WebSocket client that communicates with the running Phoenix server, eliminating compilation overhead and maintaining server state.

#### Tasks:
- [x] 5.3.1 Add WebSocket client dependencies:
  - [x] 5.3.1.1 `phoenix_gen_socket_client` for WebSocket communication
  - [x] 5.3.1.2 `websocket_client` for transport layer
- [x] 5.3.2 Create Phoenix Channel infrastructure:
  - [x] 5.3.2.1 `CLIChannel` for handling all CLI commands
  - [x] 5.3.2.2 Update `UserSocket` with CLI channel and API key auth
  - [x] 5.3.2.3 Implement channel message handlers for each command type
- [x] 5.3.3 Build WebSocket client architecture:
  - [x] 5.3.3.1 `CLIClient.Client` GenServer for connection management
  - [x] 5.3.3.2 `CLIClient.Transport` for Phoenix.Channels.GenSocketClient
  - [x] 5.3.3.3 Automatic reconnection on disconnect
  - [x] 5.3.3.4 Request/response correlation for async operations
- [x] 5.3.4 Implement authentication system:
  - [x] 5.3.4.1 `CLIClient.Auth` for API key management
  - [x] 5.3.4.2 Secure storage in `~/.rubber_duck/config.json`
  - [x] 5.3.4.3 `Mix.Tasks.RubberDuck.Auth` for key generation
  - [x] 5.3.4.4 Environment variable support
- [x] 5.3.5 Create command handlers:
  - [x] 5.3.5.1 `analyze` - Code analysis via WebSocket
  - [x] 5.3.5.2 `generate` - Code generation with streaming
  - [x] 5.3.5.3 `complete` - Code completions
  - [x] 5.3.5.4 `refactor` - Code refactoring
  - [x] 5.3.5.5 `test` - Test generation
  - [x] 5.3.5.6 `llm` - LLM provider management
  - [x] 5.3.5.7 `health` - Server health monitoring
- [x] 5.3.6 Implement streaming support:
  - [x] 5.3.6.1 Stream message protocol (start/data/end)
  - [x] 5.3.6.2 Progress indicators for long operations
  - [x] 5.3.6.3 Real-time output display
- [x] 5.3.7 Build escript packaging:
  - [x] 5.3.7.1 Configure escript in mix.exs
  - [x] 5.3.7.2 `CLIClient.Main` entry point with Optimus
  - [x] 5.3.7.3 Embedded Elixir runtime
  - [x] 5.3.7.4 Binary distribution at `bin/rubber_duck`
- [x] 5.3.8 Add output formatting:
  - [x] 5.3.8.1 Plain text formatter (default)
  - [x] 5.3.8.2 JSON formatter for automation
  - [x] 5.3.8.3 Table formatter with column alignment
  - [x] 5.3.8.4 Format-specific rendering for each command
- [x] 5.3.9 Implement health check feature:
  - [x] 5.3.9.1 Server uptime tracking
  - [x] 5.3.9.2 Memory usage statistics
  - [x] 5.3.9.3 Connection counting
  - [x] 5.3.9.4 Provider health status

#### Unit Tests:
Created comprehensive tests:
- [x] 5.3.10 Test channel join and authentication
- [x] 5.3.11 Test all command handlers (analyze, generate, complete, etc.)
- [x] 5.3.12 Test streaming message protocol
- [x] 5.3.13 Test LLM provider management commands
- [x] 5.3.14 Test health check response format
- [x] 5.3.15 Test connection failure and reconnection
- [x] 5.3.16 Test API key authentication flow

**Note**: Successfully transformed CLI from mix tasks to WebSocket client, providing instant command execution without compilation, persistent server connection, real-time streaming, and distributable binary. See `notes/websocket-cli-feature.md` for implementation details.

### 5.4 TUI (Terminal UI) Implementation with Go and Bubble Tea

Build a modern terminal user interface using Go and the Bubble Tea framework, leveraging the Elm Architecture for predictable state management and seamless Phoenix WebSocket integration.

#### Tasks:

**Project Setup and Dependencies:**
- [ ] 5.4.1 Create Go module `github.com/rubber_duck/tui`
- [ ] 5.4.2 Add dependencies to `go.mod`:
  - [ ] 5.4.2.1 `github.com/charmbracelet/bubbletea` - Core TUI framework
  - [ ] 5.4.2.2 `github.com/charmbracelet/bubbles` - Component library
  - [ ] 5.4.2.3 `github.com/charmbracelet/lipgloss` - Styling system
  - [ ] 5.4.2.4 `github.com/nshafer/phx` - Phoenix channels client
  - [ ] 5.4.2.5 `github.com/alecthomas/chroma` - Syntax highlighting
- [ ] 5.4.3 Set up project structure:
  - [ ] 5.4.3.1 `cmd/rubber_duck_tui/main.go` - Entry point
  - [ ] 5.4.3.2 `internal/ui/` - UI components
  - [ ] 5.4.3.3 `internal/phoenix/` - WebSocket integration
  - [ ] 5.4.3.4 `internal/commands/` - Command system

**Core Architecture Implementation:**
- [ ] 5.4.4 Implement base Model-Update-View architecture:
  - [ ] 5.4.4.1 Define `Model` struct with application state
  - [ ] 5.4.4.2 Create message types for all events
  - [ ] 5.4.4.3 Implement `Update` function for state transitions
  - [ ] 5.4.4.4 Build `View` function with Lipgloss layouts
- [ ] 5.4.5 Create state management system:
  - [ ] 5.4.5.1 File tree state and operations
  - [ ] 5.4.5.2 Editor state with content tracking
  - [ ] 5.4.5.3 Output pane state for results
  - [ ] 5.4.5.4 WebSocket connection state
  - [ ] 5.4.5.5 Analysis and generation state

**Phoenix WebSocket Integration:**
- [ ] 5.4.6 Implement Phoenix channel client:
  - [ ] 5.4.6.1 Connection management with auto-reconnect
  - [ ] 5.4.6.2 Channel join/leave operations
  - [ ] 5.4.6.3 Message serialization/deserialization
  - [ ] 5.4.6.4 Event subscription system
- [ ] 5.4.7 Create WebSocket command adapters:
  - [ ] 5.4.7.1 File analysis commands
  - [ ] 5.4.7.2 Code generation commands
  - [ ] 5.4.7.3 Completion requests
  - [ ] 5.4.7.4 Refactoring operations
- [ ] 5.4.8 Implement streaming support:
  - [ ] 5.4.8.1 Stream start/data/end message handling
  - [ ] 5.4.8.2 Progressive output rendering
  - [ ] 5.4.8.3 Stream cancellation
  - [ ] 5.4.8.4 Error recovery

**UI Component Development:**
- [ ] 5.4.9 Build file tree component:
  - [ ] 5.4.9.1 Recursive tree rendering with Lipgloss
  - [ ] 5.4.9.2 Expand/collapse functionality
  - [ ] 5.4.9.3 File type icons and styling
  - [ ] 5.4.9.4 Keyboard navigation (j/k, enter)
  - [ ] 5.4.9.5 File selection events
- [ ] 5.4.10 Create code editor component:
  - [ ] 5.4.10.1 Integrate Bubbles textarea
  - [ ] 5.4.10.2 Syntax highlighting with Chroma
  - [ ] 5.4.10.3 Line numbers and cursor position
  - [ ] 5.4.10.4 Content change tracking
  - [ ] 5.4.10.5 Auto-save functionality
- [ ] 5.4.11 Implement output/results pane:
  - [ ] 5.4.11.1 Scrollable viewport with Bubbles
  - [ ] 5.4.11.2 Formatted analysis results
  - [ ] 5.4.11.3 Error display with styling
  - [ ] 5.4.11.4 Progress indicators
  - [ ] 5.4.11.5 Clear and filter options
- [ ] 5.4.12 Build command palette:
  - [ ] 5.4.12.1 Fuzzy search with text input
  - [ ] 5.4.12.2 Command list with descriptions
  - [ ] 5.4.12.3 Keyboard shortcuts display
  - [ ] 5.4.12.4 Command execution system
  - [ ] 5.4.12.5 Recent commands history

**Layout and Navigation:**
- [ ] 5.4.13 Implement responsive layout system:
  - [ ] 5.4.13.1 Three-pane layout with Lipgloss
  - [ ] 5.4.13.2 Dynamic width calculation
  - [ ] 5.4.13.3 Terminal resize handling
  - [ ] 5.4.13.4 Minimum size constraints
- [ ] 5.4.14 Create navigation system:
  - [ ] 5.4.14.1 Tab cycling between panes
  - [ ] 5.4.14.2 Vim-style navigation keys
  - [ ] 5.4.14.3 Focus indicators
  - [ ] 5.4.14.4 Mouse support where available
- [ ] 5.4.15 Add status bar:
  - [ ] 5.4.15.1 Connection status indicator
  - [ ] 5.4.15.2 Current file path
  - [ ] 5.4.15.3 Operation progress
  - [ ] 5.4.15.4 Key hints

**Advanced Features:**
- [ ] 5.4.16 Implement modal dialogs:
  - [ ] 5.4.16.1 Confirmation dialogs
  - [ ] 5.4.16.2 Input prompts
  - [ ] 5.4.16.3 Settings dialog
  - [ ] 5.4.16.4 Help overlay
- [ ] 5.4.17 Add theming support:
  - [ ] 5.4.17.1 Color scheme definitions
  - [ ] 5.4.17.2 Dark/light mode toggle
  - [ ] 5.4.17.3 Custom style configuration
- [ ] 5.4.18 Create performance optimizations:
  - [ ] 5.4.18.1 Render caching for static components
  - [ ] 5.4.18.2 Debounced file operations
  - [ ] 5.4.18.3 Lazy loading for large files
  - [ ] 5.4.18.4 Virtual scrolling for file tree

#### Unit Tests:
Create tests in `tui/internal/ui/*_test.go` files to verify:
- [ ] 5.4.19 Test Model initialization and state
- [ ] 5.4.20 Test Update function message handling
- [ ] 5.4.21 Test View rendering without errors
- [ ] 5.4.22 Test WebSocket connection lifecycle
- [ ] 5.4.23 Test file tree navigation operations
- [ ] 5.4.24 Test editor content synchronization
- [ ] 5.4.25 Test command palette filtering
- [ ] 5.4.26 Test layout calculations
- [ ] 5.4.27 Test keyboard shortcut handling
- [ ] 5.4.28 Test error recovery mechanisms

#### Integration Tests:
Create tests in `tui/test/integration_test.go` to verify:
- [ ] 5.4.29 Test full TUI startup and initialization
- [ ] 5.4.30 Test Phoenix channel communication
- [ ] 5.4.31 Test file analysis workflow
- [ ] 5.4.32 Test code generation streaming
- [ ] 5.4.33 Test concurrent operations
- [ ] 5.4.34 Test reconnection after disconnect
- [ ] 5.4.35 Test state persistence

### Phase 5 Integration Tests

Create comprehensive integration tests in `test/integration/phase_5_test.exs` to verify:
- [ ] 5.5.1 Test LiveView and Channel coordination
- [ ] 5.5.2 Test CLI triggers real-time updates
- [ ] 5.5.3 Test settings sync across interfaces
- [ ] 5.5.4 Test analysis results consistency
- [ ] 5.5.5 Test multiple concurrent WebSocket connections
- [ ] 5.5.6 Test LiveView rapid update handling
- [ ] 5.5.7 Test TUI state management

---

## Phase 6: Planning Enhancement System

This phase implements a sophisticated planning system based on the LLM-Modulo framework, where LLMs generate plans that are validated by external critics. The system provides hierarchical task decomposition, repository-level planning, and dynamic execution with ReAct-based adaptation.

### 6.1 Planning Domain & Resources

Set up the core Ash domain and resources for the planning system, including plan tracking, task management, and validation results.

#### Tasks:
- [ ] 6.1.1 Create Planning domain module with Ash.Domain
- [ ] 6.1.2 Design Plan resource with attributes:
  - [ ] 6.1.2.1 Basic fields (id, name, description, type, status)
  - [ ] 6.1.2.2 Context storage (project context, dependencies, constraints)
  - [ ] 6.1.2.3 Validation results and execution history
  - [ ] 6.1.2.4 Timestamps and metadata
- [ ] 6.1.3 Design Task resource with attributes:
  - [ ] 6.1.3.1 Task details (name, description, complexity, status)
  - [ ] 6.1.3.2 Dependencies and ordering information
  - [ ] 6.1.3.3 Success criteria and validation rules
  - [ ] 6.1.3.4 Execution metadata and results
- [ ] 6.1.4 Create Constraint resource for plan constraints
- [ ] 6.1.5 Create Validation resource for tracking validation results
- [ ] 6.1.6 Set up relationships between resources
- [ ] 6.1.7 Create database migrations for planning tables
- [ ] 6.1.8 Implement Ash actions for CRUD operations
- [ ] 6.1.9 Add authorization policies for plan access
- [ ] 6.1.10 Create GraphQL API for planning resources

#### Unit Tests:
- [ ] 6.1.11 Test Plan resource creation and validation
- [ ] 6.1.12 Test Task resource with dependency management
- [ ] 6.1.13 Test constraint enforcement
- [ ] 6.1.14 Test validation result tracking
- [ ] 6.1.15 Test authorization policies

### 6.2 Task Decomposition Engine

Implement the task decomposition engine that breaks down high-level requests into actionable tasks using LLM-guided decomposition with validation.

#### Tasks:
- [ ] 6.2.1 Create TaskDecomposer engine using RubberDuck.Engine behavior
- [ ] 6.2.2 Implement decomposition strategies:
  - [ ] 6.2.2.1 Linear decomposition for simple tasks
  - [ ] 6.2.2.2 Hierarchical decomposition for complex features
  - [ ] 6.2.2.3 Tree-of-Thought decomposition for exploratory tasks
- [ ] 6.2.3 Integrate with CoT for reasoning during decomposition
- [ ] 6.2.4 Create planning-specific prompt templates
- [ ] 6.2.5 Implement dependency graph builder
- [ ] 6.2.6 Add task complexity estimation
- [ ] 6.2.7 Create success criteria generator
- [ ] 6.2.8 Implement task validation with critics
- [ ] 6.2.9 Add support for iterative refinement
- [ ] 6.2.10 Create planning pattern library

#### Unit Tests:
- [ ] 6.2.11 Test simple task decomposition
- [ ] 6.2.12 Test complex feature decomposition
- [ ] 6.2.13 Test dependency graph generation
- [ ] 6.2.14 Test complexity estimation accuracy
- [ ] 6.2.15 Test iterative refinement process

### 6.3 Critics System (Hard & Soft Critics)

Implement the external critics system for plan validation, including hard critics for correctness and soft critics for quality.

#### Tasks:
- [ ] 6.3.1 Define CriticBehaviour for critic implementations
- [ ] 6.3.2 Implement HardCritic module:
  - [ ] 6.3.2.1 Syntax validation using AST parser
  - [ ] 6.3.2.2 Dependency validation and cycle detection
  - [ ] 6.3.2.3 Constraint satisfaction checking
  - [ ] 6.3.2.4 Feasibility analysis
  - [ ] 6.3.2.5 Resource requirement validation
- [ ] 6.3.3 Implement SoftCritic module:
  - [ ] 6.3.3.1 Code style and convention checking
  - [ ] 6.3.3.2 Best practice validation
  - [ ] 6.3.3.3 Performance impact analysis
  - [ ] 6.3.3.4 Security consideration checking
- [ ] 6.3.4 Create critic orchestrator for running multiple critics
- [ ] 6.3.5 Implement validation result aggregation
- [ ] 6.3.6 Add critic configuration system
- [ ] 6.3.7 Create custom critic plugin support
- [ ] 6.3.8 Implement validation caching
- [ ] 6.3.9 Add validation explanation generation
- [ ] 6.3.10 Create validation dashboard UI

#### Unit Tests:
- [ ] 6.3.11 Test syntax validation critic
- [ ] 6.3.12 Test dependency cycle detection
- [ ] 6.3.13 Test constraint satisfaction
- [ ] 6.3.14 Test soft critic suggestions
- [ ] 6.3.15 Test critic orchestration

### 6.4 ReAct-Based Execution Framework

Build the ReAct (Reasoning-Acting) execution framework for dynamic plan execution with observation and adaptation.

#### Tasks:
- [ ] 6.4.1 Create PlanExecutor GenServer
- [ ] 6.4.2 Implement ReAct loop:
  - [ ] 6.4.2.1 Thought generation for task analysis
  - [ ] 6.4.2.2 Action execution with monitoring
  - [ ] 6.4.2.3 Observation collection and analysis
  - [ ] 6.4.2.4 Dynamic plan adjustment
- [ ] 6.4.3 Integrate with existing workflow engine
- [ ] 6.4.4 Add execution state management
- [ ] 6.4.5 Implement failure recovery strategies
- [ ] 6.4.6 Create execution monitoring hooks
- [ ] 6.4.7 Add real-time progress tracking
- [ ] 6.4.8 Implement rollback capabilities
- [ ] 6.4.9 Create execution history tracking
- [ ] 6.4.10 Add execution analytics

#### Unit Tests:
- [ ] 6.4.11 Test basic ReAct execution loop
- [ ] 6.4.12 Test failure recovery
- [ ] 6.4.13 Test dynamic plan adjustment
- [ ] 6.4.14 Test rollback functionality
- [ ] 6.4.15 Test concurrent task execution

### 6.5 Repository-Level Planning

Implement repository-wide planning capabilities for multi-file changes and architectural modifications.

#### Tasks:
- [ ] 6.5.1 Create RepositoryPlanner module
- [ ] 6.5.2 Implement change impact analysis:
  - [ ] 6.5.2.1 File dependency graph building
  - [ ] 6.5.2.2 Change propagation analysis
  - [ ] 6.5.2.3 Risk assessment for changes
- [ ] 6.5.3 Build change sequencing algorithm
- [ ] 6.5.4 Implement parallel change detection
- [ ] 6.5.5 Create migration plan generator
- [ ] 6.5.6 Add test impact analysis
- [ ] 6.5.7 Implement change preview system
- [ ] 6.5.8 Create conflict resolution strategies
- [ ] 6.5.9 Add architectural pattern detection
- [ ] 6.5.10 Implement change validation pipeline

#### Unit Tests:
- [ ] 6.5.11 Test impact analysis accuracy
- [ ] 6.5.12 Test change sequencing
- [ ] 6.5.13 Test parallel change detection
- [ ] 6.5.14 Test migration plan generation
- [ ] 6.5.15 Test conflict resolution

### 6.6 Planning DSL with Spark

Create a domain-specific language for defining plans using the Spark framework.

#### Tasks:
- [ ] 6.6.1 Design Planning DSL structure
- [ ] 6.6.2 Implement Spark DSL sections:
  - [ ] 6.6.2.1 Plan section for plan metadata
  - [ ] 6.6.2.2 Task entity for task definitions
  - [ ] 6.6.2.3 Constraint entity for constraints
  - [ ] 6.6.2.4 Validation entity for custom validators
- [ ] 6.6.3 Create DSL compiler
- [ ] 6.6.4 Implement DSL validation
- [ ] 6.6.5 Add DSL to Ash resource transformation
- [ ] 6.6.6 Create DSL documentation generator
- [ ] 6.6.7 Implement DSL migration support
- [ ] 6.6.8 Add DSL syntax highlighting
- [ ] 6.6.9 Create example plan templates
- [ ] 6.6.10 Build DSL testing framework

#### Unit Tests:
- [ ] 6.6.11 Test DSL parsing
- [ ] 6.6.12 Test DSL compilation
- [ ] 6.6.13 Test DSL validation
- [ ] 6.6.14 Test resource transformation
- [ ] 6.6.15 Test DSL error handling

---


## Phase 7: MCP (Model Context Protocol) Integration

This phase implements comprehensive Model Context Protocol (MCP) support, enabling RubberDuck to connect with a vast ecosystem of external tools and data sources while exposing its own capabilities through standardized interfaces. MCP acts as a universal adapter for AI systems, solving the integration complexity problem and enabling powerful new workflows.

### 7.1 MCP Client Implementation

Implement the MCP client infrastructure using Hermes MCP, enabling RubberDuck to connect to and utilize external MCP servers for enhanced functionality.

#### Tasks:
- [ ] 7.1.1 Add Hermes MCP dependency to mix.exs
- [ ] 7.1.2 Create `RubberDuck.MCP.Client` module structure
- [ ] 7.1.3 Implement transport adapters:
  - [ ] 7.1.3.1 STDIO transport for local MCP servers
  - [ ] 7.1.3.2 HTTP/SSE transport for remote servers
  - [ ] 7.1.3.3 WebSocket transport for real-time connections
- [ ] 7.1.4 Build client supervisor with OTP patterns:
  - [ ] 7.1.4.1 DynamicSupervisor for client spawning
  - [ ] 7.1.4.2 Registry for client tracking
  - [ ] 7.1.4.3 Connection pool management
- [ ] 7.1.5 Create capability negotiation:
  - [ ] 7.1.5.1 Tool discovery
  - [ ] 7.1.5.2 Resource enumeration
  - [ ] 7.1.5.3 Prompt template retrieval
- [ ] 7.1.6 Implement authentication mechanisms:
  - [ ] 7.1.6.1 OAuth 2.1 support
  - [ ] 7.1.6.2 API key authentication
  - [ ] 7.1.6.3 Certificate-based auth
- [ ] 7.1.7 Add client health monitoring:
  - [ ] 7.1.7.1 Heartbeat implementation
  - [ ] 7.1.7.2 Automatic reconnection
  - [ ] 7.1.7.3 Circuit breaker per server
- [ ] 7.1.8 Create request/response correlation
- [ ] 7.1.9 Implement client-side caching
- [ ] 7.1.10 Add telemetry for MCP operations

#### Unit Tests:
Create tests in `test/rubber_duck/mcp/client_test.exs` to verify:
- [ ] 7.1.11 Test client initialization with different transports
- [ ] 7.1.12 Test capability negotiation protocol
- [ ] 7.1.13 Test tool discovery and invocation
- [ ] 7.1.14 Test resource access patterns
- [ ] 7.1.15 Test authentication flows
- [ ] 7.1.16 Test reconnection on disconnect
- [ ] 7.1.17 Test concurrent requests handling
- [ ] 7.1.18 Test circuit breaker behavior

### 7.2 MCP Server Implementation

Create RubberDuck's own MCP server to expose its capabilities as standardized tools that other AI systems can leverage.

#### Tasks:
- [ ] 7.2.1 Create `RubberDuck.MCP.Server` module
- [ ] 7.2.2 Implement server transports:
  - [ ] 7.2.2.1 STDIO server for local access
  - [ ] 7.2.2.2 HTTP/SSE server with Plug
  - [ ] 7.2.2.3 WebSocket server integration
- [ ] 7.2.3 Build tool exposure framework:
  - [ ] 7.2.3.1 AST parsing tools
  - [ ] 7.2.3.2 Code analysis tools
  - [ ] 7.2.3.3 Code generation tools
  - [ ] 7.2.3.4 Memory access tools
- [ ] 7.2.4 Create resource providers:
  - [ ] 7.2.4.1 Project file resources
  - [ ] 7.2.4.2 Analysis result resources
  - [ ] 7.2.4.3 Memory context resources
- [ ] 7.2.5 Implement prompt templates:
  - [ ] 7.2.5.1 Code review prompts
  - [ ] 7.2.5.2 Refactoring prompts
  - [ ] 7.2.5.3 Documentation prompts
- [ ] 7.2.6 Add server authorization:
  - [ ] 7.2.6.1 Per-tool permissions
  - [ ] 7.2.6.2 Resource access control
  - [ ] 7.2.6.3 Rate limiting per client
- [ ] 7.2.7 Create server health endpoints
- [ ] 7.2.8 Implement server-side logging
- [ ] 7.2.9 Add connection management
- [ ] 7.2.10 Build server configuration DSL

#### Unit Tests:
Create tests in `test/rubber_duck/mcp/server_test.exs` to verify:
- [ ] 7.2.11 Test server initialization and startup
- [ ] 7.2.12 Test tool registration and exposure
- [ ] 7.2.13 Test resource provider functionality
- [ ] 7.2.14 Test authorization enforcement
- [ ] 7.2.15 Test concurrent client handling
- [ ] 7.2.16 Test rate limiting behavior
- [ ] 7.2.17 Test health check responses

### 7.3 MCP Tool Registry

Build a comprehensive registry system for managing MCP tools from various sources with capability-based discovery.

#### Tasks:
- [ ] 7.3.1 Create `RubberDuck.MCP.Registry` module
- [ ] 7.3.2 Implement tool cataloging:
  - [ ] 7.3.2.1 Internal tool registration
  - [ ] 7.3.2.2 External tool discovery
  - [ ] 7.3.2.3 Tool metadata storage
- [ ] 7.3.3 Build capability indexing:
  - [ ] 7.3.3.1 Semantic capability matching
  - [ ] 7.3.3.2 Input/output type tracking
  - [ ] 7.3.3.3 Performance characteristics
- [ ] 7.3.4 Create tool composition engine:
  - [ ] 7.3.4.1 Sequential tool chaining
  - [ ] 7.3.4.2 Parallel tool execution
  - [ ] 7.3.4.3 Conditional tool selection
- [ ] 7.3.5 Add tool versioning support
- [ ] 7.3.6 Implement tool quality metrics:
  - [ ] 7.3.6.1 Success rate tracking
  - [ ] 7.3.6.2 Latency monitoring
  - [ ] 7.3.6.3 Error rate analysis
- [ ] 7.3.7 Create tool recommendation system
- [ ] 7.3.8 Build tool testing framework
- [ ] 7.3.9 Add tool documentation generator
- [ ] 7.3.10 Implement tool deprecation handling

#### Unit Tests:
Create tests in `test/rubber_duck/mcp/registry_test.exs` to verify:
- [ ] 7.3.11 Test tool registration and retrieval
- [ ] 7.3.12 Test capability-based discovery
- [ ] 7.3.13 Test tool composition patterns
- [ ] 7.3.14 Test quality metrics tracking
- [ ] 7.3.15 Test recommendation accuracy
- [ ] 7.3.16 Test version compatibility

### 7.4 MCP Integration with Existing Systems

Create seamless integration between MCP and RubberDuck's existing architecture, enhancing rather than replacing current functionality.

#### Tasks:
- [ ] 7.4.1 Integrate with LLM providers:
  - [ ] 7.4.1.1 Add MCP to provider abstraction
  - [ ] 7.4.1.2 Expose provider capabilities via MCP
  - [ ] 7.4.1.3 Enable MCP-based provider selection
- [ ] 7.4.2 Connect to memory system:
  - [ ] 7.4.2.1 Expose memory as MCP resources
  - [ ] 7.4.2.2 Enable MCP tool memory updates
  - [ ] 7.4.2.3 Create memory synchronization
- [ ] 7.4.3 Enhance workflow system:
  - [ ] 7.4.3.1 Add MCP tool steps to Reactor
  - [ ] 7.4.3.2 Create MCP-aware workflows
  - [ ] 7.4.3.3 Enable dynamic MCP tool selection
- [ ] 7.4.4 Extend engine system:
  - [ ] 7.4.4.1 Create MCP engine adapter
  - [ ] 7.4.4.2 Enable engines as MCP tools
  - [ ] 7.4.4.3 Add MCP-based engine discovery
- [ ] 7.4.5 Update context building:
  - [ ] 7.4.5.1 Include MCP tool states
  - [ ] 7.4.5.2 Add MCP resource context
  - [ ] 7.4.5.3 Enable MCP-aware prompts
- [ ] 7.4.6 Enhance agent system:
  - [ ] 7.4.6.1 Give agents MCP tool access
  - [ ] 7.4.6.2 Create MCP-specialized agents
  - [ ] 7.4.6.3 Enable agent tool learning
- [ ] 7.4.7 Update CLI for MCP commands
- [ ] 7.4.8 Add LiveView MCP tool browser
- [ ] 7.4.9 Create MCP debugging tools
- [ ] 7.4.10 Build integration test suite

#### Unit Tests:
Create tests in `test/rubber_duck/mcp/integration_test.exs` to verify:
- [ ] 7.4.11 Test LLM provider MCP integration
- [ ] 7.4.12 Test memory system integration
- [ ] 7.4.13 Test workflow MCP steps
- [ ] 7.4.14 Test engine MCP adaptation
- [ ] 7.4.15 Test context enhancement
- [ ] 7.4.16 Test agent MCP usage
- [ ] 7.4.17 Test end-to-end MCP flows

### 7.5 MCP Security & Performance

Implement comprehensive security measures and performance optimizations for MCP integration.

#### Tasks:
- [ ] 7.5.1 Implement security measures:
  - [ ] 7.5.1.1 Input validation for all MCP calls
  - [ ] 7.5.1.2 Command injection prevention
  - [ ] 7.5.1.3 Path traversal protection
  - [ ] 7.5.1.4 Secrets management
- [ ] 7.5.2 Add authentication layer:
  - [ ] 7.5.2.1 mTLS for server connections
  - [ ] 7.5.2.2 JWT token validation
  - [ ] 7.5.2.3 API key rotation
- [ ] 7.5.3 Create audit logging:
  - [ ] 7.5.3.1 Tool invocation tracking
  - [ ] 7.5.3.2 Resource access logging
  - [ ] 7.5.3.3 Security event monitoring
- [ ] 7.5.4 Implement performance optimization:
  - [ ] 7.5.4.1 Connection pooling
  - [ ] 7.5.4.2 Request batching
  - [ ] 7.5.4.3 Result caching
  - [ ] 7.5.4.4 Lazy loading
- [ ] 7.5.5 Add rate limiting:
  - [ ] 7.5.5.1 Per-tool rate limits
  - [ ] 7.5.5.2 Global rate limiting
  - [ ] 7.5.5.3 Adaptive throttling
- [ ] 7.5.6 Create monitoring dashboard:
  - [ ] 7.5.6.1 MCP metrics visualization
  - [ ] 7.5.6.2 Performance analytics
  - [ ] 7.5.6.3 Security alerts
- [ ] 7.5.7 Implement failover strategies
- [ ] 7.5.8 Add request prioritization
- [ ] 7.5.9 Create security scanner
- [ ] 7.5.10 Build performance profiler

#### Unit Tests:
Create tests in `test/rubber_duck/mcp/security_test.exs` to verify:
- [ ] 7.5.11 Test input validation effectiveness
- [ ] 7.5.12 Test injection attack prevention
- [ ] 7.5.13 Test authentication mechanisms
- [ ] 7.5.14 Test audit logging completeness
- [ ] 7.5.15 Test rate limiting enforcement
- [ ] 7.5.16 Test performance under load
- [ ] 7.5.17 Test failover behavior

### 7.6 Advanced MCP Patterns

Implement sophisticated MCP usage patterns that showcase the protocol's full potential for AI-assisted development.

#### Tasks:
- [ ] 7.6.1 Create multi-tool workflows:
  - [ ] 7.6.1.1 GitHub + AWS integration
  - [ ] 7.6.1.2 Database + API composition
  - [ ] 7.6.1.3 Browser + Code analysis
- [ ] 7.6.2 Build reactive MCP systems:
  - [ ] 7.6.2.1 Event-driven tool activation
  - [ ] 7.6.2.2 Proactive context updates
  - [ ] 7.6.2.3 Automatic tool suggestions
- [ ] 7.6.3 Implement sampling patterns:
  - [ ] 7.6.3.1 Tool-initiated LLM calls
  - [ ] 7.6.3.2 Iterative refinement loops
  - [ ] 7.6.3.3 Multi-step reasoning
- [ ] 7.6.4 Create federated MCP networks:
  - [ ] 7.6.4.1 Cross-server tool sharing
  - [ ] 7.6.4.2 Distributed tool execution
  - [ ] 7.6.4.3 Consensus mechanisms
- [ ] 7.6.5 Build MCP marketplace integration:
  - [ ] 7.6.5.1 Tool discovery service
  - [ ] 7.6.5.2 Quality ratings
  - [ ] 7.6.5.3 Usage analytics
- [ ] 7.6.6 Add MCP-based plugins
- [ ] 7.6.7 Create MCP workflow templates
- [ ] 7.6.8 Implement MCP best practices
- [ ] 7.6.9 Build MCP testing harness
- [ ] 7.6.10 Create MCP documentation

#### Unit Tests:
Create tests in `test/rubber_duck/mcp/advanced_test.exs` to verify:
- [ ] 7.6.11 Test multi-tool coordination
- [ ] 7.6.12 Test reactive system behavior
- [ ] 7.6.13 Test sampling pattern execution
- [ ] 7.6.14 Test federated operations
- [ ] 7.6.15 Test marketplace integration
- [ ] 7.6.16 Test advanced error handling

### Phase 7 Integration Tests

Create comprehensive integration tests in `test/integration/phase_7_test.exs` to verify:
- [ ] 7.7.1 Test complete MCP client-server communication
- [ ] 7.7.2 Test tool discovery and invocation pipeline
- [ ] 7.7.3 Test MCP integration with existing systems
- [ ] 7.7.4 Test security measures effectiveness
- [ ] 7.7.5 Test performance optimization impact
- [ ] 7.7.6 Test advanced pattern implementations
- [ ] 7.7.7 Test multi-server MCP scenarios
- [ ] 7.7.8 Test MCP-enhanced code generation quality
- [ ] 7.7.9 Test MCP tool composition workflows
- [ ] 7.7.10 Test failover and recovery mechanisms

---

## Phase 8: Advanced Features & Production Readiness

This final phase implements production-critical features including background job processing, security measures, deployment configurations, and performance optimizations. This phase ensures the system is ready for real-world usage at scale.

### 8.1 Background Job Processing with Oban

Implement asynchronous job processing for resource-intensive operations like project indexing and batch analysis.

#### Tasks:
- [ ] 8.1.1 Add Oban dependency and configuration
- [ ] 8.1.2 Create Oban database migrations
- [ ] 8.1.3 Set up job queues:
  - [ ] 8.1.3.1 `:indexing` - File and project indexing
  - [ ] 8.1.3.2 `:analysis` - Code analysis jobs
  - [ ] 8.1.3.3 `:generation` - Batch code generation
  - [ ] 8.1.3.4 `:notification` - User notifications
- [ ] 8.1.4 Implement job workers:
  - [ ] 8.1.4.1 `ProjectIndexer` - Index entire projects
  - [ ] 8.1.4.2 `FileAnalyzer` - Analyze individual files
  - [ ] 8.1.4.3 `BatchGenerator` - Generate multiple files
  - [ ] 8.1.4.4 `ReportGenerator` - Create analysis reports
- [ ] 8.1.5 Add job scheduling for periodic tasks
- [ ] 8.1.6 Implement job progress tracking
- [ ] 8.1.7 Create job retry strategies
- [ ] 8.1.8 Build job monitoring dashboard
- [ ] 8.1.9 Add job priority system
- [ ] 8.1.10 Set up job telemetry

#### Unit Tests:
Create tests in `test/rubber_duck/workers/` directory to verify:

**ProjectIndexer Tests** (`project_indexer_test.exs`):
- [ ] 8.1.11 Test indexing all project files
- [ ] 8.1.12 Test handling large projects with batching
- [ ] 8.1.13 Test recovery from partial failures
- [ ] 8.1.14 Test progress tracking updates
- [ ] 8.1.15 Test file change detection
- [ ] 8.1.16 Test concurrent indexing safety

### 8.2 Security Implementation

Implement comprehensive security measures including authentication, authorization, input validation, and rate limiting.

#### Tasks:
- [ ] 8.2.1 Implement authentication system:
  - [ ] 8.2.1.1 JWT token generation
  - [ ] 8.2.1.2 API key management
  - [ ] 8.2.1.3 OAuth2 integration
  - [ ] 8.2.1.4 Session management
- [ ] 8.2.2 Add authorization layer:
  - [ ] 8.2.2.1 Role-based access control (RBAC)
  - [ ] 8.2.2.2 Project-level permissions
  - [ ] 8.2.2.3 Resource-level authorization
- [ ] 8.2.3 Create input validation:
  - [ ] 8.2.3.1 Code injection prevention
  - [ ] 8.2.3.2 Path traversal protection
  - [ ] 8.2.3.3 Size limits enforcement
- [ ] 8.2.4 Implement rate limiting:
  - [ ] 8.2.4.1 Token bucket per user
  - [ ] 8.2.4.2 Endpoint-specific limits
  - [ ] 8.2.4.3 DDoS protection
- [ ] 8.2.5 Add security scanning:
  - [ ] 8.2.5.1 Dependency vulnerability checks
  - [ ] 8.2.5.2 Code security analysis
- [ ] 8.2.6 Set up audit logging
- [ ] 8.2.7 Implement data encryption at rest

#### Unit Tests:
Create tests in `test/rubber_duck/security/` directory:

**Authentication Tests** (`authentication_test.exs`):
- [ ] 8.2.8 Test JWT token generation and verification
- [ ] 8.2.9 Test token expiration handling
- [ ] 8.2.10 Test API key validation
- [ ] 8.2.11 Test OAuth2 flow
- [ ] 8.2.12 Test session management
- [ ] 8.2.13 Test multi-factor authentication

**Authorization Tests** (`authorization_test.exs`):
- [ ] 8.2.14 Test project permission enforcement
- [ ] 8.2.15 Test role-based access
- [ ] 8.2.16 Test resource-level permissions
- [ ] 8.2.17 Test permission inheritance
- [ ] 8.2.18 Test cross-project isolation
- [ ] 8.2.19 Test admin overrides

**Input Validation Tests** (`validation_test.exs`):
- [ ] 8.2.20 Test path traversal prevention
- [ ] 8.2.21 Test code input sanitization
- [ ] 8.2.22 Test size limit enforcement
- [ ] 8.2.23 Test injection attack prevention
- [ ] 8.2.24 Test file type validation
- [ ] 8.2.25 Test rate limiting

### 8.3 Monitoring and Observability

Implement comprehensive monitoring, logging, and observability features for production operations.

#### Tasks:
- [ ] 8.3.1 Set up Telemetry integration:
  - [ ] 8.3.1.1 Define telemetry events
  - [ ] 8.3.1.2 Create metric reporters
  - [ ] 8.3.1.3 Add custom measurements
- [ ] 8.3.2 Implement structured logging:
  - [ ] 8.3.2.1 JSON log formatting
  - [ ] 8.3.2.2 Log aggregation setup
  - [ ] 8.3.2.3 Correlation ID tracking
- [ ] 8.3.3 Create health check endpoints:
  - [ ] 8.3.3.1 Database connectivity
  - [ ] 8.3.3.2 LLM provider status
  - [ ] 8.3.3.3 Memory usage
  - [ ] 8.3.3.4 Job queue health
- [ ] 8.3.4 Add performance monitoring:
  - [ ] 8.3.4.1 Request duration tracking
  - [ ] 8.3.4.2 Database query analysis
  - [ ] 8.3.4.3 Memory profiling
- [ ] 8.3.5 Set up error tracking:
  - [ ] 8.3.5.1 Sentry integration
  - [ ] 8.3.5.2 Error aggregation
  - [ ] 8.3.5.3 Alert configuration
- [ ] 8.3.6 Build metrics dashboard
- [ ] 8.3.7 Implement distributed tracing
- [ ] 8.3.8 Create SLO monitoring
- [ ] 8.3.9 Add LLM enhancement metrics:
  - [ ] 8.3.9.1 CoT reasoning quality tracking
  - [ ] 8.3.9.2 RAG retrieval precision monitoring
  - [ ] 8.3.9.3 Self-correction effectiveness metrics
  - [ ] 8.3.9.4 Enhancement technique A/B testing

#### Unit Tests:
Create tests in `test/rubber_duck/monitoring/` directory:

**Telemetry Tests** (`telemetry_test.exs`):
- [ ] 8.3.10 Test completion event emission
- [ ] 8.3.11 Test LLM request latency tracking
- [ ] 8.3.12 Test custom metric recording
- [ ] 8.3.13 Test event metadata inclusion
- [ ] 8.3.14 Test metric aggregation
- [ ] 8.3.15 Test performance measurements
- [ ] 8.3.16 Test LLM enhancement metrics

**Health Check Tests** (`health_test.exs`):
- [ ] 8.3.17 Test comprehensive health endpoint
- [ ] 8.3.18 Test detailed health with issues
- [ ] 8.3.19 Test individual component checks
- [ ] 8.3.20 Test health status aggregation
- [ ] 8.3.21 Test timeout handling
- [ ] 8.3.22 Test graceful degradation

**Metrics Tests** (`metrics_test.exs`):
- [ ] 8.3.23 Test request metric tracking
- [ ] 8.3.24 Test memory usage monitoring
- [ ] 8.3.25 Test business metric collection
- [ ] 8.3.26 Test metric persistence
- [ ] 8.3.27 Test dashboard data aggregation
- [ ] 8.3.28 Test alert triggering

### 8.4 Deployment and Scaling

Implement deployment configurations and scaling strategies for production environments.

#### Tasks:
- [ ] 8.4.1 Create Docker configuration:
  - [ ] 8.4.1.1 Multi-stage Dockerfile
  - [ ] 8.4.1.2 Docker Compose setup
  - [ ] 8.4.1.3 Health check configuration
  - [ ] 8.4.1.4 Volume management
  - [ ] 8.4.1.5 MCP server containerization
- [ ] 8.4.2 Set up Kubernetes deployment:
  - [ ] 8.4.2.1 Deployment manifests
  - [ ] 8.4.2.2 Service configuration
  - [ ] 8.4.2.3 Ingress rules
  - [ ] 8.4.2.4 ConfigMaps and Secrets
  - [ ] 8.4.2.5 MCP service mesh integration
- [ ] 8.4.3 Implement clustering:
  - [ ] 8.4.3.1 libcluster configuration
  - [ ] 8.4.3.2 Node discovery
  - [ ] 8.4.3.3 Distributed Erlang setup
  - [ ] 8.4.3.4 State synchronization
  - [ ] 8.4.3.5 MCP registry distribution
- [ ] 8.4.4 Add horizontal scaling:
  - [ ] 8.4.4.1 Load balancer configuration
  - [ ] 8.4.4.2 Session affinity
  - [ ] 8.4.4.3 Autoscaling rules
  - [ ] 8.4.4.4 MCP connection pooling
- [ ] 8.4.5 Create database migrations strategy
- [ ] 8.4.6 Set up blue-green deployment
- [ ] 8.4.7 Implement feature flags
- [ ] 8.4.8 Add CDN configuration
- [ ] 8.4.9 Create backup and restore procedures
- [ ] 8.4.10 Build disaster recovery plan

#### Unit Tests:
Create tests in `test/rubber_duck/deployment/` directory:

**Clustering Tests** (`clustering_test.exs`):
- [ ] 8.4.11 Test node discovery and connection
- [ ] 8.4.12 Test state synchronization across nodes
- [ ] 8.4.13 Test node failure handling
- [ ] 8.4.14 Test load distribution
- [ ] 8.4.15 Test cluster reformation
- [ ] 8.4.16 Test split-brain resolution

**Deployment Tests** (`deployment_test.exs`):
- [ ] 8.4.17 Test Docker image build
- [ ] 8.4.18 Test Kubernetes manifest validity
- [ ] 8.4.19 Test configuration management
- [ ] 8.4.20 Test secret handling
- [ ] 8.4.21 Test rollback procedures
- [ ] 8.4.22 Test zero-downtime deployment

**Feature Flag Tests** (`feature_flags_test.exs`):
- [ ] 8.4.23 Test feature toggle functionality
- [ ] 8.4.24 Test gradual rollout percentages
- [ ] 8.4.25 Test user-specific flags
- [ ] 8.4.26 Test flag persistence
- [ ] 8.4.27 Test A/B testing support
- [ ] 8.4.28 Test flag inheritance

### Phase 8 Integration Tests

Create comprehensive integration tests in `test/integration/phase_8_test.exs` to verify:
- [ ] 8.5.1 Test end-to-end secure workflow with monitoring
- [ ] 8.5.2 Test high load handling with rate limiting
- [ ] 8.5.3 Test monitoring captures system health
- [ ] 8.5.4 Test graceful degradation when services fail
- [ ] 8.5.5 Test distributed deployment scenario
- [ ] 8.5.6 Test backup and restore procedures
- [ ] 8.5.7 Test feature flag integration
- [ ] 8.5.8 Test MCP server scaling
- [ ] 8.5.9 Test security controls with MCP
- [ ] 8.5.10 Test production readiness criteria

### Final System Integration Tests

Create final system tests in `test/integration/complete_system_test.exs` to verify:
- [ ] 8.6.1 Test full coding assistant workflow from project creation to code generation
- [ ] 8.6.2 Test system behavior under sustained load
- [ ] 8.6.3 Test monitoring and alerting pipeline
- [ ] 8.6.4 Test multi-user collaboration scenarios
- [ ] 8.6.5 Test disaster recovery procedures
- [ ] 8.6.6 Test performance meets SLOs
- [ ] 8.6.7 Test security controls are effective
- [ ] 8.6.8 Test MCP integration enhances code quality
- [ ] 8.6.9 Test planning system with MCP tools
- [ ] 8.6.10 Test complete system resilience

---

