package ui

import (
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/nshafer/phx"
	"github.com/rubber_duck/tui/internal/phoenix"
)

// Pane represents the different panes in the UI
type Pane int

const (
	FileTreePane Pane = iota
	EditorPane
	OutputPane
)

// Model represents the application state
type Model struct {
	// Application state
	files      []FileNode
	editor     textarea.Model
	output     viewport.Model
	statusBar  string
	
	// WebSocket state
	socket     *phx.Socket
	channel    *phx.Channel
	connected  bool
	phoenixClient phoenix.PhoenixClient
	phoenixConfig phoenix.Config
	
	// UI state
	width      int
	height     int
	activePane Pane
	
	// Components
	fileTree       FileTree
	commandPalette CommandPalette
	modal          Modal
	settingsModal  SettingsModal
	
	// File state
	currentFile string
	modified    bool
	
	// Analysis state
	analyzing    bool
	lastAnalysis string
	
	// Error state
	err error
	
	// Program reference for Phoenix client
	program *tea.Program
}

// FileNode represents a file or directory in the tree
type FileNode struct {
	Name     string
	Path     string
	IsDir    bool
	Children []FileNode
	depth    int
}

// PhoenixConfig holds the configuration for the Phoenix connection
type PhoenixConfig struct {
	URL       string
	APIKey    string
	ChannelID string
}

// NewModel creates a new application model
func NewModel() Model {
	// Initialize editor
	ta := textarea.New()
	ta.Placeholder = "Select a file to start editing..."
	ta.ShowLineNumbers = true
	ta.SetWidth(80)
	ta.SetHeight(20)
	
	// Initialize viewport for output
	vp := viewport.New(40, 20)
	vp.SetContent("Welcome to RubberDuck TUI!\n\nPress Ctrl+H for help.")
	
	// Initialize components
	fileTree := NewFileTree()
	commandPalette := NewCommandPalette()
	modal := NewModal()
	
	// Default settings
	settings := Settings{
		Theme:           "dark",
		ShowLineNumbers: true,
		AutoSave:        false,
		TabSize:         4,
		FontSize:        14,
		ServerURL:       "ws://localhost:5555/socket",
		UsesMockClient:  phoenix.IsRunningInMockMode(),
	}
	settingsModal := NewSettingsModal(settings)
	
	return Model{
		editor:         ta,
		output:         vp,
		statusBar:      "Disconnected | Press Ctrl+C to quit",
		activePane:     FileTreePane,
		fileTree:       fileTree,
		commandPalette: commandPalette,
		modal:          modal,
		settingsModal:  settingsModal,
		files:          []FileNode{}, // Will be populated when connected
	}
}

// Init initializes the model and starts the Phoenix connection
func (m Model) Init() tea.Cmd {
	// Start with a window size request and initiate connection
	return tea.Batch(
		tea.EnterAltScreen,
		startPhoenixConnection(),
	)
}

// startPhoenixConnection creates a command to initiate the Phoenix connection
func startPhoenixConnection() tea.Cmd {
	return func() tea.Msg {
		// Return a message to trigger connection setup
		return InitiateConnectionMsg{}
	}
}