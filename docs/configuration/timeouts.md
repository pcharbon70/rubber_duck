# Timeout Configuration Guide

RubberDuck provides a comprehensive timeout configuration system that allows you to tune timeouts across all components for optimal performance in your specific environment.

## Overview

The timeout configuration system provides:

- **Centralized configuration** in `config/timeouts.exs`
- **Runtime overrides** via environment variables
- **Dynamic timeout adjustment** based on context (model size, system load, etc.)
- **Type-safe access** through the `RubberDuck.Config.Timeouts` module

## Configuration Structure

Timeouts are organized hierarchically by component type:

```elixir
config :rubber_duck, :timeouts,
  channels: %{...},        # WebSocket and channel timeouts
  engines: %{...},         # Engine and processing timeouts
  tools: %{...},           # Tool execution timeouts
  llm_providers: %{...},   # LLM provider-specific timeouts
  chains: %{...},          # Chain of Thought timeouts
  workflows: %{...},       # Workflow execution timeouts
  agents: %{...},          # Agent coordination timeouts
  mcp: %{...},             # Model Context Protocol timeouts
  infrastructure: %{...},  # System infrastructure timeouts
  test: %{...}             # Testing-specific timeouts
```

## Default Timeouts

### Channels
- `conversation`: 60s - WebSocket conversation timeout
- `mcp_heartbeat`: 15s - MCP channel heartbeat interval
- `mcp_message_queue_cleanup`: 5m - Message queue cleanup interval

### Engines
- `default`: 5s - Default engine execution timeout
- `external_router`: 5m - External tool routing timeout
- `task_registry_cleanup`: 60s - Task registry cleanup interval

### Tools
- `default`: 30s - Default tool execution timeout
- `sandbox.minimal`: 5s - Strict sandbox timeout
- `sandbox.standard`: 15s - Balanced sandbox timeout
- `sandbox.enhanced`: 30s - Relaxed sandbox timeout
- `sandbox.maximum`: 60s - No restrictions sandbox timeout
- `external_registry_scan`: 5s - External tool scanning interval
- `telemetry_polling`: 10s - Telemetry data polling interval

### LLM Providers
- `default`: 30s - Default LLM request timeout
- `default_streaming`: 5m - Default streaming response timeout
- `health_check`: 5s - Provider health check timeout

Provider-specific:
- `ollama.request`: 60s
- `ollama.streaming`: 5m
- `tgi.request`: 2m
- `tgi.streaming`: 5m
- `anthropic.request`: 30s
- `openai.request`: 30s

### Chains
Each chain has a total timeout and individual step timeouts:

**Analysis Chain** (45s total):
- `understanding`: 10s
- `context_gathering`: 8s
- `pattern_identification`: 10s
- `relationship_mapping`: 10s
- `synthesis`: 7s

**Completion Chain** (20s total):
- `parse_context`: 5s
- `retrieve_patterns`: 4s
- `generate_initial`: 4s
- `refine_output`: 6s
- `validate_syntax`: 3s
- `optimize_result`: 4s
- `format_output`: 3s

### Infrastructure
- `circuit_breaker.call_timeout`: 30s
- `circuit_breaker.reset_timeout`: 60s
- `status_broadcaster.flush_interval`: 50ms
- `status_broadcaster.queue_limit`: 10,000
- `status_broadcaster.batch_size`: 100

## Runtime Configuration

### Environment Variables

You can override any timeout at runtime using environment variables:

```bash
# Channel timeouts
export RUBBER_DUCK_CHANNEL_TIMEOUT=120000  # 2 minutes

# Engine timeouts
export RUBBER_DUCK_ENGINE_DEFAULT_TIMEOUT=10000  # 10 seconds

# Tool timeouts
export RUBBER_DUCK_TOOL_DEFAULT_TIMEOUT=60000  # 1 minute

# LLM timeouts
export RUBBER_DUCK_LLM_DEFAULT_TIMEOUT=45000  # 45 seconds
export RUBBER_DUCK_LLM_STREAMING_TIMEOUT=600000  # 10 minutes

# Circuit breaker timeouts
export RUBBER_DUCK_CIRCUIT_BREAKER_TIMEOUT=45000
export RUBBER_DUCK_CIRCUIT_BREAKER_RESET_TIMEOUT=120000
```

### JSON Configuration

For complex timeout overrides, you can use a JSON configuration:

```bash
export RUBBER_DUCK_TIMEOUTS_JSON='{
  "channels": {
    "conversation": 120000,
    "mcp_heartbeat": 30000
  },
  "llm_providers": {
    "ollama": {
      "request": 120000,
      "streaming": 600000
    }
  }
}'
```

## Programmatic Access

Use the `RubberDuck.Config.Timeouts` module to access timeout values:

```elixir
# Get a specific timeout
timeout = Timeouts.get([:channels, :conversation])
# => 60_000

# Get with a default fallback
timeout = Timeouts.get([:custom, :timeout], 5_000)
# => 5_000

# Get all timeouts for a category
channel_timeouts = Timeouts.get_category(:channels)
# => %{conversation: 60_000, mcp_heartbeat: 15_000, ...}

# Dynamic timeout based on context
timeout = Timeouts.get_dynamic(
  [:llm_providers, :ollama, :request],
  %{model: "llama2:70b"}
)
# => 120_000 (doubled for large model)

# Check if a timeout exists
Timeouts.exists?([:channels, :conversation])
# => true

# Format timeout for display
Timeouts.format(60_000)
# => "60s"
```

## Dynamic Timeout Adjustment

The system supports dynamic timeout adjustment based on context:

### Model Size Modifiers
- Models with "70b": 2x timeout
- Models with "30b"/"34b": 1.5x timeout
- Models with "13b": 1.2x timeout

### Environment Modifiers
- Development: 1.5x timeout
- Test: 0.5x timeout
- Production: 1x timeout

### System Load Modifiers
- High load: 1.5x timeout
- Critical load: 2x timeout

Example usage:
```elixir
# Automatically adjusts timeout for large models
timeout = Timeouts.get_dynamic(
  [:llm_providers, :ollama, :request],
  %{model: "llama2:70b", env: :dev}
)
# => 180_000 (60s * 2 for model * 1.5 for dev)
```

## Best Practices

1. **Start with defaults**: The default timeouts are tuned for typical use cases
2. **Monitor timeout errors**: Use telemetry to track timeout occurrences
3. **Adjust gradually**: Increase timeouts in small increments
4. **Consider network latency**: Add extra time for remote services
5. **Use dynamic timeouts**: For model-specific or load-based adjustments
6. **Document changes**: Keep track of why timeouts were adjusted

## Monitoring Timeouts

Use the built-in telemetry events to monitor timeout behavior:

```elixir
:telemetry.attach(
  "timeout-handler",
  [:rubber_duck, :timeout],
  fn event, measurements, metadata, _config ->
    Logger.warn("Timeout occurred", 
      component: metadata.component,
      timeout: measurements.timeout,
      elapsed: measurements.elapsed
    )
  end,
  nil
)
```

## Common Timeout Scenarios

### Slow LLM Responses
For large models or slow providers:
```bash
export RUBBER_DUCK_LLM_DEFAULT_TIMEOUT=120000
export RUBBER_DUCK_LLM_STREAMING_TIMEOUT=900000
```

### High-Latency Networks
For cloud deployments with high latency:
```bash
export RUBBER_DUCK_TIMEOUTS_JSON='{
  "llm_providers": {
    "default": 60000,
    "health_check": 10000
  },
  "mcp": {
    "request": 60000
  }
}'
```

### Development Environment
Longer timeouts for debugging:
```bash
export RUBBER_DUCK_CHANNEL_TIMEOUT=300000  # 5 minutes
export RUBBER_DUCK_TOOL_DEFAULT_TIMEOUT=120000  # 2 minutes
```

### CI/CD Environment
Shorter timeouts for faster test runs:
```bash
export RUBBER_DUCK_TIMEOUTS_JSON='{
  "test": {
    "default": 2000,
    "integration": 5000,
    "slow_operations": 15000
  }
}'
```

## Troubleshooting

### Timeout Errors

If you're experiencing timeout errors:

1. Check the component's configured timeout:
   ```elixir
   Timeouts.get([:component, :name])
   ```

2. Review logs for actual execution time

3. Increase the timeout via environment variable:
   ```bash
   export RUBBER_DUCK_COMPONENT_TIMEOUT=<new_value>
   ```

4. Consider if the operation should be async

### Finding All Timeouts

List all configured timeout paths:
```elixir
RubberDuck.Config.Timeouts.list_paths()
# => [[:channels, :conversation], [:channels, :mcp_heartbeat], ...]
```

### Debugging Timeout Values

Check the final timeout value after all overrides:
```elixir
# In IEx
Application.get_env(:rubber_duck, :timeouts)
|> get_in([:channels, :conversation])
# => 60_000
```