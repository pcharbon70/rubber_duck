defmodule RubberDuck.LLMAbstraction.Providers.OpenAIProvider do
  @moduledoc """
  OpenAI provider implementation for the LLM abstraction layer.
  
  This provider implements the Provider behavior for OpenAI's GPT models,
  including chat completions, text completions, embeddings, and streaming.
  """

  @behaviour RubberDuck.LLMAbstraction.Provider
  
  require Logger
  
  alias RubberDuck.LLMAbstraction.{
    Config,
    HTTPClient,
    Message,
    Response,
    Capability,
    Telemetry
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
  @default_model "gpt-3.5-turbo"

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
      
      Logger.info("OpenAI provider initialized with base URL: #{validated_config.base_url}")
      {:ok, state}
    else
      {:error, reason} ->
        Logger.error("Failed to initialize OpenAI provider: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def chat(messages, %__MODULE__{} = state, opts \\ []) do
    request_id = Telemetry.track_request_start(:openai, :chat, %{model: Config.get_model(state.config)})
    start_time = System.monotonic_time(:millisecond)
    
    case build_chat_request(messages, state, opts) do
      {:ok, request_body} ->
        url = Config.get_endpoint_url(state.config, :chat)
        headers = Config.get_headers(state.config)
        
        case HTTPClient.post(url, request_body, headers: headers, timeout: state.config.timeout) do
          {:ok, http_response} ->
            case process_chat_response(http_response, state, start_time) do
              {:ok, response, new_state} ->
                # Track successful completion
                tokens_used = Response.get_token_usage(response)
                Telemetry.track_request_stop(request_id, :openai, :chat, :success, %{
                  start_time: start_time,
                  tokens_used: tokens_used,
                  model: Config.get_model(state.config)
                })
                {:ok, response, new_state}
              
              {:error, reason, new_state} ->
                Telemetry.track_request_error(request_id, :openai, :chat, reason, %{start_time: start_time})
                {:error, reason, new_state}
            end
          
          {:error, reason} ->
            new_state = update_statistics(state, :chat, :error, start_time)
            Telemetry.track_request_error(request_id, :openai, :chat, {:http_error, reason}, %{start_time: start_time})
            {:error, {:http_error, reason}, new_state}
        end
      
      {:error, reason} ->
        new_state = update_statistics(state, :chat, :error, start_time)
        Telemetry.track_request_error(request_id, :openai, :chat, reason, %{start_time: start_time})
        {:error, reason, new_state}
    end
  end

  @impl true
  def complete(prompt, %__MODULE__{} = state, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    
    case build_completion_request(prompt, state, opts) do
      {:ok, request_body} ->
        url = Config.get_endpoint_url(state.config, :completions)
        headers = Config.get_headers(state.config)
        
        case HTTPClient.post(url, request_body, headers: headers, timeout: state.config.timeout) do
          {:ok, http_response} ->
            process_completion_response(http_response, state, start_time)
          
          {:error, reason} ->
            new_state = update_statistics(state, :completion, :error, start_time)
            {:error, {:http_error, reason}, new_state}
        end
      
      {:error, reason} ->
        new_state = update_statistics(state, :completion, :error, start_time)
        {:error, reason, new_state}
    end
  end

  @impl true
  def embed(input, %__MODULE__{} = state, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    
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
    base_capabilities = [
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
      Capability.embeddings([
        constraints: [
          supported_models: ["text-embedding-ada-002", "text-embedding-3-small", "text-embedding-3-large"]
        ]
      ]),
      Capability.streaming([
        constraints: [
          supported_models: config.supported_models
        ]
      ])
    ]

    # Add function calling for models that support it
    if supports_function_calling?(config.default_model) do
      function_capability = Capability.function_calling([
        constraints: [
          max_functions: 128,
          supported_models: function_calling_models()
        ]
      ])
      [function_capability | base_capabilities]
    else
      base_capabilities
    end
  end

  @impl true
  def health_check(%__MODULE__{} = state) do
    health_status = case perform_health_check(state) do
      :ok -> :healthy
      {:degraded, _reason} -> :degraded
      {:unhealthy, _reason} -> :unhealthy
    end
    
    # Track health status change
    Telemetry.track_provider_health(:openai, health_status, %{
      provider_module: __MODULE__,
      config_base_url: state.config.base_url
    })
    
    health_status
  end

  @impl true
  def terminate(%__MODULE__{}) do
    Logger.info("OpenAI provider terminated")
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
      provider: "OpenAI",
      api_version: "v1",
      supported_features: [:chat, :completion, :embeddings, :streaming, :function_calling],
      rate_limits: %{
        gpt_4: %{rpm: 10_000, tpm: 300_000},
        gpt_3_5_turbo: %{rpm: 10_000, tpm: 1_000_000}
      },
      pricing: %{
        gpt_4: %{input: 0.03, output: 0.06},
        gpt_3_5_turbo: %{input: 0.001, output: 0.002}
      }
    }
  end

  # Request Building Functions

  defp build_chat_request(messages, state, opts) do
    with {:ok, formatted_messages} <- format_messages_for_openai(messages),
         {:ok, model} <- get_model(state, opts) do
      
      request = %{
        model: model,
        messages: formatted_messages,
        temperature: Keyword.get(opts, :temperature, @default_temperature),
        max_tokens: Keyword.get(opts, :max_tokens, @default_max_tokens),
        stream: Keyword.get(opts, :stream, false)
      }
      
      # Add optional parameters
      request = maybe_add_functions(request, opts)
      request = maybe_add_tools(request, opts)
      request = maybe_add_stop_sequences(request, opts)
      request = maybe_add_presence_penalty(request, opts)
      request = maybe_add_frequency_penalty(request, opts)
      request = maybe_add_top_p(request, opts)
      request = maybe_add_user(request, opts)
      
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
      request = maybe_add_presence_penalty(request, opts)
      request = maybe_add_frequency_penalty(request, opts)
      request = maybe_add_top_p(request, opts)
      request = maybe_add_user(request, opts)
      
      {:ok, request}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_embedding_request(input, state, opts) do
    model = Keyword.get(opts, :model, "text-embedding-ada-002")
    
    if model in ["text-embedding-ada-002", "text-embedding-3-small", "text-embedding-3-large"] do
      request = %{
        model: model,
        input: input
      }
      
      request = maybe_add_user(request, opts)
      request = maybe_add_dimensions(request, opts)
      
      {:ok, request}
    else
      {:error, {:unsupported_embedding_model, model}}
    end
  end

  # Response Processing Functions

  defp process_chat_response(http_response, state, start_time) do
    case HTTPClient.parse_json_response(http_response) do
      {:ok, response_data} ->
        case convert_openai_chat_response(response_data) do
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

  defp process_completion_response(http_response, state, start_time) do
    case HTTPClient.parse_json_response(http_response) do
      {:ok, response_data} ->
        case convert_openai_completion_response(response_data) do
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
    case Config.validate(Config.openai(Enum.to_list(config))) do
      :ok -> {:ok, Config.openai(Enum.to_list(config))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp format_messages_for_openai(messages) do
    try do
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
      {:error, {:unsupported_model, model}}
    end
  end

  defp convert_openai_chat_response(response_data) do
    try do
      llm_response = Response.from_provider_format(response_data, :openai)
      {:ok, llm_response}
    rescue
      error -> {:error, error}
    end
  end

  defp convert_openai_completion_response(response_data) do
    try do
      # Convert text completion format to standard response
      choices = Enum.map(response_data["choices"] || [], fn choice ->
        %{
          index: choice["index"],
          text: choice["text"],
          message: nil,
          finish_reason: String.to_existing_atom(choice["finish_reason"] || "stop"),
          logprobs: choice["logprobs"]
        }
      end)
      
      llm_response = Response.new([
        id: response_data["id"],
        object: response_data["object"],
        created: response_data["created"],
        model: response_data["model"],
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
      embeddings = response_data["data"]
      |> Enum.sort_by(& &1["index"])
      |> Enum.map(& &1["embedding"])
      
      {:ok, embeddings}
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

  defp perform_health_check(state) do
    # Simple health check using a minimal API call
    test_messages = [Message.user("test")]
    
    case chat(test_messages, state, [model: state.config.default_model, max_tokens: 1]) do
      {:ok, _response, _new_state} -> :ok
      {:error, {:http_error, _}, _} -> {:unhealthy, :network_error}
      {:error, {:client_error, 401, _}, _} -> {:unhealthy, :auth_error}
      {:error, {:client_error, 429, _}, _} -> {:degraded, :rate_limited}
      {:error, reason, _} -> {:degraded, reason}
    end
  end

  defp get_context_window("gpt-4"), do: 8192
  defp get_context_window("gpt-4-32k"), do: 32768
  defp get_context_window("gpt-4-1106-preview"), do: 128000
  defp get_context_window("gpt-4-0125-preview"), do: 128000
  defp get_context_window("gpt-3.5-turbo"), do: 4096
  defp get_context_window("gpt-3.5-turbo-16k"), do: 16384
  defp get_context_window("gpt-3.5-turbo-1106"), do: 16384
  defp get_context_window(_), do: 4096

  defp supports_function_calling?("gpt-4"), do: true
  defp supports_function_calling?("gpt-4-1106-preview"), do: true
  defp supports_function_calling?("gpt-4-0125-preview"), do: true
  defp supports_function_calling?("gpt-3.5-turbo"), do: true
  defp supports_function_calling?("gpt-3.5-turbo-1106"), do: true
  defp supports_function_calling?(_), do: false

  defp function_calling_models do
    ["gpt-4", "gpt-4-1106-preview", "gpt-4-0125-preview", "gpt-3.5-turbo", "gpt-3.5-turbo-1106"]
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

  defp maybe_add_functions(request, opts) do
    case Keyword.get(opts, :functions) do
      nil -> request
      functions -> Map.put(request, :functions, functions)
    end
  end

  defp maybe_add_tools(request, opts) do
    case Keyword.get(opts, :tools) do
      nil -> request
      tools -> Map.put(request, :tools, tools)
    end
  end

  defp maybe_add_stop_sequences(request, opts) do
    case Keyword.get(opts, :stop) do
      nil -> request
      stop -> Map.put(request, :stop, stop)
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

  defp maybe_add_top_p(request, opts) do
    case Keyword.get(opts, :top_p) do
      nil -> request
      top_p -> Map.put(request, :top_p, top_p)
    end
  end

  defp maybe_add_user(request, opts) do
    case Keyword.get(opts, :user) do
      nil -> request
      user -> Map.put(request, :user, user)
    end
  end

  defp maybe_add_dimensions(request, opts) do
    case Keyword.get(opts, :dimensions) do
      nil -> request
      dimensions -> Map.put(request, :dimensions, dimensions)
    end
  end
end