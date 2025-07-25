package phoenix

import (
	"fmt"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/nshafer/phx"
)

// ApiKeyClient handles API key channel operations
type ApiKeyClient struct {
	socket    *phx.Socket
	channel   *phx.Channel
	program   *tea.Program
	userID    string
}

// NewApiKeyClient creates a new API key client
func NewApiKeyClient() *ApiKeyClient {
	return &ApiKeyClient{}
}

// SetSocket sets the Phoenix socket (must be authenticated user socket)
func (a *ApiKeyClient) SetSocket(socket *phx.Socket) {
	a.socket = socket
}

// SetProgram sets the tea.Program for sending messages
func (a *ApiKeyClient) SetProgram(program *tea.Program) {
	a.program = program
}

// SetUserID sets the user ID for the channel topic
func (a *ApiKeyClient) SetUserID(userID string) {
	a.userID = userID
}

// JoinApiKeyChannel joins the api_keys channel for the user
func (a *ApiKeyClient) JoinApiKeyChannel() tea.Cmd {
	return func() tea.Msg {
		if a.socket == nil {
			return ErrorMsg{
				Err:       fmt.Errorf("socket not connected"),
				Component: "ApiKey Client",
			}
		}
		
		if a.userID == "" {
			return ErrorMsg{
				Err:       fmt.Errorf("user ID not set"),
				Component: "ApiKey Client",
			}
		}
		
		// Join api_keys:manage channel
		channelName := "api_keys:manage"
		channel := a.socket.Channel(channelName, nil)
		
		// Set up event handlers
		a.setupApiKeyHandlers(channel)
		
		// Join the channel
		join, err := channel.Join()
		if err != nil {
			return ErrorMsg{
				Err:       fmt.Errorf("failed to join api_keys channel: %w", err),
				Component: "ApiKey Client",
			}
		}
		
		// Handle join responses
		join.Receive("ok", func(response any) {
			a.channel = channel
			if a.program != nil {
				a.program.Send(ApiKeyChannelJoinedMsg{})
			}
		})
		
		join.Receive("error", func(response any) {
			if a.program != nil {
				a.program.Send(ErrorMsg{
					Err:       fmt.Errorf("api_keys channel join rejected: %v", response),
					Component: "ApiKey Client",
				})
			}
		})
		
		join.Receive("timeout", func(response any) {
			if a.program != nil {
				a.program.Send(ErrorMsg{
					Err:       fmt.Errorf("api_keys channel join timeout"),
					Component: "ApiKey Client",
				})
			}
		})
		
		return nil
	}
}

// setupApiKeyHandlers sets up event handlers for api_keys channel
func (a *ApiKeyClient) setupApiKeyHandlers(channel *phx.Channel) {
	// API key generated
	channel.On("api_key_generated", func(payload any) {
		var msg struct {
			APIKey struct {
				ID        string `json:"id"`
				Key       string `json:"key"`
				CreatedAt string `json:"created_at"`
				ExpiresAt string `json:"expires_at"`
			} `json:"api_key"`
			Warning string `json:"warning"`
		}
		
		if data, ok := payload.(map[string]any); ok {
			// Parse the response
			if apiKeyData, ok := data["api_key"].(map[string]any); ok {
				msg.APIKey.ID = getString(apiKeyData, "id")
				msg.APIKey.Key = getString(apiKeyData, "key")
				msg.APIKey.CreatedAt = getString(apiKeyData, "created_at")
				msg.APIKey.ExpiresAt = getString(apiKeyData, "expires_at")
			}
			msg.Warning = getString(data, "warning")
		}
		
		// Parse timestamps
		var createdAt, expiresAt time.Time
		if msg.APIKey.CreatedAt != "" {
			createdAt, _ = time.Parse(time.RFC3339, msg.APIKey.CreatedAt)
		}
		if msg.APIKey.ExpiresAt != "" {
			expiresAt, _ = time.Parse(time.RFC3339, msg.APIKey.ExpiresAt)
		}
		
		if a.program != nil {
			a.program.Send(APIKeyGeneratedMsg{
				APIKey: APIKey{
					ID:        msg.APIKey.ID,
					Key:       msg.APIKey.Key,
					CreatedAt: createdAt,
					ExpiresAt: expiresAt,
				},
				Warning: msg.Warning,
			})
		}
	})
	
	// API keys listed
	channel.On("api_key_list", func(payload any) {
		var apiKeys []APIKey
		
		if data, ok := payload.(map[string]any); ok {
			if keysData, ok := data["api_keys"].([]any); ok {
				for _, keyData := range keysData {
					if key, ok := keyData.(map[string]any); ok {
						var apiKey APIKey
						apiKey.ID = getString(key, "id")
						apiKey.Valid = getBool(key, "valid")
						
						if createdStr := getString(key, "created_at"); createdStr != "" {
							apiKey.CreatedAt, _ = time.Parse(time.RFC3339, createdStr)
						}
						if expiresStr := getString(key, "expires_at"); expiresStr != "" {
							apiKey.ExpiresAt, _ = time.Parse(time.RFC3339, expiresStr)
						}
						
						apiKeys = append(apiKeys, apiKey)
					}
				}
			}
		}
		
		if a.program != nil {
			a.program.Send(APIKeyListMsg{
				APIKeys: apiKeys,
				Count:   len(apiKeys),
			})
		}
	})
	
	// API key revoked
	channel.On("api_key_revoked", func(payload any) {
		message := "API key revoked successfully"
		if data, ok := payload.(map[string]any); ok {
			if msg, ok := data["message"].(string); ok {
				message = msg
			}
		}
		
		if a.program != nil {
			a.program.Send(APIKeyRevokedMsg{
				Message: message,
			})
		}
	})
	
	// API key error
	channel.On("api_key_error", func(payload any) {
		var operation, message, details string
		
		if data, ok := payload.(map[string]any); ok {
			operation = getString(data, "operation")
			message = getString(data, "message")
			details = getString(data, "details")
		}
		
		if a.program != nil {
			a.program.Send(APIKeyErrorMsg{
				Operation: operation,
				Message:   message,
				Details:   details,
			})
		}
	})
}

// GenerateAPIKey generates a new API key
func (a *ApiKeyClient) GenerateAPIKey(params map[string]any) tea.Cmd {
	return func() tea.Msg {
		if a.channel == nil {
			return ErrorMsg{
				Err:       fmt.Errorf("api_keys channel not joined"),
				Component: "ApiKey Client",
			}
		}
		
		push, err := a.channel.Push("generate_api_key", nil)
		if err != nil {
			return ErrorMsg{
				Err:       fmt.Errorf("failed to generate API key: %w", err),
				Component: "ApiKey Client",
			}
		}
		
		// Handle responses
		push.Receive("ok", func(response any) {
			// Response will be handled by the event handler
		})
		
		push.Receive("error", func(response any) {
			if a.program != nil {
				a.program.Send(APIKeyErrorMsg{
					Operation: "generate",
					Message:   "Failed to generate API key",
					Details:   fmt.Sprintf("%v", response),
				})
			}
		})
		
		push.Receive("timeout", func(response any) {
			// API key generation uses channel events for success, ignore push timeout
		})
		
		return nil
	}
}

// ListAPIKeys lists all API keys for the user
func (a *ApiKeyClient) ListAPIKeys() tea.Cmd {
	return func() tea.Msg {
		if a.channel == nil {
			return ErrorMsg{
				Err:       fmt.Errorf("api_keys channel not joined"),
				Component: "ApiKey Client",
			}
		}
		
		push, err := a.channel.Push("list_api_keys", nil)
		if err != nil {
			return ErrorMsg{
				Err:       fmt.Errorf("failed to list API keys: %w", err),
				Component: "ApiKey Client",
			}
		}
		
		// Handle responses
		push.Receive("ok", func(response any) {
			// Response will be handled by the event handler
		})
		
		push.Receive("error", func(response any) {
			if a.program != nil {
				a.program.Send(APIKeyErrorMsg{
					Operation: "list",
					Message:   "Failed to list API keys",
					Details:   fmt.Sprintf("%v", response),
				})
			}
		})
		
		push.Receive("timeout", func(response any) {
			// API key list uses channel events for success, ignore push timeout
		})
		
		return nil
	}
}

// RevokeAPIKey revokes a specific API key
func (a *ApiKeyClient) RevokeAPIKey(keyID string) tea.Cmd {
	return func() tea.Msg {
		if a.channel == nil {
			return ErrorMsg{
				Err:       fmt.Errorf("api_keys channel not joined"),
				Component: "ApiKey Client",
			}
		}
		
		params := map[string]any{
			"api_key_id": keyID,
		}
		
		push, err := a.channel.Push("revoke_api_key", params)
		if err != nil {
			return ErrorMsg{
				Err:       fmt.Errorf("failed to revoke API key: %w", err),
				Component: "ApiKey Client",
			}
		}
		
		// Handle responses
		push.Receive("ok", func(response any) {
			// Response will be handled by the event handler
		})
		
		push.Receive("error", func(response any) {
			if a.program != nil {
				a.program.Send(APIKeyErrorMsg{
					Operation: "revoke",
					Message:   "Failed to revoke API key",
					Details:   fmt.Sprintf("%v", response),
				})
			}
		})
		
		push.Receive("timeout", func(response any) {
			// API key revoke uses channel events for success, ignore push timeout
		})
		
		return nil
	}
}

// LeaveChannel leaves the api_keys channel
func (a *ApiKeyClient) LeaveChannel() {
	if a.channel != nil {
		a.channel.Leave()
		a.channel = nil
	}
}

// Helper functions
func getString(data map[string]any, key string) string {
	if val, ok := data[key].(string); ok {
		return val
	}
	return ""
}

func getBool(data map[string]any, key string) bool {
	if val, ok := data[key].(bool); ok {
		return val
	}
	return false
}

// Message types for API key channel

type ApiKeyChannelJoinedMsg struct{}