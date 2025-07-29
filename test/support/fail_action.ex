defmodule RubberDuck.Test.FailAction do
  @moduledoc """
  Test action that always fails. Used for testing error handling.
  """
  
  use Jido.Action,
    name: "fail_action",
    description: "Action that always fails",
    schema: []
    
  @impl true
  def run(_params, _context) do
    {:error, "This action always fails"}
  end
end