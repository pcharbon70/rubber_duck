package commands

import (
	"testing"
	"time"
)

func TestUnifiedCommand_ToJSON(t *testing.T) {
	cmd := UnifiedCommand{
		Command: "analyze",
		Args: map[string]interface{}{
			"file": "main.go",
		},
		Options: map[string]interface{}{
			"format": "json",
		},
		Context: CommandContext{
			ClientType:   "tui",
			CurrentFile:  "main.go",
			Language:     "go",
			CursorLine:   10,
			CursorColumn: 5,
		},
	}

	jsonStr, err := cmd.ToJSON()
	if err != nil {
		t.Fatalf("ToJSON failed: %v", err)
	}

	if jsonStr == "" {
		t.Error("Expected non-empty JSON string")
	}

	// Test that we can parse it back
	var parsed UnifiedCommand
	err = parsed.FromJSON(jsonStr)
	if err != nil {
		t.Fatalf("FromJSON failed: %v", err)
	}

	if parsed.Command != cmd.Command {
		t.Errorf("Expected command %s, got %s", cmd.Command, parsed.Command)
	}
}

func TestUnifiedCommand_FromJSON(t *testing.T) {
	jsonStr := `{
		"command": "generate",
		"args": {"prompt": "create a function"},
		"options": {"language": "go"},
		"context": {
			"client_type": "tui",
			"current_file": "test.go",
			"language": "go"
		}
	}`

	var cmd UnifiedCommand
	err := cmd.FromJSON(jsonStr)
	if err != nil {
		t.Fatalf("FromJSON failed: %v", err)
	}

	if cmd.Command != "generate" {
		t.Errorf("Expected command 'generate', got '%s'", cmd.Command)
	}

	if cmd.Context.ClientType != "tui" {
		t.Errorf("Expected client_type 'tui', got '%s'", cmd.Context.ClientType)
	}
}

func TestUnifiedCommand_IsValid(t *testing.T) {
	tests := []struct {
		name     string
		cmd      UnifiedCommand
		expected bool
	}{
		{
			name: "valid command",
			cmd: UnifiedCommand{
				Command: "analyze",
				Context: CommandContext{ClientType: "tui"},
			},
			expected: true,
		},
		{
			name: "missing command",
			cmd: UnifiedCommand{
				Context: CommandContext{ClientType: "tui"},
			},
			expected: false,
		},
		{
			name: "missing client type",
			cmd: UnifiedCommand{
				Command: "analyze",
				Context: CommandContext{},
			},
			expected: false,
		},
		{
			name:     "empty command",
			cmd:      UnifiedCommand{},
			expected: false,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			result := test.cmd.IsValid()
			if result != test.expected {
				t.Errorf("Expected %v, got %v", test.expected, result)
			}
		})
	}
}

func TestCommandContext_SetTUIContext(t *testing.T) {
	var ctx CommandContext
	ctx.SetTUIContext("main.go", "package main", "go", 10, 5)

	if ctx.ClientType != "tui" {
		t.Errorf("Expected client_type 'tui', got '%s'", ctx.ClientType)
	}

	if ctx.CurrentFile != "main.go" {
		t.Errorf("Expected current_file 'main.go', got '%s'", ctx.CurrentFile)
	}

	if ctx.EditorContent != "package main" {
		t.Errorf("Expected editor_content 'package main', got '%s'", ctx.EditorContent)
	}

	if ctx.Language != "go" {
		t.Errorf("Expected language 'go', got '%s'", ctx.Language)
	}

	if ctx.CursorLine != 10 {
		t.Errorf("Expected cursor_line 10, got %d", ctx.CursorLine)
	}

	if ctx.CursorColumn != 5 {
		t.Errorf("Expected cursor_column 5, got %d", ctx.CursorColumn)
	}
}

func TestCommandContext_AddMetadata(t *testing.T) {
	var ctx CommandContext
	ctx.AddMetadata("test_key", "test_value")
	ctx.AddMetadata("number", 42)

	if ctx.Metadata == nil {
		t.Fatal("Expected metadata to be initialized")
	}

	if ctx.Metadata["test_key"] != "test_value" {
		t.Errorf("Expected metadata test_key to be 'test_value', got %v", ctx.Metadata["test_key"])
	}

	if ctx.Metadata["number"] != 42 {
		t.Errorf("Expected metadata number to be 42, got %v", ctx.Metadata["number"])
	}
}

func TestUnifiedResponse_IsSuccess(t *testing.T) {
	tests := []struct {
		name     string
		response UnifiedResponse
		expected bool
	}{
		{
			name:     "success status",
			response: UnifiedResponse{Status: "success"},
			expected: true,
		},
		{
			name:     "error status",
			response: UnifiedResponse{Status: "error"},
			expected: false,
		},
		{
			name:     "pending status",
			response: UnifiedResponse{Status: "pending"},
			expected: false,
		},
		{
			name:     "empty status",
			response: UnifiedResponse{},
			expected: false,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			result := test.response.IsSuccess()
			if result != test.expected {
				t.Errorf("Expected %v, got %v", test.expected, result)
			}
		})
	}
}

func TestUnifiedResponse_IsError(t *testing.T) {
	tests := []struct {
		name     string
		response UnifiedResponse
		expected bool
	}{
		{
			name:     "error status",
			response: UnifiedResponse{Status: "error"},
			expected: true,
		},
		{
			name:     "success status",
			response: UnifiedResponse{Status: "success"},
			expected: false,
		},
		{
			name:     "pending status",
			response: UnifiedResponse{Status: "pending"},
			expected: false,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			result := test.response.IsError()
			if result != test.expected {
				t.Errorf("Expected %v, got %v", test.expected, result)
			}
		})
	}
}

func TestUnifiedResponse_IsStreaming(t *testing.T) {
	tests := []struct {
		name     string
		response UnifiedResponse
		expected bool
	}{
		{
			name:     "streaming status",
			response: UnifiedResponse{Status: "streaming"},
			expected: true,
		},
		{
			name:     "has stream info",
			response: UnifiedResponse{Stream: &StreamInfo{ID: "test"}},
			expected: true,
		},
		{
			name:     "success status",
			response: UnifiedResponse{Status: "success"},
			expected: false,
		},
		{
			name:     "no stream info",
			response: UnifiedResponse{Status: "pending"},
			expected: false,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			result := test.response.IsStreaming()
			if result != test.expected {
				t.Errorf("Expected %v, got %v", test.expected, result)
			}
		})
	}
}

func TestCommandError_Error(t *testing.T) {
	err := &CommandError{
		Code:    "TEST_ERROR",
		Message: "This is a test error",
	}

	if err.Error() != "This is a test error" {
		t.Errorf("Expected error message 'This is a test error', got '%s'", err.Error())
	}
}

func TestBuildTUIContext(t *testing.T) {
	ctx := BuildTUIContext("main.go", "package main", "go", 10, 5)

	if ctx.CurrentFile != "main.go" {
		t.Errorf("Expected current_file 'main.go', got '%s'", ctx.CurrentFile)
	}

	if ctx.EditorContent != "package main" {
		t.Errorf("Expected editor_content 'package main', got '%s'", ctx.EditorContent)
	}

	if ctx.Language != "go" {
		t.Errorf("Expected language 'go', got '%s'", ctx.Language)
	}

	if ctx.CursorLine != 10 {
		t.Errorf("Expected cursor_line 10, got %d", ctx.CursorLine)
	}

	if ctx.CursorColumn != 5 {
		t.Errorf("Expected cursor_column 5, got %d", ctx.CursorColumn)
	}

	if ctx.Metadata == nil {
		t.Error("Expected metadata to be initialized")
	}
}

func TestCommandDefinition_Validation(t *testing.T) {
	// Test valid command definition
	validDef := CommandDefinition{
		Name:        "test_command",
		Description: "A test command",
		Category:    "Test",
		Type:        LocalCommand,
		Args: []ArgDef{
			{Name: "arg1", Description: "First argument", Type: "string", Required: true},
		},
		Options: []OptDef{
			{Name: "verbose", Description: "Verbose output", Type: "bool", Default: false},
		},
	}

	// This would be tested in registry_test.go with the ValidateCommand method
	_ = validDef
}

func TestProgressInfo(t *testing.T) {
	progress := ProgressInfo{
		Current:     50,
		Total:       100,
		Percentage:  50,
		Message:     "Processing...",
		Cancellable: true,
	}

	if progress.Current != 50 {
		t.Errorf("Expected current 50, got %d", progress.Current)
	}

	if progress.Percentage != 50 {
		t.Errorf("Expected percentage 50, got %d", progress.Percentage)
	}

	if !progress.Cancellable {
		t.Error("Expected progress to be cancellable")
	}
}

func TestStreamInfo(t *testing.T) {
	stream := StreamInfo{
		ID:       "stream123",
		Event:    "data",
		Sequence: 5,
		Final:    false,
	}

	if stream.ID != "stream123" {
		t.Errorf("Expected ID 'stream123', got '%s'", stream.ID)
	}

	if stream.Event != "data" {
		t.Errorf("Expected event 'data', got '%s'", stream.Event)
	}

	if stream.Sequence != 5 {
		t.Errorf("Expected sequence 5, got %d", stream.Sequence)
	}

	if stream.Final {
		t.Error("Expected stream to not be final")
	}
}

func TestCommandStats(t *testing.T) {
	stats := CommandStats{
		CommandName:     "test_command",
		ExecutionCount:  10,
		SuccessCount:    8,
		ErrorCount:      2,
		AverageLatency:  100 * time.Millisecond,
		LastExecuted:    time.Now(),
		TotalDuration:   1 * time.Second,
	}

	if stats.CommandName != "test_command" {
		t.Errorf("Expected command name 'test_command', got '%s'", stats.CommandName)
	}

	if stats.ExecutionCount != 10 {
		t.Errorf("Expected execution count 10, got %d", stats.ExecutionCount)
	}

	if stats.SuccessCount != 8 {
		t.Errorf("Expected success count 8, got %d", stats.SuccessCount)
	}

	if stats.ErrorCount != 2 {
		t.Errorf("Expected error count 2, got %d", stats.ErrorCount)
	}
}