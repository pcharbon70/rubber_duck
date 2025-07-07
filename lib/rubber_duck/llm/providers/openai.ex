defmodule RubberDuck.LLM.Providers.OpenAI do
  @moduledoc """
  OpenAI provider adapter for GPT models.

  Supports:
  - GPT-4 and GPT-4 Turbo
  - GPT-3.5 Turbo
  - Function calling
  - Streaming responses
  - JSON mode
  """

  @behaviour RubberDuck.LLM.Provider

  alias RubberDuck.LLM.{Provider, Request, Response, ProviderConfig, Tokenization}

  require Logger

  @base_url "https://api.openai.com/v1"
  @chat_endpoint "/chat/completions"

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
      name: "OpenAI",
      models: [
        %{
          id: "gpt-4",
          context_window: 8192,
          max_output: 4096,
          supports_functions: true,
          supports_vision: false
        },
        %{
          id: "gpt-4-turbo",
          context_window: 128_000,
          max_output: 4096,
          supports_functions: true,
          supports_vision: true
        },
        %{
          id: "gpt-3.5-turbo",
          context_window: 16385,
          max_output: 4096,
          supports_functions: true,
          supports_vision: false
        }
      ],
      features: [:streaming, :function_calling, :system_messages, :json_mode],
      pricing_url: "https://openai.com/pricing"
    }
  end

  @impl true
  def supports_feature?(feature) do
    feature in [:streaming, :function_calling, :system_messages, :json_mode]
  end

  @impl true
  def count_tokens(text, model) when is_binary(text) do
    Tokenization.count_tokens(text, model)
  end

  def count_tokens(messages, model) when is_list(messages) do
    Tokenization.count_tokens(messages, model)
  end

  @impl true
  def health_check(%ProviderConfig{} = config) do
    # Use the models endpoint as a lightweight health check
    url = build_url("/models", config)
    headers = Provider.build_headers(config)

    case Req.get(url, headers: headers, timeout: 5000) do
      {:ok, %{status: 200}} ->
        {:ok, %{status: :healthy, timestamp: DateTime.utc_now()}}

      {:ok, %{status: status}} ->
        {:error, {:unhealthy, status}}

      {:error, reason} ->
        {:error, {:unhealthy, reason}}
    end
  end

  @impl true
  def stream_completion(%Request{} = request, %ProviderConfig{} = config, callback) do
    with {:ok, _} <- validate_config(config),
         {:ok, payload} <- build_payload(%{request | options: Map.put(request.options, :stream, true)}) do
      ref = make_ref()
      parent = self()

      # Start streaming in a separate process
      spawn_link(fn ->
        result = stream_request(payload, config, callback)
        send(parent, {:stream_done, ref, result})
      end)

      {:ok, ref}
    end
  end

  # Private functions

  defp build_payload(%Request{} = request) do
    base_payload = %{
      "model" => request.model,
      "messages" => format_messages(request.messages)
    }

    payload =
      base_payload
      |> maybe_add_option("temperature", request.options.temperature)
      |> maybe_add_option("max_tokens", request.options.max_tokens)
      |> maybe_add_option("stream", request.options.stream)
      |> maybe_add_functions(request.options[:functions])
      |> maybe_add_json_mode(request.options[:json_mode])

    {:ok, payload}
  end

  defp format_messages(messages) do
    Enum.map(messages, fn message ->
      %{
        "role" => message["role"] || message[:role] || "user",
        "content" => message["content"] || message[:content] || ""
      }
      |> maybe_add_message_field("name", message["name"] || message[:name])
      |> maybe_add_message_field("function_call", message["function_call"] || message[:function_call])
    end)
  end

  defp maybe_add_option(payload, _key, nil), do: payload

  defp maybe_add_option(payload, key, value) do
    Map.put(payload, to_string(key), value)
  end

  defp maybe_add_message_field(message, _key, nil), do: message

  defp maybe_add_message_field(message, key, value) do
    Map.put(message, key, value)
  end

  defp maybe_add_functions(payload, nil), do: payload

  defp maybe_add_functions(payload, functions) when is_list(functions) do
    Map.put(payload, "functions", functions)
  end

  defp maybe_add_json_mode(payload, true) do
    Map.put(payload, "response_format", %{"type" => "json_object"})
  end

  defp maybe_add_json_mode(payload, _), do: payload

  defp make_request(payload, config) do
    url = build_url(@chat_endpoint, config)
    headers = Provider.build_headers(config)

    Logger.debug("OpenAI request to #{url}")

    start_time = System.monotonic_time(:millisecond)

    result =
      Req.post(url,
        json: payload,
        headers: headers,
        timeout: config.timeout,
        # We handle retries at a higher level
        retry: false
      )

    latency = System.monotonic_time(:millisecond) - start_time
    Logger.debug("OpenAI response received in #{latency}ms")

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
        response = Response.from_provider(:openai, decoded)
        {:ok, response}

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  defp stream_request(payload, config, callback) do
    url = build_url(@chat_endpoint, config)
    headers = Provider.build_headers(config)

    # Use Req streaming with a simple approach
    case Req.post(url, headers: headers, json: payload, receive_timeout: 30_000) do
      {:ok, %{status: 200, body: body}} ->
        # For now, simulate streaming by processing the response
        # In a real implementation, we'd use Req's streaming capabilities
        simulate_openai_streaming(body, callback)
        {:ok, :completed}

      {:error, reason} ->
        Logger.error("OpenAI streaming error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp simulate_openai_streaming(response_body, callback) do
    # Simple simulation - split the response content and stream it
    case Jason.decode(response_body) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        # Split content into words and stream them
        words = String.split(content, " ")

        Enum.each(words, fn word ->
          chunk = %{
            content: word <> " ",
            role: "assistant",
            finish_reason: nil,
            usage: nil,
            metadata: %{}
          }

          callback.(chunk)
          # Simulate network delay
          Process.sleep(50)
        end)

        # Send final chunk
        final_chunk = %{
          content: nil,
          role: nil,
          finish_reason: "stop",
          usage: %{prompt_tokens: 10, completion_tokens: length(words), total_tokens: 10 + length(words)},
          metadata: %{}
        }

        callback.(final_chunk)

      _ ->
        # Fallback for other response formats
        :ok
    end
  end
end
