package phoenix

import (
	"fmt"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// ExampleMockUsage demonstrates how to use the mock Phoenix client
func ExampleMockUsage() {
	// Create a mock client with custom settings
	mock := NewMockClientWithOptions(MockOptions{
		NetworkDelay:   50 * time.Millisecond,  // Fast responses
		ErrorRate:      0.1,                    // 10% error rate
		StreamingSpeed: 25 * time.Millisecond, // Fast streaming
	})

	// Create a minimal Bubble Tea program for testing
	program := tea.NewProgram(nil)

	// Test connection
	config := Config{
		URL:       "ws://localhost:5555/socket",
		APIKey:    "test-key",
		ChannelID: "test:channel",
	}

	// Connect (this will return immediately with mock)
	cmd := mock.Connect(config, program)
	msg := cmd()
	fmt.Printf("Connection result: %T\n", msg)

	// Test file operations
	listCmd := mock.ListFiles(".")
	listMsg := listCmd()
	fmt.Printf("File list result: %T\n", listMsg)

	// Test analysis
	analyzeCmd := mock.AnalyzeFile("main.go", "full")
	analyzeMsg := analyzeCmd()
	fmt.Printf("Analysis result: %T\n", analyzeMsg)

	// Output:
	// Connection result: phoenix.ConnectedMsg
	// File list result: phoenix.StreamStartMsg
	// Analysis result: phoenix.StreamStartMsg
}

// TestMockClientInterface ensures mock client implements the interface
func TestMockClientInterface(t *testing.T) {
	var client PhoenixClient = NewMockClient()
	
	if client == nil {
		t.Fatal("Mock client should not be nil")
	}
	
	// Test that all interface methods are available
	if !client.IsConnected() {
		// Expected - not connected initially
	}
}

// TestRealClientInterface ensures real client implements the interface
func TestRealClientInterface(t *testing.T) {
	var client PhoenixClient = NewRealClient()
	
	if client == nil {
		t.Fatal("Real client should not be nil")
	}
	
	// Test that all interface methods are available
	if !client.IsConnected() {
		// Expected - not connected initially
	}
}

// TestFactoryFunction tests the factory function
func TestFactoryFunction(t *testing.T) {
	// Test default behavior (should use mock in development)
	client := NewPhoenixClient()
	if client == nil {
		t.Fatal("Factory should return a client")
	}
	
	// Test explicit mock mode
	EnableMockMode()
	mockClient := NewPhoenixClient()
	if mockClient == nil {
		t.Fatal("Factory should return a mock client")
	}
	
	// Test explicit real mode
	DisableMockMode()
	realClient := NewPhoenixClient()
	if realClient == nil {
		t.Fatal("Factory should return a real client")
	}
}