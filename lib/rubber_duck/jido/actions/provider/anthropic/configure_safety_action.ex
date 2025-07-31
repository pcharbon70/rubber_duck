defmodule RubberDuck.Jido.Actions.Provider.Anthropic.ConfigureSafetyAction do
  @moduledoc """
  Action for configuring Anthropic safety settings.
  
  This action updates the safety configuration for Anthropic provider agent,
  controlling content filtering and safety features.
  """
  
  use Jido.Action,
    name: "configure_safety",
    description: "Configures Anthropic safety filtering settings",
    schema: [
      block_flagged_content: [type: :boolean, default: nil],
      content_filtering: [type: :atom, values: [:strict, :moderate, :permissive], default: nil],
      allowed_topics: [type: :atom, default: nil]
    ]

  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    # Build safety settings update (only include non-nil values)
    safety_updates = params
    |> Map.take([:block_flagged_content, :content_filtering, :allowed_topics])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
    
    # Update safety configuration
    current_safety = agent.state.safety_config || %{}
    updated_safety = Map.merge(current_safety, safety_updates)
    
    state_updates = %{safety_config: updated_safety}
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} ->
        # Emit configuration success signal
        signal_params = %{
          signal_type: "provider.safety.configured",
          data: %{
            provider: "anthropic",
            settings: updated_safety,
            timestamp: DateTime.utc_now()
          }
        }
        
        case EmitSignalAction.run(signal_params, %{agent: updated_agent}) do
          {:ok, signal_result, _} ->
            {:ok, %{
              safety_configured: true,
              provider: "anthropic",
              settings: updated_safety,
              signal_emitted: signal_result.signal_emitted
            }, %{agent: updated_agent}}
            
          error -> error
        end
        
      error -> error
    end
  end
end