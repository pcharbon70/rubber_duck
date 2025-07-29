package phoenix

import (
	"encoding/json"
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/nshafer/phx"
)

// PlanningClient handles planning channel operations
type PlanningClient struct {
	socket  *phx.Socket
	channel *phx.Channel
	program *tea.Program
}

// NewPlanningClient creates a new planning client
func NewPlanningClient() *PlanningClient {
	return &PlanningClient{}
}

// SetSocket sets the Phoenix socket
func (p *PlanningClient) SetSocket(socket *phx.Socket) {
	p.socket = socket
}

// SetProgram sets the Bubble Tea program for sending messages
func (p *PlanningClient) SetProgram(program *tea.Program) {
	p.program = program
}

// JoinPlanningChannel joins the planning channel
func (p *PlanningClient) JoinPlanningChannel() tea.Cmd {
	return func() tea.Msg {
		if p.socket == nil {
			return ErrorMsg{
				Err:       fmt.Errorf("socket not connected"),
				Component: "Planning Client",
			}
		}
		
		// Join planning:lobby channel
		channel := p.socket.Channel("planning:lobby", nil)
		
		// Join the channel
		join, err := channel.Join()
		if err != nil {
			return ErrorMsg{
				Err:       fmt.Errorf("failed to join planning channel: %w", err),
				Component: "Planning Client",
			}
		}
		
		// Handle join response
		join.Receive("ok", func(response any) {
			p.program.Send(PlanningChannelJoinedMsg{
				Channel:  channel,
				Response: response,
			})
		})
		
		join.Receive("error", func(response any) {
			p.program.Send(ErrorMsg{
				Err:       fmt.Errorf("planning channel join failed: %v", response),
				Component: "Planning Client",
			})
		})
		
		join.Receive("timeout", func(response any) {
			p.program.Send(ErrorMsg{
				Err:       fmt.Errorf("planning channel join timeout"),
				Component: "Planning Client",
			})
		})
		
		// Set up channel event handlers
		p.setupChannelHandlers(channel)
		
		p.channel = channel
		return PlanningChannelJoiningMsg{}
	}
}

// setupChannelHandlers sets up event handlers for planning channel
func (p *PlanningClient) setupChannelHandlers(channel *phx.Channel) {
	// Handle planning started event
	channel.On("planning_started", func(payload any) {
		data, _ := json.Marshal(payload)
		p.program.Send(PlanningStartedMsg{
			Data: data,
		})
	})
	
	// Handle planning step event
	channel.On("planning_step", func(payload any) {
		data, _ := json.Marshal(payload)
		p.program.Send(PlanningStepMsg{
			Data: data,
		})
	})
	
	// Handle planning completed event
	channel.On("planning_completed", func(payload any) {
		data, _ := json.Marshal(payload)
		p.program.Send(PlanningCompletedMsg{
			Data: data,
		})
	})
	
	// Handle planning error event
	channel.On("planning_error", func(payload any) {
		data, _ := json.Marshal(payload)
		p.program.Send(PlanningErrorMsg{
			Data: data,
		})
	})
	
	// Handle planning cancelled event
	channel.On("planning_cancelled", func(payload any) {
		p.program.Send(PlanningCancelledMsg{})
	})
	
	// Handle error event
	channel.On("error", func(payload any) {
		p.program.Send(ErrorMsg{
			Err:       fmt.Errorf("planning channel error: %v", payload),
			Component: "Planning Channel",
		})
	})
}

// Push sends a message to the planning channel
func (p *PlanningClient) Push(event string, payload map[string]any) tea.Cmd {
	return func() tea.Msg {
		if p.channel == nil {
			return ErrorMsg{
				Err:       fmt.Errorf("planning channel not joined"),
				Component: "Planning Client",
			}
		}
		
		push, err := p.channel.Push(event, payload)
		if err != nil {
			return ErrorMsg{
				Err:       err,
				Component: "Planning Push",
			}
		}
		
		push.Receive("ok", func(response any) {
			// Success - nothing specific to do
		})
		
		push.Receive("error", func(response any) {
			p.program.Send(ErrorMsg{
				Err:       fmt.Errorf("planning push failed: %v", response),
				Component: "Planning Push",
			})
		})
		
		push.Receive("timeout", func(response any) {
			// For planning events, we might handle responses through channel events
			if event != "start_planning" && event != "cancel_planning" {
				p.program.Send(ErrorMsg{
					Err:       fmt.Errorf("planning push timeout for event: %s", event),
					Component: "Planning Push",
				})
			}
		})
		
		return nil
	}
}

// PushAsync sends a message to the planning channel without waiting for responses
func (p *PlanningClient) PushAsync(event string, payload map[string]any) tea.Cmd {
	return func() tea.Msg {
		if p.channel == nil {
			return ErrorMsg{
				Err:       fmt.Errorf("planning channel not joined"),
				Component: "Planning Client",
			}
		}
		
		// Just push without setting up response handlers
		_, err := p.channel.Push(event, payload)
		if err != nil {
			return ErrorMsg{
				Err:       err,
				Component: "Planning Push",
			}
		}
		
		return nil
	}
}

// StartPlanning starts a planning session
func (p *PlanningClient) StartPlanning(query string, context map[string]any) tea.Cmd {
	payload := map[string]any{
		"query":   query,
		"context": context,
	}
	return p.PushAsync("start_planning", payload)
}

// CancelPlanning cancels the current planning session
func (p *PlanningClient) CancelPlanning() tea.Cmd {
	return p.PushAsync("cancel_planning", map[string]any{})
}

// SendPlanningFeedback sends feedback on a planning step
func (p *PlanningClient) SendPlanningFeedback(stepID string, feedback string) tea.Cmd {
	payload := map[string]any{
		"step_id":  stepID,
		"feedback": feedback,
	}
	return p.Push("planning_feedback", payload)
}

// LeaveChannel leaves the planning channel
func (p *PlanningClient) LeaveChannel() {
	if p.channel != nil {
		p.channel.Leave()
		p.channel = nil
	}
}

// Planning channel message types

type PlanningChannelJoiningMsg struct{}

type PlanningChannelJoinedMsg struct {
	Channel  *phx.Channel
	Response any
}

type PlanningStartedMsg struct {
	Data json.RawMessage
}

type PlanningStepMsg struct {
	Data json.RawMessage
}

type PlanningCompletedMsg struct {
	Data json.RawMessage
}

type PlanningErrorMsg struct {
	Data json.RawMessage
}

type PlanningCancelledMsg struct{}