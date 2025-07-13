# RubberDuck Command Line Interface Guide

This comprehensive guide covers how to use RubberDuck's WebSocket-based CLI client for AI-powered coding assistance. The CLI client connects to a running RubberDuck server, providing real-time, stateful interactions with advanced LLM provider management and dynamic model configuration.

## Table of Contents

1. [Overview & Architecture](#overview--architecture)
2. [Installation & Setup](#installation--setup)
3. [Authentication](#authentication)
4. [LLM Provider Management](#llm-provider-management)
5. [Dynamic Model Configuration](#dynamic-model-configuration)
6. [Core Commands](#core-commands)
7. [Advanced Features](#advanced-features)
8. [Output Formats](#output-formats)
9. [Common Workflows](#common-workflows)
10. [Troubleshooting](#troubleshooting)
11. [Performance Tips](#performance-tips)

## Overview & Architecture

The RubberDuck CLI is a standalone client that communicates with the RubberDuck server via WebSocket channels. This architecture provides several key benefits:

- **No Compilation Required**: The CLI runs as a pre-built binary
- **Persistent Connection**: Maintains state between commands
- **Real-time Streaming**: Live updates for long-running operations
- **Remote Access**: Connect to RubberDuck servers anywhere
- **Multiple Clients**: Support for concurrent CLI sessions
- **Dynamic LLM Configuration**: Runtime provider and model switching

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
5. **TGI (Text Generation Inference)** - High-performance inference server

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

One of RubberDuck's most powerful features is the ability to dynamically configure LLM providers and models at runtime, both globally and per-command.

### Setting Default Provider and Model

```bash
# Set the default provider for all commands
rubber_duck llm set-default ollama

# Set the model for a specific provider
rubber_duck llm set-model ollama codellama
rubber_duck llm set-model openai gpt-4

# Set multiple providers at once
rubber_duck llm set-model anthropic claude-3-sonnet
rubber_duck llm set-model ollama mistral
```

### Listing Available Models

```bash
# List all available models across all providers
rubber_duck llm list-models

# Output:
# Available Models:
# 
# ollama:
#   - llama2 (7B parameters)
#   - codellama (7B parameters, code-optimized)
#   - mistral (7B parameters)
#   - phi (3B parameters, fast)
# 
# openai:
#   - gpt-3.5-turbo (chat optimized)
#   - gpt-4 (advanced reasoning)
#   - gpt-4-turbo (latest, faster)
# 
# anthropic:
#   - claude-3-haiku (fast, lightweight)
#   - claude-3-sonnet (balanced)
#   - claude-3-opus (most capable)

# List models for specific provider
rubber_duck llm list-models ollama
```

### Configuration Priority

RubberDuck uses a configuration hierarchy (highest to lowest priority):

1. **Command-line environment variables**: `RUBBER_DUCK_PROVIDER=ollama`
2. **CLI config file**: `~/.rubber_duck/config.json`
3. **Server application config**: Default fallbacks

```bash
# Override provider for a single command
RUBBER_DUCK_PROVIDER=openai rubber_duck generate "create a web API"

# Override both provider and model
RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=mistral rubber_duck analyze lib/module.ex
```

### Global vs Per-Command Configuration

```bash
# Set global defaults (affects all future commands)
rubber_duck llm set-default ollama
rubber_duck llm set-model ollama codellama

# Use different provider for specific command
RUBBER_DUCK_PROVIDER=openai rubber_duck generate "complex algorithm"

# Check current configuration
rubber_duck llm status

# View effective configuration for debugging
rubber_duck llm status --show-config
```

## Core Commands

### 1. Code Analysis

Analyze code for issues, patterns, and improvements with configurable LLM providers.

```bash
# Basic file analysis (uses default provider/model)
rubber_duck analyze lib/my_module.ex

# Use specific provider for analysis
RUBBER_DUCK_PROVIDER=openai rubber_duck analyze lib/my_module.ex --type security

# Recursive directory analysis with fast model
RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=phi rubber_duck analyze lib/ --recursive

# Include fix suggestions using powerful model
RUBBER_DUCK_PROVIDER=anthropic rubber_duck analyze lib/my_module.ex --include-suggestions
```

**Options:**
- `-t, --type <all|semantic|style|security>` - Analysis type (default: all)
- `-r, --recursive` - Analyze directories recursively
- `--include-suggestions` - Include fix suggestions

**Example Output:**
```
Analyzing: lib/my_module.ex (using ollama:codellama)

Issues Found:

WARNING (2):
  lib/my_module.ex:15:5
  Unused variable 'result'
  
  lib/my_module.ex:42:1
  Function complexity too high (cyclomatic: 12)

Suggestions:
  - Remove unused variable or prefix with underscore
  - Break complex function into smaller functions

Summary: 2 issues found
Provider: ollama (codellama) - Response time: 1.2s
```

### 2. Code Generation

Generate code from natural language descriptions with real-time streaming.

```bash
# Generate code with live output (uses default provider)
rubber_duck generate "create a GenServer for rate limiting"

# Use specific model for code generation
RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=codellama rubber_duck generate "user authentication module" --output lib/auth.ex

# Use powerful model for complex generation
RUBBER_DUCK_PROVIDER=anthropic RUBBER_DUCK_MODEL=claude-3-opus rubber_duck generate "distributed system design" --language elixir

# Use context files with specific provider
RUBBER_DUCK_PROVIDER=openai rubber_duck generate "add caching to this module" --context lib/existing_module.ex
```

**Options:**
- `-o, --output <file>` - Save to file
- `-l, --language <lang>` - Target language (default: elixir)
- `--context <file>` - Context files

**Real-time Output:**
```bash
$ rubber_duck generate "create a rate limiter using GenServer"
Generating code using ollama:codellama... 
defmodule RateLimiter do
  use GenServer
  
  # ... code streams in real-time ...
end

Generation complete!
Provider: ollama (codellama) - Tokens: 234 - Time: 3.4s
```

### 3. Code Completion

Get intelligent completions at specific positions using optimized models.

```bash
# Get completions with fast model
RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=phi rubber_duck complete lib/my_module.ex --line 25 --column 10

# More suggestions with powerful model
RUBBER_DUCK_PROVIDER=openai rubber_duck complete lib/my_module.ex -l 25 -c 10 --max 10
```

**Options:**
- `--line <n>` - Line number (required)
- `--column <n>` - Column number (required)
- `--max <n>` - Maximum suggestions (default: 5)

### 4. Code Refactoring

Refactor code based on instructions using appropriate models.

```bash
# Refactor with preview using default provider
rubber_duck refactor lib/legacy.ex "modernize this code"

# Show diff only with specific model
RUBBER_DUCK_PROVIDER=anthropic rubber_duck refactor lib/module.ex "use pattern matching" --dry-run

# Interactive refactoring with code-optimized model
RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=codellama rubber_duck refactor lib/complex.ex "simplify" --interactive
```

**Options:**
- `--dry-run` - Preview changes without applying
- `--interactive` - Step through changes
- `-o, --output <file>` - Save to different file

### 5. Test Generation

Generate comprehensive test suites with models optimized for testing.

```bash
# Generate tests using default provider
rubber_duck test lib/my_module.ex

# Use code-specialized model for comprehensive testing
RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=codellama rubber_duck test lib/calculator.ex --output test/calculator_test.exs --include-edge-cases

# Generate property-based tests with powerful reasoning model
RUBBER_DUCK_PROVIDER=anthropic rubber_duck test lib/parser.ex --include-property-tests
```

**Options:**
- `-o, --output <file>` - Output file
- `-f, --framework <name>` - Test framework (default: exunit)
- `--include-edge-cases` - Add edge case tests
- `--include-property-tests` - Add property tests

## Advanced Features

### Model Selection Strategies

Choose models based on task requirements and performance needs:

```bash
# Fast completion for simple tasks
RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=phi rubber_duck complete file.ex --line 10 --column 5

# Balanced performance for most tasks
RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=codellama rubber_duck analyze lib/

# Maximum capability for complex reasoning
RUBBER_DUCK_PROVIDER=anthropic RUBBER_DUCK_MODEL=claude-3-opus rubber_duck generate "distributed system architecture"

# Cost-effective for simple generation
RUBBER_DUCK_PROVIDER=openai RUBBER_DUCK_MODEL=gpt-3.5-turbo rubber_duck generate "helper function"
```

### Provider Failover and Fallbacks

Configure automatic failover between providers:

```bash
# Set multiple providers with fallback priority
rubber_duck llm set-default ollama
rubber_duck llm enable openai  # Will be used if ollama fails
rubber_duck llm enable anthropic  # Third fallback

# Test provider health before important operations
rubber_duck llm status && rubber_duck generate "critical code component"
```

### Real-time Streaming

The CLI supports streaming for long-running operations:

```bash
# Watch generation progress with streaming
rubber_duck generate "complex implementation" --verbose

# Streaming output shows:
# Generating code using anthropic:claude-3-sonnet... [█████████████░░░░░░░] 65%
# Creating module structure...
# Adding function definitions...
# Implementing business logic...
# Adding documentation...
# Generation complete!
```

### Batch Operations with Different Models

Process multiple files efficiently with optimal model selection:

```bash
# Analyze all files with fast model for overview
for file in lib/**/*.ex; do
  RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=phi rubber_duck analyze "$file" --format json >> quick_analysis.jsonl
done

# Deep analysis of critical files with powerful model
for file in lib/core/*.ex; do
  RUBBER_DUCK_PROVIDER=anthropic RUBBER_DUCK_MODEL=claude-3-opus rubber_duck analyze "$file" --include-suggestions >> deep_analysis.md
done

# Generate tests with code-specialized model
find lib -name "*.ex" | while read module; do
  test_file="test/${module#lib/}_test.exs"
  if [ ! -f "$test_file" ]; then
    RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=codellama rubber_duck test "$module" --output "$test_file"
  fi
done
```

### Server Health Monitoring

Monitor the health and status of your RubberDuck server and LLM providers:

```bash
# Comprehensive health check including LLM providers
rubber_duck health

# Health check with table format for better readability
rubber_duck health --format table

# JSON output for scripting and monitoring
rubber_duck health --format json

# Monitor specific provider health
rubber_duck health --format json | jq '.providers.ollama.health'

# Get memory usage during operations
rubber_duck health --format json | jq '.memory.total_mb'
```

**Health Information Includes:**
- Server status and uptime
- Memory usage breakdown
- Active WebSocket connections
- LLM provider health and model status
- Provider response times and error rates

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

# Save for later processing
rubber_duck llm status --format json > provider_status.json

# Extract provider information
rubber_duck llm status --format json | jq '.providers[] | {name, model, health}'

# Monitor health metrics
rubber_duck health --format json | jq '{uptime: .uptime.total_seconds, memory_mb: .memory.total_mb, providers: [.providers[] | {name, health, model}]}'
```

### Table Format

Structured tables for status and list outputs:

```bash
rubber_duck llm status --format table
```

Output:
```
┌─────────┬────────────┬─────────┬─────────┬──────────────┬────────┬─────────────┐
│ Provider│ Status     │ Enabled │ Health  │ Model        │ Errors │ Last Used   │
├─────────┼────────────┼─────────┼─────────┼──────────────┼────────┼─────────────┤
│ ollama  │ connected  │ true    │ healthy │ codellama    │ 0      │ 2 mins ago  │
│ openai  │ connected  │ true    │ healthy │ gpt-4        │ 0      │ never       │
│ anthropic│ disconnected│ false  │ unknown │ claude-3-opus│ 0      │ 1 hour ago  │
└─────────┴────────────┴─────────┴─────────┴──────────────┴────────┴─────────────┘
```

## Common Workflows

### 1. Initial Project Setup with Optimal Models

```bash
# Set up optimal provider configuration
rubber_duck llm set-default ollama
rubber_duck llm set-model ollama codellama  # Best for code
rubber_duck llm enable openai
rubber_duck llm set-model openai gpt-4      # Backup for complex tasks

# Complete project health check with fast model
RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=phi rubber_duck analyze . --recursive --format json > project_health.json

# Extract critical issues for detailed analysis
jq '.issues[] | select(.severity == "error")' project_health.json | \
  while read -r issue; do
    file=$(echo "$issue" | jq -r '.file')
    # Use powerful model for complex issue analysis
    RUBBER_DUCK_PROVIDER=anthropic RUBBER_DUCK_MODEL=claude-3-opus rubber_duck analyze "$file" --include-suggestions
  done
```

### 2. Multi-Model Test-Driven Development

```bash
# 1. Generate module with code-specialized model
RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=codellama rubber_duck generate "user authentication service with JWT" --output lib/auth_service.ex

# 2. Generate comprehensive tests with testing-focused approach
RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=codellama rubber_duck test lib/auth_service.ex --output test/auth_service_test.exs --include-edge-cases

# 3. Run tests and analyze failures with reasoning model
mix test test/auth_service_test.exs || {
  RUBBER_DUCK_PROVIDER=anthropic RUBBER_DUCK_MODEL=claude-3-sonnet rubber_duck analyze test/auth_service_test.exs --include-suggestions
}

# 4. Refactor based on test results using balanced model
RUBBER_DUCK_PROVIDER=anthropic RUBBER_DUCK_MODEL=claude-3-sonnet rubber_duck refactor lib/auth_service.ex "improve error handling and add logging based on test failures"
```

### 3. Performance-Optimized Legacy Code Modernization

```bash
# 1. Quick analysis with fast model for overview
RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=phi rubber_duck analyze lib/legacy/ --recursive > legacy_overview.txt

# 2. Deep analysis of complex modules with powerful model
for file in lib/legacy/complex_*.ex; do
  echo "Deep analysis of $file..."
  RUBBER_DUCK_PROVIDER=anthropic RUBBER_DUCK_MODEL=claude-3-opus rubber_duck analyze "$file" --include-suggestions >> deep_legacy_analysis.md
done

# 3. Generate modernized versions with code-specialized model
for file in lib/legacy/*.ex; do
  modern_file="lib/modern/$(basename $file)"
  echo "Modernizing $file -> $modern_file"
  RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=codellama rubber_duck refactor "$file" "modernize to use current Elixir patterns and idioms" --output "$modern_file"
done

# 4. Generate tests for modernized versions
for file in lib/modern/*.ex; do
  test_file="test/modern/$(basename $file _ex)_test.exs"
  RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=codellama rubber_duck test "$file" --include-property-tests --output "$test_file"
done
```

### 4. Intelligent Health Monitoring and Model Selection

```bash
# Create adaptive model selection based on server health
create_adaptive_command() {
  local command="$1"
  shift
  
  # Check server health
  local memory=$(rubber_duck health --format json | jq '.memory.total_mb')
  local provider_status=$(rubber_duck llm status --format json)
  
  # Select optimal provider based on conditions
  if (( $(echo "$memory > 1000" | bc -l) )); then
    echo "High memory usage, using lightweight model"
    RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=phi rubber_duck "$command" "$@"
  elif echo "$provider_status" | jq -e '.providers.anthropic.health == "healthy"' > /dev/null; then
    echo "Using high-capability model"
    RUBBER_DUCK_PROVIDER=anthropic RUBBER_DUCK_MODEL=claude-3-opus rubber_duck "$command" "$@"
  else
    echo "Using default reliable model"
    RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=codellama rubber_duck "$command" "$@"
  fi
}

# Use adaptive selection
create_adaptive_command generate "complex distributed system"
create_adaptive_command analyze lib/critical_module.ex --include-suggestions
```

### 5. CI/CD Integration with Provider Management

```yaml
# .github/workflows/rubber_duck.yml
name: RubberDuck Analysis with Dynamic LLM

on: [push, pull_request]

jobs:
  analyze:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Download RubberDuck CLI
      run: |
        wget https://github.com/rubber_duck/releases/latest/rubber_duck
        chmod +x rubber_duck
        
    - name: Configure Authentication and Providers
      env:
        RUBBER_DUCK_API_KEY: ${{ secrets.RUBBER_DUCK_API_KEY }}
        RUBBER_DUCK_URL: ${{ secrets.RUBBER_DUCK_URL }}
      run: |
        ./rubber_duck auth status
        # Set up optimal providers for CI
        ./rubber_duck llm set-default ollama
        ./rubber_duck llm set-model ollama phi  # Fast model for CI
        ./rubber_duck llm enable openai         # Fallback
        
    - name: Health Check with Provider Status
      run: |
        ./rubber_duck health --format json > health.json
        ./rubber_duck llm status --format json > providers.json
        
        # Ensure server and at least one provider is healthy
        jq -e '.status == "healthy"' health.json || exit 1
        jq -e '[.providers[] | select(.health == "healthy")] | length > 0' providers.json || exit 1
        
    - name: Fast Analysis with Lightweight Model
      run: |
        # Use fast model for CI to reduce execution time
        RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=phi ./rubber_duck analyze lib/ --recursive --format json > analysis.json
        
    - name: Critical Issues Deep Analysis
      run: |
        # Use more powerful model for critical issues only
        critical_files=$(jq -r '.issues[] | select(.severity == "error") | .file' analysis.json | sort -u)
        for file in $critical_files; do
          echo "Deep analysis of critical file: $file"
          RUBBER_DUCK_PROVIDER=openai RUBBER_DUCK_MODEL=gpt-4 ./rubber_duck analyze "$file" --include-suggestions >> critical_analysis.md
        done
        
    - name: Model Performance Metrics
      run: |
        # Log provider performance for optimization
        ./rubber_duck llm status --format json | jq '.providers[] | {name, model, last_response_time_ms, error_count}' > provider_metrics.json
        
    - name: Upload Results
      uses: actions/upload-artifact@v3
      with:
        name: analysis-results
        path: |
          analysis.json
          critical_analysis.md
          health.json
          providers.json
          provider_metrics.json
```

## Troubleshooting

### Connection Issues

#### "Failed to connect to server"

1. **Verify server is running:**
   ```bash
   # Check if server is up
   curl http://localhost:5555/api/health
   ```

2. **Check WebSocket endpoint:**
   ```bash
   # Test WebSocket connection
   wscat -c ws://localhost:5555/socket/websocket
   ```

3. **Verify authentication:**
   ```bash
   rubber_duck auth status
   ```

### LLM Provider Issues

#### "Provider not available" or "Model not found"

1. **Check provider status:**
   ```bash
   rubber_duck llm status --format json
   ```

2. **List available models:**
   ```bash
   rubber_duck llm list-models
   ```

3. **Reconnect to providers:**
   ```bash
   rubber_duck llm connect
   ```

4. **Reset to working configuration:**
   ```bash
   # Fall back to mock provider for testing
   rubber_duck llm set-default mock
   rubber_duck llm connect mock
   ```

### Performance Issues

#### Slow Command Execution

1. **Check provider health and response times:**
   ```bash
   rubber_duck llm status --format json | jq '.providers[] | {name, health, last_response_time_ms}'
   ```

2. **Use faster models for development:**
   ```bash
   # Switch to lightweight model
   rubber_duck llm set-model ollama phi
   ```

3. **Monitor server health:**
   ```bash
   rubber_duck health --format json | jq '{memory_mb: .memory.total_mb, active_connections: .connections.active}'
   ```

#### "Model response timeout"

1. **Check model availability:**
   ```bash
   # For Ollama
   ollama list
   
   # Test model directly
   ollama run codellama "test prompt"
   ```

2. **Switch to reliable provider:**
   ```bash
   rubber_duck llm set-default mock  # Always available
   ```

### Debug Mode

Enable detailed logging including provider selection:

```bash
# Verbose output with provider details
rubber_duck analyze lib/module.ex --verbose --debug

# Debug output includes:
# - Provider selection logic
# - Model configuration
# - WebSocket frame details
# - Response timing
# - Fallback attempts
```

## Performance Tips

### 1. Optimal Model Selection

Choose models based on task requirements:

```bash
# Lightning-fast completion (< 100ms)
RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=phi rubber_duck complete file.ex --line 10 --column 5

# Balanced performance for most tasks (< 2s)
RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=codellama rubber_duck analyze lib/

# Maximum quality for complex tasks (5-30s)
RUBBER_DUCK_PROVIDER=anthropic RUBBER_DUCK_MODEL=claude-3-opus rubber_duck generate "distributed system architecture"

# Cost-effective API usage
RUBBER_DUCK_PROVIDER=openai RUBBER_DUCK_MODEL=gpt-3.5-turbo rubber_duck test lib/simple_module.ex
```

### 2. Provider Configuration Strategies

```bash
# Development setup (speed prioritized)
rubber_duck llm set-default ollama
rubber_duck llm set-model ollama phi

# Production analysis (quality prioritized)  
rubber_duck llm set-default anthropic
rubber_duck llm set-model anthropic claude-3-sonnet

# Hybrid setup (balanced)
rubber_duck llm set-default ollama
rubber_duck llm set-model ollama codellama
rubber_duck llm enable anthropic  # Fallback for complex tasks
```

### 3. Batch Processing Optimization

```bash
# Process multiple files with optimal models
process_files_optimally() {
  local files=("$@")
  
  for file in "${files[@]}"; do
    local size=$(wc -l < "$file")
    
    if (( size < 100 )); then
      # Small files: use fast model
      RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=phi rubber_duck analyze "$file" --format json
    elif (( size < 500 )); then
      # Medium files: use balanced model
      RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=codellama rubber_duck analyze "$file" --format json  
    else
      # Large files: use powerful model with streaming
      RUBBER_DUCK_PROVIDER=anthropic RUBBER_DUCK_MODEL=claude-3-sonnet rubber_duck analyze "$file" --verbose --format json
    fi
  done
}

process_files_optimally lib/**/*.ex
```

### 4. Connection Reuse and Caching

```bash
# First command establishes connection (slower)
rubber_duck llm status  # ~500ms

# Subsequent commands reuse connection (faster)
rubber_duck analyze file1.ex  # ~50ms
rubber_duck analyze file2.ex  # ~50ms

# Server caches analysis results
rubber_duck analyze large_file.ex  # 2s (first time)
rubber_duck analyze large_file.ex  # 0.1s (cached)

# Force fresh analysis when needed
rubber_duck analyze large_file.ex --no-cache
```

## Best Practices

1. **Provider Management Strategy**:
   ```bash
   # Set up reliable defaults
   rubber_duck llm set-default ollama
   rubber_duck llm set-model ollama codellama
   
   # Enable fallbacks
   rubber_duck llm enable openai
   rubber_duck llm enable anthropic
   
   # Test configuration
   rubber_duck llm status
   ```

2. **Model Selection Guidelines**:
   - **phi**: Quick completions, simple analysis
   - **codellama**: Code generation, refactoring, testing  
   - **claude-3-sonnet**: Complex analysis, documentation
   - **claude-3-opus**: Architecture design, complex reasoning
   - **gpt-4**: Fallback for any complex task

3. **Configuration Files**: Create project-specific settings:
   ```json
   # .rubber_duck.json
   {
     "default_provider": "ollama",
     "providers": {
       "ollama": {"model": "codellama"},
       "anthropic": {"model": "claude-3-sonnet"}
     },
     "analysis_options": {
       "include_suggestions": true,
       "type": "all"
     }
   }
   ```

4. **Health Monitoring**: Always verify before critical operations:
   ```bash
   # Create a pre-flight check function
   rubber_duck_safe() {
     # Check overall health
     if ! rubber_duck health --format json | jq -e '.status == "healthy"' > /dev/null; then
       echo "Error: Server unhealthy"
       return 1
     fi
     
     # Check provider availability
     if ! rubber_duck llm status --format json | jq -e '[.providers[] | select(.health == "healthy")] | length > 0' > /dev/null; then
       echo "Error: No healthy providers"
       return 1
     fi
     
     # Execute command
     rubber_duck "$@"
   }
   
   # Use for important operations
   rubber_duck_safe generate "critical system component"
   ```

5. **Shell Integration**: Add useful aliases and functions:
   ```bash
   # Add to ~/.bashrc or ~/.zshrc
   alias rd='rubber_duck'
   alias rda='rubber_duck analyze'
   alias rdg='rubber_duck generate'
   alias rdt='rubber_duck test'
   alias rdh='rubber_duck health'
   alias rdls='rubber_duck llm status'
   
   # Smart model selection
   rd_fast() { RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=phi rubber_duck "$@"; }
   rd_smart() { RUBBER_DUCK_PROVIDER=anthropic RUBBER_DUCK_MODEL=claude-3-sonnet rubber_duck "$@"; }
   rd_code() { RUBBER_DUCK_PROVIDER=ollama RUBBER_DUCK_MODEL=codellama rubber_duck "$@"; }
   ```

## Next Steps

- Explore [Provider Integration Guide](../developer/provider_integration.md) for adding custom LLM providers
- Read [Server Administration Guide](../admin/server_setup.md) for production deployment
- Check [Plugin Development](../developer/plugin_development.md) to extend functionality
- Review [Performance Tuning](../admin/performance_tuning.md) for optimization strategies

---

*Experience the power of AI-assisted development with dynamic LLM configuration! 🦆*