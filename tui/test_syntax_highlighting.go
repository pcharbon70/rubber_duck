package main

import (
	"fmt"
	"os"
	"strings"
	
	"github.com/rubber_duck/tui/internal/ui"
)

// Test program to verify syntax highlighting functionality
func main() {
	// Read the example file
	content, err := os.ReadFile("example_test_code.go")
	if err != nil {
		fmt.Printf("Error reading file: %v\n", err)
		return
	}
	
	code := string(content)
	
	// Create a theme and syntax highlighter
	theme := ui.DefaultDarkTheme()
	highlighter := ui.NewSyntaxHighlighter(theme)
	
	fmt.Println("🎨 Testing Syntax Highlighting")
	fmt.Println("==============================")
	fmt.Println()
	
	// Test Chroma highlighting
	fmt.Println("--- Chroma Highlighting (if available) ---")
	chromaResult := highlighter.HighlightCode(code[:500], "go") // Just first 500 chars
	if chromaResult != code[:500] {
		fmt.Println("✅ Chroma highlighting applied")
		fmt.Println("First few lines with highlighting:")
		lines := getFirstNLines(chromaResult, 10)
		fmt.Println(lines)
	} else {
		fmt.Println("⚠️  Chroma highlighting not applied, using fallback")
	}
	
	fmt.Println()
	
	// Test fallback highlighting
	fmt.Println("--- Custom Fallback Highlighting ---")
	highlighter.SetChromaEnabled(false)
	fallbackResult := highlighter.HighlightCode(code[:500], "go")
	if fallbackResult != code[:500] {
		fmt.Println("✅ Custom highlighting applied")
		fmt.Println("First few lines with custom highlighting:")
		lines := getFirstNLines(fallbackResult, 10)
		fmt.Println(lines)
	} else {
		fmt.Println("❌ Custom highlighting failed")
	}
	
	fmt.Println()
	
	// Test language detection
	fmt.Println("--- Language Detection Test ---")
	testFiles := []string{
		"main.go",
		"script.js", 
		"app.py",
		"module.ex",
		"README.md",
		"style.css",
		"config.json",
		"unknown.xyz",
	}
	
	for _, filename := range testFiles {
		detected := ui.DetectLanguageFromExtension(filename)
		fmt.Printf("%-15s -> %s\n", filename, detected)
	}
	
	fmt.Println()
	
	// Test different themes
	fmt.Println("--- Theme Integration Test ---")
	themes := []struct {
		name  string
		theme *ui.Theme
	}{
		{"Dark", ui.DefaultDarkTheme()},
		{"Light", ui.DefaultLightTheme()},
		{"Solarized Dark", ui.SolarizedDarkTheme()},
		{"Dracula", ui.DraculaTheme()},
	}
	
	for _, t := range themes {
		highlighter := ui.NewSyntaxHighlighter(t.theme)
		style := highlighter.GetChromaStyle()
		fmt.Printf("%-15s -> Chroma style: %s\n", t.name, style)
	}
	
	fmt.Println()
	
	// Test configuration options
	fmt.Println("--- Configuration Test ---")
	highlighter = ui.NewSyntaxHighlighter(theme)
	
	fmt.Printf("Chroma enabled: %t\n", highlighter.IsChromaEnabled())
	fmt.Printf("Current style: %s\n", highlighter.GetChromaStyle())
	
	styles := highlighter.GetAvailableChromaStyles()
	fmt.Printf("Available styles: %d (showing first 10)\n", len(styles))
	for i, style := range styles {
		if i >= 10 {
			break
		}
		fmt.Printf("  - %s\n", style)
	}
	
	languages := highlighter.GetAvailableLanguages()
	fmt.Printf("Available languages: %d (showing first 15)\n", len(languages))
	for i, lang := range languages {
		if i >= 15 {
			break
		}
		fmt.Printf("  - %s\n", lang)
	}
	
	fmt.Println()
	fmt.Println("✅ Syntax highlighting test completed!")
}

// getFirstNLines returns the first n lines from a string
func getFirstNLines(text string, n int) string {
	lines := strings.Split(text, "\n")
	if len(lines) > n {
		lines = lines[:n]
	}
	return strings.Join(lines, "\n")
}