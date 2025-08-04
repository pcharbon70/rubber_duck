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
  alias RubberDuck.Agents.ErrorHandling
  require Logger
  
  @impl true
  def mount(_params, initial_state) do
    ErrorHandling.safe_execute(fn ->
      Logger.info("Mounting Anthropic provider agent")
      
      # Load Anthropic configuration with error handling
      case safe_build_anthropic_config() do
        {:ok, config} ->
          # Set Anthropic-specific defaults with validation
          case build_provider_state(initial_state, config) do
            {:ok, state} -> 
              Logger.info("Anthropic provider agent mounted successfully with #{length(config.models)} models")
              state
            {:error, error} -> 
              ErrorHandling.categorize_error(error)
          end
        {:error, error} -> 
          ErrorHandling.categorize_error(error)
      end
    end)
  end
  
  defp safe_build_anthropic_config do
    try do
      config = build_anthropic_config()
      
      # Validate essential configuration
      case validate_anthropic_config(config) do
        :ok -> {:ok, config}
        error -> error
      end
    rescue
      error -> ErrorHandling.system_error("Failed to build Anthropic config: #{Exception.message(error)}", %{error: inspect(error)})
    end
  end
  
  defp validate_anthropic_config(%ProviderConfig{api_key: nil}) do
    ErrorHandling.validation_error("Missing ANTHROPIC_API_KEY environment variable", %{})
  end
  defp validate_anthropic_config(%ProviderConfig{models: models}) when length(models) == 0 do
    ErrorHandling.validation_error("No Anthropic models configured", %{})
  end
  defp validate_anthropic_config(_config), do: :ok
  
  defp build_provider_state(initial_state, config) do
    try do
      state = initial_state
      |> Map.put(:provider_module, Anthropic)
      |> Map.put(:provider_config, config)
      |> Map.put(:capabilities, [
        :chat, :code, :analysis, :vision, :large_context,
        :streaming, :system_messages, :safety_features
      ])
      |> Map.update(:rate_limiter, %{}, fn limiter ->
        %{limiter |
          limit: safe_get_rate_limit(config),
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
    rescue
      error -> ErrorHandling.system_error("Failed to build provider state: #{Exception.message(error)}", %{error: inspect(error)})
    end
  end
  
  # Anthropic-specific provider request handling with safety filtering
  @impl true
  def on_before_run(agent) do
    ErrorHandling.safe_execute(fn ->
      # Validate agent state before running actions
      case validate_agent_state(agent) do
        :ok -> 
          Logger.debug("Anthropic agent pre-run validation passed")
          agent
        error -> ErrorHandling.categorize_error(error)
      end
    end)
  end
  
  defp validate_agent_state(agent) do
    cond do
      not is_map(agent.state) ->
        ErrorHandling.validation_error("Invalid agent state", %{})
      is_nil(agent.state.provider_config) ->
        ErrorHandling.validation_error("Missing provider configuration", %{})
      is_nil(agent.state.provider_config.api_key) ->
        ErrorHandling.validation_error("Missing API key", %{})
      true -> :ok
    end
  end
  
  # Private functions
  
  defp build_anthropic_config do
    # Load from configuration with safe environment variable access
    api_key = System.get_env("ANTHROPIC_API_KEY")
    base_url = System.get_env("ANTHROPIC_BASE_URL") || "https://api.anthropic.com"
    rate_limit_env = System.get_env("ANTHROPIC_RATE_LIMIT")
    
    base_config = %ProviderConfig{
      name: :anthropic,
      adapter: Anthropic,
      api_key: api_key,
      base_url: base_url,
      models: [
        "claude-3-opus-20240229",
        "claude-3-sonnet-20240229",
        "claude-3-haiku-20240307",
        "claude-2.1",
        "claude-2.0",
        "claude-instant-1.2"
      ],
      priority: 2,
      rate_limit: safe_parse_rate_limit(rate_limit_env),
      max_retries: 3,
      timeout: 120_000,  # 2 minutes
      headers: %{
        "anthropic-version" => "2023-06-01"
      },
      options: []
    }
    
    # Apply any runtime overrides with error handling
    case safe_load_provider_config(:anthropic) do
      {:ok, nil} -> base_config
      {:ok, config} -> struct(ProviderConfig, config)
      {:error, _error} -> 
        Logger.warning("Failed to load provider config, using defaults")
        base_config
    end
  end
  
  defp safe_load_provider_config(provider) do
    try do
      {:ok, ConfigLoader.load_provider_config(provider)}
    rescue
      error -> {:error, Exception.message(error)}
    end
  end
  
  defp safe_get_rate_limit(%ProviderConfig{rate_limit: {limit, :minute}}) when is_integer(limit) and limit > 0, do: limit
  defp safe_get_rate_limit(%ProviderConfig{rate_limit: {limit, :hour}}) when is_integer(limit) and limit > 0, do: max(div(limit, 60), 1)
  defp safe_get_rate_limit(_), do: 50  # Default: 50 requests per minute
  
  defp safe_parse_rate_limit(nil), do: {50, :minute}  # Default tier
  defp safe_parse_rate_limit(str) when is_binary(str) do
    try do
      case String.split(str, "/") do
        [limit_str, "min"] -> 
          limit = String.to_integer(limit_str)
          if limit > 0, do: {limit, :minute}, else: {50, :minute}
        [limit_str, "hour"] -> 
          limit = String.to_integer(limit_str)
          if limit > 0, do: {limit, :hour}, else: {50, :minute}
        _ -> {50, :minute}
      end
    rescue
      ArgumentError -> {50, :minute}
      _ -> {50, :minute}
    end
  end
  defp safe_parse_rate_limit(_), do: {50, :minute}
  
  
  # Functions removed after Action migration - safety is now handled by ConfigureSafetyAction
  
  
  # Note: Anthropic-specific handling would be done via configuration and signal processing
  
  # Build status report with Anthropic-specific info
  def build_status_report(agent) do
    case RubberDuck.Agents.ProviderAgent.build_status_report(agent) do
      {:ok, base_report} ->
        ErrorHandling.safe_execute(fn ->
          anthropic_info = %{
            "models" => safe_get_models(agent.state),
            "safety_config" => Map.get(agent.state, :safety_config, %{}),
            "supports_vision" => true,
            "max_context_tokens" => 200_000,  # Claude 3
            "tier_info" => %{
              "rate_limit" => safe_get_rate_limit_info(agent.state),
              "rate_window" => "1 minute"
            }
          }
          
          Map.merge(base_report, anthropic_info)
        end)
      {:error, error} -> ErrorHandling.categorize_error(error)
    end
  end
  
  defp safe_get_models(%{provider_config: %{models: models}}) when is_list(models), do: models
  defp safe_get_models(_), do: []
  
  defp safe_get_rate_limit_info(%{rate_limiter: %{limit: limit}}) when is_integer(limit), do: limit
  defp safe_get_rate_limit_info(_), do: 50
end