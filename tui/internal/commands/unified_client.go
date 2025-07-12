package commands

import (
	"encoding/json"
	"fmt"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/rubber_duck/tui/internal/phoenix"
)

// UnifiedClient handles communication with the unified command system
type UnifiedClient struct {
	phoenixClient    phoenix.PhoenixClient
	pendingCommands  map[string]*PendingCommand
	commandTimeout   time.Duration
	mu               sync.RWMutex
	stats            map[string]*CommandStats
	maxConcurrent    int
	retryAttempts    int
}

// PendingCommand tracks a command waiting for response
type PendingCommand struct {
	ID        string
	Command   UnifiedCommand
	StartTime time.Time
	Timeout   time.Time
	Attempts  int
	Channel   chan UnifiedResponse
	Cancel    chan bool
}

// NewUnifiedClient creates a new unified command client
func NewUnifiedClient(phoenixClient phoenix.PhoenixClient, config RouterConfig) *UnifiedClient {
	timeout := config.CommandTimeout
	if timeout == 0 {
		timeout = 30 * time.Second
	}

	maxConcurrent := config.MaxConcurrentCommands
	if maxConcurrent == 0 {
		maxConcurrent = 10
	}

	retryAttempts := config.RetryAttempts
	if retryAttempts == 0 {
		retryAttempts = 3
	}

	return &UnifiedClient{
		phoenixClient:   phoenixClient,
		pendingCommands: make(map[string]*PendingCommand),
		commandTimeout:  timeout,
		stats:           make(map[string]*CommandStats),
		maxConcurrent:   maxConcurrent,
		retryAttempts:   retryAttempts,
	}
}

// ExecuteCommand sends a command to the unified command system
func (uc *UnifiedClient) ExecuteCommand(cmd UnifiedCommand) tea.Cmd {
	if !cmd.IsValid() {
		return func() tea.Msg {
			return UnifiedResponse{
				Command:   cmd.Command,
				Status:    "error",
				Error:     &CommandError{
					Code:    "INVALID_COMMAND",
					Message: "Command validation failed",
				},
				Timestamp: time.Now(),
			}
		}
	}

	// Check concurrent command limit
	uc.mu.RLock()
	if len(uc.pendingCommands) >= uc.maxConcurrent {
		uc.mu.RUnlock()
		return func() tea.Msg {
			return UnifiedResponse{
				Command:   cmd.Command,
				Status:    "error",
				Error:     &CommandError{
					Code:    "TOO_MANY_CONCURRENT",
					Message: fmt.Sprintf("Maximum concurrent commands (%d) exceeded", uc.maxConcurrent),
				},
				Timestamp: time.Now(),
			}
		}
	}
	uc.mu.RUnlock()

	commandID := generateCommandID()
	
	// Create pending command tracking
	pending := &PendingCommand{
		ID:        commandID,
		Command:   cmd,
		StartTime: time.Now(),
		Timeout:   time.Now().Add(uc.commandTimeout),
		Attempts:  1,
		Channel:   make(chan UnifiedResponse, 1),
		Cancel:    make(chan bool, 1),
	}

	uc.mu.Lock()
	uc.pendingCommands[commandID] = pending
	uc.mu.Unlock()

	// Update statistics
	uc.updateStats(cmd.Command, "started")

	// Send command via Phoenix client
	payload := map[string]interface{}{
		"id":         commandID,
		"command":    cmd.Command,
		"subcommand": cmd.Subcommand,
		"args":       cmd.Args,
		"options":    cmd.Options,
		"context":    cmd.Context,
		"timestamp":  time.Now().Unix(),
	}

	// Use Phoenix client to send the unified command
	phoenixCmd := uc.phoenixClient.Push("unified_command", payload)

	// Return a composite command that handles both sending and waiting
	return tea.Batch(
		phoenixCmd,
		uc.waitForResponse(commandID),
	)
}

// waitForResponse waits for a command response with timeout
func (uc *UnifiedClient) waitForResponse(commandID string) tea.Cmd {
	return func() tea.Msg {
		uc.mu.RLock()
		pending, exists := uc.pendingCommands[commandID]
		uc.mu.RUnlock()

		if !exists {
			return UnifiedResponse{
				ID:     commandID,
				Status: "error",
				Error: &CommandError{
					Code:    "COMMAND_NOT_FOUND",
					Message: "Command tracking lost",
				},
				Timestamp: time.Now(),
			}
		}

		// Wait for response or timeout
		select {
		case response := <-pending.Channel:
			uc.cleanupPendingCommand(commandID)
			uc.updateStats(pending.Command.Command, "completed")
			return response

		case <-pending.Cancel:
			uc.cleanupPendingCommand(commandID)
			uc.updateStats(pending.Command.Command, "cancelled")
			return UnifiedResponse{
				ID:     commandID,
				Command: pending.Command.Command,
				Status: "error",
				Error: &CommandError{
					Code:    "CANCELLED",
					Message: "Command was cancelled",
				},
				Timestamp: time.Now(),
			}

		case <-time.After(time.Until(pending.Timeout)):
			uc.cleanupPendingCommand(commandID)
			uc.updateStats(pending.Command.Command, "timeout")
			return UnifiedResponse{
				ID:     commandID,
				Command: pending.Command.Command,
				Status: "error",
				Error: &CommandError{
					Code:    "TIMEOUT",
					Message: fmt.Sprintf("Command timed out after %v", uc.commandTimeout),
				},
				Timestamp: time.Now(),
			}
		}
	}
}

// HandleResponse processes a response from the Phoenix client
func (uc *UnifiedClient) HandleResponse(payload []byte) tea.Cmd {
	var response UnifiedResponse
	if err := json.Unmarshal(payload, &response); err != nil {
		return func() tea.Msg {
			return UnifiedResponse{
				Status: "error",
				Error: &CommandError{
					Code:    "PARSE_ERROR",
					Message: fmt.Sprintf("Failed to parse response: %v", err),
				},
				Timestamp: time.Now(),
			}
		}
	}

	// Find pending command
	uc.mu.RLock()
	pending, exists := uc.pendingCommands[response.ID]
	uc.mu.RUnlock()

	if exists && pending.Channel != nil {
		// Send response to waiting command
		select {
		case pending.Channel <- response:
			// Response sent successfully
		default:
			// Channel full or closed, cleanup
			uc.cleanupPendingCommand(response.ID)
		}
	}

	// Return the response as a message for other handlers
	return func() tea.Msg {
		return response
	}
}

// CancelCommand cancels a pending command
func (uc *UnifiedClient) CancelCommand(commandID string) tea.Cmd {
	uc.mu.RLock()
	pending, exists := uc.pendingCommands[commandID]
	uc.mu.RUnlock()

	if exists {
		// Signal cancellation
		select {
		case pending.Cancel <- true:
		default:
		}

		// Send cancellation to server
		payload := map[string]interface{}{
			"command_id": commandID,
			"reason":     "user_cancellation",
		}
		return uc.phoenixClient.Push("cancel_command", payload)
	}

	return nil
}

// ListPendingCommands returns a list of pending command IDs
func (uc *UnifiedClient) ListPendingCommands() []string {
	uc.mu.RLock()
	defer uc.mu.RUnlock()

	ids := make([]string, 0, len(uc.pendingCommands))
	for id := range uc.pendingCommands {
		ids = append(ids, id)
	}
	return ids
}

// GetCommandStats returns statistics for a command
func (uc *UnifiedClient) GetCommandStats(commandName string) *CommandStats {
	uc.mu.RLock()
	defer uc.mu.RUnlock()

	if stats, exists := uc.stats[commandName]; exists {
		// Return a copy to avoid race conditions
		statsCopy := *stats
		return &statsCopy
	}
	return nil
}

// GetAllStats returns all command statistics
func (uc *UnifiedClient) GetAllStats() map[string]*CommandStats {
	uc.mu.RLock()
	defer uc.mu.RUnlock()

	result := make(map[string]*CommandStats)
	for name, stats := range uc.stats {
		statsCopy := *stats
		result[name] = &statsCopy
	}
	return result
}

// CleanupExpiredCommands removes commands that have expired
func (uc *UnifiedClient) CleanupExpiredCommands() tea.Cmd {
	now := time.Now()
	expiredIDs := []string{}

	uc.mu.RLock()
	for id, pending := range uc.pendingCommands {
		if now.After(pending.Timeout) {
			expiredIDs = append(expiredIDs, id)
		}
	}
	uc.mu.RUnlock()

	// Cleanup expired commands
	for _, id := range expiredIDs {
		uc.cleanupPendingCommand(id)
	}

	if len(expiredIDs) > 0 {
		return func() tea.Msg {
			return CommandCleanupMsg{
				CleanedCount: len(expiredIDs),
				Reason:       "timeout",
			}
		}
	}

	return nil
}

// Helper methods

func (uc *UnifiedClient) cleanupPendingCommand(commandID string) {
	uc.mu.Lock()
	defer uc.mu.Unlock()

	if pending, exists := uc.pendingCommands[commandID]; exists {
		// Close channels
		close(pending.Channel)
		close(pending.Cancel)
		
		// Remove from tracking
		delete(uc.pendingCommands, commandID)
	}
}

func (uc *UnifiedClient) updateStats(commandName, event string) {
	uc.mu.Lock()
	defer uc.mu.Unlock()

	stats, exists := uc.stats[commandName]
	if !exists {
		stats = &CommandStats{
			CommandName: commandName,
		}
		uc.stats[commandName] = stats
	}

	switch event {
	case "started":
		stats.ExecutionCount++
		stats.LastExecuted = time.Now()
	case "completed":
		stats.SuccessCount++
	case "timeout", "cancelled":
		stats.ErrorCount++
	}
}

// generateCommandID generates a unique command ID
func generateCommandID() string {
	return fmt.Sprintf("cmd_%d_%d", time.Now().UnixNano(), time.Now().Nanosecond()%1000)
}

// CommandCleanupMsg represents a cleanup event
type CommandCleanupMsg struct {
	CleanedCount int
	Reason       string
}