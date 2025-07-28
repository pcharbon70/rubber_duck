# Planning Fixes Configuration

The RubberDuck planning system includes automatic fix capabilities for validation failures.

## Configuration Options

### Auto-Fix Plans

Enable or disable automatic fixing of validation failures:

```elixir
# In config/config.exs or config/runtime.exs
config :rubber_duck, :auto_fix_plans, true  # Default: true
```

When enabled, the system will attempt to fix:
- Syntax errors in code snippets
- Missing or invalid task dependencies
- Circular dependencies
- Constraint violations
- Feasibility issues
- Resource requirement problems

### Auto-Improve Plans

Enable or disable automatic improvement of validation warnings:

```elixir
config :rubber_duck, :auto_improve_plans, true  # Default: true
```

When enabled, the system will attempt to improve:
- Vague task descriptions
- Missing success criteria
- Style and convention issues
- Security considerations
- Best practice violations

### Fix Attempt Limits

Configure the maximum number of fix attempts:

```elixir
config :rubber_duck, PlanFixer,
  max_attempts: 3,  # Default: 3
  timeout: 30_000   # Default: 30 seconds
```

## Fix Types

### Syntax Fixes
- Corrects Elixir syntax errors in code snippets
- Fixes malformed function calls
- Ensures proper module references

### Dependency Fixes
- Removes references to non-existent tasks
- Breaks circular dependency chains
- Restructures task ordering

### Constraint Fixes
- Adjusts task durations to meet time constraints
- Modifies resource requirements
- Updates task complexity ratings

### Feasibility Fixes
- Breaks down overly complex tasks
- Clarifies vague descriptions
- Adjusts unrealistic timelines

### Resource Fixes
- Reduces resource requirements where possible
- Suggests alternative resources
- Prioritizes critical needs

## Monitoring Fixes

Fixed plans include metadata about the fixes applied:

```elixir
plan.metadata["auto_fixed"] # true if fixes were applied
plan.metadata["auto_improved"] # true if improvements were applied
```

The planning response will indicate when fixes or improvements were applied:
- 🔧 **Note:** Plan was automatically fixed
- 💡 **Note:** Plan was automatically improved