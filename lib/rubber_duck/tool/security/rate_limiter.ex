defmodule RubberDuck.Tool.Security.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for tool execution.
  
  Features:
  - Per user/tool rate limiting
  - Adaptive rate limiting based on resource usage
  - Priority queues for different user tiers
  - Circuit breakers for failing tools
  """
  
  use GenServer
  
  require Logger
  
  @type bucket_key :: {user_id :: String.t(), tool :: atom()}
  @type bucket :: %{
    tokens: float(),
    max_tokens: pos_integer(),
    refill_rate: pos_integer(),
    last_refill: integer(),
    priority: :low | :normal | :high
  }
  
  @type circuit_state :: :closed | :open | :half_open
  
  @default_bucket_config %{
    max_tokens: 10,
    refill_rate: 1,  # tokens per second
    priority: :normal
  }
  
  @circuit_breaker_config %{
    failure_threshold: 5,
    success_threshold: 3,
    timeout_ms: 60_000,  # 1 minute
    half_open_requests: 1
  }
  
  # Client API
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Attempts to acquire tokens for a tool execution.
  
  Returns :ok if tokens available, {:error, :rate_limited} otherwise.
  """
  def acquire(user_id, tool, tokens \\ 1) do
    GenServer.call(__MODULE__, {:acquire, user_id, tool, tokens})
  end
  
  @doc """
  Checks if tokens are available without consuming them.
  """
  def check_available(user_id, tool, tokens \\ 1) do
    GenServer.call(__MODULE__, {:check_available, user_id, tool, tokens})
  end
  
  @doc """
  Records a tool execution result for circuit breaker tracking.
  """
  def record_result(user_id, tool, :success) do
    GenServer.cast(__MODULE__, {:record_success, user_id, tool})
  end
  
  def record_result(user_id, tool, :failure) do
    GenServer.cast(__MODULE__, {:record_failure, user_id, tool})
  end
  
  @doc """
  Updates rate limit configuration for a user/tool combination.
  """
  def update_limits(user_id, tool, config) do
    GenServer.call(__MODULE__, {:update_limits, user_id, tool, config})
  end
  
  @doc """
  Sets user priority tier.
  """
  def set_user_priority(user_id, priority) when priority in [:low, :normal, :high] do
    GenServer.call(__MODULE__, {:set_priority, user_id, priority})
  end
  
  @doc """
  Gets current rate limiter statistics.
  """
  def get_stats(user_id \\ nil, tool \\ nil) do
    GenServer.call(__MODULE__, {:get_stats, user_id, tool})
  end
  
  @doc """
  Resets rate limits for a user/tool combination.
  """
  def reset(user_id, tool) do
    GenServer.call(__MODULE__, {:reset, user_id, tool})
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Create ETS tables
    :ets.new(:rate_limiter_buckets, [:set, :public, :named_table, {:read_concurrency, true}])
    :ets.new(:circuit_breakers, [:set, :public, :named_table])
    :ets.new(:user_priorities, [:set, :public, :named_table])
    
    state = %{
      default_config: Keyword.get(opts, :default_config, @default_bucket_config),
      circuit_config: Keyword.get(opts, :circuit_config, @circuit_breaker_config),
      adaptive_limiting: Keyword.get(opts, :adaptive_limiting, true)
    }
    
    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup, 60_000)
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:acquire, user_id, tool, requested_tokens}, _from, state) do
    key = {user_id, tool}
    
    # Check circuit breaker first
    case check_circuit_breaker(key, state) do
      :open ->
        {:reply, {:error, :circuit_open}, state}
        
      circuit_state ->
        # Get or create bucket
        bucket = get_or_create_bucket(key, user_id, state)
        
        # Refill tokens based on time elapsed
        current_time = System.monotonic_time(:millisecond)
        bucket = refill_bucket(bucket, current_time)
        
        # Apply priority-based multiplier
        effective_tokens = requested_tokens / priority_multiplier(bucket.priority)
        
        # Check if enough tokens available
        if bucket.tokens >= effective_tokens do
          # Consume tokens
          updated_bucket = %{bucket | tokens: bucket.tokens - effective_tokens}
          :ets.insert(:rate_limiter_buckets, {key, updated_bucket})
          
          # Update circuit breaker state if half-open
          if circuit_state == :half_open do
            update_circuit_breaker_attempt(key)
          end
          
          {:reply, :ok, state}
        else
          # Not enough tokens
          {:reply, {:error, :rate_limited}, state}
        end
    end
  end
  
  @impl true
  def handle_call({:check_available, user_id, tool, requested_tokens}, _from, state) do
    key = {user_id, tool}
    
    case check_circuit_breaker(key, state) do
      :open ->
        {:reply, false, state}
        
      _ ->
        bucket = get_or_create_bucket(key, user_id, state)
        current_time = System.monotonic_time(:millisecond)
        bucket = refill_bucket(bucket, current_time)
        
        effective_tokens = requested_tokens / priority_multiplier(bucket.priority)
        available = bucket.tokens >= effective_tokens
        
        {:reply, available, state}
    end
  end
  
  @impl true
  def handle_call({:update_limits, user_id, tool, config}, _from, state) do
    key = {user_id, tool}
    bucket = get_or_create_bucket(key, user_id, state)
    
    updated_bucket = Map.merge(bucket, config)
    :ets.insert(:rate_limiter_buckets, {key, updated_bucket})
    
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call({:set_priority, user_id, priority}, _from, state) do
    :ets.insert(:user_priorities, {user_id, priority})
    
    # Update all existing buckets for this user
    update_user_buckets_priority(user_id, priority)
    
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_call({:get_stats, user_id, tool}, _from, state) do
    stats = compile_stats(user_id, tool)
    {:reply, {:ok, stats}, state}
  end
  
  @impl true
  def handle_call({:reset, user_id, tool}, _from, state) do
    key = {user_id, tool}
    
    # Reset bucket
    :ets.delete(:rate_limiter_buckets, key)
    
    # Reset circuit breaker
    :ets.delete(:circuit_breakers, key)
    
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_cast({:record_success, user_id, tool}, state) do
    key = {user_id, tool}
    update_circuit_breaker(key, :success, state)
    
    # Adaptive rate limiting - increase limit on consistent success
    if state.adaptive_limiting do
      adapt_rate_limit(key, :success)
    end
    
    {:noreply, state}
  end
  
  @impl true
  def handle_cast({:record_failure, user_id, tool}, state) do
    key = {user_id, tool}
    update_circuit_breaker(key, :failure, state)
    
    # Adaptive rate limiting - decrease limit on failures
    if state.adaptive_limiting do
      adapt_rate_limit(key, :failure)
    end
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    # Remove old, unused buckets
    cleanup_old_buckets()
    
    # Schedule next cleanup
    Process.send_after(self(), :cleanup, 60_000)
    
    {:noreply, state}
  end
  
  # Private functions
  
  defp get_or_create_bucket(key, user_id, state) do
    case :ets.lookup(:rate_limiter_buckets, key) do
      [{^key, bucket}] -> 
        bucket
        
      [] ->
        # Get user priority
        priority = case :ets.lookup(:user_priorities, user_id) do
          [{^user_id, p}] -> p
          [] -> :normal
        end
        
        # Create new bucket
        bucket = Map.merge(state.default_config, %{
          tokens: state.default_config.max_tokens,
          last_refill: System.monotonic_time(:millisecond),
          priority: priority
        })
        
        :ets.insert(:rate_limiter_buckets, {key, bucket})
        bucket
    end
  end
  
  defp refill_bucket(bucket, current_time) do
    elapsed_ms = current_time - bucket.last_refill
    elapsed_seconds = elapsed_ms / 1000
    
    # Calculate tokens to add
    tokens_to_add = elapsed_seconds * bucket.refill_rate
    
    # Update bucket
    new_tokens = min(bucket.tokens + tokens_to_add, bucket.max_tokens)
    
    %{bucket | 
      tokens: new_tokens,
      last_refill: current_time
    }
  end
  
  defp priority_multiplier(:high), do: 2.0
  defp priority_multiplier(:normal), do: 1.0
  defp priority_multiplier(:low), do: 0.5
  
  defp check_circuit_breaker(key, state) do
    case :ets.lookup(:circuit_breakers, key) do
      [{^key, breaker}] ->
        check_breaker_state(breaker, state.circuit_config)
      [] ->
        :closed
    end
  end
  
  defp check_breaker_state(breaker, config) do
    current_time = System.monotonic_time(:millisecond)
    
    case breaker.state do
      :open ->
        # Check if timeout has passed
        if current_time - breaker.last_failure > config.timeout_ms do
          # Transition to half-open
          updated = %{breaker | state: :half_open, half_open_attempts: 0}
          :ets.insert(:circuit_breakers, {breaker.key, updated})
          :half_open
        else
          :open
        end
        
      :half_open ->
        # Check if we've exceeded half-open attempts
        if breaker.half_open_attempts >= config.half_open_requests do
          :open
        else
          :half_open
        end
        
      _ ->
        breaker.state
    end
  end
  
  defp update_circuit_breaker(key, result, state) do
    breaker = case :ets.lookup(:circuit_breakers, key) do
      [{^key, b}] -> b
      [] -> %{
        key: key,
        state: :closed,
        failures: 0,
        successes: 0,
        last_failure: 0,
        half_open_attempts: 0
      }
    end
    
    updated = case {breaker.state, result} do
      {:closed, :failure} ->
        failures = breaker.failures + 1
        if failures >= state.circuit_config.failure_threshold do
          %{breaker | 
            state: :open,
            failures: failures,
            last_failure: System.monotonic_time(:millisecond)
          }
        else
          %{breaker | failures: failures}
        end
        
      {:closed, :success} ->
        %{breaker | successes: breaker.successes + 1}
        
      {:half_open, :success} ->
        successes = breaker.successes + 1
        if successes >= state.circuit_config.success_threshold do
          %{breaker | 
            state: :closed,
            failures: 0,
            successes: 0
          }
        else
          %{breaker | successes: successes}
        end
        
      {:half_open, :failure} ->
        %{breaker | 
          state: :open,
          failures: breaker.failures + 1,
          last_failure: System.monotonic_time(:millisecond)
        }
        
      _ ->
        breaker
    end
    
    :ets.insert(:circuit_breakers, {key, updated})
  end
  
  defp update_circuit_breaker_attempt(key) do
    case :ets.lookup(:circuit_breakers, key) do
      [{^key, breaker}] ->
        updated = %{breaker | half_open_attempts: breaker.half_open_attempts + 1}
        :ets.insert(:circuit_breakers, {key, updated})
      [] ->
        :ok
    end
  end
  
  defp adapt_rate_limit(key, :success) do
    case :ets.lookup(:rate_limiter_buckets, key) do
      [{^key, bucket}] ->
        # Increase rate limit by 10% on success
        new_max = min(bucket.max_tokens * 1.1, bucket.max_tokens * 2)
        updated = %{bucket | max_tokens: round(new_max)}
        :ets.insert(:rate_limiter_buckets, {key, updated})
      [] ->
        :ok
    end
  end
  
  defp adapt_rate_limit(key, :failure) do
    case :ets.lookup(:rate_limiter_buckets, key) do
      [{^key, bucket}] ->
        # Decrease rate limit by 20% on failure
        new_max = max(bucket.max_tokens * 0.8, 1)
        updated = %{bucket | max_tokens: round(new_max)}
        :ets.insert(:rate_limiter_buckets, {key, updated})
      [] ->
        :ok
    end
  end
  
  defp update_user_buckets_priority(user_id, priority) do
    # Find all buckets for this user
    :ets.foldl(fn
      {{^user_id, _tool} = key, bucket}, acc ->
        updated = %{bucket | priority: priority}
        :ets.insert(:rate_limiter_buckets, {key, updated})
        acc
      _, acc ->
        acc
    end, :ok, :rate_limiter_buckets)
  end
  
  defp compile_stats(nil, nil) do
    # Global stats
    bucket_count = :ets.info(:rate_limiter_buckets, :size)
    breaker_count = :ets.info(:circuit_breakers, :size)
    
    %{
      total_buckets: bucket_count,
      total_circuit_breakers: breaker_count,
      by_priority: count_by_priority()
    }
  end
  
  defp compile_stats(user_id, tool) when not is_nil(user_id) and not is_nil(tool) do
    # Specific user/tool stats
    key = {user_id, tool}
    
    bucket_stats = case :ets.lookup(:rate_limiter_buckets, key) do
      [{^key, bucket}] ->
        %{
          tokens_available: bucket.tokens,
          max_tokens: bucket.max_tokens,
          refill_rate: bucket.refill_rate,
          priority: bucket.priority
        }
      [] ->
        nil
    end
    
    breaker_stats = case :ets.lookup(:circuit_breakers, key) do
      [{^key, breaker}] ->
        %{
          state: breaker.state,
          failures: breaker.failures,
          successes: breaker.successes
        }
      [] ->
        nil
    end
    
    %{
      rate_limit: bucket_stats,
      circuit_breaker: breaker_stats
    }
  end
  
  defp compile_stats(user_id, nil) when not is_nil(user_id) do
    # All tools for a user
    user_buckets = :ets.foldl(fn
      {{^user_id, tool}, bucket}, acc ->
        [{tool, bucket} | acc]
      _, acc ->
        acc
    end, [], :rate_limiter_buckets)
    
    %{
      user_id: user_id,
      tools: Map.new(user_buckets)
    }
  end
  
  defp compile_stats(nil, tool) when not is_nil(tool) do
    # All users for a tool
    tool_buckets = :ets.foldl(fn
      {{user_id, ^tool}, bucket}, acc ->
        [{user_id, bucket} | acc]
      _, acc ->
        acc
    end, [], :rate_limiter_buckets)
    
    %{
      tool: tool,
      users: Map.new(tool_buckets)
    }
  end
  
  defp count_by_priority do
    :ets.foldl(fn
      {_, %{priority: priority}}, acc ->
        Map.update(acc, priority, 1, &(&1 + 1))
    end, %{low: 0, normal: 0, high: 0}, :rate_limiter_buckets)
  end
  
  defp cleanup_old_buckets do
    current_time = System.monotonic_time(:millisecond)
    max_idle_time = 3_600_000  # 1 hour
    
    :ets.foldl(fn
      {key, bucket}, acc ->
        if current_time - bucket.last_refill > max_idle_time do
          :ets.delete(:rate_limiter_buckets, key)
        end
        acc
    end, :ok, :rate_limiter_buckets)
  end
end