# Status Channel Integration

## Overview
Integrated Phoenix status channel to display AI work-in-progress messages in a dedicated section of the TUI chat interface.

## Implementation Details

### 1. Status Messages Component (`internal/ui/status_messages.go`)
- Created a new scrollable component for displaying status messages
- Supports 6 message categories: engine, tool, workflow, progress, error, info
- Features:
  - Color-coded messages by category
  - Scrollable viewport with auto-scroll to bottom
  - Message limiting (last 100 messages)
  - Timestamp display
  - Error metadata display

### 2. Status Client (`internal/phoenix/status_client.go`)
- Implemented Phoenix WebSocket client for status channel operations
- Methods:
  - `JoinStatusChannel(conversationID)` - Join status channel for a conversation
  - `SubscribeCategories(categories)` - Subscribe to specific message categories
  - `UnsubscribeCategories(categories)` - Unsubscribe from categories
  - `GetSubscriptions()` - Get current subscriptions
- Handles incoming status updates and forwards to UI

### 3. UI Layout Updates
- Modified chat layout to include status messages section
- Status messages take 30% of conversation history area
- Added divider between chat and status sections
- Updated component size calculations in `updateComponentSizes()`

### 4. Connection Flow
- Status channel joins automatically after successful authentication
- Connection sequence:
  1. Connect to WebSocket → Auth channel
  2. Authenticate (login or API key)
  3. Join conversation channel
  4. Join status channel with conversation ID
  5. Subscribe to all categories by default

### 5. Message Handling
- Added handlers in Update function for:
  - `StatusChannelJoinedMsg` - Channel join confirmation
  - `StatusCategoriesSubscribedMsg` - Subscription confirmation
  - `StatusUpdateMsg` - Incoming status messages
  - `StatusSubscriptionsMsg` - Current subscription status
- Status messages are automatically added to the StatusMessages component

## Usage
Status messages will automatically appear in the bottom 30% of the chat area when the AI is processing requests. The messages provide real-time feedback about:
- Engine execution status
- Tool invocations
- Workflow progress
- General progress indicators
- Errors and debugging information
- Informational messages

## Technical Decisions
1. Used separate StatusClient to manage status channel independently
2. Auto-subscribe to all categories for comprehensive feedback
3. 30% screen allocation provides good visibility without overwhelming chat
4. Scrollable viewport allows reviewing message history
5. Color coding improves message category recognition