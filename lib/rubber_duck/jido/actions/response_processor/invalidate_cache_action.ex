defmodule RubberDuck.Jido.Actions.ResponseProcessor.InvalidateCacheAction do
  @moduledoc """
  Action for invalidating specific cache entries.
  
  This action removes specific cache entries by key or pattern,
  providing flexible cache invalidation capabilities.
  """
  
  use Jido.Action,
    name: "invalidate_cache",
    description: "Invalidates specific cache entries by key or pattern",
    schema: [
      cache_keys: [
        type: {:list, :string},
        default: [],
        doc: "Specific cache keys to invalidate"
      ],
      pattern: [
        type: :string,
        default: nil,
        doc: "Regex pattern to match cache keys for invalidation"
      ]
    ]

  alias RubberDuck.Jido.Actions.Base.{EmitSignalAction, UpdateStateAction}
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    cache_keys = params.cache_keys || []
    pattern = params.pattern
    
    # Perform invalidation
    with {:ok, _result, %{agent: updated_agent}} <- invalidate_cache_entries(agent, cache_keys, pattern) do
      # Emit success signal
      signal_data = %{
        invalidated_keys: cache_keys,
        pattern: pattern,
        timestamp: DateTime.utc_now()
      }
      
      case EmitSignalAction.run(
        %{signal_type: "response.cache.invalidated", data: signal_data},
        %{agent: updated_agent}
      ) do
        {:ok, _result, %{agent: final_agent}} ->
          {:ok, signal_data, %{agent: final_agent}}
        {:error, reason} ->
          {:error, {:signal_emission_failed, reason}}
      end
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp invalidate_cache_entries(agent, cache_keys, pattern) do
    updated_cache = cond do
      pattern != nil ->
        invalidate_by_pattern(agent.state.cache, pattern)
      
      length(cache_keys) > 0 ->
        Map.drop(agent.state.cache, cache_keys)
      
      true ->
        agent.state.cache
    end
    
    UpdateStateAction.run(
      %{updates: %{cache: updated_cache}},
      %{agent: agent}
    )
  end

  defp invalidate_by_pattern(cache, pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} ->
        cache
        |> Enum.reject(fn {key, _entry} -> Regex.match?(regex, key) end)
        |> Map.new()
      
      {:error, _reason} ->
        Logger.warning("Invalid regex pattern for cache invalidation: #{pattern}")
        cache
    end
  end
end