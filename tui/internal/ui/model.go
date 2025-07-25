package ui

import (
	"time"
	
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/nshafer/phx"
	"github.com/rubber_duck/tui/internal/phoenix"
)

// Pane represents the different panes in the UI
type Pane int

const (
	ChatPane Pane = iota
	FileTreePane
	EditorPane
	OutputPane
)

// Model represents the application state
type Model struct {
	// Application state
	activePane   Pane
	width        int
	height       int
	err          error
	
	// Chat state
	chat         *Chat
	chatHeader   *ChatHeader
	
	// Status messages state
	statusMessages *StatusMessages
	
	// File tree state (optional)
	fileTree     *FileTree
	showFileTree bool
	
	// Editor state (optional)
	editor       textarea.Model
	showEditor   bool
	currentFile  string
	
	// Output pane state
	output       viewport.Model
	
	// Phoenix WebSocket state
	phoenixClient interface{} // Will be *phoenix.Client
	authClient   interface{} // Will be *phoenix.AuthClient
	statusClient interface{} // Will be *phoenix.StatusClient
	apiKeyClient interface{} // Will be *phoenix.ApiKeyClient
	socket       *phx.Socket
	authSocket   *phx.Socket // Separate socket for auth operations
	channel      *phx.Channel
	connected    bool
	phoenixURL   string
	authSocketURL string
	apiKey       string
	jwtToken     string // JWT token received after authentication
	
	// Auth state
	authenticated bool
	username      string
	userID        string // User ID for api_keys channel
	switchingSocket bool // True when switching from auth to user socket
	
	// Status bar
	statusBar    string
	systemMessage string // System message to display in status bar
	
	// Error handling
	errorHandler *ErrorHandler
	reconnectAttempts int
	lastReconnectTime time.Time
	totalConnectionAttempts int
	connectionBlocked bool
	
	// Modal states
	modal        Modal
	commandPalette CommandPalette
	
	// LLM configuration
	currentModel    string
	currentProvider string
	temperature     float64
	
	// Conversation metadata
	conversationID string
	messageCount   int
	tokenUsage     int
	tokenLimit     int
	
	// Status category metadata
	categoryMetadata map[string]CategoryInfo
	
	// Configuration
	config *Config
}

// CategoryInfo stores metadata about a status category
type CategoryInfo struct {
	Name        string
	Description string
	Color       string // Terminal color code/name
}

// NewModel creates a new TUI model with default state
func NewModel() *Model {
	// Create chat component (primary interface)
	chat := NewChat()
	
	// Create editor
	editor := textarea.New()
	editor.Placeholder = "Select a file to start editing..."
	editor.ShowLineNumbers = true
	
	// Create output viewport
	output := viewport.New(0, 0)
	
	// Create Phoenix client
	phoenixClient := phoenix.NewClient()
	authClient := phoenix.NewAuthClient()
	statusClient := phoenix.NewStatusClient()
	apiKeyClient := phoenix.NewApiKeyClient()
	
	// Create chat header
	chatHeader := NewChatHeader()
	
	// Create status messages component
	statusMessages := NewStatusMessages()
	
	// Create error handler
	errorHandler := NewErrorHandler()
	
	// Load configuration
	config, err := LoadConfig()
	if err != nil {
		// If config fails to load, use empty config with defaults
		config = &Config{
			Providers: make(map[string]ProviderConfig),
			TUI: TUIConfig{
				StatusCategoryColors: make(map[string]string),
			},
		}
	}
	
	model := &Model{
		activePane:   ChatPane, // Chat is primary
		width:        80,       // Default width
		height:       24,       // Default height
		chat:         chat,
		chatHeader:   chatHeader,
		statusMessages: statusMessages,
		fileTree:     NewFileTree(),
		editor:       editor,
		output:       output,
		showFileTree: false,    // Hidden by default
		showEditor:   false,    // Hidden by default
		statusBar:    "Welcome to RubberDuck TUI | Connecting to auth server...",
		systemMessage: "", // Start with empty system message
		errorHandler: errorHandler,
		modal:        NewModal(),
		commandPalette: NewCommandPalette(),
		phoenixURL:   "ws://localhost:5555/socket",
		authSocketURL: "ws://localhost:5555/auth_socket",
		apiKey:       "",
		jwtToken:     "",
		phoenixClient: phoenixClient,
		authClient:   authClient,
		statusClient: statusClient,
		apiKeyClient: apiKeyClient,
		currentModel:    "",  // Empty means use default
		currentProvider: "",  // Empty means unknown
		temperature:     0.7,
		authenticated:   false,
		username:     "",
		userID:       "",
		conversationID: "lobby",
		messageCount:  0,
		tokenUsage:    0,
		tokenLimit:    4096,
		categoryMetadata: make(map[string]CategoryInfo),
		config:        config,
	}
	
	// Initialize component sizes with defaults
	model.updateComponentSizes()
	
	return model
}

// Init implements tea.Model
func (m Model) Init() tea.Cmd {
	// Initialize with window size detection
	return tea.Batch(
		tea.WindowSize(),
		func() tea.Msg {
			return InitiateConnectionMsg{} // Connect to Phoenix on startup
		},
	)
}

// SetDimensions updates the model dimensions
func (m *Model) SetDimensions(width, height int) {
	m.width = width
	m.height = height
	m.updateComponentSizes()
}

// updateComponentSizes recalculates component sizes based on current layout
func (m *Model) updateComponentSizes() {
	if m.width == 0 || m.height == 0 {
		return
	}
	
	// Layout calculation for chat-focused interface
	statusBarHeight := 1
	contentHeight := m.height - statusBarHeight
	
	// Calculate widths based on visible panels
	chatWidth := m.width
	
	if m.showFileTree {
		fileTreeWidth := 30 // Fixed width for file tree
		chatWidth -= fileTreeWidth + 2 // 2 for borders
		m.fileTree.width = fileTreeWidth
		m.fileTree.height = contentHeight
	}
	
	if m.showEditor {
		editorWidth := 40 // Fixed width for editor
		chatWidth -= editorWidth + 2 // 2 for borders
		m.editor.SetWidth(editorWidth)
		m.editor.SetHeight(contentHeight)
	}
	
	// Update chat header size
	m.chatHeader.SetSize(chatWidth-2) // -2 for borders
	
	// Calculate heights for chat and status sections
	headerHeight := 3 // chat header takes 3 lines
	availableHeight := contentHeight - headerHeight - 2 // -2 for main borders
	
	// Status messages take 30% of available conversation area
	statusHeight := int(float64(availableHeight) * 0.3)
	if statusHeight < 5 {
		statusHeight = 5 // Minimum height
	}
	chatHeight := availableHeight - statusHeight - 2 // -2 for spacing between sections
	
	// Update chat and status message sizes (account for borders)
	m.chat.SetSize(chatWidth-4, chatHeight-2) // -4 for borders, -2 for height borders
	m.statusMessages.SetSize(chatWidth-4, statusHeight-2) // -4 for borders, -2 for height borders
	
	// Update output viewport size
	m.output.Width = 40
	m.output.Height = contentHeight
}

// SetPhoenixConfig updates the Phoenix connection configuration
func (m *Model) SetPhoenixConfig(url, authURL, apiKey string) {
	m.phoenixURL = url
	m.authSocketURL = authURL
	m.apiKey = apiKey
}

// GetPhoenixClient returns the Phoenix client interface
func (m *Model) GetPhoenixClient() interface{} {
	return m.phoenixClient
}

// GetAuthClient returns the Auth client interface
func (m *Model) GetAuthClient() interface{} {
	return m.authClient
}

// GetStatusClient returns the Status client interface
func (m *Model) GetStatusClient() interface{} {
	return m.statusClient
}

// GetApiKeyClient returns the ApiKey client interface
func (m *Model) GetApiKeyClient() interface{} {
	return m.apiKeyClient
}

// SetSystemMessage sets the system message to display in the status bar
func (m *Model) SetSystemMessage(message string) {
	m.systemMessage = message
}

// ClearSystemMessage clears the system message from the status bar
func (m *Model) ClearSystemMessage() {
	m.systemMessage = ""
}