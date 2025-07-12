package ui

import (
	"strings"

	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/rubber_duck/tui/internal/commands"
)

// Command represents a command in the palette
type Command struct {
	Name        string
	Desc        string  // Renamed from Description to avoid conflict
	Shortcut    string
	Action      string
	Category    string
}

// Implement list.Item interface
func (c Command) FilterValue() string { return c.Name + " " + c.Desc }
func (c Command) Title() string       { return c.Name }
func (c Command) Description() string { return c.Desc }

// CommandPalette represents the command palette component
type CommandPalette struct {
	textInput    textinput.Model
	list         list.Model
	commands     []Command
	filtered     []list.Item
	visible      bool
	width        int
	height       int
	commandRouter *commands.CommandRouter
}

// NewCommandPalette creates a new command palette
func NewCommandPalette() CommandPalette {
	// Initialize command router
	router := commands.NewCommandRouter()
	registry := commands.NewCommandRegistry()
	localHandler := commands.NewLocalHandler()
	contextBuilder := commands.NewContextBuilder()
	unifiedClient := commands.NewUnifiedClient("ws://localhost:4000/socket/websocket")
	
	// Initialize router with dependencies
	router.SetRegistry(registry)
	router.SetLocalHandler(localHandler)
	router.SetContextBuilder(contextBuilder)
	router.SetUnifiedClient(unifiedClient)
	
	// Register server commands in registry
	registerServerCommands(registry)
	
	// Register local TUI commands in registry
	registerLocalCommands(registry)
	// Define available commands
	commands := []Command{
		// File operations
		{Name: "Open File", Desc: "Open a file in the editor", Shortcut: "Ctrl+O", Action: "open_file", Category: "File"},
		{Name: "Save File", Desc: "Save the current file", Shortcut: "Ctrl+S", Action: "save_file", Category: "File"},
		{Name: "New File", Desc: "Create a new file", Shortcut: "Ctrl+N", Action: "new_file", Category: "File"},
		{Name: "Close File", Desc: "Close the current file", Shortcut: "Ctrl+W", Action: "close_file", Category: "File"},
		
		// Analysis operations
		{Name: "Analyze File", Desc: "Run analysis on current file", Shortcut: "F1", Action: "analyze", Category: "Analysis"},
		{Name: "Analyze Project", Desc: "Run analysis on entire project", Shortcut: "Shift+F1", Action: "analyze_project", Category: "Analysis"},
		{Name: "Find Issues", Desc: "Find issues in current file", Shortcut: "F2", Action: "find_issues", Category: "Analysis"},
		
		// Code generation
		{Name: "Generate Code", Desc: "Generate code with AI", Shortcut: "Ctrl+G", Action: "generate", Category: "Generate"},
		{Name: "Complete Code", Desc: "Complete code at cursor", Shortcut: "Tab", Action: "complete", Category: "Generate"},
		{Name: "Refactor", Desc: "Refactor selected code", Shortcut: "Ctrl+R", Action: "refactor", Category: "Generate"},
		{Name: "Generate Tests", Desc: "Generate tests for current code", Shortcut: "Ctrl+T", Action: "generate_tests", Category: "Generate"},
		
		// UI operations
		{Name: "Toggle File Tree", Desc: "Show/hide file tree", Shortcut: "Ctrl+B", Action: "toggle_tree", Category: "UI"},
		{Name: "Toggle Output", Desc: "Show/hide output panel", Shortcut: "Ctrl+J", Action: "toggle_output", Category: "UI"},
		{Name: "Clear Output", Desc: "Clear output panel", Shortcut: "Ctrl+L", Action: "clear_output", Category: "UI"},
		{Name: "Toggle Theme", Desc: "Switch between light/dark theme", Shortcut: "Ctrl+Shift+T", Action: "toggle_theme", Category: "UI"},
		{Name: "Settings", Desc: "Open settings dialog", Shortcut: "Ctrl+,", Action: "settings", Category: "UI"},
		
		// Help
		{Name: "Show Help", Desc: "Display help information", Shortcut: "F1", Action: "help", Category: "Help"},
		{Name: "Show Shortcuts", Desc: "Display keyboard shortcuts", Shortcut: "?", Action: "shortcuts", Category: "Help"},
		
		// Performance
		{Name: "Performance Stats", Desc: "Show performance statistics", Shortcut: "", Action: "performance_stats", Category: "Debug"},
		{Name: "Clear Cache", Desc: "Clear view cache", Shortcut: "", Action: "clear_cache", Category: "Debug"},
	}

	// Create text input
	ti := textinput.New()
	ti.Placeholder = "Type a command..."
	ti.Focus()
	ti.CharLimit = 50
	ti.Width = 40

	// Convert commands to list items
	items := make([]list.Item, len(commands))
	for i, cmd := range commands {
		items[i] = cmd
	}

	// Create list
	delegate := list.NewDefaultDelegate()
	delegate.Styles.SelectedTitle = delegate.Styles.SelectedTitle.
		Foreground(lipgloss.Color("212")).
		BorderForeground(lipgloss.Color("62"))
	delegate.Styles.SelectedDesc = delegate.Styles.SelectedDesc.
		Foreground(lipgloss.Color("246"))

	l := list.New(items, delegate, 50, 10)
	l.Title = "Command Palette"
	l.SetShowStatusBar(false)
	l.SetFilteringEnabled(true)
	l.Styles.Title = lipgloss.NewStyle().
		Foreground(lipgloss.Color("62")).
		Bold(true)

	return CommandPalette{
		textInput:     ti,
		list:          l,
		commands:      commands,
		filtered:      items,
		visible:       false,
		commandRouter: router,
	}
}

// Update handles command palette updates
func (cp CommandPalette) Update(msg tea.Msg) (CommandPalette, tea.Cmd) {
	if !cp.visible {
		return cp, nil
	}

	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "esc", "ctrl+p":
			cp.visible = false
			return cp, nil
		case "enter":
			if selectedItem, ok := cp.list.SelectedItem().(Command); ok {
				cp.visible = false
				return cp, cp.executeCommand(selectedItem)
			}
		case "tab", "shift+tab":
			// Switch between input and list
			if cp.textInput.Focused() {
				cp.textInput.Blur()
			} else {
				cp.textInput.Focus()
			}
			return cp, nil
		}
	case tea.WindowSizeMsg:
		cp.width = msg.Width
		cp.height = msg.Height
		cp.updateSize()
		return cp, nil
	}

	// Update text input
	var cmd tea.Cmd
	prevValue := cp.textInput.Value()
	cp.textInput, cmd = cp.textInput.Update(msg)
	cmds = append(cmds, cmd)

	// Filter commands if input changed
	if cp.textInput.Value() != prevValue {
		cp.filterCommands()
	}

	// Update list
	cp.list, cmd = cp.list.Update(msg)
	cmds = append(cmds, cmd)

	return cp, tea.Batch(cmds...)
}

// View renders the command palette
func (cp CommandPalette) View() string {
	if !cp.visible {
		return ""
	}

	// Create dialog box
	dialogWidth := 60
	dialogHeight := 20
	if dialogWidth > cp.width-4 {
		dialogWidth = cp.width - 4
	}
	if dialogHeight > cp.height-4 {
		dialogHeight = cp.height - 4
	}

	dialogStyle := lipgloss.NewStyle().
		Width(dialogWidth).
		Height(dialogHeight).
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("62")).
		Background(lipgloss.Color("235")).
		Padding(1)

	// Build content
	var content strings.Builder
	content.WriteString(cp.textInput.View())
	content.WriteString("\n\n")
	content.WriteString(cp.list.View())

	dialog := dialogStyle.Render(content.String())

	// Center the dialog
	return lipgloss.Place(
		cp.width,
		cp.height,
		lipgloss.Center,
		lipgloss.Center,
		dialog,
	)
}

// Show displays the command palette
func (cp *CommandPalette) Show() {
	cp.visible = true
	cp.textInput.Focus()
	cp.textInput.SetValue("")
	cp.filterCommands()
}

// Hide hides the command palette
func (cp *CommandPalette) Hide() {
	cp.visible = false
}

// IsVisible returns whether the palette is visible
func (cp CommandPalette) IsVisible() bool {
	return cp.visible
}

// GetCommandRouter returns the command router for external use
func (cp CommandPalette) GetCommandRouter() *commands.CommandRouter {
	return cp.commandRouter
}

// ExecuteCommandDirectly allows external components to execute commands through the router
func (cp *CommandPalette) ExecuteCommandDirectly(commandName string, args map[string]interface{}, tuiContext interface{}) tea.Cmd {
	if cp.commandRouter == nil {
		return nil
	}
	return cp.commandRouter.ExecuteCommand(commandName, args, tuiContext)
}

// filterCommands filters the command list based on input
func (cp *CommandPalette) filterCommands() {
	query := strings.ToLower(cp.textInput.Value())
	
	if query == "" {
		// Show all commands
		items := make([]list.Item, len(cp.commands))
		for i, cmd := range cp.commands {
			items[i] = cmd
		}
		cp.list.SetItems(items)
		return
	}

	// Fuzzy filter
	var filtered []list.Item
	for _, cmd := range cp.commands {
		cmdLower := strings.ToLower(cmd.Name + " " + cmd.Desc + " " + cmd.Category)
		if fuzzyMatch(query, cmdLower) {
			filtered = append(filtered, cmd)
		}
	}

	cp.list.SetItems(filtered)
}

// fuzzyMatch performs a simple fuzzy string match
func fuzzyMatch(query, target string) bool {
	if query == "" {
		return true
	}

	qIndex := 0
	for _, char := range target {
		if qIndex < len(query) && char == rune(query[qIndex]) {
			qIndex++
			if qIndex == len(query) {
				return true
			}
		}
	}
	return false
}

// updateSize updates component sizes based on terminal size
func (cp *CommandPalette) updateSize() {
	if cp.width > 60 {
		cp.list.SetWidth(56)
		cp.textInput.Width = 56
	} else {
		cp.list.SetWidth(cp.width - 4)
		cp.textInput.Width = cp.width - 4
	}

	if cp.height > 20 {
		cp.list.SetHeight(16)
	} else {
		cp.list.SetHeight(cp.height - 4)
	}
}

// executeCommand creates a command to execute the selected command using the new router
func (cp *CommandPalette) executeCommand(cmd Command) tea.Cmd {
	return func() tea.Msg {
		// Create a simple TUI context for command execution
		tuiContext := commands.TUIContext{
			CurrentFile:   getCurrentFile(),
			EditorContent: getEditorContent(),
			Language:      detectLanguageFromFile(getCurrentFile()),
			CursorLine:    getCursorLine(),
			CursorColumn:  getCursorColumn(),
			Metadata:      make(map[string]interface{}),
		}
		
		// Convert legacy command args format to map
		args := make(map[string]interface{})
		if cmd.Category != "" {
			args["category"] = cmd.Category
		}
		
		// Execute command through router
		return cp.commandRouter.ExecuteCommand(cmd.Action, args, tuiContext)
	}
}

// Helper functions to extract TUI state - these would be implemented based on actual model structure
func getCurrentFile() string {
	// In a real implementation, this would access the current model state
	return ""
}

func getEditorContent() string {
	// In a real implementation, this would access the editor content
	return ""
}

func detectLanguageFromFile(filename string) string {
	// Simple language detection based on file extension
	if strings.HasSuffix(filename, ".go") {
		return "go"
	}
	if strings.HasSuffix(filename, ".js") {
		return "javascript"
	}
	if strings.HasSuffix(filename, ".py") {
		return "python"
	}
	if strings.HasSuffix(filename, ".ex") || strings.HasSuffix(filename, ".exs") {
		return "elixir"
	}
	return "text"
}

func getCursorLine() int {
	// In a real implementation, this would access the cursor position
	return 1
}

func getCursorColumn() int {
	// In a real implementation, this would access the cursor position
	return 1
}

// registerServerCommands registers server-side commands in the registry
func registerServerCommands(registry *commands.CommandRegistry) {
	// Analysis commands - these run on the server
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "analyze",
		Description: "Analyze current file for issues",
		Category:    "Analysis",
		Type:        commands.ServerCommand,
		Args: []commands.ArgDef{
			{Name: "file", Type: "file", Required: false, Description: "File to analyze"},
		},
		Options: []commands.OptDef{
			{Name: "deep", Type: "bool", Default: false, Description: "Perform deep analysis"},
		},
	})
	
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "analyze_project",
		Description: "Analyze entire project",
		Category:    "Analysis",
		Type:        commands.ServerCommand,
	})
	
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "find_issues",
		Description: "Find issues in current file",
		Category:    "Analysis",
		Type:        commands.ServerCommand,
	})
	
	// Code generation commands - these run on the server
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "generate",
		Description: "Generate code with AI",
		Category:    "Generate",
		Type:        commands.ServerCommand,
		Args: []commands.ArgDef{
			{Name: "prompt", Type: "string", Required: true, Description: "Generation prompt"},
		},
		Options: []commands.OptDef{
			{Name: "language", Type: "string", Default: "go", Description: "Target language"},
		},
	})
	
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "complete",
		Description: "Complete code at cursor",
		Category:    "Generate",
		Type:        commands.ServerCommand,
	})
	
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "refactor",
		Description: "Refactor selected code",
		Category:    "Generate",
		Type:        commands.ServerCommand,
	})
	
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "generate_tests",
		Description: "Generate tests for current code",
		Category:    "Generate",
		Type:        commands.ServerCommand,
	})
}

// registerLocalCommands registers local TUI commands in the registry
func registerLocalCommands(registry *commands.CommandRegistry) {
	// File operations - these are local TUI operations
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "open_file",
		Description: "Open a file in the editor",
		Category:    "File",
		Type:        commands.LocalCommand,
		LocalOnly:   true,
	})
	
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "save_file",
		Description: "Save the current file",
		Category:    "File",
		Type:        commands.LocalCommand,
		LocalOnly:   true,
	})
	
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "new_file",
		Description: "Create a new file",
		Category:    "File",
		Type:        commands.LocalCommand,
		LocalOnly:   true,
	})
	
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "close_file",
		Description: "Close the current file",
		Category:    "File",
		Type:        commands.LocalCommand,
		LocalOnly:   true,
	})
	
	// UI operations - these are local to the TUI
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "toggle_tree",
		Description: "Toggle file tree visibility",
		Category:    "UI",
		Type:        commands.LocalCommand,
		LocalOnly:   true,
	})
	
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "toggle_output",
		Description: "Toggle output panel visibility",
		Category:    "UI",
		Type:        commands.LocalCommand,
		LocalOnly:   true,
	})
	
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "clear_output",
		Description: "Clear output panel",
		Category:    "UI",
		Type:        commands.LocalCommand,
		LocalOnly:   true,
	})
	
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "toggle_theme",
		Description: "Toggle between light/dark theme",
		Category:    "UI",
		Type:        commands.LocalCommand,
		LocalOnly:   true,
	})
	
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "settings",
		Description: "Open settings dialog",
		Category:    "UI",
		Type:        commands.LocalCommand,
		LocalOnly:   true,
	})
	
	// Help commands - these are local
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "help",
		Description: "Display help information",
		Category:    "Help",
		Type:        commands.LocalCommand,
		LocalOnly:   true,
	})
	
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "shortcuts",
		Description: "Display keyboard shortcuts",
		Category:    "Help",
		Type:        commands.LocalCommand,
		LocalOnly:   true,
	})
	
	// Debug commands - these are local
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "performance_stats",
		Description: "Show performance statistics",
		Category:    "Debug",
		Type:        commands.LocalCommand,
		LocalOnly:   true,
	})
	
	registry.RegisterCommand(commands.CommandDefinition{
		Name:        "clear_cache",
		Description: "Clear view cache",
		Category:    "Debug",
		Type:        commands.LocalCommand,
		LocalOnly:   true,
	})
}