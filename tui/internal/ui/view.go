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
	
	// Use full height
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
	
	// Build chat content with status messages at top, conversation at bottom
	// Calculate heights for chat and status sections
	statusBarHeight := 1 // status bar takes 1 line
	// Account for outer container border (2 lines) and reduce by 2 more for visibility
	availableHeight := contentHeight - statusBarHeight - 5
	
	// Status messages take 10% of available conversation area
	statusHeight := int(float64(availableHeight) * 0.10)
	if statusHeight < 3 {
		statusHeight = 3 // Minimum height
	}
	chatHeight := availableHeight - statusHeight
	
	// Update component sizes
	m.statusMessages.SetSize(chatWidth-4, statusHeight) // -4 for horizontal padding
	// Update chat size
	m.chat.SetSize(chatWidth-4, chatHeight) // -4 for horizontal padding
	
	// Create styles for rounded borders
	statusBorderStyle := lipgloss.NewStyle().
		Width(chatWidth - 2).
		Padding(0, 1)
		
	chatBorderStyle := lipgloss.NewStyle().
		Width(chatWidth - 2).
		Padding(0, 1)
	
	// Create mini status bar as separate component
	statusBar := m.renderMiniStatusBar(chatWidth - 2)
	
	// Status messages content (without status bar)
	statusContent := m.statusMessages.View()
	
	// Apply borders to sections
	statusSection := statusBorderStyle.Render(statusContent)
	chatSection := chatBorderStyle.Render(m.chat.View())
	
	// Add separator between status bar and status messages
	separator := lipgloss.NewStyle().
		Width(chatWidth - 2).
		BorderStyle(lipgloss.NormalBorder()).
		BorderBottom(true).
		BorderForeground(lipgloss.Color("240")).
		Render("")
	
	// Add separator between status messages and chat
	chatSeparator := lipgloss.NewStyle().
		Width(chatWidth - 2).
		BorderStyle(lipgloss.NormalBorder()).
		BorderBottom(true).
		BorderForeground(lipgloss.Color("240")).
		Render("")
	
	chatContent := lipgloss.JoinVertical(
		lipgloss.Left,
		statusBar,        // Status bar at the top
		separator,        // Separator after status bar
		statusSection,
		chatSeparator,    // Separator between status and chat
		chatSection,
	)
	
	chat := chatStyle.
		Width(chatWidth).
		Height(contentHeight - 2).
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
	
	// Join components horizontally with top margin to ensure visibility
	content := lipgloss.JoinHorizontal(lipgloss.Top, components...)
	// Add top margin of 2 to push content down and make status bar visible
	return lipgloss.NewStyle().MarginTop(2).Render(content)
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
	
	// Add system message if present
	if m.systemMessage != "" {
		sysMsg := lipgloss.NewStyle().
			Foreground(lipgloss.Color("220")). // Yellow for visibility
			Bold(true).
			Render(m.systemMessage)
		components = append(components, sysMsg)
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

