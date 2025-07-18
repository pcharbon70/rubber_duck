package ui

import (
	"github.com/charmbracelet/lipgloss"
)

// View renders the entire UI
func (m Model) View() string {
	if m.width == 0 || m.height == 0 {
		return "Loading..."
	}
	
	// Check if modal is visible
	if m.modal.IsVisible() {
		return m.renderWithModal()
	}
	
	// Check if command palette is visible
	if m.commandPalette.IsVisible() {
		return m.renderWithCommandPalette()
	}
	
	// Define styles
	borderStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("240"))
		
	activeBorderStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("62"))
	
	// Calculate content height (minus status bar)
	contentHeight := m.height - 1
	
	// Build the layout based on visible components
	var components []string
	
	// File tree (if visible)
	if m.showFileTree {
		style := borderStyle
		if m.activePane == FileTreePane {
			style = activeBorderStyle
		}
		fileTree := style.
			Width(30).
			Height(contentHeight).
			Render(m.fileTree.View())
		components = append(components, fileTree)
	}
	
	// Chat (always visible - primary interface)
	chatStyle := borderStyle
	if m.activePane == ChatPane {
		chatStyle = activeBorderStyle
	}
	
	// Calculate chat width based on visible panels
	chatWidth := m.width
	if m.showFileTree {
		chatWidth -= 32 // 30 + 2 for borders
	}
	if m.showEditor {
		chatWidth -= 42 // 40 + 2 for borders
	}
	
	chat := chatStyle.
		Width(chatWidth).
		Height(contentHeight).
		Render(m.chat.View())
	components = append(components, chat)
	
	// Editor (if visible)
	if m.showEditor {
		style := borderStyle
		if m.activePane == EditorPane {
			style = activeBorderStyle
		}
		editor := style.
			Width(40).
			Height(contentHeight).
			Render(m.editor.View())
		components = append(components, editor)
	}
	
	// Join components horizontally
	main := lipgloss.JoinHorizontal(lipgloss.Top, components...)
	
	// Add status bar
	statusBar := m.renderStatusBar()
	
	// Join vertically
	return lipgloss.JoinVertical(lipgloss.Left, main, statusBar)
}

// renderStatusBar renders the status bar
func (m Model) renderStatusBar() string {
	statusStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("240")).
		Background(lipgloss.Color("235")).
		Width(m.width).
		Padding(0, 1)
		
	// Connection indicator
	connStatus := "●"
	if m.connected {
		connStatus = lipgloss.NewStyle().Foreground(lipgloss.Color("46")).Render("●")
	} else {
		connStatus = lipgloss.NewStyle().Foreground(lipgloss.Color("196")).Render("●")
	}
	
	status := connStatus + " " + m.statusBar
	return statusStyle.Render(status)
}

// renderWithModal renders the UI with a modal overlay
func (m Model) renderWithModal() string {
	// Render base view
	base := m.View()
	
	// TODO: Implement modal overlay
	return base
}

// renderWithCommandPalette renders the UI with command palette overlay
func (m Model) renderWithCommandPalette() string {
	// Render base view
	base := m.View()
	
	// TODO: Implement command palette overlay
	return base
}