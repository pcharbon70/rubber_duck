package ui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

// ThemedStyles contains all UI styles based on the current theme
type ThemedStyles struct {
	activeStyle       lipgloss.Style
	inactiveStyle     lipgloss.Style
	statusBarStyle    lipgloss.Style
	selectedFileStyle lipgloss.Style
	dirStyle          lipgloss.Style
	fileStyle         lipgloss.Style
}

// getThemedStyles returns styles based on current theme
func (m Model) getThemedStyles() ThemedStyles {
	theme := m.GetTheme()
	
	return ThemedStyles{
		activeStyle: lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(theme.Selection),
		
		inactiveStyle: lipgloss.NewStyle().
			Border(lipgloss.NormalBorder()).
			BorderForeground(theme.Border),
		
		statusBarStyle: lipgloss.NewStyle().
			Foreground(theme.StatusBarText).
			Background(theme.StatusBar),
		
		selectedFileStyle: lipgloss.NewStyle().
			Foreground(theme.TreeSelected).
			Background(theme.Selection),
		
		dirStyle: lipgloss.NewStyle().
			Foreground(theme.TreeDirectory),
		
		fileStyle: lipgloss.NewStyle().
			Foreground(theme.TreeFile),
	}
}

// View renders the entire UI
func (m Model) View() string {
	if m.width == 0 || m.height == 0 {
		return "Loading..."
	}

	// Start performance monitoring
	if m.performanceMonitor != nil {
		m.performanceMonitor.StartRender()
		defer m.performanceMonitor.EndRender()
	}

	// Get themed styles
	styles := m.getThemedStyles()

	// Calculate dimensions
	sidebarWidth := 30
	outputWidth := 40
	editorWidth := m.width - sidebarWidth - outputWidth - 6 // borders
	contentHeight := m.height - 3                            // status bar

	// Build panes
	fileTree := m.renderFileTree(sidebarWidth, contentHeight, styles)
	editor := m.renderEditor(editorWidth, contentHeight, styles)
	output := m.renderOutput(outputWidth, contentHeight, styles)

	// Combine horizontally
	main := lipgloss.JoinHorizontal(
		lipgloss.Top,
		fileTree,
		editor,
		output,
	)

	// Add status bar
	statusBar := m.renderStatusBar(styles)

	// Combine main UI
	ui := lipgloss.JoinVertical(
		lipgloss.Left,
		main,
		statusBar,
	)

	// Overlay command palette if visible
	if m.commandPalette.IsVisible() {
		return m.commandPalette.View()
	}
	
	// Overlay modal if visible
	if m.modal.IsVisible() {
		return m.modal.View()
	}
	
	// Overlay settings modal if visible
	if m.settingsModal.IsVisible() {
		return m.settingsModal.View()
	}

	return ui
}

// renderFileTree renders the file tree pane
func (m Model) renderFileTree(width, height int, styles ThemedStyles) string {
	style := styles.inactiveStyle
	if m.activePane == FileTreePane {
		style = styles.activeStyle
	}

	content := m.buildFileTreeContent()

	return style.
		Width(width).
		Height(height).
		Render(content)
}

// buildFileTreeContent builds the file tree content
func (m Model) buildFileTreeContent() string {
	// Update file tree size
	m.fileTree.width = 28  // Account for borders
	m.fileTree.height = m.height - 5  // Account for borders and status
	
	content := m.fileTree.View()
	if content == "" || content == "No files loaded" {
		return " 📁 RubberDuck Project\n ──────────────────────\n\n No files loaded\n\n Press Ctrl+O to open\n a project"
	}
	
	return " 📁 RubberDuck Project\n ──────────────────────\n" + content
}

// renderEditor renders the editor pane
func (m Model) renderEditor(width, height int, styles ThemedStyles) string {
	style := styles.inactiveStyle
	if m.activePane == EditorPane {
		style = styles.activeStyle
	}

	// Add title to editor
	title := " Editor"
	if m.currentFile != "" {
		title = " Editor - " + m.currentFile
	}

	// Get editor content and apply syntax highlighting
	editorContent := m.editor.Value()
	if m.currentFile != "" && editorContent != "" && m.settings.UseSyntaxHighlighting {
		language := DetectLanguageFromExtension(m.currentFile)
		highlighter := m.CreateSyntaxHighlighter()
		editorContent = highlighter.HighlightCode(editorContent, language)
	} else {
		editorContent = m.editor.View()
	}

	return style.
		Width(width).
		Height(height).
		Render(title + "\n" + editorContent)
}

// renderOutput renders the output pane
func (m Model) renderOutput(width, height int, styles ThemedStyles) string {
	style := styles.inactiveStyle
	if m.activePane == OutputPane {
		style = styles.activeStyle
	}

	title := " Output"
	if m.analyzing {
		title = " Output (Analyzing...)"
	}

	outputView := m.output.View()

	return style.
		Width(width).
		Height(height).
		Render(title + "\n" + outputView)
}

// renderStatusBar renders the status bar
func (m Model) renderStatusBar(styles ThemedStyles) string {
	width := m.width

	// Connection indicator
	connStatus := "⚡"
	if !m.connected {
		connStatus = "⚠️ "
	}

	// Build status text
	status := fmt.Sprintf(" %s %s", connStatus, m.statusBar)

	// Pad to full width
	padding := width - lipgloss.Width(status)
	if padding > 0 {
		status += strings.Repeat(" ", padding)
	}

	return styles.statusBarStyle.Render(status)
}