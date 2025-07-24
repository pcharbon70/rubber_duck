package ui

import (
	"fmt"
	"strings"
	"time"
	
	"github.com/charmbracelet/bubbles/viewport"
	"github.com/charmbracelet/lipgloss"
)

// StatusCategory represents different categories of status messages
type StatusCategory string

const (
	StatusCategoryEngine   StatusCategory = "engine"
	StatusCategoryTool     StatusCategory = "tool"
	StatusCategoryWorkflow StatusCategory = "workflow"
	StatusCategoryProgress StatusCategory = "progress"
	StatusCategoryError    StatusCategory = "error"
	StatusCategoryInfo     StatusCategory = "info"
)

// StatusMessage represents a single status update
type StatusMessage struct {
	Category  StatusCategory
	Text      string
	Metadata  map[string]interface{}
	Timestamp time.Time
}

// StatusMessages represents the status messages component
type StatusMessages struct {
	messages        []StatusMessage
	viewport        viewport.Model
	width           int
	height          int
	maxMessages     int
	showTimestamp   bool
	categoryColors  map[string]string // Category name to color code mapping
}

// NewStatusMessages creates a new status messages component
func NewStatusMessages() *StatusMessages {
	vp := viewport.New(0, 0)
	
	return &StatusMessages{
		messages:       []StatusMessage{},
		viewport:       vp,
		width:          80,
		height:         10,
		maxMessages:    100, // Keep last 100 messages
		showTimestamp:  true,
		categoryColors: make(map[string]string),
	}
}

// SetSize updates the component dimensions
func (s *StatusMessages) SetSize(width, height int) {
	s.width = width
	s.height = height
	s.viewport.Width = width
	s.viewport.Height = height - 2 // Account for title and margin
	
	// Update viewport content when size changes
	s.viewport.SetContent(s.buildContent())
}

// SetCategoryColors sets the color mapping for categories
func (s *StatusMessages) SetCategoryColors(colors map[string]string) {
	s.categoryColors = colors
	// Re-render content with new colors
	s.viewport.SetContent(s.buildContent())
}

// AddMessage adds a new status message
func (s *StatusMessages) AddMessage(category StatusCategory, text string, metadata map[string]interface{}) {
	msg := StatusMessage{
		Category:  category,
		Text:      text,
		Metadata:  metadata,
		Timestamp: time.Now(),
	}
	
	s.messages = append(s.messages, msg)
	
	// Limit number of messages
	if len(s.messages) > s.maxMessages {
		s.messages = s.messages[len(s.messages)-s.maxMessages:]
	}
	
	// Update viewport
	s.viewport.SetContent(s.buildContent())
	
	// Auto-scroll to bottom
	s.viewport.GotoBottom()
}

// Clear removes all messages
func (s *StatusMessages) Clear() {
	s.messages = []StatusMessage{}
	s.viewport.SetContent("")
}

// View renders the status messages component
func (s StatusMessages) View() string {
	// Add a title/label at the top
	titleStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("63")).
		Width(s.width).
		Align(lipgloss.Center).
		MarginBottom(1)
	
	title := titleStyle.Render("◆ AI Status Messages ◆")
	
	var content string
	if len(s.messages) == 0 {
		emptyStyle := lipgloss.NewStyle().
			Foreground(lipgloss.Color("240")).
			Italic(true).
			Align(lipgloss.Center).
			Width(s.width).
			Height(s.height - 2) // Account for title
		content = emptyStyle.Render("No status messages")
	} else {
		content = s.viewport.View()
	}
	
	return lipgloss.JoinVertical(lipgloss.Left, title, content)
}

// buildContent builds the formatted content for the viewport
func (s StatusMessages) buildContent() string {
	if len(s.messages) == 0 {
		return ""
	}
	
	var content strings.Builder
	
	// Define default category styles
	defaultCategoryStyles := map[StatusCategory]string{
		StatusCategoryEngine:   "33",    // Blue
		StatusCategoryTool:     "213",   // Purple
		StatusCategoryWorkflow: "226",   // Yellow
		StatusCategoryProgress: "46",    // Green
		StatusCategoryError:    "196",   // Red
		StatusCategoryInfo:     "240",   // Gray
	}
	
	timeStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("240"))
	
	for i, msg := range s.messages {
		if i > 0 {
			content.WriteString("\n")
		}
		
		// Get color for category
		color := "240" // Default gray
		
		// First check if we have a configured color for this category
		if configuredColor, exists := s.categoryColors[string(msg.Category)]; exists {
			color = configuredColor
		} else if defaultColor, exists := defaultCategoryStyles[msg.Category]; exists {
			// Fall back to default color
			color = defaultColor
		}
		
		style := lipgloss.NewStyle().Foreground(lipgloss.Color(color))
		
		// Format line
		categoryText := style.Bold(true).Render(fmt.Sprintf("[%s]", strings.ToUpper(string(msg.Category))))
		
		if s.showTimestamp {
			timestamp := msg.Timestamp.Format("15:04:05")
			timeText := timeStyle.Render(timestamp)
			content.WriteString(fmt.Sprintf("%s %s ", categoryText, timeText))
		} else {
			content.WriteString(fmt.Sprintf("%s ", categoryText))
		}
		
		// Add the message text
		content.WriteString(msg.Text)
		
		// Add metadata if present and it's an error or has details
		if msg.Category == StatusCategoryError && msg.Metadata != nil {
			if details, ok := msg.Metadata["error"].(string); ok {
				content.WriteString(fmt.Sprintf("\n    %s", lipgloss.NewStyle().Foreground(lipgloss.Color("196")).Render(details)))
			}
		}
	}
	
	return content.String()
}

// GetMessageCount returns the number of messages
func (s *StatusMessages) GetMessageCount() int {
	return len(s.messages)
}

// ScrollUp scrolls the viewport up
func (s *StatusMessages) ScrollUp() {
	s.viewport.LineUp(3)
}

// ScrollDown scrolls the viewport down
func (s *StatusMessages) ScrollDown() {
	s.viewport.LineDown(3)
}

// GotoTop scrolls to the top
func (s *StatusMessages) GotoTop() {
	s.viewport.GotoTop()
}

// GotoBottom scrolls to the bottom
func (s *StatusMessages) GotoBottom() {
	s.viewport.GotoBottom()
}