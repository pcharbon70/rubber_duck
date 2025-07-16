# Feature 008: MCP Client Implementation

## Overview

The MCP (Model Context Protocol) client implementation enables RubberDuck to connect to external MCP servers, expanding its capabilities through access to a vast ecosystem of tools and data sources. This implementation follows Phase 8.1 of the implementation plan and leverages the Hermes MCP library for Elixir.

## Key Components

### 1. Core Client Module (`RubberDuck.MCP.Client`)

The main client module provides a GenServer-based implementation with:
- Connection lifecycle management
- Health monitoring with automatic heartbeat
- Request/response correlation
- Telemetry integration
- Automatic reconnection support

### 2. Transport Adapters

Three transport types are supported:

#### STDIO Transport
- For local MCP servers that communicate via standard input/output
- Commonly used for command-line tools
- Example: GitHub MCP server, filesystem tools

#### HTTP/SSE Transport
- For remote MCP servers using Server-Sent Events
- Supports authentication headers
- Real-time updates via SSE stream

#### WebSocket Transport
- For bidirectional real-time communication
- Lower latency than HTTP/SSE
- Suitable for high-frequency interactions

### 3. OTP Supervision Architecture

```
Application Supervisor
├── MCP.ClientRegistry (Registry)
└── MCP.ClientSupervisor (DynamicSupervisor)
    ├── MCP Client 1
    ├── MCP Client 2
    └── MCP Client N
```

- **ClientRegistry**: Tracks all active clients by name
- **ClientSupervisor**: Manages client lifecycle with fault tolerance
- **Connection Pool**: Efficient connection reuse (future enhancement)

### 4. Security Features

- **Authentication Support**:
  - OAuth 2.1 for secure token-based auth
  - API keys for simple authentication
  - Certificate-based authentication for enterprise

- **Transport Security**:
  - TLS/SSL for encrypted connections
  - Input validation and sanitization
  - Rate limiting per client

## Usage Examples

### Starting a Client

```elixir
# Connect to GitHub MCP server
{:ok, client} = RubberDuck.MCP.Client.start_link(
  name: :github_mcp,
  transport: {:stdio, 
    command: "npx",
    args: ["@modelcontextprotocol/server-github"]
  },
  capabilities: [:tools, :resources],
  auth: {:api_key, key: System.get_env("GITHUB_TOKEN")}
)
```

### Using Tools

```elixir
# List available tools
{:ok, tools} = RubberDuck.MCP.Client.list_tools(:github_mcp)

# Call a tool
{:ok, result} = RubberDuck.MCP.Client.call_tool(
  :github_mcp,
  "search_repositories",
  %{query: "elixir mcp", sort: "stars", limit: 10}
)
```

### Working with Resources

```elixir
# List resources
{:ok, resources} = RubberDuck.MCP.Client.list_resources(:github_mcp)

# Read a resource
{:ok, content} = RubberDuck.MCP.Client.read_resource(
  :github_mcp,
  "github://repo/owner/name/README.md"
)
```

## Configuration

### Application Config

```elixir
config :rubber_duck, :mcp,
  clients: [
    %{
      name: :github,
      transport: {:stdio, command: "npx", args: ["@modelcontextprotocol/server-github"]},
      capabilities: [:tools, :resources],
      auto_start: true,
      auto_reconnect: true,
      timeout: 30_000
    },
    %{
      name: :postgres,
      transport: {:stdio, command: "npx", args: ["@modelcontextprotocol/server-postgres"]},
      capabilities: [:tools, :resources],
      auth: {:env, "DATABASE_URL"}
    }
  ]
```

### Runtime Configuration

```elixir
# Start a client dynamically
RubberDuck.MCP.ClientSupervisor.start_client(
  name: :dynamic_client,
  transport: {:websocket, url: "ws://localhost:8080/mcp"},
  capabilities: [:tools]
)

# Stop a client
RubberDuck.MCP.ClientSupervisor.stop_client(:dynamic_client)
```

## Monitoring and Telemetry

The MCP client emits telemetry events for monitoring:

```elixir
# Connection events
[:rubber_duck, :mcp, :client, :connected]
[:rubber_duck, :mcp, :client, :disconnected]

# Request events
[:rubber_duck, :mcp, :client, :request, :start]
[:rubber_duck, :mcp, :client, :request, :stop]
[:rubber_duck, :mcp, :client, :request, :error]

# Health events
[:rubber_duck, :mcp, :client, :heartbeat, :success]
[:rubber_duck, :mcp, :client, :heartbeat, :failure]
```

## Integration Points

### With LLM System
- MCP tools can be exposed to LLM providers for enhanced capabilities
- Tool results can be included in prompts automatically
- Dynamic tool selection based on context

### With Workflow System
- MCP tools can be used as workflow steps
- Reactor integration for complex tool orchestration
- Conditional tool execution based on results

### With Memory System
- Tool results can be stored in memory for context
- Historical tool usage patterns for optimization
- Caching of frequently accessed resources

## Testing

The implementation includes comprehensive tests:
- Unit tests for all components
- Integration tests with mock MCP servers
- Property-based tests for protocol compliance
- Performance benchmarks

Run tests with:
```bash
mix test test/rubber_duck/mcp --only mcp
```

## Future Enhancements

1. **Connection Pooling**: Implement pooling for efficient connection reuse
2. **Tool Caching**: Cache tool results based on parameters
3. **Distributed MCP**: Support for MCP server clusters
4. **Tool Discovery Service**: Automatic discovery of available MCP servers
5. **Visual Tool Browser**: LiveView interface for exploring MCP tools

## Technical Details

### Dependencies
- `hermes_mcp ~> 0.10.5` - Elixir MCP implementation
- Built on OTP 26+ for optimal performance
- Phoenix PubSub for real-time updates

### Performance Considerations
- Concurrent request handling via GenServer
- Automatic batching for bulk operations
- Circuit breaker pattern for failing servers
- Exponential backoff for reconnections

### Error Handling
- Graceful degradation when servers unavailable
- Detailed error messages with recovery suggestions
- Automatic retry with configurable policies
- Dead letter queue for failed requests

## Conclusion

The MCP client implementation provides RubberDuck with a powerful extension mechanism, enabling integration with external tools and services through a standardized protocol. The fault-tolerant, supervised architecture ensures reliable operation while the flexible transport system supports various deployment scenarios.