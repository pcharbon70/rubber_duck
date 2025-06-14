defmodule RubberDuck.LoadBalancing.CircuitBreaker do
  @moduledoc """
  Circuit breaker implementation for provider health monitoring and fault tolerance.
  
  Implements the circuit breaker pattern to prevent cascading failures by
  monitoring provider health and automatically failing fast when providers
  are experiencing issues. Supports configurable failure thresholds,
  timeout periods, and gradual recovery testing.
  """
  
  use GenServer
  require Logger
  
  @type circuit_state :: :closed | :open | :half_open
  @type provider_circuit :: %{
    provider_id: term(),
    state: circuit_state(),
    failure_count: non_neg_integer(),
    success_count: non_neg_integer(),
    last_failure_time: non_neg_integer() | nil,
    last_success_time: non_neg_integer() | nil,
    half_open_start_time: non_neg_integer() | nil,
    config: circuit_config()
  }
  
  @type circuit_config :: %{
    failure_threshold: non_neg_integer(),
    success_threshold: non_neg_integer(),
    timeout_ms: non_neg_integer(),
    half_open_timeout_ms: non_neg_integer(),
    monitoring_window_ms: non_neg_integer()
  }
  
  @type call_result :: {:ok, term()} | {:error, term()}
  @type circuit_result :: 
    {:ok, term()} | 
    {:error, :circuit_open} | 
    {:error, :circuit_half_open_limit_exceeded} |
    {:error, term()}
  
  @default_config %{
    failure_threshold: 5,
    success_threshold: 3,
    timeout_ms: 60_000,
    half_open_timeout_ms: 30_000,
    monitoring_window_ms: 300_000  # 5 minutes
  }
  
  # Client API
  
  @doc """
  Start the CircuitBreaker GenServer.
  
  ## Examples
  
      {:ok, pid} = CircuitBreaker.start_link()
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Execute a function with circuit breaker protection.
  
  ## Examples
  
      result = CircuitBreaker.call(:openai_provider, fn ->
        # Make API call to provider
        SomeProvider.make_request(params)
      end)
      
      case result do
        {:ok, response} -> handle_success(response)
        {:error, :circuit_open} -> handle_circuit_open()
        {:error, reason} -> handle_error(reason)
      end
  """
  def call(provider_id, fun) when is_function(fun, 0) do
    GenServer.call(__MODULE__, {:execute_call, provider_id, fun})
  end
  
  @doc """
  Record a successful call for a provider.
  
  ## Examples
  
      :ok = CircuitBreaker.record_success(:openai_provider)
  """
  def record_success(provider_id) do
    GenServer.cast(__MODULE__, {:record_success, provider_id})
  end
  
  @doc """
  Record a failed call for a provider.
  
  ## Examples
  
      :ok = CircuitBreaker.record_failure(:openai_provider, :timeout)
  """
  def record_failure(provider_id, reason \\ :unknown) do
    GenServer.cast(__MODULE__, {:record_failure, provider_id, reason})
  end
  
  @doc """
  Get the current state of a provider's circuit breaker.
  
  ## Examples
  
      :closed = CircuitBreaker.get_state(:openai_provider)
      :open = CircuitBreaker.get_state(:failing_provider)
  """
  def get_state(provider_id) do
    GenServer.call(__MODULE__, {:get_state, provider_id})
  end
  
  @doc """
  Get detailed circuit breaker information for a provider.
  
  ## Examples
  
      info = CircuitBreaker.get_circuit_info(:openai_provider)
      # %{state: :closed, failure_count: 0, success_count: 10, ...}
  """
  def get_circuit_info(provider_id) do
    GenServer.call(__MODULE__, {:get_circuit_info, provider_id})
  end
  
  @doc """
  Manually open a circuit breaker (e.g., for maintenance).
  
  ## Examples
  
      :ok = CircuitBreaker.force_open(:openai_provider)
  """
  def force_open(provider_id) do
    GenServer.call(__MODULE__, {:force_open, provider_id})
  end
  
  @doc """
  Manually close a circuit breaker.
  
  ## Examples
  
      :ok = CircuitBreaker.force_close(:openai_provider)
  """
  def force_close(provider_id) do
    GenServer.call(__MODULE__, {:force_close, provider_id})
  end
  
  @doc """
  Update configuration for a provider's circuit breaker.
  
  ## Examples
  
      :ok = CircuitBreaker.update_config(:openai_provider, %{
        failure_threshold: 10,
        timeout_ms: 120_000
      })
  """
  def update_config(provider_id, config_updates) do
    GenServer.call(__MODULE__, {:update_config, provider_id, config_updates})
  end
  
  @doc """
  Get statistics for all circuit breakers.
  
  ## Examples
  
      stats = CircuitBreaker.get_stats()
      # %{
      #   total_circuits: 3,
      #   open_circuits: 1,
      #   half_open_circuits: 0,
      #   closed_circuits: 2,
      #   circuits: %{...}
      # }
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Get health scores for all providers.
  
  Returns a map of provider_id => health_score (0.0 to 1.0).
  
  ## Examples
  
      health = CircuitBreaker.get_health_scores()
      # %{openai_provider: 0.95, anthropic_provider: 0.87, failing_provider: 0.1}
  """
  def get_health_scores do
    GenServer.call(__MODULE__, :get_health_scores)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    default_config = Keyword.get(opts, :default_config, @default_config)
    cleanup_interval = Keyword.get(opts, :cleanup_interval, 60_000)
    
    state = %{
      circuits: %{},
      default_config: default_config,
      cleanup_timer: nil
    }
    
    # Schedule periodic cleanup
    timer = Process.send_after(self(), :cleanup, cleanup_interval)
    
    {:ok, %{state | cleanup_timer: timer}}
  end
  
  @impl true
  def handle_call({:execute_call, provider_id, fun}, _from, state) do
    circuit = get_or_create_circuit(provider_id, state)
    
    case check_circuit_state(circuit) do
      {:allow, updated_circuit} ->
        # Execute the function and record result
        start_time = System.monotonic_time(:millisecond)
        
        result = try do
          fun.()
        catch
          :error, reason -> {:error, reason}
          :exit, reason -> {:error, {:exit, reason}}
          :throw, reason -> {:error, {:throw, reason}}
        end
        
        execution_time = System.monotonic_time(:millisecond) - start_time
        
        {final_result, final_circuit} = case result do
          {:ok, value} ->
            new_circuit = record_success_internal(updated_circuit, execution_time)
            {{:ok, value}, new_circuit}
          
          {:error, reason} ->
            new_circuit = record_failure_internal(updated_circuit, reason, execution_time)
            {{:error, reason}, new_circuit}
        end
        
        updated_state = put_circuit(state, provider_id, final_circuit)
        {:reply, final_result, updated_state}
      
      {:deny, reason, updated_circuit} ->
        updated_state = put_circuit(state, provider_id, updated_circuit)
        {:reply, {:error, reason}, updated_state}
    end
  end
  
  @impl true
  def handle_call({:get_state, provider_id}, _from, state) do
    circuit = get_or_create_circuit(provider_id, state)
    {:reply, circuit.state, state}
  end
  
  @impl true
  def handle_call({:get_circuit_info, provider_id}, _from, state) do
    circuit = get_or_create_circuit(provider_id, state)
    
    info = %{
      state: circuit.state,
      failure_count: circuit.failure_count,
      success_count: circuit.success_count,
      last_failure_time: circuit.last_failure_time,
      last_success_time: circuit.last_success_time,
      config: circuit.config,
      health_score: calculate_health_score(circuit)
    }
    
    {:reply, info, state}
  end
  
  @impl true
  def handle_call({:force_open, provider_id}, _from, state) do
    circuit = get_or_create_circuit(provider_id, state)
    updated_circuit = %{circuit | state: :open, last_failure_time: System.monotonic_time(:millisecond)}
    updated_state = put_circuit(state, provider_id, updated_circuit)
    
    Logger.warn("Circuit breaker for #{provider_id} manually opened")
    {:reply, :ok, updated_state}
  end
  
  @impl true
  def handle_call({:force_close, provider_id}, _from, state) do
    circuit = get_or_create_circuit(provider_id, state)
    updated_circuit = %{circuit | 
      state: :closed, 
      failure_count: 0, 
      success_count: 0,
      last_success_time: System.monotonic_time(:millisecond)
    }
    updated_state = put_circuit(state, provider_id, updated_circuit)
    
    Logger.info("Circuit breaker for #{provider_id} manually closed")
    {:reply, :ok, updated_state}
  end
  
  @impl true
  def handle_call({:update_config, provider_id, config_updates}, _from, state) do
    circuit = get_or_create_circuit(provider_id, state)
    updated_config = Map.merge(circuit.config, config_updates)
    updated_circuit = %{circuit | config: updated_config}
    updated_state = put_circuit(state, provider_id, updated_circuit)
    
    Logger.info("Updated circuit breaker config for #{provider_id}: #{inspect(config_updates)}")
    {:reply, :ok, updated_state}
  end
  
  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = calculate_circuit_stats(state.circuits)
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:get_health_scores, _from, state) do
    health_scores = Map.new(state.circuits, fn {provider_id, circuit} ->
      {provider_id, calculate_health_score(circuit)}
    end)
    
    {:reply, health_scores, state}
  end
  
  @impl true
  def handle_cast({:record_success, provider_id}, state) do
    circuit = get_or_create_circuit(provider_id, state)
    updated_circuit = record_success_internal(circuit, 0)
    updated_state = put_circuit(state, provider_id, updated_circuit)
    
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_cast({:record_failure, provider_id, reason}, state) do
    circuit = get_or_create_circuit(provider_id, state)
    updated_circuit = record_failure_internal(circuit, reason, 0)
    updated_state = put_circuit(state, provider_id, updated_circuit)
    
    {:noreply, updated_state}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    # Perform periodic cleanup and state transitions
    updated_circuits = Map.new(state.circuits, fn {provider_id, circuit} ->
      {provider_id, maybe_transition_state(circuit)}
    end)
    
    updated_state = %{state | circuits: updated_circuits}
    
    # Schedule next cleanup
    timer = Process.send_after(self(), :cleanup, 60_000)
    
    {:noreply, %{updated_state | cleanup_timer: timer}}
  end
  
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  @impl true
  def terminate(_reason, state) do
    if state.cleanup_timer do
      Process.cancel_timer(state.cleanup_timer)
    end
    :ok
  end
  
  # Private Functions
  
  defp get_or_create_circuit(provider_id, state) do
    case Map.get(state.circuits, provider_id) do
      nil -> create_circuit(provider_id, state.default_config)
      circuit -> circuit
    end
  end
  
  defp create_circuit(provider_id, config) do
    %{
      provider_id: provider_id,
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil,
      last_success_time: nil,
      half_open_start_time: nil,
      config: config
    }
  end
  
  defp put_circuit(state, provider_id, circuit) do
    %{state | circuits: Map.put(state.circuits, provider_id, circuit)}
  end
  
  defp check_circuit_state(circuit) do
    current_time = System.monotonic_time(:millisecond)
    
    case circuit.state do
      :closed ->
        {:allow, circuit}
      
      :open ->
        if circuit.last_failure_time && 
           (current_time - circuit.last_failure_time) >= circuit.config.timeout_ms do
          # Transition to half-open
          updated_circuit = %{circuit | 
            state: :half_open, 
            half_open_start_time: current_time,
            success_count: 0
          }
          {:allow, updated_circuit}
        else
          {:deny, :circuit_open, circuit}
        end
      
      :half_open ->
        # Check if we've been in half-open too long
        if circuit.half_open_start_time &&
           (current_time - circuit.half_open_start_time) >= circuit.config.half_open_timeout_ms do
          # Reset to open if we've been half-open too long
          updated_circuit = %{circuit | 
            state: :open,
            last_failure_time: current_time,
            half_open_start_time: nil
          }
          {:deny, :circuit_half_open_timeout, updated_circuit}
        else
          {:allow, circuit}
        end
    end
  end
  
  defp record_success_internal(circuit, _execution_time) do
    current_time = System.monotonic_time(:millisecond)
    updated_circuit = %{circuit | 
      success_count: circuit.success_count + 1,
      last_success_time: current_time
    }
    
    case circuit.state do
      :closed ->
        # Reset failure count on success
        %{updated_circuit | failure_count: 0}
      
      :half_open ->
        if updated_circuit.success_count >= circuit.config.success_threshold do
          # Transition back to closed
          Logger.info("Circuit breaker for #{circuit.provider_id} transitioned from half-open to closed")
          %{updated_circuit | 
            state: :closed, 
            failure_count: 0,
            half_open_start_time: nil
          }
        else
          updated_circuit
        end
      
      :open ->
        # Shouldn't happen, but handle gracefully
        updated_circuit
    end
  end
  
  defp record_failure_internal(circuit, reason, _execution_time) do
    current_time = System.monotonic_time(:millisecond)
    updated_circuit = %{circuit | 
      failure_count: circuit.failure_count + 1,
      last_failure_time: current_time
    }
    
    case circuit.state do
      :closed ->
        if updated_circuit.failure_count >= circuit.config.failure_threshold do
          # Transition to open
          Logger.warn("Circuit breaker for #{circuit.provider_id} opened due to #{circuit.config.failure_threshold} failures. Last error: #{inspect(reason)}")
          %{updated_circuit | state: :open}
        else
          updated_circuit
        end
      
      :half_open ->
        # Any failure in half-open should return to open
        Logger.warn("Circuit breaker for #{circuit.provider_id} returned to open from half-open due to failure: #{inspect(reason)}")
        %{updated_circuit | 
          state: :open,
          half_open_start_time: nil
        }
      
      :open ->
        updated_circuit
    end
  end
  
  defp maybe_transition_state(circuit) do
    current_time = System.monotonic_time(:millisecond)
    
    case circuit.state do
      :open ->
        if circuit.last_failure_time && 
           (current_time - circuit.last_failure_time) >= circuit.config.timeout_ms do
          # Auto-transition to half-open
          %{circuit | 
            state: :half_open,
            half_open_start_time: current_time,
            success_count: 0
          }
        else
          circuit
        end
      
      :half_open ->
        if circuit.half_open_start_time &&
           (current_time - circuit.half_open_start_time) >= circuit.config.half_open_timeout_ms do
          # Timeout in half-open, return to open
          %{circuit | 
            state: :open,
            last_failure_time: current_time,
            half_open_start_time: nil
          }
        else
          circuit
        end
      
      _ ->
        circuit
    end
  end
  
  defp calculate_health_score(circuit) do
    current_time = System.monotonic_time(:millisecond)
    monitoring_window = circuit.config.monitoring_window_ms
    
    # Base score on current state
    base_score = case circuit.state do
      :closed -> 1.0
      :half_open -> 0.5
      :open -> 0.0
    end
    
    # Adjust based on recent success/failure ratio
    recent_activity_score = if circuit.last_success_time || circuit.last_failure_time do
      last_success = circuit.last_success_time || 0
      last_failure = circuit.last_failure_time || 0
      
      # Weight recent activity
      success_recency = if last_success > 0 do
        age = current_time - last_success
        max(0.0, 1.0 - (age / monitoring_window))
      else
        0.0
      end
      
      failure_recency = if last_failure > 0 do
        age = current_time - last_failure
        max(0.0, 1.0 - (age / monitoring_window))
      else
        0.0
      end
      
      # Success is good, recent failures are bad
      success_recency * 0.5 - failure_recency * 0.3
    else
      0.0
    end
    
    # Combine scores and clamp to [0.0, 1.0]
    final_score = base_score + recent_activity_score
    max(0.0, min(1.0, final_score))
  end
  
  defp calculate_circuit_stats(circuits) do
    states = Map.values(circuits) |> Enum.map(& &1.state)
    
    %{
      total_circuits: map_size(circuits),
      closed_circuits: Enum.count(states, &(&1 == :closed)),
      open_circuits: Enum.count(states, &(&1 == :open)),
      half_open_circuits: Enum.count(states, &(&1 == :half_open)),
      circuits: Map.new(circuits, fn {provider_id, circuit} ->
        {provider_id, %{
          state: circuit.state,
          failure_count: circuit.failure_count,
          success_count: circuit.success_count,
          health_score: calculate_health_score(circuit)
        }}
      end)
    }
  end
end