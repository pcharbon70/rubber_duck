defmodule RubberDuck.CLI.Runner do
  @moduledoc """
  Coordinates the execution of CLI commands, handling common concerns
  like output formatting, error handling, and progress tracking.
  """

  alias RubberDuck.Commands.{Command, Context, Processor}
  alias RubberDuck.CLI.Formatter

  @doc """
  Runs a CLI command with the given arguments and configuration.

  Returns {:ok, output} on success or {:error, reason} on failure.
  """
  def run(command_name, args, config) do
    with {:ok, command} <- build_command(command_name, args, config),
         {:ok, result} <- Processor.execute(command),
         {:ok, formatted} <- format_output(result, config) do
      output(formatted, config)
      {:ok, formatted}
    end
  end

  defp build_command(nil, _args, _config) do
    {:error, "No command specified. Run with --help for usage information."}
  end

  defp build_command(command_name, args, config) when is_atom(command_name) do
    # Build context
    context = %Context{
      user_id: config[:user_id] || "cli_user",
      session_id: config[:session_id] || generate_session_id(),
      permissions: [:read, :write, :execute],
      metadata: %{source: "cli"}
    }

    # Handle LLM subcommands
    {name, subcommand, processed_args} = case command_name do
      :llm -> handle_llm_subcommand(args)
      _ -> {command_name, nil, args}
    end

    command = %Command{
      name: name,
      subcommand: subcommand,
      args: processed_args,
      options: config,
      context: context,
      client_type: :cli,
      format: config[:format] || :text
    }

    {:ok, command}
  end

  defp build_command(unknown, _args, _config) do
    {:error, "Unknown command: #{unknown}"}
  end

  defp handle_llm_subcommand(args) do
    case args do
      %{subcommand: nil} ->
        {:llm, :status, %{}}
        
      %{subcommand: {subcommand, subcommand_args}} ->
        {:llm, subcommand, subcommand_args}
        
      _ ->
        {:llm, :status, args}
    end
  end

  defp generate_session_id do
    "cli_#{System.system_time(:second)}_#{:rand.uniform(1000)}"
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
