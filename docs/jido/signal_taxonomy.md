# Signal Taxonomy Documentation

This document describes the standardized signal taxonomy and routing system for the RubberDuck platform. All signals are CloudEvents-compliant through Jido.Signal integration.

## Overview

The signal taxonomy provides a structured categorization of signals with intelligent routing, priority handling, and dead letter queue management. This ensures consistent signal handling across the distributed agent system.

## Signal Categories

### 1. Request Signals
- **Purpose**: Initiate actions, workflows, or processes
- **Patterns**: `*.request`, `*.initiate`, `*.start`, `*.begin`
- **Default Priority**: Normal
- **Examples**:
  - `analysis.request` - Request code analysis
  - `generation.request.create` - Request content generation
  - `workflow.initiate` - Start a workflow

### 2. Event Signals
- **Purpose**: Indicate state changes or occurrences
- **Patterns**: `*.created`, `*.updated`, `*.deleted`, `*.completed`, `*.failed`
- **Default Priority**: Normal
- **Examples**:
  - `user.created` - User was created
  - `file.updated` - File was modified
  - `process.completed` - Process finished successfully

### 3. Command Signals
- **Purpose**: Direct imperative actions
- **Patterns**: `*.execute`, `*.run`, `*.stop`, `*.cancel`, `*.pause`
- **Default Priority**: High
- **Examples**:
  - `server.execute` - Execute server command
  - `job.cancel` - Cancel running job
  - `system.restart` - Restart system component

### 4. Query Signals
- **Purpose**: Request information retrieval
- **Patterns**: `*.query`, `*.fetch`, `*.get`, `*.list`, `*.search`
- **Default Priority**: Low
- **Examples**:
  - `user.query` - Query user information
  - `metrics.fetch` - Fetch metrics data
  - `logs.search` - Search through logs

### 5. Notification Signals
- **Purpose**: Provide alerts, warnings, or status updates
- **Patterns**: `*.notify`, `*.alert`, `*.warning`, `*.info`, `*.error`
- **Default Priority**: Normal
- **Examples**:
  - `system.alert` - System alert notification
  - `health.warning` - Health check warning
  - `status.notify` - Status update notification

## Signal Structure

All signals must conform to CloudEvents specification via Jido.Signal:

```elixir
%{
  # Required fields
  type: "domain.action",      # Hierarchical signal type
  source: "agent:123",         # Signal origin identifier
  data: %{},                   # Signal payload
  
  # Optional fields
  id: "sig_abc123",           # Unique signal ID (auto-generated if missing)
  time: "2024-01-01T00:00:00Z", # ISO 8601 timestamp (auto-generated if missing)
  subject: "resource:456",     # Resource identifier
  datacontenttype: "application/json",
  dataschema: "https://example.com/schema"
}
```

## Using the Signal Taxonomy

### 1. Signal Category Module

```elixir
alias RubberDuck.Jido.Signals.SignalCategory

# Check valid categories
SignalCategory.valid_category?(:request)  # => true

# Infer category from signal type
{:ok, :event} = SignalCategory.infer_category("user.created")

# Get default priority
priority = SignalCategory.default_priority(:command)  # => :high

# Create signal specification
spec = SignalCategory.create_signal_spec(
  "analysis.request",
  :request,
  priority: :high,
  metadata: %{urgency: "immediate"}
)
```

### 2. Signal Validation

```elixir
alias RubberDuck.Jido.Signals.SignalValidator

# Validate a signal
signal = %{
  type: "user.created",
  source: "agent:123",
  data: %{user_id: "u456"}
}

{:ok, validated} = SignalValidator.validate(signal)
# Adds: category, id, time

# Validate as Jido.Signal
{:ok, jido_signal} = SignalValidator.validate_jido_signal(signal)

# Batch validation
signals = [signal1, signal2, signal3]
{:ok, valid_signals} = SignalValidator.validate_batch(signals)
```

### 3. Signal Routing

```elixir
alias RubberDuck.Jido.Signals.SignalRouter

# Start the router
{:ok, _pid} = SignalRouter.start_link(
  routing_strategy: :round_robin,
  max_handlers_per_pattern: 10
)

# Register routes
SignalRouter.register_route("analysis.*", AnalysisHandler, 
  category: :request,
  priority: :high
)

SignalRouter.register_route(~r/^user\..*/, UserHandler)

# Route a signal
signal = %{type: "analysis.request", source: "cli", data: %{}}
{:ok, handlers} = SignalRouter.route_signal(signal)

# Get routing metrics
metrics = SignalRouter.get_metrics()
```

#### Routing Strategies

- **`:round_robin`** - Distribute signals evenly across handlers
- **`:random`** - Random handler selection
- **`:least_loaded`** - Route to handler with lowest load
- **`:sticky`** - Always use the same handler for a pattern

### 4. Priority Handling

```elixir
alias RubberDuck.Jido.Signals.SignalPriority

# Start priority queue
{:ok, _pid} = SignalPriority.start_link(
  max_queue_size: 10_000,
  ratios: %{
    critical: 1.0,   # Always process
    high: 0.7,       # 70% processing rate
    normal: 0.4,     # 40% processing rate
    low: 0.1         # 10% processing rate
  }
)

# Enqueue with priority
SignalPriority.enqueue(signal, :critical)

# Dequeue based on priority
{:ok, entry} = SignalPriority.dequeue()

# Batch dequeue
{:ok, entries} = SignalPriority.dequeue_batch(10)

# Check queue sizes
sizes = SignalPriority.queue_sizes()
# => %{critical: 0, high: 2, normal: 5, low: 10}
```

### 5. Dead Letter Queue

```elixir
alias RubberDuck.Jido.Signals.DeadLetterQueue

# Start DLQ
{:ok, _pid} = DeadLetterQueue.start_link(
  default_ttl: :timer.hours(24),
  max_retries: 3
)

# Add failed signal
DeadLetterQueue.enqueue(signal, :handler_not_found,
  ttl: :timer.hours(6),
  metadata: %{attempt: 1}
)

# Retry a signal
{:ok, signal} = DeadLetterQueue.retry("sig_123")

# List dead letters
dead_letters = DeadLetterQueue.list(
  limit: 50,
  reason: :timeout,
  sort_by: :last_failure
)

# Get statistics
stats = DeadLetterQueue.stats()
# => %{
#   current_count: 15,
#   total_enqueued: 100,
#   total_retried: 75,
#   total_expired: 10
# }

# Manual cleanup
{:ok, expired_count} = DeadLetterQueue.cleanup()
```

## Integration Examples

### Creating and Emitting Categorized Signals

```elixir
# Using EmitSignalAction with proper category
defmodule MyAction do
  use Jido.Action
  
  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  alias RubberDuck.Jido.Signals.SignalCategory
  
  def run(params, context) do
    # Perform action logic...
    
    # Emit categorized event signal
    EmitSignalAction.run(%{
      signal_type: "process.completed",
      data: %{
        process_id: params.id,
        duration: 1000,
        status: "success"
      },
      source: "action:#{__MODULE__}"
    }, context)
  end
end
```

### Implementing a Signal Handler

```elixir
defmodule MySignalHandler do
  use GenServer
  
  alias RubberDuck.Jido.Signals.{SignalRouter, SignalValidator}
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    # Register routes for this handler
    SignalRouter.register_route("mydomain.*", self())
    {:ok, %{}}
  end
  
  def handle_call({:handle_signal, signal}, _from, state) do
    # Validate signal
    case SignalValidator.validate(signal) do
      {:ok, validated} ->
        # Process based on category
        result = case validated.category do
          :request -> handle_request(validated)
          :event -> handle_event(validated)
          :command -> handle_command(validated)
          _ -> {:error, :unsupported_category}
        end
        {:reply, result, state}
        
      {:error, errors} ->
        {:reply, {:error, errors}, state}
    end
  end
  
  defp handle_request(signal), do: {:ok, :processed}
  defp handle_event(signal), do: {:ok, :recorded}
  defp handle_command(signal), do: {:ok, :executed}
end
```

### Monitoring Signal Flow

```elixir
defmodule SignalMonitor do
  def get_system_metrics do
    %{
      routing: SignalRouter.get_metrics(),
      priority_queues: SignalPriority.stats(),
      dead_letters: DeadLetterQueue.stats()
    }
  end
  
  def health_check do
    metrics = get_system_metrics()
    
    cond do
      metrics.dead_letters.current_count > 100 ->
        {:unhealthy, "Too many dead letters"}
        
      metrics.routing.no_route_count > metrics.routing.routed_count ->
        {:unhealthy, "Most signals have no routes"}
        
      true ->
        {:healthy, metrics}
    end
  end
end
```

## Best Practices

1. **Use Hierarchical Naming**: Always use `domain.action` format for signal types
2. **Include Timestamps**: Let the system auto-generate timestamps for consistency
3. **Validate Early**: Validate signals at entry points to catch issues early
4. **Handle Categories**: Design handlers to work with specific signal categories
5. **Monitor Dead Letters**: Regularly check and retry dead letter signals
6. **Set Appropriate Priorities**: Use priority levels that match business importance
7. **Configure Routing**: Choose routing strategies that match your load patterns
8. **Test Signal Paths**: Ensure all signal types have registered handlers

## Configuration

The signal taxonomy system can be configured through application config:

```elixir
config :rubber_duck, :signal_taxonomy,
  router: [
    routing_strategy: :round_robin,
    max_handlers_per_pattern: 10
  ],
  priority: [
    max_queue_size: 10_000,
    ratios: %{
      critical: 1.0,
      high: 0.7,
      normal: 0.4,
      low: 0.1
    }
  ],
  dead_letter: [
    default_ttl: :timer.hours(24),
    max_retries: 3,
    cleanup_interval: :timer.minutes(5)
  ]
```

## Telemetry Events

The signal taxonomy system emits telemetry events for monitoring:

- `[:rubber_duck, :signal, :routed]` - Signal successfully routed
- `[:rubber_duck, :signal, :no_route]` - No route found for signal
- `[:rubber_duck, :signal, :validated]` - Signal validation completed
- `[:rubber_duck, :signal, :dead_letter]` - Signal sent to DLQ
- `[:rubber_duck, :signal, :retried]` - Dead letter signal retried

Attach to these events for custom monitoring and alerting.