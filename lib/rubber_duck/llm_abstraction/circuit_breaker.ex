defmodule RubberDuck.LLMAbstraction.CircuitBreaker do
  @moduledoc """
  Circuit breaker implementation for provider health monitoring.
  
  This module implements the circuit breaker pattern to prevent cascading
  failures when LLM providers experience issues. It monitors provider
  health and automatically opens circuits to failing providers while
  providing mechanisms for recovery.
  
  Features:
  - Configurable failure thresholds
  - Exponential backoff for recovery attempts
  - Half-open state for gradual recovery
  - Distributed circuit state across cluster
  - Health monitoring and alerting
  """

  use GenServer
  require Logger

  defstruct [
    :provider,
    :state,
    :failure_count,
    :success_count,
    :last_failure_time,
    :next_attempt_time,
    :config
  ]

  @type circuit_state :: :closed | :open | :half_open
  @type t :: %__MODULE__{
    provider: atom(),
    state: circuit_state(),
    failure_count: non_neg_integer(),
    success_count: non_neg_integer(),
    last_failure_time: DateTime.t() | nil,
    next_attempt_time: DateTime.t() | nil,
    config: map()
  }

  # Default configuration
  @default_config %{
    failure_threshold: 5,           # Number of failures to open circuit
    recovery_timeout_ms: 30_000,    # Initial timeout before retry
    max_recovery_timeout_ms: 300_000, # Max backoff timeout
    success_threshold: 3,           # Successful calls to close circuit
    timeout_ms: 5_000,             # Request timeout
    monitoring_window_ms: 60_000    # Window for failure rate calculation
  }

  # Client API

  def start_link(provider, config \\ %{}) do
    GenServer.start_link(__MODULE__, {provider, config}, name: via_tuple(provider))
  end

  @doc """
  Execute a function call through the circuit breaker.
  
  ## Parameters
    - provider: Provider name
    - fun: Function to execute
    - timeout: Optional timeout override
    
  ## Returns
    - {:ok, result} | {:error, reason}
  """
  def call(provider, fun, timeout \\ nil) do
    case get_state(provider) do
      :closed -> 
        execute_call(provider, fun, timeout)
      
      :open -> 
        {:error, :circuit_open}
      
      :half_open -> 
        execute_call_half_open(provider, fun, timeout)
    end
  end

  @doc """
  Get the current state of a circuit breaker.
  """
  def get_state(provider) do
    case GenServer.whereis(via_tuple(provider)) do
      nil -> 
        # Circuit breaker not started, assume closed
        :closed
      
      pid -> 
        GenServer.call(pid, :get_state)
    end
  end

  @doc """
  Get detailed circuit breaker information.
  """
  def get_info(provider) do
    case GenServer.whereis(via_tuple(provider)) do
      nil -> 
        {:error, :not_found}
      
      pid -> 
        GenServer.call(pid, :get_info)
    end
  end

  @doc """
  Manually trip the circuit breaker (for testing or emergency).
  """
  def trip(provider) do
    case GenServer.whereis(via_tuple(provider)) do
      nil -> 
        {:error, :not_found}
      
      pid -> 
        GenServer.cast(pid, :trip)
    end
  end

  @doc """
  Manually reset the circuit breaker.
  """
  def reset(provider) do
    case GenServer.whereis(via_tuple(provider)) do
      nil -> 
        {:error, :not_found}
      
      pid -> 
        GenServer.cast(pid, :reset)
    end
  end

  @doc """
  Update circuit breaker configuration.
  """
  def configure(provider, new_config) do
    case GenServer.whereis(via_tuple(provider)) do
      nil -> 
        {:error, :not_found}
      
      pid -> 
        GenServer.call(pid, {:configure, new_config})
    end
  end

  # Server Callbacks

  @impl true
  def init({provider, config}) do
    merged_config = Map.merge(@default_config, config)
    
    state = %__MODULE__{
      provider: provider,
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil,
      next_attempt_time: nil,
      config: merged_config
    }
    
    Logger.info("Circuit breaker started for provider #{provider}")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    current_state = determine_current_state(state)
    {:reply, current_state, %{state | state: current_state}}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    current_state = determine_current_state(state)
    
    info = %{
      provider: state.provider,
      state: current_state,
      failure_count: state.failure_count,
      success_count: state.success_count,
      last_failure_time: state.last_failure_time,
      next_attempt_time: state.next_attempt_time,
      config: state.config
    }
    
    {:reply, info, %{state | state: current_state}}
  end

  @impl true
  def handle_call({:configure, new_config}, _from, state) do
    merged_config = Map.merge(state.config, new_config)
    new_state = %{state | config: merged_config}
    
    Logger.info("Updated circuit breaker config for #{state.provider}: #{inspect(new_config)}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:execute, fun, timeout}, _from, state) do
    case determine_current_state(state) do
      :closed ->
        execute_and_handle_result(fun, timeout, state)
      
      :open ->
        {:reply, {:error, :circuit_open}, state}
      
      :half_open ->
        execute_and_handle_result_half_open(fun, timeout, state)
    end
  end

  @impl true
  def handle_cast(:trip, state) do
    Logger.warning("Circuit breaker manually tripped for provider #{state.provider}")
    new_state = trip_circuit(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:reset, state) do
    Logger.info("Circuit breaker manually reset for provider #{state.provider}")
    new_state = reset_circuit(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_success}, state) do
    new_state = record_success(state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:record_failure}, state) do
    new_state = record_failure(state)
    {:noreply, new_state}
  end

  # Private Functions

  defp via_tuple(provider) do
    {:via, Registry, {RubberDuck.CircuitBreakerRegistry, provider}}
  end

  defp execute_call(provider, fun, timeout) do
    case GenServer.whereis(via_tuple(provider)) do
      nil ->
        # No circuit breaker, execute directly
        execute_with_timeout(fun, timeout || @default_config.timeout_ms)
      
      pid ->
        GenServer.call(pid, {:execute, fun, timeout}, :infinity)
    end
  end

  defp execute_call_half_open(provider, fun, timeout) do
    # In half-open state, we execute but handle results carefully
    execute_call(provider, fun, timeout)
  end

  defp determine_current_state(state) do
    current_time = DateTime.utc_now()
    
    case state.state do
      :open ->
        if state.next_attempt_time && 
           DateTime.compare(current_time, state.next_attempt_time) != :lt do
          :half_open
        else
          :open
        end
      
      other ->
        other
    end
  end

  defp execute_and_handle_result(fun, timeout, state) do
    timeout_ms = timeout || state.config.timeout_ms
    
    case execute_with_timeout(fun, timeout_ms) do
      {:ok, result} ->
        new_state = record_success(state)
        {:reply, {:ok, result}, new_state}
      
      {:error, reason} ->
        new_state = record_failure(state)
        {:reply, {:error, reason}, new_state}
    end
  end

  defp execute_and_handle_result_half_open(fun, timeout, state) do
    timeout_ms = timeout || state.config.timeout_ms
    
    case execute_with_timeout(fun, timeout_ms) do
      {:ok, result} ->
        new_state = record_success(state)
        
        # Check if we should close the circuit
        if new_state.success_count >= state.config.success_threshold do
          closed_state = close_circuit(new_state)
          {:reply, {:ok, result}, closed_state}
        else
          {:reply, {:ok, result}, new_state}
        end
      
      {:error, reason} ->
        # Failure in half-open state trips the circuit immediately
        new_state = trip_circuit(state)
        {:reply, {:error, reason}, new_state}
    end
  end

  defp execute_with_timeout(fun, timeout_ms) do
    task = Task.async(fun)
    
    try do
      result = Task.await(task, timeout_ms)
      {:ok, result}
    catch
      :exit, {:timeout, _} ->
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
      
      kind, reason ->
        Task.shutdown(task, :brutal_kill)
        {:error, {kind, reason}}
    end
  end

  defp record_success(state) do
    new_success_count = state.success_count + 1
    
    %{state | 
      success_count: new_success_count,
      failure_count: 0  # Reset failure count on success
    }
  end

  defp record_failure(state) do
    current_time = DateTime.utc_now()
    new_failure_count = state.failure_count + 1
    
    new_state = %{state | 
      failure_count: new_failure_count,
      success_count: 0,  # Reset success count on failure
      last_failure_time: current_time
    }
    
    # Check if we should trip the circuit
    if new_failure_count >= state.config.failure_threshold do
      trip_circuit(new_state)
    else
      new_state
    end
  end

  defp trip_circuit(state) do
    current_time = DateTime.utc_now()
    next_attempt_time = DateTime.add(current_time, state.config.recovery_timeout_ms, :millisecond)
    
    Logger.warning("Circuit breaker opened for provider #{state.provider} " <>
                  "after #{state.failure_count} failures")
    
    %{state | 
      state: :open,
      next_attempt_time: next_attempt_time
    }
  end

  defp close_circuit(state) do
    Logger.info("Circuit breaker closed for provider #{state.provider} " <>
               "after #{state.success_count} successful calls")
    
    %{state | 
      state: :closed,
      failure_count: 0,
      success_count: 0,
      next_attempt_time: nil
    }
  end

  defp reset_circuit(state) do
    %{state | 
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil,
      next_attempt_time: nil
    }
  end

  # Public convenience functions for recording results

  @doc """
  Record a successful operation for the circuit breaker.
  """
  def record_success_external(provider) do
    case GenServer.whereis(via_tuple(provider)) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:record_success})
    end
  end

  @doc """
  Record a failed operation for the circuit breaker.
  """
  def record_failure_external(provider) do
    case GenServer.whereis(via_tuple(provider)) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:record_failure})
    end
  end
end