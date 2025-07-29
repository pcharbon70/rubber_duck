package ui

import (
	"fmt"
	"strings"
	"sync"

	"github.com/rubber_duck/tui/internal/phoenix"
)

// ResponseHandler defines the interface for formatting conversation responses
type ResponseHandler interface {
	// FormatResponse formats a response based on its type and metadata
	FormatResponse(response phoenix.ConversationMessage) string
	
	// GetConversationType returns the conversation type this handler handles
	GetConversationType() string
}

// ResponseHandlerRegistry manages response handlers by conversation type
type ResponseHandlerRegistry struct {
	mu       sync.RWMutex
	handlers map[string]ResponseHandler
	defaultHandler ResponseHandler
}

// NewResponseHandlerRegistry creates a new handler registry with default handlers
func NewResponseHandlerRegistry() *ResponseHandlerRegistry {
	registry := &ResponseHandlerRegistry{
		handlers: make(map[string]ResponseHandler),
	}
	
	// Set default handler
	registry.defaultHandler = &SimpleResponseHandler{}
	
	// Register built-in handlers
	// Note: conversation_type comes as string representation of Elixir atoms
	registry.handlers["simple"] = &SimpleResponseHandler{}
	registry.handlers["simple_conversation"] = &SimpleResponseHandler{}
	
	registry.handlers["complex"] = &ComplexResponseHandler{}
	registry.handlers["complex_conversation"] = &ComplexResponseHandler{}
	
	registry.handlers["analysis"] = &AnalysisResponseHandler{}
	registry.handlers["analysis_conversation"] = &AnalysisResponseHandler{}
	
	registry.handlers["generation"] = &GenerationResponseHandler{}
	registry.handlers["generation_conversation"] = &GenerationResponseHandler{}
	
	registry.handlers["problem_solving"] = &ProblemSolvingResponseHandler{}
	registry.handlers["problem_solver"] = &ProblemSolvingResponseHandler{}
	
	registry.handlers["multi_step"] = &MultiStepResponseHandler{}
	registry.handlers["multi_step_conversation"] = &MultiStepResponseHandler{}
	
	registry.handlers["planning"] = &PlanningResponseHandler{}
	registry.handlers["planning_conversation"] = &PlanningResponseHandler{}
	
	return registry
}

// RegisterHandler registers a handler for its conversation type
func (r *ResponseHandlerRegistry) RegisterHandler(handler ResponseHandler) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.handlers[handler.GetConversationType()] = handler
}

// GetHandler returns the appropriate handler for a conversation type
func (r *ResponseHandlerRegistry) GetHandler(conversationType string) ResponseHandler {
	r.mu.RLock()
	defer r.mu.RUnlock()
	
	if handler, exists := r.handlers[conversationType]; exists {
		return handler
	}
	return r.defaultHandler
}

// FormatResponse formats a response using the appropriate handler
func (r *ResponseHandlerRegistry) FormatResponse(response phoenix.ConversationMessage) string {
	handler := r.GetHandler(response.ConversationType)
	return handler.FormatResponse(response)
}

// BaseResponseHandler provides common functionality for response handlers
type BaseResponseHandler struct{}

// formatMetadata formats metadata if present
func (h *BaseResponseHandler) formatMetadata(metadata map[string]any) string {
	if len(metadata) == 0 {
		return ""
	}
	
	var parts []string
	parts = append(parts, "\n---")
	parts = append(parts, "*Metadata:*")
	
	for key, value := range metadata {
		// Skip internal metadata
		if strings.HasPrefix(key, "_") {
			continue
		}
		parts = append(parts, fmt.Sprintf("- **%s**: %v", key, value))
	}
	
	return strings.Join(parts, "\n")
}

// addSectionHeader adds a formatted section header
func (h *BaseResponseHandler) addSectionHeader(title string) string {
	return fmt.Sprintf("\n### %s\n", title)
}

// addEmphasis adds emphasis to important text
func (h *BaseResponseHandler) addEmphasis(text string) string {
	return fmt.Sprintf("**%s**", text)
}

// addCodeBlock formats text as a code block
func (h *BaseResponseHandler) addCodeBlock(code string, language string) string {
	if language != "" {
		return fmt.Sprintf("```%s\n%s\n```", language, code)
	}
	return fmt.Sprintf("```\n%s\n```", code)
}