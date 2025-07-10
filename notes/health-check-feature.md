# Health Check Feature Summary

## Overview

Added server health check functionality to the RubberDuck CLI, allowing users to monitor server status, memory usage, active connections, and LLM provider health through a simple command.

## Implementation Details

### Command Syntax
```bash
rubber_duck health [--format <json|plain|table>]
```

### Components Added

1. **CLI Command Handler** (`lib/rubber_duck/cli_client/commands/health.ex`)
   - Sends health check request to server
   - Formats health data for display
   - Supports multiple output formats

2. **Channel Handler** (`lib/rubber_duck_web/channels/cli_channel.ex`)
   - Added `handle_in("health", ...)` handler
   - Collects server metrics:
     - Server uptime
     - Memory usage statistics
     - Active connection counts
     - LLM provider health status

3. **Output Formatting** (`lib/rubber_duck/cli_client/formatter.ex`)
   - Plain text format: Human-readable server status
   - Table format: Structured display with memory and provider tables
   - JSON format: Machine-readable for monitoring/automation

4. **CLI Integration** (`lib/rubber_duck/cli_client/main.ex`)
   - Added health command specification
   - Integrated with existing command routing

### Health Data Structure

```elixir
%{
  status: "healthy",
  server_time: DateTime,
  uptime: %{days: 2, hours: 14, minutes: 30, total_seconds: 225000},
  memory: %{
    total_mb: 512.3,
    processes_mb: 256.7,
    ets_mb: 45.2,
    binary_mb: 89.4,
    system_mb: 121.0
  },
  connections: %{
    "active_connections" => 3,
    "total_channels" => 4
  },
  providers: [
    %{name: "mock", status: "connected", health: "healthy"},
    %{name: "ollama", status: "connected", health: "healthy"},
    %{name: "tgi", status: "disconnected", health: "unknown"}
  ]
}
```

### Example Output

**Plain Format:**
```
Server Health Status:

Status: healthy
Server Time: 2024-01-15T10:30:00Z
Uptime: 2d 14h 30m

Memory Usage:
  Total: 512.3 MB
  Processes: 256.7 MB
  ETS Tables: 45.2 MB
  Binaries: 89.4 MB
  System: 121.0 MB

Connections:
  Active WebSocket Connections: 3
  Total Channels: 4

Provider Health:
  mock: ● healthy (connected)
  ollama: ● healthy (connected)
  tgi: ? unknown (disconnected)
```

**Table Format:**
```
Server Health: healthy
Server Time: 2024-01-15T10:30:00Z
Uptime: 2d 14h 30m

Memory Usage:
+-----------+--------------+
| Component | Usage (MB)   |
+-----------+--------------+
| Total     | 512.3        |
| Processes | 256.7        |
| ETS Tables| 45.2         |
| Binaries  | 89.4         |
| System    | 121.0        |
+-----------+--------------+

Connections: 3 active, 4 channels

Provider Health:
+----------+--------------+---------+
| Provider | Status       | Health  |
+----------+--------------+---------+
| mock     | connected    | healthy |
| ollama   | connected    | healthy |
| tgi      | disconnected | unknown |
+----------+--------------+---------+
```

## Documentation Updates

1. **CLI Guide** (`guides/user/001-command_line_interface.md`)
   - Added health check section with examples
   - Updated troubleshooting to include health checks
   - Added monitoring script examples

2. **Port Configuration**
   - Changed default port from 4000 to 5555 across all documentation and configuration files
   - Updated: dev.exs, CLI client defaults, all guide examples

## Testing

- Added comprehensive test coverage in `cli_channel_test.exs`
- Tests verify health data structure and response format
- Fixed authentication in tests (API keys must be 32+ bytes)

## Use Cases

1. **Service Monitoring**: Check if server is healthy before running commands
2. **Performance Debugging**: Monitor memory usage patterns
3. **Provider Status**: Verify LLM providers are connected and healthy
4. **CI/CD Integration**: Automated health checks in deployment pipelines
5. **Uptime Tracking**: Monitor server stability over time

## Future Enhancements

1. Historical health data tracking
2. Health check alerts/notifications
3. More detailed metrics (CPU usage, request rates)
4. Custom health check thresholds
5. Provider-specific health metrics