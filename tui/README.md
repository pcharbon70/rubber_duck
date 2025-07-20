# RubberDuck TUI

A modern Terminal User Interface (TUI) for RubberDuck, built with Go and the Bubble Tea framework.

## Features

- **Chat-focused interface**: Primary interaction through conversation with the AI assistant
- **Enhanced Chat Header**: Real-time display of connection status, model info, token usage, and message count
- **Phoenix WebSocket integration**: Real-time communication with the RubberDuck backend
- **Authentication Support**: Login/logout and API key management via auth channel
- **Model Selection**: Switch between different AI models (GPT-4, Claude, Llama2, etc.)
- **Token Tracking**: Monitor token usage with color-coded indicators (green/yellow/red)
- **Keyboard-driven navigation**: Efficient interaction without mouse
- **Optional panels**: File tree and editor can be toggled as needed
- **Command palette**: Quick access to commands with Ctrl+P

## Installation

```bash
cd tui
go build -o rubber_duck_tui ./cmd/tui
```

## Usage

### Basic Usage

```bash
# Connect to local Phoenix server (default port 5555)
./rubber_duck_tui

# Connect to custom server with separate auth endpoint
./rubber_duck_tui -url ws://example.com:4000/socket -auth-url ws://example.com:4000/auth_socket

# Connect with API key (auto-authenticates)
./rubber_duck_tui -api-key YOUR_API_KEY

# Enable debug logging
./rubber_duck_tui -debug
```

### API Key Configuration

The API key can be provided through multiple sources (in order of precedence):

1. **Command line flag**: `-api-key YOUR_API_KEY`
2. **Environment variable**: `RUBBER_DUCK_API_KEY`
3. **Config file**: `~/.rubber_duck/config.json` with format:
   ```json
   {
     "api_key": "YOUR_API_KEY"
   }
   ```

### Keyboard Shortcuts

#### Global Shortcuts
- `Ctrl+C` or `q`: Quit the application
- `Tab`: Switch between panes
- `Ctrl+P`: Open command palette
- `Ctrl+H`: Show help
- `Ctrl+F`: Toggle file tree
- `Ctrl+E`: Toggle editor
- `Ctrl+/`: Focus chat

#### Chat Shortcuts
- `Enter`: Send message
- `Ctrl+Enter` or `Ctrl+J`: Insert newline
- Arrow keys: Scroll through message history

#### Slash Commands (type in chat)
- `/help` or `/h` or `/?`: Show help
- `/model <name> [provider]`: Set AI model with optional provider
  - Example: `/model gpt4` or `/model gpt4 azure`
- `/provider <name>`: Set provider for current model
  - Example: `/provider openai` or `/provider custom`
- `/clear` or `/new`: Start new conversation
- `/tree` or `/files`: Toggle file tree
- `/editor` or `/edit`: Toggle editor
- `/commands` or `/cmds`: Show command palette
- `/login <username> <password>`: Login to server
- `/logout`: Logout from server
- `/status` or `/auth`: Check authentication status
- `/apikey generate`: Generate new API key
- `/apikey list`: List all API keys
- `/apikey revoke <key-id>`: Revoke an API key
- `/quit` or `/exit` or `/q`: Exit application

#### File Tree Shortcuts (when visible)
- `↑`/`↓` or `j`/`k`: Navigate files
- `Enter`: Select file

#### Model Selection
- `Ctrl+P`: Open command palette and type "Model:" to see available models
- Available models:
  - **Default**: System default model
  - **GPT-4**: OpenAI GPT-4
  - **GPT-3.5 Turbo**: OpenAI GPT-3.5 Turbo
  - **Claude 3 Opus**: Anthropic Claude 3 Opus
  - **Claude 3 Sonnet**: Anthropic Claude 3 Sonnet
  - **Llama 2**: Ollama Llama 2 (local)
  - **Mistral**: Ollama Mistral (local)
  - **CodeLlama**: Ollama CodeLlama (local)

## UI Layout

### Chat Interface with Header
```
┌─────────────────────────────────────────────────────────────┐
│ ● 💬 lobby | Model: gpt-4 (OpenAI)    Tokens: 245/8192 | Messages: 5 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                    Message History                          │
│                                                             │
│  You • 2:34 PM                                             │
│  Can you help me implement...                              │
│                                                             │
│  Assistant • 2:34 PM                                       │
│  I'll help you implement...                                │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ Type a message... (Enter to send, Ctrl+Enter for newline)  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Header Indicators
- **Connection Status**: ● (green) = authenticated, ◐ (yellow) = connected, ○ (red) = disconnected
- **Model Info**: Current model and provider
- **Token Usage**: Color-coded (green < 70%, yellow 70-90%, red > 90%)
- **Message Count**: Total messages in conversation

## Architecture

The TUI follows the Elm Architecture pattern using Bubble Tea:

- **Model**: Application state (`internal/ui/model.go`)
- **Update**: State transitions (`internal/ui/update.go`)
- **View**: Rendering logic (`internal/ui/view.go`)

### Key Components

- **Chat Component** (`internal/ui/chat.go`): Main conversation interface
- **Chat Header** (`internal/ui/chat_header.go`): Status and metadata display
- **Phoenix Client** (`internal/phoenix/client.go`): WebSocket communication
- **Auth Client** (`internal/phoenix/auth_client.go`): Authentication operations
- **Token Counter** (`internal/ui/token_counter.go`): Token usage estimation
- **Command Palette** (`internal/ui/command_palette.go`): Command execution
- **File Tree** (`internal/ui/file_tree.go`): File navigation (optional)

## Development

### Running Tests

```bash
go test ./...
```

### Project Structure

```
tui/
├── cmd/
│   └── tui/           # Main entry point
├── internal/
│   ├── ui/            # UI components and state
│   └── phoenix/       # Phoenix WebSocket client
└── go.mod             # Go module definition
```

## Integration with RubberDuck

The TUI uses a dual-socket architecture to connect to the RubberDuck Phoenix server:

### Connection Flow:
1. **Auth Socket Connection**: Connects to `/auth_socket` (no credentials required)
2. **Auth Channel Join**: Automatically joins `auth:lobby` channel
3. **Authentication**: 
   - If API key provided: Automatic authentication
   - Otherwise: Manual login required via `/login` command
   - Receives JWT token upon successful authentication
4. **Socket Switch**: Disconnects from auth socket, connects to `/socket` with JWT/API key
5. **Authenticated Channels**: Join conversation and status channels on authenticated socket

### Auth Channel (`auth:lobby`):
- User authentication (login/logout)
- API key generation and management
- Token refresh
- Authentication status checks

### Conversation Channel (`conversation:lobby`):
- Sending messages to the AI assistant
- Receiving responses (with streaming support planned)
- Starting new conversations
- Context updates
- Error handling with retry capabilities
- Per-conversation model preferences

## Future Enhancements

- Syntax highlighting for code blocks (using Chroma)
- Theming support
- Performance optimizations for large conversations
- File editing integration
- Multiple conversation support