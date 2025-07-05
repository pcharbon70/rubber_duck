# Feature: Base Engine Behavior

## Overview
Implement the base engine behavior infrastructure that provides GenServer-based engine management, supervision, lifecycle control, and health monitoring. This builds upon the Spark DSL foundation to create running engine instances.

## Goals
- Create a base GenServer template for all engines
- Implement engine supervision tree for fault tolerance
- Add engine lifecycle management (start, stop, restart)
- Create engine communication protocol
- Implement health checks and monitoring
- Build engine registry with capability-based discovery
- Enable multi-engine coordination

## Technical Design

### 1. Base Engine GenServer
Create `RubberDuck.Engine.Server` that wraps engines with GenServer functionality:

```elixir
defmodule RubberDuck.Engine.Server do
  use GenServer
  
  # Starts an engine with its configuration
  def start_link(engine_config, opts \\ [])
  
  # Standard GenServer callbacks
  def init(args)
  def handle_call({:execute, input}, from, state)
  def handle_info(:health_check, state)
  def terminate(reason, state)
end
```

### 2. Engine Supervision Tree
Create `RubberDuck.Engine.Supervisor`:
- DynamicSupervisor for managing engine instances
- Restart strategies based on engine configuration
- Child spec generation from engine configs

### 3. Engine Registry
Create `RubberDuck.Engine.Registry`:
- Process registry for named engine lookup
- Capability-based discovery
- Load balancing for multiple instances
- Pub/sub for engine events

### 4. Engine Manager
Create `RubberDuck.Engine.Manager`:
- High-level API for engine operations
- Start/stop/restart engines
- Query engine status
- Execute requests with routing

### 5. Health Monitoring
Implement health check system:
- Periodic health checks
- Circuit breaker integration
- Telemetry events
- Automatic restart on failure

### 6. Communication Protocol
Define structured communication:
- Request/response format
- Async execution support
- Timeout handling
- Error propagation

## Implementation Steps

1. **Create Engine.Server module**
   - GenServer wrapper for engines
   - State management
   - Message handling

2. **Implement supervision tree**
   - DynamicSupervisor setup
   - Child specs from engine configs
   - Restart strategies

3. **Build engine registry**
   - Named process registration
   - Capability indexing
   - Discovery functions

4. **Create engine manager**
   - High-level API
   - Engine lifecycle control
   - Request routing

5. **Add health monitoring**
   - Periodic health checks
   - Telemetry integration
   - Auto-recovery

6. **Define communication protocol**
   - Message formats
   - Error handling
   - Timeouts

7. **Integration with existing system**
   - Wire up with EngineSystem DSL
   - Update example engines
   - Migration guide

## Testing Strategy

1. **Unit tests**
   - Engine server behavior
   - Registry operations
   - Manager functions

2. **Integration tests**
   - Full engine lifecycle
   - Multi-engine scenarios
   - Failure recovery

3. **Property tests**
   - Concurrent operations
   - Registry consistency
   - Load distribution

## Example Usage

```elixir
# Start engine system
{:ok, _} = RubberDuck.Engine.Supervisor.start_link()

# Load engines from DSL module
RubberDuck.Engine.Manager.load_engines(MyApp.Engines)

# Execute on specific engine
{:ok, result} = RubberDuck.Engine.Manager.execute(:code_completion, %{
  code: "def hello",
  cursor: 9
})

# Execute on any engine with capability
{:ok, result} = RubberDuck.Engine.Manager.execute_by_capability(
  :text_processing,
  %{text: "Hello world"}
)

# Check engine health
:healthy = RubberDuck.Engine.Manager.health_status(:code_completion)

# Stop engine
:ok = RubberDuck.Engine.Manager.stop_engine(:code_completion)
```

## Success Criteria
- [ ] Engines run as supervised GenServers
- [ ] Automatic restart on crashes
- [ ] Health monitoring works
- [ ] Registry enables fast lookups
- [ ] Manager provides clean API
- [ ] Tests demonstrate reliability
- [ ] Documentation is complete