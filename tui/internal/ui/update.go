package ui

import (
	"encoding/json"
	"fmt"
	"time"
	
	"github.com/atotto/clipboard"
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
		case "ctrl+c", "ctrl+q":
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
		case "ctrl+a":
			// Copy all conversation history
			content := m.chat.GetAllMessagesPlainText()
			if content != "" {
				if err := clipboard.WriteAll(content); err != nil {
					m.statusMessages.AddMessage(StatusCategoryError, fmt.Sprintf("Failed to copy: %v", err), nil)
				} else {
					m.statusBar = "Copied all messages to clipboard"
					m.chat.AddMessage(SystemMessage, "All messages copied to clipboard", "system")
				}
			} else {
				m.statusBar = "No messages to copy"
			}
			return m, nil
		case "ctrl+l":
			// Copy last assistant message
			content := m.chat.GetLastAssistantMessage()
			if content != "" {
				if err := clipboard.WriteAll(content); err != nil {
					m.statusMessages.AddMessage(StatusCategoryError, fmt.Sprintf("Failed to copy: %v", err), nil)
				} else {
					m.statusBar = "Copied last assistant message to clipboard"
					m.chat.AddMessage(SystemMessage, "Last assistant message copied to clipboard", "system")
				}
			} else {
				m.statusBar = "No assistant message to copy"
			}
			return m, nil
		case "ctrl+t":
			// Toggle mouse mode info
			return m, func() tea.Msg { return ToggleMouseModeMsg{} }
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
		
	case ToggleMouseModeMsg:
		// Toggle mouse mode state (for display purposes)
		m.mouseEnabled = !m.mouseEnabled
		if m.mouseEnabled {
			m.statusBar = "Mouse mode is currently enabled"
			m.chat.AddMessage(SystemMessage, "Mouse mode is currently ENABLED. You cannot select text but can scroll with the mouse wheel. To disable mouse mode, restart the TUI without the --mouse flag.", "system")
		} else {
			m.statusBar = "Text selection mode is active" 
			m.chat.AddMessage(SystemMessage, "Text selection is currently ENABLED. You can select and copy text with your mouse (Ctrl+Shift+C to copy). To enable mouse scrolling, restart the TUI with the --mouse flag:\n\n./rubber_duck_tui --mouse", "system")
		}
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
		// Reset all connection counters on successful connection
		m.reconnectAttempts = 0
		m.totalConnectionAttempts = 0
		m.connectionBlocked = false
		
		// Update connection status based on socket type
		if msg.SocketType == phoenix.AuthSocketType {
			// Auth socket connected
			m.connected = true
			m.statusBar = "Connected to auth server - Checking authentication..."
			m.updateHeaderState()
			return m, func() tea.Msg { return phoenix.AuthConnectedMsg{} }
		} else {
			// User socket connected
			m.connected = true
			m.switchingSocket = false // Clear the switching flag
			m.statusBar = "Connected to authenticated socket - Joining channels..."
			m.updateHeaderState()
			// Join conversation, status, api_keys, and planning channels
			return m, tea.Batch(
				func() tea.Msg { return JoinConversationChannelMsg{} },
				func() tea.Msg { return JoinApiKeyChannelMsg{} },
				func() tea.Msg { return JoinPlanningChannelMsg{} },
			)
		}
		
	case phoenix.DisconnectedMsg:
		// Handle disconnection based on socket type and switching state
		if msg.SocketType == phoenix.AuthSocketType {
			// Auth socket disconnected
			if !m.switchingSocket {
				// Only set disconnected if we're not switching to user socket
				m.connected = false
			}
			// If we're switching, keep m.connected true since we're about to connect to user socket
		} else {
			// User socket disconnected - always set disconnected
			m.connected = false
			m.switchingSocket = false // Clear switching flag if set
		}
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
		// Store socket based on authenticated state
		if !m.authenticated {
			// Before authentication, we're creating auth socket
			m.authSocket = msg.Socket
		} else {
			// After authentication, we're creating user socket
			m.socket = msg.Socket
			// Update clients with new socket
			if statusClient, ok := m.statusClient.(*phoenix.StatusClient); ok {
				statusClient.SetSocket(m.socket)
			}
		}
		return m, nil
		
	case phoenix.ChannelJoinedMsg:
		m.channel = msg.Channel
		
		// Check if this is the conversation channel join response
		if msg.Channel != nil && msg.Response != nil {
			// Extract conversation_id and history from the response
			if respMap, ok := msg.Response.(map[string]any); ok {
				if convID, ok := respMap["conversation_id"].(string); ok {
					m.conversationID = convID
					m.chatHeader.SetConversationID(convID)
					m.statusBar = fmt.Sprintf("Joined conversation %s", convID)
					
					// Don't request history immediately - wait for channel to be fully ready
					// Just join the status channel
					if statusClient, ok := m.statusClient.(*phoenix.StatusClient); ok {
						statusClient.SetSocket(m.socket)
						statusClient.SetProgram(m.ProgramHolder())
						return m, statusClient.JoinStatusChannel(m.conversationID)
					}
				}
			}
		}
		
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
		// Check if provider and model are set
		if m.currentProvider == "" || m.currentModel == "" {
			m.statusMessages.AddMessage(StatusCategoryError, "Please set both provider and model before sending messages. Use /provider <name> and /model <name>", nil)
			m.chat.AddMessage(SystemMessage, "Please configure your LLM:\n• Use /provider <name> to set the provider\n• Use /model <name> to set the model\n\nExample:\n/provider openai\n/model gpt-4", "system")
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
		m.isProcessing = true // Mark as processing
		if client, ok := m.phoenixClient.(*phoenix.Client); ok && m.connected {
			// Always send with provider and model configuration
			return m, client.SendMessageWithConfig(msg.Content, m.currentModel, m.currentProvider, m.temperature)
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
		
	case CancelRequestMsg:
		// Only process cancel if we're currently processing
		if m.isProcessing {
			m.statusBar = "Cancelling..."
			if client, ok := m.phoenixClient.(*phoenix.Client); ok && m.connected {
				return m, client.CancelProcessing()
			}
		}
		return m, nil
		
	case ProcessingCancelledMsg:
		m.isProcessing = false
		m.statusBar = "Request cancelled"
		m.chat.AddMessage(SystemMessage, "Request cancelled by user", "system")
		return m, nil
		
	// Phoenix conversation messages
	case phoenix.ConversationResponseMsg:
		// Parse the response
		var response phoenix.ConversationMessage
		if err := json.Unmarshal(msg.Response, &response); err == nil {
			// Use response handler to format the response based on conversation type
			formattedResponse := m.responseHandlers.FormatResponse(response)
			
			// Add formatted response to chat
			m.chat.AddMessage(AssistantMessage, formattedResponse, "assistant")
			m.messageCount = m.chat.GetMessageCount()
			
			// Note: Provider and model info from responses should NOT override user settings
			// Only explicit user commands should change these values
			
			// Update token usage
			m.tokenUsage = EstimateConversationTokens(m.chat.GetMessages())
			m.tokenLimit = GetModelTokenLimit(m.currentModel)
			m.updateHeaderState()
			
			// Update status bar with conversation type
			if response.ConversationType != "" {
				m.statusBar = fmt.Sprintf("Response received (%s)", response.ConversationType)
			} else {
				m.statusBar = "Response received"
			}
			m.isProcessing = false // Clear processing state
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
			// Note: Context updates should not override user-selected model/provider
			// Only show that the server has acknowledged the preference
			if context.Context.PreferredModel != "" {
				m.statusBar = fmt.Sprintf("Server acknowledged model preference: %s", context.Context.PreferredModel)
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
		
	case phoenix.ConversationHistoryMsg:
		// Clear system message
		m.systemMessage = ""
		
		// Clear existing messages first
		m.chat.ClearMessages()
		
		// Process history messages
		if messages, ok := msg.Messages.([]any); ok && len(messages) > 0 {
			m.statusBar = fmt.Sprintf("Loading %d messages from history...", len(messages))
			
			// Add each historical message
			for _, msgData := range messages {
				if msgMap, ok := msgData.(map[string]any); ok {
					// Extract message fields
					content, _ := msgMap["content"].(string)
					role, _ := msgMap["role"].(string)
					
					// Map role to message type
					var msgType MessageType
					switch role {
					case "user":
						msgType = UserMessage
					case "assistant":
						msgType = AssistantMessage
					case "system":
						msgType = SystemMessage
					default:
						msgType = SystemMessage
					}
					
					// Add message to chat
					m.chat.AddMessage(msgType, content, role)
				}
			}
			
			// Update message count and token usage
			m.messageCount = m.chat.GetMessageCount()
			m.tokenUsage = EstimateConversationTokens(m.chat.GetMessages())
			m.chatHeader.SetMessageCount(m.messageCount)
			m.chatHeader.SetTokenUsage(m.tokenUsage, m.tokenLimit)
			
			m.statusBar = fmt.Sprintf("Loaded %d messages from history", len(messages))
		} else {
			m.statusBar = "No conversation history found"
		}
		
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
		m.isProcessing = false // Clear processing state on error
		// Use error handler to prevent spam
		if display, message := m.errorHandler.HandleError(msg.Err, msg.Component); display {
			m.statusBar = message
			m.statusMessages.AddMessage(StatusCategoryError, message, nil)
			
			// Also show API key channel errors in chat for debugging
			if msg.Component == "ApiKey Client" {
				m.chat.AddMessage(ErrorMessage, fmt.Sprintf("API Key Client Error: %s", message), "system")
			}
			
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
		
	// Planning channel messages
	case phoenix.PlanningChannelJoinedMsg:
		m.statusBar = "Planning channel joined"
		return m, nil
		
	case phoenix.PlanningStartedMsg:
		// Parse planning started data
		var data map[string]any
		if err := json.Unmarshal(msg.Data, &data); err == nil {
			if sessionID, ok := data["session_id"].(string); ok {
				m.chat.AddMessage(SystemMessage, fmt.Sprintf("Planning session started (ID: %s)", sessionID), "planning")
			}
		}
		m.statusMessages.AddMessage(StatusCategoryInfo, "Planning started", nil)
		return m, nil
		
	case phoenix.PlanningStepMsg:
		// Parse planning step data
		var data map[string]any
		if err := json.Unmarshal(msg.Data, &data); err == nil {
			stepID := data["step_id"]
			stepType := data["type"]
			description := data["description"]
			
			stepMsg := fmt.Sprintf("Planning Step: %s\nType: %s\nDescription: %s", stepID, stepType, description)
			
			// Add any additional details
			if details, ok := data["details"].(map[string]any); ok {
				stepMsg += "\nDetails:"
				for k, v := range details {
					stepMsg += fmt.Sprintf("\n  - %s: %v", k, v)
				}
			}
			
			m.chat.AddMessage(SystemMessage, stepMsg, "planning")
		}
		return m, nil
		
	case phoenix.PlanningCompletedMsg:
		// Parse planning completed data
		var data map[string]any
		if err := json.Unmarshal(msg.Data, &data); err == nil {
			summary := data["summary"]
			if steps, ok := data["steps"].([]any); ok {
				completedMsg := fmt.Sprintf("Planning completed!\nSummary: %s\n\nSteps (%d):", summary, len(steps))
				for i, step := range steps {
					if stepMap, ok := step.(map[string]any); ok {
						completedMsg += fmt.Sprintf("\n%d. %s", i+1, stepMap["description"])
					}
				}
				m.chat.AddMessage(SystemMessage, completedMsg, "planning")
			}
		}
		m.statusMessages.AddMessage(StatusCategoryInfo, "Planning completed", nil)
		return m, nil
		
	case phoenix.PlanningErrorMsg:
		// Parse planning error data
		var data map[string]any
		if err := json.Unmarshal(msg.Data, &data); err == nil {
			errorMsg := fmt.Sprintf("Planning error: %s", data["message"])
			if details, ok := data["details"].(string); ok && details != "" {
				errorMsg += fmt.Sprintf("\nDetails: %s", details)
			}
			m.chat.AddMessage(ErrorMessage, errorMsg, "planning")
			m.statusMessages.AddMessage(StatusCategoryError, "Planning failed", nil)
		}
		return m, nil
		
	case phoenix.PlanningCancelledMsg:
		m.chat.AddMessage(SystemMessage, "Planning cancelled", "planning")
		m.statusMessages.AddMessage(StatusCategoryInfo, "Planning cancelled", nil)
		return m, nil
		
	// Join conversation channel after authentication
	case JoinConversationChannelMsg:
		if m.authenticated {
			m.statusBar = "Joining conversation channel..."
			if client, ok := m.phoenixClient.(*phoenix.Client); ok {
				// Join conversation channel first
				// Status channel will be joined after we get the conversation ID
				return m, client.JoinChannel("conversation:lobby")
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
		
	// Join planning channel for authenticated user
	case JoinPlanningChannelMsg:
		if m.authenticated {
			m.statusBar = "Joining planning channel..."
			if planningClient, ok := m.planningClient.(*phoenix.PlanningClient); ok {
				planningClient.SetSocket(m.socket)
				planningClient.SetProgram(m.ProgramHolder())
				return m, planningClient.JoinPlanningChannel()
			}
		}
		return m, nil
		
	// Switch to authenticated user socket
	case SwitchToUserSocketMsg:
		m.statusBar = "Switching to authenticated connection..."
		m.switchingSocket = true // Set flag to indicate we're switching
		// Don't disconnect from auth socket - we need to stay connected to AuthChannel
		// Just connect to user socket with JWT token
		// Now connect to user socket with JWT token only
		client := m.phoenixClient.(*phoenix.Client)
		config := phoenix.Config{
			URL:      m.phoenixURL,
			IsAuth:   false,
		}
		// Always use JWT token for user socket authentication
		if m.jwtToken != "" {
			config.JWTToken = m.jwtToken
			m.statusBar = "Connecting to authenticated socket with JWT token..."
		} else {
			// This shouldn't happen - we should always have a JWT token after authentication
			m.statusBar = "Error: No JWT token available for authenticated connection"
			m.statusMessages.AddMessage(StatusCategoryError, "Cannot connect to user socket: No JWT token available", nil)
			return m, nil
		}
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
		// Check if already authenticated
		if m.authenticated && m.jwtToken != "" {
			// Already authenticated, proceed directly to user socket
			m.statusBar = fmt.Sprintf("Already authenticated as %s - Switching to user socket...", m.username)
			m.statusMessages.AddMessage(StatusCategoryInfo, fmt.Sprintf("Using existing authentication for user %s", m.username), nil)
			
			// Trigger switch to user socket
			return m, func() tea.Msg { return SwitchToUserSocketMsg{} }
		}
		
		// Check if we have an API key to authenticate with
		if m.apiKey != "" {
			// Mask the API key for display (show only last 4 characters)
			maskedKey := "****"
			if len(m.apiKey) > 4 {
				maskedKey = "****" + m.apiKey[len(m.apiKey)-4:]
			}
			m.statusBar = fmt.Sprintf("Authenticating with API key: %s", maskedKey)
			m.statusMessages.AddMessage(StatusCategoryInfo, fmt.Sprintf("Attempting authentication with API key: %s", maskedKey), nil)
			
			// Attempt API key authentication
			if authClient, ok := m.authClient.(*phoenix.AuthClient); ok {
				return m, authClient.AuthenticateWithAPIKey(m.apiKey)
			}
		}
		
		// No API key, wait for manual authentication
		m.statusBar = "Auth channel joined - Waiting for authentication..."
		return m, nil
		
	case phoenix.LoginSuccessMsg:
		m.authenticated = true
		m.username = msg.User.Username
		m.userID = msg.User.ID // Store user ID for api_keys channel
		m.jwtToken = msg.Token // Store the JWT token
		m.statusBar = fmt.Sprintf("Logged in as %s - Switching to authenticated connection...", msg.User.Username)
		
		// Show appropriate message based on whether API key was used
		if m.apiKey != "" {
			m.chat.AddMessage(SystemMessage, fmt.Sprintf("Successfully authenticated as %s via API key", msg.User.Username), "system")
			m.statusMessages.AddMessage(StatusCategoryInfo, fmt.Sprintf("API key authentication successful - logged in as %s", msg.User.Username), nil)
		} else {
			m.chat.AddMessage(SystemMessage, fmt.Sprintf("Successfully logged in as %s", msg.User.Username), "system")
		}
		
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
		// Debug: Check if we have the key
		if msg.APIKey.Key == "" {
			m.chat.AddMessage(ErrorMessage, "Error: API key was generated but key value is empty", "system")
			m.statusMessages.AddMessage(StatusCategoryError, "API key generation succeeded but key value is missing", nil)
		} else {
			// Show the key and warning
			keyMsg := fmt.Sprintf("API Key Generated!\n\nKey: %s\n\n%s\n\nExpires: %s", 
				msg.APIKey.Key, 
				msg.Warning,
				msg.APIKey.ExpiresAt.Format("2006-01-02 15:04:05"))
			m.chat.AddMessage(SystemMessage, keyMsg, "system")
		}
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
		m.chat.AddMessage(ErrorMessage, fmt.Sprintf("API Key Error (%s): %s\nDetails: %s", msg.Operation, msg.Message, msg.Details), "system")
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
		m.statusBar = fmt.Sprintf("Status channel joined for conversation %s", msg.ConversationID)
		
		// Store category metadata with colors from config
		if msg.CategoryDescriptions != nil {
			for category, description := range msg.CategoryDescriptions {
				// Get color from config, fallback to white
				color := m.config.GetCategoryColor(category, "white")
				m.categoryMetadata[category] = CategoryInfo{
					Name:        category,
					Description: description,
					Color:       color,
				}
			}
		}
		
		// Subscribe to all available categories
		if len(msg.AvailableCategories) > 0 {
			// Also ensure metadata exists for categories without descriptions
			for _, category := range msg.AvailableCategories {
				if _, exists := m.categoryMetadata[category]; !exists {
					color := m.config.GetCategoryColor(category, "white")
					m.categoryMetadata[category] = CategoryInfo{
						Name:        category,
						Description: "", // No description provided
						Color:       color,
					}
				}
			}
			
			if statusClient, ok := m.statusClient.(*phoenix.StatusClient); ok {
				m.statusBar = "Subscribing to status categories..."
				return m, statusClient.SubscribeCategories(msg.AvailableCategories)
			}
		} else {
			// Fallback to default categories if none provided
			if statusClient, ok := m.statusClient.(*phoenix.StatusClient); ok {
				categories := []string{"engine", "tool", "workflow", "progress", "error", "info"}
				
				// Create default metadata for fallback categories
				for _, category := range categories {
					if _, exists := m.categoryMetadata[category]; !exists {
						color := m.config.GetCategoryColor(category, "white")
						m.categoryMetadata[category] = CategoryInfo{
							Name:        category,
							Description: "", // No description for defaults
							Color:       color,
						}
					}
				}
				
				return m, statusClient.SubscribeCategories(categories)
			}
		}
		
		// Update status messages component with category colors
		colors := make(map[string]string)
		for category, info := range m.categoryMetadata {
			colors[category] = info.Color
		}
		m.statusMessages.SetCategoryColors(colors)
		
		return m, nil
		
	case phoenix.StatusCategoriesSubscribedMsg:
		m.statusBar = fmt.Sprintf("Subscribed to status categories: %v", msg.Categories)
		
		// Now that all channels are ready, request conversation history
		m.systemMessage = "Loading conversation history..."
		if client, ok := m.phoenixClient.(*phoenix.Client); ok {
			return m, client.GetConversationHistory(100)
		}
		
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
		m.chat.AddMessage(SystemMessage, "API key management channel joined successfully", "system")
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
	help += "Ctrl+C/Ctrl+Q - Quit\n\n"
	
	help += "NAVIGATION:\n"
	help += "━━━━━━━━━━━━━━━━━━━━━\n"
	help += "Ctrl+/    - Focus chat\n"
	help += "Ctrl+F    - Toggle file tree\n"
	help += "Ctrl+E    - Toggle editor\n\n"
	
	help += "COPY/PASTE:\n"
	help += "━━━━━━━━━━━━━━━━━━━━━\n"
	help += "Ctrl+A    - Copy all messages to clipboard\n"
	help += "Ctrl+L    - Copy last assistant message\n"
	help += "Ctrl+T    - Show mouse mode status\n"
	help += "\nText selection is enabled by default.\n"
	help += "For mouse scrolling, start with: ./rubber_duck_tui --mouse\n\n"
	
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
	help += "/plan     - Start AI planning session (e.g., /plan create REST API)\n"
	help += "/clear    - New conversation\n"
	help += "/tree     - Toggle file tree\n"
	help += "/editor   - Toggle editor\n"
	help += "/commands - Show command palette\n"
	help += "/login    - Login to server\n"
	help += "/logout   - Logout from server\n"
	help += "/apikey   - API key management (generate/list/revoke/save)\n"
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
	
	// Model command
	case "set_model":
		if args := msg.Args; args != nil {
			model := args["model"]
			if model != "" {
				// If model is "default" or "none", clear the model
				if model == "default" || model == "none" {
					m.currentModel = ""
					m.currentProvider = ""
					m.updateHeaderState()
					m.statusBar = "Model cleared - using server default"
					m.chat.AddMessage(SystemMessage, "Model preference cleared - using server default", "system")
				} else {
					m.currentModel = model
					// Don't change provider if already set
					m.tokenLimit = GetModelTokenLimit(model)
					m.updateHeaderState()
					m.statusBar = fmt.Sprintf("Model set to: %s", model)
					m.chat.AddMessage(SystemMessage, fmt.Sprintf("Model set to: %s", model), "system")
				}
			}
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
		m.chat.AddMessage(SystemMessage, "Requesting API key generation...", "system")
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
		
	case "auth_apikey_save":
		if args := msg.Args; args != nil {
			apiKey := args["apikey"]
			
			if apiKey == "" {
				m.statusMessages.AddMessage(StatusCategoryError, "No API key provided. Usage: /apikey save <api-key>", nil)
				return m, nil
			}
			
			// Update the config
			m.config.APIKey = apiKey
			
			// Save the config
			if err := SaveConfig(m.config); err != nil {
				m.statusMessages.AddMessage(StatusCategoryError, fmt.Sprintf("Failed to save config: %v", err), nil)
			} else {
				m.statusBar = "API key saved"
				m.chat.AddMessage(SystemMessage, "Server API key saved to ~/.rubber_duck/config.json", "system")
			}
		}
		
	// Provider and model commands
	case "set_provider":
		if args := msg.Args; args != nil {
			provider := args["provider"]
			if provider != "" {
				m.currentProvider = provider
				m.updateHeaderState()
				m.statusBar = fmt.Sprintf("Provider set to: %s", provider)
				m.chat.AddMessage(SystemMessage, fmt.Sprintf("Provider set to: %s", provider), "system")
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
			}
		}
	
	// Planning commands
	case "start_planning":
		// Start a planning session
		if !m.authenticated {
			m.statusMessages.AddMessage(StatusCategoryError, "You must be authenticated to use planning", nil)
			return m, nil
		}
		
		// Get the query from args
		query := msg.Args["query"]
		if query == "" {
			m.statusMessages.AddMessage(StatusCategoryError, "Please provide a query for planning", nil)
			return m, nil
		}
		
		// Start planning with context
		m.statusBar = "Starting planning session..."
		if planningClient, ok := m.planningClient.(*phoenix.PlanningClient); ok {
			// Create context with current model/provider info
			context := map[string]any{
				"provider": m.currentProvider,
				"model":    m.currentModel,
			}
			return m, planningClient.StartPlanning(query, context)
		}
		return m, nil
	
	// Config commands
	case "config_save":
		// Save current provider and model as defaults
		m.config.DefaultProvider = m.currentProvider
		m.config.DefaultModel = m.currentModel
		
		// Save the config
		if err := SaveConfig(m.config); err != nil {
			m.statusMessages.AddMessage(StatusCategoryError, fmt.Sprintf("Failed to save config: %v", err), nil)
			m.statusBar = "Failed to save config"
		} else {
			m.statusBar = "Config saved"
			message := "Default settings saved to ~/.rubber_duck/config.json"
			if m.currentProvider != "" && m.currentModel != "" {
				message = fmt.Sprintf("Default settings saved:\n  Provider: %s\n  Model: %s", m.currentProvider, m.currentModel)
			} else if m.currentProvider != "" {
				message = fmt.Sprintf("Default settings saved:\n  Provider: %s\n  Model: (server default)", m.currentProvider)
			} else if m.currentModel != "" {
				message = fmt.Sprintf("Default settings saved:\n  Provider: (none)\n  Model: %s", m.currentModel)
			}
			m.chat.AddMessage(SystemMessage, message, "system")
		}
		
	case "config_load":
		// Reload config from file
		config, err := LoadConfig()
		if err != nil {
			m.statusMessages.AddMessage(StatusCategoryError, fmt.Sprintf("Failed to load config: %v", err), nil)
			m.statusBar = "Failed to load config"
		} else {
			// Update model's config and current settings
			m.config = config
			m.currentProvider = config.DefaultProvider
			m.currentModel = config.DefaultModel
			m.updateHeaderState()
			
			message := "Settings loaded from ~/.rubber_duck/config.json"
			if config.DefaultProvider != "" && config.DefaultModel != "" {
				message = fmt.Sprintf("Settings loaded:\n  Provider: %s\n  Model: %s", config.DefaultProvider, config.DefaultModel)
			} else if config.DefaultProvider != "" {
				message = fmt.Sprintf("Settings loaded:\n  Provider: %s\n  Model: (server default)", config.DefaultProvider)
			} else if config.DefaultModel != "" {
				message = fmt.Sprintf("Settings loaded:\n  Provider: (none)\n  Model: %s", config.DefaultModel)
			} else {
				message = "Settings loaded (no default provider/model set)"
			}
			m.statusBar = "Config loaded"
			m.chat.AddMessage(SystemMessage, message, "system")
		}
	
	// Timestamp commands
	case "timestamps_on":
		m.statusMessages.SetShowTimestamp(true)
		m.statusBar = "Timestamps enabled"
		m.chat.AddMessage(SystemMessage, "Timestamps enabled for status messages", "system")
		
	case "timestamps_off":
		m.statusMessages.SetShowTimestamp(false)
		m.statusBar = "Timestamps disabled"
		m.chat.AddMessage(SystemMessage, "Timestamps disabled for status messages", "system")
		
	case "timestamps_toggle":
		m.statusMessages.ToggleTimestamps()
		status := "enabled"
		if !m.statusMessages.GetShowTimestamp() {
			status = "disabled"
		}
		m.statusBar = fmt.Sprintf("Timestamps %s", status)
		m.chat.AddMessage(SystemMessage, fmt.Sprintf("Timestamps %s for status messages", status), "system")
		
	case "timestamps_status":
		status := "enabled"
		if !m.statusMessages.GetShowTimestamp() {
			status = "disabled"
		}
		m.chat.AddMessage(SystemMessage, fmt.Sprintf("Timestamps are currently %s\n\nUsage: /timestamps <on|off|toggle>\n  on    - Show timestamps in status messages\n  off   - Hide timestamps in status messages\n  toggle - Toggle timestamp display", status), "system")
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
	// Keep auth socket connected if we're already authenticated
	if m.authSocket != nil && !m.authenticated {
		m.authSocket.Disconnect()
		m.authSocket = nil
	}
	if m.socket != nil {
		m.socket.Disconnect()
		m.socket = nil
	}
	
	// Reset connection state
	m.connected = false
	// Don't reset authenticated state if we're already authenticated
	// m.authenticated = false  // Keep existing auth state
	m.channel = nil
	
	// Update reconnect tracking
	m.reconnectAttempts++
	m.lastReconnectTime = now
	
	m.statusBar = fmt.Sprintf("Reconnecting... (attempt %d)", m.reconnectAttempts)
	m.chat.AddMessage(SystemMessage, fmt.Sprintf("Initiating reconnection (attempt %d)...", m.reconnectAttempts), "system")
	
	// Initiate new connection
	return *m, func() tea.Msg { return InitiateConnectionMsg{} }
}