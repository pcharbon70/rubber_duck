package commands

import (
	"reflect"
	"testing"
)

func TestNewCommandRegistry(t *testing.T) {
	registry := NewCommandRegistry()

	if registry == nil {
		t.Fatal("Expected non-nil registry")
	}

	if registry.commands == nil {
		t.Error("Expected commands map to be initialized")
	}

	if registry.local == nil {
		t.Error("Expected local commands map to be initialized")
	}

	if registry.GetCommandCount() != 0 {
		t.Error("Expected empty registry to have 0 commands")
	}
}

func TestCommandRegistry_RegisterCommand(t *testing.T) {
	registry := NewCommandRegistry()

	def := CommandDefinition{
		Name:        "test_command",
		Description: "A test command",
		Category:    "Test",
		Type:        LocalCommand,
	}

	registry.RegisterCommand(def)

	if registry.GetCommandCount() != 1 {
		t.Errorf("Expected 1 command, got %d", registry.GetCommandCount())
	}

	retrieved := registry.GetCommand("test_command")
	if retrieved == nil {
		t.Fatal("Expected to retrieve registered command")
	}

	if retrieved.Name != def.Name {
		t.Errorf("Expected name %s, got %s", def.Name, retrieved.Name)
	}
}

func TestCommandRegistry_RegisterLocalCommand(t *testing.T) {
	registry := NewCommandRegistry()

	cmd := LocalTUICommand{
		Name:        "local_test",
		Description: "A local test command",
		Category:    "Test",
		Handler:     func(args map[string]interface{}, context CommandContext) error { return nil },
	}

	registry.RegisterLocalCommand(cmd)

	if registry.GetLocalCommandCount() != 1 {
		t.Errorf("Expected 1 local command, got %d", registry.GetLocalCommandCount())
	}

	retrieved := registry.GetLocalCommand("local_test")
	if retrieved == nil {
		t.Fatal("Expected to retrieve registered local command")
	}

	if retrieved.Name != cmd.Name {
		t.Errorf("Expected name %s, got %s", cmd.Name, retrieved.Name)
	}
}

func TestCommandRegistry_GetCommand(t *testing.T) {
	registry := NewCommandRegistry()

	// Test non-existent command
	cmd := registry.GetCommand("non_existent")
	if cmd != nil {
		t.Error("Expected nil for non-existent command")
	}

	// Register and retrieve command
	def := CommandDefinition{
		Name:        "existing_command",
		Description: "An existing command",
		Type:        ServerCommand,
	}

	registry.RegisterCommand(def)

	retrieved := registry.GetCommand("existing_command")
	if retrieved == nil {
		t.Fatal("Expected to retrieve existing command")
	}

	if retrieved.Name != def.Name {
		t.Errorf("Expected name %s, got %s", def.Name, retrieved.Name)
	}

	// Verify it's a copy (changes don't affect original)
	retrieved.Name = "modified"
	original := registry.GetCommand("existing_command")
	if original.Name == "modified" {
		t.Error("Expected retrieved command to be a copy")
	}
}

func TestCommandRegistry_ListCommands(t *testing.T) {
	registry := NewCommandRegistry()

	// Empty registry
	commands := registry.ListCommands()
	if len(commands) != 0 {
		t.Errorf("Expected 0 commands, got %d", len(commands))
	}

	// Add commands
	def1 := CommandDefinition{Name: "command_b", Description: "Second command"}
	def2 := CommandDefinition{Name: "command_a", Description: "First command"}
	def3 := CommandDefinition{Name: "command_c", Description: "Third command"}

	registry.RegisterCommand(def1)
	registry.RegisterCommand(def2)
	registry.RegisterCommand(def3)

	commands = registry.ListCommands()
	if len(commands) != 3 {
		t.Errorf("Expected 3 commands, got %d", len(commands))
	}

	// Verify sorting
	expectedOrder := []string{"command_a", "command_b", "command_c"}
	for i, cmd := range commands {
		if cmd.Name != expectedOrder[i] {
			t.Errorf("Expected command %s at position %d, got %s", expectedOrder[i], i, cmd.Name)
		}
	}
}

func TestCommandRegistry_ListCommandsByCategory(t *testing.T) {
	registry := NewCommandRegistry()

	def1 := CommandDefinition{Name: "cmd1", Category: "Category1"}
	def2 := CommandDefinition{Name: "cmd2", Category: "Category1"}
	def3 := CommandDefinition{Name: "cmd3", Category: "Category2"}
	def4 := CommandDefinition{Name: "cmd4", Category: ""} // Empty category

	registry.RegisterCommand(def1)
	registry.RegisterCommand(def2)
	registry.RegisterCommand(def3)
	registry.RegisterCommand(def4)

	categories := registry.ListCommandsByCategory()

	if len(categories) != 3 {
		t.Errorf("Expected 3 categories, got %d", len(categories))
	}

	// Check Category1 has 2 commands
	if len(categories["Category1"]) != 2 {
		t.Errorf("Expected 2 commands in Category1, got %d", len(categories["Category1"]))
	}

	// Check Category2 has 1 command
	if len(categories["Category2"]) != 1 {
		t.Errorf("Expected 1 command in Category2, got %d", len(categories["Category2"]))
	}

	// Check General category (empty category becomes "General")
	if len(categories["General"]) != 1 {
		t.Errorf("Expected 1 command in General category, got %d", len(categories["General"]))
	}
}

func TestCommandRegistry_SearchCommands(t *testing.T) {
	registry := NewCommandRegistry()

	def1 := CommandDefinition{Name: "analyze_file", Description: "Analyze a file for issues"}
	def2 := CommandDefinition{Name: "generate_code", Description: "Generate code using AI"}
	def3 := CommandDefinition{Name: "file_operations", Description: "Various file operations"}

	registry.RegisterCommand(def1)
	registry.RegisterCommand(def2)
	registry.RegisterCommand(def3)

	// Search by name
	results := registry.SearchCommands("analyze")
	if len(results) != 1 || results[0].Name != "analyze_file" {
		t.Errorf("Expected 1 result for 'analyze', got %d", len(results))
	}

	// Search by description
	results = registry.SearchCommands("file")
	if len(results) != 2 {
		t.Errorf("Expected 2 results for 'file', got %d", len(results))
	}

	// Case insensitive search
	results = registry.SearchCommands("ANALYZE")
	if len(results) != 1 {
		t.Errorf("Expected 1 result for case insensitive search, got %d", len(results))
	}

	// No matches
	results = registry.SearchCommands("nonexistent")
	if len(results) != 0 {
		t.Errorf("Expected 0 results for nonexistent term, got %d", len(results))
	}
}

func TestCommandRegistry_GetCommandsByType(t *testing.T) {
	registry := NewCommandRegistry()

	def1 := CommandDefinition{Name: "local_cmd", Type: LocalCommand}
	def2 := CommandDefinition{Name: "server_cmd", Type: ServerCommand}
	def3 := CommandDefinition{Name: "hybrid_cmd", Type: HybridCommand}
	def4 := CommandDefinition{Name: "another_local", Type: LocalCommand}

	registry.RegisterCommand(def1)
	registry.RegisterCommand(def2)
	registry.RegisterCommand(def3)
	registry.RegisterCommand(def4)

	// Test LocalCommand
	localCommands := registry.GetCommandsByType(LocalCommand)
	if len(localCommands) != 2 {
		t.Errorf("Expected 2 local commands, got %d", len(localCommands))
	}

	// Test ServerCommand
	serverCommands := registry.GetCommandsByType(ServerCommand)
	if len(serverCommands) != 1 {
		t.Errorf("Expected 1 server command, got %d", len(serverCommands))
	}

	// Test HybridCommand
	hybridCommands := registry.GetCommandsByType(HybridCommand)
	if len(hybridCommands) != 1 {
		t.Errorf("Expected 1 hybrid command, got %d", len(hybridCommands))
	}
}

func TestCommandRegistry_GetCategories(t *testing.T) {
	registry := NewCommandRegistry()

	def1 := CommandDefinition{Name: "cmd1", Category: "Category2"}
	def2 := CommandDefinition{Name: "cmd2", Category: "Category1"}
	def3 := CommandDefinition{Name: "cmd3", Category: "Category2"}
	def4 := CommandDefinition{Name: "cmd4", Category: ""} // Empty category

	registry.RegisterCommand(def1)
	registry.RegisterCommand(def2)
	registry.RegisterCommand(def3)
	registry.RegisterCommand(def4)

	categories := registry.GetCategories()

	expectedCategories := []string{"Category1", "Category2", "General"}
	if !reflect.DeepEqual(categories, expectedCategories) {
		t.Errorf("Expected categories %v, got %v", expectedCategories, categories)
	}
}

func TestCommandRegistry_ValidateCommand(t *testing.T) {
	registry := NewCommandRegistry()

	tests := []struct {
		name        string
		def         CommandDefinition
		expectError bool
		errorCount  int
	}{
		{
			name: "valid command",
			def: CommandDefinition{
				Name:        "valid_cmd",
				Description: "A valid command",
				Args: []ArgDef{
					{Name: "arg1", Type: "string", Required: true},
				},
				Options: []OptDef{
					{Name: "verbose", Type: "bool", Default: false},
				},
			},
			expectError: false,
			errorCount:  0,
		},
		{
			name: "missing name",
			def: CommandDefinition{
				Description: "Missing name",
			},
			expectError: true,
			errorCount:  1,
		},
		{
			name: "missing description",
			def: CommandDefinition{
				Name: "missing_desc",
			},
			expectError: true,
			errorCount:  1,
		},
		{
			name: "duplicate argument names",
			def: CommandDefinition{
				Name:        "dup_args",
				Description: "Duplicate arguments",
				Args: []ArgDef{
					{Name: "arg1", Type: "string"},
					{Name: "arg1", Type: "int"},
				},
			},
			expectError: true,
		},
		{
			name: "invalid argument type",
			def: CommandDefinition{
				Name:        "invalid_type",
				Description: "Invalid argument type",
				Args: []ArgDef{
					{Name: "arg1", Type: "invalid_type"},
				},
			},
			expectError: true,
		},
		{
			name: "conflicting flags",
			def: CommandDefinition{
				Name:        "conflicting",
				Description: "Conflicting flags",
				LocalOnly:   true,
				ServerOnly:  true,
			},
			expectError: true,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			errors := registry.ValidateCommand(test.def)
			
			if test.expectError && len(errors) == 0 {
				t.Error("Expected validation errors but got none")
			}
			
			if !test.expectError && len(errors) > 0 {
				t.Errorf("Expected no validation errors but got: %v", errors)
			}
			
			if test.errorCount > 0 && len(errors) != test.errorCount {
				t.Errorf("Expected %d errors, got %d: %v", test.errorCount, len(errors), errors)
			}
		})
	}
}

func TestCommandRegistry_CommandExists(t *testing.T) {
	registry := NewCommandRegistry()

	if registry.CommandExists("nonexistent") {
		t.Error("Expected false for non-existent command")
	}

	def := CommandDefinition{Name: "existing", Description: "Existing command"}
	registry.RegisterCommand(def)

	if !registry.CommandExists("existing") {
		t.Error("Expected true for existing command")
	}
}

func TestCommandRegistry_UnregisterCommand(t *testing.T) {
	registry := NewCommandRegistry()

	def := CommandDefinition{Name: "to_remove", Description: "Command to remove"}
	registry.RegisterCommand(def)

	if registry.GetCommandCount() != 1 {
		t.Error("Expected 1 command after registration")
	}

	// Remove existing command
	if !registry.UnregisterCommand("to_remove") {
		t.Error("Expected true when removing existing command")
	}

	if registry.GetCommandCount() != 0 {
		t.Error("Expected 0 commands after removal")
	}

	// Try to remove non-existent command
	if registry.UnregisterCommand("nonexistent") {
		t.Error("Expected false when removing non-existent command")
	}
}

func TestCommandRegistry_GetCommandHelp(t *testing.T) {
	registry := NewCommandRegistry()

	def := CommandDefinition{
		Name:        "help_test",
		Description: "A command for testing help",
		Category:    "Test",
		Args: []ArgDef{
			{Name: "file", Description: "File to process", Type: "file", Required: true},
		},
		Options: []OptDef{
			{Name: "verbose", Description: "Verbose output", Type: "bool", Default: false},
		},
		Examples: []string{
			"help_test myfile.txt",
			"help_test myfile.txt --verbose",
		},
	}

	registry.RegisterCommand(def)

	help := registry.GetCommandHelp("help_test")

	// Check that help contains expected sections
	expectedStrings := []string{
		"Command: help_test",
		"Description: A command for testing help",
		"Category: Test",
		"Arguments:",
		"file (file) (required) - File to process",
		"Options:",
		"--verbose (bool) - Verbose output",
		"Examples:",
		"help_test myfile.txt",
	}

	for _, expected := range expectedStrings {
		if !contains(help, expected) {
			t.Errorf("Expected help to contain '%s', but it didn't. Help: %s", expected, help)
		}
	}

	// Test non-existent command
	helpNonExistent := registry.GetCommandHelp("nonexistent")
	if !contains(helpNonExistent, "Command not found") {
		t.Errorf("Expected help for non-existent command to contain error message")
	}
}

func TestCommandRegistry_Clear(t *testing.T) {
	registry := NewCommandRegistry()

	// Add some commands
	def1 := CommandDefinition{Name: "cmd1", Description: "Command 1"}
	def2 := CommandDefinition{Name: "cmd2", Description: "Command 2"}
	cmd1 := LocalTUICommand{Name: "local1", Description: "Local 1"}

	registry.RegisterCommand(def1)
	registry.RegisterCommand(def2)
	registry.RegisterLocalCommand(cmd1)

	if registry.GetCommandCount() != 2 {
		t.Error("Expected 2 commands before clear")
	}

	if registry.GetLocalCommandCount() != 1 {
		t.Error("Expected 1 local command before clear")
	}

	// Clear registry
	registry.Clear()

	if registry.GetCommandCount() != 0 {
		t.Error("Expected 0 commands after clear")
	}

	if registry.GetLocalCommandCount() != 0 {
		t.Error("Expected 0 local commands after clear")
	}
}

// Helper function
func contains(s, substr string) bool {
	return len(substr) <= len(s) && (substr == "" || s[len(s)-len(substr):] == substr || 
		   s[:len(substr)] == substr || 
		   func() bool {
		   	for i := 0; i <= len(s)-len(substr); i++ {
		   		if s[i:i+len(substr)] == substr {
		   			return true
		   		}
		   	}
		   	return false
		   }())
}