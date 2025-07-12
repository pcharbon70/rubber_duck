package ui

import (
	"encoding/json"
	"time"

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

// Modal messages
type ShowModalMsg struct {
	Type    ModalType
	Title   string
	Content string
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
	Client phoenix.PhoenixClient
}

// InitiateConnectionMsg triggers the Phoenix connection setup
type InitiateConnectionMsg struct{}

// AutoSaveMsg indicates an auto-save operation
type AutoSaveMsg struct {
	File string
}

// Local command messages from unified command system
type ShowHelpMsg struct {
	Topic string
}

type ShowSettingsMsg struct {
	Tab string
}

type ToggleThemeMsg struct{}

type ClearOutputMsg struct{}

type ShowPerformanceStatsMsg struct {
	Detailed bool
}

type ClearCacheMsg struct {
	CacheType string
}

type ShowInputModalMsg struct {
	Title       string
	Prompt      string
	Placeholder string
	Action      string
}

type SaveFileMsg struct {
	Path    string
	Content string
	Force   bool
}

type CloseFileMsg struct {
	Path string
	Save bool
}

type FocusPaneMsg struct {
	Pane string
}

type ShowSearchMsg struct {
	Query         string
	Scope         string
	CaseSensitive bool
}

type GotoLineMsg struct {
	Line int
}

type ShowCommandPaletteMsg struct {
	Filter string
}

// Unified command system response messages
type UnsolicitedResponseMsg struct {
	Response interface{} // commands.UnifiedResponse
}

type CommandCompletedMsg struct {
	Command  string
	Content  interface{}
	Duration time.Duration
}

type CommandErrorMsg struct {
	Command string
	Error   interface{} // *commands.CommandError
}

type CommandStreamingMsg struct {
	Command  string
	StreamID string
	Content  interface{}
}

type CommandStatusMsg struct {
	Command string
	Status  string
	Content interface{}
}

type RetryCommandMsg struct {
	Command     interface{} // commands.UnifiedCommand
	AttemptNum  int
	MaxRetries  int
	OriginalCmd interface{} // *commands.PendingCommand
}