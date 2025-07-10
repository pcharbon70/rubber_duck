defmodule RubberDuck.CLIClient.Commands.Complete do
  @moduledoc """
  Complete command handler for CLI client.
  """

  alias RubberDuck.CLIClient.Client

  def run(args, opts) do
    # Extract values from Optimus.ParseResult struct
    file = Map.get(args.args, :file)
    line = Map.get(args.args, :line)
    column = Map.get(args.args, :column)

    params = %{
      "file" => file,
      "line" => line,
      "column" => column,
      "format" => opts[:format],
      "verbose" => opts[:verbose]
    }

    case Client.send_command("complete", params) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
