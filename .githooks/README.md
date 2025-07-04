# Git Hooks for RubberDuck

This directory contains Git hooks to ensure code quality and consistency across the RubberDuck project.

## Installation

To install the git hooks, run the installation script from the project root:

```bash
./.githooks/install.sh
```

This will configure Git to use the hooks in this directory.

## Available Hooks

### pre-commit

The pre-commit hook runs automatically before each commit and performs the following checks:

1. **Format Check** - Ensures all staged Elixir files are properly formatted according to `.formatter.exs`
2. **Compilation Check** - Verifies the code compiles without warnings or errors
3. **Linting** - Runs Credo (if installed) to check for code quality issues

If any check fails, the commit will be aborted, and you'll need to fix the issues before committing.

## Manual Execution

You can manually run the pre-commit hook to test your changes:

```bash
./.githooks/pre-commit
```

## Bypassing Hooks

In rare cases where you need to bypass the hooks (not recommended), you can use:

```bash
git commit --no-verify
```

⚠️ **Warning**: Only bypass hooks when absolutely necessary, as this can introduce formatting inconsistencies or broken code into the repository.

## Uninstalling

To disable the git hooks:

```bash
git config --unset core.hooksPath
```

## Troubleshooting

### Hook not executing

1. Ensure the hook files are executable:
   ```bash
   chmod +x .githooks/*
   ```

2. Verify git is configured to use the hooks:
   ```bash
   git config core.hooksPath
   # Should output: .githooks
   ```

### Mix command not found

Ensure Elixir and Mix are installed and available in your PATH.

### Credo not running

The pre-commit hook will skip Credo checks if it's not installed. To enable Credo:

1. Add Credo to your dependencies in `mix.exs`:
   ```elixir
   {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
   ```

2. Run `mix deps.get` to install it.

## Contributing

When adding new hooks:

1. Create the hook file in `.githooks/`
2. Make it executable: `chmod +x .githooks/your-hook`
3. Update this README with documentation
4. Test the hook thoroughly before committing