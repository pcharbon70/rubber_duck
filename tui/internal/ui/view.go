package ui

import (
	"strings"
	
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
	
	// Use full height (no status bar)
	contentHeight := m.height
	
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
	chatHeight := availableHeight - statusHeight
	
	// Update component sizes - reduce status messages height to account for status bar
	m.statusMessages.SetSize(chatWidth-4, statusHeight-3) // -4 for borders, -3 for height borders and status bar
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
	
	// Create mini status bar for status messages area
	statusBar := m.renderMiniStatusBar(chatWidth - 2)
	
	// Combine status bar with status messages
	statusContent := lipgloss.JoinVertical(
		lipgloss.Left,
		statusBar,
		m.statusMessages.View(),
	)
	
	// Apply borders to sections
	statusSection := statusBorderStyle.Render(statusContent)
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
	
	// Join components horizontally and return (no status bar)
	return lipgloss.JoinHorizontal(lipgloss.Top, components...)
}

// renderMiniStatusBar renders a compact status bar for the status messages area
func (m Model) renderMiniStatusBar(width int) string {
	statusStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("240")).
		Background(lipgloss.Color("235")).
		Width(width).
		Padding(0, 1)
		
	// Connection indicator
	var connStatus string
	if m.connected {
		connStatus = lipgloss.NewStyle().
			Foreground(lipgloss.Color("46")).
			Bold(true).
			Render("● Connected")
	} else {
		connStatus = lipgloss.NewStyle().
			Foreground(lipgloss.Color("196")).
			Bold(true).
			Render("● Disconnected")
	}
	
	// Build status components
	var components []string
	components = append(components, connStatus)
	
	// Add authentication status
	if m.authenticated && m.username != "" {
		authStatus := lipgloss.NewStyle().
			Foreground(lipgloss.Color("46")).
			Bold(true).
			Render("● " + m.username)
		components = append(components, authStatus)
	} else {
		authStatus := lipgloss.NewStyle().
			Foreground(lipgloss.Color("196")).
			Bold(true).
			Render("● Not authenticated")
		components = append(components, authStatus)
	}
	
	// Add provider status
	if m.currentProvider != "" {
		providerStatus := lipgloss.NewStyle().
			Foreground(lipgloss.Color("46")).
			Bold(true).
			Render("● " + m.currentProvider)
		components = append(components, providerStatus)
	} else {
		providerStatus := lipgloss.NewStyle().
			Foreground(lipgloss.Color("196")).
			Bold(true).
			Render("● No provider")
		components = append(components, providerStatus)
	}
	
	// Add model status
	if m.currentModel != "" {
		modelStatus := lipgloss.NewStyle().
			Foreground(lipgloss.Color("46")).
			Bold(true).
			Render("● " + m.currentModel)
		components = append(components, modelStatus)
	} else {
		modelStatus := lipgloss.NewStyle().
			Foreground(lipgloss.Color("196")).
			Bold(true).
			Render("● No model")
		components = append(components, modelStatus)
	}
	
	// Join components with separator
	content := strings.Join(components, "  |  ")
	
	return statusStyle.Render(content)
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

