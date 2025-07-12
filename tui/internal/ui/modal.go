package ui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ModalType represents different types of modals
type ModalType int

const (
	ModalConfirm ModalType = iota
	ModalInput
	ModalSettings
	ModalHelp
	ModalError
	ModalInfo
)

// ModalButton represents a button in a modal dialog
type ModalButton struct {
	Label    string
	Value    string
	Style    lipgloss.Style
	Primary  bool
	Shortcut string // e.g., "y", "n", "enter", "esc"
}

// Modal represents a modal dialog component
type Modal struct {
	// Core properties
	modalType ModalType
	title     string
	content   string
	visible   bool
	width     int
	height    int
	
	// Buttons
	buttons       []ModalButton
	selectedIndex int
	
	// Input field (for input modals)
	textInput textinput.Model
	hasInput  bool
	
	// Callback
	onResult func(result ModalResult)
	
	// Styling
	overlayStyle lipgloss.Style
	boxStyle     lipgloss.Style
	titleStyle   lipgloss.Style
	contentStyle lipgloss.Style
}

// ModalResult represents the result of a modal interaction
type ModalResult struct {
	Action   string // Button value that was selected
	Input    string // Text input value (for input modals)
	Canceled bool   // True if user pressed Esc or closed the modal
}

// NewModal creates a new modal with default styling
func NewModal() Modal {
	ti := textinput.New()
	ti.CharLimit = 256
	ti.Width = 40
	
	return Modal{
		textInput: ti,
		overlayStyle: lipgloss.NewStyle().
			Background(lipgloss.Color("0")).
			Foreground(lipgloss.Color("255")),
		boxStyle: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("62")).
			Background(lipgloss.Color("235")).
			Padding(1, 2),
		titleStyle: lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("212")).
			MarginBottom(1),
		contentStyle: lipgloss.NewStyle().
			Foreground(lipgloss.Color("252")).
			MarginBottom(1),
	}
}

// Common modal constructors

// ShowConfirm displays a confirmation dialog
func (m *Modal) ShowConfirm(title, content string, onResult func(ModalResult)) {
	m.modalType = ModalConfirm
	m.title = title
	m.content = content
	m.visible = true
	m.hasInput = false
	m.selectedIndex = 1 // Default to "No" for safety
	m.onResult = onResult
	
	m.buttons = []ModalButton{
		{
			Label:    "Yes",
			Value:    "yes",
			Shortcut: "y",
			Style:    lipgloss.NewStyle().Foreground(lipgloss.Color("42")),
		},
		{
			Label:    "No",
			Value:    "no",
			Shortcut: "n",
			Primary:  true,
			Style:    lipgloss.NewStyle().Foreground(lipgloss.Color("196")),
		},
	}
}

// ShowInput displays an input dialog
func (m *Modal) ShowInput(title, content, placeholder string, onResult func(ModalResult)) {
	m.modalType = ModalInput
	m.title = title
	m.content = content
	m.visible = true
	m.hasInput = true
	m.selectedIndex = 0
	m.onResult = onResult
	
	// Configure text input
	m.textInput.Placeholder = placeholder
	m.textInput.SetValue("")
	m.textInput.Focus()
	
	m.buttons = []ModalButton{
		{
			Label:    "OK",
			Value:    "ok",
			Shortcut: "enter",
			Primary:  true,
			Style:    lipgloss.NewStyle().Foreground(lipgloss.Color("42")),
		},
		{
			Label:    "Cancel",
			Value:    "cancel",
			Shortcut: "esc",
			Style:    lipgloss.NewStyle().Foreground(lipgloss.Color("240")),
		},
	}
}

// ShowError displays an error message
func (m *Modal) ShowError(title, content string) {
	m.modalType = ModalError
	m.title = "❌ " + title
	m.content = content
	m.visible = true
	m.hasInput = false
	m.selectedIndex = 0
	m.onResult = nil
	
	m.buttons = []ModalButton{
		{
			Label:    "OK",
			Value:    "ok",
			Shortcut: "enter",
			Primary:  true,
			Style:    lipgloss.NewStyle().Foreground(lipgloss.Color("196")),
		},
	}
}

// ShowInfo displays an information message
func (m *Modal) ShowInfo(title, content string) {
	m.modalType = ModalInfo
	m.title = "ℹ️  " + title
	m.content = content
	m.visible = true
	m.hasInput = false
	m.selectedIndex = 0
	m.onResult = nil
	
	m.buttons = []ModalButton{
		{
			Label:    "OK",
			Value:    "ok",
			Shortcut: "enter",
			Primary:  true,
			Style:    lipgloss.NewStyle().Foreground(lipgloss.Color("33")),
		},
	}
}

// Update handles modal updates
func (m Modal) Update(msg tea.Msg) (Modal, tea.Cmd) {
	if !m.visible {
		return m, nil
	}
	
	var cmds []tea.Cmd
	
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "esc":
			m.visible = false
			if m.onResult != nil {
				return m, func() tea.Msg {
					m.onResult(ModalResult{Canceled: true})
					return nil
				}
			}
			return m, nil
			
		case "tab", "shift+tab":
			if m.hasInput && m.textInput.Focused() {
				// Switch from input to buttons
				m.textInput.Blur()
			} else if m.hasInput && !m.textInput.Focused() {
				// Switch from buttons to input
				m.textInput.Focus()
				return m, textinput.Blink
			} else {
				// Navigate buttons
				if msg.String() == "tab" {
					m.selectedIndex = (m.selectedIndex + 1) % len(m.buttons)
				} else {
					m.selectedIndex = (m.selectedIndex - 1 + len(m.buttons)) % len(m.buttons)
				}
			}
			
		case "left", "h":
			if !m.hasInput || !m.textInput.Focused() {
				if m.selectedIndex > 0 {
					m.selectedIndex--
				}
			}
			
		case "right", "l":
			if !m.hasInput || !m.textInput.Focused() {
				if m.selectedIndex < len(m.buttons)-1 {
					m.selectedIndex++
				}
			}
			
		case "enter":
			if m.hasInput && m.textInput.Focused() {
				// Submit with enter in text input
				m.visible = false
				if m.onResult != nil && m.buttons[0].Value == "ok" {
					inputValue := m.textInput.Value()
					return m, func() tea.Msg {
						m.onResult(ModalResult{
							Action: "ok",
							Input:  inputValue,
						})
						return nil
					}
				}
			} else {
				// Select current button
				m.visible = false
				if m.onResult != nil {
					button := m.buttons[m.selectedIndex]
					inputValue := m.textInput.Value()
					return m, func() tea.Msg {
						m.onResult(ModalResult{
							Action: button.Value,
							Input:  inputValue,
						})
						return nil
					}
				}
			}
			
		default:
			// Check button shortcuts
			if !m.hasInput || !m.textInput.Focused() {
				for i, button := range m.buttons {
					if button.Shortcut == msg.String() {
						m.selectedIndex = i
						m.visible = false
						if m.onResult != nil {
							inputValue := m.textInput.Value()
							return m, func() tea.Msg {
								m.onResult(ModalResult{
									Action: button.Value,
									Input:  inputValue,
								})
								return nil
							}
						}
						return m, nil
					}
				}
			}
		}
		
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
	}
	
	// Update text input if present and focused
	if m.hasInput && m.textInput.Focused() {
		var cmd tea.Cmd
		m.textInput, cmd = m.textInput.Update(msg)
		cmds = append(cmds, cmd)
	}
	
	return m, tea.Batch(cmds...)
}

// View renders the modal
func (m Modal) View() string {
	if !m.visible || m.width == 0 || m.height == 0 {
		return ""
	}
	
	// Build modal content
	var content strings.Builder
	
	// Title
	content.WriteString(m.titleStyle.Render(m.title))
	content.WriteString("\n\n")
	
	// Content
	content.WriteString(m.contentStyle.Render(m.content))
	content.WriteString("\n")
	
	// Input field (if applicable)
	if m.hasInput {
		content.WriteString("\n")
		content.WriteString(m.textInput.View())
		content.WriteString("\n")
	}
	
	// Buttons
	content.WriteString("\n")
	for i, button := range m.buttons {
		style := button.Style
		if i == m.selectedIndex && (!m.hasInput || !m.textInput.Focused()) {
			// Highlight selected button
			style = style.
				Background(lipgloss.Color("62")).
				Foreground(lipgloss.Color("230")).
				Bold(true)
		}
		
		label := button.Label
		if button.Shortcut != "" && button.Shortcut != "enter" && button.Shortcut != "esc" {
			label = fmt.Sprintf("[%s] %s", button.Shortcut, label)
		}
		
		content.WriteString(style.Render(fmt.Sprintf(" %s ", label)))
		if i < len(m.buttons)-1 {
			content.WriteString("  ")
		}
	}
	
	// Calculate modal dimensions
	modalContent := content.String()
	lines := strings.Split(modalContent, "\n")
	modalWidth := 0
	for _, line := range lines {
		if w := lipgloss.Width(line); w > modalWidth {
			modalWidth = w
		}
	}
	modalWidth += 6 // Account for padding and borders
	
	if modalWidth < 40 {
		modalWidth = 40
	}
	if modalWidth > m.width-10 {
		modalWidth = m.width - 10
	}
	
	// Apply box styling
	box := m.boxStyle.
		Width(modalWidth).
		Render(modalContent)
	
	// Create semi-transparent overlay effect
	overlay := lipgloss.Place(
		m.width,
		m.height,
		lipgloss.Center,
		lipgloss.Center,
		box,
		lipgloss.WithWhitespaceBackground(lipgloss.Color("236")),
	)
	
	return overlay
}

// Helper methods

// Hide hides the modal
func (m *Modal) Hide() {
	m.visible = false
}

// IsVisible returns whether the modal is visible
func (m Modal) IsVisible() bool {
	return m.visible
}

// SetSize updates the modal's terminal dimensions
func (m *Modal) SetSize(width, height int) {
	m.width = width
	m.height = height
}