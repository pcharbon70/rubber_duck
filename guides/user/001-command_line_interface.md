# RubberDuck Command Line Interface Guide

This comprehensive guide covers how to use RubberDuck's WebSocket-based CLI client for AI-powered coding assistance. The CLI client connects to a running RubberDuck server, providing real-time, stateful interactions with advanced LLM provider management and dynamic model configuration.

## Table of Contents

1. [Overview & Architecture](#overview--architecture)
2. [Installation & Setup](#installation--setup)
3. [Authentication](#authentication)
4. [LLM Provider Management](#llm-provider-management)
5. [Dynamic Model Configuration](#dynamic-model-configuration)
6. [Core Commands](#core-commands)
7. [Conversation and REPL Mode](#conversation-and-repl-mode)
8. [Advanced Features](#advanced-features)
9. [Output Formats](#output-formats)
10. [Common Workflows](#common-workflows)
11. [Troubleshooting](#troubleshooting)
12. [Performance Tips](#performance-tips)

## Overview & Architecture

The RubberDuck CLI is a standalone client that communicates with the RubberDuck server via WebSocket channels. This architecture provides several key benefits:

- **No Compilation Required**: The CLI runs as a pre-built binary
- **Persistent Connection**: Maintains state between commands
- **Real-time Streaming**: Live updates for long-running operations
- **Remote Access**: Connect to RubberDuck servers anywhere
- **Multiple Clients**: Support for concurrent CLI sessions
- **Dynamic LLM Configuration**: Runtime provider and model switching *(partially implemented)*

### How It Works

```
┌─────────────┐         WebSocket          ┌──────────────┐
│  CLI Client ├──────────────────────────►│ RubberDuck   │
│  (Binary)   │◄──────────────────────────┤ Server       │
└─────────────┘     Phoenix Channels       └──────────────┘
```

## Installation & Setup

### Prerequisites

**For the Server:**
- Elixir 1.15+ and Erlang/OTP 25+
- PostgreSQL 16+ (for vector storage)
- Running RubberDuck server

**For the CLI Client:**
- No dependencies! The CLI is a standalone binary

### Server Setup

First, ensure your RubberDuck server is running:

```bash
# Clone and setup the server
git clone https://github.com/yourusername/rubber_duck.git
cd rubber_duck

# Install dependencies
mix deps.get

# Setup database
mix ash.setup

# Start the server
mix phx.server
```

The server will start on `http://localhost:5555` by default.

### Building the CLI Client

```bash
# From the project root
mix deps.get
mix escript.build

# The binary is created at bin/rubber_duck
ls -la bin/rubber_duck
```

### Installing the CLI

You can install the CLI binary system-wide:

```bash
# Option 1: Copy to /usr/local/bin
sudo cp bin/rubber_duck /usr/local/bin/

# Option 2: Add bin/ to your PATH
export PATH="$PATH:/path/to/rubber_duck/bin"

# Option 3: Create an alias
alias rubber_duck="/path/to/rubber_duck/bin/rubber_duck"
```

### First Run

```bash
# Verify installation
rubber_duck --version

# Check available commands
rubber_duck --help
```

## Authentication

The CLI uses API key authentication to securely connect to the RubberDuck server.

### Initial Authentication Setup

```bash
# Start the authentication setup wizard
rubber_duck auth setup

# You'll be prompted for:
# 1. Server URL (default: ws://localhost:5555/socket/websocket)
# 2. API key (leave blank to generate one)
```

### Generating API Keys

On the server side, generate API keys using:

```bash
# Generate a new API key
mix rubber_duck.auth generate

# Example output:
# Generated API key: a1b2c3d4e5f6789012345678901234567890123456789012
# Description: CLI access
```

### Managing Authentication

```bash
# Check current authentication status
rubber_duck auth status

# Output:
# Authentication Status:
# 
# Configured: Yes
# Server: ws://localhost:5555/socket/websocket
# API Key: a1b2c3d4...9012 (masked)
# Config Location: ~/.rubber_duck/config.json

# Clear stored credentials
rubber_duck auth clear
```

### Configuration File

The CLI stores configuration in `~/.rubber_duck/config.json`:

```json
{
  "api_key": "a1b2c3d4e5f6789012345678901234567890123456789012",
  "server_url": "ws://localhost:5555/socket/websocket",
  "created_at": "2024-01-15T10:30:00Z",
  "llm": {
    "default_provider": "ollama",
    "providers": {
      "ollama": {
        "model": "codellama"
      },
      "openai": {
        "model": "gpt-4"
      }
    }
  }
}
```

### Environment Variables

You can also use environment variables:

```bash
export RUBBER_DUCK_API_KEY="your-api-key-here"
export RUBBER_DUCK_URL="ws://production.server.com/socket/websocket"
```

## LLM Provider Management

RubberDuck supports multiple LLM providers that can be managed dynamically through the CLI.

### Available Providers

1. **Mock** - Testing provider, no external service required
2. **Ollama** - Run LLMs locally
3. **OpenAI** - GPT models via OpenAI API
4. **Anthropic** - Claude models via Anthropic API
5. **TGI (HuggingFace Text Generation Inference)** - High-performance inference server

### Provider Status and Health

```bash
# View all provider status
rubber_duck llm status

# Output:
# LLM Provider Status:
# 
# ✓ ollama
#   Status: connected
#   Health: ● healthy
#   Model: codellama
#   Last used: 2024-01-15T14:30:00Z
#   Errors: 0
# 
# ✓ openai
#   Status: connected
#   Health: ● healthy
#   Model: gpt-4
#   Last used: never
#   Errors: 0
# 
# ✗ anthropic
#   Status: disconnected
#   Health: ? unknown
#   Model: claude-3-sonnet
#   Last used: never
#   Errors: 0

# View status in table format
rubber_duck llm status --format table

# JSON output for scripting
rubber_duck llm status --format json
```

### Setting Up Ollama

```bash
# 1. Install Ollama (on the server machine)
curl -fsSL https://ollama.ai/install.sh | sh

# 2. Start Ollama service
ollama serve

# 3. Pull models
ollama pull llama2
ollama pull codellama
ollama pull mistral

# 4. Connect via RubberDuck CLI
rubber_duck llm connect ollama

# Output:
# Successfully connected to ollama
```

### Setting Up HuggingFace Text Generation Inference (TGI)

```bash
# 1. Run TGI using Docker (on the server machine)
docker run --gpus all --shm-size 1g -p 8080:80 \
  -v $PWD/data:/data \
  ghcr.io/huggingface/text-generation-inference:latest \
  --model-id codellama/CodeLlama-13b-Instruct-hf \
  --max-total-tokens 8192

# 2. Verify TGI is running
curl http://localhost:8080/health

# 3. Connect via RubberDuck CLI
rubber_duck llm connect tgi

# 4. Check connection status
rubber_duck llm status
```

TGI supports any HuggingFace model and provides:
- OpenAI-compatible API endpoints
- Flash Attention optimizations
- Streaming responses
- Function calling support
- Guided generation capabilities

### Managing Provider Connections

```bash
# Connect to specific provider
rubber_duck llm connect ollama

# Connect to all configured providers
rubber_duck llm connect

# Disconnect from provider
rubber_duck llm disconnect ollama

# Disable provider (keeps config but won't use)
rubber_duck llm disable mock

# Enable provider
rubber_duck llm enable mock
```

## Dynamic Model Configuration

**Note: The following dynamic model configuration commands are NOT YET IMPLEMENTED:**
- `rubber_duck llm set-default <provider>`
- `rubber_duck llm set-model <provider> <model>`
- `rubber_duck llm list-models [provider]`

Currently, model configuration must be done through:
1. Server configuration files
2. Environment variables at runtime

### Current Model Configuration

Models are configured in the server's `config/config.exs`:

```elixir
config :rubber_duck, :llm,
  providers: [
    %{
      name: :ollama,
      adapter: RubberDuck.LLM.Providers.Ollama,
      base_url: "http://localhost:11434",
      models: ["codellama", "mistral", "phi"],
      default_model: "codellama"
    },
    %{
      name: :tgi,
      adapter: RubberDuck.LLM.Providers.TGI,
      base_url: "http://localhost:8080",
      models: ["codellama-13b", "llama-3.1-8b"],
      default_model: "codellama-13b"
    }
  ]
```

### Environment Variable Override

You can override the provider for specific commands:

```bash
# Use environment variables (if supported by server implementation)
RUBBER_DUCK_PROVIDER=ollama rubber_duck generate "create a web API"
RUBBER_DUCK_MODEL=mistral rubber_duck analyze lib/module.ex
```

## Core Commands

### 1. Code Analysis

Analyze code for issues, patterns, and improvements.

```bash
# Basic file analysis
rubber_duck analyze lib/my_module.ex

# Recursive directory analysis
rubber_duck analyze lib/ --recursive

# Include fix suggestions (NOT YET IMPLEMENTED)
# rubber_duck analyze lib/my_module.ex --include-suggestions
```

**Available Options:**
- `-t, --type <all|semantic|style|security>` - Analysis type (default: all)
- `-r, --recursive` - Analyze directories recursively

**Unimplemented Options:**
- `--include-suggestions` - Include fix suggestions

### 2. Code Generation

Generate code from natural language descriptions.

```bash
# Generate code
rubber_duck generate "create a GenServer for rate limiting"

# Generate with output file
rubber_duck generate "user authentication module" --output lib/auth.ex

# Specify language
rubber_duck generate "REST API client" --language elixir
```

**Available Options:**
- `-o, --output <file>` - Save to file
- `-l, --language <lang>` - Target language (default: elixir)

**Unimplemented Options:**
- `--context <file>` - Context files
- `-i, --interactive` - Interactive mode for iterative refinement

### 3. Code Completion

Get intelligent completions at specific positions.

```bash
# Get completions
rubber_duck complete lib/my_module.ex --line 25 --column 10

# More suggestions (NOT YET IMPLEMENTED - --max option not available)
# rubber_duck complete lib/my_module.ex --line 25 --column 10 --max 10
```

**Required Options:**
- `--line <n>` - Line number
- `--column <n>` - Column number

**Unimplemented Options:**
- `-n, --max-suggestions` - Maximum suggestions (always returns default of 5)

### 4. Code Refactoring

Refactor code based on instructions.

```bash
# Refactor with instruction
rubber_duck refactor lib/legacy.ex "modernize this code"

# Preview changes (NOT YET IMPLEMENTED)
# rubber_duck refactor lib/module.ex "use pattern matching" --dry-run

# Save to different file (NOT YET IMPLEMENTED)
# rubber_duck refactor lib/complex.ex "simplify" --output lib/simple.ex
```

**Unimplemented Options:**
- `--dry-run` - Preview changes without applying
- `-d, --diff` - Show diff instead of full output
- `--in-place` - Modify the file in place
- `-i, --interactive` - Step through changes
- `-o, --output <file>` - Save to different file

### 5. Test Generation

Generate comprehensive test suites.

```bash
# Generate tests
rubber_duck test lib/my_module.ex

# Specify framework
rubber_duck test lib/calculator.ex --framework exunit

# With output file
rubber_duck test lib/parser.ex --output test/parser_test.exs
```

**Available Options:**
- `-o, --output <file>` - Output file
- `-f, --framework <name>` - Test framework (default: exunit)

**Unimplemented Options:**
- `--include-edge-cases` - Add edge case tests
- `--include-property-tests` - Add property tests

### 6. Health Check

Monitor the health and status of your RubberDuck server.

```bash
# Basic health check
rubber_duck health

# Table format
rubber_duck health --format table

# JSON output for monitoring
rubber_duck health --format json
```

**Health Information Includes:**
- Server status and uptime
- Memory usage breakdown
- Active WebSocket connections
- LLM provider health and status

## Conversation and REPL Mode

RubberDuck provides two powerful interactive modes for conversing with the AI assistant.

### Conversation Commands

```bash
# Start a new conversation
rubber_duck conversation start "Project Planning"

# Start with specific type
rubber_duck conversation start --type coding

# List conversations
rubber_duck conversation list

# Show conversation history
rubber_duck conversation show <conversation-id>

# Send a message
rubber_duck conversation send "How do I implement authentication?" --conversation <id>

# Delete conversation
rubber_duck conversation delete <conversation-id>
```

### Interactive Chat Mode

```bash
# Enter chat mode
rubber_duck conversation chat

# Resume specific conversation
rubber_duck conversation chat <conversation-id>

# Start chat with title
rubber_duck conversation chat --title "Debug Session"
```

### NEW: Enhanced REPL Mode

The new REPL mode provides a superior interactive experience:

```bash
# Start REPL
rubber_duck repl

# Start with specific conversation type
rubber_duck repl -t coding

# Resume last conversation
rubber_duck repl -r last

# Resume specific conversation
rubber_duck repl -r <conversation-id>

# Skip welcome message
rubber_duck repl --no-welcome
```

**REPL Features:**
- Direct message input without command prefixes
- Multi-line input with `"""` or `\`
- Rich command set with `/` prefix
- Context file management
- Session auto-save
- Model switching (when implemented on server)

**REPL Commands:**
```
Basic:
  /help              - Show help
  /exit              - Exit REPL
  /clear             - Clear screen
  /info              - Session information

Conversation:
  /history           - Show history
  /save [filename]   - Save conversation
  /recent            - Show recent conversations
  /switch <id>       - Switch conversation

Context:
  /context           - Show context files
  /context add <file> - Add file to context
  /context clear     - Clear context

Model:
  /model             - Show current model
  /model <spec>      - Change model (when implemented)

Integrated:
  /analyze <file>    - Analyze in context
  /generate <prompt> - Generate code
  /refactor <instr>  - Refactor with context
```

## Advanced Features

### Real-time Streaming

The CLI supports streaming for long-running operations:

```bash
# Generation shows progress (when verbose output is enabled)
rubber_duck generate "complex implementation" --verbose
```

### Batch Operations

Process multiple files efficiently:

```bash
# Analyze all files
for file in lib/**/*.ex; do
  rubber_duck analyze "$file" --format json >> analysis.jsonl
done

# Generate tests for modules without tests
find lib -name "*.ex" | while read module; do
  test_file="test/${module#lib/}_test.exs"
  if [ ! -f "$test_file" ]; then
    rubber_duck test "$module" --output "$test_file"
  fi
done
```

## Output Formats

### Plain Text (Default)

Human-readable format optimized for terminal display:

```bash
rubber_duck analyze lib/module.ex
```

### JSON Format

Machine-readable for scripting and automation:

```bash
# Pipe to jq for processing
rubber_duck analyze lib/module.ex --format json | jq '.issues[]'

# Extract provider information
rubber_duck llm status --format json | jq '.providers[] | {name, model, health}'
```

### Table Format

Structured tables for status and list outputs:

```bash
rubber_duck llm status --format table
rubber_duck health --format table
```

## Common Workflows

### 1. Initial Project Setup

```bash
# 1. Set up authentication
rubber_duck auth setup

# 2. Connect to LLM providers
rubber_duck llm connect ollama
rubber_duck llm connect tgi  # If using HuggingFace TGI

# 3. Check health
rubber_duck health

# 4. Analyze project
rubber_duck analyze . --recursive

# 5. Start REPL for interactive work
rubber_duck repl
```

### 2. Test-Driven Development

```bash
# 1. Generate module
rubber_duck generate "user authentication service with JWT" --output lib/auth_service.ex

# 2. Generate tests
rubber_duck test lib/auth_service.ex --output test/auth_service_test.exs

# 3. Run tests and refine
mix test test/auth_service_test.exs || {
  rubber_duck refactor lib/auth_service.ex "fix failing tests"
}
```

### 3. Interactive Development with REPL

```bash
# Start coding session
rubber_duck repl -t coding

# In REPL:
rd> /context add lib/my_module.ex
rd> Please help me refactor this module to use GenServer
rd> /save refactoring_session.md
```

### 4. CI/CD Integration

```yaml
# .github/workflows/rubber_duck.yml
name: RubberDuck Analysis

on: [push, pull_request]

jobs:
  analyze:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup RubberDuck
      run: |
        # Download and setup CLI
        wget https://github.com/rubber_duck/releases/latest/rubber_duck
        chmod +x rubber_duck
        
    - name: Configure
      env:
        RUBBER_DUCK_API_KEY: ${{ secrets.RUBBER_DUCK_API_KEY }}
        RUBBER_DUCK_URL: ${{ secrets.RUBBER_DUCK_URL }}
      run: |
        ./rubber_duck auth status
        
    - name: Health Check
      run: |
        ./rubber_duck health --format json > health.json
        
    - name: Analysis
      run: |
        ./rubber_duck analyze lib/ --recursive --format json > analysis.json
        
    - name: Upload Results
      uses: actions/upload-artifact@v3
      with:
        name: analysis-results
        path: |
          analysis.json
          health.json
```

## Troubleshooting

### Connection Issues

#### "Failed to connect to server"

1. **Verify server is running:**
   ```bash
   curl http://localhost:5555/api/health
   ```

2. **Check authentication:**
   ```bash
   rubber_duck auth status
   ```

3. **Test WebSocket connection:**
   ```bash
   wscat -c ws://localhost:5555/socket/websocket
   ```

### LLM Provider Issues

#### "Provider not available"

1. **Check provider status:**
   ```bash
   rubber_duck llm status
   ```

2. **Reconnect to providers:**
   ```bash
   rubber_duck llm connect
   ```

3. **For Ollama issues:**
   ```bash
   # Check if Ollama is running
   ollama list
   ```

4. **For TGI issues:**
   ```bash
   # Check TGI health
   curl http://localhost:8080/health
   ```

### Performance Issues

#### Slow Command Execution

1. **Check provider health:**
   ```bash
   rubber_duck llm status --format json | jq '.providers[] | {name, health}'
   ```

2. **Monitor server health:**
   ```bash
   rubber_duck health --format json | jq '{memory_mb: .memory.total_mb}'
   ```

### Debug Mode

Enable detailed logging:

```bash
# Verbose output
rubber_duck analyze lib/module.ex --verbose --debug

# Debug includes:
# - WebSocket frame details
# - Response timing
# - Error traces
```

## Performance Tips

### 1. Connection Reuse

```bash
# First command establishes connection (slower)
rubber_duck llm status  # ~500ms

# Subsequent commands reuse connection (faster)
rubber_duck analyze file1.ex  # ~50ms
rubber_duck analyze file2.ex  # ~50ms
```

### 2. Use REPL for Interactive Work

The REPL mode maintains persistent connections and context:

```bash
# Instead of multiple commands:
rubber_duck conversation send "question 1" -c <id>
rubber_duck conversation send "question 2" -c <id>

# Use REPL:
rubber_duck repl
rd> question 1
rd> question 2
```

### 3. Batch Processing

For multiple files, consider using JSON output and processing in parallel:

```bash
# Process files in parallel
find lib -name "*.ex" -print0 | \
  xargs -0 -P 4 -I {} rubber_duck analyze {} --format json >> results.jsonl
```

## Unimplemented Features Summary

The following features are documented but NOT YET IMPLEMENTED:

### LLM Commands:
- `llm set-default <provider>` - Set default provider
- `llm set-model <provider> <model>` - Set model for provider
- `llm list-models [provider]` - List available models

### Command Options:
- `analyze --include-suggestions` - Include fix suggestions
- `generate --context <file>` - Add context files
- `generate --interactive` - Interactive refinement
- `complete --max <n>` - Set maximum suggestions
- `refactor --dry-run` - Preview changes
- `refactor --diff` - Show diff
- `refactor --in-place` - Modify in place
- `refactor --interactive` - Step through changes
- `refactor --output <file>` - Save to different file
- `test --include-edge-cases` - Add edge case tests
- `test --include-property-tests` - Add property tests

### Other:
- Model switching in REPL (`/model <spec>` works but backend support varies)
- Per-command model selection via environment variables
- Caching for analysis results (`--no-cache` flag)

Most core functionality is working, but these advanced features would enhance the user experience when implemented.

## Next Steps

- Use `rubber_duck repl` for an enhanced interactive experience
- Explore the [Developer Guides](../developer/) for extending functionality
- Check server logs if you encounter issues with unimplemented features

---

*Experience the power of AI-assisted development with RubberDuck! 🦆*