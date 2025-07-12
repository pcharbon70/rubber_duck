defmodule RubberDuck.CLIClient.Formatter do
  @moduledoc """
  Output formatting for CLI client responses.
  
  This module delegates to the unified formatters for consistent formatting
  across all client interfaces.
  """

  alias RubberDuck.Commands.Formatters

  @doc """
  Format output based on the specified format using unified formatters.
  """
  def format(output, format) do
    formatters = Formatters.load_formatters()
    
    formatter = case format do
      :json -> Map.get(formatters, :json)
      :plain -> Map.get(formatters, :text)
      :table -> Map.get(formatters, :table)
      _ -> Map.get(formatters, :text)
    end
    
    if formatter do
      formatter.format(output)
    else
      # Should not happen, but provide minimal fallback
      inspect(output, pretty: true)
    end
  end
end
