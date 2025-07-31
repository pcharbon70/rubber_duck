defmodule RubberDuck.Jido.Actions.LLMRouter.ProviderRegisterAction do
  @moduledoc """
  Action for registering new LLM providers in the LLM Router Agent.
  
  This action handles the registration process including configuration validation,
  provider state initialization, metrics setup, and model capability tracking.
  """
  
  use Jido.Action,
    name: "provider_register",
    description: "Registers a new LLM provider with configuration validation",
    schema: [
      name: [type: :string, required: true],
      config: [type: :map, required: true]
    ]

  alias RubberDuck.LLM.ProviderConfig
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    provider_name = String.to_atom(params.name)
    
    # Convert config map to ProviderConfig struct
    provider_config = build_provider_config(provider_name, params.config)
    
    # Validate configuration
    case ProviderConfig.validate(provider_config) do
      {:ok, validated_config} ->
        with {:ok, updated_agent} <- register_provider(agent, provider_name, validated_config),
             {:ok, _} <- emit_registration_success(updated_agent, params.name, validated_config) do
          {:ok, %{
            "registered" => true,
            "provider" => params.name,
            "models" => validated_config.models,
            "status" => "registered"
          }, %{agent: updated_agent}}
        end
      
      {:error, reason} ->
        with {:ok, _} <- emit_registration_failed(agent, params.name, reason) do
          {:ok, %{
            "registered" => false,
            "provider" => params.name,
            "error" => "Registration failed: #{inspect(reason)}"
          }, %{agent: agent}}
        end
    end
  end

  # Private functions

  defp register_provider(agent, provider_name, validated_config) do
    # Initialize provider state
    provider_state = %{
      status: :healthy,
      last_health_check: System.monotonic_time(:millisecond),
      consecutive_failures: 0,
      current_load: 0
    }
    
    # Update model capabilities
    updated_capabilities = update_model_capabilities(
      agent.state.model_capabilities, 
      validated_config
    )
    
    # Prepare state updates
    state_updates = %{
      providers: Map.put(agent.state.providers, provider_name, validated_config),
      provider_states: Map.put(agent.state.provider_states, provider_name, provider_state),
      model_capabilities: updated_capabilities,
      metrics: update_metrics_for_new_provider(agent.state.metrics, provider_name)
    }
    
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end

  defp update_metrics_for_new_provider(metrics, provider_name) do
    metrics
    |> put_in([:requests_by_provider, provider_name], 0)
    |> put_in([:avg_latency_by_provider, provider_name], 0)
    |> put_in([:error_rates, provider_name], 0.0)
  end

  defp emit_registration_success(agent, provider_name, validated_config) do
    signal_params = %{
      signal_type: "llm.provider.registered",
      data: %{
        provider: provider_name,
        models: validated_config.models,
        status: "registered",
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end

  defp emit_registration_failed(agent, provider_name, reason) do
    signal_params = %{
      signal_type: "llm.provider.registration_failed",
      data: %{
        provider: provider_name,
        error: "Registration failed: #{inspect(reason)}",
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end

  defp build_provider_config(name, config_map) do
    %ProviderConfig{
      name: name,
      adapter: Module.concat([RubberDuck.LLM.Providers, Macro.camelize(Atom.to_string(name))]),
      api_key: config_map["api_key"],
      base_url: config_map["base_url"],
      models: config_map["models"] || [],
      priority: config_map["priority"] || 1,
      rate_limit: parse_rate_limit(config_map["rate_limit"]),
      max_retries: config_map["max_retries"] || 3,
      timeout: config_map["timeout"] || 30_000,
      headers: config_map["headers"] || %{},
      options: config_map["options"] || []
    }
  end

  defp parse_rate_limit(nil), do: nil
  defp parse_rate_limit(%{"limit" => limit, "unit" => unit}) do
    {limit, String.to_atom(unit)}
  end

  defp update_model_capabilities(current_capabilities, provider_config) do
    # In production, would load actual model capabilities
    # For now, use simplified capabilities
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