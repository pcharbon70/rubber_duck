defmodule RubberDuck.Interface.ErrorHandler do
  @moduledoc """
  Standardized error handling across all interfaces.
  
  This module provides utilities for creating, transforming, and logging errors
  in a consistent way across different interface adapters. It defines standard
  error categories and provides transformation functions for interface-specific
  error formats.
  """

  alias RubberDuck.Interface.Behaviour
  alias RubberDuck.EventBroadcasting.EventBroadcaster

  require Logger

  @type error_category :: 
    :validation_error |
    :authentication_error |
    :authorization_error |
    :not_found |
    :timeout |
    :rate_limit |
    :internal_error |
    :unsupported_operation |
    :network_error |
    :dependency_error

  @type error_severity :: :low | :medium | :high | :critical

  @type error_context :: %{
    optional(:request_id) => String.t(),
    optional(:interface) => atom(),
    optional(:operation) => atom(),
    optional(:user_id) => String.t(),
    optional(:session_id) => String.t(),
    optional(:component) => String.t(),
    optional(:trace_id) => String.t()
  }

  @doc """
  Creates a standardized error with proper categorization and metadata.
  
  ## Parameters
  - `category` - Error category atom
  - `message` - Human-readable error message
  - `metadata` - Additional error metadata
  - `context` - Request/operation context
  
  ## Returns
  - Standardized error tuple
  
  ## Examples
  
      iex> ErrorHandler.create_error(
      ...>   :validation_error, 
      ...>   "Missing required field 'operation'",
      ...>   %{field: :operation},
      ...>   %{request_id: "req_123"}
      ...> )
      {:error, :validation_error, "Missing required field 'operation'", %{
        field: :operation,
        category: :validation_error,
        severity: :medium,
        request_id: "req_123",
        timestamp: ~U[...]
      }}
  """
  def create_error(category, message, metadata \\ %{}, context \\ %{}) do
    severity = determine_severity(category)
    
    error_metadata = metadata
    |> Map.put(:category, category)
    |> Map.put(:severity, severity)
    |> Map.put(:timestamp, DateTime.utc_now())
    |> Map.merge(context)
    
    error = Behaviour.error(category, message, error_metadata)
    
    # Log the error
    log_error(error, context)
    
    # Broadcast error event
    broadcast_error_event(error, context)
    
    error
  end

  @doc """
  Transforms an internal error to interface-specific format.
  
  ## Parameters
  - `error` - Internal error tuple
  - `interface` - Target interface (:cli, :web, :lsp, etc.)
  - `options` - Interface-specific transformation options
  
  ## Returns
  - Transformed error in interface format
  """
  def transform_error(error, interface, options \\ [])

  def transform_error({:error, category, message, metadata} = _error, interface, options) do
    case interface do
      :cli -> transform_cli_error(category, message, metadata, options)
      :web -> transform_web_error(category, message, metadata, options)
      :lsp -> transform_lsp_error(category, message, metadata, options)
      _ -> transform_generic_error(category, message, metadata, options)
    end
  end

  def transform_error(error, interface, options) do
    # Handle non-standard error formats
    generic_error = normalize_error(error)
    transform_error(generic_error, interface, options)
  end

  @doc """
  Generates an error response in the standard response format.
  
  ## Parameters
  - `error` - Error tuple
  - `request_id` - Original request ID
  - `metadata` - Additional response metadata
  
  ## Returns
  - Error response map
  """
  def error_to_response({:error, category, message, error_metadata}, request_id, metadata \\ %{}) do
    response_metadata = Map.merge(%{
      error_category: category,
      error_severity: Map.get(error_metadata, :severity, :medium),
      timestamp: DateTime.utc_now()
    }, metadata)
    
    Behaviour.error_response(request_id, {category, message, error_metadata}, response_metadata)
  end

  @doc """
  Wraps exceptions in standardized error format.
  
  ## Parameters
  - `exception` - Exception struct
  - `context` - Error context
  
  ## Returns
  - Standardized error tuple
  """
  def wrap_exception(exception, context \\ %{}) do
    {category, message, metadata} = categorize_exception(exception)
    
    create_error(category, message, metadata, context)
  end

  @doc """
  Logs an error with structured information.
  
  ## Parameters
  - `error` - Error tuple
  - `context` - Logging context
  """
  def log_error({:error, category, message, metadata}, context \\ %{}) do
    severity = Map.get(metadata, :severity, :medium)
    
    log_data = %{
      category: category,
      message: message,
      metadata: metadata,
      context: context
    }
    
    case severity do
      :critical ->
        Logger.error("Critical error occurred", log_data)
      :high ->
        Logger.error("High severity error", log_data)
      :medium ->
        Logger.warning("Error occurred", log_data)
      :low ->
        Logger.info("Minor error", log_data)
    end
  end

  @doc """
  Updates error metrics for monitoring.
  
  ## Parameters
  - `error` - Error tuple
  - `context` - Error context
  """
  def update_error_metrics({:error, category, _message, metadata}, context \\ %{}) do
    interface = Map.get(context, :interface, :unknown)
    severity = Map.get(metadata, :severity, :medium)
    
    # Here you would typically update your metrics system
    # For now, we'll just log the metric
    Logger.debug("Error metric", %{
      interface: interface,
      category: category,
      severity: severity,
      timestamp: DateTime.utc_now()
    })
  end

  @doc """
  Determines if an error should be retried.
  
  ## Parameters
  - `error` - Error tuple
  
  ## Returns
  - `true` if error is retryable, `false` otherwise
  """
  def retryable?({:error, category, _message, _metadata}) do
    case category do
      :timeout -> true
      :network_error -> true
      :dependency_error -> true
      :rate_limit -> true
      :internal_error -> true
      _ -> false
    end
  end

  @doc """
  Gets retry delay for retryable errors.
  
  ## Parameters
  - `error` - Error tuple
  - `attempt` - Current retry attempt number
  
  ## Returns
  - Delay in milliseconds
  """
  def retry_delay({:error, category, _message, _metadata}, attempt) do
    base_delay = case category do
      :rate_limit -> 60_000  # 1 minute
      :timeout -> 5_000      # 5 seconds
      :network_error -> 2_000 # 2 seconds
      _ -> 1_000             # 1 second
    end
    
    # Exponential backoff with jitter
    delay = base_delay * :math.pow(2, attempt - 1)
    jitter = :rand.uniform(1000)
    
    round(delay + jitter)
  end

  # Private functions

  defp determine_severity(category) do
    case category do
      :authentication_error -> :high
      :authorization_error -> :high
      :internal_error -> :critical
      :dependency_error -> :high
      :timeout -> :medium
      :rate_limit -> :medium
      :validation_error -> :low
      :not_found -> :low
      :unsupported_operation -> :low
      :network_error -> :medium
      _ -> :medium
    end
  end

  defp broadcast_error_event(error, context) do
    {:error, category, message, metadata} = error
    
    event_payload = %{
      category: category,
      message: message,
      severity: Map.get(metadata, :severity, :medium),
      interface: Map.get(context, :interface),
      operation: Map.get(context, :operation),
      request_id: Map.get(context, :request_id),
      user_id: Map.get(context, :user_id),
      timestamp: DateTime.utc_now()
    }
    
    EventBroadcaster.broadcast_async(%{
      topic: "interface.error.#{category}",
      payload: event_payload,
      priority: :high,
      metadata: %{component: "error_handler", severity: event_payload.severity}
    })
  end

  defp transform_cli_error(category, message, metadata, options) do
    include_stack_trace = Keyword.get(options, :include_stack_trace, false)
    colorize = Keyword.get(options, :colorize, true)
    
    error_prefix = if colorize, do: "\e[31mError:\e[0m", else: "Error:"
    category_text = category |> Atom.to_string() |> String.replace("_", " ") |> String.capitalize()
    
    formatted_message = "#{error_prefix} #{category_text} - #{message}"
    
    error_data = %{
      message: formatted_message,
      category: category,
      exit_code: category_to_exit_code(category)
    }
    
    if include_stack_trace and Map.has_key?(metadata, :stacktrace) do
      Map.put(error_data, :stacktrace, format_stacktrace(metadata.stacktrace))
    else
      error_data
    end
  end

  defp transform_web_error(category, message, metadata, options) do
    include_details = Keyword.get(options, :include_details, false)
    
    http_status = category_to_http_status(category)
    
    error_response = %{
      error: %{
        type: category,
        message: message,
        status: http_status
      }
    }
    
    if include_details do
      details_metadata = metadata
      |> Map.drop([:timestamp, :severity, :category])
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
      
      if map_size(details_metadata) > 0 do
        put_in(error_response, [:error, :details], details_metadata)
      else
        error_response
      end
    else
      error_response
    end
  end

  defp transform_lsp_error(category, message, metadata, _options) do
    error_code = category_to_lsp_error_code(category)
    
    %{
      code: error_code,
      message: message,
      data: Map.get(metadata, :lsp_data, %{})
    }
  end

  defp transform_generic_error(category, message, metadata, _options) do
    %{
      type: category,
      message: message,
      metadata: metadata
    }
  end

  defp normalize_error({:error, _reason} = error) when is_tuple(error) and tuple_size(error) == 2 do
    {:error, reason} = error
    create_error(:internal_error, "#{inspect(reason)}")
  end

  defp normalize_error(error) when is_binary(error) do
    create_error(:internal_error, error)
  end

  defp normalize_error(error) do
    create_error(:internal_error, "#{inspect(error)}")
  end

  defp categorize_exception(%ArgumentError{message: message}) do
    {:validation_error, "Invalid argument: #{message}", %{exception_type: "ArgumentError"}}
  end

  defp categorize_exception(%MatchError{} = exception) do
    {:internal_error, "Match error: #{Exception.message(exception)}", 
     %{exception_type: "MatchError"}}
  end

  defp categorize_exception(%RuntimeError{message: message}) do
    {:internal_error, message, %{exception_type: "RuntimeError"}}
  end

  defp categorize_exception(exception) do
    message = if Exception.exception?(exception) do
      Exception.message(exception)
    else
      "#{inspect(exception)}"
    end
    
    {:internal_error, "Unhandled exception: #{message}", 
     %{exception_type: exception.__struct__ |> Module.split() |> List.last()}}
  end

  defp category_to_exit_code(category) do
    case category do
      :validation_error -> 64        # EX_USAGE
      :authentication_error -> 77    # EX_NOPERM
      :authorization_error -> 77     # EX_NOPERM
      :not_found -> 66              # EX_NOINPUT
      :timeout -> 75                # EX_TEMPFAIL
      :rate_limit -> 75             # EX_TEMPFAIL
      :internal_error -> 70         # EX_SOFTWARE
      :unsupported_operation -> 64  # EX_USAGE
      :network_error -> 69          # EX_UNAVAILABLE
      :dependency_error -> 69       # EX_UNAVAILABLE
      _ -> 1                        # General error
    end
  end

  defp category_to_http_status(category) do
    case category do
      :validation_error -> 400      # Bad Request
      :authentication_error -> 401  # Unauthorized
      :authorization_error -> 403   # Forbidden
      :not_found -> 404            # Not Found
      :timeout -> 408              # Request Timeout
      :rate_limit -> 429           # Too Many Requests
      :internal_error -> 500       # Internal Server Error
      :unsupported_operation -> 501 # Not Implemented
      :network_error -> 502        # Bad Gateway
      :dependency_error -> 503     # Service Unavailable
      _ -> 500                     # Internal Server Error
    end
  end

  defp category_to_lsp_error_code(category) do
    case category do
      :validation_error -> -32602    # Invalid params
      :not_found -> -32601          # Method not found
      :internal_error -> -32603     # Internal error
      :timeout -> -32000            # Server error start
      :unsupported_operation -> -32601 # Method not found
      _ -> -32603                   # Internal error
    end
  end

  defp format_stacktrace(stacktrace) when is_list(stacktrace) do
    stacktrace
    |> Enum.map(&Exception.format_stacktrace_entry/1)
    |> Enum.join("\n")
  end

  defp format_stacktrace(stacktrace), do: "#{inspect(stacktrace)}"
end