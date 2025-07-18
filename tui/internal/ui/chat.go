package ui

import (
	"time"
	
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
)

// MessageType represents different types of chat messages
type MessageType int

const (
	UserMessage MessageType = iota
	AssistantMessage
	SystemMessage
	ErrorMessage
)

// ChatMessage represents a single message in the chat
type ChatMessage struct {
	Type      MessageType
	Content   string
	Author    string
	Timestamp time.Time
}

// Chat represents the chat component
type Chat struct {
	messages []ChatMessage
	viewport viewport.Model
	input    textarea.Model
	width    int
	height   int
	focused  bool
}

// NewChat creates a new chat component
func NewChat() *Chat {
	// Initialize viewport for message history
	vp := viewport.New(0, 0)
	
	// Initialize textarea for input
	ta := textarea.New()
	ta.Placeholder = "Type a message... (Enter to send, Ctrl+Enter for newline)"
	ta.ShowLineNumbers = false
	ta.SetHeight(3)
	ta.Focus()
	
	return &Chat{
		messages: []ChatMessage{},
		viewport: vp,
		input:    ta,
		width:    80,
		height:   24,
		focused:  true,
	}
}

// Init initializes the chat component
func (c Chat) Init() tea.Cmd {
	return nil
}

// Update handles chat updates
func (c Chat) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	// TODO: Implement chat update logic
	return c, nil
}

// View renders the chat component
func (c Chat) View() string {
	// TODO: Implement chat view
	return "Chat component (not yet implemented)"
}

// SetSize updates the chat component dimensions
func (c *Chat) SetSize(width, height int) {
	c.width = width
	c.height = height
	// Update viewport size (leaving room for input)
	c.viewport.Width = width
	c.viewport.Height = height - 5 // Leave room for input area
	c.input.SetWidth(width)
}

// Focus sets the focus state
func (c *Chat) Focus() {
	c.focused = true
	c.input.Focus()
}

// Blur removes focus
func (c *Chat) Blur() {
	c.focused = false
	c.input.Blur()
}

// AddMessage adds a message to the chat history
func (c *Chat) AddMessage(msgType MessageType, content, author string) {
	msg := ChatMessage{
		Type:      msgType,
		Content:   content,
		Author:    author,
		Timestamp: time.Now(),
	}
	c.messages = append(c.messages, msg)
	// TODO: Update viewport content
}