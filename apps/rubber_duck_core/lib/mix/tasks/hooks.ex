defmodule Mix.Tasks.Hooks.Install do
  use Mix.Task

  @shortdoc "Installs git hooks for pre-commit quality checks"

  @moduledoc """
  Installs git hooks for the RubberDuck project.

  ## Usage

      mix hooks.install

  This task installs a pre-commit hook that runs code quality checks
  before allowing commits. The hook runs the same checks as `mix quality`:

  - Code formatting verification
  - Credo linting (strict mode)
  - Compilation with warnings as errors

  The hook can be bypassed temporarily with `git commit --no-verify` if needed.

  ## Options

      --force    - Overwrite existing hooks without prompting

  """

  @hooks_dir ".git/hooks"
  @pre_commit_hook Path.join(@hooks_dir, "pre-commit")
  @script_source "scripts/pre-commit"

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [force: :boolean])
    force = opts[:force] || false

    install_hooks(force)
  end

  defp install_hooks(force) do
    unless File.exists?(@hooks_dir) do
      Mix.shell().error("Error: .git/hooks directory not found. Are you in a git repository?")
      System.halt(1)
    end

    unless File.exists?(@script_source) do
      Mix.shell().error("Error: Hook script not found at #{@script_source}")
      System.halt(1)
    end

    install_pre_commit_hook(force)
  end

  defp install_pre_commit_hook(force) do
    if File.exists?(@pre_commit_hook) and not force do
      response = Mix.shell().yes?("Pre-commit hook already exists. Overwrite?")

      unless response do
        Mix.shell().info("Skipping pre-commit hook installation.")
        :ok
      else
        do_install_hook()
      end
    else
      do_install_hook()
    end
  end

  defp do_install_hook do
    case File.cp(@script_source, @pre_commit_hook) do
      :ok ->
        # Make the hook executable
        case File.chmod(@pre_commit_hook, 0o755) do
          :ok ->
            Mix.shell().info("✅ Pre-commit hook installed successfully!")
            Mix.shell().info("The hook will run quality checks before each commit.")
            Mix.shell().info("Use 'git commit --no-verify' to bypass the hook if needed.")

          {:error, reason} ->
            Mix.shell().error("Failed to make hook executable: #{reason}")
            System.halt(1)
        end

      {:error, reason} ->
        Mix.shell().error("Failed to install pre-commit hook: #{reason}")
        System.halt(1)
    end
  end
end

defmodule Mix.Tasks.Hooks.Uninstall do
  use Mix.Task

  @shortdoc "Uninstalls git hooks"

  @moduledoc """
  Uninstalls git hooks for the RubberDuck project.

  ## Usage

      mix hooks.uninstall

  This removes the pre-commit hook that was installed with `mix hooks.install`.
  """

  @pre_commit_hook ".git/hooks/pre-commit"

  def run(_args) do
    if File.exists?(@pre_commit_hook) do
      response = Mix.shell().yes?("Remove pre-commit hook?")

      if response do
        case File.rm(@pre_commit_hook) do
          :ok ->
            Mix.shell().info("✅ Pre-commit hook removed successfully!")

          {:error, reason} ->
            Mix.shell().error("Failed to remove pre-commit hook: #{reason}")
            System.halt(1)
        end
      else
        Mix.shell().info("Hook removal cancelled.")
      end
    else
      Mix.shell().info("No pre-commit hook found to remove.")
    end
  end
end

defmodule Mix.Tasks.Hooks do
  use Mix.Task

  @shortdoc "Manage git hooks"

  @moduledoc """
  Manage git hooks for the RubberDuck project.

  ## Available commands

      mix hooks.install      - Install pre-commit quality check hook
      mix hooks.uninstall    - Remove pre-commit hook

  ## Examples

      mix hooks.install      # Install the pre-commit hook
      mix hooks.uninstall    # Remove the pre-commit hook

  """

  def run([]) do
    Mix.shell().info("Available hook commands:")
    Mix.shell().info("  mix hooks.install    - Install pre-commit quality check hook")
    Mix.shell().info("  mix hooks.uninstall  - Remove pre-commit hook")
    Mix.shell().info("")
    Mix.shell().info("Run 'mix help hooks.COMMAND' for more information on a specific command.")
  end

  def run(args) do
    Mix.shell().error("Unknown command. Available commands: install, uninstall")
    run([])
  end
end
