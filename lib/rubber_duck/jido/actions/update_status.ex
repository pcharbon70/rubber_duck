defmodule RubberDuck.Jido.Actions.UpdateStatus do
  @moduledoc """
  Action to update an agent's status.
  """
  
  use Jido.Action,
    name: "update_status",
    description: "Updates the agent's status",
    schema: [
      status: [type: :atom, required: true, values: [:idle, :busy, :error]],
      reason: [type: :string, required: false]
    ]
  
  @impl true
  def run(params, context) do
    old_status = context.agent.state.status
    new_status = params.status
    
    updated_state = Map.put(context.agent.state, :status, new_status)
    updated_agent = Map.put(context.agent, :state, updated_state)
    
    result = %{
      old_status: old_status,
      new_status: new_status,
      changed: old_status != new_status
    }
    
    if params[:reason] do
      Map.put(result, :reason, params.reason)
    end
    
    {:ok, result, %{agent: updated_agent}}
  end
end