defmodule RubberDuck.Jido.Actions.ShortTermMemory.StoreMemoryAction do
  @moduledoc """
  Action to store a memory item in short-term memory with TTL and indexing.
  
  This action:
  - Generates a unique item ID
  - Stores the item in the primary ETS table
  - Updates user and session indexes
  - Sets TTL for automatic expiration
  - Updates storage metrics
  """
  
  use Jido.Action,
    name: "store_memory",
    description: "Store memory item with TTL and indexing",
    schema: [
      user_id: [type: :string, required: true],
      session_id: [type: :string, required: false],
      type: [type: :atom, default: :chat],
      content: [type: :string, required: true],
      metadata: [type: :map, default: %{}]
    ]
  
  alias RubberDuck.Jido.Actions.Base.UpdateStateAction
  
  @impl true
  def run(params, context) do
    agent = context.agent
    
    # Generate unique item ID
    item_id = generate_item_id()
    timestamp = DateTime.utc_now()
    
    item_data = %{
      id: item_id,
      user_id: params.user_id,
      session_id: params[:session_id],
      type: params.type,
      content: params.content,
      metadata: params.metadata,
      created_at: timestamp,
      expires_at: DateTime.add(timestamp, agent.state.config.ttl_seconds, :second),
      compressed: false
    }
    
    # Store in primary ETS table
    :ets.insert(agent.state.ets_tables.primary, {item_id, item_data})
    
    # Update indexes
    :ets.insert(agent.state.ets_tables.user_index, {params.user_id, item_id})
    
    if params[:session_id] do
      session_key = {params.user_id, params.session_id}
      :ets.insert(agent.state.ets_tables.session_index, {session_key, item_id})
    end
    
    # Time index for TTL cleanup
    expires_unix = DateTime.to_unix(item_data.expires_at)
    :ets.insert(agent.state.ets_tables.time_index, {expires_unix, item_id})
    
    # Update metrics
    item_size = calculate_item_size(item_data)
    current_metrics = agent.state.metrics
    
    updated_metrics = %{
      current_metrics |
      total_items: current_metrics.total_items + 1,
      memory_usage_bytes: current_metrics.memory_usage_bytes + item_size,
      avg_item_size: calculate_avg_item_size(current_metrics, item_size)
    }
    
    # Update agent state with new metrics
    case UpdateStateAction.run(
      %{updates: %{metrics: updated_metrics}},
      %{agent: agent}
    ) do
      {:ok, _result, %{agent: updated_agent}} ->
        result = %{
          stored: true,
          item_id: item_id,
          expires_at: item_data.expires_at,
          item_size: item_size
        }
        {:ok, result, %{agent: updated_agent}}
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  # Private utility functions
  
  defp generate_item_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  defp calculate_item_size(item_data) do
    :erlang.byte_size(:erlang.term_to_binary(item_data))
  end
  
  defp calculate_avg_item_size(metrics, new_item_size) do
    if metrics.total_items == 0 do
      new_item_size
    else
      (metrics.avg_item_size * metrics.total_items + new_item_size) / (metrics.total_items + 1)
    end
  end
end