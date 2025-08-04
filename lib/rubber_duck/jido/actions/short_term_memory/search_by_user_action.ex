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
  
  alias RubberDuck.Agents.{ErrorHandling, ActionErrorPatterns}
  require Logger
  
  @impl true
  def run(params, context) do
    ErrorHandling.safe_execute(fn ->
      # Validate parameters and context
      with :ok <- validate_user_params(params),
           :ok <- validate_user_context(context) do
        
        agent = context.agent
        
        # Safely lookup user index
        case safe_user_lookup(agent.state.ets_tables.user_index, params.user_id) do
          {:ok, []} -> 
            {:ok, [], %{agent: agent}}
          {:ok, results} ->
            item_ids = Enum.map(results, fn {_, item_id} -> item_id end)
            case fetch_items_by_ids(agent, item_ids) do
              {:ok, items} ->
                {:ok, items, %{agent: agent}}
              error -> error
            end
          error -> error
        end
      end
    end)
  end
  
  defp validate_user_params(%{user_id: user_id}) when is_binary(user_id) and byte_size(user_id) > 0, do: :ok
  defp validate_user_params(params), do: ErrorHandling.validation_error("Invalid parameters: user_id must be a non-empty string", %{params: params})
  
  defp validate_user_context(%{agent: %{state: %{ets_tables: %{user_index: table, primary: primary}}}}) 
       when not is_nil(table) and not is_nil(primary), do: :ok
  defp validate_user_context(_), do: ErrorHandling.validation_error("Invalid context: missing agent with ETS tables", %{})
  
  defp safe_user_lookup(user_table, user_id) do
    try do
      results = :ets.lookup(user_table, user_id)
      {:ok, results}
    rescue
      ArgumentError ->
        ErrorHandling.resource_error("ETS user index table not available", %{table: user_table})
      error ->
        ErrorHandling.system_error("Failed to lookup user: #{Exception.message(error)}", %{error: inspect(error)})
    end
  end
  
  defp fetch_items_by_ids(agent, item_ids) do
    try do
      current_time = DateTime.utc_now()
      primary_table = agent.state.ets_tables.primary
      
      items = Enum.reduce(item_ids, [], fn item_id, acc ->
        case safe_item_lookup(primary_table, item_id) do
          {:ok, item_data} ->
            # Check if item is still valid (not expired)
            if Map.has_key?(item_data, :expires_at) and not is_nil(item_data.expires_at) do
              if DateTime.compare(current_time, item_data.expires_at) == :lt do
                [item_data | acc]
              else
                acc
              end
            else
              [item_data | acc]
            end
          {:error, :not_found} -> 
            acc
          {:error, _reason} -> 
            acc
        end
      end)
      
      {:ok, Enum.reverse(items)}
    rescue
      error ->
        ErrorHandling.system_error("Failed to fetch items: #{Exception.message(error)}", %{error: inspect(error)})
    end
  end
  
  defp safe_item_lookup(primary_table, item_id) do
    try do
      case :ets.lookup(primary_table, item_id) do
        [{^item_id, item_data}] -> {:ok, item_data}
        [] -> {:error, :not_found}
      end
    rescue
      ArgumentError ->
        {:error, :table_not_available}
      error ->
        {:error, Exception.message(error)}
    end
  end
end