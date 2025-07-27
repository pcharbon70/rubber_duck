package ui

import (
	"fmt"
	"strings"

	"github.com/rubber_duck/tui/internal/phoenix"
)

// GenerationResponseHandler handles code/content generation responses
type GenerationResponseHandler struct {
	BaseResponseHandler
}

// GetConversationType returns the conversation type this handler handles
func (h *GenerationResponseHandler) GetConversationType() string {
	return "generation"
}

// FormatResponse formats a generation response with highlighted generated content
func (h *GenerationResponseHandler) FormatResponse(response phoenix.ConversationMessage) string {
	var parts []string
	
	// Add generation header with type if available
	generationType := ""
	if gType, ok := response.Metadata["generation_type"].(string); ok {
		generationType = h.formatGenerationType(gType)
	}
	parts = append(parts, fmt.Sprintf("## 🔧 %sGeneration\n", generationType))
	
	// Add implementation plan if available
	if implementationPlan, ok := response.Metadata["implementation_plan"].([]any); ok && len(implementationPlan) > 0 {
		parts = append(parts, h.addSectionHeader("Implementation Plan"))
		for i, step := range implementationPlan {
			parts = append(parts, fmt.Sprintf("%d. %v", i+1, step))
		}
		parts = append(parts, "")
	}
	
	// Add reasoning steps if available
	if reasoningSteps, ok := response.Metadata["reasoning_steps"].([]any); ok && len(reasoningSteps) > 0 {
		parts = append(parts, h.addSectionHeader("Reasoning"))
		for i, step := range reasoningSteps {
			parts = append(parts, fmt.Sprintf("%d. %v", i+1, step))
		}
		parts = append(parts, "")
	}
	
	// Check for generated code in metadata
	if code, ok := response.Metadata["generated_code"].(string); ok && code != "" {
		parts = append(parts, h.addSectionHeader("Generated Code"))
		// Try to determine language from generation type
		language := h.inferLanguage(generationType)
		parts = append(parts, h.addCodeBlock(code, language))
		parts = append(parts, "\n💡 **Tip**: You can copy the code above using Ctrl+L to copy the last assistant message.\n")
		
		// Add the explanation from response
		if response.Response != "" && response.Response != code {
			parts = append(parts, h.addSectionHeader("Explanation"))
			parts = append(parts, response.Response)
		}
	} else {
		// No structured code in metadata, use response
		parts = append(parts, response.Response)
		if strings.Contains(response.Response, "```") {
			parts = append(parts, "\n💡 **Tip**: You can copy the code above using Ctrl+L to copy the last assistant message.")
		}
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

// formatGenerationType formats the generation type for display
func (h *GenerationResponseHandler) formatGenerationType(gType string) string {
	typeMap := map[string]string{
		"function":           "Function ",
		"module":            "Module ",
		"api":               "API ",
		"test":              "Test ",
		"scaffold":          "Scaffold ",
		"feature":           "Feature ",
		"general_generation": "",
	}
	
	if formatted, ok := typeMap[gType]; ok {
		return formatted
	}
	return ""
}

// inferLanguage tries to infer programming language from generation type
func (h *GenerationResponseHandler) inferLanguage(genType string) string {
	// This is a simple heuristic, could be improved
	if strings.Contains(genType, "Test") {
		return "elixir" // Assuming Elixir for tests in this project
	}
	return "elixir" // Default to Elixir for RubberDuck project
}