defmodule RubberDuck.LLM.ErrorHandler do
  @moduledoc """
  Comprehensive error handling for the LLM service layer.
  
  This module provides:
  - Standardized error types and formats
  - Error context enrichment
  - Retry logic with exponential backoff
  - Recovery strategies
  - Error reporting and telemetry
  """
  
  require Logger
  
  @type error_type :: 
    :provider_not_configured |
    :provider_not_connected |
    :invalid_request |
    :rate_limit_exceeded |
    :timeout |
    :network_error |
    :authentication_failed |
    :model_not_available |
    :context_too_large |
    :invalid_response |
    :service_unavailable |
    :unknown_error
    
  @type error_severity :: :critical | :error | :warning | :info
  
  @type error_context :: %{
    error_type: error_type(),
    severity: error_severity(),
    provider: atom() | nil,
    model: String.t() | nil,
    user_id: String.t() | nil,
    request_id: String.t() | nil,
    timestamp: DateTime.t(),
    details: map(),
    retry_count: non_neg_integer(),
    recoverable: boolean()
  }
  
  @type formatted_error :: {error_type(), error_context()}
  
  # Maximum retry attempts for different error types
  @retry_limits %{
    rate_limit_exceeded: 3,
    timeout: 2,
    network_error: 3,
    service_unavailable: 2,
    invalid_response: 1
  }
  
  # Base delay in milliseconds for exponential backoff
  @base_delay 1000
  @max_delay 30_000
  
  @doc """
  Handles an error by enriching it with context and determining recovery strategy.
  """
  @spec handle_error(term(), keyword()) :: {:error, formatted_error()} | {:retry, formatted_error(), non_neg_integer()}
  def handle_error(error, opts \\ []) do
    context = build_error_context(error, opts)
    
    # Log the error
    log_error(context)
    
    # Report telemetry
    report_telemetry(context)
    
    # Determine if we should retry
    case should_retry?(context) do
      {true, delay} ->
        {:retry, {context.error_type, context}, delay}
        
      false ->
        {:error, {context.error_type, context}}
    end
  end
  
  @doc """
  Wraps a function with error handling and retry logic.
  """
  @spec with_error_handling((() -> {:ok, term()} | {:error, term()}), keyword()) :: {:ok, term()} | {:error, formatted_error()}
  def with_error_handling(fun, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    retry_count = Keyword.get(opts, :retry_count, 0)
    
    case fun.() do
      {:ok, result} ->
        {:ok, result}
        
      {:error, reason} ->
        case handle_error(reason, Keyword.put(opts, :retry_count, retry_count)) do
          {:retry, {_type, _context}, delay} when retry_count < max_retries ->
            Logger.info("Retrying after #{delay}ms (attempt #{retry_count + 1}/#{max_retries})")
            Process.sleep(delay)
            with_error_handling(fun, Keyword.put(opts, :retry_count, retry_count + 1))
            
          {:retry, error, _delay} ->
            # Max retries exceeded
            {:error, error}
            
          {:error, error} ->
            {:error, error}
        end
    end
  end
  
  @doc """
  Formats an error for user display.
  """
  @spec format_user_error(formatted_error()) :: String.t()
  def format_user_error({error_type, context}) do
    case error_type do
      :provider_not_configured ->
        "The LLM provider '#{context.provider}' is not configured. Please check your settings."
        
      :provider_not_connected ->
        "Unable to connect to the LLM provider '#{context.provider}'. Please check your API credentials and network connection."
        
      :rate_limit_exceeded ->
        "Rate limit exceeded for #{context.provider}. Please try again in a few moments."
        
      :timeout ->
        "The request timed out. The LLM provider may be experiencing high load."
        
      :authentication_failed ->
        "Authentication failed for #{context.provider}. Please check your API key."
        
      :model_not_available ->
        "The model '#{context.model}' is not available for provider '#{context.provider}'."
        
      :context_too_large ->
        "The conversation context is too large. Please start a new conversation or reduce the message size."
        
      :service_unavailable ->
        "The LLM service is temporarily unavailable. Please try again later."
        
      _ ->
        "An unexpected error occurred. Please try again or contact support if the issue persists."
    end
  end
  
  @doc """
  Extracts error details from various error formats.
  """
  @spec extract_error_details(term()) :: map()
  def extract_error_details(error) do
    case error do
      {:missing_required_parameter, param} ->
        %{parameter: param, message: "Required parameter '#{param}' is missing"}
        
      {:invalid_messages, reason} ->
        %{reason: reason, message: "Invalid message format"}
        
      {:provider_not_configured, provider} ->
        %{provider: provider, message: "Provider '#{provider}' is not configured"}
        
      {:unknown_model, model} ->
        %{model: model, message: "Unknown model '#{model}'"}
        
      {:http_error, status, body} ->
        %{status_code: status, response_body: body, message: "HTTP error #{status}"}
        
      %{__exception__: true} = exception ->
        %{
          exception_type: exception.__struct__,
          message: Exception.message(exception),
          stacktrace: Process.info(self(), :current_stacktrace)
        }
        
      error when is_binary(error) ->
        %{message: error}
        
      error ->
        %{raw_error: inspect(error), message: "Unknown error format"}
    end
  end
  
  # Private functions
  
  defp build_error_context(error, opts) do
    error_type = classify_error(error)
    severity = determine_severity(error_type)
    
    %{
      error_type: error_type,
      severity: severity,
      provider: Keyword.get(opts, :provider),
      model: Keyword.get(opts, :model),
      user_id: Keyword.get(opts, :user_id),
      request_id: Keyword.get(opts, :request_id),
      timestamp: DateTime.utc_now(),
      details: extract_error_details(error),
      retry_count: Keyword.get(opts, :retry_count, 0),
      recoverable: is_recoverable?(error_type)
    }
  end
  
  defp classify_error(error) do
    case error do
      {:missing_required_parameter, _} -> :invalid_request
      {:invalid_messages, _} -> :invalid_request
      {:provider_not_configured, _} -> :provider_not_configured
      {:provider_not_connected, _} -> :provider_not_connected
      {:unknown_model, _} -> :model_not_available
      {:rate_limit, _} -> :rate_limit_exceeded
      {:timeout, _} -> :timeout
      :timeout -> :timeout
      {:http_error, 401, _} -> :authentication_failed
      {:http_error, 429, _} -> :rate_limit_exceeded
      {:http_error, 500, _} -> :service_unavailable
      {:http_error, 503, _} -> :service_unavailable
      {:http_error, _, _} -> :network_error
      {:network_error, _} -> :network_error
      {:invalid_response, _} -> :invalid_response
      _ -> :unknown_error
    end
  end
  
  defp determine_severity(error_type) do
    case error_type do
      :provider_not_configured -> :critical
      :authentication_failed -> :critical
      :service_unavailable -> :error
      :timeout -> :error
      :rate_limit_exceeded -> :warning
      :invalid_request -> :warning
      :model_not_available -> :warning
      _ -> :error
    end
  end
  
  defp is_recoverable?(error_type) do
    error_type in [:rate_limit_exceeded, :timeout, :network_error, :service_unavailable, :invalid_response]
  end
  
  defp should_retry?(%{error_type: error_type, retry_count: retry_count, recoverable: true}) do
    max_retries = Map.get(@retry_limits, error_type, 0)
    
    if retry_count < max_retries do
      delay = calculate_backoff_delay(retry_count, error_type)
      {true, delay}
    else
      false
    end
  end
  
  defp should_retry?(_), do: false
  
  defp calculate_backoff_delay(retry_count, error_type) do
    # Special handling for rate limits
    base = case error_type do
      :rate_limit_exceeded -> @base_delay * 5  # Start with 5 second delay
      _ -> @base_delay
    end
    
    # Exponential backoff with jitter
    delay = base * :math.pow(2, retry_count) + :rand.uniform(500)
    min(round(delay), @max_delay)
  end
  
  defp log_error(%{severity: severity} = context) do
    message = format_log_message(context)
    
    case severity do
      :critical -> Logger.error(message, error_context: context)
      :error -> Logger.error(message, error_context: context)
      :warning -> Logger.warning(message, error_context: context)
      :info -> Logger.info(message, error_context: context)
    end
  end
  
  defp format_log_message(context) do
    """
    LLM Error: #{context.error_type}
    Provider: #{context.provider || "unknown"}
    Model: #{context.model || "unknown"}
    User: #{context.user_id || "unknown"}
    Request ID: #{context.request_id || "unknown"}
    Details: #{inspect(context.details)}
    Retry Count: #{context.retry_count}
    Recoverable: #{context.recoverable}
    """
  end
  
  defp report_telemetry(context) do
    :telemetry.execute(
      [:rubber_duck, :llm, :error],
      %{count: 1},
      %{
        error_type: context.error_type,
        severity: context.severity,
        provider: context.provider,
        model: context.model,
        recoverable: context.recoverable,
        retry_count: context.retry_count
      }
    )
  end
  
  @doc """
  Creates a fallback response for critical errors.
  """
  @spec create_fallback_response(formatted_error()) :: map()
  def create_fallback_response({error_type, context}) do
    %{
      choices: [
        %{
          index: 0,
          message: %{
            role: "assistant",
            content: "I apologize, but I'm unable to process your request due to a technical issue: #{format_user_error({error_type, context})}"
          },
          finish_reason: "error"
        }
      ],
      usage: nil,
      error: %{
        type: error_type,
        message: format_user_error({error_type, context}),
        recoverable: context.recoverable
      }
    }
  end
end