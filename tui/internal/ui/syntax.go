package ui

import (
	"strings"
	"unicode"

	"github.com/charmbracelet/lipgloss"
)

// SyntaxHighlighter provides basic syntax highlighting for code
type SyntaxHighlighter struct {
	theme *Theme
}

// NewSyntaxHighlighter creates a new syntax highlighter with the given theme
func NewSyntaxHighlighter(theme *Theme) *SyntaxHighlighter {
	return &SyntaxHighlighter{
		theme: theme,
	}
}

// HighlightCode applies syntax highlighting to code based on language
func (sh *SyntaxHighlighter) HighlightCode(code, language string) string {
	if sh.theme == nil {
		return code
	}

	switch strings.ToLower(language) {
	case "go":
		return sh.highlightGo(code)
	case "javascript", "js":
		return sh.highlightJavaScript(code)
	case "python", "py":
		return sh.highlightPython(code)
	case "elixir", "ex":
		return sh.highlightElixir(code)
	case "markdown", "md":
		return sh.highlightMarkdown(code)
	default:
		return sh.highlightGeneric(code)
	}
}

// highlightGo provides Go-specific syntax highlighting
func (sh *SyntaxHighlighter) highlightGo(code string) string {
	keywords := []string{
		"package", "import", "func", "var", "const", "type", "struct", "interface",
		"if", "else", "for", "range", "switch", "case", "default", "select",
		"go", "defer", "return", "break", "continue", "fallthrough",
		"map", "chan", "make", "new", "len", "cap", "append", "copy", "delete",
		"panic", "recover", "nil", "true", "false", "iota",
	}

	types := []string{
		"int", "int8", "int16", "int32", "int64",
		"uint", "uint8", "uint16", "uint32", "uint64", "uintptr",
		"float32", "float64", "complex64", "complex128",
		"bool", "byte", "rune", "string", "error",
	}

	return sh.highlightWithRules(code, keywords, types)
}

// highlightJavaScript provides JavaScript-specific syntax highlighting
func (sh *SyntaxHighlighter) highlightJavaScript(code string) string {
	keywords := []string{
		"function", "var", "let", "const", "if", "else", "for", "while", "do",
		"switch", "case", "default", "break", "continue", "return",
		"try", "catch", "finally", "throw", "new", "delete", "typeof", "instanceof",
		"in", "of", "this", "super", "class", "extends", "import", "export",
		"async", "await", "yield", "true", "false", "null", "undefined",
	}

	types := []string{
		"Object", "Array", "String", "Number", "Boolean", "Date", "RegExp",
		"Function", "Promise", "Set", "Map", "Symbol",
	}

	return sh.highlightWithRules(code, keywords, types)
}

// highlightPython provides Python-specific syntax highlighting
func (sh *SyntaxHighlighter) highlightPython(code string) string {
	keywords := []string{
		"def", "class", "if", "elif", "else", "for", "while", "break", "continue",
		"return", "yield", "try", "except", "finally", "raise", "with", "as",
		"import", "from", "global", "nonlocal", "lambda", "pass", "del",
		"and", "or", "not", "in", "is", "True", "False", "None",
	}

	types := []string{
		"int", "float", "str", "bool", "list", "dict", "tuple", "set",
		"bytes", "bytearray", "memoryview", "range", "enumerate", "zip",
	}

	return sh.highlightWithRules(code, keywords, types)
}

// highlightElixir provides Elixir-specific syntax highlighting
func (sh *SyntaxHighlighter) highlightElixir(code string) string {
	keywords := []string{
		"def", "defp", "defmodule", "defstruct", "defprotocol", "defimpl",
		"if", "unless", "cond", "case", "with", "for", "try", "catch", "rescue", "after",
		"do", "end", "when", "and", "or", "not", "in", "fn", "receive", "send",
		"true", "false", "nil", "self", "super", "quote", "unquote",
	}

	types := []string{
		"atom", "binary", "bitstring", "boolean", "float", "integer",
		"list", "map", "pid", "port", "reference", "tuple", "function",
	}

	return sh.highlightWithRules(code, keywords, types)
}

// highlightMarkdown provides basic markdown syntax highlighting
func (sh *SyntaxHighlighter) highlightMarkdown(code string) string {
	lines := strings.Split(code, "\n")
	highlighted := make([]string, len(lines))

	for i, line := range lines {
		highlighted[i] = sh.highlightMarkdownLine(line)
	}

	return strings.Join(highlighted, "\n")
}

// highlightMarkdownLine highlights a single markdown line
func (sh *SyntaxHighlighter) highlightMarkdownLine(line string) string {
	// Headers
	if strings.HasPrefix(line, "#") {
		return lipgloss.NewStyle().
			Foreground(sh.theme.Function).
			Bold(true).
			Render(line)
	}

	// Code blocks
	if strings.HasPrefix(line, "```") || strings.HasPrefix(line, "    ") {
		return lipgloss.NewStyle().
			Foreground(sh.theme.String).
			Background(sh.theme.CurrentLine).
			Render(line)
	}

	// Bold text
	line = sh.replaceMarkdownPatterns(line, "**", lipgloss.NewStyle().Bold(true))
	line = sh.replaceMarkdownPatterns(line, "__", lipgloss.NewStyle().Bold(true))

	// Italic text
	line = sh.replaceMarkdownPatterns(line, "*", lipgloss.NewStyle().Italic(true))
	line = sh.replaceMarkdownPatterns(line, "_", lipgloss.NewStyle().Italic(true))

	// Inline code
	line = sh.replaceMarkdownPatterns(line, "`", lipgloss.NewStyle().
		Foreground(sh.theme.String).
		Background(sh.theme.CurrentLine))

	return line
}

// replaceMarkdownPatterns replaces markdown patterns with styled versions
func (sh *SyntaxHighlighter) replaceMarkdownPatterns(text, pattern string, style lipgloss.Style) string {
	parts := strings.Split(text, pattern)
	if len(parts) < 3 {
		return text
	}

	result := parts[0]
	for i := 1; i < len(parts); i += 2 {
		if i+1 < len(parts) {
			result += style.Render(parts[i]) + parts[i+1]
		} else {
			result += pattern + parts[i]
		}
	}

	return result
}

// highlightGeneric provides basic highlighting for unknown languages
func (sh *SyntaxHighlighter) highlightGeneric(code string) string {
	// Basic highlighting for strings, comments, and numbers
	lines := strings.Split(code, "\n")
	highlighted := make([]string, len(lines))

	for i, line := range lines {
		highlighted[i] = sh.highlightGenericLine(line)
	}

	return strings.Join(highlighted, "\n")
}

// highlightGenericLine highlights a single line with generic rules
func (sh *SyntaxHighlighter) highlightGenericLine(line string) string {
	// Comments (// and #)
	if strings.Contains(line, "//") {
		commentIdx := strings.Index(line, "//")
		beforeComment := line[:commentIdx]
		comment := line[commentIdx:]
		return beforeComment + lipgloss.NewStyle().
			Foreground(sh.theme.Comment).
			Render(comment)
	}

	if strings.Contains(line, "#") {
		commentIdx := strings.Index(line, "#")
		beforeComment := line[:commentIdx]
		comment := line[commentIdx:]
		return beforeComment + lipgloss.NewStyle().
			Foreground(sh.theme.Comment).
			Render(comment)
	}

	// Strings (simple detection)
	line = sh.highlightStrings(line, "\"")
	line = sh.highlightStrings(line, "'")

	// Numbers
	line = sh.highlightNumbers(line)

	return line
}

// highlightWithRules applies keyword and type highlighting
func (sh *SyntaxHighlighter) highlightWithRules(code string, keywords, types []string) string {
	words := sh.tokenize(code)
	result := ""

	for _, word := range words {
		if sh.isKeyword(word.text, keywords) {
			result += lipgloss.NewStyle().
				Foreground(sh.theme.Keyword).
				Bold(true).
				Render(word.text)
		} else if sh.isType(word.text, types) {
			result += lipgloss.NewStyle().
				Foreground(sh.theme.Function).
				Render(word.text)
		} else if sh.isString(word.text) {
			result += lipgloss.NewStyle().
				Foreground(sh.theme.String).
				Render(word.text)
		} else if sh.isNumber(word.text) {
			result += lipgloss.NewStyle().
				Foreground(sh.theme.Number).
				Render(word.text)
		} else if sh.isComment(word.text) {
			result += lipgloss.NewStyle().
				Foreground(sh.theme.Comment).
				Render(word.text)
		} else {
			result += word.text
		}
	}

	return result
}

// Token represents a tokenized piece of code
type Token struct {
	text     string
	tokenType string
}

// tokenize breaks code into tokens while preserving whitespace and structure
func (sh *SyntaxHighlighter) tokenize(code string) []Token {
	tokens := []Token{}
	current := ""
	inString := false
	stringChar := byte(0)
	inComment := false

	for i, char := range code {
		// Handle string literals
		if (char == '"' || char == '\'') && !inComment {
			if !inString {
				if current != "" {
					tokens = append(tokens, Token{current, "word"})
					current = ""
				}
				inString = true
				stringChar = code[i]
				current += string(char)
			} else if code[i] == stringChar {
				current += string(char)
				tokens = append(tokens, Token{current, "string"})
				current = ""
				inString = false
				stringChar = 0
			} else {
				current += string(char)
			}
			continue
		}

		if inString {
			current += string(char)
			continue
		}

		// Handle comments
		if i < len(code)-1 && code[i:i+2] == "//" {
			if current != "" {
				tokens = append(tokens, Token{current, "word"})
				current = ""
			}
			inComment = true
			current += "//"
			continue
		}

		if inComment {
			current += string(char)
			if char == '\n' {
				tokens = append(tokens, Token{current, "comment"})
				current = ""
				inComment = false
			}
			continue
		}

		// Handle word boundaries
		if unicode.IsSpace(char) || sh.isPunctuation(char) {
			if current != "" {
				tokens = append(tokens, Token{current, "word"})
				current = ""
			}
			tokens = append(tokens, Token{string(char), "punctuation"})
		} else {
			current += string(char)
		}
	}

	if current != "" {
		tokenType := "word"
		if inString {
			tokenType = "string"
		} else if inComment {
			tokenType = "comment"
		}
		tokens = append(tokens, Token{current, tokenType})
	}

	return tokens
}

// Helper functions

func (sh *SyntaxHighlighter) isKeyword(word string, keywords []string) bool {
	for _, keyword := range keywords {
		if word == keyword {
			return true
		}
	}
	return false
}

func (sh *SyntaxHighlighter) isType(word string, types []string) bool {
	for _, t := range types {
		if word == t {
			return true
		}
	}
	return false
}

func (sh *SyntaxHighlighter) isString(word string) bool {
	return len(word) >= 2 && 
		((word[0] == '"' && word[len(word)-1] == '"') ||
		 (word[0] == '\'' && word[len(word)-1] == '\''))
}

func (sh *SyntaxHighlighter) isNumber(word string) bool {
	if len(word) == 0 {
		return false
	}
	
	for i, char := range word {
		if i == 0 && (char == '-' || char == '+') {
			continue
		}
		if !unicode.IsDigit(char) && char != '.' {
			return false
		}
	}
	return true
}

func (sh *SyntaxHighlighter) isComment(word string) bool {
	return strings.HasPrefix(word, "//") || strings.HasPrefix(word, "#")
}

func (sh *SyntaxHighlighter) isPunctuation(char rune) bool {
	punctuation := "(){}[]<>,.;:!?+-*/=&|^%~`@$"
	return strings.ContainsRune(punctuation, char)
}

func (sh *SyntaxHighlighter) highlightStrings(line, quote string) string {
	parts := strings.Split(line, quote)
	if len(parts) < 3 {
		return line
	}

	result := parts[0]
	for i := 1; i < len(parts); i += 2 {
		if i+1 < len(parts) {
			content := quote + parts[i] + quote
			styled := lipgloss.NewStyle().
				Foreground(sh.theme.String).
				Render(content)
			result += styled + parts[i+1]
		} else {
			result += quote + parts[i]
		}
	}

	return result
}

func (sh *SyntaxHighlighter) highlightNumbers(line string) string {
	words := strings.Fields(line)
	result := line

	for _, word := range words {
		if sh.isNumber(word) {
			styled := lipgloss.NewStyle().
				Foreground(sh.theme.Number).
				Render(word)
			result = strings.Replace(result, word, styled, 1)
		}
	}

	return result
}

// detectLanguageFromExtension detects language from file extension
func DetectLanguageFromExtension(filename string) string {
	parts := strings.Split(filename, ".")
	if len(parts) < 2 {
		return "text"
	}

	ext := strings.ToLower(parts[len(parts)-1])
	
	switch ext {
	case "go":
		return "go"
	case "js", "jsx", "mjs":
		return "javascript"
	case "ts", "tsx":
		return "typescript"
	case "py", "pyw":
		return "python"
	case "ex", "exs":
		return "elixir"
	case "md", "markdown":
		return "markdown"
	case "rs":
		return "rust"
	case "c", "h":
		return "c"
	case "cpp", "cc", "cxx", "hpp":
		return "cpp"
	case "java":
		return "java"
	case "rb":
		return "ruby"
	case "php":
		return "php"
	case "sh", "bash":
		return "bash"
	case "json":
		return "json"
	case "xml":
		return "xml"
	case "html", "htm":
		return "html"
	case "css":
		return "css"
	case "sql":
		return "sql"
	case "yaml", "yml":
		return "yaml"
	case "toml":
		return "toml"
	default:
		return "text"
	}
}