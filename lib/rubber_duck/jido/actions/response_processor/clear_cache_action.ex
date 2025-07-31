defmodule RubberDuck.Jido.Actions.ResponseProcessor.ClearCacheAction do
  @moduledoc """
  Action for clearing all cached responses.
  
  This action removes all entries from the response cache and emits
  a signal with the number of cleared entries.
  """
  
  use Jido.Action,
    name: "clear_cache",
    description: "Clears all cached responses and reports the number of cleared entries",
    schema: []

  alias RubberDuck.Jido.Actions.Base.{EmitSignalAction, UpdateStateAction}
  require Logger

  @impl true
  def run(_params, context) do
    agent = context.agent
    cache_size = map_size(agent.state.cache)
    
    # Clear the cache
    with {:ok, _result, %{agent: updated_agent}} <- UpdateStateAction.run(
      %{updates: %{cache: %{}}},
      %{agent: agent}
    ) do
      # Emit success signal
      signal_data = %{
        cleared_entries: cache_size,
        timestamp: DateTime.utc_now()
      }
      
      case EmitSignalAction.run(
        %{signal_type: "response.cache.cleared", data: signal_data},
        %{agent: updated_agent}
      ) do
        {:ok, _result, %{agent: final_agent}} ->
          Logger.info("ResponseProcessorAgent cache cleared (#{cache_size} entries)")
          {:ok, signal_data, %{agent: final_agent}}
        {:error, reason} ->
          {:error, {:signal_emission_failed, reason}}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end
end