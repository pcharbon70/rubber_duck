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
	
	// Add generation header
	parts = append(parts, "## 🔧 Generated Content\n")
	
	// Check for generated code in metadata
	if code, ok := response.Metadata["generated_code"].(string); ok {
		language := "text"
		if lang, ok := response.Metadata["language"].(string); ok {
			language = lang
		}
		
		// Add description if available
		if desc, ok := response.Metadata["description"].(string); ok {
			parts = append(parts, fmt.Sprintf("*%s*\n", desc))
		}
		
		parts = append(parts, h.addCodeBlock(code, language))
		parts = append(parts, "\n💡 **Tip**: You can copy the code above using Ctrl+L to copy the last assistant message.\n")
		
		// Add the explanation from response
		if response.Response != "" && response.Response != code {
			parts = append(parts, h.addSectionHeader("Explanation"))
			parts = append(parts, response.Response)
		}
	} else {
		// No structured code in metadata, check if response contains code blocks
		if strings.Contains(response.Response, "```") {
			parts = append(parts, response.Response)
			parts = append(parts, "\n💡 **Tip**: You can copy the code above using Ctrl+L to copy the last assistant message.")
		} else {
			parts = append(parts, response.Response)
		}
	}
	
	// Add usage notes if available
	if usage, ok := response.Metadata["usage_notes"].(string); ok {
		parts = append(parts, h.addSectionHeader("Usage Notes"))
		parts = append(parts, usage)
	}
	
	// Add dependencies if available
	if deps, ok := response.Metadata["dependencies"].([]any); ok && len(deps) > 0 {
		parts = append(parts, h.addSectionHeader("Dependencies"))
		for _, dep := range deps {
			parts = append(parts, fmt.Sprintf("• %v", dep))
		}
	}
	
	// Add remaining metadata
	filteredMetadata := make(map[string]any)
	for k, v := range response.Metadata {
		if k != "generated_code" && k != "language" && k != "description" && 
		   k != "usage_notes" && k != "dependencies" {
			filteredMetadata[k] = v
		}
	}
	if len(filteredMetadata) > 0 {
		parts = append(parts, h.formatMetadata(filteredMetadata))
	}
	
	return strings.Join(parts, "\n")
}