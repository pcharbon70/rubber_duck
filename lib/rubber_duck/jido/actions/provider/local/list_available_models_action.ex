defmodule RubberDuck.Jido.Actions.Provider.Local.ListAvailableModelsAction do
  @moduledoc """
  Action for listing available models in local provider.
  
  This action queries the local provider (e.g., Ollama) for available
  models and returns the list along with currently loaded models.
  """
  
  use Jido.Action,
    name: "list_available_models",
    description: "Lists available models in local provider",
    schema: []

  alias RubberDuck.LLM.Providers.Ollama
  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  
  require Logger

  @impl true
  def run(_params, context) do
    agent = context.agent
    
    # Get available models from local provider
    models = list_local_models()
    
    # Emit models available signal
    signal_params = %{
      signal_type: "provider.models.available",
      data: %{
        models: models,
        loaded: Map.keys(agent.state.loaded_models),
        provider: "local",
        timestamp: DateTime.utc_now()
      }
    }
    
    case EmitSignalAction.run(signal_params, %{agent: agent}) do
      {:ok, signal_result, _} ->
        {:ok, %{
          models: models,
          loaded: Map.keys(agent.state.loaded_models),
          provider: "local",
          signal_emitted: signal_result.signal_emitted
        }, %{agent: agent}}
        
      error -> error
    end
  end

  # Private functions

  defp list_local_models do
    # Get available models from Ollama or local directory
    case Ollama.list_models() do
      {:ok, models} -> models
      {:error, _} -> []
    end
  end
end