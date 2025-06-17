defmodule RubberDuck.LLMAbstraction.Providers.LocalProvider do
  @moduledoc """
  Local/OpenAI-compatible provider implementation for the LLM abstraction layer.
  
  This provider implements the Provider behavior for local LLM servers that
  provide OpenAI-compatible APIs, such as llama.cpp, Ollama, LocalAI, etc.
  """

  @behaviour RubberDuck.LLMAbstraction.Provider
  
  require Logger
  
  alias RubberDuck.LLMAbstraction.{
    Config,
    HTTPClient,
    Message,
    Response,
    Capability
  }

  defstruct [:config, :http_client, :statistics, :health_status, :server_info]

  @type state :: %__MODULE__{
    config: Config.t(),
    http_client: module(),
    statistics: map(),
    health_status: :healthy | :degraded | :unhealthy,
    server_info: map()
  }

  @default_temperature 0.7
  @default_max_tokens 1000
  @default_model "local-model"

  # Provider Behavior Implementation

  @impl true
  def init(config) when is_map(config) do
    with {:ok, validated_config} <- validate_and_normalize_config(config),
         :ok <- Config.validate(validated_config) do
      
      state = %__MODULE__{
        config: validated_config,
        http_client: HTTPClient,
        statistics: initialize_statistics(),
        health_status: :healthy,
        server_info: %{}
      }
      
      # Try to detect server capabilities
      updated_state = detect_server_capabilities(state)
      
      Logger.info("Local provider initialized with base URL: #{validated_config.base_url}")
      {:ok, updated_state}
    else
      {:error, reason} ->
        Logger.error("Failed to initialize Local provider: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def chat(messages, %__MODULE__{} = state, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    
    case build_chat_request(messages, state, opts) do
      {:ok, request_body} ->
        url = Config.get_endpoint_url(state.config, :chat)
        headers = Config.get_headers(state.config)
        
        case HTTPClient.post(url, request_body, headers: headers, timeout: state.config.timeout) do
          {:ok, http_response} ->
            process_chat_response(http_response, state, start_time)
          
          {:error, reason} ->
            new_state = update_statistics(state, :chat, :error, start_time)
            {:error, {:http_error, reason}, new_state}
        end
      
      {:error, reason} ->
        new_state = update_statistics(state, :chat, :error, start_time)
        {:error, reason, new_state}
    end
  end

  @impl true
  def complete(prompt, %__MODULE__{} = state, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    
    # Try completions endpoint first, fallback to chat
    case has_completions_endpoint?(state) do
      true ->
        case build_completion_request(prompt, state, opts) do
          {:ok, request_body} ->
            url = Config.get_endpoint_url(state.config, :completions)
            headers = Config.get_headers(state.config)
            
            case HTTPClient.post(url, request_body, headers: headers, timeout: state.config.timeout) do
              {:ok, http_response} ->
                process_completion_response(http_response, state, start_time)
              
              {:error, reason} ->
                # Fallback to chat if completions endpoint fails
                Logger.debug("Completions endpoint failed, falling back to chat: #{inspect(reason)}")
                fallback_to_chat(prompt, state, opts, start_time)
            end
          
          {:error, reason} ->
            new_state = update_statistics(state, :completion, :error, start_time)
            {:error, reason, new_state}
        end
      
      false ->
        # Use chat endpoint
        fallback_to_chat(prompt, state, opts, start_time)
    end
  end

  @impl true
  def embed(input, %__MODULE__{} = state, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    
    case has_embeddings_endpoint?(state) do
      true ->
        case build_embedding_request(input, state, opts) do
          {:ok, request_body} ->
            url = Config.get_endpoint_url(state.config, :embeddings)
            headers = Config.get_headers(state.config)
            
            case HTTPClient.post(url, request_body, headers: headers, timeout: state.config.timeout) do
              {:ok, http_response} ->
                process_embedding_response(http_response, state, start_time)
              
              {:error, reason} ->
                new_state = update_statistics(state, :embedding, :error, start_time)
                {:error, {:http_error, reason}, new_state}
            end
          
          {:error, reason} ->
            new_state = update_statistics(state, :embedding, :error, start_time)
            {:error, reason, new_state}
        end
      
      false ->
        {:error, :not_supported, state}
    end
  end

  @impl true
  def stream_chat(messages, %__MODULE__{} = state, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    
    case build_chat_request(messages, state, Keyword.put(opts, :stream, true)) do
      {:ok, request_body} ->
        url = Config.get_endpoint_url(state.config, :chat)
        headers = Config.get_headers(state.config)
        
        case HTTPClient.stream_request(url, method: :post, headers: headers, body: request_body) do
          {:ok, stream} ->
            processed_stream = stream
            |> HTTPClient.parse_sse_stream()
            |> Stream.map(&parse_streaming_chunk/1)
            |> Stream.filter(&(&1 != nil))
            
            new_state = update_statistics(state, :stream_chat, :success, start_time)
            {:ok, processed_stream, new_state}
          
          {:error, reason} ->
            new_state = update_statistics(state, :stream_chat, :error, start_time)
            {:error, {:stream_error, reason}, new_state}
        end
      
      {:error, reason} ->
        new_state = update_statistics(state, :stream_chat, :error, start_time)
        {:error, reason, new_state}
    end
  end

  @impl true
  def capabilities(%__MODULE__{config: config, server_info: server_info}) do
    base_capabilities = [
      Capability.chat_completion([
        constraints: [
          max_tokens: Map.get(server_info, :max_tokens, 4096),
          max_context_window: Map.get(server_info, :context_window, 4096),
          supported_models: config.supported_models
        ]
      ]),
      Capability.text_completion([
        constraints: [
          max_tokens: Map.get(server_info, :max_tokens, 4096),
          supported_models: config.supported_models
        ]
      ])
    ]

    # Add streaming if supported
    base_capabilities = if Map.get(server_info, :supports_streaming, true) do
      streaming_cap = Capability.streaming([
        constraints: [supported_models: config.supported_models]
      ])
      [streaming_cap | base_capabilities]
    else
      base_capabilities
    end

    # Add embeddings if supported
    if Map.get(server_info, :supports_embeddings, false) do
      embedding_cap = Capability.embeddings([
        constraints: [supported_models: config.supported_models]
      ])
      [embedding_cap | base_capabilities]
    else
      base_capabilities
    end
  end

  @impl true
  def health_check(%__MODULE__{} = state) do
    case perform_health_check(state) do
      :ok -> :healthy
      {:degraded, _reason} -> :degraded
      {:unhealthy, _reason} -> :unhealthy
    end
  end

  @impl true
  def terminate(%__MODULE__{}) do
    Logger.info("Local provider terminated")
    :ok
  end

  @impl true
  def validate_config(config) when is_map(config) do
    case validate_and_normalize_config(config) do
      {:ok, validated_config} -> Config.validate(validated_config)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def metadata do
    %{
      provider: "Local",
      api_version: "custom",
      supported_features: [:chat, :completion, :streaming],
      description: "OpenAI-compatible local LLM server"
    }
  end

  # Request Building Functions

  defp build_chat_request(messages, state, opts) do
    with {:ok, formatted_messages} <- format_messages_for_local(messages),
         {:ok, model} <- get_model(state, opts) do
      
      request = %{
        model: model,
        messages: formatted_messages,
        temperature: Keyword.get(opts, :temperature, @default_temperature),
        max_tokens: Keyword.get(opts, :max_tokens, @default_max_tokens),
        stream: Keyword.get(opts, :stream, false)
      }
      
      # Add optional parameters that most local servers support
      request = maybe_add_stop_sequences(request, opts)
      request = maybe_add_top_p(request, opts)
      request = maybe_add_presence_penalty(request, opts)
      request = maybe_add_frequency_penalty(request, opts)
      
      {:ok, request}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_completion_request(prompt, state, opts) do
    with {:ok, model} <- get_model(state, opts) do
      request = %{
        model: model,
        prompt: prompt,
        temperature: Keyword.get(opts, :temperature, @default_temperature),
        max_tokens: Keyword.get(opts, :max_tokens, @default_max_tokens),
        stream: Keyword.get(opts, :stream, false)
      }
      
      # Add optional parameters
      request = maybe_add_stop_sequences(request, opts)
      request = maybe_add_top_p(request, opts)
      request = maybe_add_presence_penalty(request, opts)
      request = maybe_add_frequency_penalty(request, opts)
      
      {:ok, request}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_embedding_request(input, state, opts) do
    with {:ok, model} <- get_embedding_model(state, opts) do
      request = %{
        model: model,
        input: input
      }
      
      {:ok, request}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Response Processing Functions

  defp process_chat_response(http_response, state, start_time) do
    case HTTPClient.parse_json_response(http_response) do
      {:ok, response_data} ->
        case convert_local_chat_response(response_data) do
          {:ok, llm_response} ->
            new_state = update_statistics(state, :chat, :success, start_time)
            {:ok, llm_response, new_state}
          
          {:error, reason} ->
            new_state = update_statistics(state, :chat, :error, start_time)
            {:error, {:response_parse_error, reason}, new_state}
        end
      
      {:error, reason} ->
        new_state = update_statistics(state, :chat, :error, start_time)
        {:error, {:api_error, reason}, new_state}
    end
  end

  defp process_completion_response(http_response, state, start_time) do
    case HTTPClient.parse_json_response(http_response) do
      {:ok, response_data} ->
        case convert_local_completion_response(response_data) do
          {:ok, llm_response} ->
            new_state = update_statistics(state, :completion, :success, start_time)
            {:ok, llm_response, new_state}
          
          {:error, reason} ->
            new_state = update_statistics(state, :completion, :error, start_time)
            {:error, {:response_parse_error, reason}, new_state}
        end
      
      {:error, reason} ->
        new_state = update_statistics(state, :completion, :error, start_time)
        {:error, {:api_error, reason}, new_state}
    end
  end

  defp process_embedding_response(http_response, state, start_time) do
    case HTTPClient.parse_json_response(http_response) do
      {:ok, response_data} ->
        case extract_embeddings(response_data) do
          {:ok, embeddings} ->
            new_state = update_statistics(state, :embedding, :success, start_time)
            {:ok, embeddings, new_state}
          
          {:error, reason} ->
            new_state = update_statistics(state, :embedding, :error, start_time)
            {:error, {:response_parse_error, reason}, new_state}
        end
      
      {:error, reason} ->
        new_state = update_statistics(state, :embedding, :error, start_time)
        {:error, {:api_error, reason}, new_state}
    end
  end

  # Helper Functions

  defp validate_and_normalize_config(config) do
    case Config.validate(Config.local(Enum.to_list(config))) do
      :ok -> {:ok, Config.local(Enum.to_list(config))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp format_messages_for_local(messages) do
    try do
      # Use OpenAI format for local servers (most common)
      formatted = Enum.map(messages, fn message ->
        Message.to_provider_format(message, :openai)
      end)
      {:ok, formatted}
    rescue
      error -> {:error, {:message_format_error, error}}
    end
  end

  defp get_model(state, opts) do
    model = Keyword.get(opts, :model) || Config.get_model(state.config)
    
    if Config.supports_model?(state.config, model) do
      {:ok, model}
    else
      {:ok, model}  # Be permissive for local servers
    end
  end

  defp get_embedding_model(state, opts) do
    model = Keyword.get(opts, :model) || 
            List.first(state.config.supported_models) || 
            Config.get_model(state.config)
    {:ok, model}
  end

  defp convert_local_chat_response(response_data) do
    try do
      # Try OpenAI format first
      llm_response = Response.from_provider_format(response_data, :openai)
      {:ok, llm_response}
    rescue
      _ ->
        # Fallback to generic conversion
        try do
          llm_response = Response.from_provider_format(response_data, :generic)
          {:ok, llm_response}
        rescue
          error -> {:error, error}
        end
    end
  end

  defp convert_local_completion_response(response_data) do
    try do
      # Convert text completion format to standard response
      choices = Enum.map(response_data["choices"] || [], fn choice ->
        %{
          index: choice["index"] || 0,
          text: choice["text"],
          message: nil,
          finish_reason: parse_finish_reason(choice["finish_reason"]),
          logprobs: choice["logprobs"]
        }
      end)
      
      llm_response = Response.new([
        id: response_data["id"] || generate_id(),
        object: response_data["object"] || "text_completion",
        created: response_data["created"] || System.system_time(:second),
        model: response_data["model"] || "local-model",
        choices: choices,
        usage: response_data["usage"]
      ])
      
      {:ok, llm_response}
    rescue
      error -> {:error, error}
    end
  end

  defp extract_embeddings(response_data) do
    try do
      case response_data["data"] do
        nil -> {:error, :no_embeddings_data}
        data when is_list(data) ->
          embeddings = data
          |> Enum.sort_by(& &1["index"])
          |> Enum.map(& &1["embedding"])
          {:ok, embeddings}
        _ -> {:error, :invalid_embeddings_format}
      end
    rescue
      error -> {:error, error}
    end
  end

  defp parse_streaming_chunk(%{data: "[DONE]"}) do
    nil
  end

  defp parse_streaming_chunk(%{data: data}) do
    case Jason.decode(data) do
      {:ok, chunk} ->
        case chunk["choices"] do
          [choice | _] ->
            delta = choice["delta"]
            %{
              id: chunk["id"],
              model: chunk["model"],
              delta: delta,
              finish_reason: choice["finish_reason"]
            }
          
          _ -> nil
        end
      
      {:error, _} -> nil
    end
  end

  defp parse_streaming_chunk(_) do
    nil
  end

  defp fallback_to_chat(prompt, state, opts, start_time) do
    messages = [Message.user(prompt)]
    chat(messages, state, opts)
  end

  defp detect_server_capabilities(state) do
    # Try to detect what endpoints are available
    server_info = %{
      supports_chat: true,  # Assume chat is available
      supports_completions: check_endpoint_availability(state, :completions),
      supports_embeddings: check_endpoint_availability(state, :embeddings),
      supports_streaming: true,  # Most servers support streaming
      max_tokens: 4096,  # Default assumption
      context_window: 4096  # Default assumption
    }
    
    %{state | server_info: server_info}
  end

  defp check_endpoint_availability(state, endpoint) do
    try do
      url = Config.get_endpoint_url(state.config, endpoint)
      headers = Config.get_headers(state.config)
      
      # Try a simple HEAD request or OPTIONS to check if endpoint exists
      case HTTPClient.get(url, headers: headers, timeout: 5000) do
        {:ok, %{status: status}} when status < 500 -> true
        _ -> false
      end
    rescue
      _ -> false
    end
  end

  defp has_completions_endpoint?(state) do
    Map.get(state.server_info, :supports_completions, false)
  end

  defp has_embeddings_endpoint?(state) do
    Map.get(state.server_info, :supports_embeddings, false)
  end

  defp perform_health_check(state) do
    # Simple health check using a minimal API call
    test_messages = [Message.user("test")]
    
    case chat(test_messages, state, [model: Config.get_model(state.config), max_tokens: 1]) do
      {:ok, _response, _new_state} -> :ok
      {:error, {:http_error, _}, _} -> {:unhealthy, :network_error}
      {:error, {:client_error, 401, _}, _} -> {:unhealthy, :auth_error}
      {:error, {:client_error, 429, _}, _} -> {:degraded, :rate_limited}
      {:error, reason, _} -> {:degraded, reason}
    end
  end

  defp parse_finish_reason(nil), do: :stop
  defp parse_finish_reason("stop"), do: :stop
  defp parse_finish_reason("length"), do: :length
  defp parse_finish_reason("content_filter"), do: :content_filter
  defp parse_finish_reason(_), do: :stop

  defp generate_id do
    "local_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp initialize_statistics do
    %{
      total_requests: 0,
      successful_requests: 0,
      failed_requests: 0,
      average_response_time: 0.0,
      total_tokens_used: 0,
      by_operation: %{}
    }
  end

  defp update_statistics(state, operation, result, start_time) do
    end_time = System.monotonic_time(:millisecond)
    response_time = end_time - start_time
    
    new_stats = state.statistics
    |> Map.update!(:total_requests, &(&1 + 1))
    |> Map.update!(result == :success && :successful_requests || :failed_requests, &(&1 + 1))
    |> update_average_response_time(response_time)
    |> update_operation_stats(operation, result, response_time)
    
    %{state | statistics: new_stats}
  end

  defp update_average_response_time(stats, response_time) do
    total = stats.total_requests
    current_avg = stats.average_response_time
    new_avg = (current_avg * (total - 1) + response_time) / total
    
    Map.put(stats, :average_response_time, new_avg)
  end

  defp update_operation_stats(stats, operation, result, response_time) do
    operation_stats = Map.get(stats.by_operation, operation, %{
      total: 0,
      successful: 0,
      failed: 0,
      avg_response_time: 0.0
    })
    
    new_operation_stats = operation_stats
    |> Map.update!(:total, &(&1 + 1))
    |> Map.update!(result == :success && :successful || :failed, &(&1 + 1))
    |> update_operation_avg_time(response_time)
    
    Map.put(stats, :by_operation, Map.put(stats.by_operation, operation, new_operation_stats))
  end

  defp update_operation_avg_time(op_stats, response_time) do
    total = op_stats.total
    current_avg = op_stats.avg_response_time
    new_avg = (current_avg * (total - 1) + response_time) / total
    
    Map.put(op_stats, :avg_response_time, new_avg)
  end

  # Optional parameter helpers

  defp maybe_add_stop_sequences(request, opts) do
    case Keyword.get(opts, :stop) do
      nil -> request
      stop -> Map.put(request, :stop, stop)
    end
  end

  defp maybe_add_top_p(request, opts) do
    case Keyword.get(opts, :top_p) do
      nil -> request
      top_p -> Map.put(request, :top_p, top_p)
    end
  end

  defp maybe_add_presence_penalty(request, opts) do
    case Keyword.get(opts, :presence_penalty) do
      nil -> request
      penalty -> Map.put(request, :presence_penalty, penalty)
    end
  end

  defp maybe_add_frequency_penalty(request, opts) do
    case Keyword.get(opts, :frequency_penalty) do
      nil -> request
      penalty -> Map.put(request, :frequency_penalty, penalty)
    end
  end
end