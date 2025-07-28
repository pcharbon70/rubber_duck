defmodule RubberDuck.Jido.Actions.AddMessage do
  @moduledoc """
  Action to add a message to an agent's message list.
  """
  
  use Jido.Action,
    name: "add_message",
    description: "Adds a message to the agent's message list",
    schema: [
      message: [type: :string, required: true],
      timestamp: [type: :boolean, default: true]
    ]
  
  @impl true
  def run(params, context) do
    message = if Map.get(params, :timestamp, true) do
      "[#{DateTime.utc_now() |> DateTime.to_iso8601()}] #{Map.get(params, :message, "")}"
    else
      Map.get(params, :message, "")
    end
    
    current_messages = context.agent.state.messages || []
    updated_messages = current_messages ++ [message]
    
    updated_state = Map.put(context.agent.state, :messages, updated_messages)
    updated_agent = Map.put(context.agent, :state, updated_state)
    
    {:ok, %{message_added: message, total_messages: length(updated_messages)}, 
     %{agent: updated_agent}}
  end
end