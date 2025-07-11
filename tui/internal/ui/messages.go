package ui

import (
	"encoding/json"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/nshafer/phx"
	"github.com/rubber_duck/tui/internal/phoenix"
)

// Msg represents all possible messages in the application
type Msg interface{}

// WebSocket messages
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

// Analysis messages
type StartAnalysisMsg struct{ Path string }
type AnalysisResultMsg struct {
	Path   string
	Result AnalysisResult
}

type AnalysisResult struct {
	Issues []Issue
	Error  error
}

type Issue struct {
	Line    int
	Column  int
	Message string
	Type    string
}

// File operation messages
type FileLoadedMsg struct {
	Path    string
	Content string
}

type FileSavedMsg struct {
	Path    string
	Success bool
}

// Command messages
type ExecuteCommandMsg struct {
	Command string
	Args    []string
}

type CommandResultMsg struct {
	Command string
	Result  string
	Error   error
}

// Helper message for retrying operations
type RetryMsg struct {
	Cmd tea.Cmd
}

// Phoenix connection message
type PhoenixConnectMsg struct {
	Config phoenix.Config
	Client *phoenix.Client
}

// InitiateConnectionMsg triggers the Phoenix connection setup
type InitiateConnectionMsg struct{}