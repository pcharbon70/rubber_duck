# Feature 15.1.3: Signal Router Implementation

## Overview
This feature enhances the existing SignalRouter with strict CloudEvents 1.0 compliance and advanced capabilities for agent communication patterns. This is a breaking change that removes backward compatibility with non-CloudEvents signals.

## Current State
We have a basic SignalRouter implementation that:
- Auto-converts signals to CloudEvents format
- Maps signals to actions
- Executes actions asynchronously
- Supports basic pattern matching and subscriptions

## Breaking Changes
1. **No backward compatibility** - all signals must be valid CloudEvents
2. **No auto-conversion** - invalid signals will be rejected with clear errors
3. **Required fields enforced** - `specversion`, `id`, `source`, `type` must be present
4. **Strict validation** - field types and formats are validated

## Implementation Phases

### Phase 1: Core Signal Router Enhancements (15.1.3.1)
- Strict CloudEvents validation
- Configurable routing table
- Dead letter queue for failed signals
- Enhanced pattern matching

### Phase 2: Signal Subscription System (15.1.3.2)
- Priority-based routing
- Advanced filtering capabilities
- Subscription lifecycle management
- Performance optimizations

### Phase 3: Signal Transformation Pipeline (15.1.3.3)
- Pluggable transformer behaviour
- Built-in transformers (enricher, filter, aggregator)
- Transformation chains
- Error handling

### Phase 4: Signal Persistence Layer (15.1.3.4)
- Ash resource for CloudEvents storage
- Event replay functionality
- Retention policies
- Query interface

### Phase 5: Signal Monitoring (15.1.3.5)
- Comprehensive telemetry
- Performance metrics
- Health checks
- Alerting capabilities

## Technical Architecture

### CloudEvents Compliance
All signals must conform to CloudEvents 1.0 specification:
```elixir
%{
  "specversion" => "1.0",              # Required
  "id" => "unique-id",                 # Required
  "source" => "service/component",      # Required (URI-reference)
  "type" => "com.example.action",      # Required
  "time" => "2025-01-29T10:00:00Z",   # Optional (RFC3339)
  "datacontenttype" => "application/json", # Optional
  "data" => %{...}                     # Optional
}
```

### Module Structure
```
lib/rubber_duck/jido/
├── signal_router.ex
├── signal_router/
│   ├── config.ex
│   ├── dead_letter_queue.ex
│   ├── metrics.ex
│   ├── pipeline.ex
│   ├── subscription.ex
│   └── transformers/
├── cloud_events/
│   └── validator.ex
└── signals/
    └── cloud_event.ex
```

## Benefits
1. **Standards Compliance** - Full CloudEvents 1.0 support
2. **Reliability** - Dead letter queue prevents signal loss
3. **Flexibility** - Configurable routing and transformations
4. **Observability** - Comprehensive monitoring and metrics
5. **Performance** - Optimized for high throughput
6. **Maintainability** - Clear separation of concerns

## Migration Requirements
All existing code that sends signals must be updated to use proper CloudEvents format:

Before:
```elixir
Jido.send_signal(agent, %{"type" => "increment", "data" => %{"amount" => 1}})
```

After:
```elixir
Jido.send_signal(agent, %{
  "specversion" => "1.0",
  "id" => Uniq.UUID.uuid4(),
  "source" => "my-service/component",
  "type" => "increment",
  "data" => %{"amount" => 1}
})
```

## Success Metrics
- 100% CloudEvents validation compliance
- <5ms routing latency at 1000 signals/sec
- Zero signal loss with dead letter queue
- Complete audit trail for all signals
- Real-time monitoring dashboard