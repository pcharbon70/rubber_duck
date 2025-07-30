# Provider Agents Architecture

## Overview

Provider agents are autonomous agents that wrap individual LLM providers (OpenAI, Anthropic, Local models) to handle provider-specific concerns while providing a uniform signal-based interface to the LLM Router Agent.

## Architecture

### Base Provider Agent

The `ProviderAgent` module provides common functionality for all provider agents:

```elixir
use RubberDuck.Agents.ProviderAgent,
  name: "provider_name",
  description: "Provider description"
```

#### Core Features

1. **Rate Limiting**
   - Configurable per-provider limits
   - Time window or concurrent request based
   - Automatic request rejection when limited

2. **Circuit Breaking**
   - Opens after consecutive failures
   - Half-open state for recovery testing
   - Configurable thresholds and timeouts

3. **Metrics Collection**
   - Request counts (total, successful, failed)
   - Token usage tracking
   - Latency measurements
   - Success rate calculation

4. **Request Tracking**
   - Active request monitoring
   - Concurrent request limiting
   - Request lifecycle management

### Provider-Specific Agents

#### OpenAI Provider Agent

Specializes in handling OpenAI GPT models with features:

- Function calling configuration
- Streaming response support
- Model-specific rate limits (RPM tiers)
- GPT-4 and GPT-3.5 model support

```elixir
# Special signals
configure_functions - Set up function calling
stream_request - Handle streaming completions
```

#### Anthropic Provider Agent  

Manages Claude models with capabilities:

- Vision support for Claude 3
- Large context window handling (200k tokens)
- Safety feature configuration
- Content filtering

```elixir
# Special signals
configure_safety - Set content filtering rules
vision_request - Process images with Claude 3
```

#### Local Provider Agent

Handles local models (Ollama, llama.cpp) with features:

- Resource monitoring (CPU, GPU, memory)
- Dynamic model loading/unloading
- Performance tracking per model
- Offline operation

```elixir
# Special signals
load_model - Load a model into memory
unload_model - Free model resources
get_resource_status - Check system resources
list_available_models - List local models
```

## Signal Flow

### Common Signals (All Providers)

#### Input Signals

```json
{
  "type": "provider_request",
  "data": {
    "request_id": "req-123",
    "messages": [...],
    "model": "gpt-4",
    "temperature": 0.7,
    "max_tokens": 1000
  }
}
```

```json
{
  "type": "feature_check",
  "data": {
    "feature": "streaming"
  }
}
```

```json
{
  "type": "get_provider_status"
}
```

#### Output Signals

```json
{
  "type": "provider_response",
  "data": {
    "request_id": "req-123",
    "response": {...},
    "provider": "openai",
    "model": "gpt-4",
    "latency_ms": 523
  }
}
```

```json
{
  "type": "provider_error",
  "data": {
    "request_id": "req-123",
    "error_type": "rate_limited",
    "error": "Provider rate limit exceeded"
  }
}
```

```json
{
  "type": "provider_status",
  "data": {
    "provider": "openai",
    "status": "healthy",
    "circuit_breaker": {
      "state": "closed",
      "failure_count": 0
    },
    "rate_limiter": {
      "limit": 60,
      "window_ms": 60000,
      "current_count": 15
    },
    "metrics": {
      "total_requests": 1000,
      "success_rate": 98.5
    }
  }
}
```

## Integration with LLM Router

Provider agents integrate with the LLM Router Agent through signals:

1. **Registration**: Provider agents register with the router on startup
2. **Health Monitoring**: Regular status updates to the router
3. **Request Handling**: Router sends provider_request signals
4. **Response/Error**: Agents emit provider_response or provider_error

## Rate Limiting Strategies

### API-Based Providers (OpenAI, Anthropic)

- Time window based (requests per minute/hour)
- Automatic window reset
- Pre-emptive rejection to avoid API errors

### Local Providers

- Concurrent request limiting
- Resource-based constraints
- Dynamic adjustment based on system load

## Circuit Breaker States

```
CLOSED → (failures) → OPEN → (timeout) → HALF_OPEN → (success) → CLOSED
                         ↑                    ↓
                         ←─── (failure) ──────┘
```

- **Closed**: Normal operation
- **Open**: Rejecting all requests
- **Half-Open**: Testing with limited requests

## Error Handling

Provider agents handle various error types:

1. **Rate Limiting**: Pre-emptive rejection with clear error
2. **Circuit Breaking**: Fast-fail when provider is unhealthy  
3. **Provider Errors**: Wrapped and enriched with context
4. **Resource Constraints**: Local provider specific
5. **Model Availability**: Check before processing

## Metrics and Monitoring

Each provider agent tracks:

- Request volume and success rates
- Token usage and costs
- Latency percentiles
- Circuit breaker state changes
- Rate limit utilization
- Model-specific performance (local)

## Configuration

Provider agents are configured through:

1. Environment variables (API keys, URLs)
2. Runtime configuration (ConfigLoader)
3. Dynamic updates via signals
4. Provider-specific defaults

Example configuration:

```elixir
%ProviderConfig{
  name: :openai,
  api_key: System.get_env("OPENAI_API_KEY"),
  models: ["gpt-4", "gpt-3.5-turbo"],
  rate_limit: {3000, :minute},
  timeout: 120_000
}
```

## Best Practices

1. **Fail Fast**: Use circuit breakers to prevent cascading failures
2. **Resource Awareness**: Monitor local resources before accepting requests
3. **Graceful Degradation**: Provide clear errors when limited
4. **Metrics First**: Track everything for optimization
5. **Provider Abstraction**: Hide provider specifics behind signals