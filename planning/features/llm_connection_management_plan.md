# LLM Connection Management Feature Plan

## Feature Overview
Implement explicit connection management for LLM providers with connect/disconnect functionality, health monitoring, and connection state persistence.

## Goals
1. Provide explicit lifecycle management for LLM provider connections
2. Enable users to connect/disconnect from specific providers or all providers
3. Monitor connection health and provide status information
4. Support connection pooling for providers that benefit from it
5. Graceful shutdown and cleanup of connections

## Implementation Plan

### Phase 1: Core Connection Manager
1. **ConnectionManager GenServer**
   - Manages connection lifecycle for all providers
   - Tracks connection state, health, and metrics
   - Handles connect/disconnect operations
   - Periodic health checks

2. **Provider Adapter Extensions**
   - Add `connect/1`, `disconnect/1`, and `health_check/1` callbacks
   - Default implementations for stateless providers
   - Custom implementations for providers requiring connection state

### Phase 2: CLI Integration
1. **LLM Command Module**
   - `rubber_duck llm status` - Show all provider status
   - `rubber_duck llm connect [provider]` - Connect to provider(s)
   - `rubber_duck llm disconnect [provider]` - Disconnect from provider(s)
   - `rubber_duck llm enable <provider>` - Enable a provider
   - `rubber_duck llm disable <provider>` - Disable a provider

2. **CLI Output Formatting**
   - Status table showing provider state
   - Success/error messages for operations
   - Connection health indicators

### Phase 3: Provider Implementations
1. **Mock Provider**
   - Simulate connection states for testing
   - Configurable failure scenarios

2. **Ollama Provider**
   - HTTP connection pooling
   - Health endpoint checking
   - Connection validation

3. **TGI Provider**
   - WebSocket connection management
   - Persistent connection state
   - Reconnection logic

### Phase 4: Integration with LLM Service
1. **Service Updates**
   - Check connection state before requests
   - Automatic fallback for disconnected providers
   - Connection-aware load balancing

2. **Error Handling**
   - Distinguish connection errors from request errors
   - Appropriate retry strategies based on error type

### Phase 5: Testing & Documentation
1. **Tests**
   - ConnectionManager unit tests
   - Provider adapter tests
   - CLI command integration tests
   - End-to-end connection scenarios

2. **Documentation**
   - User guide for connection management
   - Provider-specific connection instructions
   - Troubleshooting guide

## Technical Details

### Connection States
- `disconnected` - No active connection
- `connecting` - Connection in progress
- `connected` - Active connection, healthy
- `unhealthy` - Connected but failing health checks
- `disconnecting` - Disconnection in progress

### Health Check Strategy
- Run health checks every 30 seconds for connected providers
- Mark unhealthy after 3 consecutive failures
- Automatic reconnection attempts for connection-oriented providers

### Configuration
```elixir
config :rubber_duck, :llm,
  connection_config: %{
    health_check_interval: 30_000,
    max_reconnect_attempts: 3,
    reconnect_delay: 5_000,
    connection_timeout: 10_000
  }
```

## Success Criteria
1. Users can explicitly connect/disconnect from LLM providers
2. Connection state persists across requests
3. Health monitoring provides accurate status
4. Graceful handling of connection failures
5. Clear CLI feedback for all operations

## Risk Mitigation
- Ensure backward compatibility with existing stateless providers
- Implement connection pooling carefully to avoid resource leaks
- Provide clear error messages for connection issues
- Add comprehensive logging for debugging

## Estimated Timeline
- Phase 1: 2 hours (Core ConnectionManager)
- Phase 2: 1 hour (CLI Integration)
- Phase 3: 2 hours (Provider Implementations)
- Phase 4: 1 hour (Service Integration)
- Phase 5: 2 hours (Testing & Documentation)

Total: ~8 hours