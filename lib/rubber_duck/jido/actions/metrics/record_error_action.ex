defmodule RubberDuck.Jido.Actions.Metrics.RecordErrorAction do
  @moduledoc """
  Action for recording error occurrences in agent operations.
  
  This action captures error events with type classification for
  error rate analysis and alerting.
  """
  
  use Jido.Action,
    name: "record_error",
    description: "Records error occurrences for metrics analysis",
    schema: [
      agent_id: [
        type: :string,
        required: true,
        doc: "ID of the agent where the error occurred"
      ],
      error_type: [
        type: :atom,
        required: true,
        doc: "Type/category of the error"
      ]
    ]

  alias RubberDuck.Jido.Actions.Base.UpdateStateAction
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    %{agent_id: agent_id, error_type: error_type} = params
    
    Logger.debug("Recording error occurrence", 
      agent_id: agent_id, 
      error_type: error_type
    )
    
    # Add to current window error data
    current_errors = get_in(agent.state.current_window, [:errors, agent_id]) || []
    updated_errors = [error_type | current_errors]
    
    state_updates = %{
      current_window: put_in(
        agent.state.current_window,
        [:errors, agent_id],
        updated_errors
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