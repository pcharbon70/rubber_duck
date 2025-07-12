package ui

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

// TestModalCreation tests creating different modal types
func TestModalCreation(t *testing.T) {
	modal := NewModal()
	
	// Test initial state
	if modal.IsVisible() {
		t.Error("Modal should not be visible initially")
	}
	
	// Test confirm modal
	var confirmResult ModalResult
	modal.ShowConfirm("Test Confirm", "Are you sure?", func(result ModalResult) {
		confirmResult = result
	})
	
	if !modal.IsVisible() {
		t.Error("Modal should be visible after ShowConfirm")
	}
	
	if modal.title != "Test Confirm" {
		t.Errorf("Expected title 'Test Confirm', got '%s'", modal.title)
	}
	
	if len(modal.buttons) != 2 {
		t.Errorf("Confirm modal should have 2 buttons, got %d", len(modal.buttons))
	}
}

// TestModalInput tests input modal functionality
func TestModalInput(t *testing.T) {
	modal := NewModal()
	
	var inputResult ModalResult
	modal.ShowInput("Test Input", "Enter value:", "placeholder", func(result ModalResult) {
		inputResult = result
	})
	
	if !modal.hasInput {
		t.Error("Input modal should have input field")
	}
	
	if modal.textInput.Placeholder != "placeholder" {
		t.Errorf("Expected placeholder 'placeholder', got '%s'", modal.textInput.Placeholder)
	}
	
	// Test handling enter key
	modal.textInput.SetValue("test value")
	modal.textInput.Focus()
	
	updatedModal, cmd := modal.Update(tea.KeyMsg{Type: tea.KeyEnter})
	
	if updatedModal.IsVisible() {
		t.Error("Modal should be hidden after pressing Enter")
	}
	
	// Execute the command to trigger callback
	if cmd != nil {
		cmd()
		
		if inputResult.Input != "test value" {
			t.Errorf("Expected input 'test value', got '%s'", inputResult.Input)
		}
		
		if inputResult.Action != "ok" {
			t.Errorf("Expected action 'ok', got '%s'", inputResult.Action)
		}
	}
}

// TestModalKeyboardNavigation tests keyboard navigation
func TestModalKeyboardNavigation(t *testing.T) {
	modal := NewModal()
	modal.ShowConfirm("Test", "Confirm?", nil)
	
	// Test initial selection (should be on "No" for safety)
	if modal.selectedIndex != 1 {
		t.Errorf("Initial selection should be 1 (No), got %d", modal.selectedIndex)
	}
	
	// Test left navigation
	modal, _ = modal.Update(tea.KeyMsg{Type: tea.KeyLeft})
	if modal.selectedIndex != 0 {
		t.Errorf("After left, selection should be 0, got %d", modal.selectedIndex)
	}
	
	// Test right navigation
	modal, _ = modal.Update(tea.KeyMsg{Type: tea.KeyRight})
	if modal.selectedIndex != 1 {
		t.Errorf("After right, selection should be 1, got %d", modal.selectedIndex)
	}
	
	// Test escape key
	modal, _ = modal.Update(tea.KeyMsg{Type: tea.KeyEsc})
	if modal.IsVisible() {
		t.Error("Modal should be hidden after pressing Escape")
	}
}

// TestModalShortcuts tests button shortcuts
func TestModalShortcuts(t *testing.T) {
	modal := NewModal()
	
	var result ModalResult
	modal.ShowConfirm("Test", "Confirm?", func(r ModalResult) {
		result = r
	})
	
	// Test 'y' shortcut for Yes
	modal, cmd := modal.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'y'}})
	
	if modal.IsVisible() {
		t.Error("Modal should be hidden after pressing 'y'")
	}
	
	if cmd != nil {
		cmd()
		if result.Action != "yes" {
			t.Errorf("Expected action 'yes', got '%s'", result.Action)
		}
	}
	
	// Reset and test 'n' shortcut
	modal.ShowConfirm("Test", "Confirm?", func(r ModalResult) {
		result = r
	})
	
	modal, cmd = modal.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'n'}})
	
	if modal.IsVisible() {
		t.Error("Modal should be hidden after pressing 'n'")
	}
	
	if cmd != nil {
		cmd()
		if result.Action != "no" {
			t.Errorf("Expected action 'no', got '%s'", result.Action)
		}
	}
}

// TestModalTypes tests different modal types
func TestModalTypes(t *testing.T) {
	tests := []struct {
		name     string
		showFunc func(*Modal)
		wantType ModalType
		wantIcon string
	}{
		{
			name: "Error modal",
			showFunc: func(m *Modal) {
				m.ShowError("Error", "Something went wrong")
			},
			wantType: ModalError,
			wantIcon: "❌",
		},
		{
			name: "Info modal",
			showFunc: func(m *Modal) {
				m.ShowInfo("Info", "Information message")
			},
			wantType: ModalInfo,
			wantIcon: "ℹ️",
		},
		{
			name: "Help modal",
			showFunc: func(m *Modal) {
				m.ShowHelp()
			},
			wantType: ModalHelp,
			wantIcon: "🔑",
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			modal := NewModal()
			tt.showFunc(&modal)
			
			if modal.modalType != tt.wantType {
				t.Errorf("Expected type %v, got %v", tt.wantType, modal.modalType)
			}
			
			if !modal.IsVisible() {
				t.Error("Modal should be visible")
			}
			
			// Check for icon in title
			if tt.wantIcon != "" && !strings.Contains(modal.title, tt.wantIcon) {
				t.Errorf("Expected title to contain icon %s", tt.wantIcon)
			}
		})
	}
}

// TestModalView tests that modal renders without errors
func TestModalView(t *testing.T) {
	modal := NewModal()
	modal.SetSize(120, 30)
	
	// Test rendering when not visible
	view := modal.View()
	if view != "" {
		t.Error("Modal should render empty string when not visible")
	}
	
	// Test rendering when visible
	modal.ShowConfirm("Test", "This is a test", nil)
	view = modal.View()
	
	if view == "" {
		t.Error("Modal should render content when visible")
	}
	
	// Check that content is included
	if !strings.Contains(view, "Test") {
		t.Error("Modal view should contain title")
	}
	
	if !strings.Contains(view, "This is a test") {
		t.Error("Modal view should contain content")
	}
	
	if !strings.Contains(view, "Yes") || !strings.Contains(view, "No") {
		t.Error("Modal view should contain buttons")
	}
}