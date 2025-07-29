defmodule RubberDuck.Jido.Proper.ExampleAgent do
  @moduledoc """
  Example of a properly implemented Jido agent.
  
  This follows the official Jido patterns where agents are
  data structures with schemas and associated actions.
  """
  
  use Jido.Agent,
    name: "example_agent",
    description: "Demonstrates proper Jido agent patterns",
    schema: [
      counter: [type: :integer, default: 0],
      messages: [type: {:list, :string}, default: []],
      status: [type: :atom, default: :idle, values: [:idle, :busy, :error]],
      last_action: [type: :string, default: nil],
      created_at: [type: :string, required: true]
    ],
    actions: [
      RubberDuck.Jido.Actions.Increment,
      RubberDuck.Jido.Actions.AddMessage,
      RubberDuck.Jido.Actions.UpdateStatus
    ]
  
  # Agent-specific callbacks (following Jido.Agent behavior)
  
  @impl Jido.Agent
  def on_before_run(agent) do
    # Update status to busy before running actions
    updated_agent = put_in(agent.state.status, :busy)
    {:ok, updated_agent}
  end
  
  @impl Jido.Agent
  def on_after_run(agent, _result, metadata) do
    # Update last_action and status after running
    updated_agent = 
      agent
      |> put_in([:state, :status], :idle)
      |> put_in([:state, :last_action], metadata[:action_name])
    
    {:ok, updated_agent}
  end
  
  @impl Jido.Agent
  def on_error(agent, error) do
    # Update status to error
    updated_agent = put_in(agent.state.status, :error)
    
    # Log the error
    require Logger
    Logger.error("ExampleAgent error: #{inspect(error)}")
    
    {:ok, updated_agent}
  end
end