package phoenix

import (
	"encoding/json"
	"fmt"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/nshafer/phx"
)

// AuthClient handles authentication operations via Phoenix auth channel
type AuthClient struct {
	socket      *phx.Socket
	authChannel *phx.Channel
	program     *tea.Program
	connected   bool
	joining     bool // Track if join is in progress
}

// NewAuthClient creates a new auth client
func NewAuthClient() *AuthClient {
	return &AuthClient{}
}

// SetProgram sets the tea.Program for sending messages
func (a *AuthClient) SetProgram(program *tea.Program) {
	a.program = program
}

// SetSocket sets the Phoenix socket (shared with main client)
func (a *AuthClient) SetSocket(socket *phx.Socket) {
	a.socket = socket
}

// JoinAuthChannel joins the auth:lobby channel
func (a *AuthClient) JoinAuthChannel() tea.Cmd {
	return func() tea.Msg {
		if a.socket == nil {
			return ErrorMsg{
				Err:       fmt.Errorf("socket not connected"),
				Component: "Auth Client",
			}
		}

		// Check if already connected or joining
		if a.connected || a.joining {
			// This is not an error, just skip the duplicate join
			return nil
		}

		// Mark as joining
		a.joining = true

		// Join auth:lobby channel
		channel := a.socket.Channel("auth:lobby", map[string]string{})
		
		join, err := channel.Join()
		if err != nil {
			return ErrorMsg{
				Err:       err,
				Component: "Auth Channel Join",
			}
		}

		// Handle join response
		join.Receive("ok", func(response any) {
			a.connected = true
			a.joining = false
			if a.program != nil {
				a.program.Send(AuthChannelJoinedMsg{})
			}
		})

		join.Receive("error", func(response any) {
			a.joining = false
			if a.program != nil {
				a.program.Send(ErrorMsg{
					Err:       fmt.Errorf("failed to join auth channel: %v", response),
					Component: "Auth Channel Join",
				})
			}
		})

		// Set up auth channel handlers
		a.setupAuthHandlers(channel)
		a.authChannel = channel

		return AuthConnectedMsg{}
	}
}

// setupAuthHandlers sets up event handlers for auth channel
func (a *AuthClient) setupAuthHandlers(channel *phx.Channel) {
	// Login success
	channel.On("login_success", func(payload any) {
		var msg struct {
			User  AuthUser `json:"user"`
			Token string   `json:"token"`
		}
		if data, err := json.Marshal(payload); err == nil {
			if err := json.Unmarshal(data, &msg); err == nil {
				if a.program != nil {
					a.program.Send(LoginSuccessMsg{
						User:  msg.User,
						Token: msg.Token,
					})
				}
			}
		}
	})

	// Login error
	channel.On("login_error", func(payload any) {
		var msg struct {
			Message string `json:"message"`
			Details string `json:"details"`
		}
		if data, err := json.Marshal(payload); err == nil {
			if err := json.Unmarshal(data, &msg); err == nil {
				if a.program != nil {
					a.program.Send(LoginErrorMsg{
						Message: msg.Message,
						Details: msg.Details,
					})
				}
			}
		}
	})

	// API key authentication success - returns same format as login_success
	channel.On("authenticate_with_api_key_success", func(payload any) {
		var msg struct {
			User  AuthUser `json:"user"`
			Token string   `json:"token"`
		}
		if data, err := json.Marshal(payload); err == nil {
			if err := json.Unmarshal(data, &msg); err == nil {
				if a.program != nil {
					a.program.Send(LoginSuccessMsg{
						User:  msg.User,
						Token: msg.Token,
					})
				}
			}
		}
	})

	// API key authentication error
	channel.On("authenticate_with_api_key_error", func(payload any) {
		var msg struct {
			Message string `json:"message"`
			Details string `json:"details"`
		}
		if data, err := json.Marshal(payload); err == nil {
			if err := json.Unmarshal(data, &msg); err == nil {
				if a.program != nil {
					a.program.Send(LoginErrorMsg{
						Message: msg.Message,
						Details: msg.Details,
					})
				}
			}
		}
	})

	// Logout success
	channel.On("logout_success", func(payload any) {
		var msg struct {
			Message string `json:"message"`
		}
		if data, err := json.Marshal(payload); err == nil {
			if err := json.Unmarshal(data, &msg); err == nil {
				if a.program != nil {
					a.program.Send(LogoutSuccessMsg{
						Message: msg.Message,
					})
				}
			}
		}
	})

	// Auth status
	channel.On("auth_status", func(payload any) {
		var msg struct {
			Authenticated   bool       `json:"authenticated"`
			User           *AuthUser  `json:"user,omitempty"`
			AuthenticatedAt *time.Time `json:"authenticated_at,omitempty"`
		}
		if data, err := json.Marshal(payload); err == nil {
			if err := json.Unmarshal(data, &msg); err == nil {
				if a.program != nil {
					a.program.Send(AuthStatusMsg{
						Authenticated:   msg.Authenticated,
						User:           msg.User,
						AuthenticatedAt: msg.AuthenticatedAt,
					})
				}
			}
		}
	})

	// Token refreshed
	channel.On("token_refreshed", func(payload any) {
		var msg struct {
			User  AuthUser `json:"user"`
			Token string   `json:"token"`
		}
		if data, err := json.Marshal(payload); err == nil {
			if err := json.Unmarshal(data, &msg); err == nil {
				if a.program != nil {
					a.program.Send(TokenRefreshedMsg{
						User:  msg.User,
						Token: msg.Token,
					})
				}
			}
		}
	})
}

// Login attempts to login with username and password
func (a *AuthClient) Login(username, password string) tea.Cmd {
	return a.push("login", map[string]any{
		"username": username,
		"password": password,
	})
}

// Logout logs out the current user
func (a *AuthClient) Logout() tea.Cmd {
	return a.push("logout", map[string]any{})
}

// GetStatus gets the current authentication status
func (a *AuthClient) GetStatus() tea.Cmd {
	return a.push("get_status", map[string]any{})
}


// RefreshToken refreshes the authentication token
func (a *AuthClient) RefreshToken() tea.Cmd {
	return a.push("refresh_token", map[string]any{})
}

// AuthenticateWithAPIKey authenticates using an API key
func (a *AuthClient) AuthenticateWithAPIKey(apiKey string) tea.Cmd {
	return a.push("authenticate_with_api_key", map[string]any{
		"api_key": apiKey,
	})
}

// push sends a message to the auth channel
func (a *AuthClient) push(event string, payload map[string]any) tea.Cmd {
	return func() tea.Msg {
		if a.authChannel == nil {
			return ErrorMsg{
				Err:       fmt.Errorf("auth channel not joined"),
				Component: "Auth Push",
			}
		}

		push, err := a.authChannel.Push(event, payload)
		if err != nil {
			return ErrorMsg{
				Err:       err,
				Component: "Auth Push",
			}
		}

		// Set up response handlers
		push.Receive("ok", func(response any) {
			// Success handled by channel event handlers
		})

		push.Receive("error", func(response any) {
			if a.program != nil {
				a.program.Send(ErrorMsg{
					Err:       fmt.Errorf("auth push failed: %v", response),
					Component: "Auth Push",
				})
			}
		})

		push.Receive("timeout", func(response any) {
			// Always report timeouts with the specific event name so we can debug
			if a.program != nil {
				a.program.Send(ErrorMsg{
					Err:       fmt.Errorf("Connection timeout for event: %s", event),
					Component: "Auth Push",
				})
			}
		})

		return nil
	}
}

// IsConnected returns whether the auth channel is connected
func (a *AuthClient) IsConnected() bool {
	return a.connected
}

// Disconnect leaves the auth channel
func (a *AuthClient) Disconnect() tea.Cmd {
	return func() tea.Msg {
		if a.authChannel != nil {
			a.authChannel.Leave()
			a.authChannel = nil
			a.connected = false
			a.joining = false
		}
		return nil
	}
}