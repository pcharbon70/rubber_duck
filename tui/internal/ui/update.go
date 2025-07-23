package ui

import (
	"encoding/json"
	"fmt"
	"time"
	
	tea "github.com/charmbracelet/bubbletea"
	"github.com/rubber_duck/tui/internal/phoenix"
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
				content:   m.buildHelpContent(),
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
		case "ctrl+r":
			// Reconnect with backoff
			return m.handleReconnect()
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
		// Check if connection is blocked due to too many attempts
		if m.connectionBlocked {
			m.statusBar = "Connection blocked - too many failed attempts"
			return m, nil
		}
		
		// Increment total connection attempts
		m.totalConnectionAttempts++
		const maxTotalAttempts = 5
		
		// Block further connections if we've tried too many times
		if m.totalConnectionAttempts > maxTotalAttempts {
			m.connectionBlocked = true
			m.statusBar = "Connection blocked after repeated failures. Please restart TUI."
			m.statusMessages.AddMessage(StatusCategoryError, fmt.Sprintf("Connection blocked after %d failed attempts. Please verify the server is running and restart the TUI.", maxTotalAttempts), nil)
			return m, nil
		}
		
		m.statusBar = fmt.Sprintf("Connecting to auth server... (attempt %d)", m.totalConnectionAttempts)
		client := m.phoenixClient.(*phoenix.Client)
		// First connect to auth socket
		config := phoenix.Config{
			URL:     m.authSocketURL,
			IsAuth:  true,
			Channel: "auth:lobby",
		}
		return m, client.Connect(config)
		
	case phoenix.ConnectedMsg:
		m.connected = true
		// Reset all connection counters on successful connection
		m.reconnectAttempts = 0
		m.totalConnectionAttempts = 0
		m.connectionBlocked = false
		
		// Check if this is auth socket or user socket
		if m.socket == nil {
			// First connection is to auth socket
			m.statusBar = "Connected to auth server - Checking authentication..."
			m.updateHeaderState()
			return m, func() tea.Msg { return phoenix.AuthConnectedMsg{} }
		} else {
			// Second connection is to user socket
			m.statusBar = "Connected to authenticated socket - Joining channels..."
			m.updateHeaderState()
			// Join conversation, status, and api_keys channels
			return m, tea.Batch(
				func() tea.Msg { return JoinConversationChannelMsg{} },
				func() tea.Msg { return JoinApiKeyChannelMsg{} },
			)
		}
		
	case phoenix.DisconnectedMsg:
		m.connected = false
		m.updateHeaderState()
		
		if msg.Error != nil {
			// Use error handler for disconnect errors
			if display, message := m.errorHandler.HandleError(msg.Error, "Connection"); display {
				m.statusBar = message
				m.statusMessages.AddMessage(StatusCategoryError, message, nil)
				
				// Add reconnection advice
				m.statusMessages.AddMessage(StatusCategoryInfo, "Connection lost. You can try reconnecting with Ctrl+R or restart the TUI.", nil)
			}
		} else {
			m.statusBar = "Disconnected"
			// Reset error handler on clean disconnect
			m.errorHandler.Reset()
		}
		return m, nil
		
	case phoenix.SocketCreatedMsg:
		// Store socket - auth socket first, then user socket
		if m.socket == nil && m.authSocket == nil {
			// First socket is auth socket
			m.authSocket = msg.Socket
		} else {
			// Second socket is user socket
			m.socket = msg.Socket
			// Update clients with new socket
			if statusClient, ok := m.statusClient.(*phoenix.StatusClient); ok {
				statusClient.SetSocket(m.socket)
			}
		}
		return m, nil
		
	case phoenix.ChannelJoinedMsg:
		m.channel = msg.Channel
		m.statusBar = m.buildStatusBar()
		return m, nil
		
	case phoenix.ChannelJoiningMsg:
		m.statusBar = "Joining conversation channel..."
		return m, nil
		
	case ChatMessageSentMsg:
		// Check if authenticated first
		if !m.authenticated {
			m.statusMessages.AddMessage(StatusCategoryError, "You must be authenticated to send messages. Use /login <username> <password>", nil)
			return m, nil
		}
		// Check if conversation channel is joined
		if m.channel == nil {
			m.statusMessages.AddMessage(StatusCategoryError, "Not connected to conversation channel", nil)
			return m, nil
		}
		// Send message through Phoenix channel
		m.chat.AddMessage(UserMessage, msg.Content, "user")
		m.messageCount = m.chat.GetMessageCount()
		// Update token usage
		m.tokenUsage = EstimateConversationTokens(m.chat.GetMessages())
		m.tokenLimit = GetModelTokenLimit(m.currentModel)
		m.updateHeaderState()
		m.statusBar = "Sending message..."
		if client, ok := m.phoenixClient.(*phoenix.Client); ok && m.connected {
			// Use the configured model if set
			if m.currentModel != "" {
				return m, client.SendMessageWithConfig(msg.Content, m.currentModel, m.temperature)
			}
			return m, client.SendMessage(msg.Content)
		}
		// If not connected, show error
		m.statusMessages.AddMessage(StatusCategoryError, "Not connected to server", nil)
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
		// Use error handler to prevent spam
		if display, message := m.errorHandler.HandleError(msg.Err, msg.Component); display {
			m.statusBar = message
			m.statusMessages.AddMessage(StatusCategoryError, message, nil)
			
			// Add connection advice if available
			if advice := GetConnectionAdvice(msg.Err); advice != "" {
				m.statusMessages.AddMessage(StatusCategoryInfo, advice, nil)
			}
		}
		return m, nil
		
	case ExecuteCommandMsg:
		return m.handleCommand(msg)
		
	// Phoenix conversation messages
	case phoenix.ConversationResponseMsg:
		// Parse the response
		var response phoenix.ConversationMessage
		if err := json.Unmarshal(msg.Response, &response); err == nil {
			m.chat.AddMessage(AssistantMessage, response.Response, "assistant")
			m.messageCount = m.chat.GetMessageCount()
			
			// Check if response includes provider info
			if response.RoutedTo != "" {
				// RoutedTo might contain provider info like "openai" or "anthropic"
				m.currentProvider = response.RoutedTo
			}
			
			// Check metadata for model/provider info
			if response.Metadata != nil {
				if provider, ok := response.Metadata["provider"].(string); ok {
					m.currentProvider = provider
				}
				if model, ok := response.Metadata["model"].(string); ok {
					m.currentModel = model
				}
			}
			
			// Update token usage
			m.tokenUsage = EstimateConversationTokens(m.chat.GetMessages())
			m.tokenLimit = GetModelTokenLimit(m.currentModel)
			m.updateHeaderState()
			m.statusBar = "Response received"
		}
		return m, nil
		
	case phoenix.ConversationThinkingMsg:
		m.statusBar = "Assistant is thinking..."
		return m, nil
		
	case phoenix.ConversationContextUpdatedMsg:
		// Parse the context update to check if model was set
		var context struct {
			Context struct {
				PreferredModel    string `json:"preferred_model"`
				PreferredProvider string `json:"preferred_provider"`
			} `json:"context"`
		}
		if err := json.Unmarshal(msg.Context, &context); err == nil {
			if context.Context.PreferredModel != "" {
				// Update model and provider from context
				m.currentModel = context.Context.PreferredModel
				m.currentProvider = context.Context.PreferredProvider
				m.updateHeaderState()
				m.statusBar = fmt.Sprintf("Model preference saved: %s", context.Context.PreferredModel)
			} else {
				m.statusBar = "Context updated"
			}
		} else {
			m.statusBar = "Context updated"
		}
		return m, nil
		
	case phoenix.ConversationResetMsg:
		// Clear chat history on reset
		m.chat = NewChat()
		chatHeight := m.height - 1 - 3 // status bar and header
		m.chat.SetSize(m.width-2, chatHeight)
		m.messageCount = 0
		m.tokenUsage = 0
		m.updateHeaderState()
		m.statusBar = "Conversation reset"
		return m, nil
		
	// Phoenix streaming messages
	case phoenix.StreamStartMsg:
		m.statusBar = "Receiving response..."
		// TODO: Could add a streaming indicator to chat
		return m, nil
		
	case phoenix.StreamDataMsg:
		// TODO: Implement streaming support in chat
		// For now, we'll wait for the complete response
		return m, nil
		
	case phoenix.StreamEndMsg:
		m.statusBar = "Response complete"
		return m, nil
		
	// Phoenix error handling
	case phoenix.ErrorMsg:
		m.err = msg.Err
		// Use error handler to prevent spam
		if display, message := m.errorHandler.HandleError(msg.Err, msg.Component); display {
			m.statusBar = message
			m.statusMessages.AddMessage(StatusCategoryError, message, nil)
			
			// Add connection advice if available
			if advice := GetConnectionAdvice(msg.Err); advice != "" {
				m.statusMessages.AddMessage(StatusCategoryInfo, advice, nil)
			}
			
			// If retry command is available, offer to retry
			if msg.Retry != nil {
				m.chat.AddMessage(SystemMessage, "You can retry this operation by pressing Ctrl+R", "system")
			}
		}
		return m, nil
		
	// Join conversation channel after authentication
	case JoinConversationChannelMsg:
		if m.authenticated {
			m.statusBar = "Joining conversation channel..."
			if client, ok := m.phoenixClient.(*phoenix.Client); ok {
				// Join conversation channel and then status channel
				return m, tea.Batch(
					client.JoinChannel("conversation:lobby"),
					func() tea.Msg { return JoinStatusChannelMsg{} },
				)
			}
		} else {
			m.statusBar = "Cannot join conversation - not authenticated"
			m.statusMessages.AddMessage(StatusCategoryError, "Authentication required to join conversation", nil)
		}
		return m, nil
		
	// Join status channel after conversation channel
	case JoinStatusChannelMsg:
		if m.authenticated {
			m.statusBar = "Joining status channel..."
			if statusClient, ok := m.statusClient.(*phoenix.StatusClient); ok {
				statusClient.SetSocket(m.socket)
				statusClient.SetProgram(m.ProgramHolder())
				// Join status channel with current conversation ID
				return m, statusClient.JoinStatusChannel(m.conversationID)
			}
		}
		return m, nil
		
	// Join API key channel for authenticated user
	case JoinApiKeyChannelMsg:
		if m.authenticated && m.userID != "" {
			m.statusBar = "Joining API key channel..."
			if apiKeyClient, ok := m.apiKeyClient.(*phoenix.ApiKeyClient); ok {
				apiKeyClient.SetSocket(m.socket)
				apiKeyClient.SetProgram(m.ProgramHolder())
				apiKeyClient.SetUserID(m.userID)
				return m, apiKeyClient.JoinApiKeyChannel()
			}
		}
		return m, nil
		
	// Switch to authenticated user socket
	case SwitchToUserSocketMsg:
		m.statusBar = "Disconnecting from auth socket..."
		// First disconnect from auth socket
		if m.authSocket != nil {
			m.authSocket.Disconnect()
			m.authSocket = nil
		}
		// Now connect to user socket with credentials
		client := m.phoenixClient.(*phoenix.Client)
		config := phoenix.Config{
			URL:      m.phoenixURL,
			APIKey:   m.apiKey,
			JWTToken: m.jwtToken,
			IsAuth:   false,
		}
		m.statusBar = "Connecting to authenticated socket..."
		return m, client.Connect(config)
		
	// Authentication messages
	case phoenix.AuthConnectedMsg:
		// Auth channel connected, join it
		if authClient, ok := m.authClient.(*phoenix.AuthClient); ok {
			authClient.SetSocket(m.authSocket)
			authClient.SetProgram(m.ProgramHolder())
			return m, authClient.JoinAuthChannel()
		}
		return m, nil
		
	case phoenix.AuthChannelJoinedMsg:
		m.statusBar = "Auth channel joined - Waiting for authentication status..."
		// The server will send auth status through channel events if needed
		// We don't need to actively request it, avoiding potential timeout errors
		return m, nil
		
	case phoenix.LoginSuccessMsg:
		m.authenticated = true
		m.username = msg.User.Username
		m.userID = msg.User.ID // Store user ID for api_keys channel
		m.jwtToken = msg.Token // Store the JWT token
		m.statusBar = fmt.Sprintf("Logged in as %s - Switching to authenticated connection...", msg.User.Username)
		m.chat.AddMessage(SystemMessage, fmt.Sprintf("Successfully logged in as %s", msg.User.Username), "system")
		m.updateHeaderState()
		// Now switch to the authenticated socket
		return m, func() tea.Msg { return SwitchToUserSocketMsg{} }
		
	case phoenix.LoginErrorMsg:
		m.statusBar = fmt.Sprintf("Login failed: %s", msg.Message)
		m.statusMessages.AddMessage(StatusCategoryError, fmt.Sprintf("Login failed: %s - %s", msg.Message, msg.Details), nil)
		return m, nil
		
	case phoenix.LogoutSuccessMsg:
		m.authenticated = false
		m.username = ""
		m.statusBar = "Logged out"
		m.chat.AddMessage(SystemMessage, msg.Message, "system")
		// Leave conversation channel when logged out
		if _, ok := m.phoenixClient.(*phoenix.Client); ok {
			// This will trigger leaving the channel
			if m.channel != nil {
				m.channel = nil
			}
		}
		return m, nil
		
	case phoenix.AuthStatusMsg:
		m.authenticated = msg.Authenticated
		if msg.Authenticated && msg.User != nil {
			m.username = msg.User.Username
			m.userID = msg.User.ID // Store user ID for api_keys channel
			// If authenticated via API key, we should switch to user socket
			if m.apiKey != "" {
				m.statusBar = fmt.Sprintf("Authenticated as %s via API key - Switching to authenticated connection...", msg.User.Username)
				m.chat.AddMessage(SystemMessage, fmt.Sprintf("Authentication status: Logged in as %s (API key)", msg.User.Username), "system")
				return m, func() tea.Msg { return SwitchToUserSocketMsg{} }
			} else {
				// Already authenticated somehow
				m.statusBar = fmt.Sprintf("Authenticated as %s - Joining conversation...", msg.User.Username)
				m.chat.AddMessage(SystemMessage, fmt.Sprintf("Authentication status: Logged in as %s", msg.User.Username), "system")
				return m, func() tea.Msg { return JoinConversationChannelMsg{} }
			}
		} else {
			m.username = ""
			m.userID = ""
			m.statusBar = "Not authenticated - Please login with /login <username> <password>"
			m.chat.AddMessage(SystemMessage, "Authentication status: Not logged in\nPlease use /login <username> <password> to authenticate", "system")
		}
		return m, nil
		
	case phoenix.APIKeyGeneratedMsg:
		m.statusBar = "API key generated"
		// Show the key and warning
		keyMsg := fmt.Sprintf("API Key Generated!\n\nKey: %s\n\n%s\n\nExpires: %s", 
			msg.APIKey.Key, 
			msg.Warning,
			msg.APIKey.ExpiresAt.Format("2006-01-02 15:04:05"))
		m.chat.AddMessage(SystemMessage, keyMsg, "system")
		return m, nil
		
	case phoenix.APIKeyListMsg:
		m.statusBar = fmt.Sprintf("Found %d API keys", msg.Count)
		// Format and display the keys
		keyList := "Your API Keys:\n\n"
		for _, key := range msg.APIKeys {
			status := "Valid"
			if !key.Valid {
				status = "Revoked"
			}
			keyList += fmt.Sprintf("ID: %s\nStatus: %s\nCreated: %s\nExpires: %s\n\n",
				key.ID,
				status,
				key.CreatedAt.Format("2006-01-02 15:04:05"),
				key.ExpiresAt.Format("2006-01-02 15:04:05"))
		}
		m.chat.AddMessage(SystemMessage, keyList, "system")
		return m, nil
		
	case phoenix.APIKeyRevokedMsg:
		m.statusBar = "API key revoked"
		m.chat.AddMessage(SystemMessage, msg.Message, "system")
		return m, nil
		
	case phoenix.APIKeyErrorMsg:
		m.statusBar = fmt.Sprintf("API key error: %s", msg.Message)
		m.statusMessages.AddMessage(StatusCategoryError, fmt.Sprintf("API key %s failed: %s - %s", msg.Operation, msg.Message, msg.Details), nil)
		return m, nil
		
	case phoenix.TokenRefreshedMsg:
		m.statusBar = "Token refreshed"
		m.chat.AddMessage(SystemMessage, "Authentication token refreshed successfully", "system")
		return m, nil
		
	case phoenix.TokenErrorMsg:
		m.statusBar = fmt.Sprintf("Token error: %s", msg.Message)
		m.statusMessages.AddMessage(StatusCategoryError, fmt.Sprintf("Token refresh failed: %s - %s", msg.Message, msg.Details), nil)
		return m, nil
		
	case phoenix.RetryMsg:
		// Execute the retry command
		return m, msg.Cmd
		
	// Status channel messages
	case phoenix.StatusChannelJoinedMsg:
		m.statusBar = "Status channel joined - Subscribing to all categories..."
		// Subscribe to all categories by default
		if statusClient, ok := m.statusClient.(*phoenix.StatusClient); ok {
			categories := []string{"engine", "tool", "workflow", "progress", "error", "info"}
			return m, statusClient.SubscribeCategories(categories)
		}
		return m, nil
		
	case phoenix.StatusCategoriesSubscribedMsg:
		m.statusBar = fmt.Sprintf("Subscribed to status categories: %v", msg.Categories)
		return m, nil
		
	case phoenix.StatusUpdateMsg:
		// Add status message to the status messages component
		m.statusMessages.AddMessage(
			StatusCategory(msg.Category),
			msg.Text,
			msg.Metadata,
		)
		return m, nil
		
	case phoenix.StatusSubscriptionsMsg:
		m.statusBar = fmt.Sprintf("Status subscriptions - Active: %v, Available: %v", msg.Subscribed, msg.Available)
		return m, nil
		
	// API key channel joined
	case phoenix.ApiKeyChannelJoinedMsg:
		m.statusBar = "API key channel joined - Ready for API key management"
		return m, nil
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

// buildHelpContent builds the help modal content with all commands
func (m Model) buildHelpContent() string {
	help := "RubberDuck TUI Help\n\n"
	
	help += "KEYBOARD SHORTCUTS:\n"
	help += "━━━━━━━━━━━━━━━━━━━━━\n"
	help += "Ctrl+P    - Command palette (all commands)\n"
	help += "Ctrl+H    - This help\n"
	help += "Ctrl+R    - Reconnect to server\n"
	help += "Tab       - Switch panes\n"
	help += "Ctrl+C/q  - Quit\n\n"
	
	help += "NAVIGATION:\n"
	help += "━━━━━━━━━━━━━━━━━━━━━\n"
	help += "Ctrl+/    - Focus chat\n"
	help += "Ctrl+F    - Toggle file tree\n"
	help += "Ctrl+E    - Toggle editor\n\n"
	
	help += "CHAT:\n"
	help += "━━━━━━━━━━━━━━━━━━━━━\n"
	help += "Enter     - Send message\n"
	help += "Ctrl+Enter - New line\n"
	help += "↑/↓       - Scroll history\n\n"
	
	help += "SLASH COMMANDS:\n"
	help += "━━━━━━━━━━━━━━━━━━━━━\n"
	help += "/help     - Show this help\n"
	help += "/model    - Set AI model (e.g., /model gpt4 [provider])\n"
	help += "/provider - Set provider (e.g., /provider azure)\n"
	help += "/clear    - New conversation\n"
	help += "/tree     - Toggle file tree\n"
	help += "/editor   - Toggle editor\n"
	help += "/commands - Show command palette\n"
	help += "/login    - Login to server\n"
	help += "/logout   - Logout from server\n"
	help += "/apikey   - API key management\n"
	help += "/status   - Check auth status\n"
	help += "/quit     - Exit application\n\n"
	
	help += "MODELS (via Ctrl+P):\n"
	help += "━━━━━━━━━━━━━━━━━━━━━\n"
	help += "• Default (system default)\n"
	help += "• GPT-4, GPT-3.5 Turbo\n"
	help += "• Claude 3 Opus, Sonnet\n"
	help += "• Llama 2, Mistral, CodeLlama\n\n"
	
	help += "Current Model: "
	if m.currentModel != "" {
		help += m.currentModel
		if m.currentProvider != "" {
			help += fmt.Sprintf(" (%s)", m.currentProvider)
		}
	} else {
		help += "default"
	}
	help += "\n\n"
	
	help += "AUTHENTICATION:\n"
	help += "━━━━━━━━━━━━━━━━━━━━━\n"
	if m.authenticated {
		help += fmt.Sprintf("Logged in as: %s\n", m.username)
	} else {
		help += "Not authenticated\n"
		help += "Use /login <username> <password> to login\n"
	}
	
	return help
}

// updateHeaderState updates the chat header with current state
func (m *Model) updateHeaderState() {
	m.chatHeader.SetConnectionStatus(m.connected, m.authenticated)
	// Use actual provider if available, otherwise fall back to guessed provider
	provider := m.currentProvider
	if provider == "" {
		provider = m.getProviderForModel(m.currentModel)
	}
	m.chatHeader.SetModel(m.currentModel, provider)
	m.chatHeader.SetConversationID(m.conversationID)
	m.chatHeader.SetMessageCount(m.messageCount)
	m.chatHeader.SetTokenUsage(m.tokenUsage, m.tokenLimit)
}

// getProviderForModel returns the provider name for a model
func (m Model) getProviderForModel(model string) string {
	switch model {
	case "gpt-4", "gpt-3.5-turbo":
		return "OpenAI"
	case "claude-3-opus", "claude-3-sonnet":
		return "Anthropic"
	case "llama2", "mistral", "codellama":
		return "Ollama"
	default:
		return ""
	}
}

// buildStatusBar builds the status bar with connection and model info
func (m Model) buildStatusBar() string {
	status := ""
	
	// Connection status
	if m.connected {
		if m.channel != nil {
			status = "Connected"
		} else {
			status = "Auth Connected"
		}
	} else {
		status = "Disconnected"
	}
	
	// Add auth info
	if m.authenticated {
		status += " | User: " + m.username
	} else {
		status += " | Not authenticated"
	}
	
	// Add model info
	if m.currentModel != "" {
		status += " | Model: " + m.currentModel
	} else {
		status += " | Model: default"
	}
	
	// Add key hints
	status += " | " + m.getKeyHints()
	
	return status
}

// handleCommand processes command execution
func (m Model) handleCommand(msg ExecuteCommandMsg) (Model, tea.Cmd) {
	switch msg.Command {
	case "help":
		m.modal = Modal{
			modalType: HelpModal,
			title:     "Help",
			content:   m.buildHelpContent(),
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
		if !m.authenticated {
			m.statusMessages.AddMessage(StatusCategoryError, "You must be authenticated to start a new conversation", nil)
			return m, nil
		}
		if m.channel == nil {
			m.statusMessages.AddMessage(StatusCategoryError, "Not connected to conversation channel", nil)
			return m, nil
		}
		m.statusBar = "Starting new conversation..."
		if client, ok := m.phoenixClient.(*phoenix.Client); ok && m.connected {
			return m, client.StartNewConversation()
		}
		m.statusBar = "Not connected to server"
	
	// Model selection commands
	case "model_default":
		m.currentModel = ""
		m.currentProvider = ""
		m.updateHeaderState()
		m.statusBar = m.buildStatusBar()
		// Clear conversation context preference
		if client, ok := m.phoenixClient.(*phoenix.Client); ok && m.connected {
			return m, client.SetConversationModel("", "")
		}
	case "model_gpt4":
		m.currentModel = "gpt-4"
		m.currentProvider = "openai"
		m.updateHeaderState()
		m.statusBar = m.buildStatusBar()
		if client, ok := m.phoenixClient.(*phoenix.Client); ok && m.connected {
			return m, client.SetConversationModel("gpt-4", "openai")
		}
	case "model_gpt35":
		m.currentModel = "gpt-3.5-turbo"
		m.currentProvider = "openai"
		m.updateHeaderState()
		m.statusBar = m.buildStatusBar()
		if client, ok := m.phoenixClient.(*phoenix.Client); ok && m.connected {
			return m, client.SetConversationModel("gpt-3.5-turbo", "openai")
		}
	case "model_claude_opus":
		m.currentModel = "claude-3-opus"
		m.currentProvider = "anthropic"
		m.updateHeaderState()
		m.statusBar = m.buildStatusBar()
		if client, ok := m.phoenixClient.(*phoenix.Client); ok && m.connected {
			return m, client.SetConversationModel("claude-3-opus", "anthropic")
		}
	case "model_claude_sonnet":
		m.currentModel = "claude-3-sonnet"
		m.currentProvider = "anthropic"
		m.updateHeaderState()
		m.statusBar = m.buildStatusBar()
		if client, ok := m.phoenixClient.(*phoenix.Client); ok && m.connected {
			return m, client.SetConversationModel("claude-3-sonnet", "anthropic")
		}
	case "model_llama2":
		m.currentModel = "llama2"
		m.currentProvider = "ollama"
		m.updateHeaderState()
		m.statusBar = m.buildStatusBar()
		if client, ok := m.phoenixClient.(*phoenix.Client); ok && m.connected {
			return m, client.SetConversationModel("llama2", "ollama")
		}
	case "model_mistral":
		m.currentModel = "mistral"
		m.currentProvider = "ollama"
		m.updateHeaderState()
		m.statusBar = m.buildStatusBar()
		if client, ok := m.phoenixClient.(*phoenix.Client); ok && m.connected {
			return m, client.SetConversationModel("mistral", "ollama")
		}
	case "model_codellama":
		m.currentModel = "codellama"
		m.currentProvider = "ollama"
		m.updateHeaderState()
		m.statusBar = m.buildStatusBar()
		if client, ok := m.phoenixClient.(*phoenix.Client); ok && m.connected {
			return m, client.SetConversationModel("codellama", "ollama")
		}
		
	// Authentication commands
	case "auth_login":
		if args := msg.Args; args != nil {
			username := args["username"]
			password := args["password"]
			m.statusBar = "Logging in..."
			if authClient, ok := m.authClient.(*phoenix.AuthClient); ok {
				return m, authClient.Login(username, password)
			}
		}
		m.statusBar = "Login failed: invalid arguments"
		
	case "auth_logout":
		m.statusBar = "Logging out..."
		if authClient, ok := m.authClient.(*phoenix.AuthClient); ok {
			return m, authClient.Logout()
		}
		
	case "auth_status":
		m.statusBar = "Checking auth status..."
		m.statusMessages.AddMessage(StatusCategoryInfo, "Requesting authentication status from server...", nil)
		if authClient, ok := m.authClient.(*phoenix.AuthClient); ok {
			return m, authClient.GetStatus()
		}
		
	case "auth_apikey_generate":
		if !m.authenticated {
			m.statusMessages.AddMessage(StatusCategoryError, "You must be authenticated to manage API keys", nil)
			return m, nil
		}
		m.statusBar = "Generating API key..."
		if apiKeyClient, ok := m.apiKeyClient.(*phoenix.ApiKeyClient); ok {
			return m, apiKeyClient.GenerateAPIKey(nil)
		}
		
	case "auth_apikey_list":
		if !m.authenticated {
			m.statusMessages.AddMessage(StatusCategoryError, "You must be authenticated to manage API keys", nil)
			return m, nil
		}
		m.statusBar = "Listing API keys..."
		if apiKeyClient, ok := m.apiKeyClient.(*phoenix.ApiKeyClient); ok {
			return m, apiKeyClient.ListAPIKeys()
		}
		
	case "auth_apikey_revoke":
		if !m.authenticated {
			m.statusMessages.AddMessage(StatusCategoryError, "You must be authenticated to manage API keys", nil)
			return m, nil
		}
		if args := msg.Args; args != nil {
			keyID := args["id"]
			m.statusBar = "Revoking API key..."
			if apiKeyClient, ok := m.apiKeyClient.(*phoenix.ApiKeyClient); ok {
				return m, apiKeyClient.RevokeAPIKey(keyID)
			}
		}
		m.statusBar = "Revoke failed: missing key ID"
		
	// Provider and model commands
	case "set_provider":
		if args := msg.Args; args != nil {
			provider := args["provider"]
			if provider != "" {
				m.currentProvider = provider
				m.updateHeaderState()
				m.statusBar = fmt.Sprintf("Provider set to: %s", provider)
				m.chat.AddMessage(SystemMessage, fmt.Sprintf("Provider set to: %s", provider), "system")
				
				// Update conversation context with new provider
				if client, ok := m.phoenixClient.(*phoenix.Client); ok && m.connected && m.channel != nil {
					return m, client.SetConversationModel(m.currentModel, provider)
				}
			}
		}
		
	case "set_model_with_provider":
		if args := msg.Args; args != nil {
			model := args["model"]
			provider := args["provider"]
			if model != "" && provider != "" {
				m.currentModel = model
				m.currentProvider = provider
				m.tokenLimit = GetModelTokenLimit(model)
				m.updateHeaderState()
				m.statusBar = fmt.Sprintf("Model set to: %s (%s)", model, provider)
				m.chat.AddMessage(SystemMessage, fmt.Sprintf("Model set to: %s\nProvider set to: %s", model, provider), "system")
				
				// Update conversation context
				if client, ok := m.phoenixClient.(*phoenix.Client); ok && m.connected && m.channel != nil {
					return m, client.SetConversationModel(model, provider)
				}
			}
		}
	}
	
	return m, nil
}

// handleReconnect attempts to reconnect with exponential backoff
func (m *Model) handleReconnect() (Model, tea.Cmd) {
	now := time.Now()
	const maxReconnectAttempts = 3
	
	// Calculate backoff duration
	timeSinceLastAttempt := now.Sub(m.lastReconnectTime)
	
	// Reset attempts if it's been more than 5 minutes
	if timeSinceLastAttempt > 5*time.Minute {
		m.reconnectAttempts = 0
	}
	
	// Check if we've exceeded maximum attempts
	if m.reconnectAttempts >= maxReconnectAttempts {
		m.statusBar = "Maximum reconnection attempts reached. Please check server and restart TUI."
		m.statusMessages.AddMessage(StatusCategoryError, fmt.Sprintf("Failed to reconnect after %d attempts. Please verify the server is running and restart the TUI.", maxReconnectAttempts), nil)
		return *m, nil
	}
	
	// Calculate backoff: 1s, 2s, 4s, 8s, 16s, 32s, max 60s
	backoffSeconds := 1 << m.reconnectAttempts
	if backoffSeconds > 60 {
		backoffSeconds = 60
	}
	backoffDuration := time.Duration(backoffSeconds) * time.Second
	
	// Check if we should wait before reconnecting
	if timeSinceLastAttempt < backoffDuration {
		waitTime := backoffDuration - timeSinceLastAttempt
		m.statusBar = fmt.Sprintf("Please wait %v before reconnecting", waitTime.Round(time.Second))
		m.chat.AddMessage(SystemMessage, fmt.Sprintf("Reconnection cooldown: please wait %v", waitTime.Round(time.Second)), "system")
		return *m, nil
	}
	
	// Reset error handler for fresh start
	m.errorHandler.Reset()
	
	// Disconnect existing connections
	if m.authSocket != nil {
		m.authSocket.Disconnect()
		m.authSocket = nil
	}
	if m.socket != nil {
		m.socket.Disconnect()
		m.socket = nil
	}
	
	// Reset connection state
	m.connected = false
	m.authenticated = false
	m.channel = nil
	
	// Update reconnect tracking
	m.reconnectAttempts++
	m.lastReconnectTime = now
	
	m.statusBar = fmt.Sprintf("Reconnecting... (attempt %d)", m.reconnectAttempts)
	m.chat.AddMessage(SystemMessage, fmt.Sprintf("Initiating reconnection (attempt %d)...", m.reconnectAttempts), "system")
	
	// Initiate new connection
	return *m, func() tea.Msg { return InitiateConnectionMsg{} }
}