package commands

import (
	"encoding/json"
	"fmt"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// ResponseHandler processes unified command responses
type ResponseHandler struct {
	pendingCommands map[string]*PendingCommand
	stats           map[string]*ResponseStats
}

// PendingCommand tracks a command waiting for response
type PendingCommand struct {
	Command     UnifiedCommand
	StartTime   time.Time
	Timeout     time.Duration
	Callback    func(UnifiedResponse) tea.Cmd
	Retries     int
	MaxRetries  int
}

// ResponseStats tracks response statistics
type ResponseStats struct {
	CommandName    string
	TotalRequests  int
	SuccessCount   int
	ErrorCount     int
	TimeoutCount   int
	AverageLatency time.Duration
	TotalLatency   time.Duration
	LastResponse   time.Time
}

// NewResponseHandler creates a new response handler
func NewResponseHandler() *ResponseHandler {
	return &ResponseHandler{
		pendingCommands: make(map[string]*PendingCommand),
		stats:          make(map[string]*ResponseStats),
	}
}

// TrackCommand tracks a command for response handling
func (rh *ResponseHandler) TrackCommand(cmd UnifiedCommand, timeout time.Duration, callback func(UnifiedResponse) tea.Cmd) string {
	requestID := generateRequestID()
	
	pending := &PendingCommand{
		Command:    cmd,
		StartTime:  time.Now(),
		Timeout:    timeout,
		Callback:   callback,
		Retries:    0,
		MaxRetries: 3,
	}
	
	rh.pendingCommands[requestID] = pending
	rh.updateStats(cmd.Command, "request", 0)
	
	return requestID
}

// HandleResponse processes a unified command response
func (rh *ResponseHandler) HandleResponse(response UnifiedResponse) tea.Cmd {
	// Find the pending command
	pending, exists := rh.pendingCommands[response.RequestID]
	if !exists {
		// No pending command found - might be an unsolicited response
		return rh.handleUnsolicitedResponse(response)
	}
	
	// Calculate latency
	latency := time.Since(pending.StartTime)
	
	// Update statistics
	if response.IsSuccess() {
		rh.updateStats(pending.Command.Command, "success", latency)
	} else if response.IsError() {
		rh.updateStats(pending.Command.Command, "error", latency)
	}
	
	// Remove from pending commands
	delete(rh.pendingCommands, response.RequestID)
	
	// Call the callback if provided
	if pending.Callback != nil {
		return pending.Callback(response)
	}
	
	// Default response handling
	return rh.defaultResponseHandler(response)
}

// HandleTimeout processes command timeouts
func (rh *ResponseHandler) HandleTimeout(requestID string) tea.Cmd {
	pending, exists := rh.pendingCommands[requestID]
	if !exists {
		return nil
	}
	
	// Update timeout statistics
	rh.updateStats(pending.Command.Command, "timeout", time.Since(pending.StartTime))
	
	// Check if we should retry
	if pending.Retries < pending.MaxRetries {
		pending.Retries++
		pending.StartTime = time.Now()
		// Keep the command in pending state for retry
		return rh.retryCommand(pending)
	}
	
	// Remove from pending commands
	delete(rh.pendingCommands, requestID)
	
	// Create timeout response
	timeoutResponse := UnifiedResponse{
		RequestID: requestID,
		Command:   pending.Command.Command,
		Status:    "timeout",
		Error: &CommandError{
			Code:    "COMMAND_TIMEOUT",
			Message: fmt.Sprintf("Command %s timed out after %v", pending.Command.Command, pending.Timeout),
		},
		Duration: time.Since(pending.StartTime),
	}
	
	// Call the callback if provided
	if pending.Callback != nil {
		return pending.Callback(timeoutResponse)
	}
	
	return rh.defaultResponseHandler(timeoutResponse)
}

// CheckTimeouts checks for and handles expired commands
func (rh *ResponseHandler) CheckTimeouts() []tea.Cmd {
	var timeoutCmds []tea.Cmd
	var expiredIDs []string
	
	now := time.Now()
	for requestID, pending := range rh.pendingCommands {
		if now.Sub(pending.StartTime) > pending.Timeout {
			expiredIDs = append(expiredIDs, requestID)
		}
	}
	
	for _, requestID := range expiredIDs {
		if cmd := rh.HandleTimeout(requestID); cmd != nil {
			timeoutCmds = append(timeoutCmds, cmd)
		}
	}
	
	return timeoutCmds
}

// GetPendingCommands returns the current pending commands
func (rh *ResponseHandler) GetPendingCommands() map[string]*PendingCommand {
	// Return a copy to avoid race conditions
	pending := make(map[string]*PendingCommand)
	for id, cmd := range rh.pendingCommands {
		cmdCopy := *cmd
		pending[id] = &cmdCopy
	}
	return pending
}

// GetResponseStats returns response statistics
func (rh *ResponseHandler) GetResponseStats() map[string]*ResponseStats {
	// Return a copy to avoid race conditions
	stats := make(map[string]*ResponseStats)
	for name, stat := range rh.stats {
		statCopy := *stat
		stats[name] = &statCopy
	}
	return stats
}

// ClearStats clears all response statistics
func (rh *ResponseHandler) ClearStats() {
	rh.stats = make(map[string]*ResponseStats)
}

// handleUnsolicitedResponse handles responses that don't match pending commands
func (rh *ResponseHandler) handleUnsolicitedResponse(response UnifiedResponse) tea.Cmd {
	// This might be a server-initiated response (like a notification)
	return func() tea.Msg {
		return UnsolicitedResponseMsg{
			Response: response,
		}
	}
}

// defaultResponseHandler provides default handling for responses
func (rh *ResponseHandler) defaultResponseHandler(response UnifiedResponse) tea.Cmd {
	return func() tea.Msg {
		if response.IsSuccess() {
			return CommandCompletedMsg{
				Command:  response.Command,
				Content:  response.Content,
				Duration: response.Duration,
			}
		} else if response.IsError() {
			return CommandErrorMsg{
				Command: response.Command,
				Error:   response.Error,
			}
		} else if response.IsStreaming() {
			return CommandStreamingMsg{
				Command:  response.Command,
				StreamID: response.Stream.ID,
				Content:  response.Content,
			}
		}
		
		return CommandStatusMsg{
			Command: response.Command,
			Status:  response.Status,
			Content: response.Content,
		}
	}
}

// retryCommand creates a command to retry a failed command
func (rh *ResponseHandler) retryCommand(pending *PendingCommand) tea.Cmd {
	return func() tea.Msg {
		return RetryCommandMsg{
			Command:     pending.Command,
			AttemptNum:  pending.Retries,
			MaxRetries:  pending.MaxRetries,
			OriginalCmd: pending,
		}
	}
}

// updateStats updates response statistics
func (rh *ResponseHandler) updateStats(commandName, eventType string, latency time.Duration) {
	stats, exists := rh.stats[commandName]
	if !exists {
		stats = &ResponseStats{
			CommandName: commandName,
		}
		rh.stats[commandName] = stats
	}
	
	stats.LastResponse = time.Now()
	
	switch eventType {
	case "request":
		stats.TotalRequests++
	case "success":
		stats.SuccessCount++
		stats.TotalLatency += latency
		stats.AverageLatency = stats.TotalLatency / time.Duration(stats.SuccessCount)
	case "error":
		stats.ErrorCount++
	case "timeout":
		stats.TimeoutCount++
	}
}

// generateRequestID generates a unique request ID
func generateRequestID() string {
	return fmt.Sprintf("req_%d_%d", time.Now().UnixNano(), time.Now().Nanosecond()%1000)
}

// Response message types for the TUI
type UnsolicitedResponseMsg struct {
	Response UnifiedResponse
}

type CommandCompletedMsg struct {
	Command  string
	Content  interface{}
	Duration time.Duration
}

type CommandErrorMsg struct {
	Command string
	Error   *CommandError
}

type CommandStreamingMsg struct {
	Command  string
	StreamID string
	Content  interface{}
}

type CommandStatusMsg struct {
	Command string
	Status  string
	Content interface{}
}

type RetryCommandMsg struct {
	Command     UnifiedCommand
	AttemptNum  int
	MaxRetries  int
	OriginalCmd *PendingCommand
}

// ParseResponseFromJSON parses a unified response from JSON
func ParseResponseFromJSON(data []byte) (UnifiedResponse, error) {
	var response UnifiedResponse
	err := json.Unmarshal(data, &response)
	return response, err
}

// CreateErrorResponse creates an error response
func CreateErrorResponse(requestID, command, errorCode, errorMessage string) UnifiedResponse {
	return UnifiedResponse{
		RequestID: requestID,
		Command:   command,
		Status:    "error",
		Error: &CommandError{
			Code:    errorCode,
			Message: errorMessage,
		},
		Timestamp: time.Now(),
	}
}

// CreateSuccessResponse creates a success response
func CreateSuccessResponse(requestID, command string, content interface{}) UnifiedResponse {
	return UnifiedResponse{
		RequestID: requestID,
		Command:   command,
		Status:    "success",
		Content:   content,
		Timestamp: time.Now(),
	}
}