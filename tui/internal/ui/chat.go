package ui

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
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
	theme    *Theme
}

// NewChat creates a new chat component
func NewChat() *Chat {
	// Initialize viewport
	vp := viewport.New(80, 20)
	vp.SetContent("")

	// Initialize input textarea
	ta := textarea.New()
	ta.Placeholder = "Type a message... (Enter to send, Ctrl+Enter for newline)"
	ta.ShowLineNumbers = false
	ta.SetHeight(3)
	ta.SetWidth(80)
	ta.CharLimit = 0 // No limit
	ta.Focus()

	return &Chat{
		messages: make([]ChatMessage, 0),
		viewport: vp,
		input:    ta,
		width:    80,
		height:   24,
		focused:  false,
	}
}

// Init initializes the chat component
func (c Chat) Init() tea.Cmd {
	return nil
}

// Update handles chat updates
func (c Chat) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var (
		vpCmd    tea.Cmd
		inputCmd tea.Cmd
		cmds     []tea.Cmd
	)

	// Handle keyboard input when focused
	if c.focused {
		switch msg := msg.(type) {
		case tea.KeyMsg:
			switch msg.Type {
			case tea.KeyEnter:
				// Send message if we have content
				if content := strings.TrimSpace(c.input.Value()); content != "" {
					// Clear the input
					c.input.SetValue("")
					c.input.Reset()
					
					// Add user message to history
					c.AddMessage(UserMessage, content, "user")
					
					// Return command to send message
					return c, func() tea.Msg {
						return ChatMessageSentMsg{
							Content: content,
						}
					}
				}
				return c, nil
			
			case tea.KeyCtrlC:
				// Let ctrl+c bubble up for quit handling
				return c, nil
				
			default:
				// Handle multiline with Ctrl+Enter (represented as Ctrl+J in some terminals)
				if msg.Type == tea.KeyCtrlJ {
					// Insert newline
					current := c.input.Value()
					c.input.SetValue(current + "\n")
				}
			}
		}
	}

	// Update input if focused
	if c.focused {
		c.input, inputCmd = c.input.Update(msg)
		cmds = append(cmds, inputCmd)
	}

	// Always update viewport for scrolling
	c.viewport, vpCmd = c.viewport.Update(msg)
	cmds = append(cmds, vpCmd)

	return c, tea.Batch(cmds...)
}

// View renders the chat component
func (c Chat) View() string {
	if c.width == 0 || c.height == 0 {
		return ""
	}

	// Update viewport content
	c.viewport.SetContent(c.buildViewportContent())

	// Get styles
	theme := c.getTheme()
	
	// Chat container style
	chatStyle := lipgloss.NewStyle().
		Width(c.width).
		Height(c.height).
		Border(lipgloss.RoundedBorder()).
		BorderForeground(theme.Border)

	if c.focused {
		chatStyle = chatStyle.BorderForeground(theme.Selection)
	}

	// Build the view
	content := lipgloss.JoinVertical(
		lipgloss.Left,
		c.viewport.View(),
		lipgloss.NewStyle().
			Width(c.width-2).
			Border(lipgloss.NormalBorder(), true, false, false, false).
			BorderForeground(theme.Border).
			Render(c.input.View()),
	)

	return chatStyle.Render(content)
}

// SetSize updates the chat dimensions
func (c *Chat) SetSize(width, height int) {
	c.width = width
	c.height = height
	
	// Update viewport size (leave room for input and borders)
	viewportHeight := height - 5 // 3 for input + 2 for borders
	if viewportHeight < 1 {
		viewportHeight = 1
	}
	c.viewport.Width = width - 2  // Account for borders
	c.viewport.Height = viewportHeight
	
	// Update input width
	c.input.SetWidth(width - 2)
}

// Focus sets focus on the chat input
func (c *Chat) Focus() {
	c.focused = true
	c.input.Focus()
}

// Blur removes focus from the chat input
func (c *Chat) Blur() {
	c.focused = false
	c.input.Blur()
}

// IsFocused returns whether the chat is focused
func (c Chat) IsFocused() bool {
	return c.focused
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
	
	// Update viewport content and scroll to bottom
	c.viewport.SetContent(c.buildViewportContent())
	c.viewport.GotoBottom()
}

// ClearMessages clears all messages from the chat
func (c *Chat) ClearMessages() {
	c.messages = []ChatMessage{}
	c.viewport.SetContent("")
}

// SetTheme sets the theme for styling
func (c *Chat) SetTheme(theme *Theme) {
	c.theme = theme
}

// buildViewportContent builds the formatted message history
func (c Chat) buildViewportContent() string {
	if len(c.messages) == 0 {
		return lipgloss.NewStyle().
			Foreground(lipgloss.Color("240")).
			Italic(true).
			Render("No messages yet. Type a message and press Enter to send.")
	}

	theme := c.getTheme()
	var lines []string
	
	for _, msg := range c.messages {
		lines = append(lines, c.formatMessage(msg, theme))
	}
	
	return strings.Join(lines, "\n\n")
}

// formatMessage formats a single message based on its type
func (c Chat) formatMessage(msg ChatMessage, theme *Theme) string {
	timestamp := msg.Timestamp.Format("15:04:05")
	
	// Style based on message type
	var (
		authorStyle  lipgloss.Style
		contentStyle lipgloss.Style
		prefix       string
	)
	
	switch msg.Type {
	case UserMessage:
		prefix = "You"
		authorStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(theme.KeywordType)
		contentStyle = lipgloss.NewStyle().
			Foreground(theme.Text)
			
	case AssistantMessage:
		prefix = "Assistant"
		authorStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(theme.Function)
		contentStyle = lipgloss.NewStyle().
			Foreground(theme.Text)
			
	case SystemMessage:
		prefix = "System"
		authorStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(theme.Comment)
		contentStyle = lipgloss.NewStyle().
			Foreground(theme.Comment).
			Italic(true)
			
	case ErrorMessage:
		prefix = "Error"
		authorStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(theme.ErrorText)
		contentStyle = lipgloss.NewStyle().
			Foreground(theme.ErrorText)
	}
	
	// Build the message
	header := fmt.Sprintf("%s %s [%s]", 
		authorStyle.Render(prefix),
		lipgloss.NewStyle().Foreground(theme.Comment).Render("•"),
		lipgloss.NewStyle().Foreground(theme.Comment).Render(timestamp),
	)
	
	// Format content with proper indentation for multiline
	lines := strings.Split(msg.Content, "\n")
	formattedLines := make([]string, len(lines))
	for i, line := range lines {
		formattedLines[i] = contentStyle.Render(line)
	}
	
	return header + "\n" + strings.Join(formattedLines, "\n")
}

// getTheme returns the current theme or a default
func (c Chat) getTheme() *Theme {
	if c.theme != nil {
		return c.theme
	}
	// Return default dark theme
	return GetTheme("dark")
}

// GetMessages returns the chat messages (for testing or external access)
func (c Chat) GetMessages() []ChatMessage {
	return c.messages
}