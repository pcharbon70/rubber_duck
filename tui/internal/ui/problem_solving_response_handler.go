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
	
	// Add problem statement if available
	if problem, ok := response.Metadata["problem_statement"].(string); ok {
		parts = append(parts, h.addSectionHeader("Problem"))
		parts = append(parts, fmt.Sprintf("> %s\n", problem))
	}
	
	// Add approach if available
	if approach, ok := response.Metadata["approach"].(string); ok {
		parts = append(parts, h.addSectionHeader("Approach"))
		parts = append(parts, approach, "")
	}
	
	// Check for structured steps in metadata
	if steps, ok := response.Metadata["solution_steps"].([]any); ok && len(steps) > 0 {
		parts = append(parts, h.addSectionHeader("Solution Steps"))
		for i, step := range steps {
			parts = append(parts, fmt.Sprintf("**Step %d**: %v", i+1, step))
		}
		parts = append(parts, "")
	}
	
	// Main response content (solution details)
	if response.Response != "" {
		// If we already have structured steps, this is additional detail
		if _, hasSteps := response.Metadata["solution_steps"]; hasSteps {
			parts = append(parts, h.addSectionHeader("Detailed Solution"))
		}
		parts = append(parts, response.Response)
	}
	
	// Add outcome/result if available
	if outcome, ok := response.Metadata["outcome"].(string); ok {
		parts = append(parts, h.addSectionHeader("Outcome"))
		parts = append(parts, fmt.Sprintf("✅ %s", outcome))
	}
	
	// Add alternatives if available
	if alternatives, ok := response.Metadata["alternatives"].([]any); ok && len(alternatives) > 0 {
		parts = append(parts, h.addSectionHeader("Alternative Solutions"))
		for _, alt := range alternatives {
			parts = append(parts, fmt.Sprintf("• %v", alt))
		}
	}
	
	// Add remaining metadata
	filteredMetadata := make(map[string]any)
	for k, v := range response.Metadata {
		if k != "problem_statement" && k != "approach" && k != "solution_steps" && 
		   k != "outcome" && k != "alternatives" {
			filteredMetadata[k] = v
		}
	}
	if len(filteredMetadata) > 0 {
		parts = append(parts, h.formatMetadata(filteredMetadata))
	}
	
	return strings.Join(parts, "\n")
}