package ui

import (
	"strings"

	"github.com/charmbracelet/bubbles/list"
	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
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
	textInput textinput.Model
	list      list.Model
	commands  []Command
	filtered  []list.Item
	visible   bool
	width     int
	height    int
}

// NewCommandPalette creates a new command palette
func NewCommandPalette() CommandPalette {
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
		textInput: ti,
		list:      l,
		commands:  commands,
		filtered:  items,
		visible:   false,
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
				return cp, executeCommand(selectedItem)
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

// executeCommand creates a command to execute the selected command
func executeCommand(cmd Command) tea.Cmd {
	return func() tea.Msg {
		return ExecuteCommandMsg{
			Command: cmd.Action,
			Args:    []string{},
		}
	}
}