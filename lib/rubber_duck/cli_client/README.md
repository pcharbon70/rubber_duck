# RubberDuck WebSocket CLI Client

A standalone CLI client that communicates with the RubberDuck server via WebSocket channels, eliminating the need for compilation and preserving server state between commands.

## Features

- **No Compilation Required**: Runs as a standalone binary without needing the full project
- **Persistent Connection**: Maintains WebSocket connection for faster command execution
- **Real-time Streaming**: Supports streaming responses for long-running operations
- **API Key Authentication**: Secure authentication using API keys
- **Full Command Support**: All CLI commands available through WebSocket interface

## Installation

### Building the CLI

```bash
# From the project root
mix deps.get
mix escript.build

# The binary will be created at bin/rubber_duck
```

### Setting up Authentication

1. Generate an API key on the server:
```bash
mix rubber_duck.auth generate
```

2. Configure the CLI client:
```bash
./bin/rubber_duck auth setup
# Enter server URL and API key when prompted
```

## Usage

### Authentication Commands

```bash
# Set up authentication
rubber_duck auth setup

# Check authentication status
rubber_duck auth status

# Clear stored credentials
rubber_duck auth clear
```

### Code Analysis

```bash
# Analyze a file or directory
rubber_duck analyze lib/my_module.ex
rubber_duck analyze lib/ --recursive

# Specific analysis types
rubber_duck analyze lib/my_module.ex --type security
```

### Code Generation

```bash
# Generate code from natural language
rubber_duck generate "Create a GenServer that manages user sessions"

# Generate with specific language
rubber_duck generate "REST API endpoint" --language python

# Save to file
rubber_duck generate "Fibonacci function" --output lib/fib.ex
```

### Code Completion

```bash
# Get completions at a specific position
rubber_duck complete lib/my_module.ex --line 42 --column 10
```

### Code Refactoring

```bash
# Refactor with instructions
rubber_duck refactor lib/my_module.ex "Extract this into a separate function"

# Preview changes without applying
rubber_duck refactor lib/my_module.ex "Rename variable foo to bar" --dry-run
```

### Test Generation

```bash
# Generate tests for a module
rubber_duck test lib/my_module.ex

# Specify test framework
rubber_duck test lib/my_module.ex --framework exunit

# Save to specific file
rubber_duck test lib/my_module.ex --output test/my_module_test.exs
```

### LLM Provider Management

```bash
# Check provider status
rubber_duck llm status

# Connect to a provider
rubber_duck llm connect ollama

# Disconnect from a provider
rubber_duck llm disconnect ollama

# Enable/disable providers
rubber_duck llm enable ollama
rubber_duck llm disable mock
```

## Configuration

The CLI stores configuration in `~/.rubber_duck/config.json`:

```json
{
  "api_key": "your-api-key-here",
  "server_url": "ws://localhost:5555/socket/websocket",
  "created_at": "2024-01-15T10:30:00Z"
}
```

### Environment Variables

- `RUBBER_DUCK_API_KEY`: API key for authentication
- `RUBBER_DUCK_URL`: Server WebSocket URL

## Architecture

The CLI client uses Phoenix Channels for real-time communication:

1. **WebSocket Connection**: Establishes persistent connection to server
2. **Channel Communication**: Sends commands and receives responses via `cli:commands` channel
3. **Streaming Support**: Handles long-running operations with streaming responses
4. **Automatic Reconnection**: Reconnects on connection loss

## Development

### Running Tests

```bash
mix test test/rubber_duck_web/channels/cli_channel_test.exs
```

### Building for Distribution

```bash
# Create release build
MIX_ENV=prod mix escript.build

# The binary can be distributed standalone
cp bin/rubber_duck /usr/local/bin/
```

## Troubleshooting

### Connection Issues

1. Verify server is running: `mix phx.server`
2. Check server URL in config: `rubber_duck auth status`
3. Ensure API key is valid: `mix rubber_duck.auth list`

### Authentication Errors

1. Regenerate API key: `mix rubber_duck.auth generate`
2. Update CLI config: `rubber_duck auth setup`
3. Check WebSocket endpoint configuration

### Performance

- The CLI maintains a persistent connection for better performance
- First command may take longer due to connection setup
- Subsequent commands execute faster using existing connection