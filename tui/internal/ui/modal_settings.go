package ui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Settings represents application settings
type Settings struct {
	Theme           string
	ShowLineNumbers bool
	AutoSave        bool
	TabSize         int
	FontSize        int
	ServerURL       string
	UsesMockClient  bool
}

// SettingsModal is a specialized modal for settings
type SettingsModal struct {
	Modal
	settings       Settings
	tempSettings   Settings // For editing
	selectedField  int
	inputs         []textinput.Model
	editing        bool
	availableThemes []string
}

// NewSettingsModal creates a new settings modal
func NewSettingsModal(currentSettings Settings) SettingsModal {
	baseModal := NewModal()
	
	// Create text inputs for editable fields
	serverInput := textinput.New()
	serverInput.Placeholder = "ws://localhost:5555/socket"
	serverInput.Width = 40
	serverInput.SetValue(currentSettings.ServerURL)
	
	tabSizeInput := textinput.New()
	tabSizeInput.Placeholder = "4"
	tabSizeInput.Width = 5
	tabSizeInput.SetValue(fmt.Sprintf("%d", currentSettings.TabSize))
	
	fontSizeInput := textinput.New()
	fontSizeInput.Placeholder = "14"
	fontSizeInput.Width = 5
	fontSizeInput.SetValue(fmt.Sprintf("%d", currentSettings.FontSize))
	
	return SettingsModal{
		Modal:        baseModal,
		settings:     currentSettings,
		tempSettings: currentSettings,
		inputs: []textinput.Model{
			serverInput,
			tabSizeInput,
			fontSizeInput,
		},
		availableThemes: []string{"dark", "light", "solarized-dark", "dracula"},
	}
}

// SetAvailableThemes updates the list of available themes
func (m *SettingsModal) SetAvailableThemes(themes []string) {
	m.availableThemes = themes
}

// cycleTheme moves to the next theme in the list
func (m *SettingsModal) cycleTheme(forward bool) {
	if len(m.availableThemes) == 0 {
		return
	}
	
	currentIndex := 0
	for i, theme := range m.availableThemes {
		if theme == m.tempSettings.Theme {
			currentIndex = i
			break
		}
	}
	
	if forward {
		currentIndex = (currentIndex + 1) % len(m.availableThemes)
	} else {
		currentIndex = (currentIndex - 1 + len(m.availableThemes)) % len(m.availableThemes)
	}
	
	m.tempSettings.Theme = m.availableThemes[currentIndex]
}

// ShowSettings displays the settings modal
func (m *SettingsModal) ShowSettings(onResult func(Settings, bool)) {
	m.modalType = ModalSettings
	m.title = "⚙️  Settings"
	m.visible = true
	m.hasInput = false
	m.selectedField = 0
	m.editing = false
	
	// Reset temp settings to current
	m.tempSettings = m.settings
	
	m.buttons = []ModalButton{
		{
			Label:    "Save",
			Value:    "save",
			Shortcut: "s",
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
	
	// Custom onResult to handle settings
	m.onResult = func(result ModalResult) {
		saved := result.Action == "save" && !result.Canceled
		if saved {
			m.settings = m.tempSettings
		}
		onResult(m.settings, saved)
	}
}

// Update handles settings modal specific updates
func (m SettingsModal) Update(msg tea.Msg) (SettingsModal, tea.Cmd) {
	if !m.visible {
		return m, nil
	}
	
	var cmds []tea.Cmd
	
	switch msg := msg.(type) {
	case tea.KeyMsg:
		// If editing a field, handle input
		if m.editing {
			switch msg.String() {
			case "enter":
				m.editing = false
				m.applyFieldValue()
				m.inputs[m.getInputIndex()].Blur()
				return m, nil
				
			case "esc":
				m.editing = false
				m.inputs[m.getInputIndex()].Blur()
				return m, nil
				
			default:
				// Update the active input
				idx := m.getInputIndex()
				if idx >= 0 && idx < len(m.inputs) {
					var cmd tea.Cmd
					m.inputs[idx], cmd = m.inputs[idx].Update(msg)
					cmds = append(cmds, cmd)
				}
				return m, tea.Batch(cmds...)
			}
		}
		
		// Navigation when not editing
		switch msg.String() {
		case "up", "k":
			if m.selectedField > 0 {
				m.selectedField--
			}
			
		case "down", "j":
			maxField := 6 // Number of settings fields
			if m.selectedField < maxField {
				m.selectedField++
			}
			
		case "left", "h":
			// Cycle theme backwards if on theme field
			if m.selectedField == 0 {
				m.cycleTheme(false)
			}
			
		case "right", "l":
			// Cycle theme forwards if on theme field
			if m.selectedField == 0 {
				m.cycleTheme(true)
			}
			
		case "enter", " ":
			if m.selectedField < 6 { // Settings fields
				m.toggleOrEditField()
			} else { // Buttons
				// Handle button selection
				buttonIndex := m.selectedField - 6
				if buttonIndex == 0 { // Save
					m.visible = false
					if m.onResult != nil {
						return m, func() tea.Msg {
							m.onResult(ModalResult{Action: "save"})
							return nil
						}
					}
				} else { // Cancel
					m.visible = false
					if m.onResult != nil {
						return m, func() tea.Msg {
							m.onResult(ModalResult{Canceled: true})
							return nil
						}
					}
				}
			}
			
		case "s": // Save shortcut
			m.visible = false
			if m.onResult != nil {
				return m, func() tea.Msg {
					m.onResult(ModalResult{Action: "save"})
					return nil
				}
			}
			
		case "esc": // Cancel
			m.visible = false
			if m.onResult != nil {
				return m, func() tea.Msg {
					m.onResult(ModalResult{Canceled: true})
					return nil
				}
			}
		}
	}
	
	// Update base modal
	var cmd tea.Cmd
	m.Modal, cmd = m.Modal.Update(msg)
	cmds = append(cmds, cmd)
	
	return m, tea.Batch(cmds...)
}

// View renders the settings modal
func (m SettingsModal) View() string {
	if !m.visible || m.width == 0 || m.height == 0 {
		return ""
	}
	
	var content strings.Builder
	
	// Title
	content.WriteString(m.titleStyle.Render(m.title))
	content.WriteString("\n\n")
	
	// Settings fields
	fields := []struct {
		label    string
		value    string
		editable bool
	}{
		{"Theme", m.tempSettings.Theme, false},
		{"Show Line Numbers", fmt.Sprintf("%v", m.tempSettings.ShowLineNumbers), false},
		{"Auto Save", fmt.Sprintf("%v", m.tempSettings.AutoSave), false},
		{"Tab Size", fmt.Sprintf("%d", m.tempSettings.TabSize), true},
		{"Font Size", fmt.Sprintf("%d", m.tempSettings.FontSize), true},
		{"Server URL", m.tempSettings.ServerURL, true},
	}
	
	labelStyle := lipgloss.NewStyle().
		Width(20).
		Foreground(lipgloss.Color("245"))
	
	valueStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("252"))
	
	selectedStyle := lipgloss.NewStyle().
		Background(lipgloss.Color("236")).
		Foreground(lipgloss.Color("212"))
	
	for i, field := range fields {
		label := labelStyle.Render(field.label + ":")
		
		var value string
		if field.editable && m.editing && i == m.selectedField {
			// Show input field
			idx := m.getInputIndex()
			if idx >= 0 {
				value = m.inputs[idx].View()
			}
		} else {
			// Show value
			value = valueStyle.Render(field.value)
			
			// Add toggle indicators for boolean fields
			if i <= 2 { // Theme, line numbers, auto save
				if field.value == "true" {
					value = "☑ " + value
				} else if field.value == "false" {
					value = "☐ " + value
				}
			}
		}
		
		line := fmt.Sprintf("%s %s", label, value)
		
		// Highlight selected field
		if i == m.selectedField {
			line = selectedStyle.Render(line)
			if field.editable && !m.editing {
				line += " " + lipgloss.NewStyle().
					Foreground(lipgloss.Color("240")).
					Render("(press Enter to edit)")
			}
		}
		
		content.WriteString(line)
		content.WriteString("\n")
	}
	
	// Add connection status
	content.WriteString("\n")
	statusStyle := lipgloss.NewStyle().
		Foreground(lipgloss.Color("240")).
		Italic(true)
	
	if m.tempSettings.UsesMockClient {
		content.WriteString(statusStyle.Render("📡 Using mock client (development mode)"))
	} else {
		content.WriteString(statusStyle.Render("📡 Connected to Phoenix server"))
	}
	content.WriteString("\n\n")
	
	// Buttons
	for i, button := range m.buttons {
		style := button.Style
		buttonIndex := 6 + i // After settings fields
		if buttonIndex == m.selectedField {
			style = style.
				Background(lipgloss.Color("62")).
				Foreground(lipgloss.Color("230")).
				Bold(true)
		}
		
		label := fmt.Sprintf("[%s] %s", button.Shortcut, button.Label)
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
	
	if modalWidth < 60 {
		modalWidth = 60
	}
	if modalWidth > m.width-10 {
		modalWidth = m.width - 10
	}
	
	// Apply box styling
	box := m.boxStyle.
		Width(modalWidth).
		Render(modalContent)
	
	// Create overlay
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

func (m *SettingsModal) toggleOrEditField() {
	switch m.selectedField {
	case 0: // Theme
		m.cycleTheme(true)
		
	case 1: // Show Line Numbers
		m.tempSettings.ShowLineNumbers = !m.tempSettings.ShowLineNumbers
		
	case 2: // Auto Save
		m.tempSettings.AutoSave = !m.tempSettings.AutoSave
		
	case 3, 4, 5: // Editable fields
		m.editing = true
		idx := m.getInputIndex()
		if idx >= 0 {
			m.inputs[idx].Focus()
		}
	}
}

func (m *SettingsModal) getInputIndex() int {
	switch m.selectedField {
	case 3: // Tab Size
		return 1
	case 4: // Font Size
		return 2
	case 5: // Server URL
		return 0
	default:
		return -1
	}
}

func (m *SettingsModal) applyFieldValue() {
	idx := m.getInputIndex()
	if idx < 0 || idx >= len(m.inputs) {
		return
	}
	
	value := m.inputs[idx].Value()
	
	switch m.selectedField {
	case 3: // Tab Size
		if size := parseInt(value); size > 0 && size <= 8 {
			m.tempSettings.TabSize = size
		}
		
	case 4: // Font Size
		if size := parseInt(value); size >= 8 && size <= 32 {
			m.tempSettings.FontSize = size
		}
		
	case 5: // Server URL
		if value != "" {
			m.tempSettings.ServerURL = value
		}
	}
}

// parseInt safely parses an integer with a default of 0
func parseInt(s string) int {
	var n int
	fmt.Sscanf(s, "%d", &n)
	return n
}