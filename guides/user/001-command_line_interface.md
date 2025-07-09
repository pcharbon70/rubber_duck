# RubberDuck Command Line Interface Guide

This guide covers how to use RubberDuck's command-line interface (CLI) for AI-powered coding assistance, including setting up LLM connections and using various commands.

## Table of Contents

1. [Installation & Setup](#installation--setup)
2. [Connecting to LLMs](#connecting-to-llms)
3. [Core Commands](#core-commands)
4. [Output Formats](#output-formats)
5. [Common Workflows](#common-workflows)
6. [Troubleshooting](#troubleshooting)

## Installation & Setup

### Prerequisites

- Elixir 1.15+ and Erlang/OTP 25+
- PostgreSQL 16+ (for vector storage and extensions)
- Git

### Initial Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/rubber_duck.git
cd rubber_duck

# Install dependencies
mix deps.get

# Create and setup the database
mix ash.setup

# This will:
# - Create the database
# - Install required PostgreSQL extensions (pgvector, uuid-ossp, etc.)
# - Run all migrations
```

### Building the CLI

```bash
# Compile the project
mix compile

# Build the CLI executable (optional)
mix escript.build
```

### Database Management

```bash
# Run new migrations
mix ash.migrate

# Rollback migrations
mix ash.rollback

# Reset database (drop, create, migrate)
mix ash.reset

# Check migration status
mix ash.migrate --status
```

### Running the CLI

You can run the CLI in two ways:

```bash
# Using mix directly
mix rubber_duck <command> [options]

# Using the compiled escript (if built)
./rubber_duck <command> [options]
```

## Connecting to LLMs

Before using RubberDuck's AI features, you need to connect to at least one LLM provider.

### Available Providers

1. **Mock Provider** - For testing, no external service required
2. **Ollama** - Run LLMs locally
3. **Text Generation Inference (TGI)** - High-performance inference server

### Setting Up Ollama (Recommended for Local Use)

#### 1. Install Ollama

```bash
# Linux/Mac
curl -fsSL https://ollama.ai/install.sh | sh

# Or download from https://ollama.ai/download
```

#### 2. Start Ollama Service

```bash
# Start in a separate terminal
ollama serve
```

#### 3. Pull Models

```bash
# Download models you want to use
ollama pull llama2        # General purpose
ollama pull codellama     # Code-specific
ollama pull mistral       # Fast and efficient
```

#### 4. Connect RubberDuck to Ollama

```bash
# Connect to Ollama
rubber_duck llm connect ollama

# Verify connection
rubber_duck llm status
```

### Setting Up TGI (For Production Use)

#### 1. Start TGI with Docker

```bash
# Run TGI with a specific model
docker run --gpus all --shm-size 1g -p 8080:80 \
  -v $HOME/.cache/huggingface:/data \
  ghcr.io/huggingface/text-generation-inference:latest \
  --model-id meta-llama/Llama-2-7b-chat-hf
```

#### 2. Connect RubberDuck

```bash
# Connect to TGI
rubber_duck llm connect tgi

# Check status
rubber_duck llm status
```

### Managing LLM Connections

```bash
# View status of all providers
rubber_duck llm status

# Connect to all configured providers
rubber_duck llm connect

# Connect to specific provider
rubber_duck llm connect ollama

# Disconnect from provider
rubber_duck llm disconnect ollama

# Disable provider (keeps connection but won't use it)
rubber_duck llm disable ollama

# Enable provider
rubber_duck llm enable ollama
```

### Connection Status Output

```bash
$ rubber_duck llm status

Provider Status:
┌─────────┬────────────┬─────────┬─────────┬────────────────┬────────┐
│ Provider│ Status     │ Enabled │ Health  │ Last Used      │ Errors │
├─────────┼────────────┼─────────┼─────────┼────────────────┼────────┤
│ mock    │ connected  │ true    │ healthy │ never          │ 0      │
│ ollama  │ connected  │ true    │ healthy │ 2024-01-15 ... │ 0      │
│ tgi     │ disconnected│ true    │ not connected │ never     │ 0      │
└─────────┴────────────┴─────────┴─────────┴────────────────┴────────┘

Summary: 3 providers total, 2 connected, 2 healthy
```

## Core Commands

### 1. Code Analysis

Analyze code files or entire projects for issues, patterns, and improvements.

```bash
# Analyze a single file
rubber_duck analyze lib/my_module.ex

# Analyze with specific analysis type
rubber_duck analyze lib/my_module.ex --type semantic

# Analyze entire directory
rubber_duck analyze lib/ --recursive

# Include fix suggestions
rubber_duck analyze lib/my_module.ex --include-suggestions
```

**Options:**
- `--type <all|semantic|style|security>` - Type of analysis (default: all)
- `--recursive` - Analyze directories recursively
- `--include-suggestions` - Include fix suggestions in output
- `--format <plain|json|table>` - Output format

**Example Output:**
```
Analyzing: lib/my_module.ex

Issues Found:
1. Line 15: Unused variable 'result'
   Suggestion: Remove the variable or use it
   
2. Line 42: Function complexity too high (cyclomatic complexity: 12)
   Suggestion: Consider breaking into smaller functions

Summary: 2 issues found (1 warning, 1 info)
```

### 2. Code Generation

Generate code from natural language descriptions.

```bash
# Generate code to stdout
rubber_duck generate "create a GenServer that manages a user session"

# Generate to a file
rubber_duck generate "REST API endpoint for user authentication" \
  --output lib/my_app_web/controllers/auth_controller.ex

# Specify target language
rubber_duck generate "binary search algorithm" --language python

# Use context from existing files
rubber_duck generate "add pagination to this query" \
  --context lib/my_app/users.ex
```

**Options:**
- `--output <file>` - Output file path
- `--language <lang>` - Target programming language (default: elixir)
- `--context <file>` - Context file or directory
- `--interactive` - Enter interactive refinement mode

**Example:**
```bash
$ rubber_duck generate "create a function to validate email addresses"

Generated code:

```elixir
def validate_email(email) when is_binary(email) do
  email_regex = ~r/^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$/
  
  case Regex.match?(email_regex, email) do
    true -> {:ok, email}
    false -> {:error, "Invalid email format"}
  end
end

def validate_email(_), do: {:error, "Email must be a string"}
```

### 3. Code Completion

Get intelligent code completions at a specific position.

```bash
# Get completions at line 25, column 10
rubber_duck complete lib/my_module.ex --line 25 --column 10

# Specify number of suggestions
rubber_duck complete lib/my_module.ex -l 25 -c 10 --max-suggestions 10
```

**Options:**
- `--line <n>` or `-l <n>` - Line number (required)
- `--column <n>` or `-c <n>` - Column number (required)
- `--max-suggestions <n>` - Maximum suggestions (default: 5)

**Example Output:**
```
Completions for lib/my_module.ex:25:10

1. |> Enum.map(&process_item/1)
   Confidence: 0.95
   
2. |> Enum.filter(&valid?/1)
   Confidence: 0.87
   
3. |> Enum.reduce(%{}, fn item, acc ->
   Confidence: 0.82
```

### 4. Code Refactoring

Refactor code based on instructions or patterns.

```bash
# Refactor with instructions
rubber_duck refactor lib/my_module.ex "extract the validation logic into separate functions"

# Show diff instead of full output
rubber_duck refactor lib/my_module.ex "use pattern matching instead of if statements" --diff

# Refactor in place (modifies the file)
rubber_duck refactor lib/my_module.ex "convert to use with statement" --in-place

# Output to different file
rubber_duck refactor lib/old_module.ex "modernize the code" --output lib/new_module.ex
```

**Options:**
- `--output <file>` - Output file path
- `--diff` - Show diff instead of full output
- `--in-place` - Modify the file directly

**Example:**
```bash
$ rubber_duck refactor lib/user.ex "make the code more functional" --diff

--- lib/user.ex
+++ lib/user.ex (refactored)
@@ -5,12 +5,8 @@
   def update_name(user, name) do
-    if name != nil and name != "" do
-      user.name = name
-      {:ok, user}
-    else
-      {:error, "Invalid name"}
-    end
+    case validate_name(name) do
+      {:ok, valid_name} -> {:ok, %{user | name: valid_name}}
+      error -> error
+    end
   end
+
+  defp validate_name(name) when is_binary(name) and name != "",
+    do: {:ok, name}
+  defp validate_name(_), do: {:error, "Invalid name"}
```

### 5. Test Generation

Generate comprehensive tests for existing code.

```bash
# Generate tests for a module
rubber_duck test lib/my_module.ex

# Specify test framework
rubber_duck test lib/my_module.ex --framework exunit

# Output to specific file
rubber_duck test lib/my_module.ex --output test/my_module_test.exs

# Include edge cases
rubber_duck test lib/my_module.ex --include-edge-cases

# Generate property tests
rubber_duck test lib/my_module.ex --include-property-tests
```

**Options:**
- `--framework <name>` - Test framework (default: exunit)
- `--output <file>` - Output file path
- `--include-edge-cases` - Generate edge case tests
- `--include-property-tests` - Generate property-based tests

**Example Output:**
```elixir
defmodule MyModuleTest do
  use ExUnit.Case
  alias MyModule

  describe "validate_email/1" do
    test "accepts valid email addresses" do
      assert {:ok, "user@example.com"} = MyModule.validate_email("user@example.com")
      assert {:ok, "test.user+tag@domain.co.uk"} = MyModule.validate_email("test.user+tag@domain.co.uk")
    end

    test "rejects invalid email addresses" do
      assert {:error, "Invalid email format"} = MyModule.validate_email("invalid")
      assert {:error, "Invalid email format"} = MyModule.validate_email("@example.com")
      assert {:error, "Invalid email format"} = MyModule.validate_email("user@")
    end

    test "handles non-string input" do
      assert {:error, "Email must be a string"} = MyModule.validate_email(123)
      assert {:error, "Email must be a string"} = MyModule.validate_email(nil)
      assert {:error, "Email must be a string"} = MyModule.validate_email(%{})
    end
  end
end
```

## Output Formats

RubberDuck supports multiple output formats for different use cases:

### Plain Text (Default)

Human-readable format for terminal display.

```bash
rubber_duck analyze lib/my_module.ex --format plain
```

### JSON

Machine-readable format for scripting and tooling integration.

```bash
rubber_duck analyze lib/my_module.ex --format json | jq '.issues'
```

**Example JSON Output:**
```json
{
  "type": "analysis_result",
  "file": "lib/my_module.ex",
  "issues": [
    {
      "line": 15,
      "column": 5,
      "severity": "warning",
      "message": "Unused variable 'result'",
      "suggestion": "Remove the variable or use it"
    }
  ],
  "summary": {
    "total": 1,
    "errors": 0,
    "warnings": 1,
    "info": 0
  }
}
```

### Table

Structured table format for better readability of tabular data.

```bash
rubber_duck llm status --format table
```

## Common Workflows

### 1. Setting Up a New Development Environment

```bash
# 1. Connect to your preferred LLM
rubber_duck llm connect ollama

# 2. Analyze your project structure
rubber_duck analyze lib/ --recursive > analysis_report.txt

# 3. Generate missing tests
for file in lib/**/*.ex; do
  test_file="test/${file#lib/}_test.exs"
  if [ ! -f "$test_file" ]; then
    rubber_duck test "$file" --output "$test_file"
  fi
done
```

### 2. Refactoring Legacy Code

```bash
# 1. Analyze the module for issues
rubber_duck analyze lib/legacy_module.ex --include-suggestions

# 2. Refactor based on analysis
rubber_duck refactor lib/legacy_module.ex "modernize and improve code quality"

# 3. Generate comprehensive tests
rubber_duck test lib/legacy_module.ex --include-edge-cases

# 4. Verify improvements
rubber_duck analyze lib/legacy_module.ex
```

### 3. Interactive Development Session

```bash
# 1. Start with code generation
rubber_duck generate "create a rate limiter using GenServer"

# 2. Save and analyze
rubber_duck generate "create a rate limiter using GenServer" > lib/rate_limiter.ex
rubber_duck analyze lib/rate_limiter.ex

# 3. Add tests
rubber_duck test lib/rate_limiter.ex --output test/rate_limiter_test.exs

# 4. Refine based on needs
rubber_duck refactor lib/rate_limiter.ex "add configuration options"
```

### 4. CI/CD Integration

```yaml
# .github/workflows/code_quality.yml
name: Code Quality Check

on: [push, pull_request]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      
      - name: Setup Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '25'
          
      - name: Install dependencies
        run: mix deps.get
        
      - name: Run RubberDuck analysis
        run: |
          mix rubber_duck analyze lib/ --recursive --format json > analysis.json
          
      - name: Check for critical issues
        run: |
          errors=$(jq '.summary.errors' analysis.json)
          if [ "$errors" -gt 0 ]; then
            echo "Found $errors errors!"
            exit 1
          fi
```

## Troubleshooting

### LLM Connection Issues

#### "Failed to connect to ollama"

1. **Check Ollama is running:**
   ```bash
   ps aux | grep ollama
   # If not running, start it:
   ollama serve
   ```

2. **Verify Ollama is accessible:**
   ```bash
   curl http://localhost:11434/api/tags
   ```

3. **Check you have models installed:**
   ```bash
   ollama list
   # If empty, pull a model:
   ollama pull llama2
   ```

#### "Provider not configured"

Add the provider to your configuration file:

```elixir
# config/dev.exs
config :rubber_duck, :llm,
  providers: [
    %{
      name: :ollama,
      adapter: RubberDuck.LLM.Providers.Ollama,
      base_url: "http://localhost:11434",
      models: ["llama2", "codellama"]
    }
  ]
```

### Command Issues

#### "No command specified"

Make sure to specify a command:
```bash
# Wrong
rubber_duck

# Correct
rubber_duck analyze lib/my_module.ex
```

#### "Unknown command"

Check available commands:
```bash
rubber_duck --help
```

Valid commands are: `analyze`, `generate`, `complete`, `refactor`, `test`, `llm`

### Performance Issues

#### Slow Response Times

1. **Check LLM connection health:**
   ```bash
   rubber_duck llm status
   ```

2. **Use a faster model:**
   ```bash
   # Switch to a smaller, faster model
   ollama pull phi
   rubber_duck llm connect ollama
   ```

3. **Check system resources:**
   ```bash
   # CPU and memory usage
   top
   
   # Disk I/O
   iotop
   ```

### Getting Help

1. **Command help:**
   ```bash
   rubber_duck <command> --help
   ```

2. **Check logs:**
   ```bash
   tail -f log/dev.log
   ```

3. **Enable debug mode:**
   ```bash
   rubber_duck analyze lib/my_module.ex --debug
   ```

## Best Practices

1. **Start with the Mock Provider**: Test commands with the mock provider before connecting to real LLMs.

2. **Use Appropriate Models**: 
   - `codellama` for code-specific tasks
   - `mistral` or `phi` for faster responses
   - `llama2` for general purpose

3. **Leverage Output Formats**:
   - Use JSON format for scripting
   - Use table format for status information
   - Use plain format for reading

4. **Batch Operations**: For multiple files, use shell scripting:
   ```bash
   find lib -name "*.ex" -exec rubber_duck analyze {} \;
   ```

5. **Cache Results**: RubberDuck caches analysis results. Use `--force` to bypass cache when needed.

6. **Monitor Health**: Regularly check provider health:
   ```bash
   rubber_duck llm status
   ```

## Next Steps

- Explore the [Web Interface Guide](002-web_interface.md) for using RubberDuck's web UI
- Read the [Plugin Development Guide](../developer/001-creating_plugins.md) to extend RubberDuck
- Check the [API Documentation](../api/index.md) for programmatic access

---

*Happy coding with RubberDuck! 🦆*