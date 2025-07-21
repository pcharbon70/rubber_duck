// Monaco Editor hook for Phoenix LiveView
// Handles the lifecycle and bidirectional data sync of Monaco Editor

export const MonacoEditor = {
  mounted() {
    this.editor = null
    this.monaco = null
    this.decorations = []
    this.remoteDecorations = new Map()
    this.language = this.el.dataset.language || 'plaintext'
    this.readOnly = this.el.dataset.readOnly === 'true'
    this.content = this.el.dataset.content || ''
    this.filePath = this.el.dataset.filePath
    this.isUpdating = false
    this.changeTimeout = null
    
    // Parse options
    try {
      this.options = JSON.parse(this.el.dataset.options || '{}')
    } catch (e) {
      this.options = {}
    }
    
    // Load Monaco Editor
    this.loadMonaco()
    
    // Listen for LiveView events
    this.handleEvent("format_document", ({ editor_id }) => {
      if (editor_id === this.el.id && this.editor) {
        this.editor.getAction('editor.action.formatDocument').run()
      }
    })
    
    this.handleEvent("apply_edit", ({ editor_id, edit }) => {
      if (editor_id === this.el.id && this.editor) {
        this.applyEdit(edit)
      }
    })
    
    this.handleEvent("set_decorations", ({ editor_id, decorations }) => {
      if (editor_id === this.el.id && this.editor) {
        this.setDecorations(decorations)
      }
    })
    
    this.handleEvent("update_content", ({ editor_id, content, language }) => {
      if (editor_id === this.el.id && this.editor) {
        this.updateContent(content, language)
      }
    })
    
    this.handleEvent("update_remote_cursor", ({ editor_id, user_id, position, color }) => {
      if (editor_id === this.el.id && this.editor) {
        this.updateRemoteCursor(user_id, position, color)
      }
    })
    
    this.handleEvent("set_read_only", ({ editor_id, read_only }) => {
      if (editor_id === this.el.id && this.editor) {
        this.editor.updateOptions({ readOnly: read_only })
      }
    })
  },
  
  async loadMonaco() {
    // Check if Monaco is already loaded globally
    if (window.monaco) {
      this.monaco = window.monaco
      this.initializeEditor()
      return
    }
    
    // Load Monaco Editor from CDN
    const monacoScript = document.createElement('script')
    monacoScript.src = 'https://cdn.jsdelivr.net/npm/monaco-editor@0.45.0/min/vs/loader.js'
    
    monacoScript.onload = () => {
      require.config({ 
        paths: { 
          'vs': 'https://cdn.jsdelivr.net/npm/monaco-editor@0.45.0/min/vs' 
        }
      })
      
      require(['vs/editor/editor.main'], () => {
        this.monaco = window.monaco
        this.initializeEditor()
      })
    }
    
    document.head.appendChild(monacoScript)
  },
  
  initializeEditor() {
    // Configure Monaco environment
    this.monaco.editor.defineTheme('rubber-duck-dark', {
      base: 'vs-dark',
      inherit: true,
      rules: [
        { token: 'comment', foreground: '6A737D', fontStyle: 'italic' },
        { token: 'keyword', foreground: 'F97583' },
        { token: 'string', foreground: '9ECBFF' }
      ],
      colors: {
        'editor.background': '#111827',
        'editor.foreground': '#E1E4E8',
        'editor.lineHighlightBackground': '#1F2937',
        'editor.selectionBackground': '#3730A3',
        'editorCursor.foreground': '#60A5FA',
        'editorWhitespace.foreground': '#374151'
      }
    })
    
    // Create editor instance
    this.editor = this.monaco.editor.create(this.el, {
      value: this.content,
      language: this.language,
      theme: this.options.theme || 'rubber-duck-dark',
      readOnly: this.readOnly,
      ...this.options,
      // Override some options for better LiveView integration
      automaticLayout: true,
      scrollBeyondLastLine: false
    })
    
    // Set up event handlers
    this.setupEventHandlers()
    
    // Notify LiveView that editor is ready
    this.pushEvent("editor_mounted", {})
    
    // Set up AI-powered features
    this.setupAIFeatures()
  },
  
  setupEventHandlers() {
    // Handle content changes
    this.editor.onDidChangeModelContent((e) => {
      if (this.isUpdating) return
      
      // Clear existing timeout
      if (this.changeTimeout) {
        clearTimeout(this.changeTimeout)
      }
      
      // Debounce changes
      this.changeTimeout = setTimeout(() => {
        const content = this.editor.getValue()
        const changes = e.changes.map(change => ({
          range: {
            startLine: change.range.startLineNumber,
            startColumn: change.range.startColumn,
            endLine: change.range.endLineNumber,
            endColumn: change.range.endColumn
          },
          text: change.text,
          rangeLength: change.rangeLength
        }))
        
        this.pushEvent("content_changed", { content, changes })
      }, 300)
    })
    
    // Handle cursor position changes
    this.editor.onDidChangeCursorPosition((e) => {
      const position = {
        line: e.position.lineNumber,
        column: e.position.column
      }
      
      const selection = this.editor.getSelection()
      const selectionData = {
        startLine: selection.startLineNumber,
        startColumn: selection.startColumn,
        endLine: selection.endLineNumber,
        endColumn: selection.endColumn
      }
      
      this.pushEvent("cursor_changed", { position, selection: selectionData })
    })
    
    // Handle focus
    this.editor.onDidFocusEditorText(() => {
      this.pushEvent("editor_focused", {})
    })
    
    this.editor.onDidBlurEditorText(() => {
      this.pushEvent("editor_blurred", {})
    })
    
    // Add custom keybindings
    this.addCustomKeybindings()
  },
  
  setupAIFeatures() {
    // Register completion provider
    this.monaco.languages.registerCompletionItemProvider(this.language, {
      provideCompletionItems: (model, position, context) => {
        return new Promise((resolve) => {
          // Request completions from LiveView
          this.pushEventTo(this.el, "request_completions", {
            position: {
              line: position.lineNumber,
              column: position.column
            },
            context: {
              triggerKind: context.triggerKind,
              triggerCharacter: context.triggerCharacter
            }
          })
          
          // Listen for completion response
          const handler = this.handleEvent("completions_response", ({ completions }) => {
            const suggestions = completions.map(item => ({
              label: item.label,
              kind: this.monaco.languages.CompletionItemKind[item.kind],
              detail: item.detail,
              insertText: item.insertText,
              insertTextRules: item.insertTextRules
            }))
            
            resolve({ suggestions })
            handler() // Remove handler
          })
          
          // Timeout after 1 second
          setTimeout(() => resolve({ suggestions: [] }), 1000)
        })
      }
    })
    
    // Register hover provider for code explanations
    this.monaco.languages.registerHoverProvider(this.language, {
      provideHover: (model, position) => {
        return new Promise((resolve) => {
          const word = model.getWordAtPosition(position)
          if (!word) {
            resolve(null)
            return
          }
          
          // Request explanation from LiveView
          this.pushEventTo(this.el, "request_explanation", {
            word: word.word,
            position: {
              line: position.lineNumber,
              column: position.column
            }
          })
          
          // Listen for explanation response
          const handler = this.handleEvent("explanation_response", ({ explanation }) => {
            resolve({
              contents: [
                { value: explanation, isTrusted: true }
              ]
            })
            handler() // Remove handler
          })
          
          // Timeout after 1 second
          setTimeout(() => resolve(null), 1000)
        })
      }
    })
  },
  
  addCustomKeybindings() {
    // Format document
    this.editor.addCommand(
      this.monaco.KeyMod.Alt | this.monaco.KeyMod.Shift | this.monaco.KeyCode.KeyF,
      () => {
        this.pushEvent("format_document", {})
      }
    )
    
    // Save
    this.editor.addCommand(
      this.monaco.KeyMod.CtrlCmd | this.monaco.KeyCode.KeyS,
      () => {
        this.pushEvent("save_file", {})
      }
    )
    
    // Toggle AI assistant
    this.editor.addCommand(
      this.monaco.KeyMod.CtrlCmd | this.monaco.KeyCode.KeyI,
      () => {
        this.pushEvent("toggle_ai_assistant", {})
      }
    )
  },
  
  updateContent(content, language) {
    this.isUpdating = true
    
    if (language && language !== this.language) {
      this.language = language
      this.monaco.editor.setModelLanguage(this.editor.getModel(), language)
    }
    
    // Save cursor position
    const position = this.editor.getPosition()
    
    // Update content
    this.editor.setValue(content)
    
    // Restore cursor position
    if (position) {
      this.editor.setPosition(position)
    }
    
    this.isUpdating = false
  },
  
  applyEdit(edit) {
    const model = this.editor.getModel()
    const range = new this.monaco.Range(
      edit.range.startLine,
      edit.range.startColumn || 1,
      edit.range.endLine,
      edit.range.endColumn || model.getLineMaxColumn(edit.range.endLine)
    )
    
    const operation = {
      range: range,
      text: edit.text,
      forceMoveMarkers: true
    }
    
    this.editor.executeEdits('ai-suggestion', [operation])
  },
  
  setDecorations(decorations) {
    // Clear existing decorations
    this.decorations = this.editor.deltaDecorations(this.decorations, [])
    
    // Apply new decorations
    const newDecorations = decorations.map(dec => ({
      range: new this.monaco.Range(
        dec.range.startLine,
        dec.range.startColumn,
        dec.range.endLine,
        dec.range.endColumn
      ),
      options: {
        className: dec.className,
        hoverMessage: dec.hoverMessage,
        inlineClassName: dec.inlineClassName,
        isWholeLine: dec.isWholeLine
      }
    }))
    
    this.decorations = this.editor.deltaDecorations([], newDecorations)
  },
  
  updateRemoteCursor(userId, position, color) {
    // Get existing decorations for this user
    const existingDecorations = this.remoteDecorations.get(userId) || []
    
    // Clear existing decorations
    this.editor.deltaDecorations(existingDecorations, [])
    
    if (!position) {
      // User disconnected or left the file
      this.remoteDecorations.delete(userId)
      return
    }
    
    // Create new cursor decoration
    const cursorDecoration = {
      range: new this.monaco.Range(
        position.line,
        position.column,
        position.line,
        position.column
      ),
      options: {
        className: 'remote-cursor',
        beforeContentClassName: 'remote-cursor-flag',
        hoverMessage: { value: `User ${userId}` },
        stickiness: this.monaco.editor.TrackedRangeStickiness.NeverGrowsWhenTypingAtEdges,
        zIndex: 1000
      }
    }
    
    // Apply CSS for the cursor color
    const styleId = `remote-cursor-${userId}`
    let style = document.getElementById(styleId)
    if (!style) {
      style = document.createElement('style')
      style.id = styleId
      document.head.appendChild(style)
    }
    
    style.textContent = `
      .remote-cursor-${userId}::before {
        content: '';
        position: absolute;
        width: 2px;
        height: 1.2em;
        background-color: ${color};
      }
      .remote-cursor-flag-${userId}::before {
        content: '${userId.substring(0, 2).toUpperCase()}';
        position: absolute;
        top: -1.2em;
        padding: 2px 4px;
        background-color: ${color};
        color: white;
        font-size: 0.8em;
        border-radius: 2px;
      }
    `
    
    // Apply decorations
    const newDecorations = this.editor.deltaDecorations([], [cursorDecoration])
    this.remoteDecorations.set(userId, newDecorations)
  },
  
  destroyed() {
    // Clean up
    if (this.editor) {
      this.editor.dispose()
    }
    
    // Clear all remote cursor styles
    this.remoteDecorations.forEach((_, userId) => {
      const style = document.getElementById(`remote-cursor-${userId}`)
      if (style) {
        style.remove()
      }
    })
    
    if (this.changeTimeout) {
      clearTimeout(this.changeTimeout)
    }
  }
}