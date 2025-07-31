defmodule RubberDuck.Jido.Actions.ShortTermMemory.CleanupExpiredAction do
  use Jido.Action,
    name: "cleanup_expired",
    description: "Remove expired memory items",
    schema: []
  
  @impl true
  def run(_params, context) do
    agent = context.agent
    current_time = DateTime.utc_now() |> DateTime.to_unix()
    
    # Find expired items using time index
    expired_items = :ets.select(agent.state.ets_tables.time_index, [
      {{:"$1", :"$2"}, [{:<, :"$1", current_time}], [:"$2"]}
    ])
    
    # Remove expired items
    Enum.each(expired_items, fn item_id ->
      remove_item_from_all_tables(agent, item_id)
    end)
    
    result = %{cleaned: true, items_removed: length(expired_items)}
    {:ok, result, %{agent: agent}}
  end
  
  defp remove_item_from_all_tables(agent, item_id) do
    case :ets.lookup(agent.state.ets_tables.primary, item_id) do
      [{^item_id, item_data}] ->
        :ets.delete(agent.state.ets_tables.primary, item_id)
        :ets.delete_object(agent.state.ets_tables.user_index, {item_data.user_id, item_id})
        
        if item_data.session_id do
          session_key = {item_data.user_id, item_data.session_id}
          :ets.delete_object(agent.state.ets_tables.session_index, {session_key, item_id})
        end
        
        expires_timestamp = DateTime.to_unix(item_data.expires_at)
        :ets.delete_object(agent.state.ets_tables.time_index, {expires_timestamp, item_id})
      [] -> :ok
    end
  end
end