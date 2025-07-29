package ui

import (
	"fmt"
	"strings"
	
	"github.com/rubber_duck/tui/internal/phoenix"
)

// PlanningResponseHandler handles planning conversation responses
type PlanningResponseHandler struct {
	BaseResponseHandler
}

// GetConversationType returns the conversation type this handler handles
func (h *PlanningResponseHandler) GetConversationType() string {
	return "planning"
}

// FormatResponse formats a planning response with plan details
func (h *PlanningResponseHandler) FormatResponse(response phoenix.ConversationMessage) string {
	var parts []string
	
	// Add planning header
	parts = append(parts, "## 📋 Planning Response\n")
	
	// Show the main response first
	if response.Response != "" {
		parts = append(parts, response.Response)
		parts = append(parts, "") // Add spacing
	}
	
	// The plan could be at different levels depending on how Phoenix sends it
	// First check if plan is directly in metadata (which would mean it's at root level of the response)
	var plan map[string]any
	var validationSummary string
	var readyForExecution bool
	var errors []any
	var processingTime float64
	
	// Check if we have the raw response structure
	if rawResponse, ok := response.Metadata["_raw_response"].(map[string]any); ok {
		// Plan is in the raw response
		if p, ok := rawResponse["plan"].(map[string]any); ok {
			plan = p
		}
		if vs, ok := rawResponse["validation_summary"].(string); ok {
			validationSummary = vs
		}
		if ready, ok := rawResponse["ready_for_execution"].(bool); ok {
			readyForExecution = ready
		}
		if err, ok := rawResponse["errors"].([]any); ok {
			errors = err
		}
		if pt, ok := rawResponse["processing_time"].(float64); ok {
			processingTime = pt
		}
	} else {
		// Check if plan is directly in metadata (flattened structure)
		if p, ok := response.Metadata["plan"].(map[string]any); ok {
			plan = p
		}
		if vs, ok := response.Metadata["validation_summary"].(string); ok {
			validationSummary = vs
		}
		if ready, ok := response.Metadata["ready_for_execution"].(bool); ok {
			readyForExecution = ready
		}
		if err, ok := response.Metadata["errors"].([]any); ok {
			errors = err
		}
		if pt, ok := response.Metadata["processing_time"].(float64); ok {
			processingTime = pt
		}
	}
	
	// Display the plan if we found it
	if plan != nil {
		parts = append(parts, h.formatPlan(plan))
	}
	
	// Show validation summary if available
	if validationSummary != "" {
		parts = append(parts, fmt.Sprintf("\n**Validation Status:** %s", h.formatValidationStatus(validationSummary)))
	}
	
	// Show ready for execution status
	if validationSummary != "" || plan != nil {
		status := "❌ Not ready"
		if readyForExecution {
			status = "✅ Ready for execution"
		}
		parts = append(parts, fmt.Sprintf("**Execution Status:** %s", status))
	}
	
	// Show errors if any
	if len(errors) > 0 {
		parts = append(parts, "\n**⚠️ Errors:**")
		for _, err := range errors {
			parts = append(parts, fmt.Sprintf("- %v", err))
		}
	}
	
	// Add processing time if available
	if processingTime > 0 {
		parts = append(parts, fmt.Sprintf("\n_Processing time: %.2fs_", processingTime/1000))
	}
	
	return strings.Join(parts, "\n")
}

// formatPlan formats the plan structure
func (h *PlanningResponseHandler) formatPlan(plan map[string]any) string {
	var parts []string
	
	parts = append(parts, "### 📑 Plan Details\n")
	
	// Plan header info
	if name, ok := plan["name"].(string); ok {
		parts = append(parts, fmt.Sprintf("**Name:** %s", name))
	}
	
	if planType, ok := plan["type"].(string); ok {
		parts = append(parts, fmt.Sprintf("**Type:** %s", h.formatPlanType(planType)))
	}
	
	if status, ok := plan["status"].(string); ok {
		parts = append(parts, fmt.Sprintf("**Status:** %s", h.formatPlanStatus(status)))
	}
	
	if desc, ok := plan["description"].(string); ok {
		parts = append(parts, fmt.Sprintf("\n**Description:**\n%s", desc))
	}
	
	// Task summary
	if taskCount, ok := plan["task_count"].(float64); ok {
		parts = append(parts, fmt.Sprintf("\n**Total Tasks:** %d", int(taskCount)))
	}
	
	// Display phases with their tasks (new hierarchical structure)
	if phases, ok := plan["phases"].([]any); ok && len(phases) > 0 {
		parts = append(parts, h.formatPhases(phases))
	}
	
	// Display orphan tasks (backward compatibility)
	if orphanTasks, ok := plan["orphan_tasks"].([]any); ok && len(orphanTasks) > 0 {
		parts = append(parts, "\n### 📝 Standalone Tasks\n")
		for _, task := range orphanTasks {
			if taskMap, ok := task.(map[string]any); ok {
				parts = append(parts, h.formatTask(taskMap, 0))
			}
		}
	}
	
	// Show if plan was auto-improved or auto-fixed
	if metadata, ok := plan["metadata"].(map[string]any); ok {
		var flags []string
		if autoImproved, ok := metadata["auto_improved"].(bool); ok && autoImproved {
			flags = append(flags, "🔧 Auto-improved")
		}
		if autoFixed, ok := metadata["auto_fixed"].(bool); ok && autoFixed {
			flags = append(flags, "🔨 Auto-fixed")
		}
		if len(flags) > 0 {
			parts = append(parts, fmt.Sprintf("\n%s", strings.Join(flags, " | ")))
		}
	}
	
	return strings.Join(parts, "\n")
}

// formatPhases formats all phases with their tasks
func (h *PlanningResponseHandler) formatPhases(phases []any) string {
	var parts []string
	
	parts = append(parts, "\n### 📊 Execution Phases\n")
	
	for _, phase := range phases {
		if phaseMap, ok := phase.(map[string]any); ok {
			parts = append(parts, h.formatPhase(phaseMap))
		}
	}
	
	return strings.Join(parts, "\n")
}

// formatPhase formats a single phase with its tasks
func (h *PlanningResponseHandler) formatPhase(phase map[string]any) string {
	var parts []string
	
	// Phase header
	number := ""
	if n, ok := phase["number"].(string); ok {
		number = n
	}
	
	name := "Unnamed phase"
	if n, ok := phase["name"].(string); ok {
		name = n
	}
	
	parts = append(parts, fmt.Sprintf("\n#### Phase %s: %s\n", number, name))
	
	// Phase description
	if desc, ok := phase["description"].(string); ok && desc != "" {
		parts = append(parts, fmt.Sprintf("_%s_\n", desc))
	}
	
	// Tasks in this phase
	if tasks, ok := phase["tasks"].([]any); ok && len(tasks) > 0 {
		for _, task := range tasks {
			if taskMap, ok := task.(map[string]any); ok {
				parts = append(parts, h.formatTask(taskMap, 0))
			}
		}
	}
	
	return strings.Join(parts, "\n")
}

// formatTask formats a single task with optional subtasks
func (h *PlanningResponseHandler) formatTask(task map[string]any, indent int) string {
	var parts []string
	indentStr := strings.Repeat("  ", indent)
	
	// Task number, name and status
	number := ""
	if n, ok := task["number"].(string); ok {
		number = n
	}
	
	name := "Unnamed task"
	if n, ok := task["name"].(string); ok {
		name = n
	}
	
	status := ""
	if s, ok := task["status"].(string); ok {
		status = h.formatTaskStatus(s)
	}
	
	// Format main task line
	if number != "" {
		parts = append(parts, fmt.Sprintf("%s**%s. %s** %s", indentStr, number, name, status))
	} else {
		parts = append(parts, fmt.Sprintf("%s• **%s** %s", indentStr, name, status))
	}
	
	// Task description
	if desc, ok := task["description"].(string); ok && desc != "" {
		parts = append(parts, fmt.Sprintf("%s  %s", indentStr, desc))
	}
	
	// Complexity
	if complexity, ok := task["complexity"].(string); ok {
		parts = append(parts, fmt.Sprintf("%s  _Complexity: %s_", indentStr, h.formatComplexity(complexity)))
	}
	
	// Dependencies
	if deps, ok := task["dependencies"].([]any); ok && len(deps) > 0 {
		depStrs := []string{}
		for _, dep := range deps {
			if depStr, ok := dep.(string); ok {
				depStrs = append(depStrs, depStr)
			}
		}
		if len(depStrs) > 0 {
			parts = append(parts, fmt.Sprintf("%s  _Dependencies: %s_", indentStr, strings.Join(depStrs, ", ")))
		}
	}
	
	// Subtasks
	if subtasks, ok := task["subtasks"].([]any); ok && len(subtasks) > 0 {
		for _, subtask := range subtasks {
			if subtaskMap, ok := subtask.(map[string]any); ok {
				parts = append(parts, h.formatTask(subtaskMap, indent+1))
			}
		}
	}
	
	return strings.Join(parts, "\n")
}

// Helper formatting functions

func (h *PlanningResponseHandler) formatPlanType(planType string) string {
	typeEmojis := map[string]string{
		"feature":   "✨",
		"refactor":  "♻️",
		"bugfix":    "🐛",
		"analysis":  "📊",
		"migration": "🚀",
	}
	
	emoji := "📋"
	if e, ok := typeEmojis[planType]; ok {
		emoji = e
	}
	
	return fmt.Sprintf("%s %s", emoji, strings.Title(planType))
}

func (h *PlanningResponseHandler) formatPlanStatus(status string) string {
	statusEmojis := map[string]string{
		"draft":       "📝",
		"ready":       "✅",
		"in_progress": "⚙️",
		"executing":   "⚙️",
		"completed":   "✔️",
		"failed":      "❌",
	}
	
	emoji := "❓"
	if e, ok := statusEmojis[status]; ok {
		emoji = e
	}
	
	return fmt.Sprintf("%s %s", emoji, strings.Title(strings.Replace(status, "_", " ", -1)))
}

func (h *PlanningResponseHandler) formatTaskStatus(status string) string {
	statusEmojis := map[string]string{
		"pending":     "⏳",
		"in_progress": "🔄",
		"completed":   "✅",
		"failed":      "❌",
	}
	
	emoji := ""
	if e, ok := statusEmojis[status]; ok {
		emoji = e
	}
	
	return emoji
}

func (h *PlanningResponseHandler) formatComplexity(complexity string) string {
	complexityEmojis := map[string]string{
		"trivial":      "⚪",
		"simple":       "🟢",
		"medium":       "🟡",
		"complex":      "🟠",
		"very_complex": "🔴",
	}
	
	emoji := ""
	if e, ok := complexityEmojis[complexity]; ok {
		emoji = e
	}
	
	return fmt.Sprintf("%s %s", emoji, strings.Replace(complexity, "_", " ", -1))
}

func (h *PlanningResponseHandler) formatValidationStatus(status string) string {
	statusEmojis := map[string]string{
		"passed":  "✅",
		"warning": "⚠️",
		"failed":  "❌",
	}
	
	emoji := "❓"
	if e, ok := statusEmojis[status]; ok {
		emoji = e
	}
	
	return fmt.Sprintf("%s %s", emoji, strings.Title(status))
}