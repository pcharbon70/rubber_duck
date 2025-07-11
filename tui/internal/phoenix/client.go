package phoenix

import (
	"encoding/json"
	"fmt"
	"net/url"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/nshafer/phx"
)

// Client manages the Phoenix WebSocket connection
type Client struct {
	socket  *phx.Socket
	channel *phx.Channel
	program *tea.Program
}

// Config holds the configuration for the Phoenix client
type Config struct {
	URL       string
	APIKey    string
	ChannelID string
}

// NewClient creates a new Phoenix client
func NewClient(config Config) *Client {
	return &Client{}
}

// Connect establishes the WebSocket connection
func (c *Client) Connect(config Config, program *tea.Program) tea.Cmd {
	c.program = program

	return func() tea.Msg {
		// Parse the WebSocket URL
		endPoint, err := url.Parse(config.URL)
		if err != nil {
			return DisconnectedMsg{Error: err}
		}

		// Add API key as query parameter if provided
		if config.APIKey != "" {
			q := endPoint.Query()
			q.Set("api_key", config.APIKey)
			endPoint.RawQuery = q.Encode()
		}

		// Create the socket
		socket := phx.NewSocket(endPoint)
		socket.Logger = phx.NewSimpleLogger(phx.LoggerLevel(phx.LogWarning))

		// Set up event handlers
		socket.OnOpen(func() {
			program.Send(ConnectedMsg{})
		})

		socket.OnError(func(err error) {
			program.Send(DisconnectedMsg{Error: err})
		})

		socket.OnClose(func() {
			program.Send(DisconnectedMsg{Error: fmt.Errorf("connection closed")})
		})

		// Connect to the socket
		if err := socket.Connect(); err != nil {
			return DisconnectedMsg{Error: err}
		}

		c.socket = socket

		return SocketCreatedMsg{Socket: socket}
	}
}

// JoinChannel joins the specified channel
func (c *Client) JoinChannel(socket *phx.Socket, channelTopic string) tea.Cmd {
	return func() tea.Msg {
		// Create and join channel
		channel := socket.Channel(channelTopic, nil)
		c.channel = channel

		join, err := channel.Join()
		if err != nil {
			return ErrorMsg{
				Err:       err,
				Component: "Phoenix Channel",
			}
		}

		// Set up join handlers
		join.Receive("ok", func(response any) {
			c.program.Send(ChannelJoinedMsg{Channel: channel})
			c.setupChannelHandlers(channel)
		})

		join.Receive("error", func(response any) {
			c.program.Send(ErrorMsg{
				Err:       fmt.Errorf("failed to join channel: %v", response),
				Component: "Phoenix Channel",
			})
		})

		join.Receive("timeout", func(response any) {
			c.program.Send(ErrorMsg{
				Err:       fmt.Errorf("timeout joining channel"),
				Component: "Phoenix Channel",
			})
		})

		return ChannelJoiningMsg{}
	}
}

// setupChannelHandlers sets up all channel event handlers
func (c *Client) setupChannelHandlers(channel *phx.Channel) {
	// File operations
	channel.On("file:list", func(payload any) {
		data, _ := json.Marshal(payload)
		c.program.Send(ChannelResponseMsg{
			Event:   "file_list",
			Payload: data,
		})
	})

	// Analysis results
	channel.On("analyze:result", func(payload any) {
		data, _ := json.Marshal(payload)
		c.program.Send(ChannelResponseMsg{
			Event:   "analyze_result",
			Payload: data,
		})
	})

	// Code generation
	channel.On("generate:result", func(payload any) {
		data, _ := json.Marshal(payload)
		c.program.Send(ChannelResponseMsg{
			Event:   "generate_result",
			Payload: data,
		})
	})

	// Streaming support
	channel.On("stream:start", func(payload any) {
		data := payload.(map[string]any)
		c.program.Send(StreamStartMsg{ID: data["id"].(string)})
	})

	channel.On("stream:data", func(payload any) {
		data := payload.(map[string]any)
		c.program.Send(StreamDataMsg{
			ID:   data["id"].(string),
			Data: data["chunk"].(string),
		})
	})

	channel.On("stream:end", func(payload any) {
		data := payload.(map[string]any)
		c.program.Send(StreamEndMsg{ID: data["id"].(string)})
	})

	// Error handling
	channel.On("error", func(payload any) {
		c.program.Send(ErrorMsg{
			Err:       fmt.Errorf("channel error: %v", payload),
			Component: "Phoenix Channel",
		})
	})
}

// Push sends a message to the Phoenix channel
func (c *Client) Push(event string, payload map[string]any) tea.Cmd {
	return func() tea.Msg {
		if c.channel == nil {
			return ErrorMsg{
				Err:       fmt.Errorf("channel not connected"),
				Component: "Phoenix Push",
			}
		}

		push, err := c.channel.Push(event, payload)
		if err != nil {
			return ErrorMsg{
				Err:       err,
				Component: "Phoenix Push",
			}
		}

		// Set up response handlers
		push.Receive("ok", func(response any) {
			data, _ := json.Marshal(response)
			c.program.Send(ChannelResponseMsg{
				Event:   event + "_response",
				Payload: data,
			})
		})

		push.Receive("error", func(response any) {
			c.program.Send(ErrorMsg{
				Err:       fmt.Errorf("push error: %v", response),
				Component: "Phoenix Push",
			})
		})

		push.Receive("timeout", func(response any) {
			c.program.Send(ErrorMsg{
				Err:       fmt.Errorf("push timeout"),
				Component: "Phoenix Push",
			})
		})

		return nil
	}
}

// Disconnect closes the WebSocket connection
func (c *Client) Disconnect() tea.Cmd {
	return func() tea.Msg {
		if c.channel != nil {
			c.channel.Leave()
		}
		if c.socket != nil {
			c.socket.Disconnect()
		}
		return DisconnectedMsg{Error: nil}
	}
}

// Reconnect attempts to reconnect after a delay
func (c *Client) Reconnect(config Config, delay time.Duration) tea.Cmd {
	return tea.Tick(delay, func(t time.Time) tea.Msg {
		return RetryMsg{Cmd: c.Connect(config, c.program)}
	})
}

// Message types used by Phoenix client
type (
	ConnectedMsg      struct{}
	DisconnectedMsg   struct{ Error error }
	SocketCreatedMsg  struct{ Socket *phx.Socket }
	ChannelJoinedMsg  struct{ Channel *phx.Channel }
	ChannelJoiningMsg struct{}
	
	ChannelResponseMsg struct {
		Event   string
		Payload json.RawMessage
	}
	
	StreamStartMsg struct{ ID string }
	StreamDataMsg  struct {
		ID   string
		Data string
	}
	StreamEndMsg struct{ ID string }
	
	ErrorMsg struct {
		Err       error
		Component string
		Retry     tea.Cmd
	}
	
	RetryMsg struct {
		Cmd tea.Cmd
	}
)