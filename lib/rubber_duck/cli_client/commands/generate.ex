defmodule RubberDuck.CLIClient.Commands.Generate do
  @moduledoc """
  Generate command handler for CLI client.
  """

  alias RubberDuck.CLIClient.Client

  def run(args, opts) do
    # Extract values from Optimus.ParseResult struct
    prompt = Map.get(args.args, :prompt)
    language = Map.get(args.options, :language, "elixir")
    output = Map.get(args.options, :output)

    params = %{
      "prompt" => prompt,
      "language" => language,
      "output" => output,
      "format" => opts[:format],
      "verbose" => opts[:verbose]
    }

    case Client.send_command("generate", params) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
