# Feature 5.3: CLI Implementation

## Overview
Implement a feature-rich command-line interface for RubberDuck that provides terminal users with access to all coding assistant capabilities. The CLI will use Optimus for argument parsing and support multiple output formats, interactive mode, and batch processing.

## Requirements from Implementation Plan

### Core Tasks:
1. Create `RubberDuck.CLI` module with Optimus
2. Implement subcommands:
   - `analyze` - Analyze files/projects
   - `generate` - Generate code from prompts
   - `complete` - Get code completions
   - `refactor` - Refactor code
   - `test` - Generate tests
3. Add interactive mode support
4. Implement output formatting options (JSON, plain text)
5. Create progress indicators for long operations
6. Add configuration file support
7. Implement shell completion scripts
8. Build pipe-friendly output modes
9. Add batch processing support

### Testing Requirements:
- Test analyze command execution
- Test generate command creates code
- Test JSON output formatting
- Test interactive mode operation
- Test error handling for missing files
- Test argument validation
- Test batch processing

## Implementation Plan

### Phase 1: Core CLI Infrastructure
1. Add Optimus dependency to mix.exs
2. Create base CLI module structure
3. Implement command parser and router
4. Set up output formatting system
5. Create basic mix task for CLI entry

### Phase 2: Command Implementation
1. Implement `analyze` command
   - File/project analysis integration
   - Result formatting
   - Progress indicators
2. Implement `generate` command
   - Prompt handling
   - Code generation integration
   - Output handling
3. Implement `complete` command
   - Context building
   - Completion integration
   - Multiple suggestions support
4. Implement `refactor` command
   - Code transformation support
   - Diff output
5. Implement `test` command
   - Test generation for code
   - Multiple test framework support

### Phase 3: Advanced Features
1. Interactive mode
   - REPL-like interface
   - Context persistence
   - Command history
2. Configuration file support
   - User preferences
   - Default options
   - Project-specific configs
3. Shell completion scripts
   - Bash completion
   - Zsh completion
   - Fish completion
4. Batch processing
   - Multiple file handling
   - Parallel processing
   - Result aggregation

### Phase 4: Integration & Polish
1. Progress indicators
   - Spinner for indeterminate operations
   - Progress bars for determinate operations
   - ETA calculation
2. Pipe-friendly modes
   - Machine-readable output
   - Streaming support
   - Exit codes
3. Error handling
   - User-friendly error messages
   - Debug mode with stack traces
   - Recovery suggestions

## Architecture Design

### Module Structure
```
lib/rubber_duck/cli/
├── cli.ex                  # Main CLI module with Optimus parser
├── runner.ex              # Command execution coordinator
├── commands/              # Individual command modules
│   ├── analyze.ex
│   ├── generate.ex
│   ├── complete.ex
│   ├── refactor.ex
│   └── test.ex
├── formatter/             # Output formatting
│   ├── formatter.ex       # Base formatter behavior
│   ├── json.ex           # JSON output formatter
│   ├── plain.ex          # Plain text formatter
│   └── table.ex          # Table formatter
├── interactive/           # Interactive mode
│   ├── repl.ex           # REPL implementation
│   ├── session.ex        # Session management
│   └── history.ex        # Command history
├── config/               # Configuration handling
│   ├── loader.ex         # Config file loader
│   └── validator.ex      # Config validation
└── utils/                # Utilities
    ├── progress.ex       # Progress indicators
    ├── color.ex          # Terminal colors
    └── shell.ex          # Shell integration

lib/mix/tasks/
├── rubber_duck.ex        # Main mix task entry point
└── rubber_duck/
    └── completion.ex     # Shell completion generator
```

### Key Design Decisions

1. **Optimus Integration**: Use Optimus for declarative command parsing with built-in help generation
2. **Modular Commands**: Each command is a separate module implementing a common behavior
3. **Flexible Output**: Support multiple output formats with a formatter behavior
4. **Progressive Enhancement**: Basic functionality works everywhere, enhanced features for capable terminals
5. **Integration Points**: Commands are thin wrappers around existing services
6. **Testability**: Commands return structured data, formatting is separate

## Integration Points

1. **Engine System**: Commands will use `Engine.Manager` for engine operations
2. **LLM Service**: Use `LLM.Service` for AI-powered features
3. **Analysis System**: Integrate with existing analysis engines
4. **Workspace Domain**: Use Ash resources for project/file management
5. **Memory System**: Maintain context across interactive sessions
6. **Context Builder**: Use for completion and generation commands

## Testing Strategy

1. **Unit Tests**: Test each command module independently
2. **Integration Tests**: Test command execution with real services
3. **Formatter Tests**: Verify output formatting correctness
4. **Interactive Tests**: Test REPL functionality
5. **End-to-End Tests**: Test complete CLI workflows

## Dependencies

- `optimus` - Command line parser
- `progress_bar` - Progress indicators (optional, can implement custom)
- `table_rex` - Table formatting (optional)
- `ex_prompt` - Interactive prompts (optional)

## Next Steps

1. Add Optimus dependency
2. Create basic CLI module structure
3. Implement first command (analyze)
4. Add output formatting
5. Create mix task entry point
6. Write tests
7. Iterate on remaining commands