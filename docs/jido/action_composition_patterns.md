# Action Composition Patterns

This document describes the advanced action composition patterns and middleware system available in RubberDuck's Jido implementation.

## Overview

The action composition system provides sophisticated patterns for combining and orchestrating actions, along with a middleware system for cross-cutting concerns. All patterns use proper Jido signals for coordination and CloudEvents-compliant event emission.

## Workflow Actions

### PipelineAction

Executes actions in sequence, piping the output of each action as input to the next.

```elixir
params = %{
  stages: [
    %{action: ValidateDataAction, params: %{schema: :user}},
    %{action: TransformDataAction, transform: &normalize_user/1},
    %{action: SaveDataAction, params: %{table: :users}}
  ],
  initial_data: %{name: "John", email: "john@example.com"}
}

{:ok, result} = PipelineAction.run(params, context)
```

**Features:**
- Sequential execution with data transformation
- Optional transformation functions between stages
- Stop-on-error or continue-on-error modes
- Stage-level signal emission
- Duration tracking per stage

### FanoutAction

Broadcasts the same input to multiple actions in parallel.

```elixir
params = %{
  targets: [
    %{action: NotifySlackAction, params: %{channel: "#alerts"}},
    %{action: LogToFileAction, params: %{file: "alerts.log"}},
    %{action: SendEmailAction, params: %{to: "admin@example.com"}}
  ],
  input_data: %{alert: "System critical", level: :error},
  aggregation: :all_success
}

{:ok, result} = FanoutAction.run(params, context)
```

**Aggregation Strategies:**
- `:all_success` - Requires all targets to succeed
- `:any_success` - Succeeds if any target succeeds
- `:collect_all` - Collects all results regardless of status
- `:race` - Returns first completed result

**Features:**
- Configurable max concurrency
- Timeout handling
- Per-target signal emission
- Batched execution for large target lists

### SagaAction

Implements distributed transactions with compensation/rollback.

```elixir
params = %{
  steps: [
    %{
      action: CreateOrderAction,
      params: %{order_data: order},
      compensate: CancelOrderAction
    },
    %{
      action: ChargePaymentAction,
      params: %{amount: 100.00},
      compensate: RefundPaymentAction
    },
    %{
      action: ShipItemAction,
      params: %{item_id: "123"},
      compensate: CancelShipmentAction
    }
  ],
  transaction_data: %{order_id: "order_123"}
}

{:ok, result} = SagaAction.run(params, context)
```

**Features:**
- Automatic compensation on failure
- Multiple compensation strategies (reverse, parallel, custom)
- Transaction isolation levels
- Checkpoint saving for recovery
- Step-level signal emission

### CircuitAction

Circuit breaker pattern for fault tolerance.

```elixir
params = %{
  protected_action: DatabaseQueryAction,
  action_params: %{query: "SELECT * FROM users"},
  failure_threshold: 5,
  recovery_timeout: 60_000,
  fallback_action: CachedDataAction
}

{:ok, result} = CircuitAction.run(params, context)
```

**Circuit States:**
- **Closed**: Normal operation, requests pass through
- **Open**: Failing, requests rejected or use fallback
- **Half-Open**: Testing recovery with limited requests

**Features:**
- Configurable failure thresholds
- Automatic recovery attempts
- Optional fallback actions
- Circuit state persistence in ETS
- Detailed metrics collection

## Middleware System

The middleware system provides cross-cutting concerns that can be applied to any action.

### Creating a Middleware Chain

```elixir
alias RubberDuck.Jido.Actions.Middleware.Chain

chain = Chain.new()
  |> Chain.add(LoggingMiddleware, level: :info)
  |> Chain.add(AuthMiddleware, required_roles: [:admin])
  |> Chain.add(RateLimitMiddleware, max_requests: 100)
  |> Chain.add(CacheMiddleware, ttl: 300)
  |> Chain.add(MonitoringMiddleware, sample_rate: 0.1)

result = Chain.execute(chain, MyAction, params, context)
```

### Standard Middleware

#### LoggingMiddleware

Structured logging of action execution.

**Options:**
- `level` - Log level (:debug, :info, :warning, :error)
- `log_params` - Whether to log parameters
- `log_result` - Whether to log results
- `filter_keys` - Keys to filter from logs (passwords, tokens, etc.)

#### AuthMiddleware

Authentication and authorization checks.

**Options:**
- `required_roles` - Roles required to execute
- `required_permissions` - Permissions required
- `validate_token` - Whether to validate auth tokens
- `allow_anonymous` - Allow anonymous execution
- `custom_validator` - Custom validation function

#### RateLimitMiddleware

Token bucket rate limiting.

**Options:**
- `max_requests` - Maximum requests in window
- `window_ms` - Time window in milliseconds
- `burst_size` - Burst capacity above normal rate
- `scope` - Rate limit scope (:global, :per_user, :per_action)

#### CacheMiddleware

Result caching with TTL.

**Options:**
- `ttl` - Time to live in seconds
- `cache_on` - When to cache (:success, :all)
- `key_fn` - Custom cache key generation
- `should_cache_fn` - Determine if result should be cached

#### MonitoringMiddleware

Metrics collection and alerting.

**Options:**
- `collect_metrics` - Metrics to collect
- `sample_rate` - Sampling rate (0.0-1.0)
- `alert_thresholds` - Thresholds for alerting
- `custom_metrics_fn` - Custom metrics collection

### Custom Middleware

Create custom middleware by implementing the behaviour:

```elixir
defmodule MyCustomMiddleware do
  use RubberDuck.Jido.Actions.Middleware, priority: 75
  
  @impl true
  def init(opts) do
    # Initialize middleware state
    {:ok, opts}
  end
  
  @impl true
  def call(action, params, context, next) do
    # Pre-processing
    Logger.info("Before action: #{inspect(action)}")
    
    # Call next middleware or action
    # You can modify params/context here
    result = next.(params, context)
    
    # Post-processing
    case result do
      {:ok, data, ctx} ->
        Logger.info("Action succeeded")
        {:ok, data, ctx}
      {:error, reason} ->
        Logger.error("Action failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
```

## Signal Coordination

All workflow actions emit proper Jido signals for coordination:

```elixir
# Pipeline signals
"pipeline.started"
"pipeline.stage.completed"
"pipeline.stage.failed"
"pipeline.completed"
"pipeline.failed"

# Fanout signals
"fanout.started"
"fanout.target.completed"
"fanout.target.failed"
"fanout.completed"
"fanout.failed"

# Saga signals
"saga.started"
"saga.step.completed"
"saga.step.failed"
"saga.compensating"
"saga.compensation.completed"
"saga.compensation.failed"
"saga.completed"

# Circuit signals
"circuit.call.success"
"circuit.call.failed"
"circuit.opened"
"circuit.closed"
"circuit.rejected"
"circuit.fallback.success"
"circuit.recovery_failed"
```

## Integration with Base Actions

The composition patterns work seamlessly with the base action modules:

```elixir
# Use RequestAction with circuit breaker
defmodule ProtectedAPIAction do
  use RubberDuck.Jido.Actions.Base.RequestAction,
    timeout: 5_000,
    retry_attempts: 3
end

# Wrap with circuit breaker
params = %{
  protected_action: ProtectedAPIAction,
  action_params: %{url: "https://api.example.com"},
  failure_threshold: 5
}

CircuitAction.run(params, context)
```

## Telemetry Integration

All workflow actions and middleware emit telemetry events:

```elixir
# Attach to telemetry events
:telemetry.attach(
  "action-metrics",
  [:rubber_duck, :action, :execution, :stop],
  &handle_metrics/4,
  nil
)

def handle_metrics(_event, measurements, metadata, _config) do
  Logger.info("Action #{metadata.action} took #{measurements.duration}μs")
end
```

## Best Practices

1. **Use appropriate patterns**: Choose the right composition pattern for your use case
2. **Configure middleware order**: Higher priority middleware executes first
3. **Handle errors gracefully**: Use fallbacks and compensation where appropriate
4. **Monitor performance**: Use MonitoringMiddleware for production systems
5. **Cache judiciously**: Cache expensive operations but watch memory usage
6. **Test compositions**: Test complex workflows thoroughly
7. **Use signals for coordination**: Leverage signals for loose coupling
8. **Document workflows**: Complex compositions should be well-documented

## Examples

### Complex Pipeline with Middleware

```elixir
# Define pipeline with authentication and caching
chain = Chain.new()
  |> Chain.add(AuthMiddleware, required_roles: [:data_processor])
  |> Chain.add(CacheMiddleware, ttl: 600)
  |> Chain.add(LoggingMiddleware, level: :info)

params = %{
  stages: [
    %{action: FetchDataAction},
    %{action: ValidateDataAction},
    %{action: EnrichDataAction},
    %{action: StoreDataAction}
  ],
  initial_data: %{source: "api"}
}

Chain.execute(chain, PipelineAction, params, context)
```

### Resilient Fanout with Circuit Breakers

```elixir
# Protect each target with circuit breaker
protected_targets = Enum.map(notification_targets, fn target ->
  %{
    action: CircuitAction,
    params: %{
      protected_action: target.action,
      action_params: target.params,
      failure_threshold: 3,
      fallback_action: LogNotificationAction
    }
  }
end)

params = %{
  targets: protected_targets,
  input_data: alert_data,
  aggregation: :any_success,
  max_concurrency: 5
}

FanoutAction.run(params, context)
```

### Distributed Transaction with Monitoring

```elixir
# Monitor saga execution
chain = Chain.new()
  |> Chain.add(MonitoringMiddleware, 
      alert_thresholds: %{max_duration: 5000})
  |> Chain.add(LoggingMiddleware, log_params: true)

saga_params = %{
  steps: [
    %{action: ReserveInventoryAction, compensate: ReleaseInventoryAction},
    %{action: ProcessPaymentAction, compensate: RefundPaymentAction},
    %{action: CreateShipmentAction, compensate: CancelShipmentAction}
  ],
  compensation_strategy: :reverse_order,
  save_checkpoints: true
}

Chain.execute(chain, SagaAction, saga_params, context)
```