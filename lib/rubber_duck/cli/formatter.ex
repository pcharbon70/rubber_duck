defmodule RubberDuck.CLI.Formatter do
  @moduledoc """
  Output formatting for CLI commands.

  Supports multiple output formats including plain text, JSON, and table formats.
  """

  alias RubberDuck.CLI.Formatter.{Plain, Json, Table}

  @doc """
  Formats the given result according to the specified format.

  Returns {:ok, formatted_string} or {:error, reason}.
  """
  def format(result, format) do
    case format do
      :plain -> Plain.format(result)
      :json -> Json.format(result)
      :table -> Table.format(result)
      _ -> {:error, "Unknown format: #{format}"}
    end
  end
end
