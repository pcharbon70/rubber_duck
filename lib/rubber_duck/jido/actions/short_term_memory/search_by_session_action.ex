defmodule RubberDuck.Jido.Actions.ShortTermMemory.SearchBySessionAction do
  use Jido.Action,
    name: "search_by_session",
    description: "Search memory items by user and session",
    schema: [
      user_id: [type: :string, required: true],
      session_id: [type: :string, required: true]
    ]
  
  @impl true
  def run(params, context) do
    agent = context.agent
    session_key = {params.user_id, params.session_id}
    
    case :ets.lookup(agent.state.ets_tables.session_index, session_key) do
      [] -> {:ok, [], %{agent: agent}}
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