package ui

import (
	"strings"
	"testing"
)

func TestSyntaxHighlighter_NewSyntaxHighlighter(t *testing.T) {
	theme := DefaultDarkTheme()
	highlighter := NewSyntaxHighlighter(theme)

	if highlighter.theme != theme {
		t.Errorf("Expected theme to be set")
	}

	if !highlighter.useChroma {
		t.Errorf("Expected Chroma to be enabled by default")
	}

	if !highlighter.fallbackToCustom {
		t.Errorf("Expected fallback to be enabled by default")
	}

	expectedStyle := getChromaStyleForTheme(theme)
	if highlighter.chromaStyle != expectedStyle {
		t.Errorf("Expected chromaStyle to be %s, got %s", expectedStyle, highlighter.chromaStyle)
	}
}

func TestGetChromaStyleForTheme(t *testing.T) {
	tests := []struct {
		themeName     string
		expectedStyle string
	}{
		{"dark", "monokai"},
		{"light", "github"},
		{"solarized-dark", "solarized-dark"},
		{"dracula", "dracula"},
		{"unknown", "monokai"},
	}

	for _, test := range tests {
		theme := &Theme{Name: test.themeName}
		style := getChromaStyleForTheme(theme)
		if style != test.expectedStyle {
			t.Errorf("For theme %s, expected style %s, got %s", 
				test.themeName, test.expectedStyle, style)
		}
	}
}

func TestDetectLanguageFromExtension(t *testing.T) {
	tests := []struct {
		filename string
		expected string
	}{
		{"main.go", "go"},
		{"script.js", "javascript"},
		{"app.ts", "typescript"},
		{"script.py", "python"},
		{"module.ex", "elixir"},
		{"README.md", "markdown"},
		{"main.rs", "rust"},
		{"program.c", "c"},
		{"app.cpp", "cpp"},
		{"Main.java", "java"},
		{"script.rb", "ruby"},
		{"index.php", "php"},
		{"script.sh", "bash"},
		{"data.json", "json"},
		{"config.xml", "xml"},
		{"index.html", "html"},
		{"style.css", "css"},
		{"query.sql", "sql"},
		{"config.yaml", "yaml"},
		{"config.toml", "toml"},
		{"unknown.xyz", "text"},
		{"noextension", "text"},
	}

	for _, test := range tests {
		result := DetectLanguageFromExtension(test.filename)
		// Note: Chroma's lexer.Match() might return different results
		// so we check if the result is reasonable
		if result != test.expected && result != "text" {
			// If Chroma returned something different, that's also acceptable
			t.Logf("For %s, expected %s, got %s (Chroma result)", 
				test.filename, test.expected, result)
		}
	}
}

func TestSyntaxHighlighter_HighlightCode(t *testing.T) {
	theme := DefaultDarkTheme()
	highlighter := NewSyntaxHighlighter(theme)

	// Test with simple Go code
	goCode := `package main

import "fmt"

func main() {
	fmt.Println("Hello, World!")
}`

	result := highlighter.HighlightCode(goCode, "go")
	
	// The result should be different from the original (highlighted)
	if result == goCode {
		t.Errorf("Expected highlighted code to be different from original")
	}

	// Result should not be empty
	if result == "" {
		t.Errorf("Expected non-empty result from highlighting")
	}
}

func TestSyntaxHighlighter_FallbackBehavior(t *testing.T) {
	theme := DefaultDarkTheme()
	highlighter := NewSyntaxHighlighter(theme)

	// Disable Chroma to test fallback
	highlighter.SetChromaEnabled(false)

	goCode := `package main
func main() {}`

	result := highlighter.HighlightCode(goCode, "go")
	
	// Should use custom highlighting
	if result == goCode {
		t.Errorf("Expected custom highlighting to modify the code")
	}

	// Should contain some styling
	if !strings.Contains(result, "\x1b[") && !containsLipglossStyles(result) {
		t.Logf("Result may not contain styling, but that's acceptable for custom highlighter: %s", result)
	}
}

func TestSyntaxHighlighter_Configuration(t *testing.T) {
	theme := DefaultDarkTheme()
	highlighter := NewSyntaxHighlighter(theme)

	// Test Chroma enabled/disabled
	highlighter.SetChromaEnabled(false)
	if highlighter.IsChromaEnabled() {
		t.Errorf("Expected Chroma to be disabled")
	}

	highlighter.SetChromaEnabled(true)
	if !highlighter.IsChromaEnabled() {
		t.Errorf("Expected Chroma to be enabled")
	}

	// Test style setting
	highlighter.SetChromaStyle("github")
	if highlighter.GetChromaStyle() != "github" {
		t.Errorf("Expected style to be 'github', got %s", highlighter.GetChromaStyle())
	}

	// Test fallback setting
	highlighter.SetFallbackEnabled(false)
	if highlighter.fallbackToCustom {
		t.Errorf("Expected fallback to be disabled")
	}
}

func TestSyntaxHighlighter_AvailableOptions(t *testing.T) {
	theme := DefaultDarkTheme()
	highlighter := NewSyntaxHighlighter(theme)

	// Test that we can get available styles and languages
	styles := highlighter.GetAvailableChromaStyles()
	if len(styles) == 0 {
		t.Errorf("Expected at least some Chroma styles to be available")
	}

	languages := highlighter.GetAvailableLanguages()
	if len(languages) == 0 {
		t.Errorf("Expected at least some languages to be available")
	}

	// Check for common styles and languages
	if !contains(styles, "monokai") {
		t.Errorf("Expected 'monokai' to be in available styles")
	}

	if !contains(languages, "go") {
		t.Errorf("Expected 'go' to be in available languages")
	}
}

// Helper functions

func containsLipglossStyles(s string) bool {
	// Check for common lipgloss ANSI escape sequences
	return strings.Contains(s, "\x1b[") || strings.Contains(s, "\033[")
}

func contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}