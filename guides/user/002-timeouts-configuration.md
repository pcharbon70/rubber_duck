# Timeout Configuration Guide

This guide explains how to configure timeouts in RubberDuck to optimize performance for your specific use case. Whether you're running locally with fast models or connecting to remote services over slower networks, proper timeout configuration ensures smooth operation.

## Table of Contents

1. [Overview](#overview)
2. [Configuration Methods](#configuration-methods)
3. [Channel Timeouts](#channel-timeouts)
4. [Engine Timeouts](#engine-timeouts)
5. [Tool Execution Timeouts](#tool-execution-timeouts)
6. [LLM Provider Timeouts](#llm-provider-timeouts)
7. [Chain of Thought Timeouts](#chain-of-thought-timeouts)
8. [Infrastructure Timeouts](#infrastructure-timeouts)
9. [Common Scenarios](#common-scenarios)
10. [Troubleshooting](#troubleshooting)

## Overview

RubberDuck uses timeouts to prevent operations from hanging indefinitely. The system provides:

- **Sensible defaults** that work for most use cases
- **Granular control** over individual component timeouts
- **Multiple override methods** for different deployment scenarios
- **Dynamic adjustments** based on runtime conditions

All timeout values are specified in **milliseconds**.

## Configuration Methods

You can configure timeouts using three methods, listed in order of precedence (highest to lowest):

### 1. Environment Variables (Highest Priority)

Individual timeout overrides:
```bash
export RUBBER_DUCK_CHANNEL_TIMEOUT=120000        # 2 minutes
export RUBBER_DUCK_LLM_DEFAULT_TIMEOUT=60000     # 1 minute
export RUBBER_DUCK_TOOL_DEFAULT_TIMEOUT=45000    # 45 seconds
```

### 2. JSON Configuration

For bulk overrides:
```bash
export RUBBER_DUCK_TIMEOUTS_JSON='{
  "channels": {
    "conversation": 120000,
    "mcp_heartbeat": 30000
  },
  "llm_providers": {
    "ollama": {
      "request": 90000,
      "streaming": 600000
    }
  }
}'
```

### 3. Configuration Files (Lowest Priority)

Edit `config/timeouts.exs` for permanent changes:
```elixir
config :rubber_duck, :timeouts, %{
  channels: %{
    conversation: 360_000  # Default: 6 minutes
  }
}
```

## Channel Timeouts

Channel timeouts control WebSocket connections and heartbeat intervals.

### Configuration Options

```elixir
channels: %{
  conversation: 360_000,          # WebSocket conversation timeout (6 min)
  mcp_heartbeat: 30_000,          # MCP channel heartbeat interval
  mcp_message_queue_cleanup: 600_000  # Message queue cleanup (10 min)
}
```

### Environment Variable Overrides

```bash
# Increase conversation timeout for slow responses
export RUBBER_DUCK_CHANNEL_TIMEOUT=180000  # 3 minutes

# More frequent heartbeats for unstable connections
export RUBBER_DUCK_MCP_HEARTBEAT_TIMEOUT=10000  # 10 seconds
```

### Example: High-Latency Network

For deployments with high network latency:
```bash
export RUBBER_DUCK_TIMEOUTS_JSON='{
  "channels": {
    "conversation": 180000,
    "mcp_heartbeat": 30000,
    "mcp_message_queue_cleanup": 600000
  }
}'
```

## Engine Timeouts

Engine timeouts control task processing and execution limits.

### Configuration Options

```elixir
engines: %{
  default: 10_000,                    # Default engine execution
  external_router: 600_000,           # External tool routing (10 min)
  task_registry_cleanup: 120_000,     # Task cleanup interval (2 min)
  # Conversation engines
  generation_conversation: 360_000,   # Code generation (6 min)
  analysis_conversation: 240_000,     # Code analysis (4 min) 
  complex_conversation: 480_000,      # Complex tasks (8 min)
  problem_solver: 600_000            # Problem solving (10 min)
}
```

### Environment Variable Overrides

```bash
# Quick operations
export RUBBER_DUCK_ENGINE_DEFAULT_TIMEOUT=3000  # 3 seconds

# Long-running external tools
export RUBBER_DUCK_ENGINE_EXTERNAL_ROUTER_TIMEOUT=600000  # 10 minutes
```

### Example: CPU-Intensive Tasks

For engines performing heavy computation:
```bash
export RUBBER_DUCK_TIMEOUTS_JSON='{
  "engines": {
    "default": 10000,
    "external_router": 900000,
    "task_registry_cleanup": 120000
  }
}'
```

## Tool Execution Timeouts

Tool timeouts vary based on security level and complexity.

### Configuration Options

```elixir
tools: %{
  default: 30_000,              # Default tool execution
  sandbox: %{
    minimal: 5_000,             # Strict security, quick ops
    standard: 15_000,           # Balanced security
    enhanced: 30_000,           # Relaxed security
    maximum: 60_000             # No restrictions
  },
  external_registry_scan: 5_000,  # Tool discovery
  telemetry_polling: 10_000       # Metrics collection
}
```

### Environment Variable Overrides

```bash
# Faster tool execution
export RUBBER_DUCK_TOOL_DEFAULT_TIMEOUT=20000  # 20 seconds

# Adjust sandbox levels
export RUBBER_DUCK_TOOL_SANDBOX_MINIMAL_TIMEOUT=3000
export RUBBER_DUCK_TOOL_SANDBOX_MAXIMUM_TIMEOUT=120000
```

### Example: Development Environment

For development with debugging tools:
```bash
export RUBBER_DUCK_TIMEOUTS_JSON='{
  "tools": {
    "default": 60000,
    "sandbox": {
      "minimal": 10000,
      "standard": 30000,
      "enhanced": 60000,
      "maximum": 120000
    }
  }
}'
```

## LLM Provider Timeouts

LLM timeouts are critical for model performance and vary significantly by model size and provider.

### Configuration Options

```elixir
llm_providers: %{
  default: 30_000,              # Default request timeout
  default_streaming: 300_000,   # Default streaming (5 min)
  health_check: 5_000,          # Provider health checks
  
  # Provider-specific
  ollama: %{
    request: 60_000,            # Standard Ollama request
    streaming: 300_000          # Ollama streaming
  },
  tgi: %{
    request: 120_000,           # TGI request (2 min)
    streaming: 300_000,         # TGI streaming
    health_check: 10_000        # TGI health check
  },
  anthropic: %{
    request: 30_000             # Anthropic API
  },
  openai: %{
    request: 30_000             # OpenAI API
  }
}
```

### Environment Variable Overrides

```bash
# General LLM timeouts
export RUBBER_DUCK_LLM_DEFAULT_TIMEOUT=45000
export RUBBER_DUCK_LLM_STREAMING_TIMEOUT=600000

# Provider-specific
export RUBBER_DUCK_LLM_OLLAMA_TIMEOUT=90000
export RUBBER_DUCK_LLM_TGI_TIMEOUT=180000
```

### Example: Large Language Models

For 70B+ parameter models:
```bash
export RUBBER_DUCK_TIMEOUTS_JSON='{
  "llm_providers": {
    "default": 60000,
    "default_streaming": 900000,
    "ollama": {
      "request": 180000,
      "streaming": 1200000
    },
    "tgi": {
      "request": 240000,
      "streaming": 1200000
    }
  }
}'
```

### Dynamic Model-Based Adjustments

The system automatically adjusts timeouts based on model size:
- **70B models**: 2x base timeout
- **30B/34B models**: 1.5x base timeout  
- **13B models**: 1.2x base timeout
- **7B and smaller**: 1x base timeout

## Chain of Thought Timeouts

Chains have both total timeouts and individual step timeouts.

### Configuration Options

```elixir
chains: %{
  analysis: %{
    total: 90_000,              # Total chain timeout (1.5 min)
    steps: %{
      understanding: 20_000,     # Code comprehension
      context_gathering: 16_000,  # Context analysis
      pattern_identification: 20_000,
      relationship_mapping: 20_000,
      synthesis: 14_000          # Final synthesis
    }
  },
  generation: %{
    total: 300_000,             # Total generation timeout (5 min)
    steps: %{
      understand_requirements: 20_000,
      review_context: 120_000,   # Can be slow with large codebases
      plan_structure: 20_000,
      identify_dependencies: 14_000,
      generate_implementation: 30_000,
      add_documentation: 120_000,  # Documentation generation
      generate_tests: 24_000,
      validate_output: 120_000,    # Validation checks
      provide_alternatives: 20_000
    }
  },
  completion: %{
    total: 40_000,
    steps: %{
      parse_context: 10_000,
      retrieve_patterns: 8_000,
      generate_initial: 8_000,
      refine_output: 12_000,
      validate_syntax: 6_000,
      optimize_result: 8_000,
      format_output: 6_000
    }
  }
}
```

### Example: Complex Analysis Tasks

For deep code analysis:
```bash
export RUBBER_DUCK_TIMEOUTS_JSON='{
  "chains": {
    "analysis": {
      "total": 90000,
      "steps": {
        "understanding": 20000,
        "context_gathering": 15000,
        "pattern_identification": 20000,
        "relationship_mapping": 20000,
        "synthesis": 15000
      }
    }
  }
}'
```

## Infrastructure Timeouts

System-level timeouts for reliability and performance.

### Configuration Options

```elixir
infrastructure: %{
  circuit_breaker: %{
    call_timeout: 30_000,       # Individual call timeout
    reset_timeout: 60_000       # Recovery period
  },
  status_broadcaster: %{
    flush_interval: 50,         # Message batching (ms)
    queue_limit: 10_000,        # Max queued messages
    batch_size: 100             # Messages per batch
  },
  error_boundary: %{
    default: 5_000              # Error recovery timeout
  }
}
```

### Environment Variable Overrides

```bash
# Circuit breaker adjustments
export RUBBER_DUCK_CIRCUIT_BREAKER_TIMEOUT=45000
export RUBBER_DUCK_CIRCUIT_BREAKER_RESET_TIMEOUT=120000

# Status broadcasting tuning
export RUBBER_DUCK_STATUS_FLUSH_INTERVAL=100
```

### Example: High-Throughput System

For systems handling many concurrent requests:
```bash
export RUBBER_DUCK_TIMEOUTS_JSON='{
  "infrastructure": {
    "circuit_breaker": {
      "call_timeout": 20000,
      "reset_timeout": 30000
    },
    "status_broadcaster": {
      "flush_interval": 25,
      "queue_limit": 50000,
      "batch_size": 500
    }
  }
}'
```

## Common Scenarios

### Local Development

Optimized for fast iteration and debugging:
```bash
export RUBBER_DUCK_TIMEOUTS_JSON='{
  "channels": {"conversation": 300000},
  "engines": {"default": 10000},
  "tools": {"default": 60000},
  "llm_providers": {"default": 120000}
}'
```

### Production with Remote LLMs

For cloud-deployed LLMs with network latency:
```bash
export RUBBER_DUCK_TIMEOUTS_JSON='{
  "channels": {"conversation": 180000},
  "llm_providers": {
    "default": 60000,
    "default_streaming": 600000,
    "health_check": 10000
  },
  "infrastructure": {
    "circuit_breaker": {
      "call_timeout": 45000,
      "reset_timeout": 90000
    }
  }
}'
```

### CI/CD Pipeline

Fast timeouts for automated testing:
```bash
export RUBBER_DUCK_TIMEOUTS_JSON='{
  "channels": {"conversation": 30000},
  "engines": {"default": 2000},
  "tools": {"default": 10000},
  "llm_providers": {"default": 15000},
  "test": {
    "default": 2000,
    "integration": 5000,
    "slow_operations": 10000
  }
}'
```

### Edge Deployment

For resource-constrained environments:
```bash
export RUBBER_DUCK_TIMEOUTS_JSON='{
  "engines": {"default": 3000},
  "tools": {
    "default": 15000,
    "sandbox": {"minimal": 3000, "standard": 8000}
  },
  "infrastructure": {
    "status_broadcaster": {
      "flush_interval": 100,
      "queue_limit": 1000,
      "batch_size": 20
    }
  }
}'
```

## Troubleshooting

### Timeout Errors

If you see timeout errors:

1. **Identify the component**:
   ```elixir
   # In IEx console
   RubberDuck.Config.Timeouts.get([:component, :name])
   ```

2. **Check current configuration**:
   ```elixir
   RubberDuck.Config.Timeouts.all()
   ```

3. **Increase the specific timeout**:
   ```bash
   export RUBBER_DUCK_COMPONENT_TIMEOUT=<new_value>
   ```

### Performance Issues

For slow operations:

1. **Enable timeout monitoring**:
   ```elixir
   # Monitor which operations are close to timing out
   :telemetry.attach(
     "timeout-monitor",
     [:rubber_duck, :operation, :stop],
     fn _event, %{duration: duration}, %{timeout: timeout}, _config ->
       if duration > timeout * 0.8 do
         Logger.warn("Operation used #{duration}ms of #{timeout}ms timeout")
       end
     end,
     nil
   )
   ```

2. **Analyze timeout usage**:
   ```elixir
   # See formatted timeout values
   RubberDuck.Config.Timeouts.list_paths()
   |> Enum.map(fn path ->
     value = RubberDuck.Config.Timeouts.get(path)
     formatted = RubberDuck.Config.Timeouts.format(value)
     {path, formatted}
   end)
   ```

### Dynamic Timeout Verification

Test how timeouts adjust dynamically:
```elixir
# Check timeout with context
base = RubberDuck.Config.Timeouts.get([:llm_providers, :ollama, :request])
# => 60000

# With large model
adjusted = RubberDuck.Config.Timeouts.get_dynamic(
  [:llm_providers, :ollama, :request],
  %{model: "llama2:70b"}
)
# => 120000 (doubled)

# With multiple factors
complex = RubberDuck.Config.Timeouts.get_dynamic(
  [:llm_providers, :ollama, :request],
  %{model: "llama2:70b", env: :dev, load: :high}
)
# => 270000 (base * 2 * 1.5 * 1.5)
```

## Best Practices

1. **Start with defaults** - Only adjust timeouts when you encounter issues
2. **Monitor before adjusting** - Use telemetry to understand actual execution times
3. **Adjust incrementally** - Increase timeouts by 50% at a time
4. **Consider the full chain** - If LLM timeouts increase, consider increasing channel timeouts too
5. **Document your changes** - Keep notes on why timeouts were adjusted
6. **Use environment-specific configs** - Different timeouts for dev/staging/production
7. **Review periodically** - As models and infrastructure improve, timeouts may need reduction

## Summary

RubberDuck's timeout configuration system provides the flexibility needed to run efficiently in any environment. By understanding each component's timeout requirements and using the appropriate configuration method, you can ensure optimal performance for your specific use case.