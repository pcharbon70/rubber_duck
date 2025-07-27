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
	
	// Process the response, looking for natural sections
	content := response.Response
	
	// If the response already has markdown headers, preserve them
	if strings.Contains(content, "##") || strings.Contains(content, "###") {
		parts = append(parts, content)
	} else {
		// Try to identify sections based on content patterns
		sections := h.identifySections(content)
		for i, section := range sections {
			if i > 0 {
				parts = append(parts, "\n---\n")
			}
			parts = append(parts, section)
		}
	}
	
	// Add key insights if available in metadata
	if insights, ok := response.Metadata["insights"].([]any); ok && len(insights) > 0 {
		parts = append(parts, h.addSectionHeader("Key Insights"))
		for _, insight := range insights {
			parts = append(parts, fmt.Sprintf("• %v", insight))
		}
	}
	
	// Add metadata
	if len(response.Metadata) > 0 {
		parts = append(parts, h.formatMetadata(response.Metadata))
	}
	
	return strings.Join(parts, "\n")
}

// identifySections attempts to identify logical sections in unstructured text
func (h *ComplexResponseHandler) identifySections(content string) []string {
	// For now, just return the content as-is
	// Future enhancement: use NLP or patterns to identify sections
	return []string{content}
}