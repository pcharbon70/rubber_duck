package commands

import (
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/rubber_duck/tui/internal/phoenix"
)

// CommandRouter routes commands between local TUI handlers and the unified command system
type CommandRouter struct {
	unifiedClient  *UnifiedClient
	localHandler   *LocalHandler
	registry       *CommandRegistry
	config         RouterConfig
	contextBuilder *ContextBuilder
}

// NewCommandRouter creates a new command router
func NewCommandRouter(phoenixClient phoenix.PhoenixClient, config RouterConfig) *CommandRouter {
	unifiedClient := NewUnifiedClient(phoenixClient, config)
	localHandler := NewLocalHandler()
	registry := NewCommandRegistry()
	contextBuilder := NewContextBuilder()

	router := &CommandRouter{
		unifiedClient:  unifiedClient,
		localHandler:   localHandler,
		registry:       registry,
		config:         config,
		contextBuilder: contextBuilder,
	}

	// Register default commands
	router.registerDefaultCommands()

	return router
}

// ExecuteCommand routes and executes a command
func (cr *CommandRouter) ExecuteCommand(commandName string, args map[string]interface{}, tuiContext interface{}) tea.Cmd {
	// Build command context from TUI state
	context := cr.contextBuilder.BuildContext(tuiContext)

	// Apply any command-specific options
	options := cr.buildOptions(commandName, args)

	// Check if command is blocked
	if cr.isCommandBlocked(commandName) {
		return func() tea.Msg {
			return UnifiedResponse{
				Command:   commandName,
				Status:    "error",
				Error:     &CommandError{
					Code:    "COMMAND_BLOCKED",
					Message: fmt.Sprintf("Command '%s' is not allowed", commandName),
				},
				Timestamp: time.Now(),
			}
		}
	}

	// Determine command type and route accordingly
	commandDef := cr.registry.GetCommand(commandName)
	if commandDef == nil {
		return cr.handleUnknownCommand(commandName, args, context)
	}

	switch commandDef.Type {
	case LocalCommand:
		return cr.executeLocalCommand(commandName, args, context)
	case ServerCommand:
		return cr.executeServerCommand(commandName, args, options, context)
	case HybridCommand:
		return cr.executeHybridCommand(commandName, args, options, context)
	default:
		return cr.executeServerCommand(commandName, args, options, context)
	}
}

// executeLocalCommand handles commands that are processed locally in the TUI
func (cr *CommandRouter) executeLocalCommand(commandName string, args map[string]interface{}, context CommandContext) tea.Cmd {
	return cr.localHandler.ExecuteCommand(commandName, args, context)
}

// executeServerCommand sends commands to the unified command system
func (cr *CommandRouter) executeServerCommand(commandName string, args map[string]interface{}, options map[string]interface{}, context CommandContext) tea.Cmd {
	if !cr.config.EnableServerCommands {
		return func() tea.Msg {
			return UnifiedResponse{
				Command:   commandName,
				Status:    "error",
				Error:     &CommandError{
					Code:    "SERVER_COMMANDS_DISABLED",
					Message: "Server commands are disabled",
				},
				Timestamp: time.Now(),
			}
		}
	}

	// Create unified command
	cmd := UnifiedCommand{
		Command: commandName,
		Args:    args,
		Options: options,
		Context: context,
	}

	// Add default format if not specified
	if cmd.Options == nil {
		cmd.Options = make(map[string]interface{})
	}
	if _, hasFormat := cmd.Options["format"]; !hasFormat {
		cmd.Options["format"] = cr.config.DefaultFormat
	}

	// Execute via unified client
	return cr.unifiedClient.ExecuteCommand(cmd)
}

// executeHybridCommand handles commands that may use both local and server resources
func (cr *CommandRouter) executeHybridCommand(commandName string, args map[string]interface{}, options map[string]interface{}, context CommandContext) tea.Cmd {
	// For hybrid commands, we typically start with local processing
	// and may make server calls as needed
	switch commandName {
	case "analyze_project":
		// Start with local file enumeration, then send to server
		return cr.executeProjectAnalysis(args, options, context)
	case "search_code":
		// Local search for small projects, server for large ones
		return cr.executeCodeSearch(args, options, context)
	default:
		// Default to server execution for unknown hybrid commands
		return cr.executeServerCommand(commandName, args, options, context)
	}
}

// handleUnknownCommand handles commands not in the registry
func (cr *CommandRouter) handleUnknownCommand(commandName string, args map[string]interface{}, context CommandContext) tea.Cmd {
	// Try to execute as server command (might be a new command we don't know about)
	if cr.config.EnableServerCommands {
		return cr.executeServerCommand(commandName, args, make(map[string]interface{}), context)
	}

	return func() tea.Msg {
		return UnifiedResponse{
			Command:   commandName,
			Status:    "error",
			Error:     &CommandError{
				Code:        "UNKNOWN_COMMAND",
				Message:     fmt.Sprintf("Unknown command: %s", commandName),
				Recoverable: true,
				Suggestions: cr.getSimilarCommands(commandName),
			},
			Timestamp: time.Now(),
		}
	}
}

// CancelCommand cancels a running command
func (cr *CommandRouter) CancelCommand(commandID string) tea.Cmd {
	return cr.unifiedClient.CancelCommand(commandID)
}

// ListAvailableCommands returns all available commands
func (cr *CommandRouter) ListAvailableCommands() []CommandDefinition {
	return cr.registry.ListCommands()
}

// GetCommandDefinition returns definition for a specific command
func (cr *CommandRouter) GetCommandDefinition(commandName string) *CommandDefinition {
	return cr.registry.GetCommand(commandName)
}

// HandleResponse processes responses from the unified command system
func (cr *CommandRouter) HandleResponse(payload []byte) tea.Cmd {
	return cr.unifiedClient.HandleResponse(payload)
}

// GetStats returns command execution statistics
func (cr *CommandRouter) GetStats() map[string]*CommandStats {
	return cr.unifiedClient.GetAllStats()
}

// CleanupExpiredCommands removes expired command tracking
func (cr *CommandRouter) CleanupExpiredCommands() tea.Cmd {
	return cr.unifiedClient.CleanupExpiredCommands()
}

// Helper methods

func (cr *CommandRouter) buildOptions(commandName string, args map[string]interface{}) map[string]interface{} {
	options := make(map[string]interface{})
	
	// Set default format based on command type
	switch commandName {
	case "analyze", "generate", "refactor":
		options["format"] = "ansi"
		options["stream"] = true
	case "health", "llm":
		options["format"] = "table"
	case "complete":
		options["format"] = "json"
	default:
		options["format"] = cr.config.DefaultFormat
	}

	// Copy any options from args (args starting with --) 
	for key, value := range args {
		if strings.HasPrefix(key, "--") {
			optionKey := strings.TrimPrefix(key, "--")
			options[optionKey] = value
		}
	}

	return options
}

func (cr *CommandRouter) isCommandBlocked(commandName string) bool {
	// Check blocked commands list
	for _, blocked := range cr.config.BlockedCommands {
		if blocked == commandName {
			return true
		}
	}

	// Check allowed commands list (if specified, only these are allowed)
	if len(cr.config.AllowedCommands) > 0 {
		for _, allowed := range cr.config.AllowedCommands {
			if allowed == commandName {
				return false
			}
		}
		return true // Not in allowed list
	}

	return false
}

func (cr *CommandRouter) getSimilarCommands(commandName string) []string {
	suggestions := []string{}
	allCommands := cr.registry.ListCommands()

	for _, cmd := range allCommands {
		// Simple similarity check based on prefix or common substrings
		if strings.HasPrefix(cmd.Name, commandName[:min(len(commandName), 3)]) {
			suggestions = append(suggestions, cmd.Name)
		}
		if len(suggestions) >= 3 {
			break
		}
	}

	return suggestions
}

func (cr *CommandRouter) executeProjectAnalysis(args map[string]interface{}, options map[string]interface{}, context CommandContext) tea.Cmd {
	// Hybrid command: enumerate files locally, send to server for analysis
	// This is a simplified implementation - real implementation would be more complex
	return cr.executeServerCommand("analyze", args, options, context)
}

func (cr *CommandRouter) executeCodeSearch(args map[string]interface{}, options map[string]interface{}, context CommandContext) tea.Cmd {
	// Hybrid command: decide based on project size
	// For now, always use server
	return cr.executeServerCommand("search", args, options, context)
}

func (cr *CommandRouter) registerDefaultCommands() {
	// Register local TUI commands
	cr.registry.RegisterCommand(CommandDefinition{
		Name:        "help",
		Description: "Show help information",
		Category:    "UI",
		Type:        LocalCommand,
		LocalOnly:   true,
	})

	cr.registry.RegisterCommand(CommandDefinition{
		Name:        "settings",
		Description: "Open settings dialog",
		Category:    "UI", 
		Type:        LocalCommand,
		LocalOnly:   true,
	})

	cr.registry.RegisterCommand(CommandDefinition{
		Name:        "toggle_theme",
		Description: "Toggle between light and dark theme",
		Category:    "UI",
		Type:        LocalCommand,
		LocalOnly:   true,
	})

	cr.registry.RegisterCommand(CommandDefinition{
		Name:        "clear_output",
		Description: "Clear the output pane",
		Category:    "UI",
		Type:        LocalCommand,
		LocalOnly:   true,
	})

	cr.registry.RegisterCommand(CommandDefinition{
		Name:        "performance_stats",
		Description: "Show performance statistics",
		Category:    "Debug",
		Type:        LocalCommand,
		LocalOnly:   true,
	})

	// Register server commands
	cr.registry.RegisterCommand(CommandDefinition{
		Name:        "analyze",
		Description: "Analyze code for issues and improvements",
		Category:    "Analysis",
		Type:        ServerCommand,
		ServerOnly:  true,
		Args: []ArgDef{
			{Name: "file", Description: "File to analyze", Type: "file", Required: false},
		},
		Options: []OptDef{
			{Name: "type", Description: "Analysis type", Type: "string", Choices: []string{"full", "quick", "security"}},
			{Name: "format", Description: "Output format", Type: "string", Choices: []string{"text", "json", "ansi"}},
		},
	})

	cr.registry.RegisterCommand(CommandDefinition{
		Name:        "generate",
		Description: "Generate code using AI",
		Category:    "Generation",
		Type:        ServerCommand,
		ServerOnly:  true,
		Args: []ArgDef{
			{Name: "prompt", Description: "Generation prompt", Type: "string", Required: true},
		},
		Options: []OptDef{
			{Name: "language", Description: "Target language", Type: "string"},
			{Name: "style", Description: "Code style", Type: "string"},
		},
	})

	cr.registry.RegisterCommand(CommandDefinition{
		Name:        "complete",
		Description: "Get code completions",
		Category:    "Generation",
		Type:        ServerCommand,
		ServerOnly:  true,
	})

	cr.registry.RegisterCommand(CommandDefinition{
		Name:        "refactor",
		Description: "Refactor code",
		Category:    "Generation",
		Type:        ServerCommand,
		ServerOnly:  true,
		Args: []ArgDef{
			{Name: "instruction", Description: "Refactoring instruction", Type: "string", Required: true},
		},
	})

	cr.registry.RegisterCommand(CommandDefinition{
		Name:        "health",
		Description: "Check system health",
		Category:    "System",
		Type:        ServerCommand,
		ServerOnly:  true,
	})

	cr.registry.RegisterCommand(CommandDefinition{
		Name:        "llm",
		Description: "Manage LLM providers",
		Category:    "System",
		Type:        ServerCommand,
		ServerOnly:  true,
		Args: []ArgDef{
			{Name: "action", Description: "Action to perform", Type: "string", 
			 Choices: []string{"list", "status", "set-active"}, Required: true},
		},
	})
}

// min returns the minimum of two integers
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}