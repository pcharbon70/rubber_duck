package phoenix

import (
	"encoding/json"
	"fmt"
	"net/url"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/nshafer/phx"
)

// RealClient implements PhoenixClient for actual Phoenix WebSocket connections
type RealClient struct {
	socket  *phx.Socket
	channel *phx.Channel
	program *tea.Program
	config  Config
}

// NewRealClient creates a new real Phoenix client
func NewRealClient() *RealClient {
	return &RealClient{}
}

// Connection management
func (c *RealClient) Connect(config Config, program *tea.Program) tea.Cmd {
	c.program = program
	c.config = config

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

func (c *RealClient) Disconnect() tea.Cmd {
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

func (c *RealClient) IsConnected() bool {
	return c.socket != nil && c.socket.IsConnected()
}

// Channel operations
func (c *RealClient) JoinChannel(topic string) tea.Cmd {
	return func() tea.Msg {
		if c.socket == nil {
			return ErrorMsg{
				Err:       fmt.Errorf("socket not connected"),
				Component: "Channel Join",
			}
		}

		// Create and join channel
		channel := c.socket.Channel(topic, nil)
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

func (c *RealClient) LeaveChannel(topic string) tea.Cmd {
	return func() tea.Msg {
		if c.channel != nil {
			c.channel.Leave()
			c.channel = nil
		}
		return ChannelLeftMsg{Topic: topic}
	}
}

// Message operations
func (c *RealClient) Push(event string, payload map[string]any) tea.Cmd {
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

func (c *RealClient) PushWithResponse(event string, payload map[string]any, timeout time.Duration) tea.Cmd {
	// For real client, timeout is handled by Phoenix library
	return c.Push(event, payload)
}

// File operations
func (c *RealClient) ListFiles(path string) tea.Cmd {
	return c.Push("file:list", map[string]any{"path": path})
}

func (c *RealClient) LoadFile(path string) tea.Cmd {
	return c.Push("file:load", map[string]any{"path": path})
}

func (c *RealClient) SaveFile(path string, content string) tea.Cmd {
	return c.Push("file:save", map[string]any{
		"path":    path,
		"content": content,
	})
}

func (c *RealClient) WatchFile(path string) tea.Cmd {
	return c.Push("file:watch", map[string]any{"path": path})
}

// Analysis operations
func (c *RealClient) AnalyzeFile(path string, analysisType string) tea.Cmd {
	return c.Push("analyze:file", map[string]any{
		"path": path,
		"type": analysisType,
	})
}

func (c *RealClient) AnalyzeProject(rootPath string, options map[string]any) tea.Cmd {
	payload := map[string]any{
		"root_path": rootPath,
	}
	if options != nil {
		payload["options"] = options
	}
	return c.Push("analyze:project", payload)
}

func (c *RealClient) GetAnalysisResult(analysisId string) tea.Cmd {
	return c.Push("analyze:result", map[string]any{"id": analysisId})
}

// Code operations
func (c *RealClient) GenerateCode(prompt string, context map[string]any) tea.Cmd {
	payload := map[string]any{
		"prompt": prompt,
	}
	if context != nil {
		payload["context"] = context
	}
	return c.Push("generate:code", payload)
}

func (c *RealClient) CompleteCode(content string, position int, language string) tea.Cmd {
	return c.Push("generate:completion", map[string]any{
		"content":  content,
		"position": position,
		"language": language,
	})
}

func (c *RealClient) RefactorCode(content string, instruction string, options map[string]any) tea.Cmd {
	payload := map[string]any{
		"content":     content,
		"instruction": instruction,
	}
	if options != nil {
		payload["options"] = options
	}
	return c.Push("generate:refactor", payload)
}

func (c *RealClient) GenerateTests(filePath string, testType string) tea.Cmd {
	return c.Push("generate:tests", map[string]any{
		"file_path": filePath,
		"test_type": testType,
	})
}

// LLM operations
func (c *RealClient) ListProviders() tea.Cmd {
	return c.Push("llm:list_providers", map[string]any{})
}

func (c *RealClient) GetProviderStatus(provider string) tea.Cmd {
	return c.Push("llm:provider_status", map[string]any{"provider": provider})
}

func (c *RealClient) SetActiveProvider(provider string) tea.Cmd {
	return c.Push("llm:set_provider", map[string]any{"provider": provider})
}

// Health operations
func (c *RealClient) GetHealthStatus() tea.Cmd {
	return c.Push("health:status", map[string]any{})
}

func (c *RealClient) GetSystemMetrics() tea.Cmd {
	return c.Push("health:metrics", map[string]any{})
}

// setupChannelHandlers sets up all channel event handlers
func (c *RealClient) setupChannelHandlers(channel *phx.Channel) {
	// File operations
	channel.On("file:list", func(payload any) {
		data, _ := json.Marshal(payload)
		c.program.Send(ChannelResponseMsg{
			Event:   "file_list",
			Payload: data,
		})
	})

	channel.On("file:loaded", func(payload any) {
		data, _ := json.Marshal(payload)
		c.program.Send(ChannelResponseMsg{
			Event:   "file_loaded",
			Payload: data,
		})
	})

	channel.On("file:saved", func(payload any) {
		data, _ := json.Marshal(payload)
		c.program.Send(ChannelResponseMsg{
			Event:   "file_saved",
			Payload: data,
		})
	})

	// Analysis results
	channel.On("analyze:result", func(payload any) {
		data, _ := json.Marshal(payload)
		c.program.Send(ChannelResponseMsg{
			Event:   "analysis_result",
			Payload: data,
		})
	})

	// Code generation
	channel.On("generate:result", func(payload any) {
		data, _ := json.Marshal(payload)
		c.program.Send(ChannelResponseMsg{
			Event:   "generation_result",
			Payload: data,
		})
	})

	channel.On("completion:result", func(payload any) {
		data, _ := json.Marshal(payload)
		c.program.Send(ChannelResponseMsg{
			Event:   "completion_result",
			Payload: data,
		})
	})

	channel.On("refactor:result", func(payload any) {
		data, _ := json.Marshal(payload)
		c.program.Send(ChannelResponseMsg{
			Event:   "refactor_result",
			Payload: data,
		})
	})

	// LLM operations
	channel.On("llm:providers", func(payload any) {
		data, _ := json.Marshal(payload)
		c.program.Send(ChannelResponseMsg{
			Event:   "providers_list",
			Payload: data,
		})
	})

	channel.On("llm:provider_status", func(payload any) {
		data, _ := json.Marshal(payload)
		c.program.Send(ChannelResponseMsg{
			Event:   "provider_status",
			Payload: data,
		})
	})

	// Health
	channel.On("health:status", func(payload any) {
		data, _ := json.Marshal(payload)
		c.program.Send(ChannelResponseMsg{
			Event:   "health_status",
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