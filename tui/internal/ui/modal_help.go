package ui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

// HelpSection represents a section in the help modal
type HelpSection struct {
	Title    string
	Shortcuts []KeyboardShortcut
}

// KeyboardShortcut represents a keyboard shortcut
type KeyboardShortcut struct {
	Key         string
	Description string
}

// ShowHelp displays the help modal with all keyboard shortcuts
func (m *Modal) ShowHelp() {
	m.modalType = ModalHelp
	m.title = "🔑 Keyboard Shortcuts"
	m.visible = true
	m.hasInput = false
	m.selectedIndex = 0
	m.onResult = nil
	
	// Build help content
	m.content = buildHelpContent()
	
	m.buttons = []ModalButton{
		{
			Label:    "Close",
			Value:    "close",
			Shortcut: "esc",
			Primary:  true,
			Style:    lipgloss.NewStyle().Foreground(lipgloss.Color("62")),
		},
	}
}

// buildHelpContent creates the formatted help content
func buildHelpContent() string {
	sections := []HelpSection{
		{
			Title: "🌍 Global",
			Shortcuts: []KeyboardShortcut{
				{"Tab", "Switch between panes"},
				{"Ctrl+P", "Open command palette"},
				{"Ctrl+H", "Show this help"},
				{"Ctrl+C / q", "Quit application"},
				{"Ctrl+S", "Save current file"},
			},
		},
		{
			Title: "📁 File Tree",
			Shortcuts: []KeyboardShortcut{
				{"↑↓ / j k", "Navigate files"},
				{"Enter / Space", "Select file / Toggle directory"},
				{"h / ←", "Collapse directory / Go to parent"},
				{"l / →", "Expand directory"},
				{"g", "Go to top"},
				{"G", "Go to bottom"},
				{"Ctrl+N", "Create new file"},
				{"Ctrl+D", "Delete file (with confirmation)"},
			},
		},
		{
			Title: "✏️  Editor",
			Shortcuts: []KeyboardShortcut{
				{"Ctrl+S", "Save file"},
				{"Ctrl+Z", "Undo"},
				{"Ctrl+Y", "Redo"},
				{"Ctrl+F", "Find"},
				{"Ctrl+G", "Generate code"},
				{"Tab", "Accept completion"},
				{"Esc", "Cancel completion"},
			},
		},
		{
			Title: "📊 Output Pane",
			Shortcuts: []KeyboardShortcut{
				{"↑↓", "Scroll output"},
				{"Page Up/Down", "Scroll page"},
				{"Home", "Go to beginning"},
				{"End", "Go to end"},
				{"Ctrl+L", "Clear output"},
			},
		},
		{
			Title: "🎯 Commands",
			Shortcuts: []KeyboardShortcut{
				{"F1", "Analyze current file"},
				{"Shift+F1", "Analyze project"},
				{"F2", "Find issues"},
				{"Ctrl+G", "Generate code"},
				{"Ctrl+R", "Refactor code"},
				{"Ctrl+T", "Generate tests"},
			},
		},
		{
			Title: "💬 Chat/Analysis",
			Shortcuts: []KeyboardShortcut{
				{"Ctrl+Enter", "Send message"},
				{"Ctrl+K", "Clear chat history"},
				{"Ctrl+\\", "Toggle chat panel"},
			},
		},
	}
	
	// Format sections
	var content strings.Builder
	sectionStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("212")).
		Bold(true).
		MarginBottom(1)
	
	keyStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("228")).
		Bold(true).
		Width(20)
	
	descStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("252"))
	
	for i, section := range sections {
		if i > 0 {
			content.WriteString("\n")
		}
		
		// Section title
		content.WriteString(sectionStyle.Render(section.Title))
		content.WriteString("\n")
		
		// Shortcuts
		for _, shortcut := range section.Shortcuts {
			key := keyStyle.Render(shortcut.Key)
			desc := descStyle.Render(shortcut.Description)
			content.WriteString(fmt.Sprintf("%s %s\n", key, desc))
		}
	}
	
	// Add footer
	content.WriteString("\n")
	footerStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("240")).
		Italic(true)
	content.WriteString(footerStyle.Render("💡 Tip: Most commands also available via Command Palette (Ctrl+P)"))
	
	return content.String()
}