defmodule RubberDuck.Tool.Composition.ErrorHandler do
  @moduledoc """
  Error handling and compensation strategies for workflow steps.
  
  This module provides various error handling patterns that integrate with
  Reactor's compensation system:
  - Retry policies with exponential backoff
  - Fallback strategies
  - Compensation actions for rollback
  - Circuit breaker patterns
  """
  
  use RubberDuck.Workflows.Step
  
  require Logger
  
  @doc """
  Creates a retry step that wraps another step with retry logic.
  
  ## Options
  
  - `:max_attempts` - Maximum number of retry attempts (default: 3)
  - `:initial_delay` - Initial delay in milliseconds (default: 1000)
  - `:max_delay` - Maximum delay in milliseconds (default: 30000)
  - `:backoff_factor` - Exponential backoff factor (default: 2)
  - `:jitter` - Add jitter to delays (default: true)
  - `:retryable_errors` - List of retryable error types
  
  ## Example
  
      workflow = Composition.sequential("with_retry", [
        {:api_call, ErrorHandler.retry_step(ApiTool, %{endpoint: "/users"}), 
         max_attempts: 5, initial_delay: 500}
      ])
  """
  def retry_step(tool_module, params, opts \\ []) do
    {__MODULE__, [
      action: :retry,
      tool_module: tool_module,
      params: params,
      retry_opts: opts
    ]}
  end
  
  @doc """
  Creates a fallback step that tries an alternative on failure.
  
  ## Options
  
  - `:fallback_tool` - Alternative tool to use on failure
  - `:fallback_params` - Parameters for the fallback tool
  
  ## Example
  
      workflow = Composition.sequential("with_fallback", [
        {:api_call, ErrorHandler.fallback_step(PrimaryApi, %{}, 
          fallback_tool: BackupApi, fallback_params: %{mode: "backup"})}
      ])
  """
  def fallback_step(tool_module, params, opts \\ []) do
    {__MODULE__, [
      action: :fallback,
      tool_module: tool_module,
      params: params,
      fallback_opts: opts
    ]}
  end
  
  @doc """
  Creates a circuit breaker step that fails fast after repeated failures.
  
  ## Options
  
  - `:failure_threshold` - Number of failures before opening circuit (default: 5)
  - `:recovery_timeout` - Time before trying to close circuit (default: 60000)
  - `:half_open_attempts` - Attempts allowed in half-open state (default: 1)
  
  ## Example
  
      workflow = Composition.sequential("with_circuit_breaker", [
        {:api_call, ErrorHandler.circuit_breaker_step(ExternalApi, %{}, 
          failure_threshold: 3, recovery_timeout: 30000)}
      ])
  """
  def circuit_breaker_step(tool_module, params, opts \\ []) do
    {__MODULE__, [
      action: :circuit_breaker,
      tool_module: tool_module,
      params: params,
      circuit_opts: opts
    ]}
  end
  
  @doc """
  Executes the error handling step based on the configured action.
  """
  @impl true
  def run(arguments, context) do
    opts = context[:options] || []
    action = Keyword.get(opts, :action, :retry)
    
    case action do
      :retry ->
        handle_retry(arguments, context, opts)
        
      :fallback ->
        handle_fallback(arguments, context, opts)
        
      :circuit_breaker ->
        handle_circuit_breaker(arguments, context, opts)
        
      _ ->
        {:error, {:invalid_error_handler_action, action}}
    end
  end
  
  @doc """
  Provides compensation for error handling steps.
  """
  @impl true
  def compensate(arguments, result, context) do
    opts = context[:options] || []
    tool_module = Keyword.get(opts, :tool_module)
    
    if tool_module && function_exported?(tool_module, :compensate, 3) do
      tool_module.compensate(arguments, result, context)
    else
      :ok
    end
  end
  
  # Private implementation functions
  
  defp handle_retry(arguments, context, opts) do
    tool_module = Keyword.fetch!(opts, :tool_module)
    params = Keyword.get(opts, :params, %{})
    retry_opts = Keyword.get(opts, :retry_opts, [])
    
    max_attempts = Keyword.get(retry_opts, :max_attempts, 3)
    initial_delay = Keyword.get(retry_opts, :initial_delay, 1000)
    max_delay = Keyword.get(retry_opts, :max_delay, 30_000)
    backoff_factor = Keyword.get(retry_opts, :backoff_factor, 2)
    jitter = Keyword.get(retry_opts, :jitter, true)
    retryable_errors = Keyword.get(retry_opts, :retryable_errors, default_retryable_errors())
    
    # Merge arguments with params
    merged_params = Map.merge(params, arguments)
    
    # Execute with retry
    execute_with_retry(tool_module, merged_params, context, 1, max_attempts, 
                     initial_delay, max_delay, backoff_factor, jitter, retryable_errors)
  end
  
  defp handle_fallback(arguments, context, opts) do
    tool_module = Keyword.fetch!(opts, :tool_module)
    params = Keyword.get(opts, :params, %{})
    fallback_opts = Keyword.get(opts, :fallback_opts, [])
    
    fallback_tool = Keyword.get(fallback_opts, :fallback_tool)
    fallback_params = Keyword.get(fallback_opts, :fallback_params, %{})
    
    # Merge arguments with params
    merged_params = Map.merge(params, arguments)
    
    # Try primary tool first
    case execute_tool(tool_module, merged_params, context) do
      {:ok, result} ->
        {:ok, result}
        
      {:error, error} ->
        Logger.warning("Primary tool #{tool_module} failed: #{inspect(error)}, trying fallback")
        
        if fallback_tool do
          # Try fallback tool
          fallback_merged_params = Map.merge(fallback_params, arguments)
          case execute_tool(fallback_tool, fallback_merged_params, context) do
            {:ok, result} ->
              Logger.info("Fallback tool #{fallback_tool} succeeded")
              {:ok, result}
              
            {:error, fallback_error} ->
              Logger.error("Fallback tool #{fallback_tool} also failed: #{inspect(fallback_error)}")
              {:error, {:fallback_failed, error, fallback_error}}
          end
        else
          {:error, error}
        end
    end
  end
  
  defp handle_circuit_breaker(arguments, context, opts) do
    tool_module = Keyword.fetch!(opts, :tool_module)
    params = Keyword.get(opts, :params, %{})
    circuit_opts = Keyword.get(opts, :circuit_opts, [])
    
    failure_threshold = Keyword.get(circuit_opts, :failure_threshold, 5)
    recovery_timeout = Keyword.get(circuit_opts, :recovery_timeout, 60_000)
    half_open_attempts = Keyword.get(circuit_opts, :half_open_attempts, 1)
    
    # Use tool module name as circuit breaker key
    circuit_key = tool_module
    
    # Check circuit breaker state
    case get_circuit_state(circuit_key) do
      :closed ->
        # Circuit is closed, try execution
        merged_params = Map.merge(params, arguments)
        case execute_tool(tool_module, merged_params, context) do
          {:ok, result} ->
            # Success - reset failure count
            reset_circuit_failures(circuit_key)
            {:ok, result}
            
          {:error, error} ->
            # Failure - increment failure count
            failure_count = increment_circuit_failures(circuit_key)
            
            if failure_count >= failure_threshold do
              # Open the circuit
              open_circuit(circuit_key, recovery_timeout)
              Logger.warning("Circuit breaker opened for #{tool_module} after #{failure_count} failures")
            end
            
            {:error, error}
        end
        
      :open ->
        # Circuit is open, check if recovery timeout has passed
        if circuit_recovery_ready?(circuit_key) do
          # Move to half-open state
          set_circuit_half_open(circuit_key, half_open_attempts)
          Logger.info("Circuit breaker for #{tool_module} moved to half-open state")
          
          # Try execution
          merged_params = Map.merge(params, arguments)
          case execute_tool(tool_module, merged_params, context) do
            {:ok, result} ->
              # Success - close the circuit
              close_circuit(circuit_key)
              Logger.info("Circuit breaker for #{tool_module} closed after successful recovery")
              {:ok, result}
              
            {:error, error} ->
              # Failure - back to open state
              open_circuit(circuit_key, recovery_timeout)
              Logger.warning("Circuit breaker for #{tool_module} back to open state after recovery failure")
              {:error, {:circuit_open, error}}
          end
        else
          # Still in recovery period
          {:error, {:circuit_open, "Circuit breaker is open"}}
        end
        
      :half_open ->
        # Circuit is half-open, limited attempts allowed
        if circuit_half_open_attempts_remaining?(circuit_key) do
          # Decrement attempts and try execution
          decrement_circuit_half_open_attempts(circuit_key)
          
          merged_params = Map.merge(params, arguments)
          case execute_tool(tool_module, merged_params, context) do
            {:ok, result} ->
              # Success - close the circuit
              close_circuit(circuit_key)
              Logger.info("Circuit breaker for #{tool_module} closed after half-open success")
              {:ok, result}
              
            {:error, error} ->
              # Failure - back to open state
              open_circuit(circuit_key, recovery_timeout)
              Logger.warning("Circuit breaker for #{tool_module} back to open state after half-open failure")
              {:error, {:circuit_open, error}}
          end
        else
          # No more attempts allowed in half-open state
          {:error, {:circuit_open, "No more half-open attempts"}}
        end
    end
  end
  
  defp execute_with_retry(tool_module, params, context, attempt, max_attempts, 
                         initial_delay, max_delay, backoff_factor, jitter, retryable_errors) do
    case execute_tool(tool_module, params, context) do
      {:ok, result} ->
        {:ok, result}
        
      {:error, error} ->
        if attempt >= max_attempts do
          Logger.error("Tool #{tool_module} failed after #{attempt} attempts: #{inspect(error)}")
          {:error, {:max_retries_exceeded, error}}
        else
          if error_retryable?(error, retryable_errors) do
            # Calculate delay with exponential backoff
            delay = calculate_retry_delay(attempt, initial_delay, max_delay, backoff_factor, jitter)
            
            Logger.warning("Tool #{tool_module} failed on attempt #{attempt}, retrying in #{delay}ms: #{inspect(error)}")
            
            # Sleep before retry
            Process.sleep(delay)
            
            # Retry
            execute_with_retry(tool_module, params, context, attempt + 1, max_attempts,
                             initial_delay, max_delay, backoff_factor, jitter, retryable_errors)
          else
            Logger.error("Tool #{tool_module} failed with non-retryable error: #{inspect(error)}")
            {:error, {:non_retryable_error, error}}
          end
        end
    end
  end
  
  defp execute_tool(tool_module, params, context) do
    if function_exported?(tool_module, :execute, 2) do
      tool_module.execute(params, context)
    else
      if function_exported?(tool_module, :execute, 1) do
        tool_module.execute(params)
      else
        {:error, {:tool_error, "Tool #{tool_module} does not implement execute/1 or execute/2"}}
      end
    end
  end
  
  defp calculate_retry_delay(attempt, initial_delay, max_delay, backoff_factor, jitter) do
    # Calculate exponential backoff
    delay = initial_delay * :math.pow(backoff_factor, attempt - 1)
    delay = min(delay, max_delay)
    
    # Add jitter to prevent thundering herd
    if jitter do
      jitter_amount = delay * 0.1
      delay + :rand.uniform() * jitter_amount
    else
      delay
    end
    |> round()
  end
  
  defp error_retryable?(error, retryable_errors) do
    case error do
      # Check if error matches any of the retryable error patterns
      {:error, error_type} -> Enum.member?(retryable_errors, error_type)
      {:http_error, status} when status in 500..599 -> true
      error_type -> Enum.member?(retryable_errors, error_type)
    end
  end
  
  defp default_retryable_errors do
    [
      :timeout,
      :connection_refused,
      :network_unreachable,
      :rate_limited,
      :quota_exceeded,
      :resource_busy,
      :deadlock
    ]
  end
  
  # Circuit breaker state management (simplified in-memory implementation)
  # In production, this would use a distributed cache or database
  
  defp get_circuit_state(circuit_key) do
    case :ets.lookup(:circuit_breaker_states, circuit_key) do
      [{^circuit_key, state}] -> state
      [] -> :closed
    end
  end
  
  defp open_circuit(circuit_key, recovery_timeout) do
    ensure_circuit_breaker_table()
    recovery_time = System.monotonic_time(:millisecond) + recovery_timeout
    :ets.insert(:circuit_breaker_states, {circuit_key, :open})
    :ets.insert(:circuit_breaker_recovery, {circuit_key, recovery_time})
  end
  
  defp close_circuit(circuit_key) do
    ensure_circuit_breaker_table()
    :ets.insert(:circuit_breaker_states, {circuit_key, :closed})
    :ets.delete(:circuit_breaker_failures, circuit_key)
    :ets.delete(:circuit_breaker_recovery, circuit_key)
    :ets.delete(:circuit_breaker_half_open, circuit_key)
  end
  
  defp set_circuit_half_open(circuit_key, attempts) do
    ensure_circuit_breaker_table()
    :ets.insert(:circuit_breaker_states, {circuit_key, :half_open})
    :ets.insert(:circuit_breaker_half_open, {circuit_key, attempts})
  end
  
  defp circuit_recovery_ready?(circuit_key) do
    case :ets.lookup(:circuit_breaker_recovery, circuit_key) do
      [{^circuit_key, recovery_time}] ->
        System.monotonic_time(:millisecond) >= recovery_time
      [] ->
        false
    end
  end
  
  defp circuit_half_open_attempts_remaining?(circuit_key) do
    case :ets.lookup(:circuit_breaker_half_open, circuit_key) do
      [{^circuit_key, attempts}] -> attempts > 0
      [] -> false
    end
  end
  
  defp decrement_circuit_half_open_attempts(circuit_key) do
    case :ets.lookup(:circuit_breaker_half_open, circuit_key) do
      [{^circuit_key, attempts}] when attempts > 0 ->
        :ets.insert(:circuit_breaker_half_open, {circuit_key, attempts - 1})
      _ ->
        :ok
    end
  end
  
  defp increment_circuit_failures(circuit_key) do
    ensure_circuit_breaker_table()
    case :ets.lookup(:circuit_breaker_failures, circuit_key) do
      [{^circuit_key, count}] ->
        new_count = count + 1
        :ets.insert(:circuit_breaker_failures, {circuit_key, new_count})
        new_count
      [] ->
        :ets.insert(:circuit_breaker_failures, {circuit_key, 1})
        1
    end
  end
  
  defp reset_circuit_failures(circuit_key) do
    ensure_circuit_breaker_table()
    :ets.delete(:circuit_breaker_failures, circuit_key)
  end
  
  defp ensure_circuit_breaker_table do
    tables = [
      :circuit_breaker_states,
      :circuit_breaker_failures,
      :circuit_breaker_recovery,
      :circuit_breaker_half_open
    ]
    
    Enum.each(tables, fn table ->
      case :ets.whereis(table) do
        :undefined ->
          :ets.new(table, [:set, :public, :named_table])
        _ ->
          :ok
      end
    end)
  end
end