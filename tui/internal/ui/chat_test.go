package ui

import (
	"testing"
	"time"
	
	tea "github.com/charmbracelet/bubbletea"
)

func TestNewChat(t *testing.T) {
	chat := NewChat()
	
	if chat == nil {
		t.Fatal("Expected non-nil chat component")
	}
	
	if chat.messages == nil {
		t.Error("Expected messages slice to be initialized")
	}
	
	if !chat.focused {
		t.Error("Expected chat to be focused by default")
	}
	
	if chat.width == 0 || chat.height == 0 {
		t.Error("Expected default dimensions to be set")
	}
}

func TestChat_AddMessage(t *testing.T) {
	chat := NewChat()
	
	// Add user message
	chat.AddMessage(UserMessage, "Hello, world!", "user")
	
	if len(chat.messages) != 1 {
		t.Fatalf("Expected 1 message, got %d", len(chat.messages))
	}
	
	msg := chat.messages[0]
	if msg.Type != UserMessage {
		t.Errorf("Expected UserMessage type, got %v", msg.Type)
	}
	if msg.Content != "Hello, world!" {
		t.Errorf("Expected content 'Hello, world!', got '%s'", msg.Content)
	}
	if msg.Author != "user" {
		t.Errorf("Expected author 'user', got '%s'", msg.Author)
	}
}

func TestChat_Update(t *testing.T) {
	chat := NewChat()
	chat.focused = true
	
	// Test sending a message with Enter
	msg := tea.KeyMsg{Type: tea.KeyEnter}
	chat.input.SetValue("Test message")
	
	updatedChat, cmd := chat.Update(msg)
	if cmd == nil {
		t.Error("Expected command to be returned when sending message")
	}
	
	// Execute the command to get the message
	sentMsg := cmd()
	if sentMsg == nil {
		t.Error("Expected message to be sent")
	}
	
	if chatMsg, ok := sentMsg.(ChatMessageSentMsg); ok {
		if chatMsg.Content != "Test message" {
			t.Errorf("Expected 'Test message', got '%s'", chatMsg.Content)
		}
	} else {
		t.Errorf("Expected ChatMessageSentMsg, got %T", sentMsg)
	}
	
	// Input should be cleared after sending
	if updatedChat.(Chat).input.Value() != "" {
		t.Error("Expected input to be cleared after sending")
	}
}

func TestChat_SetSize(t *testing.T) {
	chat := NewChat()
	
	chat.SetSize(100, 50)
	
	if chat.width != 100 {
		t.Errorf("Expected width 100, got %d", chat.width)
	}
	
	if chat.height != 50 {
		t.Errorf("Expected height 50, got %d", chat.height)
	}
	
	// Viewport should be resized (accounting for input area)
	expectedViewportHeight := 50 - 5 // Leave room for input
	if chat.viewport.Height != expectedViewportHeight {
		t.Errorf("Expected viewport height %d, got %d", expectedViewportHeight, chat.viewport.Height)
	}
}

func TestChat_View(t *testing.T) {
	chat := NewChat()
	chat.SetSize(80, 24)
	
	// Add some messages
	chat.AddMessage(UserMessage, "Hello", "user")
	chat.AddMessage(AssistantMessage, "Hi there!", "assistant")
	
	view := chat.View()
	if view == "" {
		t.Error("Expected non-empty view")
	}
	
	// Should contain the viewport and input
	if len(view) == 0 {
		t.Error("Expected view to have content")
	}
}

func TestChat_Focus(t *testing.T) {
	chat := NewChat()
	
	// Initially focused
	if !chat.focused {
		t.Error("Expected chat to be focused initially")
	}
	
	// Blur the chat
	chat.Blur()
	if chat.focused {
		t.Error("Expected chat to be unfocused after Blur()")
	}
	
	// Focus the chat
	chat.Focus()
	if !chat.focused {
		t.Error("Expected chat to be focused after Focus()")
	}
}

func TestChat_MessageFormatting(t *testing.T) {
	chat := NewChat()
	
	// Test different message types
	chat.AddMessage(UserMessage, "User input", "user")
	chat.AddMessage(AssistantMessage, "Assistant response", "assistant")
	chat.AddMessage(SystemMessage, "System notification", "system")
	chat.AddMessage(ErrorMessage, "Error occurred", "system")
	
	if len(chat.messages) != 4 {
		t.Errorf("Expected 4 messages, got %d", len(chat.messages))
	}
	
	// Each message type should have appropriate formatting
	content := chat.buildViewportContent()
	if content == "" {
		t.Error("Expected formatted content")
	}
}

func TestChat_HandleMultilineInput(t *testing.T) {
	chat := NewChat()
	chat.focused = true
	
	// Test Ctrl+Enter for newline
	msg := tea.KeyMsg{Type: tea.KeyCtrlJ} // Often used for newline in terminals
	chat.input.SetValue("Line 1")
	
	updatedChat, cmd := chat.Update(msg)
	if cmd != nil {
		t.Error("Expected no command for newline input")
	}
	
	// Should have newline appended
	inputChat := updatedChat.(Chat)
	if inputChat.input.Value() != "Line 1\n" {
		t.Errorf("Expected 'Line 1\\n', got '%s'", inputChat.input.Value())
	}
}

func TestChat_EmptyMessageNotSent(t *testing.T) {
	chat := NewChat()
	chat.focused = true
	
	// Test sending empty message
	msg := tea.KeyMsg{Type: tea.KeyEnter}
	chat.input.SetValue("   ") // Just whitespace
	
	_, cmd := chat.Update(msg)
	if cmd != nil {
		t.Error("Expected no command for empty message")
	}
}

func TestChatMessage_Timestamp(t *testing.T) {
	chat := NewChat()
	
	beforeTime := time.Now()
	chat.AddMessage(UserMessage, "Test", "user")
	afterTime := time.Now()
	
	msg := chat.messages[0]
	if msg.Timestamp.Before(beforeTime) || msg.Timestamp.After(afterTime) {
		t.Error("Expected timestamp to be set to current time")
	}
}