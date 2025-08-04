defmodule RubberDuck.Agents.ErrorHandling do
  @moduledoc """
  Common error handling utilities for Jido Actions.
  
  Provides standardized error response formats, retry logic,
  and common error handling patterns for use across all Actions.
  """
  
  require Logger
  
  @type error_type :: :network_error | :validation_error | :resource_error | :system_error
  
  @type error_response :: {:error, %{
    type: error_type(),
    message: String.t(),
    details: map(),
    retry_after: nil | non_neg_integer(),
    recoverable: boolean()
  }}
  
  # Error creation helpers
  
  @doc """
  Creates a standardized network error response.
  """
  def network_error(message, details \\ %{}) do
    {:error, %{
      type: :network_error,
      message: message,
      details: details,
      retry_after: Map.get(details, :retry_after, 5000),
      recoverable: Map.get(details, :recoverable, true)
    }}
  end
  
  @doc """
  Creates a standardized validation error response.
  """
  def validation_error(message, details \\ %{}) do
    {:error, %{
      type: :validation_error,
      message: message,
      details: details,
      retry_after: nil,
      recoverable: false
    }}
  end
  
  @doc """
  Creates a standardized resource error response.
  """
  def resource_error(message, details \\ %{}) do
    {:error, %{
      type: :resource_error,
      message: message,
      details: details,
      retry_after: Map.get(details, :retry_after, 1000),
      recoverable: Map.get(details, :recoverable, true)
    }}
  end
  
  @doc """
  Creates a standardized system error response.
  """
  def system_error(message, details \\ %{}) do
    {:error, %{
      type: :system_error,
      message: message,
      details: details,
      retry_after: Map.get(details, :retry_after, 10000),
      recoverable: Map.get(details, :recoverable, false)
    }}
  end
  
  # Retry logic
  
  @doc """
  Executes a function with exponential backoff retry logic.
  
  ## Options
  - `:max_retries` - Maximum number of retry attempts (default: 3)
  - `:base_delay` - Base delay in milliseconds (default: 1000)
  - `:max_delay` - Maximum delay in milliseconds (default: 30000)
  - `:jitter` - Add random jitter to delays (default: true)
  """
  def with_retry(fun, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    base_delay = Keyword.get(opts, :base_delay, 1000)
    max_delay = Keyword.get(opts, :max_delay, 30000)
    jitter = Keyword.get(opts, :jitter, true)
    
    do_retry(fun, 0, max_retries, base_delay, max_delay, jitter)
  end
  
  defp do_retry(fun, attempt, max_retries, base_delay, max_delay, jitter) do
    case fun.() do
      {:ok, _} = success ->
        success
      
      {:error, %{recoverable: false}} = error ->
        # Non-recoverable error, don't retry
        error
      
      {:error, %{retry_after: retry_after}} when is_integer(retry_after) and attempt < max_retries ->
        # Use suggested retry delay
        Process.sleep(retry_after)
        do_retry(fun, attempt + 1, max_retries, base_delay, max_delay, jitter)
      
      _error when attempt < max_retries ->
        # Calculate exponential backoff delay
        delay = calculate_delay(attempt, base_delay, max_delay, jitter)
        Logger.debug("Retry attempt #{attempt + 1}/#{max_retries} after #{delay}ms")
        Process.sleep(delay)
        do_retry(fun, attempt + 1, max_retries, base_delay, max_delay, jitter)
      
      error ->
        # Max retries reached
        Logger.warning("Max retries (#{max_retries}) reached")
        error
    end
  end
  
  defp calculate_delay(attempt, base_delay, max_delay, jitter) do
    # Exponential backoff: base_delay * 2^attempt
    delay = min(base_delay * :math.pow(2, attempt) |> round(), max_delay)
    
    if jitter do
      # Add random jitter (±25%)
      jitter_range = div(delay, 4)
      delay + :rand.uniform(jitter_range * 2) - jitter_range
    else
      delay
    end
  end
  
  # Circuit breaker pattern
  
  defmodule CircuitBreaker do
    @moduledoc """
    Simple circuit breaker implementation for protecting against cascading failures.
    """
    
    defstruct [
      :name,
      :state,
      :failure_count,
      :success_count,
      :failure_threshold,
      :success_threshold,
      :timeout,
      :last_failure_time
    ]
    
    @type t :: %__MODULE__{
      name: atom(),
      state: :closed | :open | :half_open,
      failure_count: non_neg_integer(),
      success_count: non_neg_integer(),
      failure_threshold: non_neg_integer(),
      success_threshold: non_neg_integer(),
      timeout: non_neg_integer(),
      last_failure_time: nil | DateTime.t()
    }
    
    @doc """
    Creates a new circuit breaker.
    """
    def new(name, opts \\ []) do
      %__MODULE__{
        name: name,
        state: :closed,
        failure_count: 0,
        success_count: 0,
        failure_threshold: Keyword.get(opts, :failure_threshold, 5),
        success_threshold: Keyword.get(opts, :success_threshold, 2),
        timeout: Keyword.get(opts, :timeout, 60_000),
        last_failure_time: nil
      }
    end
    
    @doc """
    Executes a function through the circuit breaker.
    """
    def call(%__MODULE__{state: :open, last_failure_time: last_failure, timeout: timeout} = breaker, _fun) do
      if DateTime.diff(DateTime.utc_now(), last_failure, :millisecond) >= timeout do
        # Timeout expired, transition to half-open
        {:half_open, %{breaker | state: :half_open, success_count: 0}}
      else
        # Circuit still open
        {:error, %{
          type: :system_error,
          message: "Circuit breaker is open",
          details: %{breaker: breaker.name},
          retry_after: timeout - DateTime.diff(DateTime.utc_now(), last_failure, :millisecond),
          recoverable: true
        }}
      end
    end
    
    def call(%__MODULE__{} = breaker, fun) do
      case fun.() do
        {:ok, _} = success ->
          breaker = record_success(breaker)
          {:ok, success, breaker}
        
        error ->
          breaker = record_failure(breaker)
          {:error, error, breaker}
      end
    end
    
    defp record_success(%__MODULE__{state: :half_open} = breaker) do
      success_count = breaker.success_count + 1
      
      if success_count >= breaker.success_threshold do
        # Enough successes, close the circuit
        %{breaker | state: :closed, failure_count: 0, success_count: 0}
      else
        %{breaker | success_count: success_count}
      end
    end
    
    defp record_success(breaker) do
      %{breaker | failure_count: 0}
    end
    
    defp record_failure(%__MODULE__{state: :half_open} = breaker) do
      # Single failure in half-open state reopens the circuit
      %{breaker | 
        state: :open, 
        failure_count: breaker.failure_count + 1,
        last_failure_time: DateTime.utc_now()
      }
    end
    
    defp record_failure(breaker) do
      failure_count = breaker.failure_count + 1
      
      if failure_count >= breaker.failure_threshold do
        # Too many failures, open the circuit
        %{breaker | 
          state: :open, 
          failure_count: failure_count,
          last_failure_time: DateTime.utc_now()
        }
      else
        %{breaker | failure_count: failure_count}
      end
    end
  end
  
  # Common error handlers
  
  @doc """
  Wraps a function that might raise an exception and converts it to an error tuple.
  """
  def safe_execute(fun) do
    try do
      result = fun.()
      {:ok, result}
    rescue
      e in ArgumentError ->
        validation_error("Invalid argument: #{Exception.message(e)}", %{exception: e})
      
      e in File.Error ->
        resource_error("File operation failed: #{Exception.message(e)}", %{exception: e})
      
      e in RuntimeError ->
        system_error("Runtime error: #{Exception.message(e)}", %{exception: e})
      
      e ->
        system_error("Unexpected error: #{inspect(e)}", %{exception: e})
    catch
      :exit, reason ->
        system_error("Process exited: #{inspect(reason)}", %{exit_reason: reason})
      
      kind, reason ->
        system_error("Caught #{kind}: #{inspect(reason)}", %{kind: kind, reason: reason})
    end
  end
  
  @doc """
  Validates required parameters and returns an error if any are missing.
  """
  def validate_required_params(params, required_keys) do
    missing_keys = required_keys -- Map.keys(params)
    
    if missing_keys == [] do
      :ok
    else
      validation_error(
        "Missing required parameters: #{Enum.join(missing_keys, ", ")}",
        %{missing_keys: missing_keys, provided_keys: Map.keys(params)}
      )
    end
  end
  
  @doc """
  Handles common HTTP response patterns.
  """
  def handle_http_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end
  
  def handle_http_response({:ok, %{status: 429, headers: headers}}) do
    retry_after = find_retry_after_header(headers)
    network_error("Rate limit exceeded", %{
      status: 429,
      retry_after: retry_after,
      recoverable: true
    })
  end
  
  def handle_http_response({:ok, %{status: status}}) when status in 500..599 do
    network_error("Server error", %{
      status: status,
      recoverable: true
    })
  end
  
  def handle_http_response({:ok, %{status: status, body: body}}) do
    network_error("HTTP request failed", %{
      status: status,
      body: body,
      recoverable: status != 404
    })
  end
  
  def handle_http_response({:error, reason}) do
    network_error("HTTP request error: #{inspect(reason)}", %{
      reason: reason,
      recoverable: true
    })
  end
  
  defp find_retry_after_header(headers) do
    case List.keyfind(headers, "retry-after", 0) do
      {_, value} -> parse_retry_after(value)
      nil -> nil
    end
  end
  
  defp parse_retry_after(value) do
    case Integer.parse(value) do
      {seconds, _} -> seconds * 1000
      :error -> 60_000  # Default to 1 minute
    end
  end
  
  @doc """
  Logs an error with appropriate level based on error type.
  """
  def log_error({:error, %{type: type, message: message, details: details}}) do
    case type do
      :validation_error ->
        Logger.warning("Validation error: #{message}", details)
      
      :network_error ->
        Logger.error("Network error: #{message}", details)
      
      :resource_error ->
        Logger.error("Resource error: #{message}", details)
      
      :system_error ->
        Logger.error("System error: #{message}", details)
    end
  end
  
  def log_error(error) do
    Logger.error("Unknown error: #{inspect(error)}")
  end
end