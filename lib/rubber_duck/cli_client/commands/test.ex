defmodule RubberDuck.CLIClient.Commands.Test do
  @moduledoc """
  Test generation command handler for CLI client.
  """

  alias RubberDuck.CLIClient.Client

  def run(args, opts) do
    # Extract values from Optimus.ParseResult struct
    file = Map.get(args.args, :file)
    framework = Map.get(args.options, :framework, "exunit")
    output = Map.get(args.options, :output)

    params = %{
      "file" => file,
      "framework" => framework,
      "output" => output,
      "format" => opts[:format],
      "verbose" => opts[:verbose]
    }

    case Client.send_command("test", params) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
