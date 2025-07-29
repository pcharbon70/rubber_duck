package ui

import (
	tea "github.com/charmbracelet/bubbletea"
)

// Message types for the TUI

// These are now imported from phoenix package - we'll use them directly

// UI messages
type WindowSizeMsg struct{ Width, Height int }
type FileSelectedMsg struct{ Path string }
type EditorUpdateMsg struct{ Content string }
type ErrorMsg struct {
	Err       error
	Component string
	Retry     tea.Cmd
}

// Chat messages
type ChatMessageSentMsg struct{ Content string }
type ChatMessageReceivedMsg struct {
	Content string
	Type    string // "assistant", "system", "error"
}

// Command messages
type ExecuteCommandMsg struct {
	Command string
	Args    map[string]string
}

// Modal messages
type ShowModalMsg struct {
	Type    ModalType
	Title   string
	Content string
}

// Copy operation messages
type CopyToClipboardMsg struct {
	Content string
	Type    string // "all" or "last_assistant"
}

// Mouse mode toggle message
type ToggleMouseModeMsg struct{}

// Cancel processing message
type CancelRequestMsg struct{}
type ProcessingCancelledMsg struct{}

// Connection messages
type InitiateConnectionMsg struct{}
type JoinConversationChannelMsg struct{}
type JoinStatusChannelMsg struct{}
type JoinApiKeyChannelMsg struct{}
type JoinPlanningChannelMsg struct{}
type SwitchToUserSocketMsg struct{}
type AuthSocketConnectedMsg struct{}

// RetryMsg for retrying failed operations
type RetryMsg struct {
	Cmd tea.Cmd
}