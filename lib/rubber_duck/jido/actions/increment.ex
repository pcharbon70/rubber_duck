defmodule RubberDuck.Jido.Actions.Increment do
  @moduledoc """
  Action to increment a counter value.
  """
  
  use Jido.Action,
    name: "increment",
    description: "Increments a counter by a specified amount",
    schema: [
      amount: [type: :integer, default: 1]
    ]
  
  @impl true
  def run(params, context) do
    # Get amount from context first (user-provided), then params (schema default)
    amount = Map.get(context, :amount, Map.get(params, :amount, 1))
    
    # Context might have state directly or within agent
    state = case context do
      %{agent: %{state: state}} -> state
      %{state: state} -> state
      _ -> %{}
    end
    
    current_value = Map.get(state, :counter, 0)
    new_value = current_value + amount
    
    # Update the state
    updated_state = Map.put(state, :counter, new_value)
    
    # Return as a directive to update agent state
    {:ok, {:set, updated_state}}
  end
end