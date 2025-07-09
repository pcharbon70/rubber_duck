# LLM Connection Management

RubberDuck provides explicit connection management for LLM providers, allowing you to connect, disconnect, and monitor the health of your LLM services.

## Overview

The Connection Management system provides:
- Explicit lifecycle management for LLM provider connections
- Health monitoring and status tracking
- Connection pooling support (where applicable)
- Graceful error handling and fallback mechanisms
- CLI commands for managing connections

## CLI Commands

### Status

Show the status of all configured LLM providers:

```bash
rubber_duck llm status
```

This displays:
- Connection status (connected, disconnected, connecting, etc.)
- Health status (healthy, unhealthy, not connected)
- Last usage time
- Error counts
- Whether the provider is enabled

### Connect

Connect to a specific provider:

```bash
rubber_duck llm connect ollama
```

Connect to all configured providers:

```bash
rubber_duck llm connect
```

### Disconnect

Disconnect from a specific provider:

```bash
rubber_duck llm disconnect ollama
```

Disconnect from all providers:

```bash
rubber_duck llm disconnect
```

### Enable/Disable

Enable or disable a provider without disconnecting:

```bash
rubber_duck llm enable ollama
rubber_duck llm disable ollama
```

Disabled providers won't be used for requests even if connected.

## Provider-Specific Connection Details

### Mock Provider

The mock provider simulates connections for testing:
- Always available (no external service required)
- Configurable connection behaviors for testing
- Useful for development without API keys

### Ollama Provider

Ollama uses HTTP connections to a local service:
- Default URL: `http://localhost:11434`
- Validates connection by checking `/api/version` endpoint
- Health checks query available models
- No persistent connection required

To use Ollama:
1. Start Ollama service: `ollama serve`
2. Pull a model: `ollama pull llama2`
3. Connect via RubberDuck: `rubber_duck llm connect ollama`

### TGI Provider

Text Generation Inference uses HTTP/WebSocket connections:
- Default URL: `http://localhost:8080`
- Retrieves model information on connect
- Supports advanced features like flash attention
- Health checks verify server availability

To use TGI:
1. Start TGI server with a model
2. Connect via RubberDuck: `rubber_duck llm connect tgi`

## Configuration

Configure connection behavior in your application config:

```elixir
config :rubber_duck, :llm,
  connection_config: %{
    health_check_interval: 30_000,      # Health check every 30 seconds
    max_reconnect_attempts: 3,          # Reconnection attempts
    reconnect_delay: 5_000,             # Delay between reconnects
    connection_timeout: 10_000          # Connection timeout
  },
  providers: [
    %{
      name: :ollama,
      adapter: RubberDuck.LLM.Providers.Ollama,
      base_url: "http://localhost:11434",
      models: ["llama2", "mistral", "codellama"]
    },
    %{
      name: :tgi,
      adapter: RubberDuck.LLM.Providers.TGI,
      base_url: "http://localhost:8080",
      models: ["llama-3.1-8b"]
    }
  ]
```

## Connection States

Providers can be in one of the following states:

- **disconnected**: No active connection
- **connecting**: Connection attempt in progress
- **connected**: Active connection, provider is healthy
- **unhealthy**: Connected but failing health checks
- **disconnecting**: Disconnection in progress

## Health Monitoring

The system automatically monitors provider health:

1. **Periodic Health Checks**: Run every 30 seconds (configurable)
2. **Failure Threshold**: Provider marked unhealthy after 3 consecutive failures
3. **Automatic Recovery**: Providers can recover when health checks succeed

Health information includes:
- Current health status
- Available models (for Ollama)
- Model information (for TGI)
- Last successful check time

## Integration with LLM Service

The LLM Service automatically:
- Checks connection status before making requests
- Falls back to alternative providers if primary is disconnected
- Updates last usage time for connected providers
- Respects enabled/disabled status

## Error Handling

Connection errors are handled gracefully:

- **Connection Refused**: Service not running
- **Timeout**: Connection attempt exceeded timeout
- **HTTP Errors**: Invalid responses from the service
- **Network Errors**: General connectivity issues

When a provider fails, the system:
1. Logs the error with details
2. Updates the provider status
3. Attempts to use fallback providers
4. Returns clear error messages

## Programmatic Usage

You can also manage connections programmatically:

```elixir
# Connect to a provider
RubberDuck.LLM.ConnectionManager.connect(:ollama)

# Check if connected
RubberDuck.LLM.ConnectionManager.connected?(:ollama)

# Get detailed connection info
{:ok, info} = RubberDuck.LLM.ConnectionManager.get_connection_info(:ollama)

# Disconnect
RubberDuck.LLM.ConnectionManager.disconnect(:ollama)

# Get status of all providers
status = RubberDuck.LLM.ConnectionManager.status()
```

## Troubleshooting

### Ollama Connection Issues

1. **Service not running**: Start with `ollama serve`
2. **Wrong port**: Check Ollama is on port 11434
3. **No models**: Pull a model with `ollama pull <model>`

### TGI Connection Issues

1. **Service not running**: Start TGI server
2. **Model loading**: Ensure model is fully loaded
3. **Port conflicts**: Check TGI is on port 8080

### General Issues

1. **Check logs**: Connection errors are logged with details
2. **Verify configuration**: Ensure provider URLs are correct
3. **Test connectivity**: Use `curl` to test endpoints directly
4. **Review health status**: Use `rubber_duck llm status` for details