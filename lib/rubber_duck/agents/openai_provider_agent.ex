defmodule RubberDuck.Agents.OpenAIProviderAgent do
  @moduledoc """
  OpenAI-specific provider agent handling GPT model requests.
  
  This agent manages:
  - OpenAI API rate limits
  - Model-specific capabilities
  - Function calling support
  - Streaming responses
  - Token usage tracking
  
  ## Signals
  
  Inherits all signals from ProviderAgent plus:
  - `configure_functions`: Configure function calling
  - `stream_request`: Handle streaming completion
  """
  
  use RubberDuck.Agents.ProviderAgent,
    name: "openai_provider",
    description: "OpenAI GPT models provider agent",
    actions: [
      RubberDuck.Jido.Actions.Provider.OpenAI.ConfigureFunctionsAction,
      RubberDuck.Jido.Actions.Provider.OpenAI.StreamRequestAction
    ]
  
  alias RubberDuck.LLM.Providers.OpenAI
  alias RubberDuck.LLM.{ProviderConfig, ConfigLoader}
  
  @impl true
  def mount(_params, initial_state) do
    # Load OpenAI configuration
    config = build_openai_config()
    
    # Set OpenAI-specific defaults
    state = initial_state
    |> Map.put(:provider_module, OpenAI)
    |> Map.put(:provider_config, config)
    |> Map.put(:capabilities, [
      :chat, :code, :analysis, :function_calling, 
      :streaming, :json_mode, :system_messages
    ])
    |> Map.update(:rate_limiter, %{}, fn limiter ->
      %{limiter |
        limit: get_rate_limit(config),
        window: 60_000  # 1 minute window
      }
    end)
    |> Map.update(:circuit_breaker, %{}, fn breaker ->
      %{breaker |
        failure_threshold: 5,
        timeout: 30_000  # 30 seconds
      }
    end)
    
    {:ok, state}
  end
  
  
  # Private functions
  
  defp build_openai_config do
    # Load from configuration
    base_config = %ProviderConfig{
      name: :openai,
      adapter: OpenAI,
      api_key: System.get_env("OPENAI_API_KEY"),
      base_url: System.get_env("OPENAI_BASE_URL") || "https://api.openai.com/v1",
      models: [
        "gpt-4-turbo-preview",
        "gpt-4",
        "gpt-4-32k", 
        "gpt-3.5-turbo",
        "gpt-3.5-turbo-16k"
      ],
      priority: 1,
      rate_limit: parse_rate_limit(System.get_env("OPENAI_RATE_LIMIT")),
      max_retries: 3,
      timeout: 120_000,  # 2 minutes for GPT-4
      headers: %{},
      options: []
    }
    
    # Apply any runtime overrides
    ConfigLoader.load_provider_config(:openai)
    |> case do
      nil -> base_config
      config -> struct(ProviderConfig, config)
    end
  end
  
  defp get_rate_limit(%ProviderConfig{rate_limit: {limit, :minute}}), do: limit
  defp get_rate_limit(%ProviderConfig{rate_limit: {limit, :hour}}), do: div(limit, 60)
  defp get_rate_limit(_), do: 60  # Default: 60 requests per minute
  
  defp parse_rate_limit(nil), do: {3000, :minute}  # Default tier
  defp parse_rate_limit(str) do
    case String.split(str, "/") do
      [limit, "min"] -> {String.to_integer(limit), :minute}
      [limit, "hour"] -> {String.to_integer(limit), :hour}
      _ -> {3000, :minute}
    end
  end
  
  
  # Build status report with OpenAI-specific info
  def build_status_report(agent) do
    base_report = RubberDuck.Agents.ProviderAgent.build_status_report(agent)
    
    Map.merge(base_report, %{
      "models" => agent.state.provider_config.models,
      "supports_functions" => Map.has_key?(agent.state, :functions),
      "function_count" => length(Map.get(agent.state, :functions, [])),
      "tier_info" => %{
        "rate_limit" => agent.state.rate_limiter.limit,
        "rate_window" => "1 minute"
      }
    })
  end
end