package phoenix

import "time"

// Auth Channel Message Types

// AuthConnectedMsg is sent when connected to auth channel
type AuthConnectedMsg struct{}

// AuthChannelJoinedMsg is sent when auth channel is joined
type AuthChannelJoinedMsg struct{}

// LoginRequestMsg requests login
type LoginRequestMsg struct {
	Username string
	Password string
}

// LoginSuccessMsg is sent when login succeeds
type LoginSuccessMsg struct {
	User  AuthUser
	Token string
}

// LoginErrorMsg is sent when login fails
type LoginErrorMsg struct {
	Message string
	Details string
}

// LogoutSuccessMsg is sent when logout succeeds
type LogoutSuccessMsg struct {
	Message string
}

// LogoutErrorMsg is sent when logout fails
type LogoutErrorMsg struct {
	Message string
}

// AuthStatusMsg contains authentication status
type AuthStatusMsg struct {
	Authenticated   bool
	User           *AuthUser
	AuthenticatedAt *time.Time
}

// APIKeyGeneratedMsg is sent when API key is generated
type APIKeyGeneratedMsg struct {
	APIKey  APIKey
	Warning string
}

// APIKeyListMsg contains list of API keys
type APIKeyListMsg struct {
	APIKeys []APIKey
	Count   int
}

// APIKeyRevokedMsg is sent when API key is revoked
type APIKeyRevokedMsg struct {
	APIKeyID string
	Message  string
}

// APIKeyErrorMsg is sent when API key operation fails
type APIKeyErrorMsg struct {
	Operation string
	Message   string
	Details   string
}

// TokenRefreshedMsg is sent when token is refreshed
type TokenRefreshedMsg struct {
	User  AuthUser
	Token string
}

// TokenErrorMsg is sent when token operation fails
type TokenErrorMsg struct {
	Message string
	Details string
}

// AuthUser represents an authenticated user
type AuthUser struct {
	ID       string `json:"id"`
	Username string `json:"username"`
	Email    string `json:"email"`
}

// APIKey represents an API key
type APIKey struct {
	ID        string    `json:"id"`
	Key       string    `json:"key,omitempty"` // Only present when generated
	ExpiresAt time.Time `json:"expires_at"`
	Valid     bool      `json:"valid"`
	CreatedAt time.Time `json:"created_at"`
}