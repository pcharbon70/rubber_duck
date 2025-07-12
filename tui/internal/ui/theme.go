package ui

import (
	"github.com/charmbracelet/lipgloss"
)

// Theme represents a color scheme for the TUI
type Theme struct {
	Name        string
	Description string
	
	// Base colors
	Background    lipgloss.Color
	Foreground    lipgloss.Color
	Border        lipgloss.Color
	Cursor        lipgloss.Color
	
	// UI element colors
	StatusBar     lipgloss.Color
	StatusBarText lipgloss.Color
	Selection     lipgloss.Color
	SelectionText lipgloss.Color
	
	// File tree colors
	TreeDirectory lipgloss.Color
	TreeFile      lipgloss.Color
	TreeSelected  lipgloss.Color
	TreeExpanded  lipgloss.Color
	
	// Editor colors
	EditorBg      lipgloss.Color
	EditorFg      lipgloss.Color
	LineNumbers   lipgloss.Color
	CurrentLine   lipgloss.Color
	
	// Syntax highlighting (basic)
	Keyword       lipgloss.Color
	String        lipgloss.Color
	Comment       lipgloss.Color
	Function      lipgloss.Color
	Number        lipgloss.Color
	
	// Output pane colors
	OutputBg      lipgloss.Color
	OutputFg      lipgloss.Color
	OutputError   lipgloss.Color
	OutputWarning lipgloss.Color
	OutputInfo    lipgloss.Color
	OutputSuccess lipgloss.Color
	
	// Modal colors
	ModalBg       lipgloss.Color
	ModalFg       lipgloss.Color
	ModalBorder   lipgloss.Color
	ModalTitle    lipgloss.Color
	ButtonPrimary lipgloss.Color
	ButtonNormal  lipgloss.Color
	
	// Command palette colors
	CommandBg     lipgloss.Color
	CommandFg     lipgloss.Color
	CommandMatch  lipgloss.Color
}

// ThemeManager manages available themes and theme switching
type ThemeManager struct {
	themes       map[string]*Theme
	currentTheme string
}

// NewThemeManager creates a new theme manager with default themes
func NewThemeManager() *ThemeManager {
	tm := &ThemeManager{
		themes:       make(map[string]*Theme),
		currentTheme: "dark",
	}
	
	// Register default themes
	tm.RegisterTheme(DefaultDarkTheme())
	tm.RegisterTheme(DefaultLightTheme())
	tm.RegisterTheme(SolarizedDarkTheme())
	tm.RegisterTheme(DraculaTheme())
	
	return tm
}

// RegisterTheme adds a new theme to the manager
func (tm *ThemeManager) RegisterTheme(theme *Theme) {
	tm.themes[theme.Name] = theme
}

// SetTheme changes the current theme
func (tm *ThemeManager) SetTheme(name string) bool {
	if _, exists := tm.themes[name]; exists {
		tm.currentTheme = name
		return true
	}
	return false
}

// GetTheme returns the current theme
func (tm *ThemeManager) GetTheme() *Theme {
	if theme, exists := tm.themes[tm.currentTheme]; exists {
		return theme
	}
	// Fallback to dark theme
	return DefaultDarkTheme()
}

// GetThemeNames returns all available theme names
func (tm *ThemeManager) GetThemeNames() []string {
	names := make([]string, 0, len(tm.themes))
	for name := range tm.themes {
		names = append(names, name)
	}
	return names
}

// GetCurrentThemeName returns the name of the current theme
func (tm *ThemeManager) GetCurrentThemeName() string {
	return tm.currentTheme
}

// DefaultDarkTheme returns the default dark theme
func DefaultDarkTheme() *Theme {
	return &Theme{
		Name:        "dark",
		Description: "Default dark theme",
		
		// Base colors
		Background:    lipgloss.Color("235"),
		Foreground:    lipgloss.Color("252"),
		Border:        lipgloss.Color("240"),
		Cursor:        lipgloss.Color("212"),
		
		// UI element colors
		StatusBar:     lipgloss.Color("237"),
		StatusBarText: lipgloss.Color("250"),
		Selection:     lipgloss.Color("240"),
		SelectionText: lipgloss.Color("255"),
		
		// File tree colors
		TreeDirectory: lipgloss.Color("33"),
		TreeFile:      lipgloss.Color("252"),
		TreeSelected:  lipgloss.Color("212"),
		TreeExpanded:  lipgloss.Color("214"),
		
		// Editor colors
		EditorBg:      lipgloss.Color("235"),
		EditorFg:      lipgloss.Color("252"),
		LineNumbers:   lipgloss.Color("240"),
		CurrentLine:   lipgloss.Color("237"),
		
		// Syntax highlighting
		Keyword:       lipgloss.Color("212"),
		String:        lipgloss.Color("214"),
		Comment:       lipgloss.Color("242"),
		Function:      lipgloss.Color("141"),
		Number:        lipgloss.Color("175"),
		
		// Output pane colors
		OutputBg:      lipgloss.Color("235"),
		OutputFg:      lipgloss.Color("252"),
		OutputError:   lipgloss.Color("196"),
		OutputWarning: lipgloss.Color("214"),
		OutputInfo:    lipgloss.Color("33"),
		OutputSuccess: lipgloss.Color("40"),
		
		// Modal colors
		ModalBg:       lipgloss.Color("237"),
		ModalFg:       lipgloss.Color("252"),
		ModalBorder:   lipgloss.Color("62"),
		ModalTitle:    lipgloss.Color("212"),
		ButtonPrimary: lipgloss.Color("40"),
		ButtonNormal:  lipgloss.Color("240"),
		
		// Command palette colors
		CommandBg:     lipgloss.Color("237"),
		CommandFg:     lipgloss.Color("252"),
		CommandMatch:  lipgloss.Color("214"),
	}
}

// DefaultLightTheme returns the default light theme
func DefaultLightTheme() *Theme {
	return &Theme{
		Name:        "light",
		Description: "Default light theme",
		
		// Base colors
		Background:    lipgloss.Color("255"),
		Foreground:    lipgloss.Color("235"),
		Border:        lipgloss.Color("250"),
		Cursor:        lipgloss.Color("33"),
		
		// UI element colors
		StatusBar:     lipgloss.Color("250"),
		StatusBarText: lipgloss.Color("235"),
		Selection:     lipgloss.Color("253"),
		SelectionText: lipgloss.Color("235"),
		
		// File tree colors
		TreeDirectory: lipgloss.Color("33"),
		TreeFile:      lipgloss.Color("235"),
		TreeSelected:  lipgloss.Color("39"),
		TreeExpanded:  lipgloss.Color("166"),
		
		// Editor colors
		EditorBg:      lipgloss.Color("255"),
		EditorFg:      lipgloss.Color("235"),
		LineNumbers:   lipgloss.Color("250"),
		CurrentLine:   lipgloss.Color("253"),
		
		// Syntax highlighting
		Keyword:       lipgloss.Color("33"),
		String:        lipgloss.Color("166"),
		Comment:       lipgloss.Color("245"),
		Function:      lipgloss.Color("127"),
		Number:        lipgloss.Color("164"),
		
		// Output pane colors
		OutputBg:      lipgloss.Color("255"),
		OutputFg:      lipgloss.Color("235"),
		OutputError:   lipgloss.Color("196"),
		OutputWarning: lipgloss.Color("166"),
		OutputInfo:    lipgloss.Color("33"),
		OutputSuccess: lipgloss.Color("28"),
		
		// Modal colors
		ModalBg:       lipgloss.Color("253"),
		ModalFg:       lipgloss.Color("235"),
		ModalBorder:   lipgloss.Color("33"),
		ModalTitle:    lipgloss.Color("33"),
		ButtonPrimary: lipgloss.Color("28"),
		ButtonNormal:  lipgloss.Color("250"),
		
		// Command palette colors
		CommandBg:     lipgloss.Color("253"),
		CommandFg:     lipgloss.Color("235"),
		CommandMatch:  lipgloss.Color("166"),
	}
}

// SolarizedDarkTheme returns the Solarized Dark theme
func SolarizedDarkTheme() *Theme {
	return &Theme{
		Name:        "solarized-dark",
		Description: "Solarized Dark color scheme",
		
		// Base colors
		Background:    lipgloss.Color("#002b36"),
		Foreground:    lipgloss.Color("#839496"),
		Border:        lipgloss.Color("#073642"),
		Cursor:        lipgloss.Color("#268bd2"),
		
		// UI element colors
		StatusBar:     lipgloss.Color("#073642"),
		StatusBarText: lipgloss.Color("#93a1a1"),
		Selection:     lipgloss.Color("#073642"),
		SelectionText: lipgloss.Color("#fdf6e3"),
		
		// File tree colors
		TreeDirectory: lipgloss.Color("#268bd2"),
		TreeFile:      lipgloss.Color("#839496"),
		TreeSelected:  lipgloss.Color("#b58900"),
		TreeExpanded:  lipgloss.Color("#cb4b16"),
		
		// Editor colors
		EditorBg:      lipgloss.Color("#002b36"),
		EditorFg:      lipgloss.Color("#839496"),
		LineNumbers:   lipgloss.Color("#586e75"),
		CurrentLine:   lipgloss.Color("#073642"),
		
		// Syntax highlighting
		Keyword:       lipgloss.Color("#859900"),
		String:        lipgloss.Color("#2aa198"),
		Comment:       lipgloss.Color("#586e75"),
		Function:      lipgloss.Color("#268bd2"),
		Number:        lipgloss.Color("#d33682"),
		
		// Output pane colors
		OutputBg:      lipgloss.Color("#002b36"),
		OutputFg:      lipgloss.Color("#839496"),
		OutputError:   lipgloss.Color("#dc322f"),
		OutputWarning: lipgloss.Color("#b58900"),
		OutputInfo:    lipgloss.Color("#268bd2"),
		OutputSuccess: lipgloss.Color("#859900"),
		
		// Modal colors
		ModalBg:       lipgloss.Color("#073642"),
		ModalFg:       lipgloss.Color("#839496"),
		ModalBorder:   lipgloss.Color("#268bd2"),
		ModalTitle:    lipgloss.Color("#b58900"),
		ButtonPrimary: lipgloss.Color("#859900"),
		ButtonNormal:  lipgloss.Color("#073642"),
		
		// Command palette colors
		CommandBg:     lipgloss.Color("#073642"),
		CommandFg:     lipgloss.Color("#839496"),
		CommandMatch:  lipgloss.Color("#b58900"),
	}
}

// DraculaTheme returns the Dracula theme
func DraculaTheme() *Theme {
	return &Theme{
		Name:        "dracula",
		Description: "Dracula color scheme",
		
		// Base colors
		Background:    lipgloss.Color("#282a36"),
		Foreground:    lipgloss.Color("#f8f8f2"),
		Border:        lipgloss.Color("#44475a"),
		Cursor:        lipgloss.Color("#ff79c6"),
		
		// UI element colors
		StatusBar:     lipgloss.Color("#44475a"),
		StatusBarText: lipgloss.Color("#f8f8f2"),
		Selection:     lipgloss.Color("#44475a"),
		SelectionText: lipgloss.Color("#f8f8f2"),
		
		// File tree colors
		TreeDirectory: lipgloss.Color("#bd93f9"),
		TreeFile:      lipgloss.Color("#f8f8f2"),
		TreeSelected:  lipgloss.Color("#ff79c6"),
		TreeExpanded:  lipgloss.Color("#ffb86c"),
		
		// Editor colors
		EditorBg:      lipgloss.Color("#282a36"),
		EditorFg:      lipgloss.Color("#f8f8f2"),
		LineNumbers:   lipgloss.Color("#6272a4"),
		CurrentLine:   lipgloss.Color("#44475a"),
		
		// Syntax highlighting
		Keyword:       lipgloss.Color("#ff79c6"),
		String:        lipgloss.Color("#f1fa8c"),
		Comment:       lipgloss.Color("#6272a4"),
		Function:      lipgloss.Color("#50fa7b"),
		Number:        lipgloss.Color("#bd93f9"),
		
		// Output pane colors
		OutputBg:      lipgloss.Color("#282a36"),
		OutputFg:      lipgloss.Color("#f8f8f2"),
		OutputError:   lipgloss.Color("#ff5555"),
		OutputWarning: lipgloss.Color("#ffb86c"),
		OutputInfo:    lipgloss.Color("#8be9fd"),
		OutputSuccess: lipgloss.Color("#50fa7b"),
		
		// Modal colors
		ModalBg:       lipgloss.Color("#44475a"),
		ModalFg:       lipgloss.Color("#f8f8f2"),
		ModalBorder:   lipgloss.Color("#bd93f9"),
		ModalTitle:    lipgloss.Color("#ff79c6"),
		ButtonPrimary: lipgloss.Color("#50fa7b"),
		ButtonNormal:  lipgloss.Color("#44475a"),
		
		// Command palette colors
		CommandBg:     lipgloss.Color("#44475a"),
		CommandFg:     lipgloss.Color("#f8f8f2"),
		CommandMatch:  lipgloss.Color("#ffb86c"),
	}
}