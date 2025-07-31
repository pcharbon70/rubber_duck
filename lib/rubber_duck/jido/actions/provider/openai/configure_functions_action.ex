defmodule RubberDuck.Jido.Actions.Provider.OpenAI.ConfigureFunctionsAction do
  @moduledoc """
  Action for configuring OpenAI function calling capabilities.
  
  This action stores function definitions in the agent state for use
  in subsequent OpenAI requests that support function calling.
  """
  
  use Jido.Action,
    name: "configure_functions",
    description: "Configures OpenAI function calling capabilities",
    schema: [
      functions: [type: :list, required: true]
    ]

  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    # Store functions in agent state
    state_updates = %{functions: params.functions}
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} ->
        # Emit configuration success signal
        signal_params = %{
          signal_type: "provider.functions.configured",
          data: %{
            provider: "openai",
            function_count: length(params.functions),
            timestamp: DateTime.utc_now()
          }
        }
        
        case EmitSignalAction.run(signal_params, %{agent: updated_agent}) do
          {:ok, signal_result, _} ->
            {:ok, %{
              functions_configured: true,
              provider: "openai",
              function_count: length(params.functions),
              signal_emitted: signal_result.signal_emitted
            }, %{agent: updated_agent}}
            
          error -> error
        end
        
      error -> error
    end
  end
end