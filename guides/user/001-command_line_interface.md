# RubberDuck Command Line Interface Guide

This comprehensive guide covers how to use RubberDuck's new WebSocket-based CLI client for AI-powered coding assistance. The CLI client connects to a running RubberDuck server, eliminating compilation overhead and providing real-time, stateful interactions.

## Table of Contents

1. [Overview & Architecture](#overview--architecture)
2. [Installation & Setup](#installation--setup)
3. [Authentication](#authentication)
4. [Connecting to LLMs](#connecting-to-llms)
5. [Core Commands](#core-commands)
6. [Advanced Features](#advanced-features)
7. [Output Formats](#output-formats)
8. [Common Workflows](#common-workflows)
9. [Troubleshooting](#troubleshooting)
10. [Performance Tips](#performance-tips)

## Overview & Architecture

The RubberDuck CLI is a standalone client that communicates with the RubberDuck server via WebSocket channels. This architecture provides several key benefits:

- **No Compilation Required**: The CLI runs as a pre-built binary
- **Persistent Connection**: Maintains state between commands
- **Real-time Streaming**: Live updates for long-running operations
- **Remote Access**: Connect to RubberDuck servers anywhere
- **Multiple Clients**: Support for concurrent CLI sessions

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
  "created_at": "2024-01-15T10:30:00Z"
}
```

### Environment Variables

You can also use environment variables:

```bash
export RUBBER_DUCK_API_KEY="your-api-key-here"
export RUBBER_DUCK_URL="ws://production.server.com/socket/websocket"
```

## Connecting to LLMs

Before using AI features, connect to one or more LLM providers through the CLI.

### Available Providers

1. **Mock** - Testing provider, no external service required
2. **Ollama** - Run LLMs locally
3. **TGI (Text Generation Inference)** - High-performance inference server

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

### Managing LLM Connections

```bash
# View all provider status
rubber_duck llm status

# Output:
# LLM Provider Status:
# 
# ✓ mock
#   Status: connected
#   Health: ● healthy
#   Enabled: true
#   Last used: never
#   Errors: 0
# 
# ✓ ollama
#   Status: connected
#   Health: ● healthy
#   Enabled: true
#   Last used: 2024-01-15T14:30:00Z
#   Errors: 0
# 
# ✗ tgi
#   Status: disconnected
#   Health: ? unknown
#   Enabled: true
#   Last used: never
#   Errors: 0

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

### 6. Server Health Monitoring

Monitor the health and status of your RubberDuck server:

```bash
# Basic health check
rubber_duck health

# Health check with table format for better readability
rubber_duck health --format table

# JSON output for scripting and monitoring
rubber_duck health --format json

# Use with jq for specific metrics
rubber_duck health --format json | jq '.memory.total_mb'
```

**Health Information Includes:**
- Server status and uptime
- Memory usage breakdown (total, processes, ETS, binaries, system)
- Active WebSocket connections
- Channel statistics
- LLM provider health status

**Example Output (Plain Format):**
```
Server Health Status:

Status: healthy
Server Time: 2024-01-15T10:30:00Z
Uptime: 2d 14h 30m

Memory Usage:
  Total: 512.3 MB
  Processes: 256.7 MB
  ETS Tables: 45.2 MB
  Binaries: 89.4 MB
  System: 121.0 MB

Connections:
  Active WebSocket Connections: 3
  Total Channels: 4

Provider Health:
  mock: ● healthy (connected)
  ollama: ● healthy (connected)
  tgi: ? unknown (disconnected)
```

**Example Output (Table Format):**
```
Server Health: healthy
Server Time: 2024-01-15T10:30:00Z
Uptime: 2d 14h 30m

Memory Usage:
+-----------+--------------+
| Component | Usage (MB)   |
+-----------+--------------+
| Total     | 512.3        |
| Processes | 256.7        |
| ETS Tables| 45.2         |
| Binaries  | 89.4         |
| System    | 121.0        |
+-----------+--------------+

Connections: 3 active, 4 channels

Provider Health:
+----------+--------------+---------+
| Provider | Status       | Health  |
+----------+--------------+---------+
| mock     | connected    | healthy |
| ollama   | connected    | healthy |
| tgi      | disconnected | unknown |
+----------+--------------+---------+
```

**Use Cases:**
- Pre-flight checks before running important operations
- Monitoring server resource usage
- Verifying provider connectivity
- Debugging performance issues
- Integration with monitoring systems

## Core Commands

### 1. Code Analysis

Analyze code for issues, patterns, and improvements.

```bash
# Basic file analysis
rubber_duck analyze lib/my_module.ex

# Analyze with specific type
rubber_duck analyze lib/my_module.ex --type security

# Recursive directory analysis
rubber_duck analyze lib/ --recursive

# Include fix suggestions
rubber_duck analyze lib/my_module.ex --include-suggestions
```

**Options:**
- `-t, --type <all|semantic|style|security>` - Analysis type (default: all)
- `-r, --recursive` - Analyze directories recursively
- `--include-suggestions` - Include fix suggestions

**Example Output:**
```
Analyzing: lib/my_module.ex

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
```

### 2. Code Generation

Generate code from natural language descriptions with real-time streaming.

```bash
# Generate code with live output
rubber_duck generate "create a GenServer for rate limiting"

# Save to file
rubber_duck generate "user authentication module" \
  --output lib/auth.ex

# Specify language
rubber_duck generate "REST API client" --language python

# Use context files
rubber_duck generate "add caching to this module" \
  --context lib/existing_module.ex
```

**Options:**
- `-o, --output <file>` - Save to file
- `-l, --language <lang>` - Target language (default: elixir)
- `--context <file>` - Context files

**Real-time Output:**
```bash
$ rubber_duck generate "create a rate limiter using GenServer"
Generating code... 
defmodule RateLimiter do
  use GenServer
  
  # ... code streams in real-time ...
end

Generation complete!
```

### 3. Code Completion

Get intelligent completions at specific positions.

```bash
# Get completions
rubber_duck complete lib/my_module.ex --line 25 --column 10

# More suggestions
rubber_duck complete lib/my_module.ex -l 25 -c 10 --max 10
```

**Options:**
- `--line <n>` - Line number (required)
- `--column <n>` - Column number (required)
- `--max <n>` - Maximum suggestions (default: 5)

**Example Output:**
```
Code Completions:

1. |> Enum.map(&String.downcase/1)
   Maps all strings to lowercase
   Insert: |> Enum.map(&String.downcase/1)

2. |> Enum.filter(&is_binary/1)
   Filters only string values
   Insert: |> Enum.filter(&is_binary/1)

3. |> Enum.reject(&is_nil/1)
   Removes nil values
   Insert: |> Enum.reject(&is_nil/1)
```

### 4. Code Refactoring

Refactor code based on instructions.

```bash
# Refactor with preview
rubber_duck refactor lib/legacy.ex "modernize this code"

# Show diff only
rubber_duck refactor lib/module.ex "use pattern matching" --dry-run

# Interactive refactoring
rubber_duck refactor lib/complex.ex "simplify" --interactive
```

**Options:**
- `--dry-run` - Preview changes without applying
- `--interactive` - Step through changes
- `-o, --output <file>` - Save to different file

**Example Diff Output:**
```diff
Refactoring Changes:

lib/user.ex:
  Line 10-15
  Replace if-else with pattern matching

  Before:
    if user != nil and user.active do
      {:ok, user}
    else
      {:error, :invalid_user}
    end

  After:
    case user do
      %User{active: true} -> {:ok, user}
      _ -> {:error, :invalid_user}
    end
```

### 5. Test Generation

Generate comprehensive test suites.

```bash
# Generate tests
rubber_duck test lib/my_module.ex

# Save to file
rubber_duck test lib/calculator.ex \
  --output test/calculator_test.exs

# Include edge cases
rubber_duck test lib/validator.ex --include-edge-cases

# Property-based tests
rubber_duck test lib/parser.ex --include-property-tests
```

**Options:**
- `-o, --output <file>` - Output file
- `-f, --framework <name>` - Test framework (default: exunit)
- `--include-edge-cases` - Add edge case tests
- `--include-property-tests` - Add property tests

## Advanced Features

### Real-time Streaming

The CLI supports streaming for long-running operations:

```bash
# Watch generation progress
rubber_duck generate "complex implementation" --verbose

# Streaming output:
# Generating code... [█████████████░░░░░░░] 65%
# Creating module structure...
# Adding function definitions...
# Implementing business logic...
# Adding documentation...
# Generation complete!
```

### Batch Operations

Process multiple files efficiently:

```bash
# Analyze all files in a directory
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

### Remote Server Connection

Connect to remote RubberDuck servers:

```bash
# Configure remote server
rubber_duck auth setup
# Server URL: wss://rubber-duck.company.com/socket/websocket
# API Key: <your-remote-api-key>

# Use with commands
rubber_duck analyze lib/module.ex --server wss://remote.server.com
```

### Concurrent Sessions

The CLI supports multiple concurrent connections:

```bash
# Terminal 1: Run analysis
rubber_duck analyze project/ --recursive

# Terminal 2: Generate code simultaneously
rubber_duck generate "new feature implementation"

# Both commands run concurrently without interference
```

### Server Health Monitoring

Check the health and status of the RubberDuck server:

```bash
# Basic health check
rubber_duck health

# Health check with table format
rubber_duck health --format table

# Health check with JSON output for monitoring
rubber_duck health --format json
```

**Health Check Output:**
```
Server Health Status:

Status: healthy
Server Time: 2024-01-15T10:30:00Z
Uptime: 2d 14h 30m

Memory Usage:
  Total: 512.3 MB
  Processes: 256.7 MB
  ETS Tables: 45.2 MB
  Binaries: 89.4 MB
  System: 121.0 MB

Connections:
  Active WebSocket Connections: 3
  Total Channels: 4

Provider Health:
  mock: ● healthy (connected)
  ollama: ● healthy (connected)
  tgi: ? unknown (disconnected)
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

# Save for later processing
rubber_duck llm status --format json > provider_status.json

# Health check for monitoring
rubber_duck health --format json > health_status.json

# Extract specific health metrics
rubber_duck health --format json | jq '{uptime: .uptime.total_seconds, memory_mb: .memory.total_mb}'
```

Example JSON:
```json
{
  "type": "analysis_result",
  "file": "lib/module.ex",
  "issues": [
    {
      "line": 15,
      "column": 5,
      "severity": "warning",
      "message": "Unused variable",
      "suggestion": "Remove or use the variable"
    }
  ],
  "summary": {
    "total": 1,
    "errors": 0,
    "warnings": 1
  }
}
```

### Table Format

Structured tables for status and list outputs:

```bash
rubber_duck llm status --format table
```

Output:
```
┌─────────┬────────────┬─────────┬─────────┬──────────────┬────────┐
│ Provider│ Status     │ Enabled │ Health  │ Last Used    │ Errors │
├─────────┼────────────┼─────────┼─────────┼──────────────┼────────┤
│ mock    │ connected  │ true    │ healthy │ never        │ 0      │
│ ollama  │ connected  │ true    │ healthy │ 2 mins ago   │ 0      │
│ tgi     │ disconnected│ false   │ unknown │ never        │ 0      │
└─────────┴────────────┴─────────┴─────────┴──────────────┴────────┘
```

## Common Workflows

### 1. Initial Project Analysis

```bash
# Complete project health check
rubber_duck analyze . --recursive --format json > project_health.json

# Extract critical issues
jq '.issues[] | select(.severity == "error")' project_health.json

# Generate report
rubber_duck analyze . --recursive --include-suggestions > analysis_report.md
```

### 2. Test-Driven Development

```bash
# 1. Generate module from description
rubber_duck generate "user authentication service with JWT" \
  --output lib/auth_service.ex

# 2. Generate comprehensive tests
rubber_duck test lib/auth_service.ex \
  --output test/auth_service_test.exs \
  --include-edge-cases

# 3. Run tests and refine
mix test test/auth_service_test.exs

# 4. Refactor based on test results
rubber_duck refactor lib/auth_service.ex \
  "improve error handling and add logging"
```

### 3. Legacy Code Modernization

```bash
# 1. Analyze legacy module
rubber_duck analyze lib/legacy/old_module.ex --include-suggestions

# 2. Generate modernized version
rubber_duck refactor lib/legacy/old_module.ex \
  "modernize to use current Elixir patterns and idioms" \
  --output lib/modern/new_module.ex

# 3. Generate tests for new version
rubber_duck test lib/modern/new_module.ex \
  --include-property-tests

# 4. Compare behaviors
rubber_duck analyze lib/modern/new_module.ex --type semantic
```

### 4. Health Monitoring and Pre-flight Checks

```bash
# Pre-flight check before important operations
rubber_duck health --format json | jq -e '.status == "healthy"' || {
  echo "Server is not healthy!"
  exit 1
}

# Monitor memory usage during operations
echo "Before operation:"
rubber_duck health --format json | jq '.memory.total_mb'

# Run heavy operation
rubber_duck analyze large_project/ --recursive

echo "After operation:"
rubber_duck health --format json | jq '.memory.total_mb'

# Create a monitoring script
cat > monitor_health.sh << 'EOF'
#!/bin/bash
while true; do
  health=$(rubber_duck health --format json)
  memory=$(echo "$health" | jq '.memory.total_mb')
  uptime=$(echo "$health" | jq '.uptime.total_seconds')
  providers=$(echo "$health" | jq -r '.providers[] | "\(.name): \(.health)"')
  
  clear
  echo "=== RubberDuck Health Monitor ==="
  echo "Memory: ${memory} MB"
  echo "Uptime: $((uptime / 3600)) hours"
  echo ""
  echo "Providers:"
  echo "$providers"
  
  sleep 5
done
EOF

chmod +x monitor_health.sh
./monitor_health.sh
```

### 5. CI/CD Integration

```yaml
# .github/workflows/rubber_duck.yml
name: RubberDuck Analysis

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
        
    - name: Configure Authentication
      env:
        RUBBER_DUCK_API_KEY: ${{ secrets.RUBBER_DUCK_API_KEY }}
        RUBBER_DUCK_URL: ${{ secrets.RUBBER_DUCK_URL }}
      run: |
        ./rubber_duck auth status
        
    - name: Health Check
      run: |
        ./rubber_duck health --format json > health.json
        jq -e '.status == "healthy"' health.json || {
          echo "Server is not healthy!"
          jq '.' health.json
          exit 1
        }
        
    - name: Run Analysis
      run: |
        ./rubber_duck analyze lib/ --recursive --format json > analysis.json
        
    - name: Check Results
      run: |
        errors=$(jq '.summary.errors' analysis.json)
        if [ "$errors" -gt 0 ]; then
          echo "Found $errors errors!"
          jq '.issues[] | select(.severity == "error")' analysis.json
          exit 1
        fi
        
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

#### "Authentication failed"

1. **Regenerate API key on server:**
   ```bash
   mix rubber_duck.auth generate
   ```

2. **Update CLI configuration:**
   ```bash
   rubber_duck auth setup
   ```

### Performance Issues

#### Slow Command Execution

1. **Check connection latency:**
   ```bash
   # Built-in ping command
   time rubber_duck ping
   ```

2. **Monitor server health:**
   ```bash
   # Full health check
   rubber_duck health --format json | jq '.'
   
   # Check specific providers
   rubber_duck llm status --format json | jq '.providers[].health'
   ```

3. **Use appropriate models:**
   - `phi` or `mistral` for faster responses
   - `codellama` for code-specific tasks
   - `llama2` for complex reasoning

### Command Errors

#### "Command timed out"

Increase timeout for long operations:
```bash
# Set custom timeout (in seconds)
RUBBER_DUCK_TIMEOUT=120 rubber_duck generate "complex system"
```

#### "Streaming interrupted"

The CLI automatically reconnects, but you can force reconnection:
```bash
# Force new connection
rubber_duck auth setup --reconnect
```

### Debug Mode

Enable detailed logging:
```bash
# Verbose output
rubber_duck analyze lib/module.ex --verbose --debug

# Debug output includes:
# - WebSocket frame details
# - Message routing
# - Timing information
# - Server responses
```

## Performance Tips

### 1. Connection Reuse

The CLI maintains persistent connections:
```bash
# First command establishes connection (slower)
rubber_duck analyze file1.ex  # ~500ms

# Subsequent commands reuse connection (faster)
rubber_duck analyze file2.ex  # ~50ms
rubber_duck analyze file3.ex  # ~50ms
```

### 2. Batch Processing

Use JSON output for efficient batch processing:
```bash
# Process multiple files efficiently
find lib -name "*.ex" -print0 | \
  xargs -0 -I {} rubber_duck analyze {} --format json >> results.jsonl

# Process results
jq -s 'group_by(.file) | map({file: .[0].file, issues: map(.issues) | add})' results.jsonl
```

### 3. Model Selection

Choose models based on task requirements:
```bash
# Fast completion for simple tasks
RUBBER_DUCK_MODEL=phi rubber_duck complete file.ex --line 10 --column 5

# Powerful model for complex generation
RUBBER_DUCK_MODEL=llama2 rubber_duck generate "distributed system design"
```

### 4. Caching

The server caches analysis results:
```bash
# First analysis (full processing)
rubber_duck analyze large_file.ex  # 2s

# Repeated analysis (cached)
rubber_duck analyze large_file.ex  # 0.1s

# Force fresh analysis
rubber_duck analyze large_file.ex --no-cache
```

## Best Practices

1. **Keep CLI Updated**: Regularly update the CLI binary for new features and fixes

2. **Use Configuration Files**: For complex projects, create `.rubber_duck.json`:
   ```json
   {
     "default_format": "json",
     "preferred_model": "codellama",
     "analysis_options": {
       "include_suggestions": true,
       "type": "all"
     }
   }
   ```

3. **Leverage Shell Integration**: Add useful aliases:
   ```bash
   alias rda='rubber_duck analyze'
   alias rdg='rubber_duck generate'
   alias rdt='rubber_duck test'
   alias rdh='rubber_duck health'
   ```

4. **Monitor Health**: Set up monitoring for production:
   ```bash
   # Health check script
   #!/bin/bash
   # Check overall server health
   rubber_duck health --format json | jq -e '.status == "healthy"'
   
   # Check specific provider health
   rubber_duck llm status --format json | \
     jq -e '.providers | map(select(.health != "healthy")) | length == 0'
   ```

5. **Pre-operation Health Checks**: Always verify server health before critical operations:
   ```bash
   # Create a wrapper function
   rubber_duck_safe() {
     # Check health first
     if ! rubber_duck health --format json | jq -e '.status == "healthy"' > /dev/null; then
       echo "Error: Server is not healthy"
       rubber_duck health
       return 1
     fi
     
     # Check memory usage
     local memory=$(rubber_duck health --format json | jq '.memory.total_mb')
     if (( $(echo "$memory > 1000" | bc -l) )); then
       echo "Warning: High memory usage (${memory}MB)"
     fi
     
     # Execute the command
     rubber_duck "$@"
   }
   
   # Use the wrapper
   rubber_duck_safe analyze lib/ --recursive
   ```

## Next Steps

- Explore [WebSocket API Documentation](../api/websocket.md) for custom integrations
- Read [Server Administration Guide](../admin/server_setup.md) for production deployment
- Check [Plugin Development](../developer/001-creating_plugins.md) to extend functionality

---

*Experience the power of AI-assisted development with RubberDuck CLI! 🦆*