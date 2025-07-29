defmodule RubberDuck.Jido.Agents.ExampleAgent do
  @moduledoc """
  Example agent demonstrating proper Jido patterns.
  
  This agent shows:
  - Proper use of Jido.Agent behavior
  - Schema definition for state validation
  - Lifecycle callbacks
  - Integration with RubberDuck infrastructure
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "example_agent",
    description: "Example agent for demonstration",
    schema: [
      counter: [type: :integer, default: 0],
      messages: [type: {:list, :string}, default: []],
      status: [type: {:in, [:idle, :busy, :error]}, default: :idle],
      last_action: [type: {:or, [:string, nil]}, default: nil]
    ],
    actions: [
      RubberDuck.Jido.Actions.Increment
    ]
  
  require Logger
  
  # Lifecycle callbacks
  
  @impl true
  def on_before_run(agent) do
    Logger.debug("ExampleAgent #{agent.id} starting action")
    
    # Set status to busy
    updated_state = Map.put(agent.state, :status, :busy)
    {:ok, %{agent | state: updated_state}}
  end
  
  @impl true
  def on_after_run(agent, _result, metadata) do
    Logger.debug("ExampleAgent #{agent.id} completed action")
    
    # Update status and last action
    updated_state = 
      agent.state
      |> Map.put(:status, :idle)
      |> Map.put(:last_action, inspect(metadata[:action]))
    
    {:ok, %{agent | state: updated_state}}
  end
  
  @impl true
  def on_error(agent, error) do
    Logger.error("ExampleAgent #{agent.id} error: #{inspect(error)}")
    
    # Set error status
    updated_state = Map.put(agent.state, :status, :error)
    {:ok, %{agent | state: updated_state}}
  end
  
  # Custom behavior
  
  @impl true
  def health_check(agent) do
    cond do
      agent.state.status == :error ->
        {:unhealthy, %{reason: "Agent in error state"}}
        
      agent.state.counter > 1000 ->
        {:unhealthy, %{reason: "Counter too high", counter: agent.state.counter}}
        
      length(agent.state.messages) > 100 ->
        {:unhealthy, %{reason: "Too many messages", count: length(agent.state.messages)}}
        
      true ->
        {:healthy, %{
          counter: agent.state.counter,
          message_count: length(agent.state.messages),
          status: agent.state.status
        }}
    end
  end
end