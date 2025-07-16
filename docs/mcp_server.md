# MCP Server Documentation

## Overview

The MCP (Model Context Protocol) Server exposes RubberDuck's capabilities to AI assistants through a standardized protocol. This allows AI tools to interact with RubberDuck's workflow engine, code analysis features, and other functionality.

## Architecture

### Core Components

1. **Server Module** (`RubberDuck.MCP.Server`)
   - Implements the `Hermes.Server` behavior
   - Manages server lifecycle and component registration
   - Handles notifications and server state

2. **State Management** (`RubberDuck.MCP.Server.State`)
   - Tracks active sessions and request metrics
   - Manages tool/resource filtering
   - Provides runtime statistics

3. **Component System**
   - **Tools**: Expose executable actions
   - **Resources**: Provide access to data
   - **Prompts**: Offer structured templates

4. **Streaming Support** (`RubberDuck.MCP.Server.Streaming`)
   - Real-time progress updates
   - Chunked content delivery
   - Token-based stream management

5. **Transport Layers**
   - STDIO (default)
   - HTTP/SSE (streamable HTTP)
   - WebSocket (future)

## Available Components

### Tools

#### WorkflowExecutor
Executes RubberDuck workflows with optional streaming progress.

```json
{
  "workflow_name": "code_analysis",
  "params": {"file_path": "lib/app.ex"},
  "async": false,
  "timeout": 30000,
  "stream_progress": true
}
```

#### CodeAnalyzer
Analyzes code structure, quality, and patterns.

```json
{
  "file_path": "lib/module.ex",
  "analysis_type": "all",
  "include_metrics": true,
  "include_ast": false
}
```

#### FileOperations
Manages file system operations with safety checks.

```json
{
  "operation": "read",
  "path": "config/config.exs",
  "options": {"encoding": "utf-8"}
}
```

#### ConversationManager
Manages AI conversation contexts and history.

```json
{
  "action": "start",
  "conversation_id": "conv_123",
  "metadata": {"topic": "code review"}
}
```

### Resources

#### ProjectFiles
Provides access to project file structure and contents.

- URI: `project://`
- Supports glob patterns for filtering

#### Documentation
Exposes project and system documentation.

- URI: `docs://`
- Categories: api, guides, tutorials, references

#### SystemState
Runtime information about the RubberDuck system.

- URI: `system://`
- Components: overview, workflows, modules, metrics, config

### Prompts

#### CodeReview
Template for comprehensive code reviews.

```json
{
  "file_path": "lib/app.ex",
  "review_type": "security",
  "context": {"pr_number": 123}
}
```

#### FeatureImplementation
Guided feature development workflow.

```json
{
  "feature_name": "User Authentication",
  "requirements": ["OAuth support", "JWT tokens"],
  "target_directory": "lib/auth"
}
```

#### BugFix
Structured bug investigation and resolution.

```json
{
  "issue_id": "BUG-456",
  "description": "Memory leak in worker process",
  "affected_files": ["lib/worker.ex"]
}
```

## Configuration

### Enabling the Server

Add to your application configuration:

```elixir
config :rubber_duck,
  mcp_server_enabled: true,
  mcp_server_transport: :stdio,
  mcp_server_port: 8080  # For HTTP transport
```

### Starting the Server

The server starts automatically when enabled. For manual control:

```elixir
# Start with STDIO transport
{:ok, pid} = RubberDuck.MCP.Server.start_link(transport: :stdio)

# Start with HTTP transport
{:ok, pid} = RubberDuck.MCP.Server.start_link(
  transport: :streamable_http,
  port: 8080
)
```

### Filtering Components

Control which tools and resources are exposed:

```elixir
RubberDuck.MCP.Server.start_link(
  transport: :stdio,
  tool_filter: fn name -> 
    name in ["WorkflowExecutor", "CodeAnalyzer"]
  end,
  resource_filter: fn uri ->
    not String.contains?(uri, "private")
  end
)
```

## Integration

### With Claude Desktop

Add to your Claude desktop configuration:

```json
{
  "mcpServers": {
    "rubber_duck": {
      "command": "mix",
      "args": ["rubber_duck.mcp", "server"],
      "env": {
        "MIX_ENV": "prod"
      }
    }
  }
}
```

### With Other AI Assistants

Any MCP-compatible assistant can connect:

1. **STDIO**: Spawn the server process and communicate via stdin/stdout
2. **HTTP**: Connect to the configured port using Server-Sent Events
3. **WebSocket**: Future support for bidirectional streaming

## Streaming Operations

For long-running operations, enable streaming:

```elixir
# In tool implementation
Streaming.with_stream(frame, "operation_name", fn frame, token ->
  # Send progress updates
  {:ok, frame} = Streaming.send_progress(frame, token, %{
    progress: 0.5,
    message: "Processing..."
  })
  
  # Stream content chunks
  {:ok, frame} = Streaming.stream_chunk(frame, token, "Output line\n")
  
  # Return final result
  {:ok, result, frame}
end)
```

## Security Considerations

1. **Authentication**: Currently relies on transport-level security
2. **Authorization**: Use component filters to restrict access
3. **Input Validation**: All inputs are validated against schemas
4. **Resource Limits**: Timeouts and rate limiting prevent abuse

## Monitoring

Access server metrics through the SystemState resource:

```bash
# View server status
curl http://localhost:8080/resources/system://overview

# Check active workflows
curl http://localhost:8080/resources/system://workflows

# Monitor performance
curl http://localhost:8080/resources/system://metrics
```

## Extending the Server

### Adding New Tools

1. Create a module using `Hermes.Server.Component`
2. Define the schema and implement `execute/2`
3. Register in the server module

```elixir
defmodule MyApp.MCP.Tools.CustomTool do
  use Hermes.Server.Component, type: :tool
  
  schema do
    field :input, {:required, :string}
    field :option, :boolean, default: true
  end
  
  @impl true
  def execute(params, frame) do
    # Tool implementation
    {:ok, result, frame}
  end
end
```

### Adding New Resources

Similar process but implement `read/2` and `list/1`:

```elixir
defmodule MyApp.MCP.Resources.CustomResource do
  use Hermes.Server.Component,
    type: :resource,
    uri: "custom://",
    mime_type: "application/json"
  
  @impl true
  def read(params, frame) do
    # Read implementation
    {:ok, content, frame}
  end
  
  @impl true
  def list(frame) do
    # List available resources
    {:ok, resources, frame}
  end
end
```

## Troubleshooting

### Common Issues

1. **Server won't start**: Check if port is already in use (HTTP transport)
2. **Components not available**: Verify registration and filters
3. **Streaming not working**: Ensure transport supports streaming
4. **High memory usage**: Monitor active sessions and implement cleanup

### Debug Mode

Enable debug logging:

```elixir
config :logger, :console,
  level: :debug,
  metadata: [:mcp_server, :mcp_component]
```

## Future Enhancements

1. **WebSocket Transport**: Full bidirectional streaming
2. **Authentication**: OAuth2/JWT support
3. **Rate Limiting**: Per-client request limits
4. **Metrics Export**: Prometheus/OpenTelemetry integration
5. **Component Hot Reload**: Dynamic component updates