defmodule RubberDuck.Jido.Actions.Provider.Local.UnloadModelAction do
  @moduledoc """
  Action for unloading a model from local provider memory.
  
  This action unloads the specified model from the local provider
  (e.g., Ollama) and updates agent state to reflect the change.
  """
  
  use Jido.Action,
    name: "unload_model",
    description: "Unloads a model from local provider memory",
    schema: [
      model: [type: :string, required: true]
    ]

  alias RubberDuck.LLM.Providers.Ollama
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    # Check if model is currently loaded
    if Map.has_key?(agent.state.loaded_models, params.model) do
      # Remove from loaded models immediately
      loaded_models = Map.delete(agent.state.loaded_models, params.model)
      state_updates = %{loaded_models: loaded_models}
      
      case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
        {:ok, _, %{agent: updated_agent}} ->
          # Start async model unloading
          Task.start(fn ->
            unload_model_async(updated_agent.id, params.model)
          end)
          
          {:ok, %{
            model_unloading: true,
            model: params.model,
            status: "unloading_started"
          }, %{agent: updated_agent}}
          
        error -> error
      end
    else
      # Model not loaded
      signal_params = %{
        signal_type: "provider.model.unloaded",
        data: %{
          model: params.model,
          status: "not_loaded",
          provider: "local",
          timestamp: DateTime.utc_now()
        }
      }
      
      case EmitSignalAction.run(signal_params, %{agent: agent}) do
        {:ok, signal_result, _} ->
          {:ok, %{
            model_unloaded: true,
            model: params.model,
            status: "not_loaded",
            signal_emitted: signal_result.signal_emitted
          }, %{agent: agent}}
          
        error -> error
      end
    end
  end

  # Private functions

  defp unload_model_async(agent_id, model_name) do
    # Unload model through Ollama provider
    case Ollama.unload_model(model_name) do
      :ok ->
        # Emit success signal
        signal_params = %{
          signal_type: "provider.model.unloaded",
          data: %{
            model: model_name,
            status: "success",
            provider: "local",
            timestamp: DateTime.utc_now()
          }
        }
        EmitSignalAction.run(signal_params, %{agent: %{id: agent_id}})
        
      {:error, reason} ->
        # Emit failure signal
        signal_params = %{
          signal_type: "provider.model.unload_failed",
          data: %{
            model: model_name,
            error: inspect(reason),
            provider: "local",
            timestamp: DateTime.utc_now()
          }
        }
        EmitSignalAction.run(signal_params, %{agent: %{id: agent_id}})
    end
  end
end