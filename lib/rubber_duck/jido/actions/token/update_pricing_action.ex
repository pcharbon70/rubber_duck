defmodule RubberDuck.Jido.Actions.Token.UpdatePricingAction do
  @moduledoc """
  Action for updating pricing models for different LLM providers and models.
  
  This action handles updates to the pricing configuration used for
  cost calculations across different providers and models.
  """
  
  use Jido.Action,
    name: "update_pricing",
    description: "Updates pricing models for LLM providers",
    schema: [
      provider: [type: :string, required: true],
      model: [type: :string, required: true],
      pricing: [type: :map, required: true]
    ]

  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    with {:ok, validated_pricing} <- validate_pricing(params.pricing),
         {:ok, updated_agent} <- update_pricing_models(agent, params, validated_pricing),
         {:ok, _} <- emit_pricing_update_signal(updated_agent, params) do
      {:ok, %{"updated" => true}, %{agent: updated_agent}}
    end
  end

  # Private functions

  defp validate_pricing(pricing) do
    required_fields = ["prompt", "completion"]
    missing_fields = required_fields -- Map.keys(pricing)
    
    if missing_fields != [] do
      {:error, "Missing required pricing fields: #{Enum.join(missing_fields, ", ")}"}
    else
      validated = %{
        prompt: pricing["prompt"],
        completion: pricing["completion"],
        unit: pricing["unit"] || 1000
      }
      {:ok, validated}
    end
  end

  defp update_pricing_models(agent, params, validated_pricing) do
    # Build the update path for nested pricing models
    pricing_path = [params.provider, params.model]
    
    # Update the pricing models in state
    updated_pricing_models = put_in(
      agent.state.pricing_models,
      pricing_path,
      validated_pricing
    )
    
    state_updates = %{
      pricing_models: updated_pricing_models
    }
    
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end

  defp emit_pricing_update_signal(agent, params) do
    signal_params = %{
      signal_type: "token.pricing.updated",
      data: %{
        provider: params.provider,
        model: params.model,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end