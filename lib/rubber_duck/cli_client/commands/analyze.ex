defmodule RubberDuck.CLIClient.Commands.Analyze do
  @moduledoc """
  Analyze command handler for CLI client.
  """

  alias RubberDuck.CLIClient.Client

  def run(args, opts) do
    params = %{
      "path" => args.path,
      "type" => args[:type] || :all,
      "recursive" => Map.get(args, :recursive, false),
      "format" => opts[:format],
      "verbose" => opts[:verbose]
    }
    
    case Client.send_command("analyze", params) do
      {:ok, result} ->
        {:ok, result}
        
      {:error, reason} ->
        {:error, format_error(reason)}
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end