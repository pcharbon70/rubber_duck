defmodule RubberDuck.CLI.Formatter.Json do
  @moduledoc """
  JSON formatter for CLI output.
  """

  @doc """
  Formats the result as JSON.
  """
  def format(result) do
    case Jason.encode(result, pretty: true) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, "Failed to encode JSON: #{inspect(reason)}"}
    end
  end
end
