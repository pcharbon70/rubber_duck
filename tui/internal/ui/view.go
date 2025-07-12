package ui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

// Styles
var (
	// Border styles
	activeStyle = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("62"))

	inactiveStyle = lipgloss.NewStyle().
			Border(lipgloss.NormalBorder()).
			BorderForeground(lipgloss.Color("240"))

	// Status bar style
	statusBarStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("240")).
			Background(lipgloss.Color("235"))

	// File tree styles
	selectedFileStyle = lipgloss.NewStyle().
				Foreground(lipgloss.Color("212")).
				Background(lipgloss.Color("236"))

	dirStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("33"))

	fileStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("252"))
)

// View renders the entire UI
func (m Model) View() string {
	if m.width == 0 || m.height == 0 {
		return "Loading..."
	}

	// Calculate dimensions
	sidebarWidth := 30
	outputWidth := 40
	editorWidth := m.width - sidebarWidth - outputWidth - 6 // borders
	contentHeight := m.height - 3                            // status bar

	// Build panes
	fileTree := m.renderFileTree(sidebarWidth, contentHeight)
	editor := m.renderEditor(editorWidth, contentHeight)
	output := m.renderOutput(outputWidth, contentHeight)

	// Combine horizontally
	main := lipgloss.JoinHorizontal(
		lipgloss.Top,
		fileTree,
		editor,
		output,
	)

	// Add status bar
	statusBar := m.renderStatusBar()

	// Combine main UI
	ui := lipgloss.JoinVertical(
		lipgloss.Left,
		main,
		statusBar,
	)

	// Overlay command palette if visible
	if m.commandPalette.IsVisible() {
		return m.commandPalette.View()
	}
	
	// Overlay modal if visible
	if m.modal.IsVisible() {
		return m.modal.View()
	}
	
	// Overlay settings modal if visible
	if m.settingsModal.IsVisible() {
		return m.settingsModal.View()
	}

	return ui
}

// renderFileTree renders the file tree pane
func (m Model) renderFileTree(width, height int) string {
	style := inactiveStyle
	if m.activePane == FileTreePane {
		style = activeStyle
	}

	content := m.buildFileTreeContent()

	return style.
		Width(width).
		Height(height).
		Render(content)
}

// buildFileTreeContent builds the file tree content
func (m Model) buildFileTreeContent() string {
	// Update file tree size
	m.fileTree.width = 28  // Account for borders
	m.fileTree.height = m.height - 5  // Account for borders and status
	
	content := m.fileTree.View()
	if content == "" || content == "No files loaded" {
		return " 📁 RubberDuck Project\n ──────────────────────\n\n No files loaded\n\n Press Ctrl+O to open\n a project"
	}
	
	return " 📁 RubberDuck Project\n ──────────────────────\n" + content
}

// renderEditor renders the editor pane
func (m Model) renderEditor(width, height int) string {
	style := inactiveStyle
	if m.activePane == EditorPane {
		style = activeStyle
	}

	// Add title to editor
	title := " Editor"
	if m.editor.Value() != "" {
		title = " Editor - main.go" // TODO: Show actual filename
	}

	editorView := m.editor.View()

	return style.
		Width(width).
		Height(height).
		Render(title + "\n" + editorView)
}

// renderOutput renders the output pane
func (m Model) renderOutput(width, height int) string {
	style := inactiveStyle
	if m.activePane == OutputPane {
		style = activeStyle
	}

	title := " Output"
	if m.analyzing {
		title = " Output (Analyzing...)"
	}

	outputView := m.output.View()

	return style.
		Width(width).
		Height(height).
		Render(title + "\n" + outputView)
}

// renderStatusBar renders the status bar
func (m Model) renderStatusBar() string {
	width := m.width

	// Connection indicator
	connStatus := "⚡"
	if !m.connected {
		connStatus = "⚠️ "
	}

	// Build status text
	status := fmt.Sprintf(" %s %s", connStatus, m.statusBar)

	// Pad to full width
	padding := width - lipgloss.Width(status)
	if padding > 0 {
		status += strings.Repeat(" ", padding)
	}

	return statusBarStyle.Render(status)
}