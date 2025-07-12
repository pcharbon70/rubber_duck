package phoenix

import (
	"encoding/json"
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

// PhoenixClient defines the interface for Phoenix channel communication
type PhoenixClient interface {
	// Connection management
	Connect(config Config, program *tea.Program) tea.Cmd
	Disconnect() tea.Cmd
	IsConnected() bool
	
	// Channel operations
	JoinChannel(topic string) tea.Cmd
	LeaveChannel(topic string) tea.Cmd
	
	// Message operations
	Push(event string, payload map[string]any) tea.Cmd
	PushWithResponse(event string, payload map[string]any, timeout time.Duration) tea.Cmd
	
	// File operations
	ListFiles(path string) tea.Cmd
	LoadFile(path string) tea.Cmd
	SaveFile(path string, content string) tea.Cmd
	WatchFile(path string) tea.Cmd
	
	// Analysis operations
	AnalyzeFile(path string, analysisType string) tea.Cmd
	AnalyzeProject(rootPath string, options map[string]any) tea.Cmd
	GetAnalysisResult(analysisId string) tea.Cmd
	
	// Code operations
	GenerateCode(prompt string, context map[string]any) tea.Cmd
	CompleteCode(content string, position int, language string) tea.Cmd
	RefactorCode(content string, instruction string, options map[string]any) tea.Cmd
	GenerateTests(filePath string, testType string) tea.Cmd
	
	// LLM operations
	ListProviders() tea.Cmd
	GetProviderStatus(provider string) tea.Cmd
	SetActiveProvider(provider string) tea.Cmd
	
	// Health operations
	GetHealthStatus() tea.Cmd
	GetSystemMetrics() tea.Cmd
}

// Response types for different operations
type (
	// Connection responses
	ConnectionResponse struct {
		Status    string `json:"status"`
		Message   string `json:"message,omitempty"`
		Timestamp string `json:"timestamp"`
	}
	
	// File operation responses
	FileListResponse struct {
		Files []FileInfo `json:"files"`
		Path  string     `json:"path"`
	}
	
	FileInfo struct {
		Name      string     `json:"name"`
		Path      string     `json:"path"`
		IsDir     bool       `json:"is_dir"`
		Size      int64      `json:"size,omitempty"`
		ModTime   time.Time  `json:"mod_time,omitempty"`
		Children  []FileInfo `json:"children,omitempty"`
	}
	
	FileContentResponse struct {
		Path     string `json:"path"`
		Content  string `json:"content"`
		Language string `json:"language,omitempty"`
		Size     int64  `json:"size"`
	}
	
	FileSaveResponse struct {
		Path      string `json:"path"`
		Success   bool   `json:"success"`
		Message   string `json:"message,omitempty"`
		Timestamp string `json:"timestamp"`
	}
	
	// Analysis responses
	AnalysisResponse struct {
		ID          string                 `json:"id"`
		Type        string                 `json:"type"`
		Status      string                 `json:"status"`
		Results     map[string]any         `json:"results,omitempty"`
		Issues      []AnalysisIssue        `json:"issues,omitempty"`
		Metrics     map[string]any         `json:"metrics,omitempty"`
		Suggestions []AnalysisSuggestion   `json:"suggestions,omitempty"`
		StartedAt   time.Time              `json:"started_at"`
		CompletedAt *time.Time             `json:"completed_at,omitempty"`
	}
	
	AnalysisIssue struct {
		Type        string            `json:"type"`
		Severity    string            `json:"severity"`
		Message     string            `json:"message"`
		File        string            `json:"file,omitempty"`
		Line        int               `json:"line,omitempty"`
		Column      int               `json:"column,omitempty"`
		Rule        string            `json:"rule,omitempty"`
		Suggestion  string            `json:"suggestion,omitempty"`
		Context     map[string]any    `json:"context,omitempty"`
	}
	
	AnalysisSuggestion struct {
		Type        string         `json:"type"`
		Description string         `json:"description"`
		File        string         `json:"file,omitempty"`
		StartLine   int            `json:"start_line,omitempty"`
		EndLine     int            `json:"end_line,omitempty"`
		Replacement string         `json:"replacement,omitempty"`
		Confidence  float64        `json:"confidence"`
	}
	
	// Code generation responses
	GenerationResponse struct {
		ID        string    `json:"id"`
		Status    string    `json:"status"`
		Content   string    `json:"content,omitempty"`
		Language  string    `json:"language,omitempty"`
		Streaming bool      `json:"streaming"`
		CreatedAt time.Time `json:"created_at"`
	}
	
	CompletionResponse struct {
		Completions []CodeCompletion `json:"completions"`
		Position    int              `json:"position"`
		Language    string           `json:"language"`
	}
	
	CodeCompletion struct {
		Text        string  `json:"text"`
		Description string  `json:"description,omitempty"`
		Type        string  `json:"type"`
		Confidence  float64 `json:"confidence"`
		StartPos    int     `json:"start_pos"`
		EndPos      int     `json:"end_pos"`
	}
	
	RefactorResponse struct {
		ID          string              `json:"id"`
		Status      string              `json:"status"`
		Changes     []RefactorChange    `json:"changes,omitempty"`
		Description string              `json:"description,omitempty"`
		Preview     string              `json:"preview,omitempty"`
	}
	
	RefactorChange struct {
		File        string `json:"file"`
		StartLine   int    `json:"start_line"`
		EndLine     int    `json:"end_line"`
		StartCol    int    `json:"start_col"`
		EndCol      int    `json:"end_col"`
		OldContent  string `json:"old_content"`
		NewContent  string `json:"new_content"`
		Description string `json:"description"`
	}
	
	// LLM responses
	ProvidersResponse struct {
		Providers []ProviderInfo `json:"providers"`
		Active    string         `json:"active"`
	}
	
	ProviderInfo struct {
		Name        string            `json:"name"`
		Type        string            `json:"type"`
		Status      string            `json:"status"`
		Models      []string          `json:"models,omitempty"`
		Capabilities []string         `json:"capabilities,omitempty"`
		Config      map[string]any    `json:"config,omitempty"`
		Metrics     map[string]any    `json:"metrics,omitempty"`
	}
	
	// Health responses
	HealthResponse struct {
		Status     string                    `json:"status"`
		Components map[string]ComponentHealth `json:"components"`
		Uptime     time.Duration             `json:"uptime"`
		Version    string                    `json:"version"`
		Timestamp  time.Time                 `json:"timestamp"`
	}
	
	ComponentHealth struct {
		Status  string         `json:"status"`
		Message string         `json:"message,omitempty"`
		Details map[string]any `json:"details,omitempty"`
	}
	
	// Streaming responses
	StreamResponse struct {
		ID     string          `json:"id"`
		Type   string          `json:"type"`
		Event  string          `json:"event"` // "start", "data", "end", "error"
		Data   json.RawMessage `json:"data,omitempty"`
		Error  string          `json:"error,omitempty"`
	}
)

// Error types
type (
	PhoenixError struct {
		Code      string `json:"code"`
		Message   string `json:"message"`
		Details   any    `json:"details,omitempty"`
		Timestamp string `json:"timestamp"`
	}
	
	ConnectionError struct {
		Type    string `json:"type"`
		Message string `json:"message"`
		Retry   bool   `json:"retry"`
	}
	
	ChannelError struct {
		Channel string `json:"channel"`
		Event   string `json:"event"`
		Message string `json:"message"`
	}
)

// Implement error interface
func (e PhoenixError) Error() string {
	return e.Message
}

func (e ConnectionError) Error() string {
	return e.Message
}

func (e ChannelError) Error() string {
	return e.Message
}