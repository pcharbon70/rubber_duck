package phoenix

import (
	"encoding/json"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// TestMockClientBasicFunctionality tests basic mock client operations
func TestMockClientBasicFunctionality(t *testing.T) {
	mock := NewMockClient()
	
	// Test initial state
	if mock.IsConnected() {
		t.Error("Mock client should not be connected initially")
	}
	
	// Create a test program
	program := tea.NewProgram(nil)
	config := Config{
		URL:       "ws://localhost:5555/socket",
		APIKey:    "test-key",
		ChannelID: "test:commands",
	}
	
	// Test connection
	connectCmd := mock.Connect(config, program)
	msg := connectCmd()
	
	if _, ok := msg.(ConnectedMsg); !ok {
		t.Errorf("Expected ConnectedMsg, got %T", msg)
	}
	
	if !mock.IsConnected() {
		t.Error("Mock client should be connected after Connect()")
	}
}

// TestMockClientFileOperations tests file-related operations
func TestMockClientFileOperations(t *testing.T) {
	mock := NewMockClient()
	setupMockClient(mock, t)
	
	t.Run("ListFiles", func(t *testing.T) {
		cmd := mock.ListFiles(".")
		msg := cmd()
		
		// Should receive a channel response with file list
		if respMsg, ok := msg.(ChannelResponseMsg); ok {
			if respMsg.Event != "file_list" {
				t.Errorf("Expected file_list event, got %s", respMsg.Event)
			}
			
			// Parse response
			var response FileListResponse
			if err := json.Unmarshal(respMsg.Payload, &response); err != nil {
				t.Fatalf("Failed to parse file list response: %v", err)
			}
			
			if len(response.Files) == 0 {
				t.Error("Expected non-empty file list")
			}
			
			if response.Path != "." {
				t.Errorf("Expected path '.', got '%s'", response.Path)
			}
		} else {
			t.Errorf("Expected ChannelResponseMsg, got %T", msg)
		}
	})
	
	t.Run("LoadFile", func(t *testing.T) {
		cmd := mock.LoadFile("main.go")
		msg := cmd()
		
		if respMsg, ok := msg.(ChannelResponseMsg); ok {
			if respMsg.Event != "file_loaded" {
				t.Errorf("Expected file_loaded event, got %s", respMsg.Event)
			}
			
			// Parse response
			var response FileContentResponse
			if err := json.Unmarshal(respMsg.Payload, &response); err != nil {
				t.Fatalf("Failed to parse file content response: %v", err)
			}
			
			if response.Path != "main.go" {
				t.Errorf("Expected path 'main.go', got '%s'", response.Path)
			}
			
			if response.Content == "" {
				t.Error("Expected non-empty file content")
			}
			
			if response.Language != "go" {
				t.Errorf("Expected language 'go', got '%s'", response.Language)
			}
		} else {
			t.Errorf("Expected ChannelResponseMsg, got %T", msg)
		}
	})
	
	t.Run("SaveFile", func(t *testing.T) {
		cmd := mock.SaveFile("test.go", "package main")
		msg := cmd()
		
		if respMsg, ok := msg.(ChannelResponseMsg); ok {
			if respMsg.Event != "file_saved" {
				t.Errorf("Expected file_saved event, got %s", respMsg.Event)
			}
			
			// Parse response
			var response FileSaveResponse
			if err := json.Unmarshal(respMsg.Payload, &response); err != nil {
				t.Fatalf("Failed to parse file save response: %v", err)
			}
			
			if !response.Success {
				t.Error("Expected successful file save")
			}
			
			if response.Path != "test.go" {
				t.Errorf("Expected path 'test.go', got '%s'", response.Path)
			}
		} else {
			t.Errorf("Expected ChannelResponseMsg, got %T", msg)
		}
	})
}

// TestMockClientAnalysisOperations tests analysis-related operations
func TestMockClientAnalysisOperations(t *testing.T) {
	mock := NewMockClient()
	setupMockClient(mock, t)
	
	t.Run("AnalyzeFile", func(t *testing.T) {
		cmd := mock.AnalyzeFile("main.go", "full")
		msg := cmd()
		
		// Should start with a stream start message
		if streamMsg, ok := msg.(StreamStartMsg); ok {
			if streamMsg.ID == "" {
				t.Error("Expected non-empty stream ID")
			}
		} else {
			t.Errorf("Expected StreamStartMsg, got %T", msg)
		}
	})
	
	t.Run("AnalyzeProject", func(t *testing.T) {
		cmd := mock.AnalyzeProject(".", map[string]any{"deep": true})
		msg := cmd()
		
		if streamMsg, ok := msg.(StreamStartMsg); ok {
			if streamMsg.ID == "" {
				t.Error("Expected non-empty stream ID")
			}
		} else {
			t.Errorf("Expected StreamStartMsg, got %T", msg)
		}
	})
	
	t.Run("GetAnalysisResult", func(t *testing.T) {
		cmd := mock.GetAnalysisResult("analysis_123")
		msg := cmd()
		
		if respMsg, ok := msg.(ChannelResponseMsg); ok {
			if respMsg.Event != "analysis_result" {
				t.Errorf("Expected analysis_result event, got %s", respMsg.Event)
			}
			
			// Parse response
			var response AnalysisResponse
			if err := json.Unmarshal(respMsg.Payload, &response); err != nil {
				t.Fatalf("Failed to parse analysis response: %v", err)
			}
			
			if response.ID == "" {
				t.Error("Expected non-empty analysis ID")
			}
			
			if response.Status != "completed" {
				t.Errorf("Expected status 'completed', got '%s'", response.Status)
			}
		} else {
			t.Errorf("Expected ChannelResponseMsg, got %T", msg)
		}
	})
}

// TestMockClientCodeOperations tests code generation operations
func TestMockClientCodeOperations(t *testing.T) {
	mock := NewMockClient()
	setupMockClient(mock, t)
	
	t.Run("GenerateCode", func(t *testing.T) {
		cmd := mock.GenerateCode("Create a hello world function", map[string]any{"language": "go"})
		msg := cmd()
		
		if streamMsg, ok := msg.(StreamStartMsg); ok {
			if streamMsg.ID == "" {
				t.Error("Expected non-empty stream ID")
			}
		} else {
			t.Errorf("Expected StreamStartMsg, got %T", msg)
		}
	})
	
	t.Run("CompleteCode", func(t *testing.T) {
		cmd := mock.CompleteCode("func main() {", 14, "go")
		msg := cmd()
		
		if respMsg, ok := msg.(ChannelResponseMsg); ok {
			if respMsg.Event != "completion_result" {
				t.Errorf("Expected completion_result event, got %s", respMsg.Event)
			}
			
			// Parse response
			var response CompletionResponse
			if err := json.Unmarshal(respMsg.Payload, &response); err != nil {
				t.Fatalf("Failed to parse completion response: %v", err)
			}
			
			if len(response.Completions) == 0 {
				t.Error("Expected non-empty completions list")
			}
			
			if response.Language != "go" {
				t.Errorf("Expected language 'go', got '%s'", response.Language)
			}
		} else {
			t.Errorf("Expected ChannelResponseMsg, got %T", msg)
		}
	})
	
	t.Run("RefactorCode", func(t *testing.T) {
		cmd := mock.RefactorCode("func old() {}", "Rename to new", nil)
		msg := cmd()
		
		if respMsg, ok := msg.(ChannelResponseMsg); ok {
			if respMsg.Event != "refactor_result" {
				t.Errorf("Expected refactor_result event, got %s", respMsg.Event)
			}
			
			// Parse response
			var response RefactorResponse
			if err := json.Unmarshal(respMsg.Payload, &response); err != nil {
				t.Fatalf("Failed to parse refactor response: %v", err)
			}
			
			if response.Status != "completed" {
				t.Errorf("Expected status 'completed', got '%s'", response.Status)
			}
		} else {
			t.Errorf("Expected ChannelResponseMsg, got %T", msg)
		}
	})
}

// TestMockClientLLMOperations tests LLM provider operations
func TestMockClientLLMOperations(t *testing.T) {
	mock := NewMockClient()
	setupMockClient(mock, t)
	
	t.Run("ListProviders", func(t *testing.T) {
		cmd := mock.ListProviders()
		msg := cmd()
		
		if respMsg, ok := msg.(ChannelResponseMsg); ok {
			if respMsg.Event != "providers_list" {
				t.Errorf("Expected providers_list event, got %s", respMsg.Event)
			}
			
			// Parse response
			var response ProvidersResponse
			if err := json.Unmarshal(respMsg.Payload, &response); err != nil {
				t.Fatalf("Failed to parse providers response: %v", err)
			}
			
			if len(response.Providers) == 0 {
				t.Error("Expected non-empty providers list")
			}
			
			if response.Active == "" {
				t.Error("Expected active provider to be set")
			}
		} else {
			t.Errorf("Expected ChannelResponseMsg, got %T", msg)
		}
	})
	
	t.Run("GetProviderStatus", func(t *testing.T) {
		cmd := mock.GetProviderStatus("ollama")
		msg := cmd()
		
		if respMsg, ok := msg.(ChannelResponseMsg); ok {
			if respMsg.Event != "provider_status" {
				t.Errorf("Expected provider_status event, got %s", respMsg.Event)
			}
			
			// Parse response
			var response ProviderInfo
			if err := json.Unmarshal(respMsg.Payload, &response); err != nil {
				t.Fatalf("Failed to parse provider status response: %v", err)
			}
			
			if response.Name != "ollama" {
				t.Errorf("Expected provider name 'ollama', got '%s'", response.Name)
			}
		} else {
			t.Errorf("Expected ChannelResponseMsg, got %T", msg)
		}
	})
	
	t.Run("SetActiveProvider", func(t *testing.T) {
		cmd := mock.SetActiveProvider("openai")
		msg := cmd()
		
		if respMsg, ok := msg.(ChannelResponseMsg); ok {
			if respMsg.Event != "provider_set" {
				t.Errorf("Expected provider_set event, got %s", respMsg.Event)
			}
		} else {
			t.Errorf("Expected ChannelResponseMsg, got %T", msg)
		}
	})
}

// TestMockClientHealthOperations tests health and monitoring operations
func TestMockClientHealthOperations(t *testing.T) {
	mock := NewMockClient()
	setupMockClient(mock, t)
	
	t.Run("GetHealthStatus", func(t *testing.T) {
		cmd := mock.GetHealthStatus()
		msg := cmd()
		
		if respMsg, ok := msg.(ChannelResponseMsg); ok {
			if respMsg.Event != "health_status" {
				t.Errorf("Expected health_status event, got %s", respMsg.Event)
			}
			
			// Parse response
			var response HealthResponse
			if err := json.Unmarshal(respMsg.Payload, &response); err != nil {
				t.Fatalf("Failed to parse health response: %v", err)
			}
			
			if response.Status == "" {
				t.Error("Expected non-empty health status")
			}
			
			if len(response.Components) == 0 {
				t.Error("Expected non-empty components list")
			}
		} else {
			t.Errorf("Expected ChannelResponseMsg, got %T", msg)
		}
	})
	
	t.Run("GetSystemMetrics", func(t *testing.T) {
		cmd := mock.GetSystemMetrics()
		msg := cmd()
		
		if respMsg, ok := msg.(ChannelResponseMsg); ok {
			if respMsg.Event != "system_metrics" {
				t.Errorf("Expected system_metrics event, got %s", respMsg.Event)
			}
			
			// Parse response as generic map
			var response map[string]any
			if err := json.Unmarshal(respMsg.Payload, &response); err != nil {
				t.Fatalf("Failed to parse metrics response: %v", err)
			}
			
			if len(response) == 0 {
				t.Error("Expected non-empty metrics")
			}
		} else {
			t.Errorf("Expected ChannelResponseMsg, got %T", msg)
		}
	})
}

// TestMockClientConfiguration tests configuration options
func TestMockClientConfiguration(t *testing.T) {
	t.Run("CustomNetworkDelay", func(t *testing.T) {
		mock := NewMockClient()
		mock.SetNetworkDelay(10 * time.Millisecond)
		
		start := time.Now()
		cmd := mock.ListFiles(".")
		cmd() // Execute command
		elapsed := time.Since(start)
		
		if elapsed < 10*time.Millisecond {
			t.Error("Expected delay to be applied")
		}
	})
	
	t.Run("CustomErrorRate", func(t *testing.T) {
		mock := NewMockClient()
		mock.SetErrorRate(1.0) // 100% error rate
		mock.SetNetworkDelay(1 * time.Millisecond) // Fast for testing
		
		setupMockClient(mock, t)
		
		// With 100% error rate, we should get errors
		errorCount := 0
		totalTests := 10
		
		for i := 0; i < totalTests; i++ {
			cmd := mock.ListFiles(".")
			msg := cmd()
			
			if _, ok := msg.(ErrorMsg); ok {
				errorCount++
			}
		}
		
		if errorCount == 0 {
			t.Error("Expected some errors with 100% error rate")
		}
	})
	
	t.Run("ZeroErrorRate", func(t *testing.T) {
		mock := NewMockClient()
		mock.SetErrorRate(0.0) // 0% error rate
		mock.SetNetworkDelay(1 * time.Millisecond)
		
		setupMockClient(mock, t)
		
		// With 0% error rate, we should get no errors
		for i := 0; i < 10; i++ {
			cmd := mock.ListFiles(".")
			msg := cmd()
			
			if _, ok := msg.(ErrorMsg); ok {
				t.Error("Expected no errors with 0% error rate")
				break
			}
		}
	})
}

// TestMockClientChannelOperations tests channel management
func TestMockClientChannelOperations(t *testing.T) {
	mock := NewMockClient()
	setupMockClient(mock, t)
	
	t.Run("JoinChannel", func(t *testing.T) {
		cmd := mock.JoinChannel("test:channel")
		msg := cmd()
		
		if _, ok := msg.(ChannelJoinedMsg); !ok {
			t.Errorf("Expected ChannelJoinedMsg, got %T", msg)
		}
	})
	
	t.Run("LeaveChannel", func(t *testing.T) {
		cmd := mock.LeaveChannel("test:channel")
		msg := cmd()
		
		if leftMsg, ok := msg.(ChannelLeftMsg); !ok {
			t.Errorf("Expected ChannelLeftMsg, got %T", msg)
		} else if leftMsg.Topic != "test:channel" {
			t.Errorf("Expected topic 'test:channel', got '%s'", leftMsg.Topic)
		}
	})
	
	t.Run("Disconnect", func(t *testing.T) {
		cmd := mock.Disconnect()
		msg := cmd()
		
		if disconnectMsg, ok := msg.(DisconnectedMsg); !ok {
			t.Errorf("Expected DisconnectedMsg, got %T", msg)
		} else if disconnectMsg.Error != nil {
			t.Errorf("Expected nil error for clean disconnect, got %v", disconnectMsg.Error)
		}
		
		if mock.IsConnected() {
			t.Error("Mock should not be connected after disconnect")
		}
	})
}

// Helper function to set up a mock client for testing
func setupMockClient(mock *MockClient, t *testing.T) {
	program := tea.NewProgram(nil)
	config := Config{
		URL:       "ws://localhost:5555/socket",
		APIKey:    "test-key",
		ChannelID: "test:commands",
	}
	
	// Connect
	connectCmd := mock.Connect(config, program)
	connectCmd()
	
	// Join channel
	joinCmd := mock.JoinChannel(config.ChannelID)
	joinCmd()
	
	if !mock.IsConnected() {
		t.Fatal("Failed to set up connected mock client")
	}
}