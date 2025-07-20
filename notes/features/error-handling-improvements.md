# Error Handling Improvements

## Overview
Added comprehensive error handling to prevent spam when connection fails and provide better user experience with helpful error messages and reconnection capabilities.

## Features Implemented

### 1. Error Handler (`internal/ui/error_handler.go`)
- **Rate Limiting**: Prevents repeated display of the same error
- **Suppression**: After 3 repeated errors, suppresses with exponential backoff
- **Deduplication**: Tracks last error to avoid duplicates
- **User-Friendly Messages**: Translates technical errors into helpful messages

### 2. Error Display in Chat
- Errors now appear in the conversation history window
- Connection advice provided based on error type
- Clear visual distinction using ErrorMessage type
- No more console spam - errors are properly managed

### 3. Reconnection with Backoff
- **Ctrl+R** shortcut for manual reconnection
- Exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s, max 60s
- Resets after 5 minutes of no attempts
- Prevents rapid reconnection attempts
- Shows cooldown time if attempting too soon

### 4. Connection Advice
Error-specific helpful tips:
- "Connection refused" → Check if Phoenix server is running on port 5555
- "Timeout" → Server might be slow or unreachable
- "Bad handshake" → Check server URL and protocol
- "Authentication failed" → Check credentials

## User Experience Improvements

### Before:
```
Error: connection refused
Error: connection refused
Error: connection refused
[Endless spam...]
```

### After:
```
◆ Conversation History ◆
─────────────────────────
[Error] Phoenix Client: Cannot connect to server. Is the Phoenix server running on the correct port?
[Info] Tip: Make sure the Phoenix server is running with 'mix phx.server' and listening on port 5555
[Info] Connection lost. You can try reconnecting with Ctrl+R or restart the TUI.
[Error] Phoenix Client: Cannot connect to server... (suppressing repeated errors for 2s)
```

## Usage

### Reconnection:
- **Ctrl+R** - Attempt to reconnect (respects backoff)
- Automatic backoff prevents server flooding
- Clear feedback on reconnection attempts

### Error Suppression:
- Same errors shown max 3 times
- Then suppressed with increasing intervals
- Prevents UI clutter while maintaining visibility

## Technical Details

### ErrorHandler Methods:
- `HandleError(err, component)` - Main error processing
- `Reset()` - Clear error state on successful connection
- `formatErrorMessage()` - Convert technical errors to user messages
- `GetConnectionAdvice()` - Provide context-specific help

### Integration Points:
- All ErrorMsg types routed through handler
- Phoenix errors processed consistently
- DisconnectedMsg includes reconnection advice
- ConnectedMsg resets reconnect attempts

## Benefits

1. **No More Spam**: Intelligent suppression prevents UI flooding
2. **Helpful Guidance**: Users get actionable advice
3. **Better UX**: Errors in chat window, not console
4. **Resilient**: Backoff prevents server overload
5. **Recoverable**: Easy reconnection with Ctrl+R