defmodule RubberDuck.Jido.Actions.RestartTracker.ClearHistoryAction do
  @moduledoc """
  Action for clearing restart history for a specific agent.
  
  This action removes all restart tracking data for an agent,
  effectively resetting its restart history and backoff status.
  """
  
  use Jido.Action,
    name: "clear_history",
    description: "Clears restart history for a specific agent",
    schema: [
      agent_id: [
        type: :string,
        required: true,
        doc: "ID of the agent to clear restart history for"
      ]
    ]

  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    %{agent_id: agent_id} = params
    
    Logger.info("Clearing restart history", agent_id: agent_id)
    
    # Check if agent has any history
    had_history = Map.has_key?(agent.state.restart_data, agent_id)
    
    # Remove the agent's restart data
    new_restart_data = Map.delete(agent.state.restart_data, agent_id)
    state_updates = %{restart_data: new_restart_data}
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} ->
        # Emit history cleared event
        with {:ok, _} <- emit_history_cleared(updated_agent, agent_id, had_history) do
          {:ok, %{history_cleared: true, had_history: had_history}, %{agent: updated_agent}}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions
  
  defp emit_history_cleared(agent, agent_id, had_history) do
    signal_params = %{
      signal_type: "restart_tracker.history.cleared",
      data: %{
        agent_id: agent_id,
        had_previous_history: had_history,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end