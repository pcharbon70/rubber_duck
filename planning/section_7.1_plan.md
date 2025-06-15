# Section 7.1: Interface Behavior and Adapter Pattern - Implementation Plan

## Overview
This section implements the adapter pattern to decouple business logic from interface-specific implementations. The goal is to create a unified interface gateway that can handle requests from CLI, web, and IDE interfaces while maintaining the same core business logic.

## Architecture Design

### Core Components

1. **InterfaceBehaviour** - Defines the contract all adapters must implement
2. **InterfaceGateway** - Central router that delegates to appropriate adapters
3. **BaseAdapter** - Common functionality shared by all adapters
4. **Request/Response Types** - Unified data structures for cross-interface communication
5. **Error Handling** - Standardized error types and transformation
6. **Capability Discovery** - Interface feature negotiation system

### Component Relationships

```
Client Request → InterfaceGateway → Adapter → Business Logic
                                        ↓
Client Response ← InterfaceGateway ← Adapter ← Business Logic
```

## Detailed Implementation Plan

### 1. InterfaceBehaviour Module (`lib/rubber_duck/interface/behaviour.ex`)
**Purpose**: Define the contract that all interface adapters must implement

**Callbacks to define**:
- `init(opts)` - Initialize adapter with configuration
- `handle_request(request, context)` - Process incoming requests
- `format_response(response, request)` - Format responses for the interface
- `handle_error(error, request)` - Transform errors to interface format
- `capabilities()` - Return supported features/operations
- `validate_request(request)` - Validate interface-specific request format
- `shutdown(reason, state)` - Cleanup on adapter shutdown

**Types to define**:
- `@type request :: map()` - Generic request structure
- `@type response :: map()` - Generic response structure  
- `@type context :: map()` - Request context (auth, metadata, etc.)
- `@type capability :: atom()` - Feature capability atoms
- `@type error :: {:error, atom(), String.t(), map()}`

### 2. InterfaceGateway Module (`lib/rubber_duck/interface/gateway.ex`)
**Purpose**: Central GenServer that routes requests to appropriate adapters

**Responsibilities**:
- Maintain registry of active adapters
- Route requests based on interface type
- Handle adapter lifecycle (start/stop/restart)
- Collect metrics across all interfaces
- Implement circuit breakers for failing adapters
- Coordinate cross-interface operations

**Public API**:
- `start_link/1` - Start the gateway
- `register_adapter/2` - Register new adapter
- `unregister_adapter/1` - Remove adapter
- `route_request/2` - Route request to appropriate adapter
- `list_adapters/0` - List registered adapters
- `adapter_capabilities/1` - Get capabilities for specific adapter
- `get_metrics/0` - Get gateway metrics

**State Structure**:
```elixir
%{
  adapters: %{interface_type => {adapter_module, adapter_pid}},
  metrics: %{interface_type => metrics},
  circuit_breakers: %{interface_type => circuit_state},
  config: gateway_config
}
```

### 3. BaseAdapter Module (`lib/rubber_duck/interface/adapters/base.ex`)
**Purpose**: Common functionality for all adapters

**Features**:
- Request ID generation and tracking
- Basic request validation
- Common error handling patterns
- Metrics collection helpers
- Request/response logging
- Context enrichment
- Rate limiting helpers

**Macros to provide**:
- `use RubberDuck.Interface.BaseAdapter` - Inject common functionality
- Default implementations for behaviour callbacks
- Helper functions for common operations

### 4. Request/Response Transformation (`lib/rubber_duck/interface/transformer.ex`)
**Purpose**: Transform between interface-specific and internal formats

**Functions**:
- `normalize_request/2` - Convert interface request to internal format
- `denormalize_response/2` - Convert internal response to interface format
- `extract_context/1` - Extract context from raw request
- `merge_metadata/2` - Merge request/response metadata
- `sanitize_data/1` - Remove sensitive information

**Transformation Rules**:
- Standardize field names (camelCase ↔ snake_case)
- Type conversions (strings ↔ atoms)
- Nested structure flattening/expansion
- Default value injection
- Validation during transformation

### 5. Error Handling (`lib/rubber_duck/interface/error_handler.ex`)
**Purpose**: Standardized error handling across interfaces

**Error Categories**:
- `:validation_error` - Invalid request format
- `:authentication_error` - Auth failures
- `:authorization_error` - Permission denied
- `:not_found` - Resource not found
- `:timeout` - Operation timeout
- `:internal_error` - System errors
- `:rate_limit` - Rate limit exceeded

**Functions**:
- `wrap_error/3` - Create standardized error
- `transform_error/2` - Convert internal errors to interface format
- `error_to_response/2` - Generate error response
- `log_error/2` - Structured error logging
- `error_metrics/1` - Update error metrics

### 6. Capability Discovery (`lib/rubber_duck/interface/capabilities.ex`)
**Purpose**: Dynamic feature discovery and negotiation

**Capability Types**:
- Core operations (chat, complete, analyze)
- Streaming support
- File handling
- Authentication methods
- Response formats
- Language support
- Model selection

**Functions**:
- `discover_capabilities/1` - Get adapter capabilities
- `negotiate_features/2` - Match client/server capabilities
- `validate_capability/2` - Check if operation is supported
- `capability_metadata/1` - Get detailed capability info
- `merge_capabilities/2` - Combine multiple capability sets

## Implementation Order

1. **First**: InterfaceBehaviour and types
2. **Second**: BaseAdapter with common functionality
3. **Third**: Error handling and transformation utilities
4. **Fourth**: Capability discovery system
5. **Fifth**: InterfaceGateway with routing
6. **Sixth**: Integration tests and documentation

## Testing Strategy

### Unit Tests
- Behaviour compliance tests for adapters
- Transformation accuracy tests
- Error handling coverage
- Capability negotiation tests

### Integration Tests
- Gateway routing tests
- Multi-adapter coordination
- Circuit breaker behavior
- Metrics collection accuracy

### Property Tests
- Request/response transformation invariants
- Error category mappings
- Capability set operations

## Success Criteria

1. All adapters implement InterfaceBehaviour
2. Gateway successfully routes to correct adapters
3. Error handling is consistent across interfaces
4. Capabilities can be discovered dynamically
5. Transformations preserve data integrity
6. Circuit breakers protect against adapter failures
7. Metrics provide visibility into all interfaces

## Configuration Example

```elixir
config :rubber_duck, RubberDuck.Interface.Gateway,
  adapters: [
    cli: {RubberDuck.Interface.Adapters.CLI, []},
    web: {RubberDuck.Interface.Adapters.Web, []},
    lsp: {RubberDuck.Interface.Adapters.LSP, []}
  ],
  circuit_breaker: [
    threshold: 5,
    timeout: 30_000
  ],
  metrics: [
    window: :timer.minutes(5),
    aggregation: [:count, :latency, :errors]
  ]
```

## Next Steps

After implementing this foundation, Section 7.2 will implement the CLI adapter using this pattern, followed by web and LSP adapters in subsequent sections.