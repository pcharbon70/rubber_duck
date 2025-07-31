defmodule RubberDuck.Jido.Actions.Base.UpdateStateAction do
  @moduledoc """
  Base action for updating agent state in the Jido pattern.
  
  This action provides a safe way to update agent state with validation
  and transformation support. It ensures state updates follow the agent's
  schema and can apply custom transformation logic.
  """
  
  use Jido.Action,
    name: "update_state",
    description: "Updates agent state with validation and transformation",
    schema: [
      updates: [
        type: :map,
        required: true,
        doc: "Map of state updates to apply"
      ],
      merge_strategy: [
        type: :atom,
        default: :merge,
        values: [:merge, :deep_merge, :replace],
        doc: "How to apply the updates to existing state"
      ],
      validate: [
        type: :boolean,
        default: true,
        doc: "Whether to validate updates against agent schema"
      ],
      transform: [
        type: {:fun, 2},
        default: nil,
        doc: "Optional transformation function (state, updates) -> updates"
      ]
    ]
  
  require Logger
  
  @impl true
  def run(params, context) do
    agent = context.agent
    updates = params.updates
    strategy = params.merge_strategy || :merge
    validate? = params.validate != false
    transform_fn = params.transform
    
    # Apply transformation if provided
    with {:ok, final_updates} <- apply_transform(transform_fn, agent.state, updates) do
      # Apply updates based on strategy
      new_state = apply_updates(agent.state, final_updates, strategy)
      
      # Validate if required
      if validate? && function_exported?(agent.module, :validate_state, 1) do
        case agent.module.validate_state(new_state) do
          :ok ->
            updated_agent = %{agent | state: new_state}
            {:ok, %{updated_fields: Map.keys(final_updates)}, %{agent: updated_agent}}
            
          {:error, reason} ->
            {:error, {:validation_failed, reason}}
        end
      else
        updated_agent = %{agent | state: new_state}
        {:ok, %{updated_fields: Map.keys(final_updates)}, %{agent: updated_agent}}
      end
    end
  end
  
  # Private functions
  
  defp apply_transform(nil, _state, updates), do: {:ok, updates}
  defp apply_transform(transform_fn, state, updates) do
    case transform_fn.(state, updates) do
      {:ok, transformed} -> {:ok, transformed}
      {:error, reason} -> {:error, {:transform_failed, reason}}
      transformed -> {:ok, transformed}
    end
  end
  
  defp apply_updates(state, updates, :merge) do
    Map.merge(state, updates)
  end
  
  defp apply_updates(state, updates, :deep_merge) do
    deep_merge(state, updates)
  end
  
  defp apply_updates(_state, updates, :replace) do
    updates
  end
  
  defp deep_merge(map1, map2) when is_map(map1) and is_map(map2) do
    Map.merge(map1, map2, fn _key, v1, v2 ->
      if is_map(v1) and is_map(v2) do
        deep_merge(v1, v2)
      else
        v2
      end
    end)
  end
  
  defp deep_merge(_map1, map2), do: map2
end