defmodule RubberDuck.CLIClient.Commands.Test do
  @moduledoc """
  Test generation command handler for CLI client.
  """

  alias RubberDuck.CLIClient.Client

  def run(args, opts) do
    params = %{
      "file" => args.file,
      "framework" => args[:framework] || "exunit",
      "output" => args[:output],
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