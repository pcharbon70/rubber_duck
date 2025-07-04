# CODE GENERATION RULES

**MANDATORY RULES FOR ALL CODE GENERATION**

## Variable Naming

### Unused Variables
- **ALWAYS** prefix unused variables with "_" to prevent compiler warnings
- Examples:
  - `def handle_call(_msg, _from, state)` - when msg and from are not used
  - `def init(_args)` - when args parameter is not used  
  - `{:ok, _pid}` - when pid is not used in pattern matching
  - `case result do {:error, _reason} -> :error end` - when reason is not needed

### Variable Usage
- If a variable is used later in the function, do NOT prefix with "_"
- Only prefix with "_" if the variable is truly unused in the function body

## Code Quality

### Compilation Warnings
- **ZERO TOLERANCE** for compilation warnings
- All unused variables must be prefixed with "_"
- All unused imports must be removed
- All unused aliases must be removed

### Pattern Matching
- Use "_" prefix in pattern matches when values are not needed
- Example: `{:ok, _result}` instead of `{:ok, result}` when result is unused

## Examples

### ❌ Bad (causes warnings)
```elixir
def handle_call(msg, from, state) do
  {:reply, :ok, state}
end

def process({:ok, result}) do
  :success
end
```

### ✅ Good (no warnings)
```elixir  
def handle_call(_msg, _from, state) do
  {:reply, :ok, state}
end

def process({:ok, _result}) do
  :success
end
```

## Enforcement
- All code MUST compile without warnings
- Code review will check for proper "_" prefixing
- CI/CD pipeline should fail on compilation warnings
