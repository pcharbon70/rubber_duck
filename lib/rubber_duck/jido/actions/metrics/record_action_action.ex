defmodule RubberDuck.Jido.Actions.Metrics.RecordActionAction do
  @moduledoc """
  Action for recording agent action executions and their performance metrics.
  
  This action captures action execution data including duration, status, and
  agent information for later aggregation and analysis.
  """
  
  use Jido.Action,
    name: "record_action",
    description: "Records agent action execution metrics",
    schema: [
      agent_id: [
        type: :string,
        required: true,
        doc: "ID of the agent that executed the action"
      ],
      action: [
        type: :string,
        required: true,
        doc: "Name of the action that was executed"
      ],
      duration_us: [
        type: :integer,
        required: true,
        doc: "Duration of action execution in microseconds"
      ],
      status: [
        type: :atom,
        required: true,
        doc: "Execution status (:success or :error)"
      ]
    ]

  alias RubberDuck.Jido.Actions.Base.UpdateStateAction
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    %{agent_id: agent_id, action: action, duration_us: duration_us, status: status} = params
    
    Logger.debug("Recording action execution", 
      agent_id: agent_id, 
      action: action, 
      duration_us: duration_us, 
      status: status
    )
    
    # Add to current window data
    action_entry = {action, duration_us, status}
    
    current_actions = get_in(agent.state.current_window, [:actions, agent_id]) || []
    updated_actions = [action_entry | current_actions]
    
    state_updates = %{
      current_window: put_in(
        agent.state.current_window,
        [:actions, agent_id],
        updated_actions
      )
    }
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} ->
        {:ok, %{recorded: true}, %{agent: updated_agent}}
      {:error, reason} ->
        {:error, reason}
    end
  end
end