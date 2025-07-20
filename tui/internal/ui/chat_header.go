package ui

import (
	"fmt"
	"github.com/charmbracelet/lipgloss"
)

// ChatHeader represents the chat header component
type ChatHeader struct {
	width           int
	conversationID  string
	model          string
	provider       string
	messageCount   int
	tokenUsage     int
	tokenLimit     int
	connected      bool
	authenticated  bool
}

// NewChatHeader creates a new chat header
func NewChatHeader() *ChatHeader {
	return &ChatHeader{
		width:          80,
		conversationID: "lobby",
		model:          "default",
		provider:       "",
		messageCount:   0,
		tokenUsage:     0,
		tokenLimit:     4096,
		connected:      false,
		authenticated:  false,
	}
}

// View renders the chat header
func (h ChatHeader) View() string {
	// Define styles
	headerStyle := lipgloss.NewStyle().
		Border(lipgloss.NormalBorder(), false, false, true, false).
		BorderForeground(lipgloss.Color("240")).
		Padding(0, 1)

	// Connection indicator
	connIndicator := "○"
	connColor := "196" // red
	if h.connected && h.authenticated {
		connIndicator = "●"
		connColor = "46" // green
	} else if h.connected {
		connIndicator = "◐"
		connColor = "226" // yellow
	}
	
	connStatus := lipgloss.NewStyle().
		Foreground(lipgloss.Color(connColor)).
		Render(connIndicator)

	// Model info
	modelInfo := h.model
	if h.provider != "" {
		modelInfo = fmt.Sprintf("%s (%s)", h.model, h.provider)
	}

	// Token usage
	tokenInfo := fmt.Sprintf("%d/%d", h.tokenUsage, h.tokenLimit)
	tokenStyle := lipgloss.NewStyle()
	
	// Color code based on usage
	usagePercent := float64(h.tokenUsage) / float64(h.tokenLimit)
	if usagePercent > 0.9 {
		tokenStyle = tokenStyle.Foreground(lipgloss.Color("196")) // red
	} else if usagePercent > 0.7 {
		tokenStyle = tokenStyle.Foreground(lipgloss.Color("226")) // yellow
	} else {
		tokenStyle = tokenStyle.Foreground(lipgloss.Color("46")) // green
	}

	// Build header content
	leftContent := fmt.Sprintf("%s 💬 %s | Model: %s", 
		connStatus, 
		h.conversationID,
		modelInfo)
	
	rightContent := fmt.Sprintf("Tokens: %s | Messages: %d",
		tokenStyle.Render(tokenInfo),
		h.messageCount)

	// Calculate padding for right alignment
	leftWidth := lipgloss.Width(leftContent)
	rightWidth := lipgloss.Width(rightContent)
	padding := h.width - leftWidth - rightWidth - 4 // 4 for borders/padding
	
	if padding < 1 {
		padding = 1
	}

	spacer := lipgloss.NewStyle().Width(padding).Render(" ")
	fullContent := leftContent + spacer + rightContent

	return headerStyle.Width(h.width).Render(fullContent)
}

// Update methods

// SetSize updates the header width
func (h *ChatHeader) SetSize(width int) {
	h.width = width
}

// SetConversationID updates the conversation ID
func (h *ChatHeader) SetConversationID(id string) {
	if id == "" {
		h.conversationID = "lobby"
	} else {
		h.conversationID = id
	}
}

// SetModel updates the model and provider
func (h *ChatHeader) SetModel(model, provider string) {
	if model == "" {
		h.model = "default"
		h.provider = ""
	} else {
		h.model = model
		h.provider = provider
	}
}

// SetMessageCount updates the message count
func (h *ChatHeader) SetMessageCount(count int) {
	h.messageCount = count
}

// SetTokenUsage updates token usage
func (h *ChatHeader) SetTokenUsage(usage, limit int) {
	h.tokenUsage = usage
	h.tokenLimit = limit
}

// SetConnectionStatus updates connection status
func (h *ChatHeader) SetConnectionStatus(connected, authenticated bool) {
	h.connected = connected
	h.authenticated = authenticated
}

// GetModelInfo returns the current model and provider
func (h *ChatHeader) GetModelInfo() (string, string) {
	return h.model, h.provider
}