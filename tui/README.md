# RubberDuck TUI

A modern terminal user interface for the RubberDuck AI coding assistant, built with Go and Bubble Tea.

## Features

- **Split-pane interface**: File tree, code editor, and output pane
- **Phoenix WebSocket integration**: Real-time communication with the RubberDuck server
- **Command palette**: Quick access to all commands (Ctrl+P)
- **Vim-style navigation**: Use j/k or arrow keys
- **Syntax highlighting**: Language-aware code display
- **Real-time analysis**: Stream results as they're generated

## Prerequisites

- Go 1.19 or later
- RubberDuck Phoenix server running on port 5555
- API key (set via `RUBBER_DUCK_API_KEY` environment variable)

## Building

```bash
cd tui
go build ./cmd/rubber_duck_tui
```

## Running

```bash
# Set your API key (optional if server allows anonymous access)
export RUBBER_DUCK_API_KEY=your_api_key_here

# Run the TUI
./rubber_duck_tui
```

## Keyboard Shortcuts

### Global
- `Tab`: Switch between panes
- `Ctrl+P`: Open command palette
- `Ctrl+H`: Show help
- `Ctrl+C` or `q`: Quit

### File Tree Pane
- `↑↓` or `j/k`: Navigate files
- `Enter` or `Space`: Select file or toggle directory
- `h` or `←`: Collapse directory or go to parent
- `l` or `→`: Expand directory
- `g`: Go to top
- `G`: Go to bottom

### Editor Pane
- Standard text editing
- `Ctrl+S`: Save file (when connected)

### Output Pane
- `↑↓`: Scroll output

### Command Palette
- Type to filter commands
- `Enter`: Execute selected command
- `Esc` or `Ctrl+P`: Close palette

## Architecture

The TUI follows the Elm Architecture pattern using Bubble Tea:

- **Model**: Application state including file tree, editor content, and connection status
- **Update**: Handles all state transitions based on messages
- **View**: Renders the UI using Lipgloss for styling

### Components

1. **File Tree** (`filetree.go`): Hierarchical file browser with expand/collapse
2. **Editor** (uses Bubbles textarea): Code editing with syntax highlighting
3. **Output Pane** (uses Bubbles viewport): Scrollable output display
4. **Command Palette** (`command_palette.go`): Fuzzy-searchable command list
5. **Phoenix Client** (`phoenix/client.go`): WebSocket communication layer

### Phoenix Integration

The TUI connects to the RubberDuck Phoenix server via WebSocket:
- Endpoint: `ws://localhost:5555/socket`
- Channel: `cli:commands`
- Authentication: API key via query parameter

Supported operations:
- File listing and loading
- Code analysis
- Code generation with streaming
- Completions
- Refactoring

## Development

### Adding New Commands

1. Add the command to the `commands` slice in `command_palette.go`
2. Handle the command execution in `update.go` under `ExecuteCommandMsg`
3. Implement the Phoenix channel push in the appropriate handler

### Extending the UI

1. Create new component files following the pattern of existing components
2. Add the component to the Model struct
3. Update the View method to render the component
4. Handle component updates in the Update method

## Troubleshooting

### Connection Issues
- Ensure the Phoenix server is running on port 5555
- Check that your API key is valid
- Look for connection errors in the status bar

### Display Issues
- The TUI requires a terminal with at least 80x24 characters
- Use a terminal that supports Unicode for proper icons
- Try different terminal emulators if rendering is incorrect