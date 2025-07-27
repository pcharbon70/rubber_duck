package ui

import "github.com/rubber_duck/tui/internal/phoenix"

// SimpleResponseHandler handles simple conversation responses
type SimpleResponseHandler struct {
	BaseResponseHandler
}

// GetConversationType returns the conversation type this handler handles
func (h *SimpleResponseHandler) GetConversationType() string {
	return "simple"
}

// FormatResponse formats a simple response
func (h *SimpleResponseHandler) FormatResponse(response phoenix.ConversationMessage) string {
	// Simple responses are just returned as-is with optional metadata
	formatted := response.Response
	
	// Add metadata if present
	if len(response.Metadata) > 0 {
		formatted += h.formatMetadata(response.Metadata)
	}
	
	return formatted
}