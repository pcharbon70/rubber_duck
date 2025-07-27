package ui

import (
	"fmt"
	"strings"

	"github.com/rubber_duck/tui/internal/phoenix"
)

// ProblemSolvingResponseHandler handles problem-solving conversation responses
type ProblemSolvingResponseHandler struct {
	BaseResponseHandler
}

// GetConversationType returns the conversation type this handler handles
func (h *ProblemSolvingResponseHandler) GetConversationType() string {
	return "problem_solving"
}

// FormatResponse formats a problem-solving response with clear problem/solution structure
func (h *ProblemSolvingResponseHandler) FormatResponse(response phoenix.ConversationMessage) string {
	var parts []string
	
	// Add problem-solving header
	parts = append(parts, "## 🎯 Problem Solving\n")
	
	// Add root cause if available
	if rootCause, ok := response.Metadata["root_cause"].(string); ok && rootCause != "" {
		parts = append(parts, h.addSectionHeader("Root Cause"))
		parts = append(parts, fmt.Sprintf("> %s\n", h.addEmphasis(rootCause)))
	}
	
	// Add reasoning steps if available
	if reasoningSteps, ok := response.Metadata["reasoning_steps"].([]any); ok && len(reasoningSteps) > 0 {
		parts = append(parts, h.addSectionHeader("Reasoning Process"))
		for i, step := range reasoningSteps {
			parts = append(parts, fmt.Sprintf("%d. %v", i+1, step))
		}
		parts = append(parts, "")
	}
	
	// Check for solution steps in metadata
	if solutionSteps, ok := response.Metadata["solution_steps"].([]any); ok && len(solutionSteps) > 0 {
		parts = append(parts, h.addSectionHeader("Solution Steps"))
		for i, step := range solutionSteps {
			parts = append(parts, fmt.Sprintf("**Step %d**: %v", i+1, step))
		}
		parts = append(parts, "")
	}
	
	// Main response content (solution details)
	if response.Response != "" {
		// If we already have structured steps, this is additional detail
		if _, hasSteps := response.Metadata["solution_steps"]; hasSteps {
			parts = append(parts, h.addSectionHeader("Detailed Solution"))
		} else {
			parts = append(parts, h.addSectionHeader("Solution"))
		}
		parts = append(parts, response.Response)
	}
	
	// Add footer with steps and processing time
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