package ui

import (
	"fmt"
	"strings"

	"github.com/rubber_duck/tui/internal/phoenix"
)

// MultiStepResponseHandler handles multi-step process responses
type MultiStepResponseHandler struct {
	BaseResponseHandler
}

// GetConversationType returns the conversation type this handler handles
func (h *MultiStepResponseHandler) GetConversationType() string {
	return "multi_step"
}

// FormatResponse formats a multi-step response with progress indicators
func (h *MultiStepResponseHandler) FormatResponse(response phoenix.ConversationMessage) string {
	var parts []string
	
	// Add multi-step header with step number
	stepNumber := 0
	if stepNum, ok := response.Metadata["step_number"].(float64); ok {
		stepNumber = int(stepNum)
		parts = append(parts, fmt.Sprintf("## 📋 Multi-Step Process (Step %d)\n", stepNumber))
	} else {
		parts = append(parts, "## 📋 Multi-Step Process\n")
	}
	
	// Main response content
	parts = append(parts, response.Response)
	
	// Add context information
	var footer []string
	
	if contextMessages, ok := response.Metadata["context_messages"].(float64); ok && contextMessages > 0 {
		footer = append(footer, fmt.Sprintf("Context messages: %.0f", contextMessages))
	}
	
	if processingTime, ok := response.Metadata["processing_time"].(float64); ok {
		footer = append(footer, fmt.Sprintf("Processing time: %.0fms", processingTime))
	}
	
	if len(footer) > 0 {
		parts = append(parts, "\n---")
		parts = append(parts, "*"+strings.Join(footer, " | ")+"*")
	}
	
	// Add navigation hint
	if stepNumber > 0 {
		parts = append(parts, "\n💡 **Tip**: Continue with the next step or ask follow-up questions.")
	}
	
	return strings.Join(parts, "\n")
}

// createProgressBar creates a visual progress bar
func (h *MultiStepResponseHandler) createProgressBar(current, total int) string {
	if total <= 0 {
		return ""
	}
	
	barWidth := 20
	filled := (current * barWidth) / total
	if filled > barWidth {
		filled = barWidth
	}
	
	bar := strings.Repeat("█", filled) + strings.Repeat("░", barWidth-filled)
	percentage := (current * 100) / total
	
	return fmt.Sprintf("Progress: [%s] %d%% (%d/%d)", bar, percentage, current, total)
}

// getStepStatus returns the status indicator for a step
func (h *MultiStepResponseHandler) getStepStatus(stepNum, currentStep int) string {
	if stepNum < currentStep {
		return "✅" // Completed
	} else if stepNum == currentStep {
		return "🔄" // In progress
	}
	return "⏳" // Pending
}