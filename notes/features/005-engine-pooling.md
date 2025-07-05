# Feature: Engine Pooling Support

## Summary
Add pooling support to the engine system to allow multiple instances of each engine type for improved throughput and concurrency.

## Requirements
- [ ] Support configurable pool size per engine
- [ ] Maintain backward compatibility (single instance by default)
- [ ] Provide pool metrics and monitoring
- [ ] Handle pool overflow gracefully
- [ ] Support different checkout strategies
- [ ] Integrate with existing health checks

## Research Summary
### Pooling Libraries
- **poolboy**: Mature Erlang worker pool library, used by Ecto and Phoenix
- **nimble_pool**: Lightweight but designed for non-process resources
- Decision: Use poolboy for its maturity and process pool support

### Technical Approach
1. Add pool configuration to engine DSL:
   ```elixir
   engine :my_engine do
     module MyEngine
     pool_size 5        # Number of workers
     max_overflow 10    # Additional workers under load
   end
   ```

2. Replace single GenServer with poolboy pool
3. Update Manager to checkout/checkin workers
4. Add pool-aware health checks and metrics

## Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking changes | High | Default pool_size to 1 for backward compatibility |
| Resource exhaustion | Medium | Configure max_overflow limits |
| Complexity increase | Medium | Clear documentation and examples |

## Implementation Checklist
- [ ] Add poolboy dependency to mix.exs
- [ ] Update Engine entity with pool configuration
- [ ] Create Engine.Pool module wrapping poolboy
- [ ] Modify Engine.Supervisor to start pools
- [ ] Update Engine.Manager checkout/checkin logic
- [ ] Add pool metrics to telemetry
- [ ] Update health checks for pools
- [ ] Write comprehensive tests
- [ ] Update documentation

## Design Details

### Pool Configuration
```elixir
defmodule Engine do
  defstruct [
    # existing fields...
    :pool_size,      # default: 1
    :max_overflow,   # default: 0
    :checkout_timeout # default: 5000
  ]
end
```

### Pool Worker Module
Create `Engine.Pool.Worker` that wraps `Engine.Server` for poolboy compatibility.

### Manager Changes
```elixir
# Instead of direct GenServer call:
def execute(engine_name, input, timeout) do
  :poolboy.transaction(
    pool_name(engine_name),
    fn worker ->
      Engine.Server.execute(worker, input, timeout)
    end,
    checkout_timeout
  )
end
```