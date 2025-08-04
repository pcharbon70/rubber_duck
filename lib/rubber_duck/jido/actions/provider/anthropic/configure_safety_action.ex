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
  alias RubberDuck.Agents.ErrorHandling
  
  require Logger

  @impl true
  def run(params, context) do
    ErrorHandling.safe_execute(fn ->
      # Validate required context
      with :ok <- validate_context(context),
           :ok <- validate_safety_params(params) do
        
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
        
        with {:ok, _, %{agent: updated_agent}} <- UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}),
             {:ok, signal_result, _} <- emit_configuration_signal(updated_agent, updated_safety) do
          {:ok, %{
            safety_configured: true,
            provider: "anthropic",
            settings: updated_safety,
            signal_emitted: signal_result.signal_emitted
          }, %{agent: updated_agent}}
        else
          {:error, reason} -> 
            ErrorHandling.system_error("Failed to configure safety settings: #{inspect(reason)}", %{reason: reason})
          error -> 
            ErrorHandling.categorize_error(error)
        end
      end
    end)
  end
  
  defp validate_context(%{agent: %{state: state}}) when is_map(state), do: :ok
  defp validate_context(_), do: ErrorHandling.validation_error("Invalid context: missing agent state", %{})
  
  defp validate_safety_params(params) do
    case params.content_filtering do
      nil -> :ok
      level when level in [:strict, :moderate, :permissive] -> :ok
      invalid -> ErrorHandling.validation_error("Invalid content filtering level: #{invalid}", %{level: invalid})
    end
  end
  
  defp emit_configuration_signal(agent, updated_safety) do
    signal_params = %{
      signal_type: "provider.safety.configured",
      data: %{
        provider: "anthropic",
        settings: updated_safety,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
end