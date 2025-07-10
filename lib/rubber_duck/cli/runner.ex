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

  defp execute_command(:llm, args, config) do
    # For llm command with nested subcommands, we need to handle it differently
    # args will have the structure from the nested subcommand
    case args do
      %{subcommand: nil} ->
        # No subcommand specified, default to status
        Commands.LLM.run(:status, %{}, config)

      %{subcommand: {subcommand, subcommand_args}} ->
        # Pass the subcommand and its args
        Commands.LLM.run(subcommand, subcommand_args, config)

      _ ->
        # Fallback - might be direct args
        Commands.LLM.run(:status, args, config)
    end
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
