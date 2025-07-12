package commands

import (
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

func TestNewResponseHandler(t *testing.T) {
	handler := NewResponseHandler()

	if handler == nil {
		t.Fatal("Expected non-nil handler")
	}

	if handler.pendingCommands == nil {
		t.Error("Expected pendingCommands map to be initialized")
	}

	if handler.stats == nil {
		t.Error("Expected stats map to be initialized")
	}
}

func TestTrackCommand(t *testing.T) {
	handler := NewResponseHandler()

	cmd := UnifiedCommand{
		Command: "test_command",
		Context: CommandContext{ClientType: "tui"},
	}

	requestID := handler.TrackCommand(cmd, 5*time.Second, nil)

	if requestID == "" {
		t.Error("Expected non-empty request ID")
	}

	pending := handler.GetPendingCommands()
	if len(pending) != 1 {
		t.Errorf("Expected 1 pending command, got %d", len(pending))
	}

	if _, exists := pending[requestID]; !exists {
		t.Error("Expected pending command to be tracked")
	}
}

func TestTrackCommandWithCallback(t *testing.T) {
	handler := NewResponseHandler()
	callbackCalled := false

	callback := func(response UnifiedResponse) tea.Cmd {
		callbackCalled = true
		return nil
	}

	cmd := UnifiedCommand{
		Command: "test_command",
		Context: CommandContext{ClientType: "tui"},
	}

	requestID := handler.TrackCommand(cmd, 5*time.Second, callback)

	// Simulate successful response
	response := UnifiedResponse{
		RequestID: requestID,
		Command:   "test_command",
		Status:    "success",
		Content:   "Test result",
	}

	handler.HandleResponse(response)

	if !callbackCalled {
		t.Error("Expected callback to be called")
	}

	// Command should be removed from pending
	pending := handler.GetPendingCommands()
	if len(pending) != 0 {
		t.Errorf("Expected 0 pending commands after response, got %d", len(pending))
	}
}

func TestHandleSuccessResponse(t *testing.T) {
	handler := NewResponseHandler()

	cmd := UnifiedCommand{
		Command: "success_test",
		Context: CommandContext{ClientType: "tui"},
	}

	requestID := handler.TrackCommand(cmd, 5*time.Second, nil)

	// Wait a bit to ensure latency is measurable
	time.Sleep(1 * time.Millisecond)

	response := UnifiedResponse{
		RequestID: requestID,
		Command:   "success_test",
		Status:    "success",
		Content:   "Success result",
	}

	cmdResult := handler.HandleResponse(response)
	if cmdResult == nil {
		t.Error("Expected non-nil command result")
	}

	// Check that statistics were updated
	stats := handler.GetResponseStats()
	if _, exists := stats["success_test"]; !exists {
		t.Error("Expected stats for success_test command")
	}

	commandStats := stats["success_test"]
	if commandStats.SuccessCount != 1 {
		t.Errorf("Expected success count 1, got %d", commandStats.SuccessCount)
	}

	if commandStats.TotalRequests != 1 {
		t.Errorf("Expected total requests 1, got %d", commandStats.TotalRequests)
	}
}

func TestHandleErrorResponse(t *testing.T) {
	handler := NewResponseHandler()

	cmd := UnifiedCommand{
		Command: "error_test",
		Context: CommandContext{ClientType: "tui"},
	}

	requestID := handler.TrackCommand(cmd, 5*time.Second, nil)

	response := UnifiedResponse{
		RequestID: requestID,
		Command:   "error_test",
		Status:    "error",
		Error: &CommandError{
			Code:    "TEST_ERROR",
			Message: "Test error message",
		},
	}

	cmdResult := handler.HandleResponse(response)
	if cmdResult == nil {
		t.Error("Expected non-nil command result")
	}

	// Check that error statistics were updated
	stats := handler.GetResponseStats()
	commandStats := stats["error_test"]
	if commandStats.ErrorCount != 1 {
		t.Errorf("Expected error count 1, got %d", commandStats.ErrorCount)
	}
}

func TestHandleUnsolicitedResponse(t *testing.T) {
	handler := NewResponseHandler()

	// Response with no matching pending command
	response := UnifiedResponse{
		RequestID: "unknown_id",
		Command:   "unsolicited_command",
		Status:    "success",
		Content:   "Unsolicited data",
	}

	cmdResult := handler.HandleResponse(response)
	if cmdResult == nil {
		t.Error("Expected non-nil command result for unsolicited response")
	}

	// Execute the command to check the message type
	msg := cmdResult()
	if _, ok := msg.(UnsolicitedResponseMsg); !ok {
		t.Errorf("Expected UnsolicitedResponseMsg, got %T", msg)
	}
}

func TestHandleTimeout(t *testing.T) {
	handler := NewResponseHandler()

	cmd := UnifiedCommand{
		Command: "timeout_test",
		Context: CommandContext{ClientType: "tui"},
	}

	requestID := handler.TrackCommand(cmd, 100*time.Millisecond, nil)

	// Manually trigger timeout
	cmdResult := handler.HandleTimeout(requestID)
	if cmdResult == nil {
		t.Error("Expected non-nil command result for timeout")
	}

	// Check that command was removed from pending
	pending := handler.GetPendingCommands()
	if len(pending) != 0 {
		t.Errorf("Expected 0 pending commands after timeout, got %d", len(pending))
	}

	// Check that timeout statistics were updated
	stats := handler.GetResponseStats()
	commandStats := stats["timeout_test"]
	if commandStats.TimeoutCount != 1 {
		t.Errorf("Expected timeout count 1, got %d", commandStats.TimeoutCount)
	}
}

func TestCheckTimeouts(t *testing.T) {
	handler := NewResponseHandler()

	// Track a command with very short timeout
	cmd := UnifiedCommand{
		Command: "quick_timeout",
		Context: CommandContext{ClientType: "tui"},
	}

	handler.TrackCommand(cmd, 1*time.Nanosecond, nil) // Immediate timeout

	// Wait a bit to ensure timeout
	time.Sleep(1 * time.Millisecond)

	timeoutCmds := handler.CheckTimeouts()
	if len(timeoutCmds) != 1 {
		t.Errorf("Expected 1 timeout command, got %d", len(timeoutCmds))
	}

	// Check that no pending commands remain
	pending := handler.GetPendingCommands()
	if len(pending) != 0 {
		t.Errorf("Expected 0 pending commands after timeout check, got %d", len(pending))
	}
}

func TestRetryLogic(t *testing.T) {
	handler := NewResponseHandler()

	cmd := UnifiedCommand{
		Command: "retry_test",
		Context: CommandContext{ClientType: "tui"},
	}

	requestID := handler.TrackCommand(cmd, 100*time.Millisecond, nil)

	// Get the pending command and modify retry count
	pending := handler.pendingCommands[requestID]
	pending.MaxRetries = 2

	// First timeout should trigger retry
	cmdResult := handler.HandleTimeout(requestID)
	if cmdResult == nil {
		t.Error("Expected non-nil command result for retry")
	}

	// Execute the retry command
	msg := cmdResult()
	if _, ok := msg.(RetryCommandMsg); !ok {
		t.Errorf("Expected RetryCommandMsg, got %T", msg)
	}

	// Command should still be pending (for retry)
	if _, exists := handler.pendingCommands[requestID]; exists {
		t.Error("Command should be removed from pending after final timeout")
	}
}

func TestResponseStats(t *testing.T) {
	handler := NewResponseHandler()

	// Track multiple commands
	for i := 0; i < 5; i++ {
		cmd := UnifiedCommand{
			Command: "stats_test",
			Context: CommandContext{ClientType: "tui"},
		}

		requestID := handler.TrackCommand(cmd, 5*time.Second, nil)

		// Simulate responses
		if i%2 == 0 {
			// Success responses
			response := UnifiedResponse{
				RequestID: requestID,
				Command:   "stats_test",
				Status:    "success",
				Content:   "Success",
			}
			handler.HandleResponse(response)
		} else {
			// Error responses
			response := UnifiedResponse{
				RequestID: requestID,
				Command:   "stats_test",
				Status:    "error",
				Error: &CommandError{
					Code:    "TEST_ERROR",
					Message: "Test error",
				},
			}
			handler.HandleResponse(response)
		}
	}

	stats := handler.GetResponseStats()
	commandStats := stats["stats_test"]

	if commandStats.TotalRequests != 5 {
		t.Errorf("Expected total requests 5, got %d", commandStats.TotalRequests)
	}

	if commandStats.SuccessCount != 3 {
		t.Errorf("Expected success count 3, got %d", commandStats.SuccessCount)
	}

	if commandStats.ErrorCount != 2 {
		t.Errorf("Expected error count 2, got %d", commandStats.ErrorCount)
	}
}

func TestClearStats(t *testing.T) {
	handler := NewResponseHandler()

	// Add some stats
	cmd := UnifiedCommand{
		Command: "clear_test",
		Context: CommandContext{ClientType: "tui"},
	}

	requestID := handler.TrackCommand(cmd, 5*time.Second, nil)

	response := UnifiedResponse{
		RequestID: requestID,
		Command:   "clear_test",
		Status:    "success",
	}

	handler.HandleResponse(response)

	// Verify stats exist
	stats := handler.GetResponseStats()
	if len(stats) == 0 {
		t.Error("Expected stats to exist before clear")
	}

	// Clear stats
	handler.ClearStats()

	// Verify stats are cleared
	stats = handler.GetResponseStats()
	if len(stats) != 0 {
		t.Errorf("Expected 0 stats after clear, got %d", len(stats))
	}
}

func TestParseResponseFromJSON(t *testing.T) {
	jsonData := `{
		"request_id": "test_123",
		"command": "parse_test",
		"status": "success",
		"content": "Parsed content",
		"timestamp": "2023-01-01T00:00:00Z"
	}`

	response, err := ParseResponseFromJSON([]byte(jsonData))
	if err != nil {
		t.Fatalf("Failed to parse JSON: %v", err)
	}

	if response.RequestID != "test_123" {
		t.Errorf("Expected request ID 'test_123', got '%s'", response.RequestID)
	}

	if response.Command != "parse_test" {
		t.Errorf("Expected command 'parse_test', got '%s'", response.Command)
	}

	if response.Status != "success" {
		t.Errorf("Expected status 'success', got '%s'", response.Status)
	}
}

func TestCreateErrorResponse(t *testing.T) {
	response := CreateErrorResponse("req_123", "test_cmd", "TEST_ERROR", "Test error message")

	if response.RequestID != "req_123" {
		t.Errorf("Expected request ID 'req_123', got '%s'", response.RequestID)
	}

	if response.Command != "test_cmd" {
		t.Errorf("Expected command 'test_cmd', got '%s'", response.Command)
	}

	if response.Status != "error" {
		t.Errorf("Expected status 'error', got '%s'", response.Status)
	}

	if response.Error == nil {
		t.Fatal("Expected error to be set")
	}

	if response.Error.Code != "TEST_ERROR" {
		t.Errorf("Expected error code 'TEST_ERROR', got '%s'", response.Error.Code)
	}
}

func TestCreateSuccessResponse(t *testing.T) {
	content := map[string]interface{}{
		"result": "success",
		"data":   "test data",
	}

	response := CreateSuccessResponse("req_456", "success_cmd", content)

	if response.RequestID != "req_456" {
		t.Errorf("Expected request ID 'req_456', got '%s'", response.RequestID)
	}

	if response.Command != "success_cmd" {
		t.Errorf("Expected command 'success_cmd', got '%s'", response.Command)
	}

	if response.Status != "success" {
		t.Errorf("Expected status 'success', got '%s'", response.Status)
	}

	if response.Content == nil {
		t.Fatal("Expected content to be set")
	}
}