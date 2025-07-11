package ui

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/rubber_duck/tui/internal/phoenix"
)

// Update handles all state transitions
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		// Global hotkeys
		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
		case "tab":
			m.activePane = m.nextPane()
			return m, nil
		case "ctrl+p":
			m.commandPalette.Show()
			return m, nil
		case "ctrl+h":
			// TODO: Show help
			return m, nil
		}

		// Handle command palette if visible
		if m.commandPalette.IsVisible() {
			var cmd tea.Cmd
			m.commandPalette, cmd = m.commandPalette.Update(msg)
			return m, cmd
		}

		// Pane-specific handling
		switch m.activePane {
		case FileTreePane:
			var cmd tea.Cmd
			m.fileTree, cmd = m.fileTree.Update(msg)
			if cmd != nil {
				cmds = append(cmds, cmd)
			}
		case EditorPane:
			var cmd tea.Cmd
			m.editor, cmd = m.editor.Update(msg)
			if cmd != nil {
				cmds = append(cmds, cmd)
			}
		case OutputPane:
			var cmd tea.Cmd
			m.output, cmd = m.output.Update(msg)
			if cmd != nil {
				cmds = append(cmds, cmd)
			}
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.updateComponentSizes()
		return m, nil

	case InitiateConnectionMsg:
		// Load API key from config file or environment
		apiKey := loadAPIKey()
		
		// Set up Phoenix connection configuration
		config := phoenix.Config{
			URL:       "ws://localhost:5555/socket",
			APIKey:    apiKey,
			ChannelID: "cli:commands",
		}
		
		// Create the Phoenix client
		client := phoenix.NewClient(config)
		m.phoenixClient = client
		m.phoenixConfig = config
		m.statusBar = "Connecting to Phoenix..."
		
		// Get the program reference
		prog := GetProgram()
		if prog == nil {
			return m, nil
		}
		
		// Start the connection
		return m, client.Connect(config, prog)

	case phoenix.SocketCreatedMsg:
		m.socket = msg.Socket
		m.statusBar = "Socket created, joining channel..."
		// Join the channel
		return m, m.phoenixClient.JoinChannel(msg.Socket, m.phoenixConfig.ChannelID)

	case phoenix.ChannelJoinedMsg:
		m.channel = msg.Channel
		m.connected = true
		m.statusBar = "Connected to Phoenix | " + m.getKeyHints()
		// Request initial file list
		return m, m.phoenixClient.Push("file:list", map[string]any{
			"path": ".",
		})

	case ConnectedMsg:
		m.connected = true
		m.statusBar = "Connected to Phoenix | " + m.getKeyHints()
		return m, nil

	case DisconnectedMsg:
		m.connected = false
		m.statusBar = lipgloss.NewStyle().
			Foreground(lipgloss.Color("196")).
			Render(fmt.Sprintf("Disconnected: %v", msg.Error))
		return m, nil

	case ChannelResponseMsg:
		switch msg.Event {
		case "analyze_result":
			// TODO: Handle analysis result
			m.output.SetContent("Analysis complete!")
		case "completion":
			// TODO: Handle completion
		case "file_list":
			// TODO: Update file tree
		}

	case FileSelectedMsg:
		m.statusBar = fmt.Sprintf("Loading %s...", msg.Path)
		return m, m.loadFile(msg.Path)

	case FileLoadedMsg:
		m.editor.SetValue(msg.Content)
		m.statusBar = fmt.Sprintf("Editing: %s | %s", msg.Path, m.getKeyHints())
		return m, nil

	case ErrorMsg:
		m.err = msg.Err
		m.statusBar = lipgloss.NewStyle().
			Foreground(lipgloss.Color("196")).
			Render(fmt.Sprintf("Error in %s: %v", msg.Component, msg.Err))
		return m, nil

	case StreamStartMsg:
		m.output.SetContent("Starting stream...\n")
		return m, nil

	case StreamDataMsg:
		content := m.output.View() + msg.Data
		m.output.SetContent(content)
		return m, nil

	case StreamEndMsg:
		content := m.output.View() + "\n--- Stream Complete ---\n"
		m.output.SetContent(content)
		return m, nil
	}

	// Update child components if they're not handled above
	switch m.activePane {
	case EditorPane:
		if _, ok := msg.(tea.KeyMsg); !ok {
			var cmd tea.Cmd
			m.editor, cmd = m.editor.Update(msg)
			cmds = append(cmds, cmd)
		}
	case OutputPane:
		if _, ok := msg.(tea.KeyMsg); !ok {
			var cmd tea.Cmd
			m.output, cmd = m.output.Update(msg)
			cmds = append(cmds, cmd)
		}
	}

	return m, tea.Batch(cmds...)
}

// nextPane cycles to the next pane
func (m Model) nextPane() Pane {
	switch m.activePane {
	case FileTreePane:
		return EditorPane
	case EditorPane:
		return OutputPane
	case OutputPane:
		return FileTreePane
	}
	return FileTreePane
}


// updateComponentSizes updates component sizes based on terminal size
func (m *Model) updateComponentSizes() {
	if m.width == 0 || m.height == 0 {
		return
	}

	// Layout calculation
	sidebarWidth := 30
	outputWidth := 40
	editorWidth := m.width - sidebarWidth - outputWidth - 6 // borders
	contentHeight := m.height - 3 // status bar

	// Update editor size
	m.editor.SetWidth(editorWidth)
	m.editor.SetHeight(contentHeight)

	// Update output viewport size
	m.output.Width = outputWidth
	m.output.Height = contentHeight
}

// getKeyHints returns context-sensitive key hints
func (m Model) getKeyHints() string {
	base := "Tab: Switch Pane | Ctrl+P: Commands | Ctrl+H: Help | Ctrl+C: Quit"
	
	switch m.activePane {
	case FileTreePane:
		return "↑↓/jk: Navigate | Enter: Select | " + base
	case EditorPane:
		return "Ctrl+S: Save | " + base
	case OutputPane:
		return "↑↓: Scroll | " + base
	}
	
	return base
}

// loadFile creates a command to load a file
func (m Model) loadFile(path string) tea.Cmd {
	return func() tea.Msg {
		// TODO: Implement actual file loading via Phoenix channel
		// For now, return a mock response
		return FileLoadedMsg{
			Path:    path,
			Content: fmt.Sprintf("// Contents of %s\n// TODO: Load from Phoenix channel", path),
		}
	}
}

// Config represents the RubberDuck configuration
type Config struct {
	APIKey    string `json:"api_key"`
	CreatedAt string `json:"created_at"`
	ServerURL string `json:"server_url"`
}

// loadAPIKey loads the API key from config file or environment
func loadAPIKey() string {
	// First check environment variable
	if apiKey := os.Getenv("RUBBER_DUCK_API_KEY"); apiKey != "" {
		return apiKey
	}
	
	// Then check config file
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	
	configPath := filepath.Join(homeDir, ".rubber_duck", "config.json")
	data, err := os.ReadFile(configPath)
	if err != nil {
		return ""
	}
	
	var config Config
	if err := json.Unmarshal(data, &config); err != nil {
		return ""
	}
	
	return config.APIKey
}