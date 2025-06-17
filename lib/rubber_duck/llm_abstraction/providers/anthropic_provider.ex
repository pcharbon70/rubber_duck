defmodule RubberDuck.LLMAbstraction.Providers.AnthropicProvider do
  @moduledoc """
  Anthropic Claude provider implementation for the LLM abstraction layer.
  
  This provider implements the Provider behavior for Anthropic's Claude models,
  including chat completions and streaming support.
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

  defstruct [:config, :http_client, :statistics, :health_status]

  @type state :: %__MODULE__{
    config: Config.t(),
    http_client: module(),
    statistics: map(),
    health_status: :healthy | :degraded | :unhealthy
  }

  @default_temperature 0.7
  @default_max_tokens 1000
  @default_model "claude-3-sonnet-20240229"

  # Provider Behavior Implementation

  @impl true
  def init(config) when is_map(config) do
    with {:ok, validated_config} <- validate_and_normalize_config(config),
         :ok <- Config.validate(validated_config) do
      
      state = %__MODULE__{
        config: validated_config,
        http_client: HTTPClient,
        statistics: initialize_statistics(),
        health_status: :healthy
      }
      
      Logger.info("Anthropic provider initialized with base URL: #{validated_config.base_url}")
      {:ok, state}
    else
      {:error, reason} ->
        Logger.error("Failed to initialize Anthropic provider: #{inspect(reason)}")
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
    # Anthropic doesn't have separate completion endpoint, convert to chat
    messages = [Message.user(prompt)]
    chat(messages, state, opts)
  end

  @impl true
  def embed(_input, %__MODULE__{} = state, _opts \\ []) do
    # Anthropic doesn't provide embeddings API
    {:error, :not_supported, state}
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
  def capabilities(%__MODULE__{config: config}) do
    [
      Capability.chat_completion([
        constraints: [
          max_tokens: 4096,
          max_context_window: get_context_window(config.default_model),
          supported_models: config.supported_models
        ]
      ]),
      Capability.text_completion([
        constraints: [
          max_tokens: 4096,
          supported_models: config.supported_models
        ]
      ]),
      Capability.streaming([
        constraints: [
          supported_models: config.supported_models
        ]
      ])
    ]
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
    Logger.info("Anthropic provider terminated")
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
      provider: "Anthropic",
      api_version: "2023-06-01",
      supported_features: [:chat, :completion, :streaming],
      rate_limits: %{
        claude_3_opus: %{rpm: 1000, tpm: 80_000},
        claude_3_sonnet: %{rpm: 1000, tpm: 80_000},
        claude_3_haiku: %{rpm: 1000, tpm: 100_000}
      },
      pricing: %{
        claude_3_opus: %{input: 0.015, output: 0.075},
        claude_3_sonnet: %{input: 0.003, output: 0.015},
        claude_3_haiku: %{input: 0.00025, output: 0.00125}
      }
    }
  end

  # Request Building Functions

  defp build_chat_request(messages, state, opts) do
    with {:ok, formatted_messages} <- format_messages_for_anthropic(messages),
         {:ok, model} <- get_model(state, opts) do
      
      {system_message, conversation_messages} = extract_system_message(formatted_messages)
      
      request = %{
        model: model,
        messages: conversation_messages,
        max_tokens: Keyword.get(opts, :max_tokens, @default_max_tokens),
        stream: Keyword.get(opts, :stream, false)
      }
      
      # Add system message if present
      request = if system_message do
        Map.put(request, :system, system_message)
      else
        request
      end
      
      # Add optional parameters
      request = maybe_add_temperature(request, opts)
      request = maybe_add_top_p(request, opts)
      request = maybe_add_top_k(request, opts)
      request = maybe_add_stop_sequences(request, opts)
      
      {:ok, request}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Response Processing Functions

  defp process_chat_response(http_response, state, start_time) do
    case HTTPClient.parse_json_response(http_response) do
      {:ok, response_data} ->
        case convert_anthropic_chat_response(response_data) do
          {:ok, llm_response} ->
            new_state = update_statistics(state, :chat, :success, start_time)
            {:ok, llm_response, new_state}
          
          {:error, reason} ->
            new_state = update_statistics(state, :chat, :error, start_time)
            {:error, {:response_parse_error, reason}, new_state}
        end
      
      {:error, reason} ->
        new_state = update_statistics(state, :chat, :error, start_time)
        if HTTPClient.client_error?(http_response) do
          {:error, {:client_error, http_response.status, reason}, new_state}
        else
          {:error, {:server_error, http_response.status, reason}, new_state}
        end
    end
  end

  # Helper Functions

  defp validate_and_normalize_config(config) do
    case Config.validate(Config.anthropic(Enum.to_list(config))) do
      :ok -> {:ok, Config.anthropic(Enum.to_list(config))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp format_messages_for_anthropic(messages) do
    try do
      formatted = Enum.map(messages, fn message ->
        Message.to_provider_format(message, :anthropic)
      end)
      {:ok, formatted}
    rescue
      error -> {:error, {:message_format_error, error}}
    end
  end

  defp extract_system_message(messages) do
    case Enum.find(messages, &(&1["role"] == "system")) do
      nil ->
        {nil, messages}
      
      system_msg ->
        system_content = system_msg["content"]
        conversation_messages = Enum.reject(messages, &(&1["role"] == "system"))
        {system_content, conversation_messages}
    end
  end

  defp get_model(state, opts) do
    model = Keyword.get(opts, :model) || Config.get_model(state.config)
    
    if Config.supports_model?(state.config, model) do
      {:ok, model}
    else
      {:error, {:unsupported_model, model}}
    end
  end

  defp convert_anthropic_chat_response(response_data) do
    try do
      llm_response = Response.from_provider_format(response_data, :anthropic)
      {:ok, llm_response}
    rescue
      error -> {:error, error}
    end
  end

  defp parse_streaming_chunk(%{event: "message_start", data: data}) do
    case Jason.decode(data) do
      {:ok, chunk} ->
        %{
          type: :message_start,
          id: chunk["message"]["id"],
          model: chunk["message"]["model"],
          role: chunk["message"]["role"]
        }
      
      {:error, _} -> nil
    end
  end

  defp parse_streaming_chunk(%{event: "content_block_delta", data: data}) do
    case Jason.decode(data) do
      {:ok, chunk} ->
        delta = chunk["delta"]
        %{
          type: :content_block_delta,
          delta: delta,
          text: delta["text"]
        }
      
      {:error, _} -> nil
    end
  end

  defp parse_streaming_chunk(%{event: "message_delta", data: data}) do
    case Jason.decode(data) do
      {:ok, chunk} ->
        delta = chunk["delta"]
        %{
          type: :message_delta,
          delta: delta,
          stop_reason: delta["stop_reason"]
        }
      
      {:error, _} -> nil
    end
  end

  defp parse_streaming_chunk(%{event: "message_stop"}) do
    %{type: :message_stop}
  end

  defp parse_streaming_chunk(_) do
    nil
  end

  defp perform_health_check(state) do
    # Simple health check using a minimal API call
    test_messages = [Message.user("Hi")]
    
    case chat(test_messages, state, [model: state.config.default_model, max_tokens: 1]) do
      {:ok, _response, _new_state} -> :ok
      {:error, {:http_error, _}, _} -> {:unhealthy, :network_error}
      {:error, {:client_error, 401, _}, _} -> {:unhealthy, :auth_error}
      {:error, {:client_error, 429, _}, _} -> {:degraded, :rate_limited}
      {:error, reason, _} -> {:degraded, reason}
    end
  end

  defp get_context_window("claude-3-opus-20240229"), do: 200_000
  defp get_context_window("claude-3-sonnet-20240229"), do: 200_000
  defp get_context_window("claude-3-haiku-20240307"), do: 200_000
  defp get_context_window("claude-2.1"), do: 200_000
  defp get_context_window("claude-2.0"), do: 100_000
  defp get_context_window("claude-instant-1.2"), do: 100_000
  defp get_context_window(_), do: 100_000

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

  defp maybe_add_temperature(request, opts) do
    case Keyword.get(opts, :temperature) do
      nil -> request
      temp when temp >= 0.0 and temp <= 1.0 -> Map.put(request, :temperature, temp)
      _ -> request
    end
  end

  defp maybe_add_top_p(request, opts) do
    case Keyword.get(opts, :top_p) do
      nil -> request
      top_p when top_p >= 0.0 and top_p <= 1.0 -> Map.put(request, :top_p, top_p)
      _ -> request
    end
  end

  defp maybe_add_top_k(request, opts) do
    case Keyword.get(opts, :top_k) do
      nil -> request
      top_k when is_integer(top_k) and top_k > 0 -> Map.put(request, :top_k, top_k)
      _ -> request
    end
  end

  defp maybe_add_stop_sequences(request, opts) do
    case Keyword.get(opts, :stop_sequences) do
      nil -> request
      stop when is_list(stop) -> Map.put(request, :stop_sequences, stop)
      _ -> request
    end
  end
end