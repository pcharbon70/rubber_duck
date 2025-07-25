package ui

import (
	"fmt"
	"strings"
	"time"
	
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/glamour"
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
	renderer *glamour.TermRenderer
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
	
	chat := &Chat{
		messages: []ChatMessage{},
		viewport: vp,
		input:    ta,
		width:    80,
		height:   24,
		focused:  true,
		renderer: nil, // Defer renderer creation
	}
	
	// No welcome message - keep chat clean on startup
	
	// Set initial viewport content
	chat.viewport.SetContent(chat.buildViewportContent())
	
	return chat
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
					
					// Check for slash commands
					if strings.HasPrefix(content, "/") {
						return c, c.handleSlashCommand(content)
					}
					
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

	// Update viewport
	c.viewport, vpCmd = c.viewport.Update(msg)
	cmds = append(cmds, vpCmd)

	return c, tea.Batch(cmds...)
}

// View renders the chat component
func (c Chat) View() string {
	// Add a title/label at the top
	titleStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("62")).
		Width(c.width).
		Align(lipgloss.Center).
		MarginBottom(1)
	
	title := titleStyle.Render("◆ Conversation History ◆")
	
	// Build the view with title
	content := lipgloss.JoinVertical(
		lipgloss.Left,
		title,
		c.viewport.View(),
		lipgloss.NewStyle().
			Width(c.width-2).
			Border(lipgloss.NormalBorder(), true, false, false, false).
			BorderForeground(lipgloss.Color("240")).
			Render(c.input.View()),
	)

	return content
}

// SetSize updates the chat component dimensions
func (c *Chat) SetSize(width, height int) {
	c.width = width
	c.height = height
	// Update viewport size (leaving room for input and title)
	c.viewport.Width = width
	c.viewport.Height = height - 7 // Leave room for input area and title
	c.input.SetWidth(width)
	
	// Clear renderer to force recreation with new width
	if c.renderer != nil && c.width != width {
		c.renderer = nil
	}
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
	
	// Update viewport content
	c.viewport.SetContent(c.buildViewportContent())
	
	// Auto-scroll to bottom
	c.viewport.GotoBottom()
}

// GetMessages returns all messages
func (c *Chat) GetMessages() []ChatMessage {
	return c.messages
}

// ClearMessages clears all messages from the chat
func (c *Chat) ClearMessages() {
	c.messages = []ChatMessage{}
	c.viewport.SetContent(c.buildViewportContent())
	c.viewport.GotoTop()
}

// GetMessageCount returns the number of messages
func (c *Chat) GetMessageCount() int {
	return len(c.messages)
}

// ensureRenderer lazily initializes the glamour renderer
func (c *Chat) ensureRenderer() {
	if c.renderer == nil && c.width > 4 {
		// Use "dark" style as default for faster initialization
		// This avoids the slow auto-detection on startup
		c.renderer, _ = glamour.NewTermRenderer(
			glamour.WithStylePath("dark"),
			glamour.WithWordWrap(c.width - 4),
		)
	}
}

// buildViewportContent builds the formatted message history
func (c *Chat) buildViewportContent() string {
	if len(c.messages) == 0 {
		return lipgloss.NewStyle().
			Foreground(lipgloss.Color("240")).
			Italic(true).
			Render("No messages yet. Type something to start the conversation!")
	}

	var content strings.Builder
	
	// Define message styles
	userStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("33")).
		Bold(true)
		
	assistantStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("213")).
		Bold(true)
		
	systemStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("240")).
		Italic(true)
		
	errorStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("196")).
		Bold(true)
		
	timeStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("240"))
	
	// Message content style with word wrapping
	// Account for viewport width minus some padding
	wrapWidth := c.viewport.Width
	if wrapWidth <= 0 {
		wrapWidth = c.width
	}
	if wrapWidth > 4 {
		wrapWidth -= 4 // Leave some padding
	}
	
	messageStyle := lipgloss.NewStyle().
		Width(wrapWidth)

	for i, msg := range c.messages {
		if i > 0 {
			content.WriteString("\n\n")
		}
		
		// Format timestamp
		timestamp := msg.Timestamp.Format("15:04:05")
		
		// Format author and message based on type
		var authorStyle lipgloss.Style
		var prefix string
		
		switch msg.Type {
		case UserMessage:
			authorStyle = userStyle
			prefix = "You"
		case AssistantMessage:
			authorStyle = assistantStyle
			prefix = "Assistant"
		case SystemMessage:
			authorStyle = systemStyle
			prefix = "System"
		case ErrorMessage:
			authorStyle = errorStyle
			prefix = "Error"
		}
		
		// Build message header
		header := fmt.Sprintf("%s %s", 
			authorStyle.Render(prefix),
			timeStyle.Render(timestamp))
		
		content.WriteString(header)
		content.WriteString("\n")
		
		// Render message content
		var renderedContent string
		
		// Use markdown rendering for assistant messages
		if msg.Type == AssistantMessage {
			// Ensure renderer is initialized
			c.ensureRenderer()
			if c.renderer != nil {
				// Try to render as markdown
				markdownContent, err := c.renderer.Render(msg.Content)
				if err == nil {
					// Remove trailing newlines from glamour output
					renderedContent = strings.TrimRight(markdownContent, "\n")
				} else {
					// Fallback to plain text with wrapping
					renderedContent = messageStyle.Render(msg.Content)
				}
			} else {
				// No renderer available, use plain text
				renderedContent = messageStyle.Render(msg.Content)
			}
		} else {
			// For user, system, and error messages, use plain text with wrapping
			renderedContent = messageStyle.Render(msg.Content)
		}
		
		content.WriteString(renderedContent)
	}
	
	return content.String()
}

// handleSlashCommand processes slash commands
func (c Chat) handleSlashCommand(command string) tea.Cmd {
	// Remove the leading slash and convert to lowercase
	cmd := strings.ToLower(strings.TrimPrefix(command, "/"))
	parts := strings.Fields(cmd)
	
	if len(parts) == 0 {
		return nil
	}
	
	// Handle different slash commands
	switch parts[0] {
	case "help", "h", "?":
		return func() tea.Msg {
			return ExecuteCommandMsg{Command: "help"}
		}
		
	case "model", "m":
		if len(parts) > 1 {
			// Handle model selection with optional provider
			modelName := strings.Join(parts[1:], " ")
			
			// Check if provider is included (format: "model provider")
			modelParts := strings.Fields(modelName)
			if len(modelParts) > 1 {
				// Model and provider specified
				model := modelParts[0]
				provider := strings.Join(modelParts[1:], " ")
				return func() tea.Msg {
					return ExecuteCommandMsg{
						Command: "set_model_with_provider",
						Args: map[string]string{
							"model":    model,
							"provider": provider,
						},
					}
				}
			} else {
				// Just model specified
				return func() tea.Msg {
					return ExecuteCommandMsg{
						Command: "set_model",
						Args: map[string]string{
							"model": modelName,
						},
					}
				}
			}
		} else {
			// Show usage - add to chat
			c.AddMessage(SystemMessage, "Usage: /model <name> [provider]\nExample: /model gpt-4\nExample: /model claude-3-opus anthropic", "system")
		}
		
	case "provider", "p":
		if len(parts) > 1 {
			providerName := strings.Join(parts[1:], " ")
			return func() tea.Msg {
				return ExecuteCommandMsg{
					Command: "set_provider",
					Args:    map[string]string{"provider": providerName},
				}
			}
		} else {
			c.AddMessage(SystemMessage, "Usage: /provider <name>\nExample: /provider openai\nExample: /provider azure\nSets the provider for the current model", "system")
		}
		
	case "clear", "cls", "new":
		// Clear conversation
		return func() tea.Msg {
			return ExecuteCommandMsg{Command: "new_conversation"}
		}
		
	case "tree", "files":
		// Toggle file tree
		return func() tea.Msg {
			return ExecuteCommandMsg{Command: "toggle_tree"}
		}
		
	case "editor", "edit":
		// Toggle editor
		return func() tea.Msg {
			return ExecuteCommandMsg{Command: "toggle_editor"}
		}
		
	case "commands", "cmds", "palette":
		// Show command palette
		return func() tea.Msg {
			return tea.KeyMsg{Type: tea.KeyCtrlP}
		}
		
	case "login":
		// Login command
		if len(parts) >= 3 {
			username := parts[1]
			password := strings.Join(parts[2:], " ")
			return func() tea.Msg {
				return ExecuteCommandMsg{
					Command: "auth_login",
					Args:    map[string]string{"username": username, "password": password},
				}
			}
		} else {
			c.AddMessage(SystemMessage, "Usage: /login <username> <password>", "system")
		}
		
	case "logout":
		// Logout command
		return func() tea.Msg {
			return ExecuteCommandMsg{Command: "auth_logout"}
		}
		
	case "apikey", "api-key":
		if len(parts) > 1 {
			switch parts[1] {
			case "generate", "gen", "new":
				return func() tea.Msg {
					return ExecuteCommandMsg{Command: "auth_apikey_generate"}
				}
			case "list", "ls":
				return func() tea.Msg {
					return ExecuteCommandMsg{Command: "auth_apikey_list"}
				}
			case "revoke", "rm", "delete":
				if len(parts) > 2 {
					return func() tea.Msg {
						return ExecuteCommandMsg{
							Command: "auth_apikey_revoke",
							Args:    map[string]string{"id": parts[2]},
						}
					}
				} else {
					c.AddMessage(SystemMessage, "Usage: /apikey revoke <key-id>", "system")
				}
			default:
				c.AddMessage(SystemMessage, "Usage: /apikey <generate|list|revoke>", "system")
			}
		} else {
			c.AddMessage(SystemMessage, "Usage: /apikey <generate|list|revoke>", "system")
		}
		
	case "status", "auth":
		// Check auth status
		return func() tea.Msg {
			return ExecuteCommandMsg{Command: "auth_status"}
		}
		
	case "quit", "exit", "q":
		// Quit application
		return tea.Quit
		
	default:
		// Unknown command - show help in chat
		helpText := fmt.Sprintf("Unknown command: /%s\n\nAvailable commands:\n", parts[0])
		helpText += "/help, /h, /?     - Show help\n"
		helpText += "/model <name>      - Set AI model\n"
		helpText += "/clear, /new       - New conversation\n"
		helpText += "/tree, /files      - Toggle file tree\n"
		helpText += "/editor, /edit     - Toggle editor\n"
		helpText += "/commands, /cmds   - Show command palette\n"
		helpText += "/provider <name>   - Set provider for current model\n"
		helpText += "/login <user> <pw> - Login to server\n"
		helpText += "/logout            - Logout from server\n"
		helpText += "/apikey <cmd>      - API key management\n"
		helpText += "/status, /auth     - Show auth status\n"
		helpText += "/quit, /exit, /q   - Quit application"
		c.AddMessage(SystemMessage, helpText, "system")
	}
	
	return nil
}