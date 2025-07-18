package ui

import (
	"encoding/json"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/nshafer/phx"
)

// Message types for the TUI

// Phoenix WebSocket messages
type ConnectedMsg struct{}
type DisconnectedMsg struct{ Error error }
type SocketCreatedMsg struct{ Socket *phx.Socket }
type ChannelJoinedMsg struct{ Channel *phx.Channel }
type ChannelJoiningMsg struct{}

type ChannelResponseMsg struct {
	Event   string
	Payload json.RawMessage
}

// Streaming messages
type StreamStartMsg struct{ ID string }
type StreamDataMsg struct {
	ID   string
	Data string
}
type StreamEndMsg struct{ ID string }

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
	Args    []string
}

// Modal messages
type ShowModalMsg struct {
	Type    ModalType
	Title   string
	Content string
}

// Connection messages
type InitiateConnectionMsg struct{}

// RetryMsg for retrying failed operations
type RetryMsg struct {
	Cmd tea.Cmd
}