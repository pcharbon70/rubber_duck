package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/rubber_duck/tui/internal/phoenix"
	"github.com/rubber_duck/tui/internal/ui"
)

func main() {
	// Parse command line flags
	var (
		url      = flag.String("url", "ws://localhost:5555/socket", "Phoenix WebSocket URL (authenticated)")
		authURL  = flag.String("auth-url", "ws://localhost:5555/auth_socket", "Phoenix Auth WebSocket URL")
		apiKey   = flag.String("api-key", "", "API key for authentication")
		debug    = flag.Bool("debug", false, "Enable debug logging")
	)
	flag.Parse()
	
	// Load API key from various sources
	finalAPIKey := loadAPIKey(*apiKey)

	// Create the model
	model := ui.NewModel()
	
	// Configure Phoenix connection
	if *url != "" {
		model.SetPhoenixConfig(*url, *authURL, finalAPIKey)
	}

	// Create the program
	p := tea.NewProgram(model, tea.WithAltScreen())
	
	// Store program reference for UI components
	ui.SetProgramHolder(p)
	
	// Set up Phoenix client with program reference
	if phoenixClient := model.GetPhoenixClient(); phoenixClient != nil {
		if client, ok := phoenixClient.(*phoenix.Client); ok {
			client.SetProgram(p)
		}
	}
	
	// Set up Auth client with program reference
	if authClient := model.GetAuthClient(); authClient != nil {
		if client, ok := authClient.(*phoenix.AuthClient); ok {
			client.SetProgram(p)
		}
	}
	
	// Set up ApiKey client with program reference
	if apiKeyClient := model.GetApiKeyClient(); apiKeyClient != nil {
		if client, ok := apiKeyClient.(*phoenix.ApiKeyClient); ok {
			client.SetProgram(p)
		}
	}

	// Enable debug logging if requested
	if *debug {
		f, err := tea.LogToFile("debug.log", "debug")
		if err != nil {
			fmt.Fprintf(os.Stderr, "fatal: %v\n", err)
			os.Exit(1)
		}
		defer f.Close()
	}

	// Run the program
	if _, err := p.Run(); err != nil {
		log.Fatal(err)
	}
}

// loadAPIKey loads the API key from various sources in order of precedence:
// 1. Command line flag (if provided)
// 2. RUBBER_DUCK_API_KEY environment variable
// 3. ~/.rubber_duck/config.json file
func loadAPIKey(flagValue string) string {
	// 1. Command line flag takes precedence
	if flagValue != "" {
		return flagValue
	}
	
	// 2. Environment variable
	if envKey := os.Getenv("RUBBER_DUCK_API_KEY"); envKey != "" {
		return envKey
	}
	
	// 3. Config file
	homeDir, err := os.UserHomeDir()
	if err == nil {
		configPath := filepath.Join(homeDir, ".rubber_duck", "config.json")
		if data, err := os.ReadFile(configPath); err == nil {
			var config map[string]interface{}
			if err := json.Unmarshal(data, &config); err == nil {
				if apiKey, ok := config["api_key"].(string); ok && apiKey != "" {
					return apiKey
				}
			}
		}
	}
	
	return ""
}