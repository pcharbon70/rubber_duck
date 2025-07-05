# Base Engine Behavior Documentation

## Overview

The Base Engine Behavior system provides GenServer-based management for engines in the RubberDuck system. It builds upon the Spark DSL foundation to create supervised, fault-tolerant engine instances with health monitoring and capability-based discovery.

## Architecture

### Core Components

1. **Engine.Server** - GenServer wrapper for engine instances
   - Handles request execution with timeouts
   - Tracks statistics (request count, errors)
   - Emits telemetry events
   - Performs periodic health checks

2. **Engine.Supervisor** - DynamicSupervisor for engine processes
   - Manages engine lifecycle
   - Provides fault tolerance with restart strategies
   - Allows runtime engine addition/removal

3. **Engine.CapabilityRegistry** - Registry for engine discovery
   - Indexes engines by capabilities
   - Maintains engine configurations
   - Enables capability-based routing

4. **Engine.Manager** - High-level API
   - Loads engines from DSL modules
   - Routes requests to engines
   - Provides unified interface for engine operations

## Usage

### Loading Engines

```elixir
# Load engines from a DSL module
RubberDuck.Engine.Manager.load_engines(MyApp.Engines)
```

### Executing Requests

```elixir
# Execute on specific engine
{:ok, result} = RubberDuck.Engine.Manager.execute(:my_engine, %{
  input: "data"
})

# Execute on any engine with capability
{:ok, result} = RubberDuck.Engine.Manager.execute_by_capability(
  :text_processing,
  %{text: "Hello"},
  strategy: :round_robin
)
```

### Managing Engine Lifecycle

```elixir
# Stop an engine
:ok = RubberDuck.Engine.Manager.stop_engine(:my_engine)

# Start individual engine
{:ok, pid} = RubberDuck.Engine.Manager.start_engine(engine_config)

# Check engine status
status = RubberDuck.Engine.Manager.status(:my_engine)
# Returns: %{
#   engine: :my_engine,
#   status: :ready,
#   request_count: 42,
#   error_count: 1,
#   uptime_seconds: 3600
# }

# Health check
:healthy = RubberDuck.Engine.Manager.health_status(:my_engine)
```

### Discovery

```elixir
# List all capabilities
capabilities = RubberDuck.Engine.Manager.list_capabilities()

# Find engines by capability
engines = RubberDuck.Engine.Manager.find_engines_by_capability(:code_completion)

# Get aggregate statistics
stats = RubberDuck.Engine.Manager.stats()
```

## Features

### Fault Tolerance
- Engines run under supervision
- Automatic restart on crashes (configurable)
- Circuit breaker pattern support
- Isolated crash domains

### Performance
- Concurrent request handling
- Request timeouts
- Telemetry integration
- Health monitoring

### Flexibility
- Multiple selection strategies (first, random, round-robin)
- Dynamic engine loading/unloading
- Capability-based routing
- Custom engine configurations

## Configuration

Engines support various configuration options:

```elixir
engine :my_engine do
  module MyEngine
  timeout 10_000        # Request timeout in ms
  priority 100          # Higher priority engines preferred
  config [              # Engine-specific config
    option1: "value",
    option2: 42
  ]
end
```

## Telemetry Events

The system emits telemetry events for monitoring:

- `[:rubber_duck, :engine, :execute]` - Request execution
  - Measurements: `duration`
  - Metadata: `engine`, `module`, `status`, `error` (if applicable)

- `[:rubber_duck, :engine, :health_check]` - Health check performed
  - Metadata: `engine`, `status`

- `[:rubber_duck, :engine, :terminate]` - Engine terminated
  - Metadata: `engine`, `reason`

## Error Handling

The system provides comprehensive error handling:

- Request timeouts return `{:error, :timeout}`
- Engine crashes are isolated and return `{:error, {:crash, reason}}`
- Missing engines return `{:error, :engine_not_found}`
- No engines with capability return `{:error, :no_engine_with_capability}`

## Best Practices

1. **Configure appropriate timeouts** - Balance between responsiveness and completion
2. **Use health checks** - Monitor engine health proactively
3. **Handle errors gracefully** - Always handle error responses
4. **Monitor telemetry** - Track performance and errors
5. **Test fault scenarios** - Ensure system handles failures well

## Engine Pooling

The engine system supports pooling for improved concurrency:

### Pool Configuration

```elixir
engine :my_engine do
  module MyEngine
  pool_size 5          # 5 worker instances
  max_overflow 10      # Up to 10 extra workers under load
  checkout_timeout 5000 # Wait up to 5s for a worker
end
```

### Pool Behavior

- When `pool_size = 1` (default), a single GenServer instance is used
- When `pool_size > 1`, a poolboy pool manages multiple workers
- Workers are checked out for each request and returned after
- Overflow workers are created when the main pool is exhausted
- Requests wait up to `checkout_timeout` for an available worker

### Pool Monitoring

```elixir
# Get pool status
status = Manager.status(:pooled_engine)
# Returns: %{
#   pool_size: 5,
#   available_workers: 3,
#   checked_out: 2,
#   overflow: 0,
#   total_workers: 5
# }

# Pool telemetry events
[:rubber_duck, :engine, :pool]
# Measurements: available_workers, checked_out, overflow, total_workers
# Metadata: engine, pool_size, max_overflow
```

## Limitations

- Restarting an engine requires re-registering its configuration
- Health checks are simple by default (can be extended)
- Selection strategies are basic (can be enhanced)

## Future Enhancements

- Persistent engine configurations
- Advanced health check strategies
- Load balancing improvements
- Engine pooling for high throughput
- Distributed engine execution