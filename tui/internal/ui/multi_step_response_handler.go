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
	
	// Add multi-step header
	parts = append(parts, "## 📋 Multi-Step Process\n")
	
	// Add overview if available
	if overview, ok := response.Metadata["overview"].(string); ok {
		parts = append(parts, fmt.Sprintf("**Overview**: %s\n", overview))
	}
	
	// Check for structured steps in metadata
	if steps, ok := response.Metadata["steps"].([]any); ok && len(steps) > 0 {
		totalSteps := len(steps)
		currentStep := 1
		
		// Get current step if available
		if current, ok := response.Metadata["current_step"].(float64); ok {
			currentStep = int(current)
		}
		
		// Add progress bar
		progress := h.createProgressBar(currentStep, totalSteps)
		parts = append(parts, progress, "")
		
		// Add steps with status indicators
		parts = append(parts, h.addSectionHeader("Steps"))
		for i, step := range steps {
			stepNum := i + 1
			status := h.getStepStatus(stepNum, currentStep)
			
			// Format step based on its structure
			var stepText string
			switch s := step.(type) {
			case string:
				stepText = s
			case map[string]any:
				if name, ok := s["name"].(string); ok {
					stepText = name
				} else if desc, ok := s["description"].(string); ok {
					stepText = desc
				} else {
					stepText = fmt.Sprintf("%v", s)
				}
			default:
				stepText = fmt.Sprintf("%v", step)
			}
			
			parts = append(parts, fmt.Sprintf("%s **Step %d**: %s", status, stepNum, stepText))
		}
		parts = append(parts, "")
	}
	
	// Main response content
	if response.Response != "" {
		// If we have steps, this is current step detail
		if _, hasSteps := response.Metadata["steps"]; hasSteps {
			if currentStep, ok := response.Metadata["current_step"].(float64); ok {
				parts = append(parts, fmt.Sprintf("### Current Step %d Details", int(currentStep)))
			} else {
				parts = append(parts, h.addSectionHeader("Details"))
			}
		}
		parts = append(parts, response.Response)
	}
	
	// Add next steps if available
	if nextSteps, ok := response.Metadata["next_steps"].([]any); ok && len(nextSteps) > 0 {
		parts = append(parts, h.addSectionHeader("Next Steps"))
		for _, next := range nextSteps {
			parts = append(parts, fmt.Sprintf("→ %v", next))
		}
	}
	
	// Add completion status if available
	if completed, ok := response.Metadata["completed"].(bool); ok && completed {
		parts = append(parts, "\n✅ **Process Complete!**")
		if summary, ok := response.Metadata["summary"].(string); ok {
			parts = append(parts, fmt.Sprintf("\n%s", summary))
		}
	}
	
	// Add remaining metadata
	filteredMetadata := make(map[string]any)
	for k, v := range response.Metadata {
		if k != "overview" && k != "steps" && k != "current_step" && 
		   k != "next_steps" && k != "completed" && k != "summary" {
			filteredMetadata[k] = v
		}
	}
	if len(filteredMetadata) > 0 {
		parts = append(parts, h.formatMetadata(filteredMetadata))
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