# Engine System Documentation

## Overview

The RubberDuck Engine System provides a pluggable architecture for extending the coding assistant with new capabilities. Built on top of Spark DSL, it allows developers to declaratively configure engines that handle specific tasks like code completion, generation, and analysis.

## Core Components

### 1. Engine Behavior (`RubberDuck.Engine`)

All engines must implement this behavior with three callbacks:

- `init/1` - Initialize the engine with configuration
- `execute/2` - Process input and return results
- `capabilities/0` - Declare what the engine can do

### 2. Engine System DSL (`RubberDuck.EngineSystem`)

Uses Spark DSL to provide a declarative configuration syntax:

```elixir
defmodule MyApp.Engines do
  use RubberDuck.EngineSystem
  
  engines do
    engine :my_engine do
      module MyApp.Engines.MyEngine
      description "Does something useful"
      priority 100
      timeout 5_000
      config [
        option1: "value1"
      ]
    end
  end
end
```

### 3. Engine Entity Attributes

Each engine has the following configurable attributes:

- `name` (required) - Unique atom identifier
- `module` (required) - Module implementing the Engine behavior
- `description` - Human-readable description
- `priority` - Execution priority (0-1000, higher runs first)
- `timeout` - Maximum execution time in milliseconds
- `config` - Engine-specific configuration
- `pool_size` - Number of worker instances (default: 1)
- `max_overflow` - Extra workers allowed under load (default: 0)
- `checkout_timeout` - Max time to wait for worker (default: 5000ms)

## Usage Examples

### Defining Engines

```elixir
defmodule MyApp.Engines do
  use RubberDuck.EngineSystem
  
  engines do
    engine :code_completion do
      module MyApp.Engines.CodeCompletion
      description "Provides intelligent code completion"
      priority 100
      timeout 5_000
      
      config [
        max_suggestions: 10,
        min_confidence: 0.7
      ]
    end
    
    engine :syntax_check do
      module MyApp.Engines.SyntaxCheck
      description "Checks code syntax"
      priority 90
      pool_size 5        # Run 5 concurrent workers
      max_overflow 10    # Allow up to 10 extra workers
    end
  end
end
```

### Implementing an Engine

```elixir
defmodule MyApp.Engines.CodeCompletion do
  @behaviour RubberDuck.Engine
  
  @impl true
  def init(config) do
    # Initialize with config
    {:ok, Map.new(config)}
  end
  
  @impl true
  def execute(%{code: code, cursor: position}, state) do
    # Process input and return suggestions
    suggestions = generate_suggestions(code, position, state)
    {:ok, suggestions}
  end
  
  @impl true
  def capabilities do
    [:code_completion, :intelligent_suggestions]
  end
end
```

### Querying Engines

```elixir
# Get all engines
engines = RubberDuck.EngineSystem.engines(MyApp.Engines)

# Get specific engine
engine = RubberDuck.EngineSystem.get_engine(MyApp.Engines, :code_completion)

# Find engines by capability
completion_engines = RubberDuck.EngineSystem.engines_by_capability(
  MyApp.Engines, 
  :code_completion
)

# Get engines sorted by priority
priority_engines = RubberDuck.EngineSystem.engines_by_priority(MyApp.Engines)
```

## Validation

The system performs compile-time validation to ensure:

- Engine names are unique within a module
- Priority values are between 0 and 1000
- Required attributes are present

## Best Practices

1. **Keep engines focused** - Each engine should handle one specific capability
2. **Use meaningful names** - Engine names should clearly indicate their purpose
3. **Set appropriate timeouts** - Balance between functionality and responsiveness
4. **Document capabilities** - Clearly list what each engine can do
5. **Handle errors gracefully** - Return `{:error, reason}` for failures

## Future Enhancements

The engine system is designed to be extended with:

- Dynamic engine loading
- Engine composition and pipelines
- Distributed engine execution
- Engine versioning and compatibility
- Performance metrics and monitoring