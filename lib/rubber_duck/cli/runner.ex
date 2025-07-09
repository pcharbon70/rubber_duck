defmodule RubberDuck.CLI.Runner do
  @moduledoc """
  Coordinates the execution of CLI commands, handling common concerns
  like output formatting, error handling, and progress tracking.
  """

  alias RubberDuck.CLI.Commands
  alias RubberDuck.CLI.Formatter

  @doc """
  Runs a CLI command with the given arguments and configuration.

  Returns {:ok, output} on success or {:error, reason} on failure.
  """
  def run(command, args, config) do
    with {:ok, result} <- execute_command(command, args, config),
         {:ok, formatted} <- format_output(result, config) do
      output(formatted, config)
      {:ok, formatted}
    end
  end

  defp execute_command(:analyze, args, config) do
    Commands.Analyze.run(args, config)
  end

  defp execute_command(:generate, args, config) do
    Commands.Generate.run(args, config)
  end

  defp execute_command(:complete, args, config) do
    Commands.Complete.run(args, config)
  end

  defp execute_command(:refactor, args, config) do
    Commands.Refactor.run(args, config)
  end

  defp execute_command(:test, args, config) do
    Commands.Test.run(args, config)
  end

  defp execute_command(nil, _args, _config) do
    {:error, "No command specified. Run with --help for usage information."}
  end

  defp execute_command(unknown, _args, _config) do
    {:error, "Unknown command: #{unknown}"}
  end

  defp format_output(result, config) do
    Formatter.format(result, config.format)
  end

  defp output(formatted, config) do
    unless config.quiet do
      IO.puts(formatted)
    end
  end
end
