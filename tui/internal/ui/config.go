package ui

import (
	"encoding/json"
	"os"
	"path/filepath"
)

// Config represents the TUI configuration
type Config struct {
	APIKey          string                    `json:"api_key,omitempty"`
	DefaultProvider string                    `json:"default_provider,omitempty"`
	DefaultModel    string                    `json:"default_model,omitempty"`
	Providers       map[string]ProviderConfig `json:"providers"`
	TUI             TUIConfig                 `json:"tui"`
}

// ProviderConfig represents provider configuration
type ProviderConfig struct {
	APIKey string   `json:"api_key"`
	Models []string `json:"models"`
}

// TUIConfig represents TUI-specific configuration
type TUIConfig struct {
	StatusCategoryColors map[string]string `json:"status_category_colors"`
}

// LoadConfig loads configuration from the user's config file
func LoadConfig() (*Config, error) {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}
	
	configPath := filepath.Join(homeDir, ".rubber_duck", "config.json")
	
	// Check if config file exists
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		// Return empty config if file doesn't exist
		return &Config{
			Providers: make(map[string]ProviderConfig),
			TUI: TUIConfig{
				StatusCategoryColors: make(map[string]string),
			},
		}, nil
	}
	
	// Read config file
	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil, err
	}
	
	// Parse JSON
	var config Config
	if err := json.Unmarshal(data, &config); err != nil {
		return nil, err
	}
	
	// Ensure maps are initialized
	if config.TUI.StatusCategoryColors == nil {
		config.TUI.StatusCategoryColors = make(map[string]string)
	}
	
	return &config, nil
}

// GetCategoryColor returns the configured color for a category, or the default
func (c *Config) GetCategoryColor(category string, defaultColor string) string {
	if c.TUI.StatusCategoryColors != nil {
		if color, exists := c.TUI.StatusCategoryColors[category]; exists {
			return color
		}
	}
	return defaultColor
}

// SaveConfig saves the configuration to the user's config file
func SaveConfig(config *Config) error {
	homeDir, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	
	configDir := filepath.Join(homeDir, ".rubber_duck")
	configPath := filepath.Join(configDir, "config.json")
	
	// Ensure config directory exists
	if err := os.MkdirAll(configDir, 0755); err != nil {
		return err
	}
	
	// Marshal config to JSON with indentation
	data, err := json.MarshalIndent(config, "", "  ")
	if err != nil {
		return err
	}
	
	// Write to file
	return os.WriteFile(configPath, data, 0644)
}

