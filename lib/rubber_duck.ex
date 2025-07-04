defmodule RubberDuck do
  @moduledoc """
  RubberDuck is an Elixir-based AI coding assistant system built with the Ash Framework.
  
  This module serves as the main entry point for the RubberDuck application,
  providing core functionality for code analysis, assistance, and LLM integration.
  """

  @doc """
  Returns the application version.

  ## Examples

      iex> RubberDuck.version()
      "0.1.0"

  """
  def version do
    Application.spec(:rubber_duck, :vsn) |> to_string()
  end
end
