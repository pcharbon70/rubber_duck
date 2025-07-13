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

	// Calculate dimensions dynamically based on visible panels
	contentHeight := m.height - 3 // status bar
	var panes []string
	
	// Calculate widths based on visible panels
	fileTreeWidth := 30
	editorWidth := 50
	availableWidth := m.width
	
	// Build visible panes
	if m.showFileTree {
		fileTree := m.renderFileTree(fileTreeWidth, contentHeight, styles)
		panes = append(panes, fileTree)
		availableWidth -= fileTreeWidth + 2 // borders
	}
	
	if m.showEditor {
		// Editor takes fixed width or remaining space if it's the only other panel
		if !m.showFileTree {
			editorWidth = m.width / 2 // Take half when shown with chat only
		}
		editor := m.renderEditor(editorWidth, contentHeight, styles)
		panes = append(panes, editor)
		availableWidth -= editorWidth + 2 // borders
	}
	
	// Chat takes all remaining space (minimum 40)
	chatWidth := availableWidth
	if chatWidth < 40 {
		chatWidth = 40
	}
	chat := m.renderChat(chatWidth, contentHeight, styles)
	panes = append(panes, chat)
	
	// Combine panes horizontally
	var main string
	if len(panes) == 1 {
		// Only chat visible
		main = panes[0]
	} else {
		// Multiple panes
		main = lipgloss.JoinHorizontal(lipgloss.Top, panes...)
	}

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

// renderChat renders the chat pane
func (m Model) renderChat(width, height int, styles ThemedStyles) string {
	// Update chat size
	m.chat.SetSize(width, height)
	
	// Set theme
	m.chat.SetTheme(m.GetTheme())
	
	// Set focus based on active pane
	if m.activePane == ChatPane {
		m.chat.Focus()
	} else {
		m.chat.Blur()
	}
	
	return m.chat.View()
}

// renderStatusBar renders the status bar
func (m Model) renderStatusBar(styles ThemedStyles) string {
	width := m.width

	// Connection indicator
	connStatus := "⚡"
	if !m.connected {
		connStatus = "⚠️ "
	}
	
	// Panel indicators
	panelStatus := ""
	if m.showFileTree {
		panelStatus += " [F]iles"
	}
	if m.showEditor {
		panelStatus += " [E]ditor"
	}
	if panelStatus == "" {
		panelStatus = " Chat Mode"
	}

	// Build status text
	status := fmt.Sprintf(" %s %s |%s", connStatus, m.statusBar, panelStatus)

	// Pad to full width
	padding := width - lipgloss.Width(status)
	if padding > 0 {
		status += strings.Repeat(" ", padding)
	}

	return styles.statusBarStyle.Render(status)
}