package ui

import (
	"github.com/charmbracelet/bubbles/textarea"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/nshafer/phx"
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
	socket       *phx.Socket
	channel      *phx.Channel
	connected    bool
	phoenixURL   string
	apiKey       string
	
	// Status bar
	statusBar    string
	
	// Modal states
	modal        Modal
	commandPalette CommandPalette
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
	
	return &Model{
		activePane:   ChatPane, // Chat is primary
		width:        80,       // Default width
		height:       24,       // Default height
		chat:         chat,
		fileTree:     NewFileTree(),
		editor:       editor,
		output:       output,
		showFileTree: false,    // Hidden by default
		showEditor:   false,    // Hidden by default
		statusBar:    "Welcome to RubberDuck TUI | Press Ctrl+H for help",
		modal:        NewModal(),
		commandPalette: NewCommandPalette(),
		phoenixURL:   "ws://localhost:4000/socket",
		apiKey:       "test_key",
	}
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
	
	// Update chat size (it takes remaining space)
	m.chat.SetSize(chatWidth-2, contentHeight) // -2 for borders
	
	// Update output viewport size
	m.output.Width = 40
	m.output.Height = contentHeight
}