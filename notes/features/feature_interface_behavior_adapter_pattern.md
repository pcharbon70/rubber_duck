# Feature: Interface Behavior and Adapter Pattern

## Overview
Implement the adapter pattern to decouple business logic from interface-specific implementations. This creates a unified interface gateway that can handle requests from CLI, web, and IDE interfaces while maintaining the same core business logic.

## Goals
1. Define a common behavior contract for all interface adapters
2. Create a central gateway for request routing
3. Implement base adapter functionality shared across interfaces
4. Enable capability discovery and negotiation
5. Standardize error handling across interfaces
6. Create request/response transformation utilities

## Technical Design

### Architecture
```
Client Request → InterfaceGateway → Adapter → Business Logic
                                        ↓
Client Response ← InterfaceGateway ← Adapter ← Business Logic
```

### Core Components

#### 1. InterfaceBehaviour (`lib/rubber_duck/interface/behaviour.ex`)
- Define behaviour callbacks all adapters must implement
- Specify request/response type contracts
- Define capability and error types
- Provide helper functions for common operations

#### 2. InterfaceGateway (`lib/rubber_duck/interface/gateway.ex`)
- GenServer managing adapter registry
- Route requests to appropriate adapters
- Handle adapter lifecycle
- Implement circuit breakers
- Collect cross-interface metrics

#### 3. BaseAdapter (`lib/rubber_duck/interface/adapters/base.ex`)
- Common functionality via `use` macro
- Request ID generation
- Basic validation helpers
- Metrics collection
- Logging utilities

#### 4. Transformer (`lib/rubber_duck/interface/transformer.ex`)
- Normalize requests to internal format
- Denormalize responses to interface format
- Handle type conversions
- Extract and merge metadata

#### 5. ErrorHandler (`lib/rubber_duck/interface/error_handler.ex`)
- Standardized error categories
- Error transformation functions
- Structured error logging
- Error metrics collection

#### 6. Capabilities (`lib/rubber_duck/interface/capabilities.ex`)
- Capability discovery system
- Feature negotiation
- Capability validation
- Metadata management

## Implementation Plan

### Phase 1: Core Contracts
1. Create InterfaceBehaviour with all callbacks
2. Define type specifications
3. Add helper functions

### Phase 2: Base Infrastructure
1. Implement BaseAdapter module
2. Create Transformer utilities
3. Build ErrorHandler system

### Phase 3: Gateway Implementation
1. Create InterfaceGateway GenServer
2. Implement adapter registration
3. Add request routing logic
4. Build circuit breaker functionality

### Phase 4: Capability System
1. Define capability types
2. Implement discovery functions
3. Create negotiation logic
4. Add validation

### Phase 5: Integration
1. Wire components together
2. Add comprehensive tests
3. Create example adapter
4. Document usage patterns

## Testing Strategy

### Unit Tests
- Behaviour compliance for mock adapter
- Transformation accuracy
- Error handling coverage
- Gateway routing logic

### Integration Tests
- Multi-adapter scenarios
- Circuit breaker behavior
- Capability negotiation
- End-to-end request flow

### Property Tests
- Transformation invariants
- Error mapping consistency
- Request/response contracts

## Success Criteria
1. ✓ All adapters implement consistent behaviour
2. ✓ Gateway routes requests correctly
3. ✓ Errors are handled uniformly
4. ✓ Capabilities are discoverable
5. ✓ Transformations preserve data
6. ✓ Circuit breakers protect system
7. ✓ Comprehensive test coverage

## API Examples

### Adapter Implementation
```elixir
defmodule MyAdapter do
  use RubberDuck.Interface.BaseAdapter
  @behaviour RubberDuck.Interface.Behaviour
  
  @impl true
  def init(opts) do
    {:ok, %{config: opts}}
  end
  
  @impl true
  def handle_request(request, context, state) do
    # Process request
    {:ok, response, state}
  end
end
```

### Gateway Usage
```elixir
# Register adapter
InterfaceGateway.register_adapter(:cli, MyAdapter, [])

# Route request
{:ok, response} = InterfaceGateway.route_request(request, :cli)
```

## Configuration
```elixir
config :rubber_duck, RubberDuck.Interface.Gateway,
  circuit_breaker: [
    threshold: 5,
    timeout: 30_000
  ],
  metrics: [
    window: :timer.minutes(5)
  ]
```

## Dependencies
- No new external dependencies required
- Uses existing OTP patterns
- Integrates with current event system

## Completion Checklist
- [ ] InterfaceBehaviour defined
- [ ] InterfaceGateway implemented
- [ ] BaseAdapter created
- [ ] Transformer utilities built
- [ ] ErrorHandler system complete
- [ ] Capabilities module done
- [ ] Unit tests passing
- [ ] Integration tests passing
- [ ] Documentation complete
- [ ] Example adapter created