defmodule RubberDuck.Jido.Actions.ResponseProcessor.GetCachedResponseAction do
  @moduledoc """
  Action for retrieving cached responses.
  
  This action checks the cache for existing responses and emits appropriate
  signals for cache hits or misses.
  """
  
  use Jido.Action,
    name: "get_cached_response",
    description: "Retrieves cached responses and handles cache hits/misses",
    schema: [
      cache_key: [
        type: :string,
        required: true,
        doc: "The cache key to look up"
      ]
    ]

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    cache_key = params.cache_key
    
    case get_from_cache(agent, cache_key) do
      {:hit, cached_response} ->
        signal_data = Map.merge(cached_response, %{
          timestamp: DateTime.utc_now()
        })
        
        case EmitSignalAction.run(
          %{signal_type: "response.cache.hit", data: signal_data},
          %{agent: agent}
        ) do
          {:ok, _result, %{agent: updated_agent}} ->
            {:ok, %{cache_hit: true, response: cached_response}, %{agent: updated_agent}}
          {:error, reason} ->
            {:error, {:signal_emission_failed, reason}}
        end
        
      :miss ->
        signal_data = %{
          cache_key: cache_key,
          timestamp: DateTime.utc_now()
        }
        
        case EmitSignalAction.run(
          %{signal_type: "response.cache.miss", data: signal_data},
          %{agent: agent}
        ) do
          {:ok, _result, %{agent: updated_agent}} ->
            {:ok, %{cache_hit: false, cache_key: cache_key}, %{agent: updated_agent}}
          {:error, reason} ->
            {:error, {:signal_emission_failed, reason}}
        end
    end
  end

  # Private functions

  defp get_from_cache(agent, cache_key) do
    case Map.get(agent.state.cache, cache_key) do
      nil -> 
        :miss
      %{expires_at: expires_at} = entry ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:hit, Map.get(entry, :data)}
        else
          :miss
        end
    end
  end
end