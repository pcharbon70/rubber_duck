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
	
	// Add analysis header with type if available
	analysisType := ""
	if aType, ok := response.Metadata["analysis_type"].(string); ok {
		analysisType = h.formatAnalysisType(aType)
	}
	parts = append(parts, fmt.Sprintf("## 📊 %sAnalysis Results\n", analysisType))
	
	// Add analysis points if available
	if analysisPoints, ok := response.Metadata["analysis_points"].([]any); ok && len(analysisPoints) > 0 {
		parts = append(parts, h.addSectionHeader("Key Analysis Points"))
		for _, point := range analysisPoints {
			parts = append(parts, fmt.Sprintf("• %v", point))
		}
		parts = append(parts, "")
	}
	
	// Main response content
	parts = append(parts, response.Response)
	
	// Add recommendations if available
	if recommendations, ok := response.Metadata["recommendations"].([]any); ok && len(recommendations) > 0 {
		parts = append(parts, h.addSectionHeader("Recommendations"))
		for i, rec := range recommendations {
			parts = append(parts, fmt.Sprintf("%d. %s", i+1, h.addEmphasis(fmt.Sprintf("%v", rec))))
		}
	}
	
	// Add processing time
	if processingTime, ok := response.Metadata["processing_time"].(float64); ok {
		parts = append(parts, fmt.Sprintf("\n---\n*Processing time: %.0fms*", processingTime))
	}
	
	return strings.Join(parts, "\n")
}

// formatAnalysisType formats the analysis type for display
func (h *AnalysisResponseHandler) formatAnalysisType(aType string) string {
	typeMap := map[string]string{
		"security":          "Security ",
		"performance":       "Performance ",
		"architecture":      "Architecture ",
		"code_review":       "Code Review ",
		"complexity":        "Complexity ",
		"general_analysis":  "",
	}
	
	if formatted, ok := typeMap[aType]; ok {
		return formatted
	}
	return ""
}