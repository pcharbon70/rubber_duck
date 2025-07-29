package phoenix

import (
	"testing"
	"time"
	
	tea "github.com/charmbracelet/bubbletea"
)

func TestNewClient(t *testing.T) {
	client := NewClient()
	
	if client == nil {
		t.Fatal("Expected non-nil client")
	}
	
	if client.socket != nil {
		t.Error("Expected socket to be nil initially")
	}
	
	if client.channel != nil {
		t.Error("Expected channel to be nil initially")
	}
}

// mockModel is a minimal tea.Model for testing
type mockModel struct{}

func (m mockModel) Init() tea.Cmd {
	return nil
}

func (m mockModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	return m, nil
}

func (m mockModel) View() string {
	return ""
}

func TestClient_SetProgram(t *testing.T) {
	client := NewClient()
	
	// Create a mock program
	model := mockModel{}
	program := tea.NewProgram(model)
	
	client.SetProgram(program)
	
	if client.program == nil {
		t.Error("Expected program to be set")
	}
}

func TestClient_Connect(t *testing.T) {
	client := NewClient()
	
	config := Config{
		URL:     "ws://localhost:4000/socket",
		APIKey:  "test_key",
		Channel: "conversation:lobby",
	}
	
	cmd := client.Connect(config)
	
	if cmd == nil {
		t.Error("Expected Connect to return a command")
	}
	
	// Execute the command to get the message
	msg := cmd()
	
	// Since we're testing without a real WebSocket server, we might get either
	// SocketCreatedMsg (if socket creation succeeded) or DisconnectedMsg (if connection failed)
	switch msg.(type) {
	case SocketCreatedMsg, DisconnectedMsg:
		// Both are valid responses for this test
	default:
		t.Errorf("Expected SocketCreatedMsg or DisconnectedMsg, got %T", msg)
	}
}

func TestClient_SendMessage(t *testing.T) {
	client := NewClient()
	
	cmd := client.SendMessage("Test message")
	
	if cmd == nil {
		t.Error("Expected SendMessage to return a command")
	}
	
	// Execute the command to get the message
	msg := cmd()
	
	// Should get an error since channel is not joined
	if errMsg, ok := msg.(ErrorMsg); ok {
		if errMsg.Component != "Phoenix Push" {
			t.Errorf("Expected Phoenix Push error, got %s", errMsg.Component)
		}
	} else {
		t.Errorf("Expected ErrorMsg, got %T", msg)
	}
}

func TestClient_Disconnect(t *testing.T) {
	client := NewClient()
	
	cmd := client.Disconnect()
	
	if cmd == nil {
		t.Error("Expected Disconnect to return a command")
	}
	
	// Execute the command
	msg := cmd()
	
	if disconnectMsg, ok := msg.(DisconnectedMsg); ok {
		if disconnectMsg.Error != nil {
			t.Errorf("Expected no error on disconnect, got %v", disconnectMsg.Error)
		}
	} else {
		t.Errorf("Expected DisconnectedMsg, got %T", msg)
	}
}

func TestClient_Reconnect(t *testing.T) {
	client := NewClient()
	
	config := Config{
		URL:     "ws://localhost:4000/socket",
		APIKey:  "test_key",
		Channel: "conversation:lobby",
	}
	
	// Test with a short delay
	delay := 100 * time.Millisecond
	cmd := client.Reconnect(config, delay)
	
	if cmd == nil {
		t.Error("Expected Reconnect to return a command")
	}
}