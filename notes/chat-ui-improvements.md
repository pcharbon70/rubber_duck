# Chat UI Improvements Plan

## Current Layout Analysis

### Overall Structure
The TUI currently uses a three-panel horizontal layout:

```
┌─────────────┬──────────────────────────────┬─────────────┐
│ File Tree   │         Chat Window          │   Editor    │
│ (Optional)  │      (Always Visible)        │ (Optional)  │
│   30 cols   │    Remaining Width           │   40 cols   │
└─────────────┴──────────────────────────────┴─────────────┘
────────────────────── Status Bar ──────────────────────────
```

### Chat Window Internal Layout
```
┌────────────────────────────────────────────┐
│                                            │
│         Message History Viewport           │
│         (height - 5 lines)                 │
│                                            │
│  - Shows all messages with timestamps      │
│  - Scrollable with arrow keys              │
│  - Auto-scrolls to bottom on new message   │
│                                            │
├────────────────────────────────────────────┤
│         Input Area (multi-line)            │
│         (5 lines height)                   │
└────────────────────────────────────────────┘
```

### Current Limitations
1. Model selection only visible in status bar
2. No visual indication of message processing status
3. Limited context about conversation state
4. No message metadata display (tokens, processing time)
5. Input area doesn't show current context or limits

## Proposed Improvements

### 1. Enhanced Chat Header
Add a dedicated header section to the chat window displaying:
- Current conversation ID/name
- Active model and provider
- Token usage indicator
- Connection status
- Quick actions (new chat, export, settings)

```
┌────────────────────────────────────────────┐
│ 💬 Conversation: lobby | Model: gpt-4      │
│ Tokens: 1,234/4,096 | ● Connected         │
├────────────────────────────────────────────┤
│         Message History Viewport           │
│                                            │
```

### 2. Improved Message Display

#### Message Grouping
- Group messages by time periods (e.g., "5 minutes ago", "Today")
- Collapse older messages with expansion option

#### Enhanced Message Cards
```
┌─────────────────────────────────────┐
│ You • 2:34 PM                       │
│ Can you help me implement...        │
└─────────────────────────────────────┘
┌─────────────────────────────────────┐
│ Assistant (gpt-4) • 2:34 PM • 342ms │
│ I'll help you implement...          │
│ [Copy] [Retry] [Edit]               │
└─────────────────────────────────────┘
```

#### Message Features
- Show provider/model per message
- Display processing time
- Add action buttons (copy, retry, edit)
- Support markdown rendering with syntax highlighting
- Code block detection and formatting

### 3. Smart Input Area

#### Input Header Bar
```
├────────────────────────────────────────────┤
│ Model: gpt-4 | Tokens: 45/4096 | 📎 2 files│
├────────────────────────────────────────────┤
│         Input Area (multi-line)            │
│         /help for commands                 │
└────────────────────────────────────────────┘
```

#### Features
- Real-time token counting
- File attachment indicators
- Context preview (files, previous messages)
- Auto-complete for slash commands
- Typing indicators for long responses

### 4. Enhanced Status Bar

Current:
```
● Connected | Model: gpt-4 | Tab: Switch Pane
```

Proposed:
```
● Connected | gpt-4 (OpenAI) | Conv: 12 msgs | ↑42ms | Tab: Switch | Ctrl+?: Help
```

Including:
- Provider name with model
- Conversation statistics
- Response time indicator
- More contextual hints

### 5. Layout Flexibility

#### Configurable Sizes
- Allow resizing panels with keyboard shortcuts
- Save layout preferences
- Preset layouts (focus modes)

#### Alternative Layouts
1. **Full-screen chat**: Hide all panels except chat
2. **Vertical split**: Chat on top, editor below
3. **Minimal mode**: Chat only with floating command palette

#### Responsive Design
- Adapt to terminal size changes
- Minimum size requirements
- Graceful degradation for small terminals

## Implementation Priorities

### High Priority
1. **Chat Header** - Critical context information
2. **Model Display in Input** - Users need to know what model they're using
3. **Token Counter** - Prevent hitting limits unexpectedly
4. **Message Actions** - Copy functionality is essential

### Medium Priority
1. **Message Grouping** - Improves readability for long conversations
2. **Processing Time Display** - Helpful for performance awareness
3. **Markdown Rendering** - Better code and formatting support
4. **Layout Presets** - Quick switching between focus modes

### Low Priority
1. **File Attachments UI** - Can use commands initially
2. **Message Search** - Nice to have for long conversations
3. **Export Functions** - Can be command-based
4. **Themes** - Aesthetic improvement

## Technical Considerations

### Required Changes

#### Model Structure Updates
- Add conversation metadata to Model struct
- Track token usage per message
- Store provider info per message
- Add layout preference fields

#### New Components
- `ChatHeader` component for status display
- `MessageCard` component for rich message display
- `InputHeader` component for input status
- `TokenCounter` utility for real-time counting

#### Dependencies
- Markdown parser (for rendering)
- Syntax highlighter (already have Chroma)
- Token counting library (tiktoken-go or similar)

### Performance Considerations
- Lazy loading for long message histories
- Virtual scrolling for better performance
- Debounced token counting
- Cached markdown rendering

### Testing Requirements
- Unit tests for new components
- Integration tests for layout switching
- Performance tests for large conversations
- Accessibility testing for screen readers

## Migration Path

### Phase 1: Foundation (Week 1)
- Add Model fields for new metadata
- Create ChatHeader component
- Implement basic token counting

### Phase 2: Core Features (Week 2)
- Enhanced message display
- Input area improvements
- Update status bar

### Phase 3: Advanced Features (Week 3)
- Layout flexibility
- Markdown rendering
- Message actions

### Phase 4: Polish (Week 4)
- Performance optimization
- Preference persistence
- Documentation updates

## User Benefits

1. **Better Context Awareness**: Always know which model, token usage, and conversation state
2. **Improved Usability**: Quick actions, better visual hierarchy
3. **Enhanced Productivity**: Copy code, retry messages, quick model switching
4. **Flexibility**: Adapt UI to different workflows and preferences
5. **Professional Feel**: Polished UI with thoughtful details

## Next Steps

1. Review and prioritize features with stakeholders
2. Create detailed component specifications
3. Set up feature flags for gradual rollout
4. Begin with Phase 1 implementation
5. Gather user feedback early and often