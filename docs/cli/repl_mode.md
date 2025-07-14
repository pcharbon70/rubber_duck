# RubberDuck REPL Mode

The RubberDuck CLI now includes an enhanced REPL (Read-Eval-Print Loop) mode for interactive conversations with the AI assistant. This provides a more natural and efficient way to interact with the AI without repeatedly typing `conversation send` commands.

## Quick Start

To start a REPL session:

```bash
rubber_duck repl
```

This will create a new conversation and drop you into an interactive prompt where you can type messages directly.

## Command-Line Options

- `-t, --type <type>` - Set conversation type (general, coding, debugging, planning, review). Default: general
- `-m, --model <model>` - Specify a model to use (e.g., "codellama", "gpt-4")
- `-r, --resume <id>` - Resume a previous conversation. Use "last" to resume the most recent
- `--no-welcome` - Skip the welcome message

## Examples

Start a coding-focused REPL:
```bash
rubber_duck repl -t coding
```

Resume your last conversation:
```bash
rubber_duck repl -r last
```

Start with a specific model:
```bash
rubber_duck repl -m "ollama codellama"
```

## REPL Commands

Once in the REPL, you can use these special commands:

### Basic Commands
- `/help` - Show available commands
- `/exit` - Exit the REPL (auto-saves conversation)
- `/clear` - Clear the screen
- `/info` - Show session information

### Conversation Management
- `/history` - Show conversation history
- `/save [filename]` - Save conversation to file
- `/recent` - Show recent conversations
- `/switch <id>` - Switch to another conversation

### Context Management
- `/context` - Show current context files
- `/context add <file>` - Add a file to the conversation context
- `/context clear` - Clear all context files

### Model Management
- `/model` - Show current model and LLM status
- `/model <spec>` - Change model (e.g., `/model ollama codellama`)

### Integrated Commands
- `/analyze <file>` - Analyze code file in conversation context
- `/generate <prompt>` - Generate code based on prompt
- `/refactor <instruction>` - Refactor code in context files

## Multi-line Input

The REPL supports multi-line input in two ways:

### Triple Quotes
Use `"""` to start and end multi-line input:

```
rd> """
This is a multi-line
message that spans
multiple lines
"""
```

### Line Continuation
Use `\` at the end of a line to continue on the next line:

```
rd> This is a long message that \
... continues on the next line
```

## Features

### Auto-save
The REPL automatically saves your conversation every 5 minutes and when you exit.

### Context-Aware Commands
When you add files to the context, they're automatically included in your messages. This is perfect for code reviews, debugging, or refactoring tasks.

### Quick Model Switching
Change models on the fly without restarting the session. Great for using different models for different types of questions.

### Session Persistence
All conversations are saved and can be resumed later. The REPL tracks your last conversation for easy resumption.

## Tips

1. **Use context files**: Add relevant code files with `/context add` before asking questions about them
2. **Save important conversations**: Use `/save` to export conversations for future reference
3. **Switch models for different tasks**: Use GPT-4 for complex reasoning, Codellama for code generation
4. **Multi-line code blocks**: Use `"""` for pasting code snippets or writing longer prompts

## Comparison with `conversation chat`

While `conversation chat` provides basic interactive mode, the new `repl` command offers:
- More intuitive command structure
- Better context management
- Model switching without restarting
- Auto-save functionality
- Integration with other RubberDuck commands
- Enhanced multi-line input support

The REPL mode is recommended for extended coding sessions and exploratory conversations with the AI assistant.