package ui

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/rubber_duck/tui/internal/phoenix"
	"github.com/rubber_duck/tui/internal/commands"
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
		case "ctrl+f":
			// Toggle file tree
			m.showFileTree = !m.showFileTree
			if m.showFileTree {
				m.statusBar = "File tree shown"
			} else {
				m.statusBar = "File tree hidden"
			}
			return m, nil
		case "ctrl+e":
			// Toggle editor
			m.showEditor = !m.showEditor
			if m.showEditor {
				m.statusBar = "Editor shown"
			} else {
				m.statusBar = "Editor hidden"
			}
			return m, nil
		case "ctrl+/":
			// Focus chat input
			m.activePane = ChatPane
			m.statusBar = "Chat focused"
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
		case ChatPane:
			// Update chat component
			var cmd tea.Cmd
			chatModel, cmd := m.chat.Update(msg)
			m.chat = chatModel.(*Chat)
			if cmd != nil {
				cmds = append(cmds, cmd)
			}
		case FileTreePane:
			if m.showFileTree {
				var cmd tea.Cmd
				m.fileTree, cmd = m.fileTree.Update(msg)
				if cmd != nil {
					cmds = append(cmds, cmd)
				}
			}
		case EditorPane:
			if m.showEditor {
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
			}
		case OutputPane:
			// Output pane is deprecated, but keep for compatibility
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
	
	case ExecuteCommandMsg:
		// Handle legacy command execution
		return m.handleCommand(msg)
	
	// Handle unified command system messages
	case ShowHelpMsg:
		m.modal.ShowHelp()
		if msg.Topic != "general" {
			m.statusBar = fmt.Sprintf("Showing help for: %s", msg.Topic)
		}
		return m, nil
	
	case ShowSettingsMsg:
		m.settingsModal.SetAvailableThemes(m.GetAvailableThemes())
		m.settingsModal.ShowSettings(func(settings Settings, saved bool) {
			if saved {
				m.editor.ShowLineNumbers = settings.ShowLineNumbers
				if m.SetTheme(settings.Theme) {
					m.statusBar = fmt.Sprintf("Settings saved - Theme: %s", settings.Theme)
				} else {
					m.statusBar = "Settings saved"
				}
			}
		})
		if msg.Tab != "general" {
			m.statusBar = fmt.Sprintf("Opening settings tab: %s", msg.Tab)
		}
		return m, nil
	
	case ToggleThemeMsg:
		currentTheme := m.themeManager.GetCurrentThemeName()
		if currentTheme == "dark" {
			m.themeManager.SetTheme("light")
			m.statusBar = "Switched to light theme"
		} else {
			m.themeManager.SetTheme("dark")
			m.statusBar = "Switched to dark theme"
		}
		return m, nil
	
	case ClearOutputMsg:
		m.output.SetContent("")
		m.statusBar = "Output cleared"
		return m, nil
	
	case ShowPerformanceStatsMsg:
		stats := m.GetPerformanceStats()
		if stats != nil {
			avgRender := stats["avg_render_time"]
			avgUpdate := stats["avg_update_time"]
			if msg.Detailed {
				m.output.SetContent(fmt.Sprintf("Detailed Performance Statistics:\nAverage Render Time: %v\nAverage Update Time: %v\nRender Samples: %v\nUpdate Samples: %v\nMemory Usage: %v\nGoroutines: %v", 
					avgRender, avgUpdate, stats["render_samples"], stats["update_samples"], "N/A", "N/A"))
			} else {
				m.output.SetContent(fmt.Sprintf("Performance Statistics:\nAverage Render Time: %v\nAverage Update Time: %v", avgRender, avgUpdate))
			}
			m.statusBar = "Performance statistics displayed"
		} else {
			m.statusBar = "Performance monitoring not available"
		}
		return m, nil
	
	case ClearCacheMsg:
		m.ClearViewCache()
		if msg.CacheType == "all" {
			m.statusBar = "All caches cleared"
		} else {
			m.statusBar = fmt.Sprintf("%s cache cleared", msg.CacheType)
		}
		return m, nil
	
	case ShowInputModalMsg:
		m.modal.ShowInput(msg.Title, msg.Prompt, msg.Placeholder, func(result ModalResult) {
			if !result.Canceled && result.Input != "" {
				// Handle the input based on action
				switch msg.Action {
				case "create_file":
					m.statusBar = fmt.Sprintf("Creating file: %s", result.Input)
				default:
					m.statusBar = fmt.Sprintf("Input received: %s", result.Input)
				}
			}
		})
		return m, nil
	
	case SaveFileMsg:
		if msg.Path != "" {
			// TODO: Implement actual file saving logic
			m.statusBar = fmt.Sprintf("Saving file: %s", msg.Path)
			if msg.Force {
				m.statusBar += " (forced)"
			}
		} else {
			m.statusBar = "Cannot save: no file path specified"
		}
		return m, nil
	
	case CloseFileMsg:
		if msg.Path != "" {
			if msg.Save {
				m.statusBar = fmt.Sprintf("Saving and closing file: %s", msg.Path)
			} else {
				m.statusBar = fmt.Sprintf("Closing file without saving: %s", msg.Path)
			}
			// TODO: Implement actual file closing logic
			m.editor.SetValue("")
			m.currentFile = ""
		} else {
			m.statusBar = "No file to close"
		}
		return m, nil
	
	case FocusPaneMsg:
		switch msg.Pane {
		case "editor":
			m.activePane = EditorPane
		case "filetree", "tree":
			m.activePane = FileTreePane
		case "output":
			m.activePane = OutputPane
		case "next":
			m.activePane = m.nextPane()
		default:
			m.activePane = m.nextPane() // fallback to next
		}
		m.statusBar = fmt.Sprintf("Focused pane: %s", msg.Pane)
		return m, nil
	
	case ShowSearchMsg:
		// TODO: Implement search functionality
		m.statusBar = fmt.Sprintf("Searching for: %s", msg.Query)
		if msg.Scope != "current_file" {
			m.statusBar += fmt.Sprintf(" (scope: %s)", msg.Scope)
		}
		return m, nil
	
	case GotoLineMsg:
		// TODO: Implement goto line functionality
		m.statusBar = fmt.Sprintf("Going to line: %d", msg.Line)
		return m, nil
	
	case ShowCommandPaletteMsg:
		m.commandPalette.Show()
		if msg.Filter != "" {
			m.statusBar = fmt.Sprintf("Command palette opened with filter: %s", msg.Filter)
		} else {
			m.statusBar = "Command palette opened"
		}
		return m, nil
	
	// Handle chat messages
	case ChatMessageSentMsg:
		// Add user message to chat
		m.chat.AddMessage(UserMessage, msg.Content, "user")
		
		// Route through command system
		if router := m.commandPalette.GetCommandRouter(); router != nil {
			// Check if it's a command (starts with /)
			if strings.HasPrefix(msg.Content, "/") {
				// Parse command
				parts := strings.Fields(msg.Content[1:]) // Remove /
				if len(parts) > 0 {
					commandName := parts[0]
					args := make(map[string]interface{})
					if len(parts) > 1 {
						args["args"] = strings.Join(parts[1:], " ")
					}
					
					// Execute command
					cmdResult := router.ExecuteCommand(commandName, args, m.buildChatContext())
					if cmdResult != nil {
						cmds = append(cmds, cmdResult)
					}
				}
			} else {
				// Regular chat message - send to server
				args := map[string]interface{}{
					"message": msg.Content,
				}
				cmdResult := router.ExecuteCommand("chat", args, m.buildChatContext())
				if cmdResult != nil {
					cmds = append(cmds, cmdResult)
				}
			}
		}
		m.statusBar = "Message sent"
		return m, tea.Batch(cmds...)
	
	case ChatMessageReceivedMsg:
		// Add received message to chat
		var msgType MessageType
		switch msg.Type {
		case "assistant":
			msgType = AssistantMessage
		case "system":
			msgType = SystemMessage
		case "error":
			msgType = ErrorMessage
		default:
			msgType = AssistantMessage
		}
		
		m.chat.AddMessage(msgType, msg.Content, msg.Type)
		m.statusBar = "Message received"
		return m, nil
	
	case ToggleFileTreeMsg:
		m.showFileTree = !m.showFileTree
		if m.showFileTree {
			m.statusBar = "File tree shown"
		} else {
			m.statusBar = "File tree hidden"
		}
		return m, nil
	
	case ToggleEditorMsg:
		m.showEditor = !m.showEditor
		if m.showEditor {
			m.statusBar = "Editor shown"
		} else {
			m.statusBar = "Editor hidden"
		}
		return m, nil
	
	// Handle unified command system response messages
	case UnsolicitedResponseMsg:
		m.statusBar = "Received unsolicited response from server"
		// TODO: Handle based on response type
		return m, nil
	
	case CommandCompletedMsg:
		m.statusBar = fmt.Sprintf("Command '%s' completed in %v", msg.Command, msg.Duration)
		if msg.Content != nil {
			// Display content in output panel
			content := fmt.Sprintf("Command: %s\nResult: %v\n\n", msg.Command, msg.Content)
			m.output.SetContent(m.output.View() + content)
		}
		return m, nil
	
	case CommandErrorMsg:
		m.statusBar = fmt.Sprintf("Command '%s' failed", msg.Command)
		if msg.Error != nil {
			error := fmt.Sprintf("Error in command '%s': %v\n\n", msg.Command, msg.Error)
			m.output.SetContent(m.output.View() + error)
		}
		return m, nil
	
	case CommandStreamingMsg:
		m.statusBar = fmt.Sprintf("Streaming data from command '%s'", msg.Command)
		if msg.Content != nil {
			content := fmt.Sprintf("%v", msg.Content)
			m.output.SetContent(m.output.View() + content)
		}
		return m, nil
	
	case CommandStatusMsg:
		m.statusBar = fmt.Sprintf("Command '%s' status: %s", msg.Command, msg.Status)
		if msg.Content != nil {
			content := fmt.Sprintf("Status update for '%s': %v\n", msg.Command, msg.Content)
			m.output.SetContent(m.output.View() + content)
		}
		return m, nil
	
	case RetryCommandMsg:
		m.statusBar = fmt.Sprintf("Retrying command (attempt %d/%d)", msg.AttemptNum, msg.MaxRetries)
		// TODO: Re-execute the command through the router
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

// nextPane cycles to the next visible pane
func (m Model) nextPane() Pane {
	switch m.activePane {
	case ChatPane:
		if m.showFileTree {
			return FileTreePane
		} else if m.showEditor {
			return EditorPane
		}
		return ChatPane
	case FileTreePane:
		if m.showEditor {
			return EditorPane
		}
		return ChatPane
	case EditorPane:
		return ChatPane
	case OutputPane:
		// Deprecated pane
		return ChatPane
	}
	return ChatPane
}

// buildChatContext creates a context for chat commands
func (m Model) buildChatContext() interface{} {
	return map[string]interface{}{
		"current_file":   m.currentFile,
		"editor_content": m.editor.Value(),
		"show_file_tree": m.showFileTree,
		"show_editor":    m.showEditor,
		"connected":      m.connected,
	}
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