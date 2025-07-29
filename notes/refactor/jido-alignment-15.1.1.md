# Refactoring Plan: Align 15.1.1 with Jido Patterns

## Current Issues

The current 15.1.1 implementation doesn't follow Jido patterns correctly:

1. **BaseAgent as GenServer**: The BaseAgent is implemented as a GenServer behavior instead of using `Jido.Agent`
2. **No Jido Actions**: Missing the core Jido concept of Actions
3. **Custom Signal Handling**: Implements custom signal handling instead of using Jido's built-in patterns
4. **Missing Jido Runtime**: Not using Jido.Runtime for agent execution
5. **Workflow Engine Placeholder**: Not integrated with Jido's workflow capabilities

## Proper Jido Architecture

According to Jido documentation:
- Agents are defined using `use Jido.Agent` with schema and actions
- Actions are discrete work units defined with `use Jido.Action`
- Agents are data structures, not processes
- Jido.Runtime handles agent execution
- Signals are handled through action queuing

## Refactoring Steps

### 1. Remove GenServer-based BaseAgent
The current BaseAgent should be deprecated in favor of proper Jido patterns.

### 2. Create Proper Jido Integration Module
```elixir
defmodule RubberDuck.Jido.Core do
  @moduledoc """
  Core Jido integration providing RubberDuck-specific utilities.
  """
  
  # Utilities for working with Jido agents
  # Signal emission helpers
  # Telemetry integration
end
```

### 3. Define Base Actions
Create common actions that agents can use:
```elixir
defmodule RubberDuck.Jido.Actions.HandleSignal do
  use Jido.Action,
    name: "handle_signal",
    description: "Processes incoming signals"
end
```

### 4. Update Signal Dispatcher
Integrate SignalDispatcher to work with Jido.Runtime instead of sending GenServer messages.

### 5. Create Agent Runner
Since Jido agents aren't processes, create a runner that:
- Manages agent lifecycle
- Routes signals to actions
- Handles state persistence

## Migration Path

### Phase 1: Add Proper Jido Components (Non-breaking)
1. Keep existing GenServer-based system
2. Add new Jido-compliant modules in parallel
3. Create adapters between old and new systems

### Phase 2: Gradual Migration
1. Convert agents one by one to new pattern
2. Maintain compatibility layer
3. Update tests incrementally

### Phase 3: Remove Legacy Code
1. Remove GenServer-based BaseAgent
2. Remove custom supervisors
3. Full Jido compliance

## Example of Proper Implementation

```elixir
# Proper Jido Agent
defmodule RubberDuck.Jido.Agents.ExampleAgent do
  use Jido.Agent,
    name: "example_agent",
    description: "Example of proper Jido agent",
    schema: [
      status: [type: :atom, default: :idle],
      counter: [type: :integer, default: 0]
    ],
    actions: [
      RubberDuck.Jido.Actions.Increment,
      RubberDuck.Jido.Actions.HandleSignal
    ]
end

# Proper Jido Action
defmodule RubberDuck.Jido.Actions.Increment do
  use Jido.Action,
    name: "increment",
    description: "Increments counter",
    schema: [
      amount: [type: :integer, default: 1]
    ]
    
  @impl true
  def run(params, context) do
    new_count = context.agent.state.counter + params.amount
    updated_state = Map.put(context.agent.state, :counter, new_count)
    updated_agent = Map.put(context.agent, :state, updated_state)
    
    {:ok, %{new_count: new_count}, %{agent: updated_agent}}
  end
end
```

## Benefits of Proper Implementation

1. **True Jido Compliance**: Follows documented patterns
2. **Better Scalability**: Agents as data, not processes
3. **Action Reusability**: Actions can be shared across agents
4. **Proper State Management**: Built-in validation and persistence
5. **Workflow Integration**: Can use Jido's workflow capabilities

## Recommendation

Since 15.1.1 is already implemented and working, I recommend:
1. Keep current implementation as-is for now
2. Create new modules following proper Jido patterns
3. Provide migration path in future phases
4. Document the architectural differences clearly

This allows the system to work while providing a path to proper Jido integration.