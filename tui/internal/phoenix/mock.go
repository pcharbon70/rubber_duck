package phoenix

import (
	"encoding/json"
	"fmt"
	"math/rand"
	"os"
	"path/filepath"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// MockClient implements PhoenixClient for development and testing
type MockClient struct {
	connected    bool
	channels     map[string]bool
	program      *tea.Program
	config       Config
	
	// Mock data
	files        map[string]string  // path -> content
	providers    []ProviderInfo
	activeProvider string
	
	// Simulation settings
	networkDelay    time.Duration
	errorRate       float64
	streamingSpeed  time.Duration
}

// NewMockClient creates a new mock Phoenix client
func NewMockClient() *MockClient {
	mock := &MockClient{
		channels:       make(map[string]bool),
		files:          make(map[string]string),
		networkDelay:   100 * time.Millisecond,
		errorRate:      0.05, // 5% error rate
		streamingSpeed: 50 * time.Millisecond,
	}
	
	mock.initializeMockData()
	return mock
}

// SetNetworkDelay configures the simulated network delay
func (m *MockClient) SetNetworkDelay(delay time.Duration) {
	m.networkDelay = delay
}

// SetErrorRate configures the simulated error rate (0.0 to 1.0)
func (m *MockClient) SetErrorRate(rate float64) {
	m.errorRate = rate
}

// SetStreamingSpeed configures the streaming simulation speed
func (m *MockClient) SetStreamingSpeed(speed time.Duration) {
	m.streamingSpeed = speed
}

// Connection management
func (m *MockClient) Connect(config Config, program *tea.Program) tea.Cmd {
	m.config = config
	m.program = program
	
	return m.delayedCommand(func() tea.Msg {
		if m.shouldSimulateError() {
			return DisconnectedMsg{Error: fmt.Errorf("connection failed: network unreachable")}
		}
		
		m.connected = true
		return ConnectedMsg{}
	})
}

func (m *MockClient) Disconnect() tea.Cmd {
	return m.delayedCommand(func() tea.Msg {
		m.connected = false
		m.channels = make(map[string]bool)
		return DisconnectedMsg{Error: nil}
	})
}

func (m *MockClient) IsConnected() bool {
	return m.connected
}

// Channel operations
func (m *MockClient) JoinChannel(topic string) tea.Cmd {
	return m.delayedCommand(func() tea.Msg {
		if !m.connected {
			return ErrorMsg{
				Err:       fmt.Errorf("not connected"),
				Component: "Channel",
			}
		}
		
		if m.shouldSimulateError() {
			return ErrorMsg{
				Err:       fmt.Errorf("failed to join channel: %s", topic),
				Component: "Channel",
			}
		}
		
		m.channels[topic] = true
		return ChannelJoinedMsg{Channel: nil} // Mock channel object
	})
}

func (m *MockClient) LeaveChannel(topic string) tea.Cmd {
	return m.delayedCommand(func() tea.Msg {
		delete(m.channels, topic)
		return ChannelLeftMsg{Topic: topic}
	})
}

// Message operations
func (m *MockClient) Push(event string, payload map[string]any) tea.Cmd {
	return m.delayedCommand(func() tea.Msg {
		if !m.connected {
			return ErrorMsg{
				Err:       fmt.Errorf("not connected"),
				Component: "Push",
			}
		}
		
		// Route to appropriate handler based on event
		switch {
		case strings.HasPrefix(event, "file:"):
			return m.handleFileEvent(event, payload)
		case strings.HasPrefix(event, "analyze:"):
			return m.handleAnalysisEvent(event, payload)
		case strings.HasPrefix(event, "generate:"):
			return m.handleGenerationEvent(event, payload)
		case strings.HasPrefix(event, "llm:"):
			return m.handleLLMEvent(event, payload)
		default:
			return ChannelResponseMsg{
				Event:   event + "_response",
				Payload: json.RawMessage(`{"status": "ok"}`),
			}
		}
	})
}

func (m *MockClient) PushWithResponse(event string, payload map[string]any, timeout time.Duration) tea.Cmd {
	return m.Push(event, payload)
}

// File operations
func (m *MockClient) ListFiles(path string) tea.Cmd {
	return m.delayedCommand(func() tea.Msg {
		files := m.generateFileList(path)
		response := FileListResponse{
			Files: files,
			Path:  path,
		}
		
		data, _ := json.Marshal(response)
		return ChannelResponseMsg{
			Event:   "file_list",
			Payload: data,
		}
	})
}

func (m *MockClient) LoadFile(path string) tea.Cmd {
	return m.delayedCommand(func() tea.Msg {
		content, exists := m.files[path]
		if !exists {
			content = m.generateFileContent(path)
			m.files[path] = content
		}
		
		response := FileContentResponse{
			Path:     path,
			Content:  content,
			Language: m.detectLanguage(path),
			Size:     int64(len(content)),
		}
		
		data, _ := json.Marshal(response)
		return ChannelResponseMsg{
			Event:   "file_loaded",
			Payload: data,
		}
	})
}

func (m *MockClient) SaveFile(path string, content string) tea.Cmd {
	return m.delayedCommand(func() tea.Msg {
		if m.shouldSimulateError() {
			return ErrorMsg{
				Err:       fmt.Errorf("failed to save file: %s", path),
				Component: "File Save",
			}
		}
		
		m.files[path] = content
		
		response := FileSaveResponse{
			Path:      path,
			Success:   true,
			Message:   "File saved successfully",
			Timestamp: time.Now().Format(time.RFC3339),
		}
		
		data, _ := json.Marshal(response)
		return ChannelResponseMsg{
			Event:   "file_saved",
			Payload: data,
		}
	})
}

func (m *MockClient) WatchFile(path string) tea.Cmd {
	return m.delayedCommand(func() tea.Msg {
		return ChannelResponseMsg{
			Event:   "file_watch_started",
			Payload: json.RawMessage(fmt.Sprintf(`{"path": "%s", "watching": true}`, path)),
		}
	})
}

// Analysis operations
func (m *MockClient) AnalyzeFile(path string, analysisType string) tea.Cmd {
	return m.simulateStreamingAnalysis(path, analysisType, false)
}

func (m *MockClient) AnalyzeProject(rootPath string, options map[string]any) tea.Cmd {
	return m.simulateStreamingAnalysis(rootPath, "project", true)
}

func (m *MockClient) GetAnalysisResult(analysisId string) tea.Cmd {
	return m.delayedCommand(func() tea.Msg {
		response := m.generateAnalysisResult(analysisId)
		data, _ := json.Marshal(response)
		return ChannelResponseMsg{
			Event:   "analysis_result",
			Payload: data,
		}
	})
}

// Code operations
func (m *MockClient) GenerateCode(prompt string, context map[string]any) tea.Cmd {
	return m.simulateStreamingGeneration(prompt, context)
}

func (m *MockClient) CompleteCode(content string, position int, language string) tea.Cmd {
	return m.delayedCommand(func() tea.Msg {
		completions := m.generateCodeCompletions(content, position, language)
		response := CompletionResponse{
			Completions: completions,
			Position:    position,
			Language:    language,
		}
		
		data, _ := json.Marshal(response)
		return ChannelResponseMsg{
			Event:   "completion_result",
			Payload: data,
		}
	})
}

func (m *MockClient) RefactorCode(content string, instruction string, options map[string]any) tea.Cmd {
	return m.delayedCommand(func() tea.Msg {
		response := m.generateRefactorResult(content, instruction)
		data, _ := json.Marshal(response)
		return ChannelResponseMsg{
			Event:   "refactor_result",
			Payload: data,
		}
	})
}

func (m *MockClient) GenerateTests(filePath string, testType string) tea.Cmd {
	return m.simulateStreamingGeneration(fmt.Sprintf("Generate %s tests for %s", testType, filePath), map[string]any{
		"file_path": filePath,
		"test_type": testType,
	})
}

// LLM operations
func (m *MockClient) ListProviders() tea.Cmd {
	return m.delayedCommand(func() tea.Msg {
		response := ProvidersResponse{
			Providers: m.providers,
			Active:    m.activeProvider,
		}
		
		data, _ := json.Marshal(response)
		return ChannelResponseMsg{
			Event:   "providers_list",
			Payload: data,
		}
	})
}

func (m *MockClient) GetProviderStatus(provider string) tea.Cmd {
	return m.delayedCommand(func() tea.Msg {
		for _, p := range m.providers {
			if p.Name == provider {
				data, _ := json.Marshal(p)
				return ChannelResponseMsg{
					Event:   "provider_status",
					Payload: data,
				}
			}
		}
		
		return ErrorMsg{
			Err:       fmt.Errorf("provider not found: %s", provider),
			Component: "LLM",
		}
	})
}

func (m *MockClient) SetActiveProvider(provider string) tea.Cmd {
	return m.delayedCommand(func() tea.Msg {
		m.activeProvider = provider
		
		return ChannelResponseMsg{
			Event:   "provider_set",
			Payload: json.RawMessage(fmt.Sprintf(`{"active": "%s", "status": "ok"}`, provider)),
		}
	})
}

// Health operations
func (m *MockClient) GetHealthStatus() tea.Cmd {
	return m.delayedCommand(func() tea.Msg {
		response := m.generateHealthStatus()
		data, _ := json.Marshal(response)
		return ChannelResponseMsg{
			Event:   "health_status",
			Payload: data,
		}
	})
}

func (m *MockClient) GetSystemMetrics() tea.Cmd {
	return m.delayedCommand(func() tea.Msg {
		metrics := map[string]any{
			"memory_usage":    rand.Float64() * 100,
			"cpu_usage":       rand.Float64() * 100,
			"active_sessions": rand.Intn(50),
			"total_requests":  rand.Intn(10000),
			"uptime":          time.Since(time.Now().Add(-time.Hour * 24 * 7)).String(),
		}
		
		data, _ := json.Marshal(metrics)
		return ChannelResponseMsg{
			Event:   "system_metrics",
			Payload: data,
		}
	})
}

// Helper methods

func (m *MockClient) delayedCommand(fn func() tea.Msg) tea.Cmd {
	return tea.Tick(m.networkDelay, func(t time.Time) tea.Msg {
		return fn()
	})
}

func (m *MockClient) shouldSimulateError() bool {
	return rand.Float64() < m.errorRate
}

func (m *MockClient) initializeMockData() {
	// Initialize mock providers
	m.providers = []ProviderInfo{
		{
			Name:   "ollama",
			Type:   "local",
			Status: "connected",
			Models: []string{"llama3.2", "codellama", "phi3"},
			Capabilities: []string{"completion", "generation", "analysis"},
			Config: map[string]any{
				"url": "http://localhost:11434",
				"model": "llama3.2",
			},
			Metrics: map[string]any{
				"requests_per_minute": rand.Intn(100),
				"avg_response_time": rand.Intn(2000),
			},
		},
		{
			Name:   "openai",
			Type:   "remote",
			Status: "available",
			Models: []string{"gpt-4", "gpt-3.5-turbo", "codex"},
			Capabilities: []string{"completion", "generation", "analysis", "planning"},
			Config: map[string]any{
				"api_key": "sk-***",
				"model": "gpt-4",
			},
			Metrics: map[string]any{
				"requests_per_minute": rand.Intn(50),
				"avg_response_time": rand.Intn(3000),
			},
		},
	}
	m.activeProvider = "ollama"
	
	// Initialize mock files
	projectRoot := "/mock/project"
	m.files = map[string]string{
		filepath.Join(projectRoot, "main.go"): `package main

import "fmt"

func main() {
	fmt.Println("Hello, World!")
}`,
		filepath.Join(projectRoot, "README.md"): `# Mock Project

This is a mock project for TUI testing.

## Features
- File browsing
- Code editing
- Analysis integration
`,
		filepath.Join(projectRoot, "lib", "utils.go"): `package lib

// Add utility function for string manipulation
func ReverseString(s string) string {
	runes := []rune(s)
	for i, j := 0, len(runes)-1; i < j; i, j = i+1, j-1 {
		runes[i], runes[j] = runes[j], runes[i]
	}
	return string(runes)
}`,
	}
}

// Message type for channel leave
type ChannelLeftMsg struct {
	Topic string
}

// Continue in next part due to length...