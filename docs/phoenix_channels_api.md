# Phoenix Channels API Documentation

## Overview

RubberDuck provides real-time communication through Phoenix Channels, enabling features like streaming code completions, live analysis results, and collaborative editing.

## Authentication

Connections must be authenticated using either:
1. **Token Authentication**: Phoenix.Token signed with user ID
2. **API Key Authentication**: Valid API key (32+ characters)

### Token Example
```javascript
const token = "your-signed-token"; // Generated server-side
const socket = new Socket("/socket", {
  params: { token: token }
});
```

### API Key Example
```javascript
const socket = new Socket("/socket", {
  params: { api_key: "your-api-key-min-32-chars" }
});
```

## Available Channels

### 1. Code Channel (`code:*`)

For code-related real-time operations.

#### Topics
- `code:project:{project_id}` - Project-wide operations
- `code:file:{file_id}` - File-specific operations

#### Events

##### Outgoing (Client → Server)

**request_completion**
```json
{
  "code": "string",
  "cursor_position": {"line": 1, "column": 1},
  "file_type": "elixir",
  "options": {
    "max_length": 100,
    "temperature": 0.7
  }
}
```

**request_analysis**
```json
{
  "code": "string",
  "file_type": "elixir"
}
```

**cursor_position**
```json
{
  "position": {"line": 5, "column": 10}
}
```

**code_change**
```json
{
  "changes": {
    "from": {"line": 1, "column": 1},
    "to": {"line": 1, "column": 5},
    "text": "new text"
  }
}
```

**cancel_completion**
```json
{
  "completion_id": "completion_xxx"
}
```

##### Incoming (Server → Client)

**completion_chunk**
```json
{
  "completion_id": "completion_xxx",
  "chunk": "code snippet",
  "timestamp": "2024-01-01T00:00:00Z"
}
```

**completion_done**
```json
{
  "completion_id": "completion_xxx",
  "result": {"status": "completed"},
  "timestamp": "2024-01-01T00:00:00Z"
}
```

**completion_error**
```json
{
  "completion_id": "completion_xxx",
  "error": "error message",
  "timestamp": "2024-01-01T00:00:00Z"
}
```

**analysis_result**
```json
{
  "analysis_id": "analysis_xxx",
  "result": {...},
  "timestamp": "2024-01-01T00:00:00Z"
}
```

**cursor_update**
```json
{
  "user_id": "user_123",
  "position": {"line": 5, "column": 10},
  "timestamp": "2024-01-01T00:00:00Z"
}
```

**code_updated**
```json
{
  "user_id": "user_123",
  "changes": {...},
  "timestamp": "2024-01-01T00:00:00Z"
}
```

**presence_state**
```json
{
  "user_123": {
    "metas": [{
      "online_at": "2024-01-01T00:00:00Z",
      "cursor_position": {"line": 1, "column": 1}
    }]
  }
}
```

### 2. Analysis Channel (`analysis:*`)

Dedicated to code analysis operations.

#### Topics
- `analysis:project:{project_id}` - Project-wide analysis
- `analysis:file:{file_id}` - File-specific analysis

#### Events

##### Outgoing (Client → Server)

**start_analysis**
```json
{
  "options": {
    "incremental": true,
    "analyze_dependencies": true
  }
}
```

**analyze**
```json
{
  "type": "semantic|style|security|ast",
  "code": "string",
  "language": "elixir"
}
```

**cancel_analysis**
```json
{
  "analysis_id": "analysis_xxx"
}
```

**get_status**
```json
{
  "analysis_id": "analysis_xxx"
}
```

##### Incoming (Server → Client)

**analysis_started**
```json
{
  "analysis_id": "analysis_xxx",
  "project_id": "project_xxx",
  "timestamp": "2024-01-01T00:00:00Z"
}
```

**analysis_update**
```json
{
  "analysis_id": "analysis_xxx",
  "type": "semantic|style|security",
  "issues": [...],
  "timestamp": "2024-01-01T00:00:00Z"
}
```

**analysis_complete**
```json
{
  "analysis_id": "analysis_xxx",
  "summary": {
    "total_issues": 10,
    "semantic_issues": 3,
    "style_issues": 5,
    "security_issues": 2,
    "files_analyzed": 15
  },
  "timestamp": "2024-01-01T00:00:00Z"
}
```

**analysis_error**
```json
{
  "analysis_id": "analysis_xxx",
  "error": "error message",
  "timestamp": "2024-01-01T00:00:00Z"
}
```

### 3. Workspace Channel (`workspace:*`)

For workspace and file management operations.

#### Topics
- `workspace:user:{user_id}` - User's workspace
- `workspace:project:{project_id}` - Project workspace

#### Events

##### Outgoing (Client → Server)

**create_file**
```json
{
  "path": "lib/my_module.ex",
  "content": "defmodule MyModule do\nend"
}
```

**update_file**
```json
{
  "file_id": "file_xxx",
  "content": "updated content"
}
```

**delete_file**
```json
{
  "file_id": "file_xxx"
}
```

**list_files**
```json
{}
```

**update_project**
```json
{
  "name": "New Project Name",
  "description": "Updated description"
}
```

##### Incoming (Server → Client)

**workspace_state**
```json
{
  "type": "user|project",
  "projects": [...] | "files": [...],
  "timestamp": "2024-01-01T00:00:00Z"
}
```

**file_created**
```json
{
  "file": {
    "id": "file_xxx",
    "path": "lib/my_module.ex",
    "language": "elixir",
    "size": 1024,
    "created_at": "2024-01-01T00:00:00Z"
  },
  "created_by": "user_123",
  "timestamp": "2024-01-01T00:00:00Z"
}
```

**file_updated**
```json
{
  "file": {...},
  "updated_by": "user_123",
  "timestamp": "2024-01-01T00:00:00Z"
}
```

**file_deleted**
```json
{
  "file_id": "file_xxx",
  "deleted_by": "user_123",
  "timestamp": "2024-01-01T00:00:00Z"
}
```

**project_updated**
```json
{
  "project": {...},
  "updated_by": "user_123",
  "timestamp": "2024-01-01T00:00:00Z"
}
```

## Message Queuing

Messages sent to offline users are queued and delivered when they reconnect. The queue has the following characteristics:

- Maximum queue size: 1,000 messages per user
- Message TTL: 24 hours
- Automatic cleanup every 30 minutes
- Messages delivered in order when user reconnects

## Rate Limiting

To prevent abuse, channels implement rate limiting:
- Connection attempts: 10 per minute per IP
- Message sends: 100 per minute per user
- File operations: 30 per minute per user

## Error Handling

All channel errors follow this format:
```json
{
  "reason": "Human-readable error message"
}
```

Common error reasons:
- "Unauthorized access to project"
- "Invalid token"
- "Changes exceed maximum message size"
- "No authentication credentials provided"

## Best Practices

1. **Connection Management**
   - Reuse socket connections
   - Implement reconnection logic with exponential backoff
   - Clean up channels on page navigation

2. **Message Size**
   - Keep messages under 1MB
   - For large files, use pagination or streaming

3. **Presence**
   - Update cursor position throttled (e.g., every 100ms)
   - Clean up presence on disconnect

4. **Error Recovery**
   - Handle network interruptions gracefully
   - Queue important messages locally
   - Retry failed operations with backoff

## Example Implementation

See `examples/channel_client.js` for a complete JavaScript client implementation.