defmodule RubberDuck.Jido.Actions.Provider.FeatureCheckAction do
  @moduledoc """
  Action for checking if a provider supports a specific feature.
  
  This action queries the provider module to determine if it supports
  a requested feature and emits appropriate response signals.
  """
  
  use Jido.Action,
    name: "feature_check",
    description: "Checks if a provider supports a specific feature",
    schema: [
      feature: [type: :string, required: true]
    ]

  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    feature_atom = String.to_atom(params.feature)
    
    # Check if provider supports the feature
    supported = check_provider_feature(agent.state.provider_module, feature_atom)
    
    # Emit response signal
    signal_params = %{
      signal_type: "provider.feature.check_response",
      data: %{
        feature: params.feature,
        supported: supported,
        provider: agent.name,
        timestamp: DateTime.utc_now()
      }
    }
    
    case EmitSignalAction.run(signal_params, %{agent: agent}) do
      {:ok, signal_result, _} ->
        {:ok, %{
          feature: params.feature,
          supported: supported,
          provider: agent.name,
          signal_emitted: signal_result.signal_emitted
        }, %{agent: agent}}
        
      error -> error
    end
  end

  # Private functions

  defp check_provider_feature(provider_module, feature) do
    if function_exported?(provider_module, :supports_feature?, 1) do
      provider_module.supports_feature?(feature)
    else
      false
    end
  end
end