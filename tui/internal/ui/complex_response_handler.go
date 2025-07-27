package ui

import (
	"fmt"
	"strings"

	"github.com/rubber_duck/tui/internal/phoenix"
)

// ComplexResponseHandler handles complex conversation responses
type ComplexResponseHandler struct {
	BaseResponseHandler
}

// GetConversationType returns the conversation type this handler handles
func (h *ComplexResponseHandler) GetConversationType() string {
	return "complex"
}

// FormatResponse formats a complex response with sections and structure
func (h *ComplexResponseHandler) FormatResponse(response phoenix.ConversationMessage) string {
	var parts []string
	
	// Add a header indicating this is a complex response
	parts = append(parts, "## 🔍 Complex Analysis\n")
	
	// Add reasoning steps if available
	if reasoningSteps, ok := response.Metadata["reasoning_steps"].([]any); ok && len(reasoningSteps) > 0 {
		parts = append(parts, h.addSectionHeader("Reasoning Process"))
		for i, step := range reasoningSteps {
			parts = append(parts, fmt.Sprintf("%d. %v", i+1, step))
		}
		parts = append(parts, "")
	}
	
	// Main response content
	parts = append(parts, h.addSectionHeader("Response"))
	parts = append(parts, response.Response)
	
	// Add total steps and processing time
	var footer []string
	if totalSteps, ok := response.Metadata["total_steps"].(float64); ok {
		footer = append(footer, fmt.Sprintf("Total steps: %.0f", totalSteps))
	}
	if processingTime, ok := response.Metadata["processing_time"].(float64); ok {
		footer = append(footer, fmt.Sprintf("Processing time: %.0fms", processingTime))
	}
	
	if len(footer) > 0 {
		parts = append(parts, "\n---")
		parts = append(parts, "*"+strings.Join(footer, " | ")+"*")
	}
	
	return strings.Join(parts, "\n")
}

// identifySections attempts to identify logical sections in unstructured text
func (h *ComplexResponseHandler) identifySections(content string) []string {
	// For now, just return the content as-is
	// Future enhancement: use NLP or patterns to identify sections
	return []string{content}
}