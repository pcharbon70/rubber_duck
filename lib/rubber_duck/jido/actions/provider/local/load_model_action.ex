defmodule RubberDuck.Jido.Actions.Provider.Local.LoadModelAction do
  @moduledoc """
  Action for loading a model into local provider memory.
  
  This action checks resource availability and loads the specified
  model into the local provider (e.g., Ollama), updating agent state
  to track loaded models.
  """
  
  use Jido.Action,
    name: "load_model",
    description: "Loads a model into local provider memory",
    schema: [
      model: [type: :string, required: true]
    ]

  alias RubberDuck.LLM.Providers.Ollama
  alias RubberDuck.Jido.Actions.Base.EmitSignalAction
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    
    # Check if model is already loaded
    if Map.has_key?(agent.state.loaded_models, params.model) do
      # Model already loaded
      signal_params = %{
        signal_type: "provider.model.loaded",
        data: %{
          model: params.model,
          status: "already_loaded",
          provider: "local",
          timestamp: DateTime.utc_now()
        }
      }
      
      case EmitSignalAction.run(signal_params, %{agent: agent}) do
        {:ok, signal_result, _} ->
          {:ok, %{
            model_loaded: true,
            model: params.model,
            status: "already_loaded",
            signal_emitted: signal_result.signal_emitted
          }, %{agent: agent}}
          
        error -> error
      end
    else
      # Check resources before loading
      if has_sufficient_resources?(agent, params.model) do
        # Start async model loading
        Task.start(fn ->
          load_model_async(agent.id, params.model)
        end)
        
        {:ok, %{
          model_loading: true,
          model: params.model,
          status: "loading_started"
        }, %{agent: agent}}
      else
        # Insufficient resources
        signal_params = %{
          signal_type: "provider.model.load_failed",
          data: %{
            model: params.model,
            error: "Insufficient resources",
            provider: "local",
            timestamp: DateTime.utc_now()
          }
        }
        
        case EmitSignalAction.run(signal_params, %{agent: agent}) do
          {:ok, signal_result, _} ->
            {:ok, %{
              model_load_failed: true,
              model: params.model,
              error: "Insufficient resources",
              signal_emitted: signal_result.signal_emitted
            }, %{agent: agent}}
            
          error -> error
        end
      end
    end
  end

  # Private functions

  defp has_sufficient_resources?(_agent, model_name) do
    # Check if we have enough resources to load the model
    model_size = estimate_model_size(model_name)
    available_memory = get_available_memory_gb()
    
    # Need at least 2x model size in available memory
    available_memory > model_size * 2
  end

  defp load_model_async(agent_id, model_name) do
    start_time = System.monotonic_time(:millisecond)
    
    # Load model through Ollama provider
    case Ollama.load_model(model_name) do
      :ok ->
        load_time = System.monotonic_time(:millisecond) - start_time
        
        # Update agent state
        send(agent_id, {:model_loaded, model_name, load_time})
        
        # Emit success signal
        signal_params = %{
          signal_type: "provider.model.loaded",
          data: %{
            model: model_name,
            status: "success",
            load_time_ms: load_time,
            provider: "local",
            timestamp: DateTime.utc_now()
          }
        }
        EmitSignalAction.run(signal_params, %{agent: %{id: agent_id}})
        
      {:error, reason} ->
        # Emit failure signal
        signal_params = %{
          signal_type: "provider.model.load_failed",
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

  defp estimate_model_size(model_name) do
    # Rough estimates in GB
    cond do
      String.contains?(model_name, "70b") -> 40
      String.contains?(model_name, "34b") -> 20
      String.contains?(model_name, "13b") -> 8
      String.contains?(model_name, "7b") -> 4
      String.contains?(model_name, "3b") -> 2
      true -> 4  # Default 4GB
    end
  end

  defp get_available_memory_gb do
    # In production, would check actual available memory
    16  # Mock 16GB available
  end
end