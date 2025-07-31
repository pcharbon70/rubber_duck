defmodule RubberDuck.Jido.Actions.ShortTermMemory.SearchByUserAction do
  @moduledoc """
  Action to search memory items by user ID.
  """
  
  use Jido.Action,
    name: "search_by_user",
    description: "Search memory items by user ID",
    schema: [
      user_id: [type: :string, required: true]
    ]
  
  @impl true
  def run(params, context) do
    agent = context.agent
    
    case :ets.lookup(agent.state.ets_tables.user_index, params.user_id) do
      [] -> 
        {:ok, [], %{agent: agent}}
      results ->
        item_ids = Enum.map(results, fn {_, item_id} -> item_id end)
        items = fetch_items_by_ids(agent, item_ids)
        {:ok, items, %{agent: agent}}
    end
  end
  
  defp fetch_items_by_ids(agent, item_ids) do
    Enum.reduce(item_ids, [], fn item_id, acc ->
      case :ets.lookup(agent.state.ets_tables.primary, item_id) do
        [{^item_id, item_data}] ->
          if DateTime.compare(DateTime.utc_now(), item_data.expires_at) == :lt do
            [item_data | acc]
          else
            acc
          end
        [] -> acc
      end
    end)
    |> Enum.reverse()
  end
end