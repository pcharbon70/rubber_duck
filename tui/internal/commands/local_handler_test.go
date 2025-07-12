package commands

import (
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

func TestNewLocalHandler(t *testing.T) {
	handler := NewLocalHandler()

	if handler == nil {
		t.Fatal("Expected non-nil handler")
	}

	if handler.handlers == nil {
		t.Error("Expected handlers map to be initialized")
	}

	if handler.stats == nil {
		t.Error("Expected stats map to be initialized")
	}

	// Check that default handlers are registered
	defaultCommands := []string{
		"help", "settings", "toggle_theme", "clear_output",
		"performance_stats", "clear_cache", "new_file", "save_file",
		"close_file", "focus", "search", "goto_line", "command_palette",
	}

	for _, cmdName := range defaultCommands {
		if _, exists := handler.handlers[cmdName]; !exists {
			t.Errorf("Expected default handler for '%s' to be registered", cmdName)
		}
	}
}

func TestLocalHandler_RegisterHandler(t *testing.T) {
	handler := NewLocalHandler()

	testHandler := func(args map[string]interface{}, context CommandContext) tea.Cmd {
		return nil
	}

	handler.RegisterHandler("test_command", testHandler)

	if _, exists := handler.handlers["test_command"]; !exists {
		t.Error("Expected test_command to be registered")
	}
}

func TestLocalHandler_ExecuteCommand(t *testing.T) {
	handler := NewLocalHandler()

	// Test unknown command
	cmd := handler.ExecuteCommand("unknown_command", map[string]interface{}{}, CommandContext{})
	if cmd == nil {
		t.Fatal("Expected non-nil command")
	}

	msg := cmd()
	response, ok := msg.(UnifiedResponse)
	if !ok {
		t.Fatal("Expected UnifiedResponse message")
	}

	if response.Status != "error" {
		t.Errorf("Expected error status, got %s", response.Status)
	}

	if response.Error == nil || response.Error.Code != "LOCAL_COMMAND_NOT_FOUND" {
		t.Error("Expected LOCAL_COMMAND_NOT_FOUND error")
	}
}

func TestLocalHandler_ExecuteCommand_Success(t *testing.T) {
	handler := NewLocalHandler()

	// Register a test handler that returns nil (success)
	handler.RegisterHandler("success_test", func(args map[string]interface{}, context CommandContext) tea.Cmd {
		return nil
	})

	cmd := handler.ExecuteCommand("success_test", map[string]interface{}{}, CommandContext{})
	if cmd == nil {
		t.Fatal("Expected non-nil command")
	}

	msg := cmd()
	response, ok := msg.(UnifiedResponse)
	if !ok {
		t.Fatal("Expected UnifiedResponse message")
	}

	if response.Status != "success" {
		t.Errorf("Expected success status, got %s", response.Status)
	}

	if response.Duration == 0 {
		t.Error("Expected non-zero duration")
	}
}

func TestLocalHandler_ExecuteCommand_WithResponse(t *testing.T) {
	handler := NewLocalHandler()

	// Register a test handler that returns a custom response
	handler.RegisterHandler("custom_response", func(args map[string]interface{}, context CommandContext) tea.Cmd {
		return func() tea.Msg {
			return UnifiedResponse{
				Command: "custom_response",
				Status:  "success",
				Content: "Custom response content",
			}
		}
	})

	cmd := handler.ExecuteCommand("custom_response", map[string]interface{}{}, CommandContext{})
	if cmd == nil {
		t.Fatal("Expected non-nil command")
	}

	msg := cmd()
	response, ok := msg.(UnifiedResponse)
	if !ok {
		t.Fatal("Expected UnifiedResponse message")
	}

	if response.Content != "Custom response content" {
		t.Errorf("Expected custom content, got %s", response.Content)
	}

	if response.Duration == 0 {
		t.Error("Expected non-zero duration to be added")
	}
}

func TestLocalHandler_GetStats(t *testing.T) {
	handler := NewLocalHandler()

	// Execute a command to generate stats
	handler.RegisterHandler("stats_test", func(args map[string]interface{}, context CommandContext) tea.Cmd {
		return nil
	})

	// Execute the command
	cmd := handler.ExecuteCommand("stats_test", map[string]interface{}{}, CommandContext{})
	cmd() // Execute to update stats

	stats := handler.GetStats()
	if len(stats) == 0 {
		t.Error("Expected stats to be recorded")
	}

	cmdStats, exists := stats["stats_test"]
	if !exists {
		t.Error("Expected stats for stats_test command")
	}

	if cmdStats.ExecutionCount != 1 {
		t.Errorf("Expected execution count 1, got %d", cmdStats.ExecutionCount)
	}

	if cmdStats.SuccessCount != 1 {
		t.Errorf("Expected success count 1, got %d", cmdStats.SuccessCount)
	}
}

func TestLocalHandler_DefaultHandlers(t *testing.T) {
	handler := NewLocalHandler()
	context := CommandContext{ClientType: "tui"}

	tests := []struct {
		name     string
		command  string
		args     map[string]interface{}
		expected string // Expected message type or content
	}{
		{
			name:     "help command",
			command:  "help",
			args:     map[string]interface{}{},
			expected: "ShowHelpMsg",
		},
		{
			name:     "help with topic",
			command:  "help",
			args:     map[string]interface{}{"topic": "commands"},
			expected: "ShowHelpMsg",
		},
		{
			name:     "settings command",
			command:  "settings",
			args:     map[string]interface{}{},
			expected: "ShowSettingsMsg",
		},
		{
			name:     "toggle theme",
			command:  "toggle_theme",
			args:     map[string]interface{}{},
			expected: "ToggleThemeMsg",
		},
		{
			name:     "clear output",
			command:  "clear_output",
			args:     map[string]interface{}{},
			expected: "ClearOutputMsg",
		},
		{
			name:     "performance stats",
			command:  "performance_stats",
			args:     map[string]interface{}{},
			expected: "ShowPerformanceStatsMsg",
		},
		{
			name:     "performance stats detailed",
			command:  "performance_stats",
			args:     map[string]interface{}{"detailed": true},
			expected: "ShowPerformanceStatsMsg",
		},
		{
			name:     "clear cache",
			command:  "clear_cache",
			args:     map[string]interface{}{},
			expected: "ClearCacheMsg",
		},
		{
			name:     "new file",
			command:  "new_file",
			args:     map[string]interface{}{},
			expected: "ShowInputModalMsg",
		},
		{
			name:     "save file",
			command:  "save_file",
			args:     map[string]interface{}{},
			expected: "SaveFileMsg",
		},
		{
			name:     "close file",
			command:  "close_file",
			args:     map[string]interface{}{},
			expected: "CloseFileMsg",
		},
		{
			name:     "focus pane",
			command:  "focus",
			args:     map[string]interface{}{"pane": "editor"},
			expected: "FocusPaneMsg",
		},
		{
			name:     "search",
			command:  "search",
			args:     map[string]interface{}{"query": "test"},
			expected: "ShowSearchMsg",
		},
		{
			name:     "goto line",
			command:  "goto_line",
			args:     map[string]interface{}{"line": 42},
			expected: "GotoLineMsg",
		},
		{
			name:     "command palette",
			command:  "command_palette",
			args:     map[string]interface{}{},
			expected: "ShowCommandPaletteMsg",
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			cmd := handler.ExecuteCommand(test.command, test.args, context)
			if cmd == nil {
				t.Fatal("Expected non-nil command")
			}

			msg := cmd()
			
			// Check message type using type assertion
			switch test.expected {
			case "ShowHelpMsg":
				if _, ok := msg.(ShowHelpMsg); !ok {
					t.Errorf("Expected ShowHelpMsg, got %T", msg)
				}
			case "ShowSettingsMsg":
				if _, ok := msg.(ShowSettingsMsg); !ok {
					t.Errorf("Expected ShowSettingsMsg, got %T", msg)
				}
			case "ToggleThemeMsg":
				if _, ok := msg.(ToggleThemeMsg); !ok {
					t.Errorf("Expected ToggleThemeMsg, got %T", msg)
				}
			case "ClearOutputMsg":
				if _, ok := msg.(ClearOutputMsg); !ok {
					t.Errorf("Expected ClearOutputMsg, got %T", msg)
				}
			case "ShowPerformanceStatsMsg":
				if _, ok := msg.(ShowPerformanceStatsMsg); !ok {
					t.Errorf("Expected ShowPerformanceStatsMsg, got %T", msg)
				}
			case "ClearCacheMsg":
				if _, ok := msg.(ClearCacheMsg); !ok {
					t.Errorf("Expected ClearCacheMsg, got %T", msg)
				}
			case "ShowInputModalMsg":
				if _, ok := msg.(ShowInputModalMsg); !ok {
					t.Errorf("Expected ShowInputModalMsg, got %T", msg)
				}
			case "SaveFileMsg":
				if _, ok := msg.(SaveFileMsg); !ok {
					t.Errorf("Expected SaveFileMsg, got %T", msg)
				}
			case "CloseFileMsg":
				if _, ok := msg.(CloseFileMsg); !ok {
					t.Errorf("Expected CloseFileMsg, got %T", msg)
				}
			case "FocusPaneMsg":
				if _, ok := msg.(FocusPaneMsg); !ok {
					t.Errorf("Expected FocusPaneMsg, got %T", msg)
				}
			case "ShowSearchMsg":
				if _, ok := msg.(ShowSearchMsg); !ok {
					t.Errorf("Expected ShowSearchMsg, got %T", msg)
				}
			case "GotoLineMsg":
				if _, ok := msg.(GotoLineMsg); !ok {
					t.Errorf("Expected GotoLineMsg, got %T", msg)
				}
			case "ShowCommandPaletteMsg":
				if _, ok := msg.(ShowCommandPaletteMsg); !ok {
					t.Errorf("Expected ShowCommandPaletteMsg, got %T", msg)
				}
			}
		})
	}
}

func TestArgHelpers(t *testing.T) {
	args := map[string]interface{}{
		"string_arg":  "test_value",
		"bool_arg":    true,
		"int_arg":     42,
		"float_arg":   3.14,
		"bool_string": "true",
		"bool_false":  "false",
	}

	// Test getStringArg
	if getStringArg(args, "string_arg", "default") != "test_value" {
		t.Error("Expected string_arg to return 'test_value'")
	}

	if getStringArg(args, "nonexistent", "default") != "default" {
		t.Error("Expected nonexistent arg to return default value")
	}

	// Test getBoolArg
	if !getBoolArg(args, "bool_arg", false) {
		t.Error("Expected bool_arg to return true")
	}

	if getBoolArg(args, "nonexistent", false) != false {
		t.Error("Expected nonexistent bool arg to return default value")
	}

	if !getBoolArg(args, "bool_string", false) {
		t.Error("Expected bool_string 'true' to return true")
	}

	if getBoolArg(args, "bool_false", true) {
		t.Error("Expected bool_false 'false' to return false")
	}

	// Test getIntArg
	if getIntArg(args, "int_arg", 0) != 42 {
		t.Error("Expected int_arg to return 42")
	}

	if getIntArg(args, "float_arg", 0) != 3 {
		t.Error("Expected float_arg to be converted to int 3")
	}

	if getIntArg(args, "nonexistent", 99) != 99 {
		t.Error("Expected nonexistent int arg to return default value")
	}
}

func TestLocalHandler_StatsUpdate(t *testing.T) {
	handler := NewLocalHandler()

	// Register a test handler
	handler.RegisterHandler("stats_update_test", func(args map[string]interface{}, context CommandContext) tea.Cmd {
		// Simulate some work
		time.Sleep(1 * time.Millisecond)
		return nil
	})

	// Execute multiple times to test stats
	for i := 0; i < 5; i++ {
		cmd := handler.ExecuteCommand("stats_update_test", map[string]interface{}{}, CommandContext{})
		cmd() // Execute the command
	}

	stats := handler.GetStats()
	cmdStats := stats["stats_update_test"]

	if cmdStats == nil {
		t.Fatal("Expected stats for stats_update_test")
	}

	if cmdStats.ExecutionCount != 5 {
		t.Errorf("Expected execution count 5, got %d", cmdStats.ExecutionCount)
	}

	if cmdStats.SuccessCount != 5 {
		t.Errorf("Expected success count 5, got %d", cmdStats.SuccessCount)
	}

	if cmdStats.ErrorCount != 0 {
		t.Errorf("Expected error count 0, got %d", cmdStats.ErrorCount)
	}

	if cmdStats.TotalDuration == 0 {
		t.Error("Expected non-zero total duration")
	}

	if cmdStats.AverageLatency == 0 {
		t.Error("Expected non-zero average latency")
	}

	if cmdStats.LastExecuted.IsZero() {
		t.Error("Expected last executed time to be set")
	}
}

func TestMessageTypes(t *testing.T) {
	// Test ShowHelpMsg
	helpMsg := ShowHelpMsg{Topic: "commands"}
	if helpMsg.Topic != "commands" {
		t.Errorf("Expected topic 'commands', got '%s'", helpMsg.Topic)
	}

	// Test ShowSettingsMsg
	settingsMsg := ShowSettingsMsg{Tab: "general"}
	if settingsMsg.Tab != "general" {
		t.Errorf("Expected tab 'general', got '%s'", settingsMsg.Tab)
	}

	// Test ShowPerformanceStatsMsg
	perfMsg := ShowPerformanceStatsMsg{Detailed: true}
	if !perfMsg.Detailed {
		t.Error("Expected detailed to be true")
	}

	// Test SaveFileMsg
	saveMsg := SaveFileMsg{Path: "test.go", Content: "package main", Force: true}
	if saveMsg.Path != "test.go" {
		t.Errorf("Expected path 'test.go', got '%s'", saveMsg.Path)
	}
	if saveMsg.Content != "package main" {
		t.Errorf("Expected content 'package main', got '%s'", saveMsg.Content)
	}
	if !saveMsg.Force {
		t.Error("Expected force to be true")
	}

	// Test FocusPaneMsg
	focusMsg := FocusPaneMsg{Pane: "editor"}
	if focusMsg.Pane != "editor" {
		t.Errorf("Expected pane 'editor', got '%s'", focusMsg.Pane)
	}

	// Test GotoLineMsg
	gotoMsg := GotoLineMsg{Line: 42}
	if gotoMsg.Line != 42 {
		t.Errorf("Expected line 42, got %d", gotoMsg.Line)
	}
}