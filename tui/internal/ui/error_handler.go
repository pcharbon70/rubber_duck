package ui

import (
	"fmt"
	"strings"
	"sync"
	"time"
)

// ErrorHandler manages error display and prevents spam
type ErrorHandler struct {
	mu              sync.Mutex
	lastError       string
	lastErrorTime   time.Time
	errorCount      int
	suppressUntil   time.Time
	backoffDuration time.Duration
}

// NewErrorHandler creates a new error handler
func NewErrorHandler() *ErrorHandler {
	return &ErrorHandler{
		backoffDuration: time.Second,
	}
}

// HandleError processes an error and returns whether it should be displayed
func (e *ErrorHandler) HandleError(err error, component string) (display bool, message string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	
	// Handle nil errors
	if err == nil {
		return false, ""
	}
	
	now := time.Now()
	errorKey := fmt.Sprintf("%s:%v", component, err)
	
	// Check if we're in suppression period
	if now.Before(e.suppressUntil) {
		return false, ""
	}
	
	// Check if it's the same error as before
	if errorKey == e.lastError && now.Sub(e.lastErrorTime) < 5*time.Second {
		e.errorCount++
		
		// After 3 repeated errors, start suppressing
		if e.errorCount >= 3 {
			e.suppressUntil = now.Add(e.backoffDuration)
			e.backoffDuration = e.backoffDuration * 2
			if e.backoffDuration > 30*time.Second {
				e.backoffDuration = 30*time.Second
			}
			
			// Show suppression message only once, then stay silent
			message = fmt.Sprintf("%s: Connection failed. Further errors suppressed to prevent spam.", component)
			return true, message
		}
		
		// Show second occurrence but suppress subsequent ones until threshold
		if e.errorCount == 2 {
			message = formatErrorMessage(err, component)
			return true, message
		}
		
		// Don't display other repeated errors
		return false, ""
	}
	
	// New error or different error
	e.lastError = errorKey
	e.lastErrorTime = now
	e.errorCount = 1
	e.backoffDuration = time.Second
	
	// Format error message
	message = formatErrorMessage(err, component)
	return true, message
}

// Reset clears the error state
func (e *ErrorHandler) Reset() {
	e.mu.Lock()
	defer e.mu.Unlock()
	
	e.lastError = ""
	e.lastErrorTime = time.Time{}
	e.errorCount = 0
	e.suppressUntil = time.Time{}
	e.backoffDuration = time.Second
}

// formatErrorMessage creates a user-friendly error message
func formatErrorMessage(err error, component string) string {
	errStr := err.Error()
	
	// Common connection errors
	if strings.Contains(errStr, "connection refused") {
		return fmt.Sprintf("%s: Cannot connect to server. Is the Phoenix server running on the correct port?", component)
	}
	
	if strings.Contains(errStr, "timeout") {
		return fmt.Sprintf("%s: Connection timeout. The server might be slow or unreachable.", component)
	}
	
	if strings.Contains(errStr, "websocket") && strings.Contains(errStr, "bad handshake") {
		// Include the actual error for debugging
		return fmt.Sprintf("%s: WebSocket handshake failed - %v", component, err)
	}
	
	if strings.Contains(errStr, "authentication") || strings.Contains(errStr, "unauthorized") {
		return fmt.Sprintf("%s: Authentication failed. Please check your credentials.", component)
	}
	
	// Default format
	return fmt.Sprintf("%s: %v", component, err)
}

// ConnectionError represents a connection-specific error
type ConnectionError struct {
	Err           error
	Component     string
	Retryable     bool
	RetryAfter    time.Duration
	SuggestedFix  string
}

func (c ConnectionError) Error() string {
	return c.Err.Error()
}

// GetConnectionAdvice provides helpful advice for connection errors
func GetConnectionAdvice(err error) string {
	errStr := err.Error()
	
	if strings.Contains(errStr, "connection refused") {
		return "Tip: Make sure the Phoenix server is running with 'mix phx.server' and listening on port 5555"
	}
	
	if strings.Contains(errStr, "no such host") {
		return "Tip: Check that the server hostname is correct and reachable"
	}
	
	if strings.Contains(errStr, "certificate") {
		return "Tip: For development, you may need to use ws:// instead of wss://"
	}
	
	return ""
}