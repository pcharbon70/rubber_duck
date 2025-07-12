package phoenix

import (
	"os"
	"testing"
	"time"
)

// TestFactoryClientSelection tests the factory's client selection logic
func TestFactoryClientSelection(t *testing.T) {
	// Save original environment
	originalEnv := map[string]string{
		"RUBBER_DUCK_CLIENT_TYPE": os.Getenv("RUBBER_DUCK_CLIENT_TYPE"),
		"RUBBER_DUCK_USE_MOCK":    os.Getenv("RUBBER_DUCK_USE_MOCK"),
		"RUBBER_DUCK_ENV":         os.Getenv("RUBBER_DUCK_ENV"),
		"RUBBER_DUCK_SERVER_URL":  os.Getenv("RUBBER_DUCK_SERVER_URL"),
	}
	
	// Restore environment after test
	defer func() {
		for key, value := range originalEnv {
			if value == "" {
				os.Unsetenv(key)
			} else {
				os.Setenv(key, value)
			}
		}
	}()
	
	tests := []struct {
		name     string
		envVars  map[string]string
		wantMock bool
	}{
		{
			name: "explicit mock type",
			envVars: map[string]string{
				"RUBBER_DUCK_CLIENT_TYPE": "mock",
			},
			wantMock: true,
		},
		{
			name: "explicit real type",
			envVars: map[string]string{
				"RUBBER_DUCK_CLIENT_TYPE": "real",
				"RUBBER_DUCK_SERVER_URL":  "ws://localhost:5555/socket",
			},
			wantMock: false,
		},
		{
			name: "explicit use mock flag",
			envVars: map[string]string{
				"RUBBER_DUCK_USE_MOCK": "true",
			},
			wantMock: true,
		},
		{
			name: "development environment",
			envVars: map[string]string{
				"RUBBER_DUCK_ENV": "development",
			},
			wantMock: true,
		},
		{
			name: "production environment with server URL",
			envVars: map[string]string{
				"RUBBER_DUCK_ENV":        "production",
				"RUBBER_DUCK_SERVER_URL": "ws://production.server/socket",
			},
			wantMock: false,
		},
		{
			name: "no server URL defaults to mock",
			envVars: map[string]string{
				"RUBBER_DUCK_ENV": "production",
			},
			wantMock: true,
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Clear environment
			os.Unsetenv("RUBBER_DUCK_CLIENT_TYPE")
			os.Unsetenv("RUBBER_DUCK_USE_MOCK")
			os.Unsetenv("RUBBER_DUCK_ENV")
			os.Unsetenv("RUBBER_DUCK_SERVER_URL")
			
			// Set test environment
			for key, value := range tt.envVars {
				os.Setenv(key, value)
			}
			
			client := NewPhoenixClient()
			
			// Check if we got the expected client type
			_, isMock := client.(*MockClient)
			_, isReal := client.(*RealClient)
			
			if tt.wantMock && !isMock {
				t.Errorf("Expected MockClient, got %T", client)
			}
			if !tt.wantMock && !isReal {
				t.Errorf("Expected RealClient, got %T", client)
			}
		})
	}
}

// TestFactoryHelperFunctions tests the factory helper functions
func TestFactoryHelperFunctions(t *testing.T) {
	// Save original environment
	originalEnv := map[string]string{
		"RUBBER_DUCK_SERVER_URL":     os.Getenv("RUBBER_DUCK_SERVER_URL"),
		"RUBBER_DUCK_API_KEY":        os.Getenv("RUBBER_DUCK_API_KEY"),
		"RUBBER_DUCK_CHANNEL_TOPIC":  os.Getenv("RUBBER_DUCK_CHANNEL_TOPIC"),
	}
	
	// Restore environment after test
	defer func() {
		for key, value := range originalEnv {
			if value == "" {
				os.Unsetenv(key)
			} else {
				os.Setenv(key, value)
			}
		}
	}()
	
	t.Run("GetServerURL with default", func(t *testing.T) {
		os.Unsetenv("RUBBER_DUCK_SERVER_URL")
		
		url := GetServerURL()
		expected := "ws://localhost:5555/socket"
		if url != expected {
			t.Errorf("Expected %s, got %s", expected, url)
		}
	})
	
	t.Run("GetServerURL with custom value", func(t *testing.T) {
		customURL := "ws://custom.server/socket"
		os.Setenv("RUBBER_DUCK_SERVER_URL", customURL)
		
		url := GetServerURL()
		if url != customURL {
			t.Errorf("Expected %s, got %s", customURL, url)
		}
	})
	
	t.Run("GetAPIKey", func(t *testing.T) {
		testKey := "test-api-key-123"
		os.Setenv("RUBBER_DUCK_API_KEY", testKey)
		
		key := GetAPIKey()
		if key != testKey {
			t.Errorf("Expected %s, got %s", testKey, key)
		}
	})
	
	t.Run("GetChannelTopic with default", func(t *testing.T) {
		os.Unsetenv("RUBBER_DUCK_CHANNEL_TOPIC")
		
		topic := GetChannelTopic()
		expected := "cli:commands"
		if topic != expected {
			t.Errorf("Expected %s, got %s", expected, topic)
		}
	})
	
	t.Run("CreateConfig", func(t *testing.T) {
		os.Setenv("RUBBER_DUCK_SERVER_URL", "ws://test.server/socket")
		os.Setenv("RUBBER_DUCK_API_KEY", "test-key")
		os.Setenv("RUBBER_DUCK_CHANNEL_TOPIC", "test:channel")
		
		config := CreateConfig()
		
		if config.URL != "ws://test.server/socket" {
			t.Errorf("Expected URL ws://test.server/socket, got %s", config.URL)
		}
		if config.APIKey != "test-key" {
			t.Errorf("Expected API key test-key, got %s", config.APIKey)
		}
		if config.ChannelID != "test:channel" {
			t.Errorf("Expected channel ID test:channel, got %s", config.ChannelID)
		}
	})
}

// TestMockClientWithOptions tests creating mock clients with custom options
func TestMockClientWithOptions(t *testing.T) {
	options := MockOptions{
		NetworkDelay:   50 * time.Millisecond,
		ErrorRate:      0.2,
		StreamingSpeed: 25 * time.Millisecond,
	}
	
	client := NewMockClientWithOptions(options)
	
	if client == nil {
		t.Fatal("Expected non-nil client")
	}
	
	mockClient, ok := client.(*MockClient)
	if !ok {
		t.Fatalf("Expected MockClient, got %T", client)
	}
	
	// Test that options were applied by checking behavior
	start := time.Now()
	cmd := mockClient.ListFiles(".")
	cmd()
	elapsed := time.Since(start)
	
	// Should have at least the configured delay
	if elapsed < 45*time.Millisecond {
		t.Errorf("Expected delay of at least 45ms, got %v", elapsed)
	}
}

// TestMockModeEnableDisable tests the mock mode control functions
func TestMockModeEnableDisable(t *testing.T) {
	// Save original environment
	originalUseMock := os.Getenv("RUBBER_DUCK_USE_MOCK")
	originalClientType := os.Getenv("RUBBER_DUCK_CLIENT_TYPE")
	
	// Restore environment after test
	defer func() {
		if originalUseMock == "" {
			os.Unsetenv("RUBBER_DUCK_USE_MOCK")
		} else {
			os.Setenv("RUBBER_DUCK_USE_MOCK", originalUseMock)
		}
		if originalClientType == "" {
			os.Unsetenv("RUBBER_DUCK_CLIENT_TYPE")
		} else {
			os.Setenv("RUBBER_DUCK_CLIENT_TYPE", originalClientType)
		}
	}()
	
	t.Run("EnableMockMode", func(t *testing.T) {
		EnableMockMode()
		
		if os.Getenv("RUBBER_DUCK_USE_MOCK") != "true" {
			t.Error("Expected RUBBER_DUCK_USE_MOCK to be set to true")
		}
		
		if !IsRunningInMockMode() {
			t.Error("Expected IsRunningInMockMode to return true")
		}
		
		client := NewPhoenixClient()
		if _, ok := client.(*MockClient); !ok {
			t.Errorf("Expected MockClient after EnableMockMode, got %T", client)
		}
	})
	
	t.Run("DisableMockMode", func(t *testing.T) {
		// First enable mock mode
		EnableMockMode()
		
		// Then disable it
		DisableMockMode()
		
		if os.Getenv("RUBBER_DUCK_USE_MOCK") != "false" {
			t.Error("Expected RUBBER_DUCK_USE_MOCK to be set to false")
		}
		
		if os.Getenv("RUBBER_DUCK_CLIENT_TYPE") != "real" {
			t.Error("Expected RUBBER_DUCK_CLIENT_TYPE to be set to real")
		}
		
		// Note: IsRunningInMockMode might still return true if no server URL is set
		// but the client type should be forced to real
		client := NewPhoenixClient()
		if _, ok := client.(*RealClient); !ok {
			t.Errorf("Expected RealClient after DisableMockMode, got %T", client)
		}
	})
}

// TestDevelopmentModeDetection tests the development mode detection logic
func TestDevelopmentModeDetection(t *testing.T) {
	// Save original environment
	originalEnv := os.Getenv("RUBBER_DUCK_ENV")
	
	// Restore environment after test
	defer func() {
		if originalEnv == "" {
			os.Unsetenv("RUBBER_DUCK_ENV")
		} else {
			os.Setenv("RUBBER_DUCK_ENV", originalEnv)
		}
	}()
	
	tests := []struct {
		name    string
		envValue string
		wantDev bool
	}{
		{name: "empty env", envValue: "", wantDev: true},
		{name: "development", envValue: "development", wantDev: true},
		{name: "dev", envValue: "dev", wantDev: true},
		{name: "DEV uppercase", envValue: "DEV", wantDev: true},
		{name: "DEVELOPMENT uppercase", envValue: "DEVELOPMENT", wantDev: true},
		{name: "production", envValue: "production", wantDev: false},
		{name: "prod", envValue: "prod", wantDev: false},
		{name: "staging", envValue: "staging", wantDev: false},
		{name: "test", envValue: "test", wantDev: false},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.envValue == "" {
				os.Unsetenv("RUBBER_DUCK_ENV")
			} else {
				os.Setenv("RUBBER_DUCK_ENV", tt.envValue)
			}
			
			isDev := isDevelopmentMode()
			if isDev != tt.wantDev {
				t.Errorf("Expected isDevelopmentMode() = %v, got %v", tt.wantDev, isDev)
			}
		})
	}
}

// TestShouldUseMockLogic tests the shouldUseMock decision logic
func TestShouldUseMockLogic(t *testing.T) {
	// Save original environment
	originalEnv := map[string]string{
		"RUBBER_DUCK_USE_MOCK":   os.Getenv("RUBBER_DUCK_USE_MOCK"),
		"RUBBER_DUCK_ENV":        os.Getenv("RUBBER_DUCK_ENV"),
		"RUBBER_DUCK_SERVER_URL": os.Getenv("RUBBER_DUCK_SERVER_URL"),
	}
	
	// Restore environment after test
	defer func() {
		for key, value := range originalEnv {
			if value == "" {
				os.Unsetenv(key)
			} else {
				os.Setenv(key, value)
			}
		}
	}()
	
	tests := []struct {
		name     string
		envVars  map[string]string
		wantMock bool
	}{
		{
			name: "explicit use mock true",
			envVars: map[string]string{
				"RUBBER_DUCK_USE_MOCK": "true",
			},
			wantMock: true,
		},
		{
			name: "explicit use mock false with server URL",
			envVars: map[string]string{
				"RUBBER_DUCK_USE_MOCK":   "false",
				"RUBBER_DUCK_SERVER_URL": "ws://server/socket",
			},
			wantMock: false,
		},
		{
			name: "development mode",
			envVars: map[string]string{
				"RUBBER_DUCK_ENV": "development",
			},
			wantMock: true,
		},
		{
			name: "production mode with server URL",
			envVars: map[string]string{
				"RUBBER_DUCK_ENV":        "production",
				"RUBBER_DUCK_SERVER_URL": "ws://server/socket",
			},
			wantMock: false,
		},
		{
			name: "no server URL",
			envVars: map[string]string{
				"RUBBER_DUCK_ENV": "production",
			},
			wantMock: true,
		},
	}
	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Clear environment
			os.Unsetenv("RUBBER_DUCK_USE_MOCK")
			os.Unsetenv("RUBBER_DUCK_ENV")
			os.Unsetenv("RUBBER_DUCK_SERVER_URL")
			
			// Set test environment
			for key, value := range tt.envVars {
				os.Setenv(key, value)
			}
			
			useMock := shouldUseMock()
			if useMock != tt.wantMock {
				t.Errorf("Expected shouldUseMock() = %v, got %v", tt.wantMock, useMock)
			}
			
			isRunningMock := IsRunningInMockMode()
			if isRunningMock != tt.wantMock {
				t.Errorf("Expected IsRunningInMockMode() = %v, got %v", tt.wantMock, isRunningMock)
			}
		})
	}
}