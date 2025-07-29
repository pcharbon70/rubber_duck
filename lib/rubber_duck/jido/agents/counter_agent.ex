defmodule RubberDuck.Jido.Agents.CounterAgent do
  @moduledoc """
  Example Jido agent that maintains a counter.
  
  This demonstrates proper Jido agent patterns including:
  - Schema definition
  - Action registration
  - Lifecycle callbacks
  - Signal handling
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "counter_agent",
    description: "An agent that maintains and manipulates a counter",
    schema: [
      value: [type: :integer, default: 0],
      last_operation: [type: :atom, default: nil],
      history: [type: {:list, :map}, default: []]
    ]
  
  # Custom lifecycle callbacks
  
  @impl Jido.Agent
  def on_after_run(agent, {:ok, result}, metadata) do
    # Track operation history
    operation = metadata[:action] || :unknown
    history_entry = %{
      operation: operation,
      result: result,
      timestamp: DateTime.utc_now()
    }
    
    updated_agent = 
      agent
      |> Map.update!(:state, fn state ->
        state
        |> Map.put(:last_operation, operation)
        |> Map.update(:history, [history_entry], &[history_entry | &1])
      end)
    
    # Call parent implementation for telemetry
    super(updated_agent, {:ok, result}, metadata)
  end
  
  # Signal handling
  
  @impl true
  def handle_signal(agent, %{"type" => "increment"} = signal) do
    amount = signal["amount"] || 1
    
    # TODO: Replace with proper Jido action enqueueing when Runtime is available
    # For now, execute directly
    {:ok, agent} = agent.__struct__.plan(agent, RubberDuck.Jido.Actions.Increment, %{amount: amount})
    {:ok, agent} = agent.__struct__.run(agent)
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "get_status"} = _signal) do
    # Emit status signal
    status_signal = %{
      "type" => "status_response",
      "data" => %{
        "value" => agent.state.value,
        "last_operation" => agent.state.last_operation,
        "history_count" => length(agent.state.history)
      }
    }
    
    emit_signal(agent, status_signal)
    {:ok, agent}
  end
  
  def handle_signal(agent, _signal) do
    # Default: ignore unknown signals
    {:ok, agent}
  end
end