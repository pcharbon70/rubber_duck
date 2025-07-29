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
    amount = Map.get(params, :amount, 1)
    current_value = Map.get(context.agent.state, :counter, 0)
    new_value = current_value + amount
    
    # Update the agent's state
    updated_state = Map.put(context.agent.state, :counter, new_value)
    updated_agent = Map.put(context.agent, :state, updated_state)
    
    {:ok, %{value: new_value, increased_by: amount}, %{agent: updated_agent}}
  end
end