defmodule RubberDuck.LLM.Providers.Ollama do
  @moduledoc """
  Ollama provider for local LLM execution.

  Supports running open-source models like Llama 2, Mistral, CodeLlama, etc.
  locally without API keys or external dependencies.

  ## Configuration

      config :rubber_duck, :llm,
        providers: [
          %{
            name: :ollama,
            adapter: RubberDuck.LLM.Providers.Ollama,
            base_url: "http://localhost:11434",
            models: ["llama2", "mistral", "codellama"],
            timeout: 60_000
          }
        ]
  """

  @behaviour RubberDuck.LLM.Provider

  alias RubberDuck.LLM.{Request, Response, ProviderConfig, Provider}

  @default_base_url "http://localhost:11434"
  @default_timeout 60_000
  # 5 minutes for streaming
  @stream_timeout 300_000

  @impl true
  def execute(%Request{} = request, %ProviderConfig{} = config) do
    endpoint = determine_endpoint(request)
    url = build_url(config, endpoint)
    body = build_request_body(request, config)
    headers = Provider.build_headers(config)

    # Use request timeout if available, otherwise use config timeout
    timeout = get_in(request.options, [:timeout]) || config.timeout || @default_timeout

    require Logger
    Logger.debug("Ollama request - URL: #{url}")
    Logger.debug("Ollama request - Body: #{inspect(body)}")
    Logger.debug("Ollama request - Timeout: #{timeout}ms")

    req_opts = [
      json: body,
      headers: headers,
      receive_timeout: timeout,
      # Also set connect_timeout and pool_timeout
      connect_options: [timeout: timeout],
      pool_timeout: timeout,
      # Let our retry logic handle it
      retry: false
    ]

    Logger.debug("Ollama making HTTP request...")
    start_time = System.monotonic_time(:millisecond)

    result =
      case Req.post(url, req_opts) do
        {:ok, %{status: 200, body: response_body}} ->
          end_time = System.monotonic_time(:millisecond)
          Logger.debug("Ollama request successful in #{end_time - start_time}ms")
          Logger.debug("Ollama response body: #{inspect(response_body)}")
          {:ok, parse_response(response_body, request)}

        {:ok, response} ->
          end_time = System.monotonic_time(:millisecond)
          Logger.debug("Ollama request failed with status #{response.status} in #{end_time - start_time}ms")
          Provider.handle_http_error({:ok, response})

        {:error, reason} ->
          end_time = System.monotonic_time(:millisecond)
          Logger.error("Ollama request error in #{end_time - start_time}ms: #{inspect(reason)}")
          {:error, {:connection_error, reason}}
      end

    result
  end

  @impl true
  def validate_config(%ProviderConfig{} = config) do
    # Ollama doesn't require API keys
    if config.base_url do
      :ok
    else
      {:error, "base_url is required for Ollama provider"}
    end
  end

  @impl true
  def info do
    %{
      name: "Ollama",
      description: "Local LLM provider for open-source models",
      supported_models: [
        "llama2",
        "llama2:7b",
        "llama2:13b",
        "llama2:70b",
        "mistral",
        "mistral:7b",
        "codellama",
        "codellama:7b",
        "codellama:13b",
        "mixtral",
        "mixtral:8x7b",
        "phi",
        "phi:2.7b",
        "neural-chat",
        "starling-lm",
        "zephyr"
      ],
      requires_api_key: false,
      supports_streaming: true,
      supports_function_calling: false,
      supports_vision: false,
      supports_system_messages: true,
      supports_json_mode: true
    }
  end

  @impl true
  def supports_feature?(feature) do
    case feature do
      :streaming -> true
      :system_messages -> true
      :json_mode -> true
      :function_calling -> false
      :vision -> false
      _ -> false
    end
  end

  @impl true
  def count_tokens(_text, _model) do
    # Ollama doesn't provide token counting directly
    # Return an error to indicate it's not supported
    {:error, :not_supported}
  end

  # This is the old single-argument health_check for backward compatibility
  @impl true
  def health_check(%ProviderConfig{} = config) do
    url = build_url(config, "/api/tags")

    case Req.get(url, receive_timeout: 5_000) do
      {:ok, %{status: 200, body: %{"models" => models}}} ->
        model_names = Enum.map(models, & &1["name"])

        {:ok,
         %{
           status: :healthy,
           models: model_names,
           message: "Ollama is running with #{length(model_names)} models available"
         }}

      {:ok, %{status: status}} ->
        {:error, {:unhealthy, "Ollama returned status #{status}"}}

      {:error, reason} ->
        {:error, {:connection_failed, reason}}
    end
  end

  @impl true
  def stream_completion(%Request{} = request, %ProviderConfig{} = config, callback) do
    endpoint = determine_endpoint(request)
    url = build_url(config, endpoint)
    body = build_request_body(request, config) |> Map.put("stream", true)
    headers = Provider.build_headers(config)

    # Create a unique reference for this stream
    ref = make_ref()

    # Start streaming in a separate process
    Task.start_link(fn ->
      stream_response(url, body, headers, callback, ref, config)
    end)

    {:ok, ref}
  end

  @impl true
  def connect(%ProviderConfig{} = config) do
    # Ollama uses HTTP, so we'll validate the connection by checking the API
    url = build_url(config, "/api/version")

    case Req.get(url, receive_timeout: 5000) do
      {:ok, %{status: 200, body: response_body}} ->
        connection_data = %{
          base_url: config.base_url || @default_base_url,
          version: response_body["version"] || "unknown",
          connected_at: DateTime.utc_now()
        }

        {:ok, connection_data}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, %Mint.TransportError{reason: :econnrefused}} ->
        {:error, {:connection_refused, "Ollama service not running at #{config.base_url || @default_base_url}"}}

      {:error, reason} ->
        {:error, {:connection_error, reason}}
    end
  end

  @impl true
  def disconnect(_config, _connection_data) do
    # Ollama doesn't maintain persistent connections
    :ok
  end

  @impl true
  def health_check(%ProviderConfig{} = config, connection_data) do
    # Handle both stateless and stateful connections
    base_url =
      case connection_data do
        :stateless -> config.base_url || @default_base_url
        data when is_map(data) -> data[:base_url] || config.base_url || @default_base_url
        _ -> config.base_url || @default_base_url
      end

    url = "#{base_url}/api/tags"

    case Req.get(url, receive_timeout: 5_000) do
      {:ok, %{status: 200, body: %{"models" => models}}} ->
        model_names = Enum.map(models, & &1["name"])

        version =
          case connection_data do
            :stateless -> "unknown"
            data when is_map(data) -> data[:version] || "unknown"
            _ -> "unknown"
          end

        {:ok,
         %{
           status: :healthy,
           models: model_names,
           version: version,
           message: "Ollama is running with #{length(model_names)} models available"
         }}

      {:ok, %{status: status}} ->
        {:error, {:unhealthy, "Ollama returned status #{status}"}}

      {:error, reason} ->
        {:error, {:connection_failed, reason}}
    end
  end

  # Private functions

  defp determine_endpoint(%Request{messages: messages}) when is_list(messages) and length(messages) > 0 do
    # Use chat endpoint for message-based requests
    "/api/chat"
  end

  defp determine_endpoint(%Request{options: %{prompt: _}}) do
    # Use generate endpoint for simple prompt-based requests
    "/api/generate"
  end

  defp determine_endpoint(_) do
    # Default to chat endpoint
    "/api/chat"
  end

  defp build_url(%ProviderConfig{base_url: base_url}, endpoint) do
    base = base_url || @default_base_url
    base <> endpoint
  end

  defp build_request_body(%Request{} = request, %ProviderConfig{} = _config) do
    base_body = %{
      "model" => request.model,
      "stream" => false
    }

    # Add appropriate fields based on endpoint
    body =
      case determine_endpoint(request) do
        "/api/chat" ->
          base_body
          |> Map.put("messages", format_messages(request.messages))

        "/api/generate" ->
          prompt = get_in(request.options, [:prompt]) || messages_to_prompt(request.messages)

          base_body
          |> Map.put("prompt", prompt)
      end

    # Add options if present
    if request.options do
      add_options(body, request.options)
    else
      body
    end
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

  defp add_options(body, options) do
    ollama_options = %{}

    # Map common options to Ollama format
    ollama_options =
      if options[:temperature] do
        Map.put(ollama_options, "temperature", options[:temperature])
      else
        ollama_options
      end

    ollama_options =
      if options[:max_tokens] do
        Map.put(ollama_options, "num_predict", options[:max_tokens])
      else
        ollama_options
      end

    ollama_options =
      if options[:top_p] do
        Map.put(ollama_options, "top_p", options[:top_p])
      else
        ollama_options
      end

    ollama_options =
      if options[:stop] do
        Map.put(ollama_options, "stop", options[:stop])
      else
        ollama_options
      end

    # Add system message if present
    body =
      if options[:system] do
        Map.put(body, "system", options[:system])
      else
        body
      end

    # Add format if JSON mode is requested
    body =
      if options[:json_mode] || options[:format] == "json" do
        Map.put(body, "format", "json")
      else
        body
      end

    # Only add options if there are any
    if map_size(ollama_options) > 0 do
      Map.put(body, "options", ollama_options)
    else
      body
    end
  end

  defp parse_response(response_body, request) do
    # Generate a unique ID for this response
    id = ("ollama_" <> :crypto.strong_rand_bytes(8)) |> Base.encode16(case: :lower)

    # Build response based on endpoint type
    content =
      case determine_endpoint(request) do
        "/api/chat" ->
          response_body["message"]["content"]

        "/api/generate" ->
          response_body["response"]
      end

    %Response{
      id: id,
      model: response_body["model"],
      provider: :ollama,
      choices: [
        %{
          index: 0,
          message: %{
            "role" => "assistant",
            "content" => content
          },
          finish_reason: if(response_body["done"], do: "stop", else: "length")
        }
      ],
      usage: parse_usage(response_body),
      created_at: DateTime.utc_now(),
      metadata: %{
        total_duration: response_body["total_duration"],
        load_duration: response_body["load_duration"],
        prompt_eval_duration: response_body["prompt_eval_duration"],
        eval_duration: response_body["eval_duration"],
        done: response_body["done"]
      },
      cached: false
    }
  end

  defp parse_usage(response_body) do
    # Ollama provides token counts differently
    prompt_tokens = response_body["prompt_eval_count"] || 0
    completion_tokens = response_body["eval_count"] || 0

    %{
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: prompt_tokens + completion_tokens
    }
  end

  defp stream_response(url, body, headers, callback, ref, config) do
    # Use Req to handle streaming
    stream_opts = [
      json: body,
      headers: headers,
      receive_timeout: config.timeout || @stream_timeout,
      into: :self
    ]

    case Req.post(url, stream_opts) do
      {:ok, response} ->
        handle_stream_response(response, callback, ref)

      {:error, reason} ->
        callback.({:error, reason, ref})
    end
  end

  defp handle_stream_response(%{status: 200} = response, callback, ref) do
    # Process the streaming response
    receive do
      {:data, chunk} ->
        # Parse the chunk and send to callback
        case Jason.decode(chunk) do
          {:ok, parsed} ->
            callback.({:chunk, format_stream_chunk(parsed), ref})

            if parsed["done"] do
              callback.({:done, ref})
            else
              handle_stream_response(response, callback, ref)
            end

          {:error, _} ->
            # Skip malformed chunks
            handle_stream_response(response, callback, ref)
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

  defp handle_stream_response(response, callback, ref) do
    callback.({:error, {:http_error, response.status}, ref})
  end

  defp format_stream_chunk(chunk) do
    content =
      case chunk do
        %{"message" => %{"content" => content}} -> content
        %{"response" => response} -> response
        _ -> ""
      end

    %{
      content: content,
      done: chunk["done"] || false,
      metadata: chunk
    }
  end
end
