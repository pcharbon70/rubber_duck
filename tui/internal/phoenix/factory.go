package phoenix

import (
	"os"
	"strings"
	"time"
)

// NewPhoenixClient creates either a real or mock Phoenix client based on configuration
func NewPhoenixClient() PhoenixClient {
	// Check environment variable for client type
	clientType := strings.ToLower(os.Getenv("RUBBER_DUCK_CLIENT_TYPE"))
	
	// Check if we should use mock mode
	if clientType == "mock" || shouldUseMock() {
		return NewMockClient()
	}
	
	return NewRealClient()
}

// shouldUseMock determines if we should use mock mode based on various factors
func shouldUseMock() bool {
	// Use mock if explicitly requested
	if os.Getenv("RUBBER_DUCK_USE_MOCK") == "true" {
		return true
	}
	
	// Use mock in development mode
	if isDevelopmentMode() {
		return true
	}
	
	// Use mock if no server URL is configured
	if os.Getenv("RUBBER_DUCK_SERVER_URL") == "" {
		return true
	}
	
	return false
}

// isDevelopmentMode checks if we're running in development mode
func isDevelopmentMode() bool {
	env := strings.ToLower(os.Getenv("RUBBER_DUCK_ENV"))
	return env == "development" || env == "dev" || env == ""
}

// Configuration helper functions

// GetServerURL returns the configured server URL or default
func GetServerURL() string {
	url := os.Getenv("RUBBER_DUCK_SERVER_URL")
	if url == "" {
		return "ws://localhost:5555/socket"  // Default Phoenix server URL
	}
	return url
}

// GetAPIKey returns the configured API key
func GetAPIKey() string {
	return os.Getenv("RUBBER_DUCK_API_KEY")
}

// GetChannelTopic returns the configured channel topic or default
func GetChannelTopic() string {
	topic := os.Getenv("RUBBER_DUCK_CHANNEL_TOPIC")
	if topic == "" {
		return "cli:commands"  // Default channel topic
	}
	return topic
}

// CreateConfig creates a Phoenix client configuration with defaults
func CreateConfig() Config {
	return Config{
		URL:       GetServerURL(),
		APIKey:    GetAPIKey(),
		ChannelID: GetChannelTopic(),
	}
}

// Development helpers

// NewMockClientWithOptions creates a mock client with custom options
func NewMockClientWithOptions(options MockOptions) PhoenixClient {
	mock := NewMockClient()
	
	if mockClient, ok := mock.(*MockClient); ok {
		if options.NetworkDelay > 0 {
			mockClient.SetNetworkDelay(options.NetworkDelay)
		}
		if options.ErrorRate >= 0 {
			mockClient.SetErrorRate(options.ErrorRate)
		}
		if options.StreamingSpeed > 0 {
			mockClient.SetStreamingSpeed(options.StreamingSpeed)
		}
	}
	
	return mock
}

// MockOptions holds configuration options for the mock client
type MockOptions struct {
	NetworkDelay    time.Duration
	ErrorRate       float64
	StreamingSpeed  time.Duration
}

// EnableMockMode forces the use of mock client for testing
func EnableMockMode() {
	os.Setenv("RUBBER_DUCK_USE_MOCK", "true")
}

// DisableMockMode forces the use of real client
func DisableMockMode() {
	os.Setenv("RUBBER_DUCK_USE_MOCK", "false")
	os.Setenv("RUBBER_DUCK_CLIENT_TYPE", "real")
}

// IsRunningInMockMode returns true if mock mode is active
func IsRunningInMockMode() bool {
	return shouldUseMock()
}