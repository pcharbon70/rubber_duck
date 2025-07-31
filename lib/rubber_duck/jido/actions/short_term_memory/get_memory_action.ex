defmodule RubberDuck.Jido.Actions.ShortTermMemory.GetMemoryAction do
  @moduledoc """
  Action to retrieve a memory item by ID from short-term memory.
  
  This action:
  - Looks up the item in the primary ETS table
  - Checks TTL expiration
  - Updates cache hit/miss metrics
  """
  
  use Jido.Action,
    name: "get_memory",
    description: "Retrieve memory item by ID",
    schema: [
      item_id: [type: :string, required: true]
    ]
  
  alias RubberDuck.Jido.Actions.Base.UpdateStateAction
  
  @impl true
  def run(params, context) do
    agent = context.agent
    
    case :ets.lookup(agent.state.ets_tables.primary, params.item_id) do
      [{item_id, item_data}] ->
        # Check if expired
        if DateTime.compare(DateTime.utc_now(), item_data.expires_at) == :lt do
          # Item found and not expired - cache hit
          updated_metrics = update_in(agent.state.metrics.cache_hits, &(&1 + 1))
          
          case UpdateStateAction.run(
            %{updates: %{metrics: updated_metrics}},
            %{agent: agent}
          ) do
            {:ok, _result, %{agent: updated_agent}} ->
              {:ok, item_data, %{agent: updated_agent}}
            {:error, reason} ->
              {:error, reason}
          end
        else
          # Item expired - cache miss
          updated_metrics = update_in(agent.state.metrics.cache_misses, &(&1 + 1))
          
          case UpdateStateAction.run(
            %{updates: %{metrics: updated_metrics}},
            %{agent: agent}
          ) do
            {:ok, _result, %{agent: updated_agent}} ->
              {:error, :expired, %{agent: updated_agent}}
            {:error, reason} ->
              {:error, reason}
          end
        end
      
      [] ->
        # Item not found - cache miss
        updated_metrics = update_in(agent.state.metrics.cache_misses, &(&1 + 1))
        
        case UpdateStateAction.run(
          %{updates: %{metrics: updated_metrics}},
          %{agent: agent}
        ) do
          {:ok, _result, %{agent: updated_agent}} ->
            {:error, :not_found, %{agent: updated_agent}}
          {:error, reason} ->
            {:error, reason}
        end
    end
  end
end