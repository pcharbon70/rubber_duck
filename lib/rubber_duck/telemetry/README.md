# RubberDuck Telemetry

This module provides comprehensive observability for the RubberDuck application through telemetry events and metrics.

## Overview

The telemetry system is built on top of Erlang's `:telemetry` library and provides:

- Automatic metric collection for Phoenix, Ecto, and Ash operations
- VM metrics (memory, run queue, etc.)
- Custom application metrics
- Structured logging with metadata
- Console reporting in development

## Architecture

### Components

1. **RubberDuck.Telemetry** - Main supervisor that manages all telemetry components
2. **RubberDuck.Telemetry.Measurements** - Periodic measurements for VM and application metrics  
3. **RubberDuck.Telemetry.Reporter** - Custom reporter for structured logging
4. **RubberDuck.Telemetry.AshHandler** - Event handlers for Ash framework operations

### Metrics Collected

#### Phoenix Metrics
- `phoenix.endpoint.start.system_time` - Endpoint request start time
- `phoenix.endpoint.stop.duration` - Total request duration
- `phoenix.router_dispatch.stop.duration` - Router dispatch duration

#### Database Metrics
- `rubber_duck.repo.query.total_time` - Total query execution time
- `rubber_duck.repo.query.decode_time` - Time spent decoding results
- `rubber_duck.repo.query.query_time` - Actual database query time
- `rubber_duck.repo.query.queue_time` - Connection pool wait time
- `rubber_duck.repo.query.idle_time` - Connection idle time

#### VM Metrics
- `vm.memory.total` - Total VM memory usage
- `vm.total_run_queue_lengths.total` - Total run queue length
- `vm.total_run_queue_lengths.cpu` - CPU run queue length
- `vm.total_run_queue_lengths.io` - IO run queue length

#### Ash Framework Metrics
- `ash.request.start.count` - Number of Ash requests started
- `ash.request.stop.duration` - Ash request duration
- `ash.request.error.count` - Number of Ash request errors

#### Custom RubberDuck Metrics
- `rubber_duck.analysis.start.count` - Analysis operations started
- `rubber_duck.analysis.stop.duration` - Analysis operation duration
- `rubber_duck.llm_request.count` - LLM API requests
- `rubber_duck.llm_request.duration` - LLM request duration
- `rubber_duck.code_file.indexed.count` - Files indexed
- `rubber_duck.embedding.generation.duration` - Embedding generation time

## Usage

### Emitting Custom Events

```elixir
# Start event
:telemetry.execute(
  [:rubber_duck, :custom_operation, :start],
  %{system_time: System.system_time()},
  %{operation_id: operation_id}
)

# Stop event with duration
:telemetry.execute(
  [:rubber_duck, :custom_operation, :stop],
  %{duration: duration},
  %{operation_id: operation_id, success: true}
)
```

### Adding New Metrics

To add new metrics, update the `metrics/0` function in `RubberDuck.Telemetry`:

```elixir
def metrics do
  [
    # ... existing metrics
    counter("rubber_duck.my_operation.count",
      tags: [:status]
    ),
    summary("rubber_duck.my_operation.duration", 
      unit: :millisecond,
      tags: [:status]
    )
  ]
end
```

### Configuration

Telemetry can be configured in `config/telemetry.exs`:

```elixir
config :rubber_duck, :telemetry,
  enabled: true,
  console_reporter: [
    enabled: Mix.env() == :dev,
    level: :info
  ],
  poller: [
    period: :timer.seconds(10)
  ]
```

## Monitoring

In development, metrics are logged to the console. For production:

1. Export metrics to monitoring services (Prometheus, DataDog, etc.)
2. Set up alerts based on error rates and latencies
3. Create dashboards for key metrics

## Best Practices

1. Always include relevant metadata in telemetry events
2. Use consistent naming conventions for event names
3. Keep measurements lightweight to avoid performance impact
4. Document all custom metrics and their meanings
5. Set appropriate measurement units (`:millisecond`, `:byte`, etc.)