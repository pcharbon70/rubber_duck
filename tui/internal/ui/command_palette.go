package ui

import (
	"strings"
	
	tea "github.com/charmbracelet/bubbletea"
)

// Command represents a command in the palette
type Command struct {
	Name        string
	Description string
	Shortcut    string
	Action      string
}

// CommandPalette represents the command palette component
type CommandPalette struct {
	commands []Command
	filtered []Command
	selected int
	visible  bool
	filter   string
}

// NewCommandPalette creates a new command palette
func NewCommandPalette() CommandPalette {
	commands := []Command{
		{Name: "New File", Description: "Create a new file", Shortcut: "Ctrl+N", Action: "new_file"},
		{Name: "Open File", Description: "Open an existing file", Shortcut: "Ctrl+O", Action: "open_file"},
		{Name: "Save File", Description: "Save the current file", Shortcut: "Ctrl+S", Action: "save_file"},
		{Name: "Toggle File Tree", Description: "Show/hide file tree", Shortcut: "Ctrl+F", Action: "toggle_tree"},
		{Name: "Toggle Editor", Description: "Show/hide editor", Shortcut: "Ctrl+E", Action: "toggle_editor"},
		{Name: "Focus Chat", Description: "Focus on chat input", Shortcut: "Ctrl+/", Action: "focus_chat"},
		{Name: "New Conversation", Description: "Start a new conversation", Shortcut: "Ctrl+Shift+N", Action: "new_conversation"},
		{Name: "Settings", Description: "Open settings", Shortcut: "Ctrl+,", Action: "settings"},
		{Name: "Help", Description: "Show help", Shortcut: "Ctrl+H", Action: "help"},
		// Model selection commands
		{Name: "Model: Default", Description: "Use system default model", Shortcut: "", Action: "model_default"},
		{Name: "Model: GPT-4", Description: "Use OpenAI GPT-4", Shortcut: "", Action: "model_gpt4"},
		{Name: "Model: GPT-3.5 Turbo", Description: "Use OpenAI GPT-3.5 Turbo", Shortcut: "", Action: "model_gpt35"},
		{Name: "Model: Claude 3 Opus", Description: "Use Anthropic Claude 3 Opus", Shortcut: "", Action: "model_claude_opus"},
		{Name: "Model: Claude 3 Sonnet", Description: "Use Anthropic Claude 3 Sonnet", Shortcut: "", Action: "model_claude_sonnet"},
		{Name: "Model: Llama 2", Description: "Use Ollama Llama 2 (local)", Shortcut: "", Action: "model_llama2"},
		{Name: "Model: Mistral", Description: "Use Ollama Mistral (local)", Shortcut: "", Action: "model_mistral"},
		{Name: "Model: CodeLlama", Description: "Use Ollama CodeLlama (local)", Shortcut: "", Action: "model_codellama"},
		// Provider commands
		{Name: "Provider: Set Custom", Description: "Set a custom provider", Shortcut: "", Action: "set_provider_prompt"},
		// Authentication commands
		{Name: "Auth: Check Status", Description: "Check authentication status", Shortcut: "", Action: "auth_status"},
		{Name: "Auth: Logout", Description: "Logout from server", Shortcut: "", Action: "auth_logout"},
		{Name: "Auth: Generate API Key", Description: "Generate new API key", Shortcut: "", Action: "auth_apikey_generate"},
		{Name: "Auth: List API Keys", Description: "List all API keys", Shortcut: "", Action: "auth_apikey_list"},
	}
	
	return CommandPalette{
		commands: commands,
		filtered: commands,
		visible:  false,
	}
}

// Update handles command palette updates
func (cp CommandPalette) Update(msg tea.Msg) (CommandPalette, tea.Cmd) {
	if !cp.visible {
		return cp, nil
	}

	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "up", "k":
			if cp.selected > 0 {
				cp.selected--
			}
		case "down", "j":
			if cp.selected < len(cp.filtered)-1 {
				cp.selected++
			}
		case "enter":
			// Execute selected command
			if cp.selected < len(cp.filtered) {
				cmd := cp.filtered[cp.selected]
				cp.Hide()
				return cp, func() tea.Msg {
					return ExecuteCommandMsg{
						Command: cmd.Action,
						Args:    nil,
					}
				}
			}
		case "esc":
			cp.Hide()
		}
	}
	return cp, nil
}

// View renders the command palette
func (cp CommandPalette) View() string {
	if !cp.visible {
		return ""
	}
	
	// Build the command list
	var items []string
	for i, cmd := range cp.filtered {
		prefix := "  "
		if i == cp.selected {
			prefix = "> "
		}
		
		line := prefix + cmd.Name
		if cmd.Shortcut != "" {
			line += " (" + cmd.Shortcut + ")"
		}
		line += " - " + cmd.Description
		items = append(items, line)
	}
	
	// Join all items
	content := strings.Join(items, "\n")
	
	// Add instructions
	instructions := "↑/↓ or j/k: Navigate | Enter: Execute | Esc: Cancel"
	
	return content + "\n\n" + instructions
}

// IsVisible returns whether the command palette is visible
func (cp CommandPalette) IsVisible() bool {
	return cp.visible
}

// Show displays the command palette
func (cp *CommandPalette) Show() {
	cp.visible = true
}

// Hide hides the command palette
func (cp *CommandPalette) Hide() {
	cp.visible = false
}