# Feature: CLI Conversation Support

## Summary
Add conversation command support to the RubberDuck escript CLI client, enabling users to start, list, manage, and interact with AI conversations from the command line. This requires handling two-way real-time communication between client and server.

## Requirements
- [ ] Add conversation command to escript CLI parser (`RubberDuck.CLIClient.Main`)
- [ ] Support conversation subcommands: start, list, show, send, delete, chat
- [ ] Implement interactive chat mode for real-time two-way conversation flow
- [ ] Handle WebSocket connection for persistent conversation sessions
- [ ] Support both one-shot commands (list, show, delete) and interactive mode (chat)
- [ ] Provide clear help documentation for conversation commands
- [ ] Support conversation-specific options (type, title, conversation ID)
- [ ] Format conversation output appropriately for CLI display
- [ ] Handle authentication properly for CLI client
- [ ] Manage connection lifecycle (connect, maintain, disconnect)
- [ ] Handle streaming responses from LLM via server

## Research Summary
### Existing Usage Rules Checked
- No specific usage rules found for CLI implementation
- Conversation handler already exists and is registered in command processor

### Documentation Reviewed
- Optimus library used for CLI parsing in escript client
- Command specifications follow consistent pattern with args, options, and flags
- CLI commands are routed through UnifiedIntegration for escript version
- Authentication handled before command execution
- Existing WebSocket infrastructure in `RubberDuck.CLIClient.Client`
- Phoenix.Channels.GenSocketClient already used for persistent connections
- Transport layer implemented in `RubberDuck.CLIClient.Transport`
- Streaming support already exists for long-running operations

### Existing Patterns Found
- Command specs defined in private functions: `lib/rubber_duck/cli_client/main.ex:246-398` (analyze_spec, etc.)
- Subcommands supported via nested specifications: `lib/rubber_duck/cli_client/main.ex:343-398` (llm_spec)
- CLI client checks authentication before executing commands: `lib/rubber_duck/cli_client/main.ex:142-150`
- Args converted to unified format: `lib/rubber_duck/cli_client/main.ex:181-184`
- Special handling for auth command bypasses auth check: `lib/rubber_duck/cli_client/main.ex:137-139`
- WebSocket client manages connection lifecycle: `lib/rubber_duck/cli_client/client.ex`
- Streaming responses handled via event handlers: `lib/rubber_duck/cli_client/client.ex:172-180`
- Channel communication pattern: push commands to "cli:commands" channel

### Technical Approach
1. Add `conversation_spec()` function to `RubberDuck.CLIClient.Main` following existing patterns
2. Define subcommands for: start, list, show, send, delete, chat
3. Add appropriate args and options for each subcommand:
   - start: title (arg), type (option) - creates conversation and returns ID
   - list: no args, format option inherited - one-shot command
   - show: conversation_id (arg) - one-shot command to display history
   - send: message (arg), conversation_id (option) - one-shot send and receive
   - delete: conversation_id (arg) - one-shot command
   - chat: conversation_id (optional arg) - enters interactive mode
4. For interactive chat mode:
   - Establish WebSocket connection to server
   - Create a read-eval-print loop (REPL) for user input
   - Handle incoming messages asynchronously while accepting input
   - Display streaming responses as they arrive
   - Support commands like /exit, /help, /clear
   - Gracefully handle connection drops and reconnection
5. Leverage existing WebSocket client infrastructure (`phoenix_gen_socket_client`)
6. Route one-shot commands through UnifiedIntegration
7. Create new interactive handler for chat mode that maintains connection

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Complex async handling in CLI | High | Use proper supervision and error boundaries |
| Connection drops during chat | Medium | Implement reconnection logic with backoff |
| Streaming response display | Medium | Buffer and format output properly |
| Concurrent I/O (input + output) | High | Use separate processes for input and display |
| Breaking existing CLI interface | Low | Only adding new commands, not modifying existing |
| Message formatting in CLI | Low | Escape and handle special characters properly |
| Escript limitations with processes | Medium | Ensure proper process cleanup on exit |

## Implementation Checklist
- [ ] Add conversation_spec to `lib/rubber_duck/cli_client/main.ex`
- [ ] Add conversation to subcommands list in `RubberDuck.CLIClient.Main`
- [ ] Create `RubberDuck.CLIClient.ConversationHandler` module for interactive chat
- [ ] Implement WebSocket connection management for chat mode
- [ ] Create REPL loop with concurrent input/output handling
- [ ] Implement streaming response display with proper formatting
- [ ] Add connection retry logic with exponential backoff
- [ ] Handle process cleanup on exit signals
- [ ] Update build_unified_args to handle conversation subcommands
- [ ] Test one-shot commands (start, list, show, send, delete)
- [ ] Test interactive chat mode with streaming responses
- [ ] Test connection resilience (drops, reconnects)
- [ ] Verify authentication flow works properly
- [ ] Update --help output to show conversation commands

## Log
- Created feature branch: feature/007-cli-conversation-support
- Set up todo tracking for implementation tasks
- Added conversation_spec function with all subcommands
- Added conversation to CLI subcommands list
- Updated build_unified_args to handle conversation subcommands
- Tests passing for help command output
- Conversation commands now recognized by CLI parser
- Created ConversationHandler module for interactive chat mode
- Added special handling for conversation chat subcommand
- Implemented REPL with commands: /help, /exit, /clear, /history
- Added streaming response handling for real-time AI responses
- Added typing indicator during AI response generation
- Tests passing for conversation ID extraction
- Fixed WebSocket routing in UnifiedIntegration module
- Added connection detection logic to route between local and remote execution
- Implemented proper connection waiting with retry logic
- Added clear error message when server is not running
- All help commands working correctly for conversation subcommands
- Added LLM connection check before starting conversations
- Implemented ensure_llm_connected in conversation handler
- Added helpful error messages directing users to connect LLM first
- Both CLI chat mode and server-side handlers check for LLM connection

## Questions for Pascal
1. Should the interactive chat mode be the primary interface, or should we support both one-shot and interactive?
2. For the chat REPL, should we show typing indicators when the AI is responding?
3. Should we persist conversation history locally for offline viewing?