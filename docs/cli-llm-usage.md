# RubberDuck CLI with LLM Integration

This guide explains how to use the RubberDuck CLI with LLM integration for AI-powered code assistance.

## Prerequisites

1. **Start the Application**:
   ```bash
   mix deps.get
   mix ecto.create
   mix ecto.migrate
   iex -S mix
   ```

2. **Configure LLM Provider** (optional):
   - By default, uses a mock provider for testing
   - To use Ollama (local LLM), uncomment the Ollama configuration in `config/dev.exs`
   - To use OpenAI/Anthropic, add your API keys to the configuration

## Available Commands

### 1. Code Generation

Generate code from natural language descriptions:

```bash
# Basic generation
mix rubber_duck generate "Create a GenServer that manages user sessions"

# Generate to a file
mix rubber_duck generate "REST API controller for products" --output lib/api/product_controller.ex

# Generate in different languages
mix rubber_duck generate "Binary search algorithm" --language python

# Interactive mode for refinement
mix rubber_duck generate "Complex state machine" --interactive
```

### 2. Code Completion

Get intelligent code completions at cursor position:

```bash
# Get completions at specific position
mix rubber_duck complete lib/my_module.ex --line 42 --column 15

# Limit number of suggestions
mix rubber_duck complete lib/my_module.ex -l 42 -c 15 --max-suggestions 3
```

### 3. Code Analysis

Analyze code for issues, patterns, and improvements:

```bash
# Analyze a single file
mix rubber_duck analyze lib/my_module.ex

# Analyze a directory recursively
mix rubber_duck analyze lib/ --recursive

# Analyze specific aspects
mix rubber_duck analyze lib/ --type security
mix rubber_duck analyze lib/ --type style
mix rubber_duck analyze lib/ --type complexity

# Output in different formats
mix rubber_duck analyze lib/my_module.ex --format json
```

### 4. Code Refactoring

Refactor code based on instructions:

```bash
# Basic refactoring
mix rubber_duck refactor lib/old_code.ex "Extract authentication logic into separate module"

# Show diff without applying
mix rubber_duck refactor lib/code.ex "Improve variable naming" --diff

# Apply changes directly
mix rubber_duck refactor lib/code.ex "Add proper error handling" --in-place
```

### 5. Test Generation

Generate comprehensive tests for your code:

```bash
# Generate tests for a module
mix rubber_duck test lib/my_module.ex

# Specify test framework
mix rubber_duck test lib/my_module.ex --framework exunit

# Include edge cases and property tests
mix rubber_duck test lib/my_module.ex --include-edge-cases --include-property-tests

# Output to specific file
mix rubber_duck test lib/my_module.ex --output test/my_module_test.exs
```

## Output Formats

All commands support multiple output formats:

### Plain Text (Default)
```bash
mix rubber_duck analyze lib/example.ex
```
Output:
```
File: lib/example.ex
Severity: warning
Issues:
  - [10:5] Unused variable 'x'
  - [25:3] Function complexity too high
```

### JSON Format
```bash
mix rubber_duck analyze lib/example.ex --format json
```
Output:
```json
{
  "type": "analysis",
  "results": [{
    "file": "lib/example.ex",
    "issues": [
      {"line": 10, "column": 5, "message": "Unused variable 'x'"}
    ]
  }]
}
```

### Table Format
```bash
mix rubber_duck analyze lib/example.ex --format table
```

## Configuration

### Using Mock Provider (Default)

The mock provider is configured by default for testing without external dependencies:

```elixir
# config/dev.exs
config :rubber_duck, :llm,
  providers: [
    %{
      name: :mock,
      adapter: RubberDuck.LLM.Providers.Mock,
      default: true,
      models: ["mock-gpt", "mock-codellama"]
    }
  ]
```

### Using Ollama (Local LLM)

1. Install Ollama:
   ```bash
   curl -fsSL https://ollama.com/install.sh | sh
   ```

2. Pull a model:
   ```bash
   ollama pull codellama
   ```

3. Uncomment Ollama configuration in `config/dev.exs`:
   ```elixir
   %{
     name: :ollama,
     adapter: RubberDuck.LLM.Providers.Ollama,
     base_url: "http://localhost:11434",
     models: ["codellama", "llama2", "mistral"]
   }
   ```

### Using OpenAI

Add to your configuration:

```elixir
%{
  name: :openai,
  adapter: RubberDuck.LLM.Providers.OpenAI,
  api_key: System.get_env("OPENAI_API_KEY"),
  models: ["gpt-4", "gpt-3.5-turbo"]
}
```

## Advanced Usage

### Batch Processing

Process multiple files:

```bash
# Analyze all Elixir files
find lib -name "*.ex" | xargs -I {} mix rubber_duck analyze {}

# Generate tests for multiple modules
for file in lib/*.ex; do
  mix rubber_duck test "$file" --output "test/$(basename "$file" .ex)_test.exs"
done
```

### Configuration File

Create `.rubber_duck.json` in your project root:

```json
{
  "llm": {
    "default_model": "codellama",
    "temperature": 0.7
  },
  "analysis": {
    "include_metrics": true,
    "severity_threshold": "warning"
  }
}
```

### Shell Completion

Add to your shell configuration:

```bash
# Bash
eval "$(mix rubber_duck completion bash)"

# Zsh
eval "$(mix rubber_duck completion zsh)"
```

## Troubleshooting

### LLM Connection Issues

1. Check if the LLM service is running:
   ```bash
   # For Ollama
   curl http://localhost:11434/api/tags
   ```

2. Verify configuration:
   ```bash
   mix rubber_duck doctor
   ```

### Performance Tips

1. Use caching for faster responses:
   ```bash
   export RUBBER_DUCK_CACHE=true
   ```

2. Adjust timeout for large files:
   ```bash
   mix rubber_duck generate "Complex system" --timeout 60000
   ```

### Debug Mode

Enable verbose logging:

```bash
mix rubber_duck analyze lib/ --debug
```

## Examples

### Real-World Scenarios

1. **Refactor a Legacy Module**:
   ```bash
   mix rubber_duck analyze lib/legacy.ex
   mix rubber_duck refactor lib/legacy.ex "Modernize code and improve structure" --diff
   mix rubber_duck test lib/legacy.ex --output test/legacy_test.exs
   ```

2. **Generate API Endpoints**:
   ```bash
   mix rubber_duck generate "CRUD endpoints for User resource with authentication" \
     --output lib/my_app_web/controllers/user_controller.ex
   ```

3. **Complete Complex Code**:
   ```bash
   # When implementing a difficult algorithm
   mix rubber_duck complete lib/algorithms/graph.ex -l 45 -c 20
   ```

## Integration with Editors

The CLI can be integrated with various editors:

- **VS Code**: Use the Tasks feature
- **Vim**: Create custom commands
- **Emacs**: Use compilation mode

Example VS Code task:

```json
{
  "label": "RubberDuck: Analyze Current File",
  "type": "shell",
  "command": "mix rubber_duck analyze ${file}",
  "problemMatcher": []
}
```

## Best Practices

1. **Start with Analysis**: Always analyze before refactoring
2. **Review Generated Code**: LLM output should be reviewed
3. **Use Appropriate Models**: Different models excel at different tasks
4. **Incremental Changes**: Make small, focused changes
5. **Test Generated Code**: Always run tests after generation

## Next Steps

- Explore advanced LLM features like RAG and Chain-of-Thought
- Configure multiple providers for fallback
- Set up continuous integration with CLI commands
- Create custom engines for domain-specific tasks