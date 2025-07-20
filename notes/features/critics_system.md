# Critics System for Plan Validation

## Overview
Implemented a comprehensive critics system based on the LLM-Modulo framework for validating plans and tasks. The system provides external validation through hard critics (correctness) and soft critics (quality), ensuring that AI-generated plans meet both functional and qualitative requirements.

## Implementation Date
January 20, 2025

## Architecture

### 1. CriticBehaviour (`lib/rubber_duck/planning/critics/critic_behaviour.ex`)
- Defines the behavior contract for all critics
- Core callbacks: `name/0`, `type/0`, `priority/0`, `validate/2`
- Optional callbacks: `configure/1`, `can_validate?/1`
- Helper functions for creating validation results

### 2. Hard Critics (`lib/rubber_duck/planning/critics/hard_critic.ex`)
Enforce correctness constraints with five sub-critics:

#### SyntaxValidator
- Validates code syntax using AST parsing
- Extracts code from various formats (direct code, snippets, markdown)
- Aggregates syntax errors across multiple code blocks

#### DependencyValidator
- Validates task dependencies exist in the plan
- Detects circular dependencies using DFS
- Ensures dependency consistency

#### ConstraintChecker
- Validates against defined constraints (duration, resources, dependencies)
- Supports multiple constraint types
- Differentiates between violations and warnings

#### FeasibilityAnalyzer
- Analyzes complexity feasibility
- Checks timeline constraints against deadlines
- Validates scope reasonableness

#### ResourceValidator
- Validates resource requirements against availability
- Supports numeric and boolean resource checks
- Handles both map and list resource specifications

### 3. Soft Critics (`lib/rubber_duck/planning/critics/soft_critic.ex`)
Assess quality aspects with four sub-critics:

#### StyleChecker
- Validates naming conventions
- Checks description quality and completeness
- Assesses documentation completeness
- Evaluates task modularity

#### BestPracticeValidator
- Checks single responsibility principle
- Validates clear interface definitions
- Ensures error handling considerations
- Verifies testing strategy presence
- Promotes incremental approaches

#### PerformanceAnalyzer
- Analyzes computational complexity patterns
- Checks data handling approaches
- Evaluates concurrency considerations
- Assesses resource usage

#### SecurityChecker
- Validates authentication requirements
- Detects sensitive data handling
- Checks input validation presence
- Identifies insecure patterns

### 4. Orchestrator (`lib/rubber_duck/planning/critics/orchestrator.ex`)
Manages critic execution and result aggregation:

- **Parallel Execution**: Runs critics concurrently for performance
- **Priority-based Ordering**: Executes critics by priority
- **Result Aggregation**: Combines results into structured summary
- **Caching**: In-memory caching with TTL
- **Configuration**: Per-critic configuration support
- **Plugin Support**: Add custom critics dynamically
- **Error Handling**: Graceful handling of critic failures

## Integration

### TaskDecomposer Integration
- Critics run automatically when `validation_enabled` is true
- Basic validations run first, followed by critic validation
- Only hard critic failures block decomposition
- Soft critic warnings are informational

### Validation Resource Integration
- Results can be persisted to database via `persist_results/2`
- Supports batch creation of validation records
- Links validations to plans or tasks

## Key Features

1. **Behavior-based Architecture**: All critics implement CriticBehaviour
2. **Parallel Execution**: Critics run concurrently for better performance
3. **Priority System**: Critics execute in priority order (lower = higher priority)
4. **Flexible Validation**: Supports sync and async validation
5. **Rich Results**: Detailed messages, suggestions, and metadata
6. **Caching**: Reduces redundant validations
7. **Extensibility**: Easy to add custom critics
8. **Graceful Degradation**: Critic failures don't crash validation

## Usage Examples

### Basic Usage
```elixir
# Create orchestrator
orchestrator = Orchestrator.new()

# Validate a plan or task
{:ok, results} = Orchestrator.validate(orchestrator, target)

# Aggregate results
summary = Orchestrator.aggregate_results(results)
```

### Custom Configuration
```elixir
orchestrator = Orchestrator.new(
  hard_critics: [MyCustomHardCritic | HardCritic.all_critics()],
  soft_critics: SoftCritic.all_critics(),
  cache_enabled: true,
  parallel_execution: true,
  timeout: 60_000
)

# Configure specific critic
orchestrator = Orchestrator.configure_critic(
  orchestrator,
  SecurityChecker,
  %{strict_mode: true}
)
```

### Creating Custom Critics
```elixir
defmodule MyCustomCritic do
  @behaviour RubberDuck.Planning.Critics.CriticBehaviour
  
  @impl true
  def name, do: "My Custom Critic"
  
  @impl true
  def type, do: :soft
  
  @impl true
  def priority, do: 150
  
  @impl true
  def validate(target, opts) do
    # Custom validation logic
    {:ok, %{
      status: :passed,
      message: "Custom validation passed",
      suggestions: ["Consider X", "Try Y"]
    }}
  end
end
```

## Benefits

1. **Quality Assurance**: Ensures both correctness and quality of AI-generated plans
2. **Early Detection**: Catches issues before execution
3. **Actionable Feedback**: Provides specific suggestions for improvements
4. **Performance**: Parallel execution minimizes validation overhead
5. **Flexibility**: Easy to customize validation rules
6. **Comprehensive**: Covers syntax, logic, best practices, performance, and security

## Future Improvements

1. **Validation Dashboard UI**: Visual interface for validation results
2. **Historical Analysis**: Track validation trends over time
3. **Machine Learning**: Learn from validation patterns
4. **More Critics**: Additional domain-specific critics
5. **External Integrations**: Connect to external validation services
6. **Async Validation**: Support for long-running validations
7. **Validation Policies**: Define validation requirements per project

## Testing

Comprehensive test suite covering:
- All individual critics
- Orchestrator functionality
- Parallel execution
- Error handling
- Custom critic integration
- Result aggregation

Run tests with:
```bash
mix test test/rubber_duck/planning/critics
```