defmodule RubberDuck.LLM.FallbackManager do
  @moduledoc """
  Fallback strategies for model availability and rate limits.
  Implements sophisticated fallback chains, circuit breakers, and retry
  mechanisms to ensure reliable LLM operations even during failures.
  """
  use GenServer
  require Logger


  defstruct [
    :fallback_chains,
    :circuit_breakers,
    :retry_strategies,
    :availability_monitor,
    :rate_limit_tracker,
    :fallback_metrics,
    :recovery_strategies
  ]

  @fallback_strategies [:sequential, :parallel, :intelligent, :cost_aware, :latency_optimized]
  @circuit_breaker_states [:closed, :open, :half_open]
  @retry_strategies [:exponential_backoff, :linear_backoff, :immediate, :fixed_interval]
  @failure_types [:rate_limit, :model_unavailable, :timeout, :api_error, :quota_exceeded]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Executes a task with automatic fallback if the primary model fails.
  """
  def execute_with_fallback(task, primary_model_id, context \\ %{}, opts \\ []) do
    GenServer.call(__MODULE__, {:execute_with_fallback, task, primary_model_id, context, opts}, 60_000)
  end

  @doc """
  Gets the fallback chain for a specific model.
  """
  def get_fallback_chain(model_id) do
    GenServer.call(__MODULE__, {:get_fallback_chain, model_id})
  end

  @doc """
  Updates the fallback chain for a model.
  """
  def update_fallback_chain(model_id, fallback_chain) do
    GenServer.call(__MODULE__, {:update_fallback_chain, model_id, fallback_chain})
  end

  @doc """
  Reports a model failure to update circuit breaker status.
  """
  def report_model_failure(model_id, failure_type, failure_details \\ %{}) do
    GenServer.cast(__MODULE__, {:report_failure, model_id, failure_type, failure_details})
  end

  @doc """
  Reports a successful model execution to update circuit breaker status.
  """
  def report_model_success(model_id, execution_details \\ %{}) do
    GenServer.cast(__MODULE__, {:report_success, model_id, execution_details})
  end

  @doc """
  Checks if a model is available based on circuit breaker status.
  """
  def check_model_availability(model_id) do
    GenServer.call(__MODULE__, {:check_availability, model_id})
  end

  @doc """
  Gets the current circuit breaker status for all models.
  """
  def get_circuit_breaker_status do
    GenServer.call(__MODULE__, :get_circuit_breaker_status)
  end

  @doc """
  Manually opens or closes a circuit breaker for a model.
  """
  def set_circuit_breaker_state(model_id, state) do
    GenServer.call(__MODULE__, {:set_circuit_breaker, model_id, state})
  end

  @doc """
  Gets fallback metrics and statistics.
  """
  def get_fallback_metrics do
    GenServer.call(__MODULE__, :get_fallback_metrics)
  end

  @doc """
  Configures retry strategies for different failure types.
  """
  def configure_retry_strategies(retry_config) do
    GenServer.call(__MODULE__, {:configure_retry, retry_config})
  end

  @doc """
  Triggers manual recovery for a model.
  """
  def trigger_model_recovery(model_id) do
    GenServer.call(__MODULE__, {:trigger_recovery, model_id})
  end

  @impl true
  def init(opts) do
    Logger.info("Starting LLM Fallback Manager with circuit breaker protection")
    
    state = %__MODULE__{
      fallback_chains: initialize_fallback_chains(opts),
      circuit_breakers: initialize_circuit_breakers(opts),
      retry_strategies: initialize_retry_strategies(opts),
      availability_monitor: initialize_availability_monitor(),
      rate_limit_tracker: initialize_rate_limit_tracker(),
      fallback_metrics: initialize_fallback_metrics(),
      recovery_strategies: initialize_recovery_strategies(opts)
    }
    
    # Start periodic availability monitoring
    schedule_availability_check()
    
    {:ok, state}
  end

  @impl true
  def handle_call({:execute_with_fallback, task, primary_model_id, context, opts}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    case perform_fallback_execution(task, primary_model_id, context, opts, state) do
      {:ok, execution_result} ->
        end_time = System.monotonic_time(:microsecond)
        execution_time = end_time - start_time
        
        new_metrics = update_fallback_metrics(state.fallback_metrics, execution_result, execution_time, :success)
        new_state = %{state | fallback_metrics: new_metrics}
        
        {:reply, {:ok, execution_result}, new_state}
      
      {:error, reason} ->
        new_metrics = update_fallback_metrics(state.fallback_metrics, nil, 0, :failure)
        new_state = %{state | fallback_metrics: new_metrics}
        
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call({:get_fallback_chain, model_id}, _from, state) do
    chain = Map.get(state.fallback_chains, model_id, [])
    {:reply, {:ok, chain}, state}
  end

  @impl true
  def handle_call({:update_fallback_chain, model_id, fallback_chain}, _from, state) do
    case validate_fallback_chain(fallback_chain) do
      :ok ->
        new_chains = Map.put(state.fallback_chains, model_id, fallback_chain)
        new_state = %{state | fallback_chains: new_chains}
        {:reply, {:ok, :chain_updated}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:check_availability, model_id}, _from, state) do
    availability = check_model_availability_internal(model_id, state)
    {:reply, {:ok, availability}, state}
  end

  @impl true
  def handle_call(:get_circuit_breaker_status, _from, state) do
    status = get_all_circuit_breaker_status(state.circuit_breakers)
    {:reply, {:ok, status}, state}
  end

  @impl true
  def handle_call({:set_circuit_breaker, model_id, breaker_state}, _from, state) do
    if breaker_state in @circuit_breaker_states do
      new_breakers = update_circuit_breaker_state(state.circuit_breakers, model_id, breaker_state)
      new_state = %{state | circuit_breakers: new_breakers}
      
      Logger.info("Circuit breaker for #{model_id} set to #{breaker_state}")
      {:reply, {:ok, :breaker_updated}, new_state}
    else
      {:reply, {:error, :invalid_state}, state}
    end
  end

  @impl true
  def handle_call(:get_fallback_metrics, _from, state) do
    enhanced_metrics = enhance_fallback_metrics(state.fallback_metrics, state)
    {:reply, enhanced_metrics, state}
  end

  @impl true
  def handle_call({:configure_retry, retry_config}, _from, state) do
    case validate_retry_config(retry_config) do
      :ok ->
        new_strategies = Map.merge(state.retry_strategies, retry_config)
        new_state = %{state | retry_strategies: new_strategies}
        {:reply, {:ok, :retry_configured}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:trigger_recovery, model_id}, _from, state) do
    case trigger_model_recovery_internal(model_id, state) do
      {:ok, recovery_result} ->
        new_state = update_recovery_state(state, model_id, recovery_result)
        {:reply, {:ok, recovery_result}, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:report_failure, model_id, failure_type, failure_details}, state) do
    new_state = process_model_failure(state, model_id, failure_type, failure_details)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:report_success, model_id, execution_details}, state) do
    new_state = process_model_success(state, model_id, execution_details)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:availability_check, state) do
    # Perform periodic availability monitoring
    new_state = perform_availability_monitoring(state)
    
    # Schedule next check
    schedule_availability_check()
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:circuit_breaker_half_open, model_id}, state) do
    # Transition circuit breaker to half-open state for testing
    new_breakers = update_circuit_breaker_state(state.circuit_breakers, model_id, :half_open)
    new_state = %{state | circuit_breakers: new_breakers}
    
    Logger.info("Circuit breaker for #{model_id} transitioned to half-open")
    {:noreply, new_state}
  end

  # Private functions

  defp perform_fallback_execution(task, primary_model_id, context, opts, state) do
    fallback_strategy = Keyword.get(opts, :fallback_strategy, :sequential)
    max_retries = Keyword.get(opts, :max_retries, 3)
    
    # Check primary model availability
    case check_model_availability_internal(primary_model_id, state) do
      %{available: true} ->
        # Try primary model first
        case execute_with_retry(task, primary_model_id, context, max_retries, state) do
          {:ok, result} ->
            {:ok, %{result: result, model_used: primary_model_id, fallback_used: false}}
          
          {:error, failure_reason} ->
            # Primary failed, try fallback chain
            Logger.warning("Primary model #{primary_model_id} failed: #{inspect(failure_reason)}")
            execute_fallback_chain(task, primary_model_id, context, fallback_strategy, opts, state)
        end
      
      %{available: false, reason: reason} ->
        Logger.warning("Primary model #{primary_model_id} unavailable: #{inspect(reason)}")
        execute_fallback_chain(task, primary_model_id, context, fallback_strategy, opts, state)
    end
  end

  defp execute_fallback_chain(task, primary_model_id, context, strategy, opts, state) do
    fallback_chain = Map.get(state.fallback_chains, primary_model_id, [])
    
    case fallback_chain do
      [] ->
        {:error, :no_fallback_available}
      
      chain ->
        case strategy do
          :sequential ->
            execute_sequential_fallback(task, chain, context, opts, state)
          
          :parallel ->
            execute_parallel_fallback(task, chain, context, opts, state)
          
          :intelligent ->
            execute_intelligent_fallback(task, chain, context, opts, state)
          
          :cost_aware ->
            execute_cost_aware_fallback(task, chain, context, opts, state)
          
          :latency_optimized ->
            execute_latency_optimized_fallback(task, chain, context, opts, state)
        end
    end
  end

  defp execute_sequential_fallback(task, chain, context, opts, state) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    
    Enum.reduce_while(chain, {:error, :all_models_failed}, fn model_id, _acc ->
      case check_model_availability_internal(model_id, state) do
        %{available: true} ->
          case execute_with_retry(task, model_id, context, max_retries, state) do
            {:ok, result} ->
              {:halt, {:ok, %{result: result, model_used: model_id, fallback_used: true}}}
            
            {:error, _failure_reason} ->
              {:cont, {:error, :model_failed}}
          end
        
        %{available: false} ->
          {:cont, {:error, :model_unavailable}}
      end
    end)
  end

  defp execute_parallel_fallback(task, chain, context, opts, state) do
    max_retries = Keyword.get(opts, :max_retries, 1)  # Reduced retries for parallel
    timeout = Keyword.get(opts, :parallel_timeout, 30_000)
    
    # Filter available models
    available_models = Enum.filter(chain, fn model_id ->
      case check_model_availability_internal(model_id, state) do
        %{available: true} -> true
        _ -> false
      end
    end)
    
    case available_models do
      [] ->
        {:error, :no_available_models}
      
      models ->
        # Execute in parallel
        tasks = Enum.map(models, fn model_id ->
          Task.async(fn ->
            execute_with_retry(task, model_id, context, max_retries, state)
          end)
        end)
        
        # Wait for first successful result
        case await_first_success(tasks, timeout) do
          {:ok, {result, model_id}} ->
            {:ok, %{result: result, model_used: model_id, fallback_used: true}}
          
          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp execute_intelligent_fallback(task, chain, context, opts, state) do
    # Analyze task and select best fallback model
    task_analysis = analyze_task_for_fallback(task, context)
    
    # Score and sort models based on task requirements
    scored_models = Enum.map(chain, fn model_id ->
      case check_model_availability_internal(model_id, state) do
        %{available: true} ->
          score = calculate_fallback_model_score(model_id, task_analysis, state)
          {model_id, score}
        
        %{available: false} ->
          {model_id, 0.0}
      end
    end)
    |> Enum.filter(fn {_model_id, score} -> score > 0 end)
    |> Enum.sort_by(fn {_model_id, score} -> score end, :desc)
    
    case scored_models do
      [] ->
        {:error, :no_suitable_fallback}
      
      [{best_model_id, _score} | _rest] ->
        max_retries = Keyword.get(opts, :max_retries, 3)
        
        case execute_with_retry(task, best_model_id, context, max_retries, state) do
          {:ok, result} ->
            {:ok, %{result: result, model_used: best_model_id, fallback_used: true, selection_reason: :intelligent}}
          
          {:error, reason} ->
            # Try remaining models sequentially
            remaining_models = Enum.map(scored_models, fn {model_id, _score} -> model_id end) |> tl()
            execute_sequential_fallback(task, remaining_models, context, opts, state)
        end
    end
  end

  defp execute_cost_aware_fallback(task, chain, context, opts, state) do
    # Sort models by cost efficiency for the task
    task_analysis = analyze_task_for_fallback(task, context)
    
    cost_sorted_models = Enum.map(chain, fn model_id ->
      case check_model_availability_internal(model_id, state) do
        %{available: true} ->
          cost_score = calculate_cost_efficiency_for_fallback(model_id, task_analysis, state)
          {model_id, cost_score}
        
        %{available: false} ->
          {model_id, 0.0}
      end
    end)
    |> Enum.filter(fn {_model_id, score} -> score > 0 end)
    |> Enum.sort_by(fn {_model_id, score} -> score end, :desc)
    
    case cost_sorted_models do
      [] ->
        {:error, :no_cost_effective_fallback}
      
      sorted_models ->
        model_ids = Enum.map(sorted_models, fn {model_id, _score} -> model_id end)
        execute_sequential_fallback(task, model_ids, context, opts, state)
    end
  end

  defp execute_latency_optimized_fallback(task, chain, context, opts, state) do
    # Sort models by expected latency
    latency_sorted_models = Enum.map(chain, fn model_id ->
      case check_model_availability_internal(model_id, state) do
        %{available: true} ->
          latency_score = calculate_latency_score_for_fallback(model_id, state)
          {model_id, latency_score}
        
        %{available: false} ->
          {model_id, 0.0}
      end
    end)
    |> Enum.filter(fn {_model_id, score} -> score > 0 end)
    |> Enum.sort_by(fn {_model_id, score} -> score end, :desc)  # Higher score = lower latency
    
    case latency_sorted_models do
      [] ->
        {:error, :no_low_latency_fallback}
      
      sorted_models ->
        model_ids = Enum.map(sorted_models, fn {model_id, _score} -> model_id end)
        execute_sequential_fallback(task, model_ids, context, opts, state)
    end
  end

  defp execute_with_retry(task, model_id, context, max_retries, state) do
    retry_strategy = get_retry_strategy_for_model(model_id, state)
    execute_with_retry_internal(task, model_id, context, retry_strategy, max_retries, 0)
  end

  defp execute_with_retry_internal(task, model_id, context, retry_strategy, max_retries, attempt) do
    case simulate_model_execution(task, model_id, context) do
      {:ok, result} ->
        {:ok, result}
      
      {:error, failure_reason} when attempt < max_retries ->
        # Calculate retry delay
        delay = calculate_retry_delay(retry_strategy, attempt)
        
        Logger.warning("Model #{model_id} failed (attempt #{attempt + 1}/#{max_retries + 1}): #{inspect(failure_reason)}, retrying in #{delay}ms")
        
        if delay > 0 do
          :timer.sleep(delay)
        end
        
        execute_with_retry_internal(task, model_id, context, retry_strategy, max_retries, attempt + 1)
      
      {:error, failure_reason} ->
        {:error, failure_reason}
    end
  end

  defp check_model_availability_internal(model_id, state) do
    circuit_breaker = Map.get(state.circuit_breakers, model_id, %{state: :closed})
    rate_limit_status = check_rate_limit_status(model_id, state.rate_limit_tracker)
    
    case {circuit_breaker.state, rate_limit_status} do
      {:open, _} ->
        %{available: false, reason: :circuit_breaker_open}
      
      {_, :rate_limited} ->
        %{available: false, reason: :rate_limited}
      
      {:half_open, _} ->
        %{available: true, reason: :testing, limited: true}
      
      {:closed, _} ->
        %{available: true, reason: :healthy}
    end
  end

  defp process_model_failure(state, model_id, failure_type, failure_details) do
    # Update circuit breaker
    new_breakers = update_circuit_breaker_on_failure(state.circuit_breakers, model_id, failure_type, failure_details)
    
    # Update rate limit tracking if applicable
    new_rate_tracker = if failure_type == :rate_limit do
      update_rate_limit_tracking(state.rate_limit_tracker, model_id, failure_details)
    else
      state.rate_limit_tracker
    end
    
    # Update availability monitoring
    new_monitor = update_availability_monitor_on_failure(state.availability_monitor, model_id, failure_type)
    
    # Update metrics
    new_metrics = update_failure_metrics(state.fallback_metrics, model_id, failure_type)
    
    %{state |
      circuit_breakers: new_breakers,
      rate_limit_tracker: new_rate_tracker,
      availability_monitor: new_monitor,
      fallback_metrics: new_metrics
    }
  end

  defp process_model_success(state, model_id, execution_details) do
    # Update circuit breaker
    new_breakers = update_circuit_breaker_on_success(state.circuit_breakers, model_id, execution_details)
    
    # Update availability monitoring
    new_monitor = update_availability_monitor_on_success(state.availability_monitor, model_id, execution_details)
    
    # Update metrics
    new_metrics = update_success_metrics(state.fallback_metrics, model_id)
    
    %{state |
      circuit_breakers: new_breakers,
      availability_monitor: new_monitor,
      fallback_metrics: new_metrics
    }
  end

  # Circuit breaker management

  defp update_circuit_breaker_on_failure(breakers, model_id, failure_type, failure_details) do
    current_breaker = Map.get(breakers, model_id, %{
      state: :closed,
      failure_count: 0,
      last_failure: nil,
      failure_threshold: 5,
      recovery_timeout: 60_000
    })
    
    new_failure_count = current_breaker.failure_count + 1
    new_state = if new_failure_count >= current_breaker.failure_threshold do
      # Open the circuit breaker
      schedule_circuit_breaker_recovery(model_id, current_breaker.recovery_timeout)
      :open
    else
      current_breaker.state
    end
    
    updated_breaker = %{current_breaker |
      failure_count: new_failure_count,
      last_failure: %{type: failure_type, details: failure_details, timestamp: System.monotonic_time(:millisecond)},
      state: new_state
    }
    
    Map.put(breakers, model_id, updated_breaker)
  end

  defp update_circuit_breaker_on_success(breakers, model_id, execution_details) do
    current_breaker = Map.get(breakers, model_id, %{state: :closed, failure_count: 0})
    
    case current_breaker.state do
      :half_open ->
        # Success in half-open state closes the circuit
        updated_breaker = %{current_breaker |
          state: :closed,
          failure_count: 0,
          last_success: %{details: execution_details, timestamp: System.monotonic_time(:millisecond)}
        }
        Map.put(breakers, model_id, updated_breaker)
      
      :closed ->
        # Reset failure count on success
        updated_breaker = %{current_breaker |
          failure_count: max(0, current_breaker.failure_count - 1),
          last_success: %{details: execution_details, timestamp: System.monotonic_time(:millisecond)}
        }
        Map.put(breakers, model_id, updated_breaker)
      
      :open ->
        # No change in open state
        breakers
    end
  end

  defp update_circuit_breaker_state(breakers, model_id, new_state) do
    current_breaker = Map.get(breakers, model_id, %{state: :closed, failure_count: 0})
    updated_breaker = %{current_breaker | state: new_state}
    Map.put(breakers, model_id, updated_breaker)
  end

  defp schedule_circuit_breaker_recovery(model_id, timeout) do
    Process.send_after(self(), {:circuit_breaker_half_open, model_id}, timeout)
  end

  # Helper functions

  defp await_first_success(tasks, timeout) do
    case Task.yield_many(tasks, timeout) do
      [] ->
        {:error, :all_tasks_timeout}
      
      results ->
        # Find first successful result
        case Enum.find(results, fn {_task, result} ->
          match?({:ok, {:ok, _}}, result)
        end) do
          {_task, {:ok, {:ok, result}}} ->
            {:ok, {result, "parallel_execution"}}
          
          _ ->
            {:error, :no_successful_result}
        end
    end
  end

  defp simulate_model_execution(task, model_id, context) do
    # Simulate execution with potential failures
    case :rand.uniform() do
      x when x < 0.1 -> {:error, :rate_limit}
      x when x < 0.15 -> {:error, :model_unavailable}
      x when x < 0.2 -> {:error, :timeout}
      _ -> {:ok, %{content: "Simulated response from #{model_id}", model_id: model_id}}
    end
  end

  defp calculate_retry_delay(strategy, attempt) do
    case strategy do
      :exponential_backoff ->
        min(30_000, round(:math.pow(2, attempt) * 1000))
      
      :linear_backoff ->
        (attempt + 1) * 1000
      
      :fixed_interval ->
        5000
      
      :immediate ->
        0
    end
  end

  # Initialization functions

  defp initialize_fallback_chains(opts) do
    default_chains = %{
      "gpt-4" => ["claude-3-opus", "gpt-3.5-turbo"],
      "claude-3-opus" => ["gpt-4", "gpt-3.5-turbo"],
      "gpt-3.5-turbo" => ["gpt-4", "claude-3-opus"]
    }
    
    custom_chains = Keyword.get(opts, :fallback_chains, %{})
    Map.merge(default_chains, custom_chains)
  end

  defp initialize_circuit_breakers(opts) do
    default_config = %{
      failure_threshold: Keyword.get(opts, :failure_threshold, 5),
      recovery_timeout: Keyword.get(opts, :recovery_timeout, 60_000)
    }
    
    Keyword.get(opts, :circuit_breakers, %{})
    |> Enum.into(%{}, fn {model_id, config} ->
      {model_id, Map.merge(default_config, config)}
    end)
  end

  defp initialize_retry_strategies(opts) do
    %{
      default: Keyword.get(opts, :default_retry_strategy, :exponential_backoff),
      rate_limit: :exponential_backoff,
      timeout: :linear_backoff,
      model_unavailable: :fixed_interval,
      api_error: :exponential_backoff
    }
  end

  defp initialize_availability_monitor do
    %{
      last_check: System.monotonic_time(:millisecond),
      model_status: %{},
      check_interval: 300_000  # 5 minutes
    }
  end

  defp initialize_rate_limit_tracker do
    %{
      rate_limits: %{},
      request_counts: %{},
      reset_times: %{}
    }
  end

  defp initialize_fallback_metrics do
    %{
      total_fallbacks: 0,
      successful_fallbacks: 0,
      failed_fallbacks: 0,
      fallback_by_reason: %{},
      avg_fallback_time: 0,
      model_failure_counts: %{}
    }
  end

  defp initialize_recovery_strategies(opts) do
    %{
      automatic_recovery: Keyword.get(opts, :automatic_recovery, true),
      health_check_interval: Keyword.get(opts, :health_check_interval, 300_000),
      recovery_attempts: Keyword.get(opts, :max_recovery_attempts, 3)
    }
  end

  # Utility and helper functions (simplified implementations)

  defp schedule_availability_check do
    Process.send_after(self(), :availability_check, 300_000)  # 5 minutes
  end

  defp perform_availability_monitoring(state) do
    # Check model health and update availability status
    Logger.debug("Performing availability monitoring")
    state
  end

  defp validate_fallback_chain(chain) do
    if is_list(chain) and Enum.all?(chain, &is_binary/1) do
      :ok
    else
      {:error, :invalid_chain_format}
    end
  end

  defp get_all_circuit_breaker_status(breakers) do
    Enum.map(breakers, fn {model_id, breaker} ->
      {model_id, %{
        state: breaker.state,
        failure_count: breaker.failure_count,
        last_failure: breaker[:last_failure],
        last_success: breaker[:last_success]
      }}
    end)
    |> Enum.into(%{})
  end

  defp validate_retry_config(config) do
    if is_map(config) do
      :ok
    else
      {:error, :invalid_retry_config}
    end
  end

  defp trigger_model_recovery_internal(model_id, state) do
    Logger.info("Triggering recovery for model #{model_id}")
    
    # Simulate recovery process
    case :rand.uniform() do
      x when x < 0.8 -> {:ok, %{recovered: true, model_id: model_id}}
      _ -> {:error, :recovery_failed}
    end
  end

  defp update_recovery_state(state, model_id, recovery_result) do
    # Update circuit breaker to closed if recovery successful
    if recovery_result.recovered do
      new_breakers = update_circuit_breaker_state(state.circuit_breakers, model_id, :closed)
      %{state | circuit_breakers: new_breakers}
    else
      state
    end
  end

  defp update_fallback_metrics(metrics, execution_result, execution_time, result_type) do
    case result_type do
      :success ->
        new_total = metrics.total_fallbacks + 1
        new_successful = metrics.successful_fallbacks + 1
        new_avg_time = (metrics.avg_fallback_time * metrics.total_fallbacks + execution_time) / new_total
        
        %{metrics |
          total_fallbacks: new_total,
          successful_fallbacks: new_successful,
          avg_fallback_time: new_avg_time
        }
      
      :failure ->
        %{metrics |
          total_fallbacks: metrics.total_fallbacks + 1,
          failed_fallbacks: metrics.failed_fallbacks + 1
        }
    end
  end

  defp enhance_fallback_metrics(metrics, state) do
    success_rate = if metrics.total_fallbacks > 0 do
      metrics.successful_fallbacks / metrics.total_fallbacks
    else
      0.0
    end
    
    Map.merge(metrics, %{
      success_rate: success_rate,
      active_circuit_breakers: count_active_circuit_breakers(state.circuit_breakers),
      configured_chains: map_size(state.fallback_chains)
    })
  end

  # Simplified helper implementations
  defp analyze_task_for_fallback(_task, _context), do: %{complexity: :medium, type: :general}
  defp calculate_fallback_model_score(_model_id, _analysis, _state), do: 0.8
  defp calculate_cost_efficiency_for_fallback(_model_id, _analysis, _state), do: 0.7
  defp calculate_latency_score_for_fallback(_model_id, _state), do: 0.9
  defp get_retry_strategy_for_model(_model_id, state), do: state.retry_strategies.default
  defp check_rate_limit_status(_model_id, _tracker), do: :ok
  defp update_rate_limit_tracking(tracker, _model_id, _details), do: tracker
  defp update_availability_monitor_on_failure(monitor, _model_id, _type), do: monitor
  defp update_availability_monitor_on_success(monitor, _model_id, _details), do: monitor
  defp update_failure_metrics(metrics, model_id, failure_type) do
    new_failure_count = Map.get(metrics.model_failure_counts, model_id, 0) + 1
    new_by_reason = Map.update(metrics.fallback_by_reason, failure_type, 1, &(&1 + 1))
    
    %{metrics |
      model_failure_counts: Map.put(metrics.model_failure_counts, model_id, new_failure_count),
      fallback_by_reason: new_by_reason
    }
  end
  defp update_success_metrics(metrics, _model_id), do: metrics
  defp count_active_circuit_breakers(breakers) do
    Enum.count(breakers, fn {_model_id, breaker} -> breaker.state != :closed end)
  end
end