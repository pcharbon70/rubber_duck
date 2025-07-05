defmodule RubberDuck.LLM.Providers.Anthropic do
  @moduledoc """
  Anthropic provider adapter for Claude models.
  
  Supports:
  - Claude 3 Opus, Sonnet, and Haiku
  - System prompts
  - Streaming responses
  - Vision capabilities (for supported models)
  """
  
  @behaviour RubberDuck.LLM.Provider
  
  alias RubberDuck.LLM.{Provider, Request, Response, ProviderConfig}
  
  require Logger
  
  @base_url "https://api.anthropic.com/v1"
  @messages_endpoint "/messages"
  @anthropic_version "2023-06-01"
  
  @impl true
  def execute(%Request{} = request, %ProviderConfig{} = config) do
    with {:ok, _} <- validate_config(config),
         {:ok, payload} <- build_payload(request),
         {:ok, response} <- make_request(payload, config),
         {:ok, parsed} <- parse_response(response, request) do
      {:ok, parsed}
    end
  end
  
  @impl true
  def validate_config(%ProviderConfig{} = config) do
    cond do
      is_nil(config.api_key) or config.api_key == "" ->
        {:error, :api_key_required}
        
      true ->
        :ok
    end
  end
  
  @impl true
  def info do
    %{
      name: "Anthropic",
      models: [
        %{
          id: "claude-3-opus",
          context_window: 200000,
          max_output: 4096,
          supports_vision: true
        },
        %{
          id: "claude-3-sonnet",
          context_window: 200000,
          max_output: 4096,
          supports_vision: true
        },
        %{
          id: "claude-3-haiku",
          context_window: 200000,
          max_output: 4096,
          supports_vision: true
        }
      ],
      features: [:streaming, :system_messages, :vision],
      pricing_url: "https://www.anthropic.com/pricing"
    }
  end
  
  @impl true
  def supports_feature?(feature) do
    feature in [:streaming, :system_messages, :vision]
  end
  
  @impl true
  def count_tokens(text, _model) when is_binary(text) do
    # Rough estimation for Claude
    # Anthropic uses a different tokenizer than OpenAI
    characters = String.length(text)
    tokens = characters / 4  # Rough average
    
    {:ok, round(tokens)}
  end
  
  def count_tokens(messages, model) when is_list(messages) do
    total = Enum.reduce(messages, 0, fn message, acc ->
      content = message["content"] || ""
      {:ok, tokens} = count_tokens(content, model)
      acc + tokens
    end)
    
    {:ok, total}
  end
  
  @impl true
  def health_check(%ProviderConfig{} = config) do
    # Anthropic doesn't have a dedicated health endpoint
    # We'll do a minimal messages request
    test_payload = %{
      "model" => "claude-3-haiku",
      "messages" => [%{"role" => "user", "content" => "Hi"}],
      "max_tokens" => 1
    }
    
    url = build_url(@messages_endpoint, config)
    headers = build_headers(config)
    
    case Req.post(url, json: test_payload, headers: headers, timeout: 5000) do
      {:ok, %{status: status}} when status in [200, 429] ->
        # 429 still means the API is reachable, just rate limited
        {:ok, %{status: :healthy, timestamp: DateTime.utc_now()}}
        
      {:ok, %{status: status}} ->
        {:error, {:unhealthy, status}}
        
      {:error, reason} ->
        {:error, {:unhealthy, reason}}
    end
  end
  
  # Private functions
  
  defp build_payload(%Request{} = request) do
    {system_message, user_messages} = extract_system_message(request.messages)
    
    base_payload = %{
      "model" => map_model_name(request.model),
      "messages" => format_messages(user_messages),
      "max_tokens" => request.options.max_tokens || 4096
    }
    
    payload = base_payload
    |> maybe_add_option("temperature", request.options.temperature)
    |> maybe_add_option("stream", request.options.stream)
    |> maybe_add_system(system_message)
    
    {:ok, payload}
  end
  
  defp extract_system_message(messages) do
    case messages do
      [%{"role" => "system", "content" => content} | rest] ->
        {content, rest}
        
      _ ->
        {nil, messages}
    end
  end
  
  defp format_messages(messages) do
    messages
    |> Enum.filter(fn msg -> msg["role"] != "system" end)
    |> Enum.map(fn message ->
      %{
        "role" => normalize_role(message["role"] || message[:role]),
        "content" => format_content(message["content"] || message[:content])
      }
    end)
  end
  
  defp normalize_role("user"), do: "user"
  defp normalize_role("assistant"), do: "assistant"
  defp normalize_role("system"), do: "user"  # Anthropic doesn't have system role in messages
  defp normalize_role(_), do: "user"
  
  defp format_content(content) when is_binary(content) do
    content
  end
  
  defp format_content(content) when is_list(content) do
    # Handle multimodal content (text + images)
    Enum.map(content, fn
      %{"type" => "text", "text" => text} ->
        %{"type" => "text", "text" => text}
        
      %{"type" => "image", "source" => source} ->
        %{
          "type" => "image",
          "source" => %{
            "type" => source["type"] || "base64",
            "media_type" => source["media_type"] || "image/jpeg",
            "data" => source["data"]
          }
        }
        
      other ->
        other
    end)
  end
  
  defp format_content(content), do: to_string(content)
  
  defp maybe_add_option(payload, _key, nil), do: payload
  defp maybe_add_option(payload, key, value) do
    Map.put(payload, to_string(key), value)
  end
  
  defp maybe_add_system(payload, nil), do: payload
  defp maybe_add_system(payload, system_content) do
    Map.put(payload, "system", system_content)
  end
  
  defp map_model_name(model) do
    # Handle any model name mappings if needed
    model
  end
  
  defp build_headers(config) do
    base_headers = Provider.build_headers(config)
    
    # Anthropic uses a different auth header format
    headers = base_headers
    |> Map.delete("authorization")
    |> Map.put("x-api-key", config.api_key)
    |> Map.put("anthropic-version", @anthropic_version)
    
    headers
  end
  
  defp make_request(payload, config) do
    url = build_url(@messages_endpoint, config)
    headers = build_headers(config)
    
    Logger.debug("Anthropic request to #{url}")
    
    start_time = System.monotonic_time(:millisecond)
    
    result = Req.post(url,
      json: payload,
      headers: headers,
      timeout: config.timeout,
      retry: false
    )
    
    latency = System.monotonic_time(:millisecond) - start_time
    Logger.debug("Anthropic response received in #{latency}ms")
    
    case result do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}
        
      other ->
        Provider.handle_http_error(other)
    end
  end
  
  defp build_url(endpoint, config) do
    base = config.base_url || @base_url
    base <> endpoint
  end
  
  defp parse_response(response_body, request) do
    case Jason.decode(response_body) do
      {:ok, decoded} ->
        response = Response.from_provider(:anthropic, decoded)
        {:ok, response}
        
      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end
end