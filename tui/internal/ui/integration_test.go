package ui

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/rubber_duck/tui/internal/phoenix"
)

// TestTUIWithMockClient tests the complete TUI integration with mock Phoenix client
func TestTUIWithMockClient(t *testing.T) {
	// Enable mock mode for this test
	phoenix.EnableMockMode()
	defer phoenix.DisableMockMode()
	
	// Create a new model
	model := NewModel()
	
	// Test initial state
	if model.connected {
		t.Error("Model should not be connected initially")
	}
	
	if model.phoenixClient != nil {
		t.Error("Phoenix client should not be set initially")
	}
	
	// Initialize the model
	initCmd := model.Init()
	if initCmd == nil {
		t.Fatal("Init() should return a command")
	}
	
	// Execute initialization command
	msg := initCmd()
	if msg == nil {
		t.Fatal("Init command should return a message")
	}
	
	// Update model with init message
	updatedModel, cmd := model.Update(msg)
	model = updatedModel.(Model)
	
	// Should have triggered connection initiation
	if model.phoenixClient == nil {
		t.Error("Phoenix client should be set after initialization")
	}
	
	// Execute connection command
	if cmd != nil {
		connectMsg := cmd()
		model, _ = model.Update(connectMsg).(Model), nil
	}
}

// TestFileTreeIntegration tests file tree integration with mock data
func TestFileTreeIntegration(t *testing.T) {
	phoenix.EnableMockMode()
	defer phoenix.DisableMockMode()
	
	model := NewModel()
	model.phoenixClient = phoenix.NewPhoenixClient()
	
	// Test window size message
	windowMsg := tea.WindowSizeMsg{Width: 120, Height: 30}
	model, _ = model.Update(windowMsg).(Model), nil
	
	if model.width != 120 || model.height != 30 {
		t.Errorf("Expected window size 120x30, got %dx%d", model.width, model.height)
	}
	
	// Test connection and file list loading
	model, cmd := model.Update(InitiateConnectionMsg{}).(Model), nil
	if cmd != nil {
		// Execute connection
		connectMsg := cmd()
		model, cmd = model.Update(connectMsg).(Model), nil
		
		if cmd != nil {
			// Execute channel join
			joinMsg := cmd()
			model, cmd = model.Update(joinMsg).(Model), nil
			
			if cmd != nil {
				// Execute file list request
				listMsg := cmd()
				model, _ = model.Update(listMsg).(Model), nil
			}
		}
	}
	
	// Verify connection
	if !model.connected {
		t.Error("Model should be connected after successful connection flow")
	}
}

// TestFileOperationsIntegration tests file loading and saving with mock client
func TestFileOperationsIntegration(t *testing.T) {
	phoenix.EnableMockMode()
	defer phoenix.DisableMockMode()
	
	model := setupConnectedModel(t)
	
	// Test file selection
	fileSelectMsg := FileSelectedMsg{Path: "main.go"}
	model, cmd := model.Update(fileSelectMsg).(Model), nil
	
	if !strings.Contains(model.statusBar, "Loading main.go") {
		t.Errorf("Expected status bar to show loading, got: %s", model.statusBar)
	}
	
	// Execute file load command
	if cmd != nil {
		loadMsg := cmd()
		
		// Should get a channel response with file content
		if respMsg, ok := loadMsg.(ChannelResponseMsg); ok {
			if respMsg.Event != "file_loaded" {
				t.Errorf("Expected file_loaded event, got %s", respMsg.Event)
			}
			
			// Process the file loaded response
			model, _ = model.Update(respMsg).(Model), nil
			
			// Check if editor was updated
			if model.editor.Value() == "" {
				t.Error("Editor should contain file content after loading")
			}
		} else {
			t.Errorf("Expected ChannelResponseMsg for file load, got %T", loadMsg)
		}
	}
}

// TestCommandPaletteIntegration tests command palette functionality
func TestCommandPaletteIntegration(t *testing.T) {
	model := NewModel()
	
	// Test showing command palette
	keyMsg := tea.KeyMsg{Type: tea.KeyCtrlP}
	model, _ = model.Update(keyMsg).(Model), nil
	
	if !model.commandPalette.IsVisible() {
		t.Error("Command palette should be visible after Ctrl+P")
	}
	
	// Test hiding command palette
	escMsg := tea.KeyMsg{Type: tea.KeyEsc}
	model, _ = model.Update(escMsg).(Model), nil
	
	if model.commandPalette.IsVisible() {
		t.Error("Command palette should be hidden after Esc")
	}
}

// TestNavigationIntegration tests pane navigation
func TestNavigationIntegration(t *testing.T) {
	model := NewModel()
	model.width = 120
	model.height = 30
	
	// Test initial pane
	if model.activePane != FileTreePane {
		t.Errorf("Expected initial pane to be FileTreePane, got %v", model.activePane)
	}
	
	// Test tab navigation
	tabMsg := tea.KeyMsg{Type: tea.KeyTab}
	
	// Go to editor pane
	model, _ = model.Update(tabMsg).(Model), nil
	if model.activePane != EditorPane {
		t.Errorf("Expected EditorPane after first tab, got %v", model.activePane)
	}
	
	// Go to output pane
	model, _ = model.Update(tabMsg).(Model), nil
	if model.activePane != OutputPane {
		t.Errorf("Expected OutputPane after second tab, got %v", model.activePane)
	}
	
	// Go back to file tree pane
	model, _ = model.Update(tabMsg).(Model), nil
	if model.activePane != FileTreePane {
		t.Errorf("Expected FileTreePane after third tab, got %v", model.activePane)
	}
}

// TestAnalysisIntegration tests analysis workflow with streaming
func TestAnalysisIntegration(t *testing.T) {
	phoenix.EnableMockMode()
	defer phoenix.DisableMockMode()
	
	model := setupConnectedModel(t)
	
	// Trigger analysis via command execution
	executeMsg := ExecuteCommandMsg{
		Command: "analyze",
		Args:    []string{"main.go"},
	}
	
	model, cmd := model.Update(executeMsg).(Model), nil
	
	// For mock client, analysis should start streaming
	if cmd != nil {
		startMsg := cmd()
		
		if streamMsg, ok := startMsg.(StreamStartMsg); ok {
			model, _ = model.Update(streamMsg).(Model), nil
			
			// Simulate receiving stream data
			dataMsg := StreamDataMsg{
				ID:   streamMsg.ID,
				Data: "Analyzing file...\n",
			}
			model, _ = model.Update(dataMsg).(Model), nil
			
			// Check if output was updated
			outputContent := model.output.View()
			if !strings.Contains(outputContent, "Analyzing file") {
				t.Error("Output should contain streaming analysis data")
			}
			
			// Simulate stream end
			endMsg := StreamEndMsg{ID: streamMsg.ID}
			model, _ = model.Update(endMsg).(Model), nil
			
		} else {
			t.Errorf("Expected StreamStartMsg for analysis, got %T", startMsg)
		}
	}
}

// TestErrorHandlingIntegration tests error handling throughout the UI
func TestErrorHandlingIntegration(t *testing.T) {
	phoenix.EnableMockMode()
	defer phoenix.DisableMockMode()
	
	// Create mock client with high error rate for testing
	mockClient := phoenix.NewMockClientWithOptions(phoenix.MockOptions{
		NetworkDelay: 1 * time.Millisecond,
		ErrorRate:    1.0, // 100% error rate
	})
	
	model := NewModel()
	model.phoenixClient = mockClient
	model.connected = true // Simulate connected state
	
	// Test file loading with errors
	fileSelectMsg := FileSelectedMsg{Path: "nonexistent.go"}
	model, cmd := model.Update(fileSelectMsg).(Model), nil
	
	if cmd != nil {
		errorMsg := cmd()
		
		// Should get an error message
		if errMsg, ok := errorMsg.(ErrorMsg); ok {
			model, _ = model.Update(errMsg).(Model), nil
			
			// Check if error is displayed in status bar
			if !strings.Contains(model.statusBar, "Error") {
				t.Error("Status bar should show error message")
			}
		}
	}
}

// TestCompleteWorkflowIntegration tests a complete user workflow
func TestCompleteWorkflowIntegration(t *testing.T) {
	phoenix.EnableMockMode()
	defer phoenix.DisableMockMode()
	
	model := setupConnectedModel(t)
	
	// 1. Load file tree
	model, cmd := model.Update(InitiateConnectionMsg{}).(Model), nil
	executeCommandChain(model, cmd)
	
	// 2. Select a file
	fileSelectMsg := FileSelectedMsg{Path: "cmd/main.go"}
	model, cmd = model.Update(fileSelectMsg).(Model), nil
	executeCommandChain(model, cmd)
	
	// 3. Edit the file (simulate typing)
	model.editor.SetValue("package main\n\nimport \"fmt\"\n\nfunc main() {\n\tfmt.Println(\"Hello World\")\n}")
	
	// 4. Analyze the file
	executeMsg := ExecuteCommandMsg{Command: "analyze", Args: []string{}}
	model, cmd = model.Update(executeMsg).(Model), nil
	executeCommandChain(model, cmd)
	
	// 5. Generate code
	generateMsg := ExecuteCommandMsg{Command: "generate", Args: []string{}}
	model, cmd = model.Update(generateMsg).(Model), nil
	executeCommandChain(model, cmd)
	
	// Verify final state
	if model.editor.Value() == "" {
		t.Error("Editor should contain content after complete workflow")
	}
	
	if !model.connected {
		t.Error("Should remain connected throughout workflow")
	}
}

// TestViewRenderingIntegration tests that the UI renders without errors
func TestViewRenderingIntegration(t *testing.T) {
	model := NewModel()
	model.width = 120
	model.height = 30
	
	// Test rendering in different states
	tests := []struct {
		name     string
		setup    func(*Model)
		wantSubstr string
	}{
		{
			name: "initial state",
			setup: func(m *Model) {
				// No setup needed
			},
			wantSubstr: "Loading...",
		},
		{
			name: "connected state",
			setup: func(m *Model) {
				m.connected = true
				m.statusBar = "Connected"
			},
			wantSubstr: "Connected",
		},
		{
			name: "with file content",
			setup: func(m *Model) {
				m.connected = true
				m.editor.SetValue("package main\n\nfunc main() {}")
				m.statusBar = "Editing: main.go"
			},
			wantSubstr: "package main",
		},
		{
			name: "command palette visible",
			setup: func(m *Model) {
				m.commandPalette.Show()
			},
			wantSubstr: "Command Palette",
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			testModel := model
			tt.setup(&testModel)
			
			view := testModel.View()
			if view == "" {
				t.Error("View should not be empty")
			}
			
			if tt.wantSubstr != "" && !strings.Contains(view, tt.wantSubstr) {
				t.Errorf("View should contain '%s'", tt.wantSubstr)
			}
		})
	}
}

// TestResponseProcessingIntegration tests processing of Phoenix responses
func TestResponseProcessingIntegration(t *testing.T) {
	model := NewModel()
	
	// Test file list response processing
	t.Run("FileListResponse", func(t *testing.T) {
		fileListResp := phoenix.FileListResponse{
			Files: []phoenix.FileInfo{
				{
					Name:  "main.go",
					Path:  "main.go",
					IsDir: false,
					Size:  100,
				},
				{
					Name:     "lib",
					Path:     "lib",
					IsDir:    true,
					Children: []phoenix.FileInfo{
						{
							Name:  "utils.go",
							Path:  "lib/utils.go",
							IsDir: false,
							Size:  50,
						},
					},
				},
			},
			Path: ".",
		}
		
		data, _ := json.Marshal(fileListResp)
		respMsg := ChannelResponseMsg{
			Event:   "file_list",
			Payload: data,
		}
		
		model, cmd := model.Update(respMsg).(Model), nil
		
		if cmd != nil {
			fileTreeMsg := cmd()
			if treeMsg, ok := fileTreeMsg.(FileTreeLoadedMsg); ok {
				model, _ = model.Update(treeMsg).(Model), nil
				
				// Verify file tree was updated
				if len(model.files) == 0 {
					t.Error("File tree should be populated after processing file list response")
				}
			}
		}
	})
	
	// Test file content response processing
	t.Run("FileContentResponse", func(t *testing.T) {
		fileContentResp := phoenix.FileContentResponse{
			Path:     "main.go",
			Content:  "package main\n\nfunc main() {}",
			Language: "go",
			Size:     25,
		}
		
		data, _ := json.Marshal(fileContentResp)
		respMsg := ChannelResponseMsg{
			Event:   "file_loaded",
			Payload: data,
		}
		
		model, cmd := model.Update(respMsg).(Model), nil
		
		if cmd != nil {
			loadedMsg := cmd()
			if fileMsg, ok := loadedMsg.(FileLoadedMsg); ok {
				model, _ = model.Update(fileMsg).(Model), nil
				
				// Verify editor was updated
				if model.editor.Value() != fileContentResp.Content {
					t.Errorf("Editor content should match response content")
				}
			}
		}
	})
}

// Helper functions for integration tests

// setupConnectedModel creates a model in connected state for testing
func setupConnectedModel(t *testing.T) Model {
	model := NewModel()
	model.phoenixClient = phoenix.NewPhoenixClient()
	model.connected = true
	model.width = 120
	model.height = 30
	model.statusBar = "Connected | Test Mode"
	
	return model
}

// executeCommandChain executes a chain of commands until completion
func executeCommandChain(model Model, cmd tea.Cmd) Model {
	for cmd != nil {
		msg := cmd()
		if msg == nil {
			break
		}
		var newCmd tea.Cmd
		model, newCmd = model.Update(msg).(Model), nil
		cmd = newCmd
	}
	return model
}

// simulateKeySequence simulates a sequence of key presses
func simulateKeySequence(model Model, keys []tea.KeyMsg) Model {
	for _, key := range keys {
		model, _ = model.Update(key).(Model), nil
	}
	return model
}