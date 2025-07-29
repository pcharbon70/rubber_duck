package phoenix

import (
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// PhoenixClient defines the interface for Phoenix WebSocket communication
type PhoenixClient interface {
	// SetProgram sets the tea.Program for sending messages
	SetProgram(program *tea.Program)
	
	// Connect establishes a WebSocket connection
	Connect(config Config) tea.Cmd
	
	// JoinChannel joins a Phoenix channel
	JoinChannel(topic string) tea.Cmd
	
	// Push sends a message to the channel
	Push(event string, payload map[string]any) tea.Cmd
	
	// SendMessage sends a chat message
	SendMessage(content string) tea.Cmd
	
	// StartNewConversation starts a new conversation
	StartNewConversation() tea.Cmd
	
	// Disconnect closes the connection
	Disconnect() tea.Cmd
	
	// Reconnect attempts to reconnect after a delay
	Reconnect(config Config, delay time.Duration) tea.Cmd
}