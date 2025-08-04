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
  alias RubberDuck.Agents.{ErrorHandling, ActionErrorPatterns}
  
  require Logger

  @impl true
  def run(params, context) do
    ErrorHandling.safe_execute(fn ->
      # Validate required parameters and context
      with :ok <- validate_context(context),
           :ok <- validate_feature_param(params.feature) do
        
        agent = context.agent
        
        # Safely convert feature to atom
        feature_result = safe_feature_conversion(params.feature)
        
        case feature_result do
          {:ok, feature_atom} ->
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
                
              {:error, reason} ->
                ErrorHandling.system_error("Failed to emit feature check signal: #{inspect(reason)}", %{reason: reason})
              error ->
                ErrorHandling.categorize_error(error)
            end
            
          error -> error
        end
      end
    end)
  end
  
  defp validate_context(%{agent: %{state: %{provider_module: module}}}) when not is_nil(module), do: :ok
  defp validate_context(_), do: ErrorHandling.validation_error("Invalid context: missing agent with provider_module", %{})
  
  defp validate_feature_param(feature) when is_binary(feature) and byte_size(feature) > 0, do: :ok
  defp validate_feature_param(feature), do: ErrorHandling.validation_error("Feature must be a non-empty string", %{feature: feature})
  
  defp safe_feature_conversion(feature) do
    try do
      {:ok, String.to_atom(feature)}
    rescue
      ArgumentError ->
        ErrorHandling.validation_error("Invalid feature name: #{feature}", %{feature: feature})
    end
  end

  # Private functions

  defp check_provider_feature(provider_module, feature) do
    try do
      if function_exported?(provider_module, :supports_feature?, 1) do
        provider_module.supports_feature?(feature)
      else
        Logger.warning("Provider module #{provider_module} does not export supports_feature?/1")
        false
      end
    rescue
      error ->
        Logger.error("Error checking provider feature: #{inspect(error)}")
        false
    end
  end
end