package phoenix

import (
	"encoding/json"
	"fmt"
	"net/url"
	"time"
	
	tea "github.com/charmbracelet/bubbletea"
	"github.com/nshafer/phx"
)

// Client represents a Phoenix WebSocket client
type Client struct {
	socket   *phx.Socket
	channel  *phx.Channel
	program  *tea.Program
	apiKey   string
}

// Config represents the Phoenix client configuration
type Config struct {
	URL      string
	APIKey   string
	JWTToken string
	Channel  string
	IsAuth   bool // true if connecting to auth socket
}

// NewClient creates a new Phoenix client
func NewClient() *Client {
	return &Client{}
}

// SetProgram sets the tea.Program for sending messages
func (c *Client) SetProgram(program *tea.Program) {
	c.program = program
}

// Connect establishes a WebSocket connection to Phoenix
func (c *Client) Connect(config Config) tea.Cmd {
	c.apiKey = config.APIKey
	
	return func() tea.Msg {
		// Parse the WebSocket URL
		endPoint, err := url.Parse(config.URL)
		if err != nil {
			return DisconnectedMsg{Error: err}
		}
		
		// For auth socket, no credentials needed
		if !config.IsAuth {
			// For user socket, add credentials
			if config.APIKey != "" {
				q := endPoint.Query()
				q.Set("api_key", config.APIKey)
				endPoint.RawQuery = q.Encode()
			} else if config.JWTToken != "" {
				q := endPoint.Query()
				q.Set("token", config.JWTToken)
				endPoint.RawQuery = q.Encode()
			}
		}
		
		// Create the socket
		socket := phx.NewSocket(endPoint)
		// Use silent logger to prevent console spam
		socket.Logger = NewSilentLogger()
		
		// Disable automatic reconnection to prevent spam
		socket.ReconnectAfterFunc = func(tries int) time.Duration {
			// Return a very large duration to effectively disable auto-reconnect
			return time.Hour * 24 // 24 hours - effectively disabled
		}
		
		// Set up event handlers
		socketType := UserSocketType
		if config.IsAuth {
			socketType = AuthSocketType
		}
		
		socket.OnOpen(func() {
			if c.program != nil {
				c.program.Send(ConnectedMsg{SocketType: socketType})
			}
		})
		
		socket.OnClose(func() {
			if c.program != nil {
				c.program.Send(DisconnectedMsg{Error: nil, SocketType: socketType})
			}
		})
		
		socket.OnError(func(err error) {
			if c.program != nil {
				c.program.Send(DisconnectedMsg{Error: err, SocketType: socketType})
			}
		})
		
		// Connect to the socket
		if err := socket.Connect(); err != nil {
			return DisconnectedMsg{Error: err, SocketType: socketType}
		}
		
		c.socket = socket
		return SocketCreatedMsg{Socket: socket}
	}
}

// JoinChannel joins a Phoenix channel
func (c *Client) JoinChannel(topic string) tea.Cmd {
	return func() tea.Msg {
		if c.socket == nil {
			return ErrorMsg{
				Err:       fmt.Errorf("socket not connected"),
				Component: "Phoenix Client",
			}
		}
		
		// Create channel with proper params
		// Note: nshafer/phx expects map[string]string, so we need to serialize complex data
		params := map[string]string{}
		channel := c.socket.Channel(topic, params)
		
		// Join the channel
		join, err := channel.Join()
		if err != nil {
			return ErrorMsg{
				Err:       err,
				Component: "Phoenix Channel Join",
			}
		}
		
		// Handle join response
		join.Receive("ok", func(response any) {
			c.program.Send(ChannelJoinedMsg{
				Channel:  channel,
				Response: response,
			})
		})
		
		join.Receive("error", func(response any) {
			c.program.Send(ErrorMsg{
				Err:       fmt.Errorf("failed to join channel: %v", response),
				Component: "Phoenix Channel Join",
			})
		})
		
		// Set up channel event handlers
		c.setupChannelHandlers(channel)
		
		c.channel = channel
		return ChannelJoiningMsg{}
	}
}

// setupChannelHandlers sets up event handlers for the channel
func (c *Client) setupChannelHandlers(channel *phx.Channel) {
	// Handle conversation responses
	channel.On("response", func(payload any) {
		data, _ := json.Marshal(payload)
		c.program.Send(ConversationResponseMsg{
			Response: data,
		})
	})
	
	// Handle thinking indicator
	channel.On("thinking", func(payload any) {
		c.program.Send(ConversationThinkingMsg{})
	})
	
	// Handle context updates
	channel.On("context_updated", func(payload any) {
		data, _ := json.Marshal(payload)
		c.program.Send(ConversationContextUpdatedMsg{
			Context: data,
		})
	})
	
	// Handle conversation reset
	channel.On("conversation_reset", func(payload any) {
		data, _ := json.Marshal(payload)
		c.program.Send(ConversationResetMsg{
			SessionInfo: data,
		})
	})
	
	// Handle processing cancelled
	channel.On("processing_cancelled", func(payload any) {
		c.program.Send(ProcessingCancelledMsg{})
	})
	
	// Handle conversation history
	channel.On("history", func(payload any) {
		if data, ok := payload.(map[string]any); ok {
			c.program.Send(ConversationHistoryMsg{
				ConversationID: data["conversation_id"],
				Messages:       data["messages"],
				Count:          data["count"],
			})
		}
	})
	
	// Handle streaming responses
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
				Err:       fmt.Errorf("channel not joined"),
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
		
		push.Receive("ok", func(response any) {
			// Success - nothing to do for now
		})
		
		push.Receive("error", func(response any) {
			c.program.Send(ErrorMsg{
				Err:       fmt.Errorf("push failed: %v", response),
				Component: "Phoenix Push",
			})
		})
		
		push.Receive("timeout", func(response any) {
			// For certain events, we handle the response through channel events, not push replies
			if event == "get_history" || event == "message" || event == "cancel_processing" {
				// These are handled by channel events, ignore push timeout
				return
			}
			
			c.program.Send(ErrorMsg{
				Err:       fmt.Errorf("Connection timeout for event: %s", event),
				Component: "Phoenix Push",
			})
		})
		
		return nil
	}
}

// PushAsync sends a message to the Phoenix channel without waiting for responses
// Use this for events where responses come through channel events, not push replies
func (c *Client) PushAsync(event string, payload map[string]any) tea.Cmd {
	return func() tea.Msg {
		if c.channel == nil {
			return ErrorMsg{
				Err:       fmt.Errorf("channel not joined"),
				Component: "Phoenix Push",
			}
		}
		
		// Just push without setting up response handlers
		_, err := c.channel.Push(event, payload)
		if err != nil {
			return ErrorMsg{
				Err:       err,
				Component: "Phoenix Push",
			}
		}
		
		// Don't wait for any responses - they'll come through channel events
		return nil
	}
}

// SendMessage sends a message to the conversation channel
func (c *Client) SendMessage(content string) tea.Cmd {
	payload := map[string]any{
		"content": content,
	}
	return c.PushAsync("message", payload)
}

// SendMessageWithConfig sends a message with LLM configuration
func (c *Client) SendMessageWithConfig(content string, model string, provider string, temperature float64) tea.Cmd {
	payload := map[string]any{
		"content": content,
	}
	
	// Add llm_config with both provider and model
	if model != "" && provider != "" {
		llmConfig := map[string]any{
			"provider":    provider,
			"model":       model,
			"temperature": temperature,
		}
		payload["llm_config"] = llmConfig
	}
	
	return c.PushAsync("message", payload)
}

// CancelProcessing sends a cancel request to stop current processing
func (c *Client) CancelProcessing() tea.Cmd {
	return c.PushAsync("cancel_processing", map[string]any{})
}

// StartNewConversation starts a new conversation
func (c *Client) StartNewConversation() tea.Cmd {
	return c.Push("new_conversation", map[string]any{})
}

// GetConversationHistory requests the conversation history
func (c *Client) GetConversationHistory(limit int) tea.Cmd {
	return c.PushAsync("get_history", map[string]any{
		"limit": limit,
	})
}

// SetConversationContext updates the conversation context
func (c *Client) SetConversationContext(context map[string]any) tea.Cmd {
	payload := map[string]any{
		"context": context,
	}
	return c.Push("set_context", payload)
}

// SetConversationModel sets the preferred model for the current conversation
func (c *Client) SetConversationModel(model string, provider string) tea.Cmd {
	context := map[string]any{
		"preferred_model": model,
	}
	if provider != "" {
		context["preferred_provider"] = provider
	}
	return c.SetConversationContext(context)
}

// Disconnect closes the WebSocket connection
func (c *Client) Disconnect() tea.Cmd {
	return func() tea.Msg {
		if c.channel != nil {
			c.channel.Leave()
			c.channel = nil
		}
		
		if c.socket != nil {
			c.socket.Disconnect()
			c.socket = nil
		}
		
		return DisconnectedMsg{Error: nil}
	}
}

// Reconnect attempts to reconnect after a delay
func (c *Client) Reconnect(config Config, delay time.Duration) tea.Cmd {
	return tea.Tick(delay, func(t time.Time) tea.Msg {
		return RetryMsg{Cmd: c.Connect(config)}
	})
}