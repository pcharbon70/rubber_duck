# Feature: Spark DSL Foundation

## Overview
Implement the Spark DSL infrastructure for the pluggable engine system. This will enable declarative configuration of engines with a clean, extensible API for defining new engines and their configurations.

## Goals
- Set up Spark DSL as the foundation for engine configuration
- Create the `RubberDuck.EngineSystem` module with Spark DSL
- Define DSL structure for engine configuration
- Implement engine entity with required attributes
- Enable modular addition of new engines without modifying core code

## Technical Design

### 1. Dependencies
Add Spark to mix.exs (though it's already included via Ash):
```elixir
{:spark, "~> 2.2"}
```

### 2. Engine System DSL Structure
Create `RubberDuck.EngineSystem` module that uses Spark.Dsl to define:
- Engine sections for grouping related engines
- Engine entities with configuration options
- Extension support for pluggable capabilities

### 3. Engine Entity Attributes
Each engine will have:
- `name` (atom, required) - Unique identifier
- `module` (module reference, required) - Implementation module
- `description` (string, optional) - Engine purpose
- `priority` (integer, default: 50) - Execution order
- `timeout` (timeout, default: 30_000) - Max execution time
- `config` (keyword list) - Engine-specific configuration

### 4. DSL Example Usage
```elixir
defmodule MyProject.Engines do
  use RubberDuck.EngineSystem

  engines do
    engine :code_completion do
      module MyProject.Engines.CodeCompletion
      description "Provides intelligent code completion"
      priority 100
      timeout 5_000
      
      config do
        max_suggestions 10
        min_confidence 0.7
      end
    end

    engine :code_generation do
      module MyProject.Engines.CodeGeneration
      description "Generates code from natural language"
      priority 90
      timeout 30_000
    end
  end
end
```

### 5. Engine Behavior
Define a behavior that all engine modules must implement:
```elixir
defmodule RubberDuck.Engine do
  @callback init(config :: keyword()) :: {:ok, state} | {:error, term}
  @callback execute(input :: map(), state :: term) :: {:ok, result} | {:error, reason}
  @callback capabilities() :: [atom()]
end
```

## Implementation Steps

1. **Add Spark dependency** (if not already available via Ash)
2. **Create base modules:**
   - `RubberDuck.EngineSystem` - Main DSL module
   - `RubberDuck.Engine` - Behavior for engines
   - `RubberDuck.EngineSystem.Engine` - Entity definition
3. **Define DSL structure:**
   - `engines` section for grouping engines
   - `engine` entity with required attributes
   - Support for nested configuration
4. **Add transformers:**
   - Validate engine uniqueness
   - Ensure modules implement Engine behavior
   - Set default values
5. **Create registry functionality:**
   - List all defined engines
   - Look up engines by name
   - Filter engines by capability

## Testing Strategy

1. **DSL compilation tests:**
   - Valid engine definitions compile
   - Invalid definitions raise compile errors
   - Required attributes are enforced

2. **Runtime tests:**
   - Engine registry works correctly
   - Engines can be looked up by name
   - Priority ordering is respected

3. **Example engine tests:**
   - Create mock engines for testing
   - Verify behavior implementation
   - Test configuration passing

## Migration Path
Since this is a new feature, no migration is needed. Future engines will be built using this DSL foundation.

## Documentation
- Document DSL usage in module docs
- Provide examples of engine definitions
- Document the Engine behavior
- Create guide for adding new engines

## Success Criteria
- [ ] Spark DSL foundation is implemented
- [ ] Engine entity supports all required attributes
- [ ] DSL compiles and validates correctly
- [ ] Registry functions work as expected
- [ ] Unit tests pass
- [ ] Documentation is complete