defmodule RubberDuck.Jido.Actions.ShortTermMemory.CleanupExpiredAction do
  use Jido.Action,
    name: "cleanup_expired",
    description: "Remove expired memory items",
    schema: []
  
  alias RubberDuck.Agents.ErrorHandling
  require Logger
  
  @impl true
  def run(_params, context) do
    ErrorHandling.safe_execute(fn ->
      # Validate context and ETS tables
      with :ok <- validate_context(context),
           :ok <- validate_ets_tables(context.agent.state) do
        
        agent = context.agent
        current_time = DateTime.utc_now() |> DateTime.to_unix()
        
        # Find expired items using time index
        case safe_find_expired_items(agent.state.ets_tables.time_index, current_time) do
          {:ok, expired_items} ->
            # Remove expired items with error handling
            case safe_remove_expired_items(agent, expired_items) do
              {:ok, removed_count} ->
                result = %{cleaned: true, items_removed: removed_count}
                {:ok, result, %{agent: agent}}
              error -> error
            end
            
          error -> error
        end
      end
    end)
  end
  
  defp validate_context(%{agent: %{state: %{ets_tables: tables}}}) when is_map(tables), do: :ok
  defp validate_context(_), do: ErrorHandling.validation_error("Invalid context: missing agent with ets_tables", %{})
  
  defp validate_ets_tables(%{ets_tables: %{time_index: time_index, primary: primary}}) 
       when not is_nil(time_index) and not is_nil(primary), do: :ok
  defp validate_ets_tables(_), do: ErrorHandling.resource_error("Missing required ETS tables", %{})
  
  defp safe_find_expired_items(time_index_table, current_time) do
    try do
      expired_items = :ets.select(time_index_table, [
        {{:"$1", :"$2"}, [{:<, :"$1", current_time}], [:"$2"]}
      ])
      {:ok, expired_items}
    rescue
      ArgumentError ->
        ErrorHandling.resource_error("ETS table not available for time index lookup", %{table: time_index_table})
      error ->
        ErrorHandling.system_error("Failed to find expired items: #{Exception.message(error)}", %{error: inspect(error)})
    end
  end
  
  defp safe_remove_expired_items(agent, expired_items) do
    try do
      removed_count = Enum.reduce(expired_items, 0, fn item_id, acc ->
        case remove_item_from_all_tables(agent, item_id) do
          :ok -> acc + 1
          :error -> acc
        end
      end)
      
      Logger.debug("Cleaned up #{removed_count} expired memory items")
      {:ok, removed_count}
    rescue
      error ->
        ErrorHandling.system_error("Failed to remove expired items: #{Exception.message(error)}", %{error: inspect(error)})
    end
  end
  
  defp remove_item_from_all_tables(agent, item_id) do
    try do
      tables = agent.state.ets_tables
      
      case :ets.lookup(tables.primary, item_id) do
        [{^item_id, item_data}] ->
          # Remove from primary table
          :ets.delete(tables.primary, item_id)
          
          # Remove from user index if user_id exists
          if Map.has_key?(item_data, :user_id) and not is_nil(item_data.user_id) do
            :ets.delete_object(tables.user_index, {item_data.user_id, item_id})
          end
          
          # Remove from session index if session_id exists
          if Map.has_key?(item_data, :session_id) and not is_nil(item_data.session_id) do
            session_key = {item_data.user_id, item_data.session_id}
            :ets.delete_object(tables.session_index, {session_key, item_id})
          end
          
          # Remove from time index if expires_at exists
          if Map.has_key?(item_data, :expires_at) and not is_nil(item_data.expires_at) do
            expires_timestamp = DateTime.to_unix(item_data.expires_at)
            :ets.delete_object(tables.time_index, {expires_timestamp, item_id})
          end
          
          :ok
          
        [] -> 
          # Item not found, which is okay
          :ok
      end
    rescue
      ArgumentError ->
        Logger.warning("ETS table not available when removing item #{item_id}")
        :error
      error ->
        Logger.error("Error removing item #{item_id}: #{Exception.message(error)}")
        :error
    end
  end
end