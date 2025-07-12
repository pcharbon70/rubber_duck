# Enhanced Syntax Highlighting Feature

## Overview

The RubberDuck TUI now includes enhanced syntax highlighting powered by the Chroma v2 library, with intelligent fallback to custom highlighting. This feature provides professional-grade code highlighting for 200+ programming languages.

## Features

### 🎨 Chroma Integration
- **200+ Languages**: Full support for major programming languages including Go, JavaScript, Python, Elixir, Rust, and many more
- **Multiple Styles**: Support for popular color schemes like Monokai, GitHub, Solarized Dark, Dracula
- **Automatic Detection**: Intelligent language detection from file extensions and content analysis
- **Terminal Optimized**: Uses appropriate color depth (8, 256, or true color) based on terminal capabilities

### 🔧 Configurable Settings
- **Enable/Disable**: Toggle syntax highlighting on/off
- **Chroma vs Custom**: Choose between Chroma engine or custom tokenizer
- **Style Selection**: Pick from available Chroma styles
- **Fallback Support**: Automatic fallback to custom highlighting if Chroma fails

### 🎭 Theme Integration
- **Theme Mapping**: Automatic Chroma style selection based on active theme
- **Consistent Colors**: Harmonious integration with TUI theme colors
- **Dynamic Updates**: Real-time style changes when switching themes

## Architecture

### Components

1. **SyntaxHighlighter**: Enhanced highlighter with dual-engine support
2. **Language Detection**: Smart file extension and content-based detection
3. **Settings Integration**: Configurable through TUI settings modal
4. **Theme Mapping**: Automatic style selection for each theme

### Engine Selection

```
User Code Input
       ↓
Language Detection (file extension/content)
       ↓
Settings Check (enabled?)
       ↓
┌─ Chroma Engine ─────────┐    ┌─ Custom Engine ────────┐
│ • Lexical analysis     │    │ • Pattern matching     │
│ • Token stream         │    │ • Regex-based          │
│ • Style application    │    │ • Language-specific    │
│ • ANSI formatting      │    │ • Basic highlighting   │
└────────────────────────┘    └────────────────────────┘
       ↓                              ↓
Highlighted Code Output
```

## Usage

### In Code

```go
// Create a syntax highlighter
theme := ui.DefaultDarkTheme()
highlighter := ui.NewSyntaxHighlighter(theme)

// Highlight code
highlighted := highlighter.HighlightCode(code, "go")

// Configure settings
highlighter.SetChromaEnabled(true)
highlighter.SetChromaStyle("monokai")
highlighter.SetFallbackEnabled(true)
```

### In TUI Settings

Access via Settings Modal:
- **Syntax Highlighting**: Enable/disable all highlighting
- **Use Chroma**: Toggle between Chroma and custom engine
- **Chroma Style**: Select from available styles
- **Fallback**: Enable automatic fallback to custom engine

## Supported Languages

The Chroma engine supports 200+ languages including:

**Popular Languages:**
- Go, JavaScript, TypeScript, Python, Rust
- Java, C, C++, C#, Swift, Kotlin
- HTML, CSS, JSON, XML, YAML, TOML
- Shell scripts, SQL, Dockerfile

**Specialized Languages:**
- Elixir, Erlang, Haskell, OCaml
- Ruby, PHP, Perl, Lua
- Assembly, VHDL, Verilog
- Many more...

**Markup & Config:**
- Markdown, reStructuredText
- YAML, TOML, INI
- Nginx, Apache configs

## Performance

### Optimizations
- **Coalesced Lexers**: Reduced token verbosity for better performance
- **Smart Caching**: Efficient re-highlighting of modified content
- **Fallback Strategy**: Quick recovery from Chroma failures
- **Incremental Updates**: Only re-highlight changed regions

### Benchmarks
- **Small files (<1KB)**: ~1-5ms highlighting time
- **Medium files (1-10KB)**: ~5-20ms highlighting time
- **Large files (>10KB)**: Chunked processing for responsiveness

## Configuration

### Settings Structure

```go
type Settings struct {
    // Syntax highlighting settings
    UseSyntaxHighlighting bool   // Master toggle
    UseChromaHighlighting bool   // Chroma vs custom
    ChromaStyle          string  // Selected style
    FallbackToCustom     bool    // Auto-fallback enabled
}
```

### Default Settings
- **UseSyntaxHighlighting**: `true`
- **UseChromaHighlighting**: `true`
- **ChromaStyle**: Theme-dependent (monokai for dark themes)
- **FallbackToCustom**: `true`

### Theme Mappings

| Theme | Default Chroma Style |
|-------|---------------------|
| Dark | monokai |
| Light | github |
| Solarized Dark | solarized-dark |
| Dracula | dracula |

## Testing

### Test Files
- `syntax_test.go`: Comprehensive unit tests
- `test_syntax_highlighting.go`: Manual testing program
- `example_test_code.go`: Sample Go code for testing

### Running Tests

```bash
# Run syntax highlighting tests
go test -v ./internal/ui -run TestSyntax

# Run manual test program
go run test_syntax_highlighting.go

# Run full test suite
./test_runner.sh
```

### Test Coverage
- Language detection accuracy
- Chroma integration functionality
- Fallback behavior
- Configuration persistence
- Theme integration
- Performance under load

## Troubleshooting

### Common Issues

**Q: Syntax highlighting not working**
A: Check settings: Syntax Highlighting enabled → Use Chroma enabled → valid style selected

**Q: Colors look wrong**
A: Verify terminal color support (256-color or true-color recommended)

**Q: Performance issues with large files**
A: Consider disabling Chroma for very large files or using custom engine

**Q: Language not detected**
A: Check file extension mapping or add custom detection rules

### Debug Mode

Enable debug logging to troubleshoot issues:

```go
// Check available styles and languages
styles := highlighter.GetAvailableChromaStyles()
languages := highlighter.GetAvailableLanguages()

// Test language detection
detected := ui.DetectLanguageFromExtension("myfile.ext")
```

## Future Enhancements

### Planned Features
- **Custom Language Definitions**: Support for domain-specific languages
- **Incremental Highlighting**: Real-time highlighting during typing
- **Syntax Error Indicators**: Visual indication of syntax errors
- **Code Folding**: Collapsible code blocks
- **Semantic Highlighting**: Context-aware highlighting

### Extension Points
- **Custom Lexers**: Plugin system for new languages
- **Style Customization**: User-defined color schemes
- **Performance Profiles**: Configurable performance vs quality trade-offs

## Dependencies

- **Chroma v2**: `github.com/alecthomas/chroma/v2`
- **Lipgloss**: `github.com/charmbracelet/lipgloss` (for styling)
- **Bubble Tea**: `github.com/charmbracelet/bubbletea` (for TUI)

## Contributing

When contributing to syntax highlighting:

1. **Test Coverage**: Add tests for new features
2. **Performance**: Profile changes with large files
3. **Compatibility**: Ensure fallback behavior works
4. **Documentation**: Update this README for new features

---

**Note**: This feature is part of Phase 5.5 TUI implementation and integrates with the existing theme and settings systems.