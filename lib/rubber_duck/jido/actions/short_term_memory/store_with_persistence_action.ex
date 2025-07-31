defmodule RubberDuck.Jido.Actions.ShortTermMemory.StoreWithPersistenceAction do
  use Jido.Action,
    name: "store_with_persistence",
    description: "Store memory item with Ash persistence",
    schema: [
      user_id: [type: :string, required: true],
      session_id: [type: :string, required: false],
      type: [type: :atom, default: :chat],
      content: [type: :string, required: true],
      metadata: [type: :map, default: %{}]
    ]
  
  alias RubberDuck.Jido.Actions.ShortTermMemory.StoreMemoryAction
  alias RubberDuck.Memory
  
  @impl true
  def run(params, context) do
    # First store in memory
    case StoreMemoryAction.run(params, context) do
      {:ok, memory_result, %{agent: updated_agent}} ->
        # Then persist to Ash resource
        case persist_to_ash(params) do
          {:ok, ash_record} ->
            result = Map.merge(memory_result, %{
              stored_in_memory: true,
              persisted_to_ash: true,
              ash_record_id: ash_record.id
            })
            {:ok, result, %{agent: updated_agent}}
          {:error, reason} ->
            result = Map.merge(memory_result, %{
              stored_in_memory: true,
              persisted_to_ash: false,
              ash_error: reason
            })
            {:ok, result, %{agent: updated_agent}}
        end
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp persist_to_ash(params) do
    interaction_params = %{
      user_id: params.user_id,
      session_id: params[:session_id] || "default",
      type: params.type,
      content: params.content,
      metadata: params.metadata
    }
    
    Memory.store_interaction(interaction_params)
  end
end