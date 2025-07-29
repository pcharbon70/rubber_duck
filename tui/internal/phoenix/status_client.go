package phoenix

import (
	"fmt"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/nshafer/phx"
)

// StatusClient handles status channel operations
type StatusClient struct {
	socket    *phx.Socket
	channel   *phx.Channel
	channelID string
	program   *tea.Program
}

// NewStatusClient creates a new status client
func NewStatusClient() *StatusClient {
	return &StatusClient{}
}

// SetSocket sets the Phoenix socket
func (s *StatusClient) SetSocket(socket *phx.Socket) {
	s.socket = socket
}

// SetProgram sets the Bubble Tea program for sending messages
func (s *StatusClient) SetProgram(program *tea.Program) {
	s.program = program
}

// JoinStatusChannel joins a status channel for a specific conversation
func (s *StatusClient) JoinStatusChannel(conversationID string) tea.Cmd {
	return func() tea.Msg {
		if s.socket == nil {
			return ErrorMsg{
				Component: "StatusClient",
				Err:       fmt.Errorf("socket not initialized"),
			}
		}

		channelName := fmt.Sprintf("status:%s", conversationID)
		s.channelID = channelName
		
		// Create and join the channel
		channel := s.socket.Channel(channelName, nil)
		s.channel = channel
		
		// Set up event handlers
		channel.On("status_update", func(payload any) {
			s.handleStatusUpdate(channel, payload)
		})
		
		// Join the channel
		join, err := channel.Join()
		if err != nil {
			return ErrorMsg{
				Component: "StatusClient",
				Err:       fmt.Errorf("failed to join status channel: %w", err),
			}
		}

		// Handle join responses
		join.Receive("ok", func(response any) {
			// Parse response
			var resp struct {
				ConversationID       string              `json:"conversation_id"`
				AvailableCategories []string            `json:"available_categories"`
				SubscribedCategories []string           `json:"subscribed_categories"`
				CategoryDescriptions map[string]string  `json:"category_descriptions"`
			}
			
			if data, ok := response.(map[string]any); ok {
				if convID, ok := data["conversation_id"].(string); ok {
					resp.ConversationID = convID
				}
				if cats, ok := data["available_categories"].([]any); ok {
					for _, cat := range cats {
						if catStr, ok := cat.(string); ok {
							resp.AvailableCategories = append(resp.AvailableCategories, catStr)
						}
					}
				}
				if descs, ok := data["category_descriptions"].(map[string]any); ok {
					resp.CategoryDescriptions = make(map[string]string)
					for cat, desc := range descs {
						if descStr, ok := desc.(string); ok {
							resp.CategoryDescriptions[cat] = descStr
						}
					}
				}
			}
			
			s.program.Send(StatusChannelJoinedMsg{
				ConversationID:       resp.ConversationID,
				AvailableCategories:  resp.AvailableCategories,
				CategoryDescriptions: resp.CategoryDescriptions,
			})
		})
		
		join.Receive("error", func(response any) {
			s.program.Send(ErrorMsg{
				Component: "StatusClient",
				Err:       fmt.Errorf("status channel join failed: %v", response),
			})
		})
		
		join.Receive("timeout", func(response any) {
			s.program.Send(ErrorMsg{
				Component: "StatusClient",
				Err:       fmt.Errorf("status channel join timeout"),
			})
		})
		
		return nil
	}
}

// SubscribeCategories subscribes to specific status categories
func (s *StatusClient) SubscribeCategories(categories []string) tea.Cmd {
	return func() tea.Msg {
		if s.channel == nil {
			return ErrorMsg{
				Component: "StatusClient",
				Err:       fmt.Errorf("status channel not joined"),
			}
		}

		push, err := s.channel.Push("subscribe_categories", map[string]any{
			"categories": categories,
		})
		if err != nil {
			return ErrorMsg{
				Component: "StatusClient",
				Err:       fmt.Errorf("failed to push subscribe: %w", err),
			}
		}

		push.Receive("ok", func(response any) {
			var subscribed []string
			if data, ok := response.(map[string]any); ok {
				if subs, ok := data["subscribed"].([]any); ok {
					for _, sub := range subs {
						if subStr, ok := sub.(string); ok {
							subscribed = append(subscribed, subStr)
						}
					}
				}
			}
			
			s.program.Send(StatusCategoriesSubscribedMsg{
				Categories: subscribed,
			})
		})
		
		push.Receive("error", func(response any) {
			var errMsg string
			if data, ok := response.(map[string]any); ok {
				if reason, ok := data["reason"].(string); ok {
					errMsg = reason
				}
				if msg, ok := data["message"].(string); ok {
					errMsg += ": " + msg
				}
			}
			
			s.program.Send(ErrorMsg{
				Component: "StatusClient",
				Err:       fmt.Errorf("subscribe failed: %s", errMsg),
			})
		})
		
		push.Receive("timeout", func(response any) {
			s.program.Send(ErrorMsg{
				Component: "StatusClient",
				Err:       fmt.Errorf("Connection timeout for event: subscribe_categories"),
			})
		})
		
		return nil
	}
}

// UnsubscribeCategories unsubscribes from specific status categories
func (s *StatusClient) UnsubscribeCategories(categories []string) tea.Cmd {
	return func() tea.Msg {
		if s.channel == nil {
			return ErrorMsg{
				Component: "StatusClient",
				Err:       fmt.Errorf("status channel not joined"),
			}
		}

		push, err := s.channel.Push("unsubscribe_categories", map[string]any{
			"categories": categories,
		})
		if err != nil {
			return ErrorMsg{
				Component: "StatusClient",
				Err:       fmt.Errorf("failed to push unsubscribe: %w", err),
			}
		}

		push.Receive("ok", func(response any) {
			var subscribed []string
			if data, ok := response.(map[string]any); ok {
				if subs, ok := data["subscribed"].([]any); ok {
					for _, sub := range subs {
						if subStr, ok := sub.(string); ok {
							subscribed = append(subscribed, subStr)
						}
					}
				}
			}
			
			s.program.Send(StatusCategoriesSubscribedMsg{
				Categories: subscribed,
			})
		})
		
		push.Receive("error", func(response any) {
			s.program.Send(ErrorMsg{
				Component: "StatusClient",
				Err:       fmt.Errorf("unsubscribe failed: %v", response),
			})
		})
		
		push.Receive("timeout", func(response any) {
			s.program.Send(ErrorMsg{
				Component: "StatusClient",
				Err:       fmt.Errorf("Connection timeout for event: unsubscribe_categories"),
			})
		})
		
		return nil
	}
}

// GetSubscriptions gets current category subscriptions
func (s *StatusClient) GetSubscriptions() tea.Cmd {
	return func() tea.Msg {
		if s.channel == nil {
			return ErrorMsg{
				Component: "StatusClient",
				Err:       fmt.Errorf("status channel not joined"),
			}
		}

		push, err := s.channel.Push("get_subscriptions", nil)
		if err != nil {
			return ErrorMsg{
				Component: "StatusClient",
				Err:       fmt.Errorf("failed to push get_subscriptions: %w", err),
			}
		}

		push.Receive("ok", func(response any) {
			var subscribed, available []string
			
			if data, ok := response.(map[string]any); ok {
				if subs, ok := data["subscribed_categories"].([]any); ok {
					for _, sub := range subs {
						if subStr, ok := sub.(string); ok {
							subscribed = append(subscribed, subStr)
						}
					}
				}
				if avail, ok := data["available_categories"].([]any); ok {
					for _, av := range avail {
						if avStr, ok := av.(string); ok {
							available = append(available, avStr)
						}
					}
				}
			}
			
			s.program.Send(StatusSubscriptionsMsg{
				Subscribed: subscribed,
				Available:  available,
			})
		})
		
		push.Receive("error", func(response any) {
			s.program.Send(ErrorMsg{
				Component: "StatusClient",
				Err:       fmt.Errorf("get subscriptions failed: %v", response),
			})
		})
		
		push.Receive("timeout", func(response any) {
			s.program.Send(ErrorMsg{
				Component: "StatusClient",
				Err:       fmt.Errorf("Connection timeout for event: get_subscriptions"),
			})
		})
		
		return nil
	}
}

// LeaveChannel leaves the status channel
func (s *StatusClient) LeaveChannel() {
	if s.channel != nil {
		s.channel.Leave()
		s.channel = nil
	}
}

// handleStatusUpdate handles incoming status update messages
func (s *StatusClient) handleStatusUpdate(_ *phx.Channel, payload any) {
	// Skip if program not set
	if s.program == nil {
		return
	}

	// Parse the status update
	data, ok := payload.(map[string]any)
	if !ok {
		return
	}

	category, _ := data["category"].(string)
	text, _ := data["text"].(string)
	metadata, _ := data["metadata"].(map[string]any)
	
	// Parse timestamp
	var timestamp time.Time
	if ts, ok := data["timestamp"].(string); ok {
		timestamp, _ = time.Parse(time.RFC3339, ts)
	} else {
		timestamp = time.Now()
	}

	// Send to the UI
	s.program.Send(StatusUpdateMsg{
		Category:  category,
		Text:      text,
		Metadata:  metadata,
		Timestamp: timestamp,
	})
}

// Status channel message types

type StatusChannelJoinedMsg struct {
	ConversationID       string
	AvailableCategories  []string
	CategoryDescriptions map[string]string
}

type StatusCategoriesSubscribedMsg struct {
	Categories []string
}

type StatusSubscriptionsMsg struct {
	Subscribed []string
	Available  []string
}

type StatusUpdateMsg struct {
	Category  string
	Text      string
	Metadata  map[string]any
	Timestamp time.Time
}