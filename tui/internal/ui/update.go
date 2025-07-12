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
	// Start performance monitoring
	if m.performanceMonitor != nil {
		m.performanceMonitor.StartUpdate()
		defer m.performanceMonitor.EndUpdate()
	}
	
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.KeyMsg:
		// Handle modals first if they're visible
		if m.modal.IsVisible() {
			var cmd tea.Cmd
			m.modal, cmd = m.modal.Update(msg)
			return m, cmd
		}
		
		if m.settingsModal.IsVisible() {
			var cmd tea.Cmd
			m.settingsModal, cmd = m.settingsModal.Update(msg)
			return m, cmd
		}
		
		// Global hotkeys
		switch msg.String() {
		case "ctrl+c", "q":
			// Show confirmation dialog if there are unsaved changes
			if m.modified {
				m.modal.ShowConfirm(
					"Unsaved Changes",
					"You have unsaved changes. Are you sure you want to quit?",
					func(result ModalResult) {
						if result.Action == "yes" {
							if prog := GetProgram(); prog != nil {
								prog.Send(tea.Quit())
							}
						}
					},
				)
				return m, nil
			}
			return m, tea.Quit
		case "tab":
			m.activePane = m.nextPane()
			return m, nil
		case "ctrl+p":
			m.commandPalette.Show()
			return m, nil
		case "ctrl+h":
			// Show help modal
			m.modal.ShowHelp()
			return m, nil
		case "ctrl+shift+t":
			// Toggle theme shortcut
			currentTheme := m.themeManager.GetCurrentThemeName()
			if currentTheme == "dark" {
				m.themeManager.SetTheme("light")
				m.statusBar = "Switched to light theme"
			} else {
				m.themeManager.SetTheme("dark")
				m.statusBar = "Switched to dark theme"
			}
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
			prevValue := m.editor.Value()
			var cmd tea.Cmd
			m.editor, cmd = m.editor.Update(msg)
			if cmd != nil {
				cmds = append(cmds, cmd)
			}
			
			// Check if content changed and trigger debounced auto-save
			if m.editor.Value() != prevValue {
				m.modified = true
				m.triggerDebouncedSave()
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
		m.modal.SetSize(msg.Width, msg.Height)
		m.settingsModal.SetSize(msg.Width, msg.Height)
		return m, nil

	case InitiateConnectionMsg:
		// Create Phoenix configuration
		config := phoenix.CreateConfig()
		
		// Create the Phoenix client (will use mock in development)
		client := phoenix.NewPhoenixClient()
		m.phoenixClient = client
		m.phoenixConfig = config
		
		// Update status based on client type
		if phoenix.IsRunningInMockMode() {
			m.statusBar = "Connecting to Mock Phoenix..."
		} else {
			m.statusBar = "Connecting to Phoenix..."
		}
		
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
		return m, m.phoenixClient.JoinChannel(m.phoenixConfig.ChannelID)

	case phoenix.ChannelJoinedMsg:
		m.channel = msg.Channel
		m.connected = true
		m.statusBar = "Connected to Phoenix | " + m.getKeyHints()
		// Request initial file list
		return m, m.phoenixClient.ListFiles(".")

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
		case "completion_result":
			// TODO: Handle completion
		case "file_list":
			// Update file tree with response data
			return m, m.handleFileListResponse(msg.Payload)
		case "file_loaded":
			// Handle file content response
			return m, m.handleFileLoadedResponse(msg.Payload)
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
		
	case AutoSaveMsg:
		// Handle auto-save operation
		m.statusBar = fmt.Sprintf("Auto-saved: %s", msg.File)
		// TODO: Implement actual file saving logic
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
	if m.phoenixClient != nil {
		return m.phoenixClient.LoadFile(path)
	}
	
	// Fallback for when no client is available
	return func() tea.Msg {
		return FileLoadedMsg{
			Path:    path,
			Content: fmt.Sprintf("// Contents of %s\n// No Phoenix client available", path),
		}
	}
}

// handleFileListResponse processes file list response from Phoenix
func (m Model) handleFileListResponse(payload []byte) tea.Cmd {
	var response phoenix.FileListResponse
	if err := json.Unmarshal(payload, &response); err != nil {
		return func() tea.Msg {
			return ErrorMsg{
				Err:       err,
				Component: "File List",
			}
		}
	}
	
	// Convert Phoenix FileInfo to UI FileNode
	root := convertFileInfoToNode(response.Files, response.Path)
	
	return func() tea.Msg {
		return FileTreeLoadedMsg{Root: root}
	}
}

// handleFileLoadedResponse processes file loaded response from Phoenix
func (m Model) handleFileLoadedResponse(payload []byte) tea.Cmd {
	var response phoenix.FileContentResponse
	if err := json.Unmarshal(payload, &response); err != nil {
		return func() tea.Msg {
			return ErrorMsg{
				Err:       err,
				Component: "File Load",
			}
		}
	}
	
	return func() tea.Msg {
		return FileLoadedMsg{
			Path:    response.Path,
			Content: response.Content,
		}
	}
}

// convertFileInfoToNode converts Phoenix FileInfo to UI FileNode
func convertFileInfoToNode(files []phoenix.FileInfo, basePath string) FileNode {
	if len(files) == 0 {
		return FileNode{
			Name:     "empty",
			Path:     basePath,
			IsDir:    true,
			Children: []FileNode{},
		}
	}
	
	// If we have multiple files, create a root node
	if len(files) > 1 {
		var children []FileNode
		for _, file := range files {
			children = append(children, convertSingleFileInfo(file))
		}
		
		return FileNode{
			Name:     "project",
			Path:     basePath,
			IsDir:    true,
			Children: children,
		}
	}
	
	// Single file/directory
	return convertSingleFileInfo(files[0])
}

// convertSingleFileInfo converts a single Phoenix FileInfo to UI FileNode
func convertSingleFileInfo(file phoenix.FileInfo) FileNode {
	var children []FileNode
	for _, child := range file.Children {
		children = append(children, convertSingleFileInfo(child))
	}
	
	return FileNode{
		Name:     file.Name,
		Path:     file.Path,
		IsDir:    file.IsDir,
		Children: children,
	}
}

// handleCommand processes ExecuteCommandMsg
func (m Model) handleCommand(msg ExecuteCommandMsg) (Model, tea.Cmd) {
	switch msg.Command {
	case "help":
		m.modal.ShowHelp()
		return m, nil
		
	case "settings":
		// Set available themes before showing settings
		m.settingsModal.SetAvailableThemes(m.GetAvailableThemes())
		
		m.settingsModal.ShowSettings(func(settings Settings, saved bool) {
			if saved {
				// Apply settings
				m.editor.ShowLineNumbers = settings.ShowLineNumbers
				
				// Apply theme change
				if m.SetTheme(settings.Theme) {
					m.statusBar = fmt.Sprintf("Settings saved - Theme: %s", settings.Theme)
				} else {
					m.statusBar = "Settings saved"
				}
			}
		})
		return m, nil
		
	case "new_file":
		m.modal.ShowInput(
			"New File",
			"Enter the file name:",
			"example.go",
			func(result ModalResult) {
				if !result.Canceled && result.Input != "" {
					// TODO: Create new file
					m.statusBar = fmt.Sprintf("Creating file: %s", result.Input)
				}
			},
		)
		return m, nil
		
	case "analyze":
		if m.currentFile != "" && m.phoenixClient != nil {
			m.statusBar = fmt.Sprintf("Analyzing %s...", m.currentFile)
			return m, m.phoenixClient.AnalyzeFile(m.currentFile, "full")
		}
		return m, nil
		
	case "generate":
		m.modal.ShowInput(
			"Generate Code",
			"What would you like to generate?",
			"Create a function that...",
			func(result ModalResult) {
				if !result.Canceled && result.Input != "" && m.phoenixClient != nil {
					m.statusBar = "Generating code..."
					m.phoenixClient.GenerateCode(result.Input, map[string]any{
						"file": m.currentFile,
						"language": m.detectLanguage(m.currentFile),
					})
				}
			},
		)
		return m, nil
		
	case "clear_output":
		m.output.SetContent("")
		m.statusBar = "Output cleared"
		return m, nil
		
	case "performance_stats":
		stats := m.GetPerformanceStats()
		if stats != nil {
			avgRender := stats["avg_render_time"]
			avgUpdate := stats["avg_update_time"]
			m.output.SetContent(fmt.Sprintf("Performance Statistics:\nAverage Render Time: %v\nAverage Update Time: %v\nRender Samples: %v\nUpdate Samples: %v", 
				avgRender, avgUpdate, stats["render_samples"], stats["update_samples"]))
			m.statusBar = "Performance statistics displayed"
		} else {
			m.statusBar = "Performance monitoring not available"
		}
		return m, nil
		
	case "clear_cache":
		m.ClearViewCache()
		m.statusBar = "View cache cleared"
		return m, nil
		
	case "toggle_theme":
		currentTheme := m.themeManager.GetCurrentThemeName()
		if currentTheme == "dark" {
			m.themeManager.SetTheme("light")
			m.statusBar = "Switched to light theme"
		} else {
			m.themeManager.SetTheme("dark")
			m.statusBar = "Switched to dark theme"
		}
		return m, nil
		
	default:
		m.statusBar = fmt.Sprintf("Unknown command: %s", msg.Command)
		return m, nil
	}
}

// detectLanguage detects the programming language from file extension
func (m Model) detectLanguage(path string) string {
	// Simple detection based on extension
	if strings.HasSuffix(path, ".go") {
		return "go"
	} else if strings.HasSuffix(path, ".js") {
		return "javascript"
	} else if strings.HasSuffix(path, ".py") {
		return "python"
	}
	return "text"
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