defmodule RubberDuck.LLM.Providers.TGI do
  @moduledoc """
  Text Generation Inference (TGI) provider for high-performance LLM inference.

  TGI is Hugging Face's production-ready inference server that supports:
  - OpenAI-compatible chat completions API
  - Native TGI generate/generate_stream endpoints
  - Function calling and guided generation
  - Flash Attention and Paged Attention optimizations
  - Streaming responses
  - Any compatible HuggingFace model

  ## Configuration

      config :rubber_duck, :llm,
        providers: [
          %{
            name: :tgi,
            adapter: RubberDuck.LLM.Providers.TGI,
            base_url: "http://localhost:8080",
            models: ["llama-3.1-8b", "mistral-7b", "codellama-13b"],
            timeout: 120_000,
            options: [
              supports_function_calling: true,
              supports_guided_generation: true
            ]
          }
        ]

  ## Endpoints

  - **Chat Completions**: `/v1/chat/completions` (OpenAI-compatible)
  - **Generate**: `/generate` (TGI-native)
  - **Generate Stream**: `/generate_stream` (TGI-native streaming)
  - **Health**: `/health` (server health)
  - **Info**: `/info` (model information)
  """

  @behaviour RubberDuck.LLM.Provider

  alias RubberDuck.LLM.{Request, Response, ProviderConfig, Provider}

  @default_base_url "http://localhost:8080"
  @default_timeout 120_000
  @stream_timeout 300_000

  @impl true
  def execute(%Request{} = request, %ProviderConfig{} = config) do
    endpoint = determine_endpoint(request)
    url = build_url(config, endpoint)
    body = build_request_body(request, config, endpoint)
    headers = build_headers(config)

    case Req.post(url, json: body, headers: headers, receive_timeout: config.timeout || @default_timeout) do
      {:ok, %{status: 200, body: response_body}} ->
        {:ok, parse_response(response_body, request, endpoint)}

      {:ok, response} ->
        Provider.handle_http_error({:ok, response})

      {:error, reason} ->
        {:error, {:connection_error, reason}}
    end
  end

  @impl true
  def validate_config(%ProviderConfig{} = config) do
    # TGI doesn't require API keys for self-hosted deployments
    if config.base_url do
      :ok
    else
      {:error, "base_url is required for TGI provider"}
    end
  end

  @impl true
  def info do
    %{
      name: "Text Generation Inference",
      description: "High-performance inference server for Hugging Face models",
      supported_models: [
        "llama-3.1-8b",
        "llama-3.1-70b",
        "llama-2-7b",
        "llama-2-13b",
        "llama-2-70b",
        "mistral-7b",
        "mistral-8x7b",
        "codellama-7b",
        "codellama-13b",
        "codellama-34b",
        "falcon-7b",
        "falcon-40b",
        "starcoder",
        "starcoder2",
        "bloom-7b",
        "gpt-neox-20b",
        "flan-t5-xxl"
      ],
      requires_api_key: false,
      supports_streaming: true,
      supports_function_calling: true,
      supports_vision: false,
      supports_system_messages: true,
      supports_json_mode: true,
      supports_guided_generation: true
    }
  end

  @impl true
  def supports_feature?(feature) do
    case feature do
      :streaming -> true
      :system_messages -> true
      :json_mode -> true
      :function_calling -> true
      :guided_generation -> true
      :vision -> false
      _ -> false
    end
  end

  @impl true
  def count_tokens(text, _model) do
    # TGI provides token counting via tokenize endpoint
    # For now, return simple estimation
    estimated_tokens =
      text
      |> String.split(~r/\s+/)
      |> length()
      |> Kernel.*(4 / 3)
      |> round()

    {:ok, estimated_tokens}
  end

  @impl true
  def health_check(%ProviderConfig{} = config) do
    url = build_url(config, "/health")

    case Req.get(url, receive_timeout: 5_000) do
      {:ok, %{status: 200}} ->
        # Try to get model info
        info_url = build_url(config, "/info")

        case Req.get(info_url, receive_timeout: 5_000) do
          {:ok, %{status: 200, body: info_body}} ->
            {:ok,
             %{
               status: :healthy,
               model: info_body["model_id"] || "unknown",
               message: "TGI server is healthy and serving model"
             }}

          _ ->
            {:ok,
             %{
               status: :healthy,
               model: "unknown",
               message: "TGI server is healthy"
             }}
        end

      {:ok, %{status: status}} ->
        {:error, {:unhealthy, "TGI server returned status #{status}"}}

      {:error, reason} ->
        {:error, {:connection_failed, reason}}
    end
  end

  @impl true
  def stream_completion(%Request{} = request, %ProviderConfig{} = config, callback) do
    endpoint = determine_stream_endpoint(request)
    url = build_url(config, endpoint)
    body = build_request_body(request, config, endpoint) |> enable_streaming()
    headers = build_headers(config)

    # Create a unique reference for this stream
    ref = make_ref()

    # Start streaming in a separate process
    Task.start_link(fn ->
      stream_response(url, body, headers, callback, ref, config, endpoint)
    end)

    {:ok, ref}
  end

  # Private functions

  defp determine_endpoint(%Request{messages: messages}) when is_list(messages) and length(messages) > 0 do
    # Use chat completions for message-based requests
    "/v1/chat/completions"
  end

  defp determine_endpoint(%Request{options: %{prompt: _}}) do
    # Use generate endpoint for simple prompt-based requests
    "/generate"
  end

  defp determine_endpoint(_) do
    # Default to chat completions
    "/v1/chat/completions"
  end

  defp determine_stream_endpoint(%Request{messages: messages}) when is_list(messages) and length(messages) > 0 do
    # Use streaming chat completions
    "/v1/chat/completions"
  end

  defp determine_stream_endpoint(_) do
    # Use generate_stream for prompt-based requests
    "/generate_stream"
  end

  defp build_url(%ProviderConfig{base_url: base_url}, endpoint) do
    base = base_url || @default_base_url
    base <> endpoint
  end

  defp build_headers(%ProviderConfig{api_key: api_key}) do
    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    if api_key do
      [{"Authorization", "Bearer #{api_key}"} | headers]
    else
      headers
    end
  end

  defp build_request_body(%Request{} = request, %ProviderConfig{} = _config, "/v1/chat/completions") do
    # Build OpenAI-compatible request
    base_body = %{
      "model" => request.model || "tgi",
      "messages" => format_messages(request.messages),
      "stream" => false
    }

    add_chat_options(base_body, request.options)
  end

  defp build_request_body(%Request{} = request, %ProviderConfig{} = _config, "/generate") do
    # Build TGI-native generate request
    prompt = get_in(request.options, [:prompt]) || messages_to_prompt(request.messages)

    base_body = %{
      "inputs" => prompt,
      "parameters" => %{}
    }

    add_generate_options(base_body, request.options)
  end

  defp build_request_body(%Request{} = request, %ProviderConfig{} = _config, "/generate_stream") do
    # Build TGI-native streaming generate request
    prompt = get_in(request.options, [:prompt]) || messages_to_prompt(request.messages)

    base_body = %{
      "inputs" => prompt,
      "parameters" => %{},
      "stream" => true
    }

    add_generate_options(base_body, request.options)
  end

  defp format_messages(messages) when is_list(messages) do
    Enum.map(messages, fn msg ->
      %{
        "role" => msg["role"] || msg[:role] || "user",
        "content" => msg["content"] || msg[:content] || ""
      }
    end)
  end

  defp format_messages(_), do: []

  defp messages_to_prompt(messages) when is_list(messages) do
    messages
    |> Enum.map(fn msg ->
      role = msg["role"] || msg[:role] || "user"
      content = msg["content"] || msg[:content] || ""
      "#{role}: #{content}"
    end)
    |> Enum.join("\n\n")
  end

  defp messages_to_prompt(_), do: ""

  defp add_chat_options(body, options) when is_map(options) do
    body
    |> maybe_add_option("max_tokens", options[:max_tokens])
    |> maybe_add_option("temperature", options[:temperature])
    |> maybe_add_option("top_p", options[:top_p])
    |> maybe_add_option("stop", options[:stop])
    |> maybe_add_option("frequency_penalty", options[:frequency_penalty])
    |> maybe_add_option("presence_penalty", options[:presence_penalty])
    |> maybe_add_tools(options[:tools])
    |> maybe_add_tool_choice(options[:tool_choice])
  end

  defp add_chat_options(body, _), do: body

  defp add_generate_options(body, options) when is_map(options) do
    parameters = body["parameters"]

    new_parameters =
      parameters
      |> maybe_add_param("max_new_tokens", options[:max_tokens])
      |> maybe_add_param("temperature", options[:temperature])
      |> maybe_add_param("top_p", options[:top_p])
      |> maybe_add_param("top_k", options[:top_k])
      |> maybe_add_param("repetition_penalty", options[:repetition_penalty])
      |> maybe_add_param("stop", options[:stop])

    Map.put(body, "parameters", new_parameters)
  end

  defp add_generate_options(body, _), do: body

  defp maybe_add_option(body, _key, nil), do: body
  defp maybe_add_option(body, key, value), do: Map.put(body, key, value)

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: Map.put(params, key, value)

  defp maybe_add_tools(body, nil), do: body

  defp maybe_add_tools(body, tools) when is_list(tools) do
    Map.put(body, "tools", tools)
  end

  defp maybe_add_tool_choice(body, nil), do: body

  defp maybe_add_tool_choice(body, tool_choice) do
    Map.put(body, "tool_choice", tool_choice)
  end

  defp enable_streaming(body) do
    Map.put(body, "stream", true)
  end

  defp parse_response(response_body, request, "/v1/chat/completions") do
    # Parse OpenAI-compatible response
    %Response{
      id: response_body["id"] || generate_id(),
      model: response_body["model"] || request.model,
      provider: :tgi,
      choices: parse_chat_choices(response_body["choices"]),
      usage: parse_chat_usage(response_body["usage"]),
      created_at: parse_timestamp(response_body["created"]) || DateTime.utc_now(),
      metadata: %{
        object: response_body["object"],
        system_fingerprint: response_body["system_fingerprint"]
      },
      cached: false
    }
  end

  defp parse_response(response_body, request, _endpoint) do
    # Parse TGI-native response
    %Response{
      id: generate_id(),
      model: request.model,
      provider: :tgi,
      choices: [
        %{
          index: 0,
          message: %{
            "role" => "assistant",
            "content" => response_body["generated_text"] || ""
          },
          finish_reason: parse_finish_reason(response_body["finish_reason"])
        }
      ],
      usage: parse_generate_usage(response_body["details"]),
      created_at: DateTime.utc_now(),
      metadata: %{
        details: response_body["details"]
      },
      cached: false
    }
  end

  defp parse_chat_choices(nil), do: []

  defp parse_chat_choices(choices) when is_list(choices) do
    Enum.map(choices, fn choice ->
      %{
        index: choice["index"],
        message: choice["message"],
        finish_reason: choice["finish_reason"]
      }
    end)
  end

  defp parse_chat_usage(nil), do: nil

  defp parse_chat_usage(usage) do
    %{
      prompt_tokens: usage["prompt_tokens"] || 0,
      completion_tokens: usage["completion_tokens"] || 0,
      total_tokens: usage["total_tokens"] || 0
    }
  end

  defp parse_generate_usage(nil), do: nil

  defp parse_generate_usage(details) do
    %{
      prompt_tokens: (details["prefill"] && length(details["prefill"])) || 0,
      completion_tokens: (details["tokens"] && length(details["tokens"])) || 0,
      total_tokens:
        ((details["prefill"] && length(details["prefill"])) || 0) +
          ((details["tokens"] && length(details["tokens"])) || 0)
    }
  end

  defp parse_finish_reason(nil), do: "stop"
  defp parse_finish_reason(reason), do: reason

  defp parse_timestamp(nil), do: nil

  defp parse_timestamp(unix_timestamp) when is_integer(unix_timestamp) do
    DateTime.from_unix!(unix_timestamp)
  end

  defp generate_id do
    ("tgi_" <> :crypto.strong_rand_bytes(8)) |> Base.encode16(case: :lower)
  end

  defp stream_response(url, body, headers, callback, ref, config, endpoint) do
    stream_opts = [
      json: body,
      headers: headers,
      receive_timeout: config.timeout || @stream_timeout,
      into: :self
    ]

    case Req.post(url, stream_opts) do
      {:ok, response} ->
        handle_stream_response(response, callback, ref, endpoint)

      {:error, reason} ->
        callback.({:error, reason, ref})
    end
  end

  defp handle_stream_response(%{status: 200} = response, callback, ref, endpoint) do
    receive do
      {:data, chunk} ->
        case parse_stream_chunk(chunk, endpoint) do
          {:ok, parsed_chunk} ->
            callback.({:chunk, parsed_chunk, ref})

            if parsed_chunk.done do
              callback.({:done, ref})
            else
              handle_stream_response(response, callback, ref, endpoint)
            end

          {:error, _} ->
            # Skip malformed chunks
            handle_stream_response(response, callback, ref, endpoint)
        end

      {:done, _} ->
        callback.({:done, ref})

      {:error, reason} ->
        callback.({:error, reason, ref})
    after
      @stream_timeout ->
        callback.({:error, :timeout, ref})
    end
  end

  defp handle_stream_response(response, callback, ref, _endpoint) do
    callback.({:error, {:http_error, response.status}, ref})
  end

  defp parse_stream_chunk(chunk, "/v1/chat/completions") do
    # Parse OpenAI-compatible streaming chunk
    lines = String.split(chunk, "\n")

    Enum.reduce_while(lines, {:ok, %{content: "", done: false}}, fn line, acc ->
      case String.trim(line) do
        "" ->
          {:cont, acc}

        "data: [DONE]" ->
          {:halt, {:ok, %{content: "", done: true}}}

        "data: " <> json_str ->
          case Jason.decode(json_str) do
            {:ok, parsed} ->
              content = get_in(parsed, ["choices", Access.at(0), "delta", "content"]) || ""
              {:cont, {:ok, %{content: content, done: false, metadata: parsed}}}

            {:error, _} ->
              {:cont, acc}
          end

        _ ->
          {:cont, acc}
      end
    end)
  end

  defp parse_stream_chunk(chunk, _endpoint) do
    # Parse TGI-native streaming chunk
    case Jason.decode(chunk) do
      {:ok, parsed} ->
        content = parsed["token"]["text"] || ""
        done = parsed["generated_text"] != nil

        {:ok,
         %{
           content: content,
           done: done,
           metadata: parsed
         }}

      {:error, _} ->
        {:error, :invalid_json}
    end
  end
end
