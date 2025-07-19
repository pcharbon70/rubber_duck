# RubberDuck Implementation Plan - Part 2 (Phases 5-7)

This document contains the detailed implementation plans for Phases 5-7 of the RubberDuck project. For the overall project status and other phases, see:
- [Main implementation plan](implementation_plan.md) - Overview and status
- [Part 1](implementation_part_1.md) - Phases 1-4 (Foundation through Workflow Orchestration)
- [Part 3](implementation_part_3.md) - Phases 8-9 (Instruction Templating through Production Readiness)

## Table of Contents
5. [Phase 5: Real-time Communication & UI](#phase-5-real-time-communication--ui)
6. [Phase 6: Conversational AI System](#phase-6-conversational-ai-system)
7. [Phase 7: Planning Enhancement System](#phase-7-planning-enhancement-system)

---

## Phase 5: Real-time Communication & UI

This phase implements the user-facing interfaces including Phoenix Channels for real-time communication, LiveView for the web interface, and a sophisticated CLI/TUI. These interfaces provide interactive access to all the coding assistant capabilities with dynamic LLM configuration support.

### 5.1 Phoenix Channels Setup ✅ ~85% Complete

Implement WebSocket-based real-time communication for streaming code completions and live updates.

**Status**: Core infrastructure implemented with multiple channels, authentication, presence tracking, rate limiting, and message queuing. Production-readiness features pending.

#### Tasks:
- [x] 5.1.1 Configure Phoenix endpoint for WebSocket support
- [x] 5.1.2 Create `RubberDuckWeb.UserSocket` module
- [x] 5.1.3 Implement authentication for socket connections (token + API key)
- [x] 5.1.4 Create `RubberDuckWeb.CodeChannel`:
  - [x] 5.1.4.1 Handle join with project authorization
  - [x] 5.1.4.2 Implement completion streaming
  - [x] 5.1.4.3 Add presence tracking
  - [x] 5.1.4.4 Handle collaborative editing events
- [x] 5.1.5 Set up channel tests infrastructure
- [x] 5.1.6 Implement reconnection logic (client-side needed)
- [ ] 5.1.7 Add channel metrics and monitoring
- [x] 5.1.8 Create channel rate limiting (via RateLimiter)
- [x] 5.1.9 Build message queuing for offline users
- [ ] 5.1.10 Document channel protocol

#### Unit Tests:
Create tests in `test/rubber_duck_web/channels/code_channel_test.exs` to verify:
- [x] 5.1.11 Test channel join with authentication
- [x] 5.1.12 Test completion streaming in chunks
- [x] 5.1.13 Test completion error handling
- [x] 5.1.14 Test cursor position broadcasting
- [x] 5.1.15 Test user presence tracking
- [ ] 5.1.16 Test message queuing for offline users
- [ ] 5.1.17 Test rate limiting enforcement

#### Implementation Summary:

**✅ Completed Features:**

1. **Core Infrastructure**:
   - Phoenix endpoint configured with WebSocket at `/socket`
   - UserSocket with token and API key authentication
   - Multiple channel modules: CodeChannel, AnalysisChannel, WorkspaceChannel, ConversationChannel, MCPChannel

2. **Authentication & Security**:
   - Token-based auth with Phoenix.Token (24-hour expiry)
   - API key authentication (placeholder validation)
   - User ID assignment and socket ID generation

3. **Channel Features**:
   - CodeChannel with code generation, completion, refactoring, analysis
   - Streaming support for long-running operations
   - Request ID tracking for async operations
   - Integration with Engine Manager

4. **Collaborative Features**:
   - RubberDuckWeb.Presence module
   - User activity tracking and cursor positions
   - After-join presence registration

5. **Infrastructure Components**:
   - MessageQueue with ETS storage (1000 msg limit, 24hr TTL)
   - RateLimiter with token bucket algorithm and priority queues
   - Circuit breakers for failing operations

**❌ Pending Improvements:**

1. **Production Readiness**:
   - Real API key validation (currently placeholder)
   - Proper `check_origin` configuration (currently false)
   - Message encryption for sensitive data

2. **Monitoring & Metrics**:
   - Telemetry events for channel operations
   - WebSocket connection metrics
   - Message processing latency tracking
   - Error rate monitoring

3. **Performance**:
   - Connection pooling
   - Message batching for bulk operations
   - Backpressure handling

4. **Documentation**:
   - Comprehensive channel protocol docs
   - Client integration examples
   - WebSocket best practices guide



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
  - [ ] 5.2.11.1 LLM Service for completions with dynamic configuration
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
  - [ ] 5.2.15.4 LLM provider status with dynamic configuration

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
- [ ] 5.2.25 Integrate with unified command system:
  - [ ] 5.2.25.1 Command execution through LiveView
  - [ ] 5.2.25.2 Dynamic LLM configuration in UI
  - [ ] 5.2.25.3 Real-time command feedback

#### Unit Tests:

**CodingSessionLive Tests** (`test/rubber_duck_web/live/coding_session_live_test.exs`):
- [ ] 5.2.26 Test mount with project authorization
- [ ] 5.2.27 Test PubSub subscription setup
- [ ] 5.2.28 Test file selection and content loading
- [ ] 5.2.29 Test editor content change handling
- [ ] 5.2.30 Test file save functionality
- [ ] 5.2.31 Test real-time update broadcasting

**Component Tests** (`test/rubber_duck_web/components/`):
- [ ] 5.2.32 Test Monaco Editor component rendering
- [ ] 5.2.33 Test Chat Panel message streaming
- [ ] 5.2.34 Test File Tree navigation
- [ ] 5.2.35 Test suggestion application
- [ ] 5.2.36 Test context panel updates

**Integration Tests** (`test/rubber_duck_web/live/integration_test.exs`):
- [ ] 5.2.37 Test complete coding session flow
- [ ] 5.2.38 Test multi-user collaboration
- [ ] 5.2.39 Test LLM response streaming
- [ ] 5.2.40 Test code analysis integration
- [ ] 5.2.41 Test memory persistence across sessions

**JavaScript Hook Tests** (`test/assets/js/hooks/`):
- [ ] 5.2.42 Test Monaco Editor mounting
- [ ] 5.2.43 Test content synchronization
- [ ] 5.2.44 Test completion provider
- [ ] 5.2.45 Test external update handling
- [ ] 5.2.46 Test cursor position broadcasting


### 5.3 TUI (Terminal UI) Implementation with Go and Bubble Tea ✅ ~90% Complete

Build a modern terminal user interface using Go and the Bubble Tea framework, leveraging the Elm Architecture for predictable state management and seamless Phoenix WebSocket integration with chat-focused interface.

**Current Status**: The TUI implementation is approximately 90% complete with recent chat-focused interface implementation. Core functionality including the Model-View-Update architecture, Phoenix WebSocket integration, UI components, and comprehensive testing infrastructure have been implemented.

**Recent Major Update**: Successfully implemented chat-focused interface where chat is the primary view and file tree/editor are optional toggleable panels.

#### Tasks:

**Project Setup and Dependencies:**
- [x] 5.3.1 Create Go module `github.com/rubber_duck/tui`
- [x] 5.3.2 Add dependencies to `go.mod`:
  - [x] 5.3.2.1 `github.com/charmbracelet/bubbletea` - Core TUI framework
  - [x] 5.3.2.2 `github.com/charmbracelet/bubbles` - Component library
  - [x] 5.3.2.3 `github.com/charmbracelet/lipgloss` - Styling system
  - [x] 5.3.2.4 `github.com/nshafer/phx` - Phoenix channels client
  - [ ] 5.3.2.5 `github.com/alecthomas/chroma` - Syntax highlighting
- [x] 5.3.3 Set up project structure:
  - [x] 5.3.3.1 `cmd/rubber_duck_tui/main.go` - Entry point
  - [x] 5.3.3.2 `internal/ui/` - UI components
  - [x] 5.3.3.3 `internal/phoenix/` - WebSocket integration
  - [x] 5.3.3.4 `internal/commands/` - Command system

**Core Architecture Implementation:**
- [x] 5.3.4 Implement base Model-Update-View architecture:
  - [x] 5.3.4.1 Define `Model` struct with application state
  - [x] 5.3.4.2 Create message types for all events
  - [x] 5.3.4.3 Implement `Update` function for state transitions
  - [x] 5.3.4.4 Build `View` function with Lipgloss layouts
- [x] 5.3.5 Create state management system:
  - [x] 5.3.5.1 File tree state and operations
  - [x] 5.3.5.2 Editor state with content tracking
  - [x] 5.3.5.3 Output pane state for results
  - [x] 5.3.5.4 WebSocket connection state
  - [x] 5.3.5.5 Chat state with message history
  - [x] 5.3.5.6 Panel visibility state for dynamic layout

**Chat-Focused Interface Implementation:**
- [x] 5.3.6 Implement chat component (`internal/ui/chat.go`):
  - [x] 5.3.6.1 Scrollable message history using viewport
  - [x] 5.3.6.2 Multi-line input with textarea
  - [x] 5.3.6.3 Message type support (user, assistant, system, error)
  - [x] 5.3.6.4 Timestamp and author tracking
  - [x] 5.3.6.5 Theme integration and styling
- [x] 5.3.7 Create dynamic layout system:
  - [x] 5.3.7.1 Chat takes remaining space after optional panels
  - [x] 5.3.7.2 Automatic width calculation based on visible components
  - [x] 5.3.7.3 Minimum width enforcement for usability
  - [x] 5.3.7.4 Panel toggle functionality
- [x] 5.3.8 Add keyboard controls for chat interface:
  - [x] 5.3.8.1 `Ctrl+F`: Toggle file tree visibility
  - [x] 5.3.8.2 `Ctrl+E`: Toggle editor visibility
  - [x] 5.3.8.3 `Ctrl+/`: Focus chat input
  - [x] 5.3.8.4 `Tab`: Cycle through visible panes
  - [x] 5.3.8.5 `Enter`: Send message
  - [x] 5.3.8.6 `Ctrl+Enter`: Newline in chat

**Phoenix WebSocket Integration:**
- [x] 5.3.9 Implement Phoenix channel client:
  - [x] 5.3.9.1 Connection management with auto-reconnect
  - [x] 5.3.9.2 Channel join/leave operations
  - [x] 5.3.9.3 Message serialization/deserialization
  - [x] 5.3.9.4 Event subscription system
- [x] 5.3.10 Create WebSocket command adapters:
  - [x] 5.3.10.1 File analysis commands
  - [x] 5.3.10.2 Code generation commands
  - [x] 5.3.10.3 Completion requests
  - [x] 5.3.10.4 Refactoring operations
  - [x] 5.3.10.5 Chat message integration
- [x] 5.3.11 Implement streaming support:
  - [x] 5.3.11.1 Stream start/data/end message handling
  - [x] 5.3.11.2 Progressive output rendering
  - [ ] 5.3.11.3 Stream cancellation
  - [ ] 5.3.11.4 Error recovery

**UI Component Development:**
- [x] 5.3.12 Build file tree component:
  - [x] 5.3.12.1 Recursive tree rendering with Lipgloss
  - [x] 5.3.12.2 Expand/collapse functionality
  - [x] 5.3.12.3 File type icons and styling
  - [x] 5.3.12.4 Keyboard navigation (j/k, enter)
  - [x] 5.3.12.5 File selection events
- [x] 5.3.13 Create code editor component:
  - [x] 5.3.13.1 Integrate Bubbles textarea
  - [ ] 5.3.13.2 Syntax highlighting with Chroma
  - [x] 5.3.13.3 Line numbers and cursor position
  - [x] 5.3.13.4 Content change tracking
  - [ ] 5.3.13.5 Auto-save functionality
- [x] 5.3.14 Implement output/results pane:
  - [x] 5.3.14.1 Scrollable viewport with Bubbles
  - [x] 5.3.14.2 Formatted analysis results
  - [x] 5.3.14.3 Error display with styling
  - [x] 5.3.14.4 Progress indicators
  - [ ] 5.3.14.5 Clear and filter options
- [x] 5.3.15 Build command palette:
  - [x] 5.3.15.1 Fuzzy search with text input
  - [x] 5.3.15.2 Command list with descriptions
  - [x] 5.3.15.3 Keyboard shortcuts display
  - [x] 5.3.15.4 Command execution system
  - [ ] 5.3.15.5 Recent commands history

**Layout and Navigation:**
- [x] 5.3.16 Implement responsive layout system:
  - [x] 5.3.16.1 Dynamic layout with chat as primary pane
  - [x] 5.3.16.2 Dynamic width calculation
  - [x] 5.3.16.3 Terminal resize handling
  - [x] 5.3.16.4 Minimum size constraints
- [x] 5.3.17 Create navigation system:
  - [x] 5.3.17.1 Tab cycling between panes
  - [x] 5.3.17.2 Vim-style navigation keys
  - [x] 5.3.17.3 Focus indicators
  - [x] 5.3.17.4 Panel-specific controls
  - [ ] 5.3.17.5 Mouse support where available
- [x] 5.3.18 Add status bar:
  - [x] 5.3.18.1 Connection status indicator
  - [x] 5.3.18.2 Current file path
  - [x] 5.3.18.3 Operation progress
  - [x] 5.3.18.4 Key hints and active panels

**Advanced Features:**
- [x] 5.3.19 Implement modal dialogs:
  - [x] 5.3.19.1 Confirmation dialogs
  - [x] 5.3.19.2 Input prompts
  - [x] 5.3.19.3 Settings dialog
  - [x] 5.3.19.4 Help overlay
- [x] 5.3.20 Add command integration:
  - [x] 5.3.20.1 Messages starting with `/` parsed as commands
  - [x] 5.3.20.2 Regular messages sent as chat commands
  - [x] 5.3.20.3 Integration with existing command router
  - [x] 5.3.20.4 Echo functionality for testing
- [ ] 5.3.21 Add theming support:
  - [ ] 5.3.21.1 Color scheme definitions
  - [ ] 5.3.21.2 Dark/light mode toggle
  - [ ] 5.3.21.3 Custom style configuration
- [ ] 5.3.22 Create performance optimizations:
  - [ ] 5.3.22.1 Render caching for static components
  - [ ] 5.3.22.2 Debounced file operations
  - [ ] 5.3.22.3 Lazy loading for large files
  - [ ] 5.3.22.4 Virtual scrolling for file tree

#### Unit Tests:
Create tests in `tui/internal/ui/*_test.go` files to verify:
- [x] 5.3.23 Test Model initialization and state
- [x] 5.3.24 Test Update function message handling
- [x] 5.3.25 Test View rendering without errors
- [x] 5.3.26 Test WebSocket connection lifecycle
- [x] 5.3.27 Test chat component functionality
- [x] 5.3.28 Test dynamic layout calculations
- [x] 5.3.29 Test panel toggle operations
- [x] 5.3.30 Test keyboard shortcut handling
- [ ] 5.3.31 Test file tree navigation operations
- [ ] 5.3.32 Test editor content synchronization
- [ ] 5.3.33 Test command palette filtering
- [ ] 5.3.34 Test error recovery mechanisms

#### Integration Tests:
Create tests in `tui/test/integration_test.go` to verify:
- [x] 5.3.35 Test full TUI startup and initialization
- [x] 5.3.36 Test Phoenix channel communication
- [x] 5.3.37 Test file analysis workflow
- [x] 5.3.38 Test code generation streaming
- [x] 5.3.39 Test chat-focused interface workflow
- [x] 5.3.40 Test panel visibility toggling
- [ ] 5.3.41 Test concurrent operations
- [ ] 5.3.42 Test reconnection after disconnect
- [ ] 5.3.43 Test state persistence

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

### 5.4 System Error Handling Enhancement ✅ Completed

Implement comprehensive error handling and reporting system improvements to ensure robust system operation.

**Status**: Successfully implemented Tower error reporting configuration fixes and system stability improvements.

#### Tasks:
- [x] 5.4.1 Fix Tower error reporting configuration:
  - [x] 5.4.1.1 Correct Tower reporter configuration format in dev.exs and prod.exs
  - [x] 5.4.1.2 Change from keyword list to map format for reporters
  - [x] 5.4.1.3 Use correct Tower.EphemeralReporter instead of non-existent Tower.LogReporter
  - [x] 5.4.1.4 Move reporter-specific options to separate config blocks
- [x] 5.4.2 Create comprehensive error testing:
  - [x] 5.4.2.1 Add test to validate Tower configuration format
  - [x] 5.4.2.2 Ensure reporters are configured as module atoms
  - [x] 5.4.2.3 Verify reporter module availability
- [x] 5.4.3 Improve system stability:
  - [x] 5.4.3.1 Fix command processor startup in application supervision tree
  - [x] 5.4.3.2 Resolve JSON encoding issues in CLI channels
  - [x] 5.4.3.3 Add proper error handling for double JSON encoding

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

### 5.5 Phase 5 Integration Tests

Create comprehensive integration tests in `test/integration/phase_5_test.exs` to verify:
- [ ] 5.5.1 Test LiveView and Channel coordination
- [ ] 5.5.2 Test CLI triggers real-time updates
- [ ] 5.5.3 Test settings sync across interfaces
- [ ] 5.5.4 Test analysis results consistency
- [ ] 5.5.5 Test multiple concurrent WebSocket connections
- [ ] 5.5.6 Test LiveView rapid update handling
- [ ] 5.5.7 Test TUI state management with chat interface
- [ ] 5.5.8 Test dynamic LLM configuration across all interfaces
- [ ] 5.5.9 Test unified command system consistency
- [ ] 5.5.10 Test error handling and recovery mechanisms

---

## Phase 6: Conversational AI System 🚧 ~30% Complete

This phase implements a memory-enhanced conversational AI system that provides natural language interaction across all client interfaces (CLI, LiveView, TUI, WebSocket). The system integrates with the 3-tier memory architecture to maintain context and supports both chat and command-based interactions.

**Current Status**: Foundation implemented with core conversation resources, Phoenix channels, and conversation routing. Advanced memory integration and multi-client features pending.

### 6.1 Memory-Enhanced Conversation Engine 🚧 ~20% Complete

Implement the core conversation engine using GenServer architecture with ETS-based short-term memory and pattern extraction capabilities.

**Implemented**:
- ✅ Core Conversation Ash resources (Conversation, Message, ConversationContext)
- ✅ Basic conversation domain setup
- ✅ CoT.ConversationManager GenServer for reasoning sessions

**Pending**: ETS-based memory, pattern extraction, lifecycle management

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

### 6.2 Multi-Client Phoenix Channel Architecture 🚧 ~40% Complete

Build Phoenix Channels infrastructure supporting heterogeneous clients with adaptive formatting and real-time communication.

**Implemented**:
- ✅ ConversationChannel with real-time messaging
- ✅ User authentication and session management
- ✅ LLM preference management integration
- ✅ Message streaming and typing indicators
- ✅ Context preservation across messages
- ✅ Error handling and response formatting

**Pending**: Client type detection, format adaptation, MessagePack, rate limiting

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

### 6.3 Conversational Context Management ❌ Not Started

Implement sophisticated context management with DynamicSupervisor orchestration and memory system integration.

**Status**: Core conversation routing implemented, but DynamicSupervisor architecture and memory bridge not yet built.

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

### 6.4 Command-Chat Hybrid Interface ❌ Not Started

Build intelligent intent classification and command suggestion system for seamless mixed interactions.

**Status**: Conversation engines route messages, but hybrid command/chat interface not implemented.

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

### 6.5 Performance & Security Implementation ❌ Not Started

Optimize performance with ETS configurations and implement comprehensive security measures.

**Status**: Basic authentication in channels, but comprehensive security and performance optimizations pending.

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
  - [ ] 6.5.2.1 AES-256-GCM implementation
  - [ ] 6.5.2.2 Key rotation system
  - [ ] 6.5.2.3 Encrypted storage
  - [ ] 6.5.2.4 Secure transmission
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

### Phase 6 Implementation Summary

**Overall Progress**: ~30% Complete

#### ✅ Completed Components:

1. **Core Conversation Infrastructure**:
   - Ash-based conversation resources (Conversation, Message, ConversationContext)
   - Conversation domain with basic CRUD operations
   - Message storage with role-based structure

2. **Phoenix Channel Implementation**:
   - Full-featured ConversationChannel with WebSocket support
   - Real-time messaging with streaming responses
   - User authentication and session management
   - LLM preference management (provider/model selection)
   - Error handling and graceful degradation

3. **Conversation Routing System**:
   - ConversationRouter engine for intelligent message routing
   - Specialized conversation engines:
     - SimpleConversation for basic queries
     - ComplexConversation for multi-step problems
     - AnalysisConversation for code analysis
     - GenerationConversation for code generation
     - ProblemSolver for debugging
     - MultiStepConversation for complex tasks

4. **Chain-of-Thought Integration**:
   - CoT.ConversationManager GenServer
   - Session tracking and caching
   - Statistics collection

#### ❌ Pending Implementation:

1. **Memory Enhancement** (Section 6.1):
   - ETS-based short-term memory tables
   - Pattern extraction and frequency analysis
   - Sliding window buffers
   - Process isolation and lifecycle management

2. **Multi-Client Support** (Section 6.2):
   - Client type detection and capability negotiation
   - Format adaptation (CLI/TUI/LiveView/WebSocket)
   - MessagePack serialization
   - Rate limiting and presence tracking

3. **Advanced Context Management** (Section 6.3):
   - DynamicSupervisor architecture
   - Memory bridge to 3-tier system
   - Multi-client presence tracking
   - Recovery with snapshot/replay

4. **Hybrid Interface** (Section 6.4):
   - Natural language command extraction
   - Intent classification
   - Command suggestions
   - Unified execution pipeline

5. **Performance & Security** (Section 6.5):
   - ETS optimization
   - Comprehensive rate limiting
   - Token-based authentication
   - Encryption layer
   - Monitoring and audit logging

#### Key Achievements:
- Working real-time conversation system
- Per-user LLM configuration support
- Intelligent message routing to specialized engines
- Solid foundation for future enhancements

#### Next Steps:
To complete Phase 6, focus should be on:
1. Implementing ETS-based memory management
2. Building the DynamicSupervisor architecture
3. Creating the memory bridge to integrate with 3-tier system
4. Adding multi-client format adaptation
5. Implementing security and performance optimizations

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

#### Unit Tests:
- [ ] 7.1.10 Test Plan resource creation and validation
- [ ] 7.1.11 Test Task resource with dependency management
- [ ] 7.1.12 Test constraint enforcement
- [ ] 7.1.13 Test validation result tracking
- [ ] 7.1.14 Test authorization policies

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
