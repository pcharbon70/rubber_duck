package ui

import (
	"fmt"
	"strings"

	"github.com/rubber_duck/tui/internal/phoenix"
)

// AnalysisResponseHandler handles analysis conversation responses
type AnalysisResponseHandler struct {
	BaseResponseHandler
}

// GetConversationType returns the conversation type this handler handles
func (h *AnalysisResponseHandler) GetConversationType() string {
	return "analysis"
}

// FormatResponse formats an analysis response with findings and conclusions
func (h *AnalysisResponseHandler) FormatResponse(response phoenix.ConversationMessage) string {
	var parts []string
	
	// Add analysis header
	parts = append(parts, "## 📊 Analysis Results\n")
	
	// Check for structured analysis in metadata
	if findings, ok := response.Metadata["findings"].([]any); ok && len(findings) > 0 {
		parts = append(parts, h.addSectionHeader("Findings"))
		for i, finding := range findings {
			parts = append(parts, fmt.Sprintf("%d. %v", i+1, finding))
		}
		parts = append(parts, "")
	}
	
	// Main response content
	parts = append(parts, response.Response)
	
	// Add conclusions if available
	if conclusions, ok := response.Metadata["conclusions"].([]any); ok && len(conclusions) > 0 {
		parts = append(parts, h.addSectionHeader("Conclusions"))
		for _, conclusion := range conclusions {
			parts = append(parts, fmt.Sprintf("• %s", h.addEmphasis(fmt.Sprintf("%v", conclusion))))
		}
	}
	
	// Add recommendations if available
	if recommendations, ok := response.Metadata["recommendations"].([]any); ok && len(recommendations) > 0 {
		parts = append(parts, h.addSectionHeader("Recommendations"))
		for _, rec := range recommendations {
			parts = append(parts, fmt.Sprintf("→ %v", rec))
		}
	}
	
	// Add data summary if available
	if dataSummary, ok := response.Metadata["data_summary"].(string); ok {
		parts = append(parts, h.addSectionHeader("Data Summary"))
		parts = append(parts, h.addCodeBlock(dataSummary, ""))
	}
	
	// Add remaining metadata
	filteredMetadata := make(map[string]any)
	for k, v := range response.Metadata {
		if k != "findings" && k != "conclusions" && k != "recommendations" && k != "data_summary" {
			filteredMetadata[k] = v
		}
	}
	if len(filteredMetadata) > 0 {
		parts = append(parts, h.formatMetadata(filteredMetadata))
	}
	
	return strings.Join(parts, "\n")
}