package commands

import (
	"encoding/json"
	"time"
)

// UnifiedCommand represents a command in the RubberDuck unified command system
type UnifiedCommand struct {
	Command   string                 `json:"command"`
	Subcommand string                `json:"subcommand,omitempty"`
	Args      map[string]interface{} `json:"args,omitempty"`
	Options   map[string]interface{} `json:"options,omitempty"`
	Context   CommandContext         `json:"context"`
}

// CommandContext represents the context for command execution
type CommandContext struct {
	ClientType    string                 `json:"client_type"`
	ProjectID     string                 `json:"project_id,omitempty"`
	UserID        string                 `json:"user_id,omitempty"`
	SessionID     string                 `json:"session_id,omitempty"`
	CurrentFile   string                 `json:"current_file,omitempty"`
	CursorLine    int                    `json:"cursor_line,omitempty"`
	CursorColumn  int                    `json:"cursor_column,omitempty"`
	SelectedText  string                 `json:"selected_text,omitempty"`
	EditorContent string                 `json:"editor_content,omitempty"`
	Language      string                 `json:"language,omitempty"`
	Permissions   []string               `json:"permissions,omitempty"`
	Metadata      map[string]interface{} `json:"metadata,omitempty"`
}

// UnifiedResponse represents a response from the unified command system
type UnifiedResponse struct {
	ID            string                 `json:"id"`
	Command       string                 `json:"command"`
	Status        string                 `json:"status"` // "success", "error", "pending", "streaming"
	Format        string                 `json:"format"` // "text", "json", "table", "markdown", "ansi"
	Content       string                 `json:"content,omitempty"`
	Data          map[string]interface{} `json:"data,omitempty"`
	Error         *CommandError          `json:"error,omitempty"`
	Progress      *ProgressInfo          `json:"progress,omitempty"`
	Stream        *StreamInfo            `json:"stream,omitempty"`
	Timestamp     time.Time              `json:"timestamp"`
	Duration      time.Duration          `json:"duration,omitempty"`
}

// CommandError represents an error from command execution
type CommandError struct {
	Code        string                 `json:"code"`
	Message     string                 `json:"message"`
	Details     map[string]interface{} `json:"details,omitempty"`
	Recoverable bool                   `json:"recoverable"`
	Suggestions []string               `json:"suggestions,omitempty"`
}

// ProgressInfo represents progress information for long-running commands
type ProgressInfo struct {
	Current     int    `json:"current"`
	Total       int    `json:"total"`
	Percentage  int    `json:"percentage"`
	Message     string `json:"message"`
	Cancellable bool   `json:"cancellable"`
}

// StreamInfo represents streaming information
type StreamInfo struct {
	ID       string `json:"id"`
	Event    string `json:"event"` // "start", "data", "end", "error"
	Sequence int    `json:"sequence"`
	Final    bool   `json:"final"`
}

// CommandType represents the type of command routing
type CommandType int

const (
	// LocalCommand is handled entirely within the TUI
	LocalCommand CommandType = iota
	// ServerCommand is routed to the unified command system
	ServerCommand
	// HybridCommand is handled locally but may call server for data
	HybridCommand
)

// LocalTUICommand represents a command that is handled locally in the TUI
type LocalTUICommand struct {
	Name        string
	Description string
	Category    string
	Handler     func(args map[string]interface{}, context CommandContext) error
}

// CommandDefinition contains information about a command
type CommandDefinition struct {
	Name         string      `json:"name"`
	Description  string      `json:"description"`
	Category     string      `json:"category"`
	Type         CommandType `json:"type"`
	Args         []ArgDef    `json:"args,omitempty"`
	Options      []OptDef    `json:"options,omitempty"`
	Permissions  []string    `json:"permissions,omitempty"`
	Examples     []string    `json:"examples,omitempty"`
	ServerOnly   bool        `json:"server_only"`
	LocalOnly    bool        `json:"local_only"`
}

// ArgDef defines a command argument
type ArgDef struct {
	Name        string      `json:"name"`
	Description string      `json:"description"`
	Type        string      `json:"type"` // "string", "int", "bool", "file", "directory"
	Required    bool        `json:"required"`
	Default     interface{} `json:"default,omitempty"`
	Validation  string      `json:"validation,omitempty"`
}

// OptDef defines a command option
type OptDef struct {
	Name        string      `json:"name"`
	Description string      `json:"description"`
	Type        string      `json:"type"`
	Required    bool        `json:"required"`
	Default     interface{} `json:"default,omitempty"`
	Choices     []string    `json:"choices,omitempty"`
}

// CommandRegistry holds all available commands
type CommandRegistry struct {
	Commands map[string]CommandDefinition `json:"commands"`
	Local    map[string]LocalTUICommand   `json:"-"`
}

// RouterConfig configures the command router
type RouterConfig struct {
	EnableServerCommands  bool     `json:"enable_server_commands"`
	EnableLocalCommands   bool     `json:"enable_local_commands"`
	DefaultFormat         string   `json:"default_format"`
	CommandTimeout        time.Duration `json:"command_timeout"`
	MaxConcurrentCommands int      `json:"max_concurrent_commands"`
	RetryAttempts         int      `json:"retry_attempts"`
	AllowedCommands       []string `json:"allowed_commands,omitempty"`
	BlockedCommands       []string `json:"blocked_commands,omitempty"`
}

// CommandResult represents the result of command execution
type CommandResult struct {
	Success   bool                   `json:"success"`
	Output    string                 `json:"output,omitempty"`
	Data      map[string]interface{} `json:"data,omitempty"`
	Error     error                  `json:"error,omitempty"`
	Duration  time.Duration          `json:"duration"`
	Metadata  map[string]interface{} `json:"metadata,omitempty"`
}

// StreamEvent represents a streaming event from command execution
type StreamEvent struct {
	Type      string    `json:"type"`
	Data      string    `json:"data"`
	Timestamp time.Time `json:"timestamp"`
	Sequence  int       `json:"sequence"`
	Final     bool      `json:"final"`
}

// CommandStats tracks command execution statistics
type CommandStats struct {
	CommandName     string        `json:"command_name"`
	ExecutionCount  int           `json:"execution_count"`
	SuccessCount    int           `json:"success_count"`
	ErrorCount      int           `json:"error_count"`
	AverageLatency  time.Duration `json:"average_latency"`
	LastExecuted    time.Time     `json:"last_executed"`
	TotalDuration   time.Duration `json:"total_duration"`
}

// Implement error interface for CommandError
func (e *CommandError) Error() string {
	return e.Message
}

// ToJSON converts UnifiedCommand to JSON string
func (cmd *UnifiedCommand) ToJSON() (string, error) {
	data, err := json.Marshal(cmd)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

// FromJSON creates UnifiedCommand from JSON string
func (cmd *UnifiedCommand) FromJSON(data string) error {
	return json.Unmarshal([]byte(data), cmd)
}

// IsValid validates the command structure
func (cmd *UnifiedCommand) IsValid() bool {
	return cmd.Command != "" && cmd.Context.ClientType != ""
}

// SetTUIContext sets TUI-specific context fields
func (ctx *CommandContext) SetTUIContext(currentFile, content, language string, line, col int) {
	ctx.ClientType = "tui"
	ctx.CurrentFile = currentFile
	ctx.EditorContent = content
	ctx.Language = language
	ctx.CursorLine = line
	ctx.CursorColumn = col
}

// AddMetadata adds metadata to the context
func (ctx *CommandContext) AddMetadata(key string, value interface{}) {
	if ctx.Metadata == nil {
		ctx.Metadata = make(map[string]interface{})
	}
	ctx.Metadata[key] = value
}

// IsSuccess returns true if the response indicates success
func (resp *UnifiedResponse) IsSuccess() bool {
	return resp.Status == "success"
}

// IsError returns true if the response indicates an error
func (resp *UnifiedResponse) IsError() bool {
	return resp.Status == "error"
}

// IsStreaming returns true if the response is a streaming response
func (resp *UnifiedResponse) IsStreaming() bool {
	return resp.Status == "streaming" || resp.Stream != nil
}