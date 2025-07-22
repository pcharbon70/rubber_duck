package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"path/filepath"
	"strings"
	"syscall"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/rubber_duck/tui/internal/phoenix"
	"github.com/rubber_duck/tui/internal/ui"
)

func init() {
	// Suppress logging at the earliest possible moment - even before main()
	log.SetOutput(ioutil.Discard)
	log.SetFlags(0)
	log.SetPrefix("")
}

func main() {
	// Re-ensure logging is suppressed (belt and suspenders)
	log.SetOutput(ioutil.Discard)
	log.SetFlags(0)
	
	// Parse command line flags
	var (
		url      = flag.String("url", "ws://localhost:5555/socket", "Phoenix WebSocket URL (authenticated)")
		authURL  = flag.String("auth-url", "ws://localhost:5555/auth_socket", "Phoenix Auth WebSocket URL")
		apiKey   = flag.String("api-key", "", "API key for authentication")
		debug    = flag.Bool("debug", false, "Enable debug logging")
	)
	flag.Parse()
	
	// More aggressive suppression for non-debug mode
	if !*debug {
		// Create a devnull file
		devNull, err := os.OpenFile(os.DevNull, os.O_WRONLY, 0755)
		if err == nil {
			// Redirect stderr file descriptor directly using dup2
			// This catches output at the lowest level
			err = syscall.Dup2(int(devNull.Fd()), 2) // 2 is stderr
			if err != nil {
				// Fallback to high-level redirect
				os.Stderr = devNull
			}
		}
		
		// Additional suppression: disable all Go default loggers
		log.SetOutput(ioutil.Discard)
		log.SetFlags(0)
		log.SetPrefix("")
		
		// Clear any existing terminal content that might interfere
		fmt.Print("\033[2J\033[H") // Clear screen and move cursor to top
		
		// Additional terminal control to prevent output leakage
		fmt.Print("\033[?1049h") // Save screen and use alternate buffer
		fmt.Print("\033[3J")     // Clear scrollback buffer
	}
	
	// Load API key from various sources
	finalAPIKey := loadAPIKey(*apiKey)

	// Create the model
	model := ui.NewModel()
	
	// Configure Phoenix connection
	if *url != "" {
		model.SetPhoenixConfig(*url, *authURL, finalAPIKey)
	}

	// Create the program with additional options to ensure full terminal usage
	p := tea.NewProgram(model, 
		tea.WithAltScreen(),     // Use alternate screen buffer
		tea.WithMouseCellMotion(), // Enable mouse support
		tea.WithoutCatchPanics(), // Let us handle panics
		tea.WithInputTTY(),       // Force TTY input handling
	)
	
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

	// Enable debug logging if requested (stderr redirection already handled above)
	if *debug {
		// Re-enable stderr for debug mode
		f, err := tea.LogToFile("debug.log", "debug")
		if err != nil {
			fmt.Fprintf(os.Stderr, "fatal: %v\n", err)
			os.Exit(1)
		}
		defer f.Close()
		// Re-enable standard logging for debug
		log.SetOutput(f)
		log.SetFlags(log.LstdFlags)
	}

	// Set up cleanup on exit
	defer func() {
		if !*debug {
			// Restore terminal state
			fmt.Print("\033[?1049l") // Restore screen from alternate buffer
			fmt.Print("\033[2J\033[H") // Clear screen one more time
		}
	}()
	
	// Run the program with better error handling
	if _, err := p.Run(); err != nil {
		// Don't use log.Fatal as it might output to stderr
		if *debug {
			fmt.Fprintln(os.Stderr, "TUI Error:", err)
		}
		os.Exit(1)
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

// containsErrorMarkers checks if output contains error message markers
func containsErrorMarkers(output string) bool {
	errorMarkers := []string{
		"[ERROR]",
		"[WARN]",
		"Connection error:",
		"dial tcp",
		"connection refused",
		"<socket>",
		"<channel>",
	}
	
	for _, marker := range errorMarkers {
		if strings.Contains(output, marker) {
			return true
		}
	}
	return false
}