package phoenix

import (
	"encoding/json"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/nshafer/phx"
)

// SocketType represents the type of socket (auth or user)
type SocketType string

const (
	AuthSocketType SocketType = "auth"
	UserSocketType SocketType = "user"
)

// Message types used by Phoenix client
type (
	ConnectedMsg      struct{ SocketType SocketType }
	DisconnectedMsg   struct{ 
		Error      error
		SocketType SocketType
	}
	SocketCreatedMsg  struct{ Socket *phx.Socket }
	ChannelJoinedMsg  struct{ 
		Channel  *phx.Channel
		Response any // Join response data from server
	}
	ChannelJoiningMsg struct{}
	
	ErrorMsg struct {
		Err       error
		Component string
		Retry     tea.Cmd
	}
	
	RetryMsg struct {
		Cmd tea.Cmd
	}
	
	// Conversation message types
	ConversationResponseMsg struct {
		Response json.RawMessage
	}
	
	ConversationThinkingMsg struct{}
	
	ConversationContextUpdatedMsg struct {
		Context json.RawMessage
	}
	
	ProcessingCancelledMsg struct{}
	
	ConversationResetMsg struct {
		SessionInfo json.RawMessage
	}
	
	ConversationHistoryMsg struct {
		ConversationID any
		Messages       any
		Count          any
	}
	
	// Streaming message types
	StreamStartMsg struct{ ID string }
	StreamDataMsg  struct {
		ID   string
		Data string
	}
	StreamEndMsg struct{ ID string }
)

// Response types for conversation
type ConversationMessage struct {
	Query            string         `json:"query"`
	Response         string         `json:"response"`
	ConversationType string         `json:"conversation_type"`
	RoutedTo         string         `json:"routed_to,omitempty"`
	Timestamp        string         `json:"timestamp"`
	Metadata         map[string]any `json:"metadata,omitempty"`
}

type ConversationContext struct {
	Context   map[string]any `json:"context"`
	Timestamp string         `json:"timestamp"`
}

type ConversationSessionInfo struct {
	SessionId string `json:"session_id"`
	Timestamp string `json:"timestamp"`
}