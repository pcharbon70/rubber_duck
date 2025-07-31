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
    description: "Anthropic Claude models provider agent"
  
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
  
  @impl true
  def handle_signal(agent, %{"type" => "configure_safety"} = signal) do
    %{"data" => safety_settings} = signal
    
    # Update safety configuration
    agent = update_in(agent.state.safety_config, fn config ->
      Map.merge(config, atomize_keys(safety_settings))
    end)
    
    signal = Jido.Signal.new!(%{
      type: "provider.safety.configured",
      source: "agent:#{agent.id}",
      data: %{
        provider: "anthropic",
        settings: agent.state.safety_config,
        timestamp: DateTime.utc_now()
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "vision_request"} = signal) do
    %{
      "data" => %{
        "request_id" => request_id,
        "messages" => messages,
        "model" => model,
        "images" => images
      } = data
    } = signal
    
    # Validate model supports vision
    if model in ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku"] do
      # Process messages with images
      enhanced_messages = add_images_to_messages(messages, images)
      
      # Use regular request handling with enhanced messages
      super(agent, %{signal | 
        "data" => Map.put(data, "messages", enhanced_messages)
      })
    else
      signal = Jido.Signal.new!(%{
        type: "provider.error",
        source: "agent:#{agent.id}",
        data: %{
          request_id: request_id,
          error_type: "unsupported_feature",
          error: "Model #{model} does not support vision",
          provider: "anthropic",
          timestamp: DateTime.utc_now()
        }
      })
      emit_signal(agent, signal)
      {:ok, agent}
    end
  end
  
  def handle_signal(agent, %{"type" => "provider_request"} = signal) do
    # Add safety checks before processing
    %{"data" => %{"messages" => messages}} = signal
    
    if should_block_content?(messages, agent.state.safety_config) do
      %{"data" => %{"request_id" => request_id}} = signal
      signal = Jido.Signal.new!(%{
        type: "provider.error",
        source: "agent:#{agent.id}",
        data: %{
          request_id: request_id,
          error_type: "content_blocked",
          error: "Request blocked by safety filters",
          provider: "anthropic",
          timestamp: DateTime.utc_now()
        }
      })
      emit_signal(agent, signal)
      {:ok, agent}
    else
      super(agent, signal)
    end
  end
  
  # Delegate other signals to base implementation
  def handle_signal(agent, signal) do
    super(agent, signal)
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
  
  defp add_images_to_messages(messages, images) do
    # Convert images to Claude's expected format
    Enum.map(messages, fn message ->
      case message do
        %{"role" => "user", "content" => content} = msg ->
          # Add images to user messages
          if images && length(images) > 0 do
            image_content = Enum.map(images, fn image ->
              %{
                "type" => "image",
                "source" => %{
                  "type" => "base64",
                  "media_type" => image["media_type"] || "image/jpeg",
                  "data" => image["data"]
                }
              }
            end)
            
            # Combine text and image content
            %{msg | "content" => [
              %{"type" => "text", "text" => content}
              | image_content
            ]}
          else
            msg
          end
          
        other -> other
      end
    end)
  end
  
  defp should_block_content?(messages, safety_config) do
    if safety_config.block_flagged_content do
      # Simple content filtering
      blocked_terms = get_blocked_terms(safety_config.content_filtering)
      
      Enum.any?(messages, fn %{"content" => content} ->
        content_lower = String.downcase(content || "")
        Enum.any?(blocked_terms, &String.contains?(content_lower, &1))
      end)
    else
      false
    end
  end
  
  defp get_blocked_terms(:strict) do
    # Comprehensive list for strict filtering
    ["harmful", "illegal", "violence", "abuse", "explicit"]
  end
  
  defp get_blocked_terms(:moderate) do
    # Moderate filtering
    ["illegal", "extreme violence", "abuse"]
  end
  
  defp get_blocked_terms(_), do: []
  
  defp atomize_keys(map) do
    Map.new(map, fn {k, v} -> 
      {String.to_atom(k), v}
    end)
  end
  
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