package ui

import (
	"testing"
)

func TestNewModel(t *testing.T) {
	// This test will fail until we implement the Model
	model := NewModel()
	
	if model == nil {
		t.Fatal("Expected non-nil model")
	}
	
	// Check that chat is focused by default
	if model.activePane != ChatPane {
		t.Errorf("Expected chat pane to be active by default, got %v", model.activePane)
	}
	
	// Check that model dimensions are initialized
	if model.width == 0 || model.height == 0 {
		t.Error("Expected default dimensions to be set")
	}
}