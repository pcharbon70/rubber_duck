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
	
	return m.renderBase()
}

// renderBase renders the base UI without overlays
func (m Model) renderBase() string {
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
	
	// Build chat content with header, status messages at top, conversation at bottom
	// Calculate heights for chat and status sections
	headerHeight := 3 // chat header takes 3 lines
	availableHeight := contentHeight - headerHeight - 2 // -2 for main borders
	
	// Status messages take 30% of available conversation area
	statusHeight := int(float64(availableHeight) * 0.3)
	if statusHeight < 5 {
		statusHeight = 5 // Minimum height
	}
	chatHeight := availableHeight - statusHeight - 2 // -2 for spacing between sections
	
	// Update component sizes
	m.statusMessages.SetSize(chatWidth-4, statusHeight-2) // -4 for borders, -2 for height borders
	// Update chat size to account for borders
	m.chat.SetSize(chatWidth-4, chatHeight-2) // -4 for borders, -2 for height borders
	
	// Create styles for rounded borders
	statusBorderStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("63")).
		Width(chatWidth - 2).
		Height(statusHeight).
		Padding(0, 1)
		
	chatBorderStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("62")).
		Width(chatWidth - 2).
		Height(chatHeight).
		Padding(0, 1)
	
	// Apply borders to sections
	statusSection := statusBorderStyle.Render(m.statusMessages.View())
	chatSection := chatBorderStyle.Render(m.chat.View())
	
	chatContent := lipgloss.JoinVertical(
		lipgloss.Left,
		m.chatHeader.View(),
		statusSection,
		chatSection,
	)
	
	chat := chatStyle.
		Width(chatWidth).
		Height(contentHeight).
		Render(chatContent)
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

// renderWithCommandPalette renders the UI with command palette overlay
func (m Model) renderWithCommandPalette() string {
	// Create command palette overlay
	paletteStyle := lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(lipgloss.Color("63")).
		Padding(1, 2).
		Width(60).
		MaxHeight(20).
		Background(lipgloss.Color("235"))
	
	palette := paletteStyle.Render(m.commandPalette.View())
	
	// Center the palette
	y := 5 // Near the top
	
	// Render base and overlay the palette
	_ = m.renderBase()
	
	// Create the full screen with palette centered
	overlay := lipgloss.Place(
		m.width, m.height,
		lipgloss.Center, lipgloss.Top,
		lipgloss.NewStyle().MarginTop(y).Render(palette),
	)
	
	// Simply return the overlay - it will appear on top of the terminal
	return overlay
}

// renderWithModal renders the UI with a modal overlay
func (m Model) renderWithModal() string {
	// Render base view
	base := m.renderBase()
	
	// TODO: Implement modal overlay
	return base
}

