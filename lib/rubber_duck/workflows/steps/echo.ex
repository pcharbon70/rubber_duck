defmodule RubberDuck.Workflows.Steps.Echo do
  @moduledoc """
  Simple test step that echoes its input.
  Used for testing workflow construction.
  """

  use Reactor.Step

  @impl true
  def run(arguments, _context, _options) do
    {:ok, arguments[:input] || arguments}
  end
end
