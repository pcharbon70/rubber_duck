defmodule Mix.Tasks.RubberDuck do
  @moduledoc """
  Mix task for running the RubberDuck CLI.

  This provides the main entry point for the RubberDuck command-line interface.

  ## Usage

      mix rubber_duck [command] [args] [options]

  ## Commands

    * `analyze` - Analyze code files or projects
    * `generate` - Generate code from natural language
    * `complete` - Get code completions
    * `refactor` - Refactor code with AI assistance
    * `test` - Generate tests for existing code

  ## Global Options

    * `-v, --verbose` - Enable verbose output
    * `-q, --quiet` - Suppress non-essential output
    * `-f, --format` - Output format (json, plain, table)
    * `-c, --config` - Path to configuration file
    * `--debug` - Enable debug mode

  ## Examples

      # Analyze a file
      mix rubber_duck analyze lib/my_module.ex
      
      # Generate code from a prompt
      mix rubber_duck generate "Create a GenServer that manages a user session"
      
      # Get completions for a file
      mix rubber_duck complete lib/my_module.ex --line 42 --column 10
      
      # Refactor code
      mix rubber_duck refactor lib/my_module.ex "Extract this into a separate function"
      
      # Generate tests
      mix rubber_duck test lib/my_module.ex

  Run `mix rubber_duck [command] --help` for more information on a specific command.
  """

  use Mix.Task

  @shortdoc "AI-powered coding assistant CLI"

  @impl Mix.Task
  def run(args) do
    # Ensure the application is started
    Mix.Task.run("app.start")

    # Delegate to the main CLI module
    RubberDuck.CLI.main(args)
  end
end
