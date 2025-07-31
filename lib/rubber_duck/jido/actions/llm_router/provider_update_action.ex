defmodule RubberDuck.Jido.Actions.LLMRouter.ProviderUpdateAction do
  @moduledoc """
  Action for updating existing LLM provider configurations in the LLM Router Agent.
  
  This action handles provider configuration updates including validation,
  model capability updates, and signal emission for tracking changes.
  """
  
  use Jido.Action,
    name: "provider_update",
    description: "Updates an existing LLM provider configuration",
    schema: [
      name: [type: :string, required: true],
      updates: [type: :map, required: true]
    ]

  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    provider_name = String.to_atom(params.name)
    
    case agent.state.providers[provider_name] do
      nil ->
        with {:ok, _} <- emit_update_failed(agent, params.name, "Provider not found") do
          {:ok, %{
            "updated" => false,
            "provider" => params.name,
            "error" => "Provider not found"
          }, %{agent: agent}}
        end
      
      existing_config ->
        with {:ok, updated_config} <- apply_config_updates(existing_config, params.updates),
             {:ok, updated_agent} <- update_provider_config(agent, provider_name, updated_config),
             {:ok, _} <- emit_update_success(updated_agent, params.name) do
          {:ok, %{
            "updated" => true,
            "provider" => params.name,
            "status" => "updated"
          }, %{agent: updated_agent}}
        else
          {:error, reason} ->
            with {:ok, _} <- emit_update_failed(agent, params.name, inspect(reason)) do
              {:ok, %{
                "updated" => false,
                "provider" => params.name,
                "error" => inspect(reason)
              }, %{agent: agent}}
            end
        end
    end
  end

  # Private functions

  defp apply_config_updates(config, updates) do
    try do
      updated_config = Enum.reduce(updates, config, fn {key, value}, acc ->
        try do
          valid_key = String.to_existing_atom(key)
          Map.put(acc, valid_key, value)
        rescue
          ArgumentError -> acc  # Skip invalid keys
        end
      end)
      {:ok, updated_config}
    rescue
      e ->
        {:error, "Failed to apply updates: #{inspect(e)}"}
    end
  end

  defp update_provider_config(agent, provider_name, updated_config) do
    # Update model capabilities if models changed
    updated_capabilities = update_model_capabilities(
      agent.state.model_capabilities, 
      updated_config
    )
    
    state_updates = %{
      providers: Map.put(agent.state.providers, provider_name, updated_config),
      model_capabilities: updated_capabilities
    }
    
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end

  defp emit_update_success(agent, provider_name) do
    signal_params = %{
      signal_type: "llm.provider.updated",
      data: %{
        provider: provider_name,
        status: "updated",
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end

  defp emit_update_failed(agent, provider_name, error_message) do
    signal_params = %{
      signal_type: "llm.provider.update_failed",
      data: %{
        provider: provider_name,
        error: error_message,
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end

  defp update_model_capabilities(current_capabilities, provider_config) do
    # In production, would load actual model capabilities
    # For now, use simplified capabilities based on model names
    model_caps = Enum.reduce(provider_config.models, %{}, fn model, acc ->
      capabilities = case model do
        "gpt-4" -> %{
          max_context: 8192,
          capabilities: [:chat, :code, :analysis],
          cost_per_1k_tokens: 0.03
        }
        "gpt-3.5-turbo" -> %{
          max_context: 4096,
          capabilities: [:chat, :code],
          cost_per_1k_tokens: 0.002
        }
        "claude-3-sonnet" -> %{
          max_context: 200_000,
          capabilities: [:chat, :code, :analysis, :vision],
          cost_per_1k_tokens: 0.003
        }
        _ -> %{
          max_context: 4096,
          capabilities: [:chat],
          cost_per_1k_tokens: 0.001
        }
      end
      
      Map.put(acc, model, capabilities)
    end)
    
    Map.merge(current_capabilities, model_caps)
  end
end