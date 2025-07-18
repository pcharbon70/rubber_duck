package ui

import (
	"fmt"
	
	tea "github.com/charmbracelet/bubbletea"
)

// Update handles all state transitions
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	// Handle global keys first
	switch msg := msg.(type) {
	case tea.KeyMsg:
		// Check if modal is visible
		if m.modal.IsVisible() {
			var cmd tea.Cmd
			m.modal, cmd = m.modal.Update(msg)
			return m, cmd
		}
		
		// Check if command palette is visible
		if m.commandPalette.IsVisible() {
			switch msg.String() {
			case "esc":
				m.commandPalette.Hide()
				return m, nil
			}
			var cmd tea.Cmd
			m.commandPalette, cmd = m.commandPalette.Update(msg)
			return m, cmd
		}
		
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
			m.modal = Modal{
				modalType: HelpModal,
				title:     "Help",
				content:   "RubberDuck TUI Help\n\nKeyboard Shortcuts:\n- Ctrl+P: Command palette\n- Ctrl+H: This help\n- Tab: Switch panes\n- Ctrl+F: Toggle file tree\n- Ctrl+E: Toggle editor\n- Ctrl+/: Focus chat",
				visible:   true,
			}
			return m, nil
		case "ctrl+f":
			m.showFileTree = !m.showFileTree
			m.updateComponentSizes()
			if m.showFileTree {
				m.statusBar = "File tree shown"
			} else {
				m.statusBar = "File tree hidden"
			}
			return m, nil
		case "ctrl+e":
			m.showEditor = !m.showEditor
			m.updateComponentSizes()
			if m.showEditor {
				m.statusBar = "Editor shown"
			} else {
				m.statusBar = "Editor hidden"
			}
			return m, nil
		case "ctrl+/":
			m.activePane = ChatPane
			m.chat.Focus()
			m.statusBar = "Chat focused"
			return m, nil
		}
		
		// Handle pane-specific input
		switch m.activePane {
		case ChatPane:
			// Update chat component
			chatModel, cmd := m.chat.Update(msg)
			if chat, ok := chatModel.(Chat); ok {
				m.chat = &chat
			}
			cmds = append(cmds, cmd)
		case FileTreePane:
			if m.showFileTree {
				var cmd tea.Cmd
				ft, cmd := m.fileTree.Update(msg)
				m.fileTree = &ft
				cmds = append(cmds, cmd)
			}
		case EditorPane:
			if m.showEditor {
				var cmd tea.Cmd
				m.editor, cmd = m.editor.Update(msg)
				cmds = append(cmds, cmd)
			}
		}
		
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.updateComponentSizes()
		return m, nil
		
	case InitiateConnectionMsg:
		m.statusBar = "Connecting to Phoenix..."
		// TODO: Implement Phoenix connection
		return m, nil
		
	case ConnectedMsg:
		m.connected = true
		m.statusBar = "Connected to Phoenix | " + m.getKeyHints()
		return m, nil
		
	case DisconnectedMsg:
		m.connected = false
		m.statusBar = fmt.Sprintf("Disconnected: %v", msg.Error)
		return m, nil
		
	case ChatMessageSentMsg:
		// Send message through Phoenix channel
		m.chat.AddMessage(UserMessage, msg.Content, "user")
		m.statusBar = "Sending message..."
		// TODO: Send through Phoenix channel
		return m, nil
		
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
		
	case FileSelectedMsg:
		m.currentFile = msg.Path
		m.statusBar = fmt.Sprintf("Loading %s...", msg.Path)
		// TODO: Load file content
		return m, nil
		
	case ErrorMsg:
		m.err = msg.Err
		m.statusBar = fmt.Sprintf("Error in %s: %v", msg.Component, msg.Err)
		return m, nil
		
	case ExecuteCommandMsg:
		return m.handleCommand(msg)
	}
	
	// Update child components
	switch m.activePane {
	case ChatPane:
		if _, ok := msg.(tea.KeyMsg); !ok {
			chatModel, cmd := m.chat.Update(msg)
			if chat, ok := chatModel.(Chat); ok {
				m.chat = &chat
			}
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
	default:
		return ChatPane
	}
}

// getKeyHints returns context-sensitive key hints
func (m Model) getKeyHints() string {
	base := "Tab: Switch Pane | Ctrl+P: Commands | Ctrl+H: Help"
	
	switch m.activePane {
	case ChatPane:
		return "Enter: Send | Ctrl+Enter: Newline | " + base
	case FileTreePane:
		return "↑↓/jk: Navigate | Enter: Select | " + base
	case EditorPane:
		return "Type to edit | " + base
	}
	
	return base
}

// handleCommand processes command execution
func (m Model) handleCommand(msg ExecuteCommandMsg) (Model, tea.Cmd) {
	switch msg.Command {
	case "help":
		m.modal = Modal{
			modalType: HelpModal,
			title:     "Help",
			content:   "RubberDuck TUI Help",
			visible:   true,
		}
	case "toggle_tree":
		m.showFileTree = !m.showFileTree
		m.updateComponentSizes()
	case "toggle_editor":
		m.showEditor = !m.showEditor
		m.updateComponentSizes()
	case "focus_chat":
		m.activePane = ChatPane
		m.chat.Focus()
	case "new_conversation":
		// TODO: Implement new conversation
		m.statusBar = "Starting new conversation..."
	}
	
	return m, nil
}