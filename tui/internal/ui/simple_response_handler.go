package ui

import (
	"fmt"

	"github.com/rubber_duck/tui/internal/phoenix"
)

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
	// Simple responses are just returned as-is
	formatted := response.Response
	
	// Add processing time if available
	if processingTime, ok := response.Metadata["processing_time"].(float64); ok {
		formatted += fmt.Sprintf("\n\n*Processing time: %.0fms*", processingTime)
	}
	
	return formatted
}