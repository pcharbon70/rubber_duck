package ui

import (
	"testing"
)

func TestNewModel(t *testing.T) {
	// Test model creation
	model := NewModel()
	
	// Verify initial state
	if model.activePane != FileTreePane {
		t.Errorf("Expected active pane to be FileTreePane, got %v", model.activePane)
	}
	
	if model.connected {
		t.Error("Expected model to be disconnected initially")
	}
	
	if model.editor.Value() != "" {
		t.Error("Expected editor to be empty initially")
	}
	
	if model.commandPalette.IsVisible() {
		t.Error("Expected command palette to be hidden initially")
	}
}

func TestModelView(t *testing.T) {
	// Test that view doesn't panic
	model := NewModel()
	model.width = 80
	model.height = 24
	
	view := model.View()
	if view == "" {
		t.Error("Expected non-empty view")
	}
}

func TestNextPane(t *testing.T) {
	model := NewModel()
	
	// Test pane cycling
	model.activePane = FileTreePane
	next := model.nextPane()
	if next != EditorPane {
		t.Errorf("Expected EditorPane after FileTreePane, got %v", next)
	}
	
	model.activePane = EditorPane
	next = model.nextPane()
	if next != OutputPane {
		t.Errorf("Expected OutputPane after EditorPane, got %v", next)
	}
	
	model.activePane = OutputPane
	next = model.nextPane()
	if next != FileTreePane {
		t.Errorf("Expected FileTreePane after OutputPane, got %v", next)
	}
}