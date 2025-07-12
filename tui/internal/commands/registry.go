package commands

import (
	"sort"
	"strings"
	"sync"
)

// CommandRegistry manages available commands and their definitions
type CommandRegistry struct {
	commands map[string]CommandDefinition
	local    map[string]LocalTUICommand
	mu       sync.RWMutex
}

// NewCommandRegistry creates a new command registry
func NewCommandRegistry() *CommandRegistry {
	return &CommandRegistry{
		commands: make(map[string]CommandDefinition),
		local:    make(map[string]LocalTUICommand),
	}
}

// RegisterCommand registers a command definition
func (cr *CommandRegistry) RegisterCommand(def CommandDefinition) {
	cr.mu.Lock()
	defer cr.mu.Unlock()
	cr.commands[def.Name] = def
}

// RegisterLocalCommand registers a local TUI command
func (cr *CommandRegistry) RegisterLocalCommand(cmd LocalTUICommand) {
	cr.mu.Lock()
	defer cr.mu.Unlock()
	cr.local[cmd.Name] = cmd
}

// GetCommand returns a command definition by name
func (cr *CommandRegistry) GetCommand(name string) *CommandDefinition {
	cr.mu.RLock()
	defer cr.mu.RUnlock()
	
	if def, exists := cr.commands[name]; exists {
		// Return a copy to avoid race conditions
		defCopy := def
		return &defCopy
	}
	return nil
}

// GetLocalCommand returns a local command by name
func (cr *CommandRegistry) GetLocalCommand(name string) *LocalTUICommand {
	cr.mu.RLock()
	defer cr.mu.RUnlock()
	
	if cmd, exists := cr.local[name]; exists {
		// Return a copy to avoid race conditions
		cmdCopy := cmd
		return &cmdCopy
	}
	return nil
}

// ListCommands returns all registered command definitions
func (cr *CommandRegistry) ListCommands() []CommandDefinition {
	cr.mu.RLock()
	defer cr.mu.RUnlock()
	
	commands := make([]CommandDefinition, 0, len(cr.commands))
	for _, def := range cr.commands {
		commands = append(commands, def)
	}
	
	// Sort by name for consistent ordering
	sort.Slice(commands, func(i, j int) bool {
		return commands[i].Name < commands[j].Name
	})
	
	return commands
}

// ListLocalCommands returns all registered local commands
func (cr *CommandRegistry) ListLocalCommands() []LocalTUICommand {
	cr.mu.RLock()
	defer cr.mu.RUnlock()
	
	commands := make([]LocalTUICommand, 0, len(cr.local))
	for _, cmd := range cr.local {
		commands = append(commands, cmd)
	}
	
	// Sort by name for consistent ordering
	sort.Slice(commands, func(i, j int) bool {
		return commands[i].Name < commands[j].Name
	})
	
	return commands
}

// ListCommandsByCategory returns commands grouped by category
func (cr *CommandRegistry) ListCommandsByCategory() map[string][]CommandDefinition {
	cr.mu.RLock()
	defer cr.mu.RUnlock()
	
	categories := make(map[string][]CommandDefinition)
	
	for _, def := range cr.commands {
		category := def.Category
		if category == "" {
			category = "General"
		}
		categories[category] = append(categories[category], def)
	}
	
	// Sort commands within each category
	for category := range categories {
		sort.Slice(categories[category], func(i, j int) bool {
			return categories[category][i].Name < categories[category][j].Name
		})
	}
	
	return categories
}

// SearchCommands searches for commands by name or description
func (cr *CommandRegistry) SearchCommands(query string) []CommandDefinition {
	cr.mu.RLock()
	defer cr.mu.RUnlock()
	
	query = strings.ToLower(query)
	matches := []CommandDefinition{}
	
	for _, def := range cr.commands {
		// Check name match
		if strings.Contains(strings.ToLower(def.Name), query) {
			matches = append(matches, def)
			continue
		}
		
		// Check description match
		if strings.Contains(strings.ToLower(def.Description), query) {
			matches = append(matches, def)
			continue
		}
		
		// Check category match
		if strings.Contains(strings.ToLower(def.Category), query) {
			matches = append(matches, def)
			continue
		}
	}
	
	// Sort by relevance (exact name matches first)
	sort.Slice(matches, func(i, j int) bool {
		nameMatchI := strings.ToLower(matches[i].Name) == query
		nameMatchJ := strings.ToLower(matches[j].Name) == query
		
		if nameMatchI && !nameMatchJ {
			return true
		}
		if !nameMatchI && nameMatchJ {
			return false
		}
		
		return matches[i].Name < matches[j].Name
	})
	
	return matches
}

// GetCommandsByType returns commands filtered by type
func (cr *CommandRegistry) GetCommandsByType(commandType CommandType) []CommandDefinition {
	cr.mu.RLock()
	defer cr.mu.RUnlock()
	
	commands := []CommandDefinition{}
	
	for _, def := range cr.commands {
		if def.Type == commandType {
			commands = append(commands, def)
		}
	}
	
	sort.Slice(commands, func(i, j int) bool {
		return commands[i].Name < commands[j].Name
	})
	
	return commands
}

// GetCategories returns all available command categories
func (cr *CommandRegistry) GetCategories() []string {
	cr.mu.RLock()
	defer cr.mu.RUnlock()
	
	categorySet := make(map[string]bool)
	
	for _, def := range cr.commands {
		category := def.Category
		if category == "" {
			category = "General"
		}
		categorySet[category] = true
	}
	
	categories := make([]string, 0, len(categorySet))
	for category := range categorySet {
		categories = append(categories, category)
	}
	
	sort.Strings(categories)
	return categories
}

// ValidateCommand validates a command definition
func (cr *CommandRegistry) ValidateCommand(def CommandDefinition) []string {
	errors := []string{}
	
	if def.Name == "" {
		errors = append(errors, "command name is required")
	}
	
	if def.Description == "" {
		errors = append(errors, "command description is required")
	}
	
	// Validate arguments
	argNames := make(map[string]bool)
	for i, arg := range def.Args {
		if arg.Name == "" {
			errors = append(errors, "argument name is required at index %d", i)
			continue
		}
		
		if argNames[arg.Name] {
			errors = append(errors, "duplicate argument name: %s", arg.Name)
		}
		argNames[arg.Name] = true
		
		if !isValidArgType(arg.Type) {
			errors = append(errors, "invalid argument type '%s' for argument '%s'", arg.Type, arg.Name)
		}
	}
	
	// Validate options
	optionNames := make(map[string]bool)
	for i, opt := range def.Options {
		if opt.Name == "" {
			errors = append(errors, "option name is required at index %d", i)
			continue
		}
		
		if optionNames[opt.Name] {
			errors = append(errors, "duplicate option name: %s", opt.Name)
		}
		optionNames[opt.Name] = true
		
		if !isValidArgType(opt.Type) {
			errors = append(errors, "invalid option type '%s' for option '%s'", opt.Type, opt.Name)
		}
	}
	
	// Check for conflicting flags
	if def.LocalOnly && def.ServerOnly {
		errors = append(errors, "command cannot be both local-only and server-only")
	}
	
	return errors
}

// CommandExists checks if a command exists in the registry
func (cr *CommandRegistry) CommandExists(name string) bool {
	cr.mu.RLock()
	defer cr.mu.RUnlock()
	
	_, exists := cr.commands[name]
	return exists
}

// LocalCommandExists checks if a local command exists in the registry
func (cr *CommandRegistry) LocalCommandExists(name string) bool {
	cr.mu.RLock()
	defer cr.mu.RUnlock()
	
	_, exists := cr.local[name]
	return exists
}

// UnregisterCommand removes a command from the registry
func (cr *CommandRegistry) UnregisterCommand(name string) bool {
	cr.mu.Lock()
	defer cr.mu.Unlock()
	
	if _, exists := cr.commands[name]; exists {
		delete(cr.commands, name)
		return true
	}
	return false
}

// UnregisterLocalCommand removes a local command from the registry
func (cr *CommandRegistry) UnregisterLocalCommand(name string) bool {
	cr.mu.Lock()
	defer cr.mu.Unlock()
	
	if _, exists := cr.local[name]; exists {
		delete(cr.local, name)
		return true
	}
	return false
}

// GetCommandCount returns the total number of registered commands
func (cr *CommandRegistry) GetCommandCount() int {
	cr.mu.RLock()
	defer cr.mu.RUnlock()
	return len(cr.commands)
}

// GetLocalCommandCount returns the total number of registered local commands
func (cr *CommandRegistry) GetLocalCommandCount() int {
	cr.mu.RLock()
	defer cr.mu.RUnlock()
	return len(cr.local)
}

// Clear removes all commands from the registry
func (cr *CommandRegistry) Clear() {
	cr.mu.Lock()
	defer cr.mu.Unlock()
	
	cr.commands = make(map[string]CommandDefinition)
	cr.local = make(map[string]LocalTUICommand)
}

// GetCommandHelp returns formatted help text for a command
func (cr *CommandRegistry) GetCommandHelp(name string) string {
	def := cr.GetCommand(name)
	if def == nil {
		return "Command not found: " + name
	}
	
	help := "Command: " + def.Name + "\n"
	help += "Description: " + def.Description + "\n"
	
	if def.Category != "" {
		help += "Category: " + def.Category + "\n"
	}
	
	if len(def.Args) > 0 {
		help += "\nArguments:\n"
		for _, arg := range def.Args {
			required := ""
			if arg.Required {
				required = " (required)"
			}
			help += "  " + arg.Name + " (" + arg.Type + ")" + required + " - " + arg.Description + "\n"
		}
	}
	
	if len(def.Options) > 0 {
		help += "\nOptions:\n"
		for _, opt := range def.Options {
			required := ""
			if opt.Required {
				required = " (required)"
			}
			help += "  --" + opt.Name + " (" + opt.Type + ")" + required + " - " + opt.Description + "\n"
		}
	}
	
	if len(def.Examples) > 0 {
		help += "\nExamples:\n"
		for _, example := range def.Examples {
			help += "  " + example + "\n"
		}
	}
	
	return help
}

// Helper functions

func isValidArgType(argType string) bool {
	validTypes := []string{
		"string", "int", "float", "bool", 
		"file", "directory", "url", "email",
		"json", "array",
	}
	
	for _, validType := range validTypes {
		if argType == validType {
			return true
		}
	}
	return false
}