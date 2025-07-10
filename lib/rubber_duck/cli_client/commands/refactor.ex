defmodule RubberDuck.CLIClient.Commands.Refactor do
  @moduledoc """
  Refactor command handler for CLI client.
  """

  alias RubberDuck.CLIClient.Client

  def run(args, opts) do
    # Extract values from Optimus.ParseResult struct
    file = Map.get(args.args, :file)
    instruction = Map.get(args.args, :instruction)
    dry_run = Map.get(args.flags, :dry_run, false)

    params = %{
      "file" => file,
      "instruction" => instruction,
      "dry_run" => dry_run,
      "format" => opts[:format],
      "verbose" => opts[:verbose]
    }

    case Client.send_command("refactor", params) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
