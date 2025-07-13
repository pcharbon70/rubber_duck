package commands

import (
	"fmt"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// LocalHandler handles commands that are processed entirely within the TUI
type LocalHandler struct {
	handlers map[string]LocalCommandHandler
	stats    map[string]*CommandStats
}

// LocalCommandHandler defines the interface for local command handlers
type LocalCommandHandler func(args map[string]interface{}, context CommandContext) tea.Cmd

// NewLocalHandler creates a new local command handler
func NewLocalHandler() *LocalHandler {
	handler := &LocalHandler{
		handlers: make(map[string]LocalCommandHandler),
		stats:    make(map[string]*CommandStats),
	}

	// Register default local command handlers
	handler.registerDefaultHandlers()

	return handler
}

// ExecuteCommand executes a local command
func (lh *LocalHandler) ExecuteCommand(commandName string, args map[string]interface{}, context CommandContext) tea.Cmd {
	startTime := time.Now()

	handler, exists := lh.handlers[commandName]
	if !exists {
		return func() tea.Msg {
			return UnifiedResponse{
				Command:   commandName,
				Status:    "error",
				Error:     &CommandError{
					Code:    "LOCAL_COMMAND_NOT_FOUND",
					Message: fmt.Sprintf("Local command '%s' not found", commandName),
				},
				Timestamp: time.Now(),
			}
		}
	}

	// Update stats
	lh.updateStats(commandName, "started")

	// Execute the handler
	cmd := handler(args, context)
	
	duration := time.Since(startTime)
	lh.updateStatsWithDuration(commandName, duration, true)

	// If cmd is nil, return a success response
	if cmd == nil {
		return func() tea.Msg {
			return UnifiedResponse{
				Command:   commandName,
				Status:    "success",
				Content:   fmt.Sprintf("Command '%s' executed successfully", commandName),
				Duration:  duration,
				Timestamp: time.Now(),
			}
		}
	}

	// Wrap the command to add response metadata
	return func() tea.Msg {
		msg := cmd()
		if response, ok := msg.(UnifiedResponse); ok {
			response.Duration = duration
			if response.Timestamp.IsZero() {
				response.Timestamp = time.Now()
			}
			return response
		}
		return msg
	}
}

// RegisterHandler registers a new local command handler
func (lh *LocalHandler) RegisterHandler(commandName string, handler LocalCommandHandler) {
	lh.handlers[commandName] = handler
}

// GetStats returns statistics for local command execution
func (lh *LocalHandler) GetStats() map[string]*CommandStats {
	result := make(map[string]*CommandStats)
	for name, stats := range lh.stats {
		statsCopy := *stats
		result[name] = &statsCopy
	}
	return result
}

// registerDefaultHandlers registers the default local command handlers
func (lh *LocalHandler) registerDefaultHandlers() {
	// Help command
	lh.RegisterHandler("help", func(args map[string]interface{}, context CommandContext) tea.Cmd {
		return func() tea.Msg {
			return ShowHelpMsg{
				Topic: getStringArg(args, "topic", "general"),
			}
		}
	})

	// Settings command
	lh.RegisterHandler("settings", func(args map[string]interface{}, context CommandContext) tea.Cmd {
		return func() tea.Msg {
			return ShowSettingsMsg{
				Tab: getStringArg(args, "tab", "general"),
			}
		}
	})

	// Theme toggle command
	lh.RegisterHandler("toggle_theme", func(args map[string]interface{}, context CommandContext) tea.Cmd {
		return func() tea.Msg {
			return ToggleThemeMsg{}
		}
	})

	// Clear output command
	lh.RegisterHandler("clear_output", func(args map[string]interface{}, context CommandContext) tea.Cmd {
		return func() tea.Msg {
			return ClearOutputMsg{}
		}
	})

	// Performance stats command
	lh.RegisterHandler("performance_stats", func(args map[string]interface{}, context CommandContext) tea.Cmd {
		return func() tea.Msg {
			return ShowPerformanceStatsMsg{
				Detailed: getBoolArg(args, "detailed", false),
			}
		}
	})

	// Clear cache command
	lh.RegisterHandler("clear_cache", func(args map[string]interface{}, context CommandContext) tea.Cmd {
		return func() tea.Msg {
			return ClearCacheMsg{
				CacheType: getStringArg(args, "type", "all"),
			}
		}
	})

	// New file command
	lh.RegisterHandler("new_file", func(args map[string]interface{}, context CommandContext) tea.Cmd {
		return func() tea.Msg {
			return ShowInputModalMsg{
				Title:       "New File",
				Prompt:      "Enter the file name:",
				Placeholder: "example.go",
				Action:      "create_file",
			}
		}
	})

	// Save file command
	lh.RegisterHandler("save_file", func(args map[string]interface{}, context CommandContext) tea.Cmd {
		return func() tea.Msg {
			return SaveFileMsg{
				Path:    context.CurrentFile,
				Content: context.EditorContent,
				Force:   getBoolArg(args, "force", false),
			}
		}
	})

	// Close file command
	lh.RegisterHandler("close_file", func(args map[string]interface{}, context CommandContext) tea.Cmd {
		return func() tea.Msg {
			return CloseFileMsg{
				Path: context.CurrentFile,
				Save: getBoolArg(args, "save", true),
			}
		}
	})

	// Focus command (switch between panes)
	lh.RegisterHandler("focus", func(args map[string]interface{}, context CommandContext) tea.Cmd {
		return func() tea.Msg {
			return FocusPaneMsg{
				Pane: getStringArg(args, "pane", "next"),
			}
		}
	})

	// Search command (local file search)
	lh.RegisterHandler("search", func(args map[string]interface{}, context CommandContext) tea.Cmd {
		return func() tea.Msg {
			return ShowSearchMsg{
				Query:     getStringArg(args, "query", ""),
				Scope:     getStringArg(args, "scope", "current_file"),
				CaseSensitive: getBoolArg(args, "case_sensitive", false),
			}
		}
	})

	// Go to line command
	lh.RegisterHandler("goto_line", func(args map[string]interface{}, context CommandContext) tea.Cmd {
		return func() tea.Msg {
			return GotoLineMsg{
				Line: getIntArg(args, "line", 1),
			}
		}
	})

	// Command palette command
	lh.RegisterHandler("command_palette", func(args map[string]interface{}, context CommandContext) tea.Cmd {
		return func() tea.Msg {
			return ShowCommandPaletteMsg{
				Filter: getStringArg(args, "filter", ""),
			}
		}
	})
	
	// Chat command (for regular chat messages - this would normally go to server)
	lh.RegisterHandler("chat", func(args map[string]interface{}, context CommandContext) tea.Cmd {
		return func() tea.Msg {
			// For now, echo back as assistant message
			message := getStringArg(args, "message", "")
			response := fmt.Sprintf("Echo: %s (This would normally go to the AI server)", message)
			
			return ChatMessageReceivedMsg{
				Content: response,
				Type:    "assistant",
			}
		}
	})
}

// updateStats updates command execution statistics
func (lh *LocalHandler) updateStats(commandName, event string) {
	stats, exists := lh.stats[commandName]
	if !exists {
		stats = &CommandStats{
			CommandName: commandName,
		}
		lh.stats[commandName] = stats
	}

	switch event {
	case "started":
		stats.ExecutionCount++
		stats.LastExecuted = time.Now()
	case "completed":
		stats.SuccessCount++
	case "error":
		stats.ErrorCount++
	}
}

// updateStatsWithDuration updates stats with execution duration
func (lh *LocalHandler) updateStatsWithDuration(commandName string, duration time.Duration, success bool) {
	stats := lh.stats[commandName]
	if stats == nil {
		return
	}

	stats.TotalDuration += duration
	if stats.ExecutionCount > 0 {
		stats.AverageLatency = stats.TotalDuration / time.Duration(stats.ExecutionCount)
	}

	if success {
		stats.SuccessCount++
	} else {
		stats.ErrorCount++
	}
}

// Helper functions for argument extraction

func getStringArg(args map[string]interface{}, key, defaultValue string) string {
	if value, exists := args[key]; exists {
		if str, ok := value.(string); ok {
			return str
		}
	}
	return defaultValue
}

func getBoolArg(args map[string]interface{}, key string, defaultValue bool) bool {
	if value, exists := args[key]; exists {
		if b, ok := value.(bool); ok {
			return b
		}
		// Try to parse string representations
		if str, ok := value.(string); ok {
			switch str {
			case "true", "1", "yes", "on":
				return true
			case "false", "0", "no", "off":
				return false
			}
		}
	}
	return defaultValue
}

func getIntArg(args map[string]interface{}, key string, defaultValue int) int {
	if value, exists := args[key]; exists {
		if i, ok := value.(int); ok {
			return i
		}
		if f, ok := value.(float64); ok {
			return int(f)
		}
	}
	return defaultValue
}

// Message types for local commands

type ShowHelpMsg struct {
	Topic string
}

type ShowSettingsMsg struct {
	Tab string
}

type ToggleThemeMsg struct{}

type ClearOutputMsg struct{}

type ShowPerformanceStatsMsg struct {
	Detailed bool
}

type ClearCacheMsg struct {
	CacheType string
}

type ShowInputModalMsg struct {
	Title       string
	Prompt      string
	Placeholder string
	Action      string
}

type SaveFileMsg struct {
	Path    string
	Content string
	Force   bool
}

type CloseFileMsg struct {
	Path string
	Save bool
}

type FocusPaneMsg struct {
	Pane string
}

type ShowSearchMsg struct {
	Query         string
	Scope         string
	CaseSensitive bool
}

type GotoLineMsg struct {
	Line int
}

type ShowCommandPaletteMsg struct {
	Filter string
}

// Chat message types (defined here to avoid circular imports)
type ChatMessageReceivedMsg struct {
	Content string
	Type    string
}