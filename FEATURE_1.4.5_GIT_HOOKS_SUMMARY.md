# Feature 1.4.5: Git Hooks for Pre-commit Quality Checks

## Overview

This feature implements automated code quality checks that run before each commit to ensure code consistency and quality across the RubberDuck project.

## Implementation Details

### Components Created

1. **Pre-commit Hook Script** (`scripts/pre-commit`)
   - Shell script that runs before each commit
   - Checks for staged Elixir files and runs quality checks
   - Provides colored output and helpful error messages
   - Can be bypassed with `git commit --no-verify`

2. **Mix Tasks** (`apps/rubber_duck_core/lib/mix/tasks/hooks.ex`)
   - `mix hooks.install` - Installs the pre-commit hook
   - `mix hooks.uninstall` - Removes the pre-commit hook
   - `mix hooks` - Shows available hook commands

3. **Mix Aliases** (in root `mix.exs`)
   - `hooks.install` - Installs hooks from umbrella root
   - `hooks.uninstall` - Uninstalls hooks from umbrella root

### Quality Checks Performed

The pre-commit hook runs the following checks on staged Elixir files:

1. **Code Formatting** - Ensures consistent code formatting
2. **Credo Linting** - Strict mode linting for code quality
3. **Compilation** - Compilation with warnings treated as errors

### Features

- **Smart Detection**: Only runs on staged `.ex` and `.exs` files
- **Merge Commit Skip**: Automatically skips checks for merge commits
- **Colored Output**: User-friendly colored terminal output
- **Helpful Messages**: Provides specific suggestions for fixing issues
- **Bypass Option**: Can be temporarily bypassed with `--no-verify`
- **Error Handling**: Graceful error handling with informative messages

### Installation

```bash
# Install the pre-commit hook
mix hooks.install

# Install with force (overwrites existing hook)
mix hooks.install --force

# Uninstall the hook
mix hooks.uninstall
```

### Usage

Once installed, the hook runs automatically on each commit attempt. If quality checks fail, the commit is prevented and helpful error messages are displayed.

### Example Output

**Successful commit:**
```
ℹ Running pre-commit quality checks...
ℹ Found staged Elixir files:
  lib/rubber_duck.ex
ℹ Running code quality checks (mix quality)...
✅ All pre-commit quality checks passed!
ℹ Your commit is ready to proceed.
```

**Failed commit:**
```
ℹ Running pre-commit quality checks...
ℹ Found staged Elixir files:
  lib/rubber_duck.ex
ℹ Running code quality checks (mix quality)...
❌ Pre-commit quality checks failed!
⚠ Please fix the issues above before committing.
ℹ Quick fixes you can try:
ℹ   • Run mix format.all to auto-fix formatting issues
ℹ   • Run mix quality to see the same checks
ℹ   • Run mix credo --strict for detailed linting feedback
⚠ To bypass this hook temporarily (not recommended), use:
⚠   git commit --no-verify
```

## Testing

The hook has been tested with:
- ✅ Syntax errors (prevents commit)
- ✅ Formatting issues (prevents commit)
- ✅ Clean code (allows commit)
- ✅ Non-Elixir files (skips checks)
- ✅ Merge commits (skips checks)

## Files Modified

- `scripts/pre-commit` - New pre-commit hook script
- `apps/rubber_duck_core/lib/mix/tasks/hooks.ex` - New Mix tasks
- `mix.exs` - Added hook installation aliases

## Integration

The hook integrates seamlessly with the existing `mix quality` alias, ensuring consistency between manual quality checks and automated pre-commit checks.