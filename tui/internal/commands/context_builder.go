package commands

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/rubber_duck/tui/internal/ui"
)

// ContextBuilder builds command context from TUI state
type ContextBuilder struct {
	sessionID   string
	startTime   time.Time
	permissions []string
}

// NewContextBuilder creates a new context builder
func NewContextBuilder() *ContextBuilder {
	return &ContextBuilder{
		sessionID:   generateSessionID(),
		startTime:   time.Now(),
		permissions: []string{"read", "write", "analyze", "generate"}, // Default permissions
	}
}

// BuildContext builds a command context from TUI state
func (cb *ContextBuilder) BuildContext(tuiState interface{}) CommandContext {
	context := CommandContext{
		ClientType:  "tui",
		SessionID:   cb.sessionID,
		Permissions: cb.permissions,
		Metadata:    make(map[string]interface{}),
	}

	// Try to extract context from different TUI state types
	switch state := tuiState.(type) {
	case ui.Model:
		cb.extractFromModel(&context, state)
	case *ui.Model:
		cb.extractFromModel(&context, *state)
	case TUIContext:
		cb.extractFromTUIContext(&context, state)
	case map[string]interface{}:
		cb.extractFromMap(&context, state)
	default:
		// Try to extract basic information if possible
		cb.addDefaultContext(&context)
	}

	// Add session metadata
	context.AddMetadata("session_start", cb.startTime)
	context.AddMetadata("session_duration", time.Since(cb.startTime))
	context.AddMetadata("client_version", "1.0.0")
	context.AddMetadata("platform", "tui")

	// Add environment information
	cb.addEnvironmentContext(&context)

	return context
}

// extractFromModel extracts context from a ui.Model
func (cb *ContextBuilder) extractFromModel(context *CommandContext, model ui.Model) {
	// Extract current file information
	if currentFile := cb.getCurrentFile(model); currentFile != "" {
		context.CurrentFile = currentFile
		context.Language = cb.detectLanguage(currentFile)
	}

	// Extract editor content
	if content := cb.getEditorContent(model); content != "" {
		context.EditorContent = content
		
		// Calculate cursor position if possible
		if line, col := cb.getCursorPosition(model); line > 0 {
			context.CursorLine = line
			context.CursorColumn = col
		}
	}

	// Extract selected text
	if selectedText := cb.getSelectedText(model); selectedText != "" {
		context.SelectedText = selectedText
	}

	// Add project information
	if projectPath := cb.getProjectPath(model); projectPath != "" {
		context.ProjectID = cb.generateProjectID(projectPath)
		context.AddMetadata("project_path", projectPath)
	}

	// Add TUI-specific metadata
	context.AddMetadata("active_pane", cb.getActivePane(model))
	context.AddMetadata("connected", cb.isConnected(model))
	context.AddMetadata("theme", cb.getCurrentTheme(model))
	
	// Add file tree context
	if files := cb.getOpenFiles(model); len(files) > 0 {
		context.AddMetadata("open_files", files)
	}

	// Add analysis state
	if analyzing := cb.isAnalyzing(model); analyzing {
		context.AddMetadata("analyzing", true)
	}
}

// extractFromTUIContext extracts context from a TUIContext struct
func (cb *ContextBuilder) extractFromTUIContext(context *CommandContext, tuiCtx TUIContext) {
	context.CurrentFile = tuiCtx.CurrentFile
	context.EditorContent = tuiCtx.EditorContent
	context.Language = tuiCtx.Language
	context.CursorLine = tuiCtx.CursorLine
	context.CursorColumn = tuiCtx.CursorColumn
	context.SelectedText = tuiCtx.SelectedText
	context.ProjectID = tuiCtx.ProjectID

	// Copy metadata
	for key, value := range tuiCtx.Metadata {
		context.AddMetadata(key, value)
	}
}

// extractFromMap extracts context from a generic map
func (cb *ContextBuilder) extractFromMap(context *CommandContext, data map[string]interface{}) {
	if file, ok := data["current_file"].(string); ok {
		context.CurrentFile = file
		context.Language = cb.detectLanguage(file)
	}

	if content, ok := data["editor_content"].(string); ok {
		context.EditorContent = content
	}

	if line, ok := data["cursor_line"].(int); ok {
		context.CursorLine = line
	}

	if col, ok := data["cursor_column"].(int); ok {
		context.CursorColumn = col
	}

	if selected, ok := data["selected_text"].(string); ok {
		context.SelectedText = selected
	}

	if projectID, ok := data["project_id"].(string); ok {
		context.ProjectID = projectID
	}

	// Copy other metadata
	for key, value := range data {
		if !isContextField(key) {
			context.AddMetadata(key, value)
		}
	}
}

// addDefaultContext adds default context when TUI state is not available
func (cb *ContextBuilder) addDefaultContext(context *CommandContext) {
	// Try to get current working directory as project
	if cwd, err := os.Getwd(); err == nil {
		context.ProjectID = cb.generateProjectID(cwd)
		context.AddMetadata("project_path", cwd)
	}

	context.AddMetadata("default_context", true)
}

// addEnvironmentContext adds environment-specific context
func (cb *ContextBuilder) addEnvironmentContext(context *CommandContext) {
	// Add OS information
	context.AddMetadata("os", getOS())
	
	// Add terminal information
	if term := os.Getenv("TERM"); term != "" {
		context.AddMetadata("terminal", term)
	}

	// Add working directory
	if cwd, err := os.Getwd(); err == nil {
		context.AddMetadata("working_directory", cwd)
	}

	// Add user information (if available)
	if user := os.Getenv("USER"); user == "" {
		if user = os.Getenv("USERNAME"); user != "" {
			context.UserID = user
		}
	} else {
		context.UserID = user
	}
}

// Helper methods to extract information from ui.Model
// Note: These methods use reflection or type assertions to access model fields
// In a real implementation, these would need to be implemented based on the actual ui.Model structure

func (cb *ContextBuilder) getCurrentFile(model ui.Model) string {
	// This would need to access the actual field from ui.Model
	// For now, return empty string - would be implemented based on actual model structure
	return ""
}

func (cb *ContextBuilder) getEditorContent(model ui.Model) string {
	// This would access the editor content from ui.Model
	return ""
}

func (cb *ContextBuilder) getCursorPosition(model ui.Model) (line, col int) {
	// This would access cursor position from ui.Model
	return 0, 0
}

func (cb *ContextBuilder) getSelectedText(model ui.Model) string {
	// This would access selected text from ui.Model
	return ""
}

func (cb *ContextBuilder) getProjectPath(model ui.Model) string {
	// This would determine the current project path
	return ""
}

func (cb *ContextBuilder) getActivePane(model ui.Model) string {
	// This would get the currently active pane
	return "editor"
}

func (cb *ContextBuilder) isConnected(model ui.Model) bool {
	// This would check if TUI is connected to server
	return false
}

func (cb *ContextBuilder) getCurrentTheme(model ui.Model) string {
	// This would get the current theme name
	return "dark"
}

func (cb *ContextBuilder) getOpenFiles(model ui.Model) []string {
	// This would get list of open files
	return []string{}
}

func (cb *ContextBuilder) isAnalyzing(model ui.Model) bool {
	// This would check if analysis is in progress
	return false
}

// Utility methods

func (cb *ContextBuilder) detectLanguage(filename string) string {
	ext := strings.ToLower(filepath.Ext(filename))
	
	langMap := map[string]string{
		".go":   "go",
		".js":   "javascript",
		".ts":   "typescript",
		".py":   "python",
		".rs":   "rust",
		".java": "java",
		".cpp":  "cpp",
		".c":    "c",
		".html": "html",
		".css":  "css",
		".json": "json",
		".yaml": "yaml",
		".yml":  "yaml",
		".md":   "markdown",
		".ex":   "elixir",
		".exs":  "elixir",
	}

	if lang, exists := langMap[ext]; exists {
		return lang
	}
	return "text"
}

func (cb *ContextBuilder) generateProjectID(projectPath string) string {
	// Generate a stable project ID based on path
	abs, err := filepath.Abs(projectPath)
	if err != nil {
		abs = projectPath
	}
	return fmt.Sprintf("project_%x", hashString(abs))
}

func generateSessionID() string {
	return fmt.Sprintf("tui_session_%d", time.Now().UnixNano())
}

func hashString(s string) uint32 {
	// Simple hash function for generating project IDs
	hash := uint32(0)
	for _, c := range s {
		hash = hash*31 + uint32(c)
	}
	return hash
}

func getOS() string {
	// Simple OS detection
	if strings.Contains(strings.ToLower(os.Getenv("OS")), "windows") {
		return "windows"
	}
	return "unix"
}

func isContextField(key string) bool {
	contextFields := []string{
		"current_file", "editor_content", "language", "cursor_line",
		"cursor_column", "selected_text", "project_id",
	}
	
	for _, field := range contextFields {
		if field == key {
			return true
		}
	}
	return false
}

// TUIContext represents a simplified context structure that can be passed directly
type TUIContext struct {
	CurrentFile   string                 `json:"current_file"`
	EditorContent string                 `json:"editor_content"`
	Language      string                 `json:"language"`
	CursorLine    int                    `json:"cursor_line"`
	CursorColumn  int                    `json:"cursor_column"`
	SelectedText  string                 `json:"selected_text"`
	ProjectID     string                 `json:"project_id"`
	Metadata      map[string]interface{} `json:"metadata"`
}

// BuildTUIContext creates a TUIContext from basic parameters
func BuildTUIContext(currentFile, content, language string, line, col int) TUIContext {
	return TUIContext{
		CurrentFile:   currentFile,
		EditorContent: content,
		Language:      language,
		CursorLine:    line,
		CursorColumn:  col,
		Metadata:      make(map[string]interface{}),
	}
}