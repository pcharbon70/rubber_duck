# Bubble Tea and Phoenix Channels Integration Guide for RubberDuck

This guide presents an alternative approach to building RubberDuck using Bubble Tea, a modern TUI framework based on the Elm Architecture. This functional programming approach offers excellent state management and composability for complex terminal applications.

## Recommended Technology Stack with Bubble Tea

The Bubble Tea ecosystem provides a cohesive set of tools for building sophisticated terminal applications with predictable state management and elegant composition patterns.

### Primary Libraries

**TUI Framework: Bubble Tea** (`github.com/charmbracelet/bubbletea`)  
Bubble Tea brings the Elm Architecture to terminal applications, offering a functional approach with immutable state and message-driven updates. With 26,000+ GitHub stars and backing from Charm, it represents the cutting edge of Go TUI development. The framework excels at complex state synchronization scenarios common in coding assistants.

**Component Library: Bubbles** (`github.com/charmbracelet/bubbles`)  
Bubbles provides pre-built components including text inputs, text areas, viewports, and file pickers. These components follow Bubble Tea patterns and can be composed into complex interfaces while maintaining clean separation of concerns.

**Phoenix Channels: nshafer/phx** (`github.com/nshafer/phx`)  
The same Phoenix channels library works excellently with Bubble Tea's message-driven architecture, making WebSocket events first-class citizens in your application's message flow.

**Styling: Lipgloss** (`github.com/charmbracelet/lipgloss`)  
Lipgloss provides a declarative styling system that integrates seamlessly with Bubble Tea, offering advanced layout capabilities and consistent theming across your application.

## The Elm Architecture in Bubble Tea

Bubble Tea's architecture revolves around three core concepts that map perfectly to a WebSocket-driven application:

### Core Architecture Pattern

```go
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
    
    // UI state
    width      int
    height     int
    activePane Pane
}

type Msg interface{}

// WebSocket messages
type ConnectedMsg struct{}
type DisconnectedMsg struct{ Error error }
type ChannelResponseMsg struct {
    Event   string
    Payload json.RawMessage
}

// UI messages
type WindowSizeMsg struct{ Width, Height int }
type FileSelectedMsg struct{ Path string }
type EditorUpdateMsg struct{ Content string }
```

### The Update Function

The update function handles all state transitions, making the application's behavior predictable and testable:

```go
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
    var cmds []tea.Cmd
    
    switch msg := msg.(type) {
    case tea.KeyMsg:
        switch msg.String() {
        case "ctrl+c", "q":
            return m, tea.Quit
        case "tab":
            m.activePane = m.nextPane()
            return m, nil
        case "ctrl+p":
            return m, showCommandPalette()
        }
        
    case ConnectedMsg:
        m.connected = true
        m.statusBar = "Connected to Phoenix"
        cmds = append(cmds, joinChannel(m.socket))
        
    case ChannelResponseMsg:
        switch msg.Event {
        case "analyze_result":
            m.output = m.updateOutput(msg.Payload)
        case "completion":
            cmds = append(cmds, m.handleCompletion(msg.Payload))
        }
        
    case FileSelectedMsg:
        content, cmd := m.loadFile(msg.Path)
        m.editor.SetValue(content)
        cmds = append(cmds, cmd)
    }
    
    // Update child components
    switch m.activePane {
    case EditorPane:
        var cmd tea.Cmd
        m.editor, cmd = m.editor.Update(msg)
        cmds = append(cmds, cmd)
    case OutputPane:
        var cmd tea.Cmd
        m.output, cmd = m.output.Update(msg)
        cmds = append(cmds, cmd)
    }
    
    return m, tea.Batch(cmds...)
}
```

## WebSocket Integration with Bubble Tea

Bubble Tea's command system elegantly handles asynchronous operations like WebSocket communication:

### Phoenix Connection Management

```go
func connectToPhoenix(url string) tea.Cmd {
    return func() tea.Msg {
        endPoint, err := url.Parse(url)
        if err != nil {
            return DisconnectedMsg{Error: err}
        }
        
        socket := phx.NewSocket(endPoint)
        
        socket.OnOpen(func() {
            // This runs in a goroutine, so we need to send a message
            program.Send(ConnectedMsg{})
        })
        
        socket.OnError(func(err error) {
            program.Send(DisconnectedMsg{Error: err})
        })
        
        if err := socket.Connect(); err != nil {
            return DisconnectedMsg{Error: err}
        }
        
        return SocketCreatedMsg{Socket: socket}
    }
}
```

### Channel Communication

Commands handle channel operations, maintaining the functional paradigm:

```go
func joinChannel(socket *phx.Socket) tea.Cmd {
    return func() tea.Msg {
        channel := socket.Channel("cli:lobby", nil)
        
        join, err := channel.Join()
        if err != nil {
            return ErrorMsg{Err: err}
        }
        
        join.Receive("ok", func(response any) {
            program.Send(ChannelJoinedMsg{Channel: channel})
        })
        
        // Set up event listeners
        channel.On("execution_result", func(payload any) {
            program.Send(ChannelResponseMsg{
                Event:   "execution_result",
                Payload: payload.(json.RawMessage),
            })
        })
        
        return ChannelJoiningMsg{}
    }
}
```

### Streaming Updates

Bubble Tea excels at handling streaming data from WebSocket connections:

```go
type StreamStartMsg struct{ ID string }
type StreamDataMsg struct{ 
    ID   string
    Data string 
}
type StreamEndMsg struct{ ID string }

func handleStreamingResponse(channel *phx.Channel) tea.Cmd {
    return func() tea.Msg {
        channel.On("stream:start", func(payload any) {
            data := payload.(map[string]any)
            program.Send(StreamStartMsg{ID: data["id"].(string)})
        })
        
        channel.On("stream:data", func(payload any) {
            data := payload.(map[string]any)
            program.Send(StreamDataMsg{
                ID:   data["id"].(string),
                Data: data["chunk"].(string),
            })
        })
        
        channel.On("stream:end", func(payload any) {
            data := payload.(map[string]any)
            program.Send(StreamEndMsg{ID: data["id"].(string)})
        })
        
        return nil
    }
}
```

## Building Core UI Components

### Layout with Lipgloss

Lipgloss provides powerful layout primitives for complex UIs:

```go
func (m Model) View() string {
    if m.width == 0 || m.height == 0 {
        return "Loading..."
    }
    
    // Define styles
    activeStyle := lipgloss.NewStyle().
        Border(lipgloss.RoundedBorder()).
        BorderForeground(lipgloss.Color("62"))
        
    inactiveStyle := lipgloss.NewStyle().
        Border(lipgloss.NormalBorder()).
        BorderForeground(lipgloss.Color("240"))
    
    // Calculate dimensions
    sidebarWidth := 30
    outputWidth := 40
    editorWidth := m.width - sidebarWidth - outputWidth - 6 // borders
    contentHeight := m.height - 3 // status bar
    
    // Build panes
    fileTreeStyle := inactiveStyle
    if m.activePane == FileTreePane {
        fileTreeStyle = activeStyle
    }
    fileTree := fileTreeStyle.
        Width(sidebarWidth).
        Height(contentHeight).
        Render(m.renderFileTree())
    
    editorStyle := inactiveStyle
    if m.activePane == EditorPane {
        editorStyle = activeStyle
    }
    editor := editorStyle.
        Width(editorWidth).
        Height(contentHeight).
        Render(m.editor.View())
    
    outputStyle := inactiveStyle
    if m.activePane == OutputPane {
        outputStyle = activeStyle
    }
    output := outputStyle.
        Width(outputWidth).
        Height(contentHeight).
        Render(m.output.View())
    
    // Combine horizontally
    main := lipgloss.JoinHorizontal(
        lipgloss.Top,
        fileTree,
        editor,
        output,
    )
    
    // Add status bar
    statusBar := m.renderStatusBar()
    
    return lipgloss.JoinVertical(
        lipgloss.Left,
        main,
        statusBar,
    )
}
```

### File Tree Component

Creating a custom file tree with Bubble Tea patterns:

```go
type FileTree struct {
    root     FileNode
    selected int
    expanded map[string]bool
    items    []FileItem // Flattened for display
}

type FileItem struct {
    node   FileNode
    depth  int
    isLast bool
}

func (ft FileTree) Update(msg tea.Msg) (FileTree, tea.Cmd) {
    switch msg := msg.(type) {
    case tea.KeyMsg:
        switch msg.String() {
        case "up", "k":
            if ft.selected > 0 {
                ft.selected--
            }
        case "down", "j":
            if ft.selected < len(ft.items)-1 {
                ft.selected++
            }
        case "enter", " ":
            item := ft.items[ft.selected]
            if item.node.IsDir {
                ft.expanded[item.node.Path] = !ft.expanded[item.node.Path]
                ft.items = ft.flatten()
            } else {
                return ft, selectFile(item.node.Path)
            }
        }
    }
    return ft, nil
}

func (ft FileTree) View() string {
    var s strings.Builder
    
    for i, item := range ft.items {
        // Indentation
        indent := strings.Repeat("  ", item.depth)
        
        // Tree characters
        prefix := "├─ "
        if item.isLast {
            prefix = "└─ "
        }
        
        // Icon
        icon := "📄"
        if item.node.IsDir {
            if ft.expanded[item.node.Path] {
                icon = "📂"
            } else {
                icon = "📁"
            }
        }
        
        // Selection highlight
        line := fmt.Sprintf("%s%s%s %s", indent, prefix, icon, item.node.Name)
        if i == ft.selected {
            line = lipgloss.NewStyle().
                Foreground(lipgloss.Color("212")).
                Background(lipgloss.Color("236")).
                Render(line)
        }
        
        s.WriteString(line + "\n")
    }
    
    return s.String()
}
```

### Code Editor with Syntax Highlighting

Integrating the Bubbles textarea with syntax highlighting:

```go
type CodeEditor struct {
    textarea    textarea.Model
    language    string
    highlighted string
    showRaw     bool
}

func NewCodeEditor() CodeEditor {
    ta := textarea.New()
    ta.Placeholder = "Start coding..."
    ta.ShowLineNumbers = true
    
    return CodeEditor{
        textarea: ta,
        language: "go",
    }
}

func (ce CodeEditor) Update(msg tea.Msg) (CodeEditor, tea.Cmd) {
    var cmd tea.Cmd
    
    switch msg := msg.(type) {
    case tea.KeyMsg:
        if msg.String() == "ctrl+h" {
            ce.showRaw = !ce.showRaw
            return ce, nil
        }
    }
    
    ce.textarea, cmd = ce.textarea.Update(msg)
    
    // Update syntax highlighting on content change
    if ce.textarea.Value() != "" {
        ce.highlighted = ce.highlightSyntax(ce.textarea.Value())
    }
    
    return ce, cmd
}

func (ce CodeEditor) highlightSyntax(content string) string {
    lexer := lexers.Get(ce.language)
    if lexer == nil {
        lexer = lexers.Fallback
    }
    
    style := styles.Get("monokai")
    formatter := formatters.Get("terminal256")
    
    var buf bytes.Buffer
    iterator, _ := lexer.Tokenise(nil, content)
    formatter.Format(&buf, style, iterator)
    
    return buf.String()
}

func (ce CodeEditor) View() string {
    if ce.showRaw {
        return ce.textarea.View()
    }
    return ce.highlighted
}
```

### Command Palette

A fuzzy-search command palette using Bubble Tea patterns:

```go
type CommandPalette struct {
    textInput textinput.Model
    list      list.Model
    commands  []Command
    filtered  []Command
}

func NewCommandPalette(commands []Command) CommandPalette {
    ti := textinput.New()
    ti.Placeholder = "Type a command..."
    ti.Focus()
    
    items := make([]list.Item, len(commands))
    for i, cmd := range commands {
        items[i] = cmd
    }
    
    l := list.New(items, commandDelegate{}, 0, 0)
    l.Title = "Command Palette"
    
    return CommandPalette{
        textInput: ti,
        list:      l,
        commands:  commands,
        filtered:  commands,
    }
}

func (cp CommandPalette) Update(msg tea.Msg) (CommandPalette, tea.Cmd) {
    var cmds []tea.Cmd
    
    switch msg := msg.(type) {
    case tea.KeyMsg:
        switch msg.String() {
        case "esc":
            return cp, closeCommandPalette()
        case "enter":
            if i, ok := cp.list.SelectedItem().(Command); ok {
                return cp, executeCommand(i)
            }
        }
    }
    
    // Update text input
    var cmd tea.Cmd
    cp.textInput, cmd = cp.textInput.Update(msg)
    cmds = append(cmds, cmd)
    
    // Filter commands based on input
    if cp.textInput.Value() != "" {
        cp.filtered = fuzzyFilter(cp.commands, cp.textInput.Value())
        items := make([]list.Item, len(cp.filtered))
        for i, cmd := range cp.filtered {
            items[i] = cmd
        }
        cp.list.SetItems(items)
    }
    
    // Update list
    cp.list, cmd = cp.list.Update(msg)
    cmds = append(cmds, cmd)
    
    return cp, tea.Batch(cmds...)
}
```

## Advanced Patterns and Best Practices

### State Management for Complex Operations

Bubble Tea's immutable state model excels at managing complex async operations:

```go
type AnalysisState struct {
    InProgress bool
    StartTime  time.Time
    Files      []string
    Results    map[string]AnalysisResult
    Errors     []error
}

func (m Model) startAnalysis(files []string) (Model, tea.Cmd) {
    m.analysis = AnalysisState{
        InProgress: true,
        StartTime:  time.Now(),
        Files:      files,
        Results:    make(map[string]AnalysisResult),
    }
    
    // Create a batch of analysis commands
    cmds := make([]tea.Cmd, len(files))
    for i, file := range files {
        cmds[i] = analyzeFile(m.channel, file)
    }
    
    return m, tea.Batch(cmds...)
}

func analyzeFile(channel *phx.Channel, path string) tea.Cmd {
    return func() tea.Msg {
        push := channel.Push("analyze", map[string]any{
            "path": path,
        })
        
        result := make(chan AnalysisResult)
        
        push.Receive("ok", func(payload any) {
            result <- parseAnalysisResult(payload)
        })
        
        push.Receive("error", func(payload any) {
            result <- AnalysisResult{
                Path:  path,
                Error: fmt.Errorf("analysis failed: %v", payload),
            }
        })
        
        return FileAnalyzedMsg{
            Path:   path,
            Result: <-result,
        }
    }
}
```

### Performance Optimization with Bubble Tea

Bubble Tea's virtual DOM-like rendering optimizes performance automatically, but you can further optimize:

```go
type RenderCache struct {
    fileTree     string
    fileTreeHash string
    outputPane   string
    outputHash   string
}

func (m Model) View() string {
    // Only re-render changed components
    fileTreeHash := hashFileTree(m.files)
    if fileTreeHash != m.cache.fileTreeHash {
        m.cache.fileTree = m.renderFileTree()
        m.cache.fileTreeHash = fileTreeHash
    }
    
    outputHash := hashOutput(m.output)
    if outputHash != m.cache.outputHash {
        m.cache.outputPane = m.output.View()
        m.cache.outputHash = outputHash
    }
    
    // Always render active components
    editor := m.editor.View()
    
    return layoutComponents(m.cache.fileTree, editor, m.cache.outputPane)
}
```

### Testing Bubble Tea Applications

The functional architecture makes testing straightforward:

```go
func TestAnalysisWorkflow(t *testing.T) {
    // Create initial model
    m := NewModel()
    
    // Simulate file selection
    m, cmd := m.Update(FileSelectedMsg{Path: "main.go"})
    assert.NotNil(t, cmd)
    
    // Simulate analysis start
    m, cmd = m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("a")})
    assert.True(t, m.analysis.InProgress)
    
    // Simulate analysis result
    m, _ = m.Update(FileAnalyzedMsg{
        Path: "main.go",
        Result: AnalysisResult{
            Issues: []Issue{{Line: 10, Message: "Unused variable"}},
        },
    })
    
    assert.Len(t, m.analysis.Results, 1)
    assert.False(t, m.analysis.InProgress)
}
```

### Error Handling and Recovery

Bubble Tea's message system provides elegant error handling:

```go
type ErrorMsg struct {
    Err       error
    Component string
    Retry     tea.Cmd
}

func (m Model) handleError(err ErrorMsg) (Model, tea.Cmd) {
    m.errors = append(m.errors, err)
    
    // Update UI to show error
    m.statusBar = lipgloss.NewStyle().
        Foreground(lipgloss.Color("196")).
        Render(fmt.Sprintf("Error in %s: %v", err.Component, err.Err))
    
    // Automatic retry for transient errors
    if err.Retry != nil && isTransient(err.Err) {
        return m, tea.Tick(5*time.Second, func(t time.Time) tea.Msg {
            return RetryMsg{Cmd: err.Retry}
        })
    }
    
    return m, nil
}
```

## Bubble Tea vs tview: When to Choose What

**Choose Bubble Tea when:**
- You prefer functional programming patterns
- Complex state management is a priority
- You want fine-grained control over rendering
- Testing is a critical requirement
- You're building a modern, aesthetically-focused TUI

**Choose tview when:**
- You need rapid prototyping
- Built-in widgets match your requirements
- Team is more familiar with imperative programming
- You want a more traditional TUI look and feel

## Production Deployment Considerations

### Binary Size Optimization

Bubble Tea applications tend to have smaller binaries:

```bash
# Build with optimizations
go build -ldflags="-s -w" -o rubber_duck_tui

# Further reduce with UPX if needed
upx --best rubber_duck_tui
```

### Cross-Platform Compatibility

Bubble Tea handles platform differences elegantly:

```go
func adaptToTerminal() tea.Cmd {
    return func() tea.Msg {
        // Detect terminal capabilities
        hasColor := lipgloss.HasDarkBackground()
        termProgram := os.Getenv("TERM_PROGRAM")
        
        return TerminalInfoMsg{
            HasTrueColor: lipgloss.ColorProfile() == termProfileTrueColor,
            HasDarkBg:    hasColor,
            Program:      termProgram,
        }
    }
}
```

## Conclusion

Bubble Tea offers a modern, functional approach to building terminal user interfaces that integrates beautifully with Phoenix channels. Its message-driven architecture naturally aligns with WebSocket events, while the Elm Architecture provides predictable state management for complex applications.

The framework's emphasis on composition and immutability leads to more maintainable code, especially as your application grows. Combined with the Charm ecosystem (Bubbles, Lipgloss, Glamour), you have all the tools needed to create a sophisticated, modern terminal-based coding assistant.

While the initial learning curve is steeper than tview, the benefits in terms of testability, state management, and long-term maintainability make Bubble Tea an excellent choice for RubberDuck's TUI implementation.
