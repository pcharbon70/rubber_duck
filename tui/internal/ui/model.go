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
	ChatPane Pane = iota  // Chat is now the primary pane
	FileTreePane
	EditorPane
	OutputPane  // Deprecated - output now shows in chat
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
	chat           *Chat
	fileTree       FileTree
	commandPalette CommandPalette
	modal          Modal
	settingsModal  SettingsModal
	themeManager   *ThemeManager
	
	// Panel visibility
	showFileTree   bool
	showEditor     bool
	
	// Settings
	settings       Settings
	
	// Performance components
	viewCache          *ViewCache
	performanceMonitor *PerformanceMonitor
	saveDebouncer      *Debouncer
	
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
	
	// Initialize viewport for output (deprecated, kept for compatibility)
	vp := viewport.New(40, 20)
	vp.SetContent("")
	
	// Initialize components
	chat := NewChat()
	fileTree := NewFileTree()
	commandPalette := NewCommandPalette()
	modal := NewModal()
	themeManager := NewThemeManager()
	
	// Initialize performance components
	viewCache := NewViewCache()
	performanceMonitor := NewPerformanceMonitor(100) // Keep 100 samples
	saveDebouncer := NewDebouncer(500 * time.Millisecond) // 500ms debounce
	
	// Default settings
	settings := Settings{
		Theme:           "dark",
		ShowLineNumbers: true,
		AutoSave:        false,
		TabSize:         4,
		FontSize:        14,
		ServerURL:       "ws://localhost:5555/socket",
		UsesMockClient:  phoenix.IsRunningInMockMode(),
		
		// Syntax highlighting defaults
		UseSyntaxHighlighting: true,
		UseChromaHighlighting: true,
		ChromaStyle:          "monokai",
		FallbackToCustom:     true,
	}
	settingsModal := NewSettingsModal(settings)
	
	return Model{
		editor:             ta,
		output:             vp,
		statusBar:          "Disconnected | Press Ctrl+C to quit | Ctrl+F: Toggle Files | Ctrl+E: Toggle Editor",
		activePane:         ChatPane,  // Start with chat focused
		chat:               chat,
		fileTree:           fileTree,
		commandPalette:     commandPalette,
		modal:              modal,
		settingsModal:      settingsModal,
		themeManager:       themeManager,
		settings:           settings,
		viewCache:          viewCache,
		performanceMonitor: performanceMonitor,
		saveDebouncer:      saveDebouncer,
		files:              []FileNode{}, // Will be populated when connected
		showFileTree:       false,  // Start with panels hidden
		showEditor:         false,
	}
}

// GetTheme returns the current theme
func (m Model) GetTheme() *Theme {
	return m.themeManager.GetTheme()
}

// SetTheme changes the current theme
func (m *Model) SetTheme(themeName string) bool {
	return m.themeManager.SetTheme(themeName)
}

// GetAvailableThemes returns all available theme names
func (m Model) GetAvailableThemes() []string {
	return m.themeManager.GetThemeNames()
}

// UpdateSettings updates the model settings and applies them
func (m *Model) UpdateSettings(newSettings Settings) {
	m.settings = newSettings
	
	// Apply theme if changed
	if m.themeManager.GetCurrentThemeName() != newSettings.Theme {
		m.SetTheme(newSettings.Theme)
	}
}

// GetSettings returns the current settings
func (m Model) GetSettings() Settings {
	return m.settings
}

// CreateSyntaxHighlighter creates a syntax highlighter configured with current settings
func (m Model) CreateSyntaxHighlighter() *SyntaxHighlighter {
	highlighter := NewSyntaxHighlighter(m.GetTheme())
	
	// Apply settings
	highlighter.SetChromaEnabled(m.settings.UseChromaHighlighting)
	highlighter.SetChromaStyle(m.settings.ChromaStyle)
	highlighter.SetFallbackEnabled(m.settings.FallbackToCustom)
	
	return highlighter
}

// triggerDebouncedSave triggers a debounced auto-save operation
func (m Model) triggerDebouncedSave() {
	if m.saveDebouncer != nil && m.currentFile != "" {
		m.saveDebouncer.Debounce(func() {
			// Auto-save logic would go here
			// For now, just update status to show file is being saved
			if prog := GetProgram(); prog != nil {
				prog.Send(AutoSaveMsg{File: m.currentFile})
			}
		})
	}
}

// GetPerformanceStats returns current performance statistics
func (m Model) GetPerformanceStats() map[string]interface{} {
	if m.performanceMonitor != nil {
		return m.performanceMonitor.GetStats()
	}
	return nil
}

// ClearViewCache clears the view cache
func (m *Model) ClearViewCache() {
	if m.viewCache != nil {
		m.viewCache.Clear()
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