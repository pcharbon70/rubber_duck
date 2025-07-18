# Feature: MCP Server Core

## Summary
Implement the core Model Context Protocol (MCP) server infrastructure to enable RubberDuck to communicate with external AI systems and tools using standardized JSON-RPC 2.0 based protocol.

## Requirements
- [ ] Create MCP server GenServer that handles JSON-RPC 2.0 messages
- [ ] Support multiple transport mechanisms (STDIO, WebSocket, HTTP)
- [ ] Implement session management with state persistence
- [ ] Handle capability negotiation during connection initialization
- [ ] Support request/response correlation for concurrent operations
- [ ] Enable streaming responses for long-running operations
- [ ] Implement graceful shutdown and connection lifecycle management
- [ ] Provide protocol version negotiation (supporting MCP 2024-11-05)
- [ ] Ensure fault tolerance with OTP supervision patterns
- [ ] Support bidirectional communication (server can push notifications)

## Research Summary
### Existing Usage Rules Checked
- GenServer patterns in RubberDuck: Standard OTP GenServer patterns with proper supervision
- Phoenix Channel patterns: WebSocket support through Phoenix.Channel behaviors
- Reactor integration: Used for workflow orchestration and step execution

### Documentation Reviewed
- MCP Protocol Specification: JSON-RPC 2.0 based, supports resources, tools, and prompts
- Research documents (005-mcp-server-for-coding-assistance.md, 012-integrated_llm_mcp_design.md): Comprehensive design patterns
- jsonrpc2 library: Mature Elixir JSON-RPC implementation supporting multiple transports

### Existing Patterns Found
- GenServer patterns: lib/rubber_duck/tool/external_router.ex:12-354 - async task handling, state management, PubSub integration
- Channel patterns: lib/rubber_duck_web/channels/workspace_channel.ex:7-246 - join/leave, message handling, broadcasts
- Tool execution: lib/rubber_duck/tool/composition/step.ex:11-228 - Reactor.Step integration, telemetry
- Monitoring: lib/rubber_duck/tool/composition/middleware/monitoring.ex - Reactor.Middleware for metrics

### Technical Approach
1. **Core Server Architecture**
   - GenServer-based MCP.Server managing connections and protocol state
   - Transport behavior abstraction supporting STDIO, WebSocket, HTTP
   - Session management with DynamicSupervisor for per-connection state
   - Integration with existing tool system through protocol bridge

2. **Protocol Implementation**
   - JSON-RPC 2.0 message parsing and validation
   - Request/response correlation with unique IDs
   - Capability negotiation during initialization
   - Support for batch requests and notifications

3. **Transport Layer**
   - Behavior callbacks for send/receive operations
   - STDIO transport for CLI integration
   - WebSocket transport using Phoenix.Channel
   - HTTP/SSE transport for web clients

4. **Session Management**
   - Per-session GenServer with isolated state
   - Context preservation across requests
   - Integration with RubberDuck's memory system
   - Graceful session termination

5. **Integration Points**
   - Bridge to existing tool registry for tool execution
   - Connection to LLM service for enhanced operations
   - Telemetry integration for monitoring
   - PubSub for real-time updates

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Protocol compatibility | High | Implement strict JSON-RPC 2.0 compliance with version negotiation |
| Concurrent request handling | Medium | Use request ID correlation and proper GenServer state management |
| Transport failures | Medium | Implement circuit breakers and automatic reconnection |
| Resource exhaustion | High | Add rate limiting and maximum session limits |
| Security vulnerabilities | High | Validate all inputs, implement authentication, audit logging |

## Implementation Checklist
- [ ] Create lib/rubber_duck/mcp/server.ex - Core MCP server GenServer
- [ ] Create lib/rubber_duck/mcp/transport.ex - Transport behavior definition
- [ ] Create lib/rubber_duck/mcp/transport/stdio.ex - STDIO transport implementation
- [ ] Create lib/rubber_duck/mcp/transport/websocket.ex - WebSocket transport
- [ ] Create lib/rubber_duck/mcp/protocol.ex - JSON-RPC 2.0 message handling
- [ ] Create lib/rubber_duck/mcp/session.ex - Session management
- [ ] Create lib/rubber_duck/mcp/session_supervisor.ex - DynamicSupervisor for sessions
- [ ] Create lib/rubber_duck/mcp/capability.ex - Capability negotiation
- [ ] Create lib/rubber_duck/mcp/bridge.ex - Bridge to RubberDuck tools
- [ ] Add jsonrpc2 dependency to mix.exs
- [ ] Create comprehensive test suite for all components
- [ ] Add telemetry events for monitoring
- [ ] Create MCP server documentation

## Questions for Pascal
1. Should we use the jsonrpc2 hex package or implement JSON-RPC handling ourselves?
2. Do you want to support all three transports (STDIO, WebSocket, HTTP) initially or start with one?
3. Should MCP server be a separate OTP application or integrated into the main supervision tree?
4. Do you want authentication/authorization from the start or add it later?
5. Should we prioritize hermes_mcp integration or build our own implementation first?