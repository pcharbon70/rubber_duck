defmodule RubberDuck.LLM.ServiceV2 do
  @moduledoc """
  Stateless LLM service that requires provider and model on every request.
  
  This is a complete refactor of the original LLM service to remove all state
  management and provider resolution logic. Each request must explicitly specify
  the provider and model to use.
  
  ## Key Changes from V1
  
  - No GenServer state management
  - Provider and model are required parameters
  - Configuration loaded on-demand per request
  - No fallback provider logic
  - No circuit breaker state
  - Simple, direct execution model
  
  ## Usage
  
      opts = [
        provider: :openai,        # Required
        model: "gpt-4",          # Required
        messages: messages,       # Required
        temperature: 0.7,
        max_tokens: 1000,
        user_id: "user_123"      # Optional, for telemetry
      ]
      
      {:ok, response} = ServiceV2.completion(opts)
  """
  
  require Logger
  
  alias RubberDuck.LLM.{
    Request,
    Response,
    ProviderConfig,
    ConfigLoader,
    AdapterRegistry,
    ErrorHandler
  }
  
  alias RubberDuck.Status
  
  @type provider_name :: atom()
  @type model_name :: String.t()
  
  @doc """
  Sends a completion request to the specified provider.
  
  ## Required Options
  
  - `:provider` - Provider to use (e.g., :openai, :anthropic)
  - `:model` - Model to use (e.g., "gpt-4", "claude-3-sonnet")
  - `:messages` - List of message maps with :role and :content
  
  ## Optional Options
  
  - `:temperature` - Sampling temperature (0.0 to 2.0)
  - `:max_tokens` - Maximum tokens to generate
  - `:timeout` - Request timeout in milliseconds (default: 30000)
  - `:user_id` - User ID for telemetry and tracking
  - `:stream` - Whether to stream the response (not yet implemented)
  
  ## Examples
  
      opts = [
        provider: :openai,
        model: "gpt-4",
        messages: [%{role: "user", content: "Hello!"}],
        temperature: 0.7
      ]
      
      {:ok, response} = ServiceV2.completion(opts)
  
  ## Errors
  
  - `{:error, {:missing_required_parameter, :provider}}`
  - `{:error, {:missing_required_parameter, :model}}`
  - `{:error, {:missing_required_parameter, :messages}}`
  - `{:error, {:provider_not_found, provider}}`
  - `{:error, {:provider_not_configured, provider}}`
  - `{:error, {:invalid_messages, reason}}`
  """
  @spec completion(keyword()) :: {:ok, Response.t()} | {:error, term()}
  def completion(opts) do
    ErrorHandler.with_error_handling(
      fn ->
        with {:ok, provider} <- fetch_required(opts, :provider),
             {:ok, model} <- fetch_required(opts, :model),
             {:ok, messages} <- fetch_required(opts, :messages),
             {:ok, messages} <- validate_messages(messages),
             {:ok, provider_config} <- load_provider_config(provider),
             {:ok, adapter} <- get_adapter(provider),
             {:ok, request} <- build_request(provider, model, messages, opts),
             {:ok, response} <- execute_request(adapter, request, provider_config, opts) do
          {:ok, response}
        else
          error -> handle_validation_error(error)
        end
      end,
      Keyword.merge(opts, [max_retries: 3])
    )
  end
  
  @doc """
  Sends a streaming completion request to the specified provider.
  
  The callback function will be called for each chunk received.
  
  ## Example
  
      opts = [
        provider: :openai,
        model: "gpt-4", 
        messages: messages
      ]
      
      {:ok, ref} = ServiceV2.completion_stream(opts, fn chunk ->
        IO.write(chunk.content)
      end)
  """
  @spec completion_stream(keyword(), function()) :: {:ok, reference()} | {:error, term()}
  def completion_stream(opts, callback) when is_function(callback, 1) do
    with {:ok, provider} <- fetch_required(opts, :provider),
         {:ok, model} <- fetch_required(opts, :model),
         {:ok, messages} <- fetch_required(opts, :messages),
         {:ok, messages} <- validate_messages(messages),
         {:ok, provider_config} <- load_provider_config(provider),
         {:ok, adapter} <- get_adapter(provider),
         {:ok, request} <- build_request(provider, model, messages, opts) do
      
      # Check if adapter supports streaming
      if function_exported?(adapter, :stream_completion, 3) do
        ref = make_ref()
        
        # Start streaming in a separate process
        Task.start_link(fn ->
          result = adapter.stream_completion(request, provider_config, callback)
          
          # Send completion notification if needed
          case result do
            {:ok, _} -> 
              Logger.debug("Streaming completed for provider=#{provider} model=#{model}")
            {:error, reason} ->
              Logger.error("Streaming failed for provider=#{provider} model=#{model}: #{inspect(reason)}")
          end
        end)
        
        {:ok, ref}
      else
        {:error, {:streaming_not_supported, provider}}
      end
    end
  end
  
  # Private Functions
  
  defp fetch_required(opts, key) do
    case Keyword.get(opts, key) do
      nil -> {:error, {:missing_required_parameter, key}}
      value -> {:ok, value}
    end
  end
  
  defp validate_messages([]), do: {:error, {:invalid_messages, :empty}}
  defp validate_messages(messages) when is_list(messages) do
    if Enum.all?(messages, &valid_message?/1) do
      {:ok, messages}
    else
      {:error, {:invalid_messages, :invalid_format}}
    end
  end
  defp validate_messages(_), do: {:error, {:invalid_messages, :not_a_list}}
  
  defp valid_message?(%{role: role, content: content}) 
    when role in ["system", "user", "assistant"] and is_binary(content), do: true
  defp valid_message?(%{"role" => role, "content" => content}) 
    when role in ["system", "user", "assistant"] and is_binary(content), do: true
  defp valid_message?(_), do: false
  
  defp load_provider_config(provider) do
    case ConfigLoader.load_provider_config(provider) do
      nil -> 
        {:error, {:provider_not_configured, provider}}
      config ->
        # Convert to ProviderConfig struct
        provider_config = struct(ProviderConfig, config)
        {:ok, provider_config}
    end
  end
  
  defp get_adapter(provider) do
    AdapterRegistry.get_adapter(provider)
  end
  
  defp build_request(provider, model, messages, opts) do
    request = %Request{
      id: generate_request_id(),
      provider: provider,
      model: model,
      messages: normalize_messages(messages),
      options: build_options(opts),
      timestamp: DateTime.utc_now(),
      status: :pending,
      retries: 0
    }
    
    {:ok, request}
  end
  
  defp normalize_messages(messages) do
    Enum.map(messages, fn
      %{role: role, content: content} -> 
        %{"role" => to_string(role), "content" => content}
      %{"role" => _role, "content" => _content} = msg -> 
        msg
      msg -> 
        msg
    end)
  end
  
  defp build_options(opts) do
    %{
      temperature: Keyword.get(opts, :temperature, 0.7),
      max_tokens: Keyword.get(opts, :max_tokens),
      timeout: Keyword.get(opts, :timeout, 30_000),
      user_id: Keyword.get(opts, :user_id),
      stream: Keyword.get(opts, :stream, false),
      top_p: Keyword.get(opts, :top_p),
      frequency_penalty: Keyword.get(opts, :frequency_penalty),
      presence_penalty: Keyword.get(opts, :presence_penalty),
      stop: Keyword.get(opts, :stop),
      n: Keyword.get(opts, :n, 1)
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end
  
  defp execute_request(adapter, request, provider_config, opts) do
    user_id = Keyword.get(opts, :user_id)
    start_time = System.monotonic_time(:millisecond)
    
    # Send telemetry for request start
    if user_id do
      Status.engine(
        user_id,
        "Starting #{request.provider} request",
        Status.build_llm_metadata(request.model, to_string(request.provider), %{
          request_id: request.id
        })
      )
    end
    
    # Execute the request with retries
    result = execute_with_retry(adapter, request, provider_config, opts[:max_retries] || 3)
    
    # Send telemetry for completion
    if user_id do
      case result do
        {:ok, response} ->
          Status.with_timing(
            user_id,
            :engine,
            "Completed #{request.provider} request",
            start_time,
            Status.build_llm_metadata(request.model, to_string(request.provider), %{
              request_id: request.id,
              usage: response.usage
            })
          )
          
        {:error, reason} ->
          Status.error(
            user_id,
            "#{request.provider} request failed",
            Status.build_error_metadata(:provider_error, inspect(reason), %{
              request_id: request.id,
              provider: request.provider,
              model: request.model
            })
          )
      end
    end
    
    result
  end
  
  defp execute_with_retry(adapter, request, config, max_retries, attempt \\ 1) do
    case adapter.execute(request, config) do
      {:ok, response} ->
        # Validate response structure
        case validate_response(response) do
          :ok -> {:ok, response}
          {:error, reason} -> {:error, {:invalid_response, reason}}
        end
        
      {:error, reason} ->
        # Enrich error with provider context
        enriched_error = enrich_error(reason, request.provider, request.model)
        
        # Let ErrorHandler decide if we should retry
        error_context = [
          provider: request.provider,
          model: request.model,
          user_id: request.user_id,
          request_id: request.id,
          retry_count: attempt - 1
        ]
        
        case ErrorHandler.handle_error(enriched_error, error_context) do
          {:retry, _formatted_error, delay} when attempt < max_retries ->
            Logger.warning("Retrying LLM request after #{delay}ms (attempt #{attempt}/#{max_retries})")
            Process.sleep(delay)
            execute_with_retry(adapter, request, config, max_retries, attempt + 1)
            
          {:retry, formatted_error, _delay} ->
            # Max retries exceeded
            {:error, formatted_error}
            
          {:error, formatted_error} ->
            # Not recoverable
            {:error, formatted_error}
        end
    end
  end
  
  defp validate_response(%Response{} = response) do
    cond do
      is_nil(response.choices) or response.choices == [] ->
        {:error, "No choices in response"}
        
      not is_list(response.choices) ->
        {:error, "Invalid choices format"}
        
      true ->
        :ok
    end
  end
  
  defp validate_response(_) do
    {:error, "Response is not a valid Response struct"}
  end
  
  defp generate_request_id do
    "req_" <> (:crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower))
  end
  
  # Error handling functions
  
  defp handle_validation_error(error) do
    case error do
      {:error, reason} -> {:error, reason}
      error -> {:error, error}
    end
  end
  
  @doc """
  Validates and enriches error responses from providers.
  """
  def enrich_error(error, provider, model) do
    case error do
      {:http_error, status, body} ->
        {:error, {:http_error, status, parse_provider_error(provider, body)}}
        
      :timeout ->
        {:error, {:timeout, "Request to #{provider}/#{model} timed out"}}
        
      {:network_error, reason} ->
        {:error, {:network_error, "Network error communicating with #{provider}: #{inspect(reason)}"}}
        
      error ->
        {:error, error}
    end
  end
  
  defp parse_provider_error(:openai, body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"message" => message, "type" => type}}} ->
        %{message: message, type: type, raw: body}
      _ ->
        %{message: body, raw: body}
    end
  end
  
  defp parse_provider_error(:anthropic, body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"error" => %{"message" => message}}} ->
        %{message: message, raw: body}
      _ ->
        %{message: body, raw: body}
    end
  end
  
  defp parse_provider_error(_provider, body) do
    %{message: to_string(body), raw: body}
  end
end