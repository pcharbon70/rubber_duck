defmodule RubberDuck.CLIClient.Commands.Complete do
  @moduledoc """
  Complete command handler for CLI client.
  """

  alias RubberDuck.CLIClient.Client

  def run(args, opts) do
    params = %{
      "file" => args.file,
      "line" => args.line,
      "column" => args.column,
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