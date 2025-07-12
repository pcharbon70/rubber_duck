package ui

import (
	"testing"
	
	"github.com/charmbracelet/lipgloss"
)

func TestThemeManager(t *testing.T) {
	tm := NewThemeManager()
	
	// Test default theme
	theme := tm.GetTheme()
	if theme.Name != "dark" {
		t.Errorf("Expected default theme 'dark', got '%s'", theme.Name)
	}
	
	// Test theme switching
	if !tm.SetTheme("light") {
		t.Error("Failed to set light theme")
	}
	
	theme = tm.GetTheme()
	if theme.Name != "light" {
		t.Errorf("Expected theme 'light', got '%s'", theme.Name)
	}
	
	// Test invalid theme
	if tm.SetTheme("nonexistent") {
		t.Error("Should not be able to set nonexistent theme")
	}
}

func TestThemeStructure(t *testing.T) {
	themes := []string{"dark", "light", "solarized-dark", "dracula"}
	
	for _, themeName := range themes {
		var theme *Theme
		switch themeName {
		case "dark":
			theme = DefaultDarkTheme()
		case "light":
			theme = DefaultLightTheme()
		case "solarized-dark":
			theme = SolarizedDarkTheme()
		case "dracula":
			theme = DraculaTheme()
		}
		
		if theme == nil {
			t.Errorf("Theme %s returned nil", themeName)
			continue
		}
		
		if theme.Name != themeName {
			t.Errorf("Theme name mismatch: expected %s, got %s", themeName, theme.Name)
		}
		
		// Test that essential colors are defined
		if theme.Background == lipgloss.Color("") {
			t.Errorf("Theme %s has empty background color", themeName)
		}
		
		if theme.Foreground == lipgloss.Color("") {
			t.Errorf("Theme %s has empty foreground color", themeName)
		}
		
		if theme.Border == lipgloss.Color("") {
			t.Errorf("Theme %s has empty border color", themeName)
		}
	}
}

func TestThemeRegistration(t *testing.T) {
	tm := NewThemeManager()
	
	// Test getting available themes
	themes := tm.GetThemeNames()
	expectedThemes := []string{"dark", "light", "solarized-dark", "dracula"}
	
	if len(themes) != len(expectedThemes) {
		t.Errorf("Expected %d themes, got %d", len(expectedThemes), len(themes))
	}
	
	// Check that all expected themes are present
	themeMap := make(map[string]bool)
	for _, theme := range themes {
		themeMap[theme] = true
	}
	
	for _, expected := range expectedThemes {
		if !themeMap[expected] {
			t.Errorf("Expected theme %s not found", expected)
		}
	}
}

func TestCustomTheme(t *testing.T) {
	tm := NewThemeManager()
	
	// Create custom theme
	customTheme := &Theme{
		Name:        "custom",
		Description: "Custom test theme",
		Background:  lipgloss.Color("#123456"),
		Foreground:  lipgloss.Color("#abcdef"),
		Border:      lipgloss.Color("#999999"),
	}
	
	// Register custom theme
	tm.RegisterTheme(customTheme)
	
	// Test setting custom theme
	if !tm.SetTheme("custom") {
		t.Error("Failed to set custom theme")
	}
	
	theme := tm.GetTheme()
	if theme.Name != "custom" {
		t.Errorf("Expected custom theme, got %s", theme.Name)
	}
	
	if theme.Background != lipgloss.Color("#123456") {
		t.Errorf("Custom theme background mismatch")
	}
}

func TestModelThemeIntegration(t *testing.T) {
	model := NewModel()
	
	// Test default theme
	theme := model.GetTheme()
	if theme.Name != "dark" {
		t.Errorf("Expected default theme 'dark', got '%s'", theme.Name)
	}
	
	// Test theme switching
	if !model.SetTheme("light") {
		t.Error("Failed to set light theme on model")
	}
	
	theme = model.GetTheme()
	if theme.Name != "light" {
		t.Errorf("Expected theme 'light', got '%s'", theme.Name)
	}
	
	// Test getting available themes
	themes := model.GetAvailableThemes()
	if len(themes) == 0 {
		t.Error("No themes available from model")
	}
}

func TestThemedStyles(t *testing.T) {
	model := NewModel()
	
	// Test with dark theme
	model.SetTheme("dark")
	darkStyles := model.getThemedStyles()
	
	// Test with light theme
	model.SetTheme("light")
	lightStyles := model.getThemedStyles()
	
	// Styles should be different between themes
	if darkStyles.statusBarStyle.GetBackground() == lightStyles.statusBarStyle.GetBackground() {
		t.Error("Dark and light themes should have different status bar backgrounds")
	}
}