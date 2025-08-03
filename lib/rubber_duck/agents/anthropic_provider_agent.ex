defmodule RubberDuck.Agents.AnthropicProviderAgent do
  @moduledoc """
  Anthropic-specific provider agent handling Claude model requests.
  
  This agent manages:
  - Anthropic API rate limits
  - Claude model capabilities
  - Large context window handling
  - Vision support for Claude 3
  - Safety features
  
  ## Signals
  
  Inherits all signals from ProviderAgent plus:
  - `configure_safety`: Configure safety settings
  - `vision_request`: Handle image analysis requests
  """
  
  use RubberDuck.Agents.ProviderAgent,
    name: "anthropic_provider",
    description: "Anthropic Claude models provider agent",
    actions: [
      RubberDuck.Jido.Actions.Provider.Anthropic.ConfigureSafetyAction,
      RubberDuck.Jido.Actions.Provider.Anthropic.VisionRequestAction
    ]
  
  alias RubberDuck.LLM.Providers.Anthropic
  alias RubberDuck.LLM.{ProviderConfig, ConfigLoader}
  
  @impl true
  def mount(_params, initial_state) do
    # Load Anthropic configuration
    config = build_anthropic_config()
    
    # Set Anthropic-specific defaults
    state = initial_state
    |> Map.put(:provider_module, Anthropic)
    |> Map.put(:provider_config, config)
    |> Map.put(:capabilities, [
      :chat, :code, :analysis, :vision, :large_context,
      :streaming, :system_messages, :safety_features
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
    |> Map.put(:safety_config, %{
      block_flagged_content: true,
      content_filtering: :moderate,
      allowed_topics: :all
    })
    
    {:ok, state}
  end
  
  # Anthropic-specific provider request handling with safety filtering
  @impl true
  def on_before_run(agent) do
    # This could be used for pre-run validation if needed
    {:ok, agent}
  end
  
  # Private functions
  
  defp build_anthropic_config do
    # Load from configuration
    base_config = %ProviderConfig{
      name: :anthropic,
      adapter: Anthropic,
      api_key: System.get_env("ANTHROPIC_API_KEY"),
      base_url: System.get_env("ANTHROPIC_BASE_URL") || "https://api.anthropic.com",
      models: [
        "claude-3-opus-20240229",
        "claude-3-sonnet-20240229",
        "claude-3-haiku-20240307",
        "claude-2.1",
        "claude-2.0",
        "claude-instant-1.2"
      ],
      priority: 2,
      rate_limit: parse_rate_limit(System.get_env("ANTHROPIC_RATE_LIMIT")),
      max_retries: 3,
      timeout: 120_000,  # 2 minutes
      headers: %{
        "anthropic-version" => "2023-06-01"
      },
      options: []
    }
    
    # Apply any runtime overrides
    ConfigLoader.load_provider_config(:anthropic)
    |> case do
      nil -> base_config
      config -> struct(ProviderConfig, config)
    end
  end
  
  defp get_rate_limit(%ProviderConfig{rate_limit: {limit, :minute}}), do: limit
  defp get_rate_limit(%ProviderConfig{rate_limit: {limit, :hour}}), do: div(limit, 60)
  defp get_rate_limit(_), do: 50  # Default: 50 requests per minute
  
  defp parse_rate_limit(nil), do: {50, :minute}  # Default tier
  defp parse_rate_limit(str) do
    case String.split(str, "/") do
      [limit, "min"] -> {String.to_integer(limit), :minute}
      [limit, "hour"] -> {String.to_integer(limit), :hour}
      _ -> {50, :minute}
    end
  end
  
  
  # Functions removed after Action migration - safety is now handled by ConfigureSafetyAction
  
  
  # Note: Anthropic-specific handling would be done via configuration and signal processing
  
  # Build status report with Anthropic-specific info
  def build_status_report(agent) do
    base_report = RubberDuck.Agents.ProviderAgent.build_status_report(agent)
    
    Map.merge(base_report, %{
      "models" => agent.state.provider_config.models,
      "safety_config" => agent.state.safety_config,
      "supports_vision" => true,
      "max_context_tokens" => 200_000,  # Claude 3
      "tier_info" => %{
        "rate_limit" => agent.state.rate_limiter.limit,
        "rate_window" => "1 minute"
      }
    })
  end
end