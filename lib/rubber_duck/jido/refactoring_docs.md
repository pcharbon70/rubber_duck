# Jido Framework Refactoring Documentation

## Overview

This document describes the complete refactoring of RubberDuck's Jido integration to align with the official Jido framework patterns. The previous implementation incorrectly used GenServer-based agents, while Jido agents are actually data structures managed by a runtime system.

## Key Changes

### 1. Agent Architecture

**Before (Incorrect):**
- Agents were GenServer processes
- State was stored in process state
- Direct message passing between agents
- Process-based lifecycle

**After (Correct):**
- Agents are data structures stored in ETS
- State is part of the agent data structure
- Communication through actions and signals
- Runtime-managed lifecycle

### 2. Core Components

#### AgentRegistry (`lib/rubber_duck/jido/agent_registry.ex`)
- ETS-based storage for agent data structures
- Provides fast concurrent access
- Manages agent versioning and metadata
- No process state for agents

#### Runtime (`lib/rubber_duck/jido/runtime.ex`)
- Executes actions on agents
- Manages lifecycle callbacks (before_run, after_run, on_error)
- Handles action validation
- Updates agent state and metadata

#### SignalRouter (`lib/rubber_duck/jido/signal_router.ex`)
- Converts CloudEvents signals to actions
- Manages signal subscriptions
- Routes signals to appropriate agents
- Executes actions asynchronously

### 3. Agent Definition

Agents now use the proper Jido.Agent behavior:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    description: "Example agent",
    schema: [
      counter: [type: :integer, default: 0],
      status: [type: :atom, default: :idle]
    ]
    
  # Optional lifecycle callbacks
  @impl true
  def on_before_run(agent) do
    {:ok, agent}
  end
  
  @impl true
  def on_after_run(agent, result, metadata) do
    {:ok, agent}
  end
end
```

### 4. Action Definition

Actions are discrete units of work:

```elixir
defmodule IncrementAction do
  use Jido.Action,
    name: "increment",
    description: "Increments a counter",
    schema: [
      amount: [type: :integer, default: 1]
    ]
    
  @impl true
  def run(params, context) do
    new_value = context.agent.state.counter + params.amount
    updated_state = Map.put(context.agent.state, :counter, new_value)
    updated_agent = Map.put(context.agent, :state, updated_state)
    
    {:ok, %{value: new_value}, %{agent: updated_agent}}
  end
end
```

### 5. Usage Patterns

```elixir
# Create an agent (data structure, not process)
{:ok, agent} = RubberDuck.Jido.create_agent(MyAgent, %{counter: 0})

# Execute an action
{:ok, result, updated_agent} = RubberDuck.Jido.execute_action(agent, IncrementAction, %{amount: 5})

# Send a signal (converted to action)
:ok = RubberDuck.Jido.send_signal(agent.id, %{
  "type" => "increment",
  "data" => %{"amount" => 3}
})
```

## Migration Guide

### For Existing Agents

1. Remove GenServer behavior and callbacks
2. Use `Jido.Agent` behavior instead
3. Move state initialization to schema
4. Convert handle_* callbacks to actions
5. Update lifecycle callbacks to new signatures

### For Tests

1. Remove process-based expectations
2. Test actions directly
3. Verify state changes through agent data
4. Use proper async handling for signals

## Benefits of New Architecture

1. **Scalability**: Agents as data can be distributed across nodes
2. **Fault Tolerance**: No process crashes, just data updates
3. **Performance**: ETS-based storage is very fast
4. **Flexibility**: Actions can be composed and reused
5. **Observability**: All state changes are explicit
6. **Testing**: Easier to test pure data transformations

## Common Pitfalls to Avoid

1. Don't try to send messages to agents - they're not processes
2. Don't store agent references - always fetch current state
3. Don't modify agent state directly - use actions
4. Don't assume synchronous signal processing
5. Don't forget to update agent in registry after actions

## Future Enhancements

1. Implement proper state validation with NimbleOptions
2. Add persistence layer for agent state
3. Implement action queuing and prioritization
4. Add distributed agent support
5. Implement more sophisticated signal routing patterns