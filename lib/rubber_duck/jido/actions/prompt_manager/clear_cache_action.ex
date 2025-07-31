defmodule RubberDuck.Jido.Actions.PromptManager.ClearCacheAction do
  @moduledoc """
  Action for clearing the agent's cache.
  
  This action clears the agent's cache and emits a signal indicating
  the cache has been cleared successfully.
  """
  
  use Jido.Action,
    name: "clear_cache",
    description: "Clears the agent's cache",
    schema: []

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(_params, context) do
    agent = context.agent
    agent_with_clear_cache = put_in(agent.state.cache, %{})
    
    signal_data = %{
      timestamp: DateTime.utc_now()
    }
    
    case EmitSignalAction.run(
      %{signal_type: "prompt.cache.cleared", data: signal_data},
      %{agent: agent_with_clear_cache}
    ) do
      {:ok, _result, %{agent: updated_agent}} ->
        Logger.info("PromptManagerAgent cache cleared")
        {:ok, signal_data, %{agent: updated_agent}}
      {:error, reason} ->
        {:error, {:signal_emission_failed, reason}}
    end
  end
end