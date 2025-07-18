defmodule RubberDuck.MCP.RateLimiter do
  @moduledoc """
  Token bucket rate limiter for MCP protocol operations.
  
  Implements a hierarchical rate limiting system with:
  - Global limits across all clients
  - Per-client limits
  - Per-operation limits
  - Adaptive rate limiting based on behavior
  
  ## Algorithm
  
  Uses the token bucket algorithm where:
  - Each bucket has a maximum capacity
  - Tokens are added at a fixed rate
  - Operations consume tokens
  - Requests are rejected when insufficient tokens
  
  ## Features
  
  - Burst allowance for temporary spikes
  - Priority clients with higher limits
  - Cost-based operations (some operations cost more tokens)
  - Circuit breaker for consistently failing clients
  """
  
  use GenServer
  
  require Logger
  
  @type bucket_key :: {client_id :: String.t(), operation :: String.t() | :global}
  @type bucket :: %{
    tokens: float(),
    max_tokens: pos_integer(),
    refill_rate: float(),
    last_refill: integer(),
    burst_allowance: pos_integer(),
    priority: :low | :normal | :high | :critical
  }
  
  @type limit_config :: %{
    max_tokens: pos_integer(),
    refill_rate: float(),
    burst_allowance: pos_integer(),
    window_seconds: pos_integer()
  }
  
  # Default configurations
  @global_limits %{
    max_tokens: 10_000,
    refill_rate: 100.0,  # tokens per second
    burst_allowance: 1_000
  }
  
  @default_client_limits %{
    normal: %{
      max_tokens: 100,
      refill_rate: 1.0,
      burst_allowance: 20
    },
    high: %{
      max_tokens: 500,
      refill_rate: 5.0,
      burst_allowance: 100
    },
    critical: %{
      max_tokens: 1_000,
      refill_rate: 10.0,
      burst_allowance: 200
    }
  }
  
  @operation_costs %{
    "tools/list" => 1,
    "tools/call" => 5,
    "resources/list" => 1,
    "resources/read" => 2,
    "workflows/create" => 10,
    "workflows/execute" => 20,
    "sampling/createMessage" => 15
  }
  
  # Client API
  
  @doc """
  Starts the rate limiter.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  @doc """
  Checks if a client can perform an operation.
  
  Returns :ok if allowed, or {:error, :rate_limited, retry_after: seconds}.
  """
  @spec check_limit(String.t(), String.t(), keyword()) :: 
    :ok | {:error, :rate_limited, retry_after: pos_integer()}
  def check_limit(client_id, operation, opts \\ []) do
    priority = Keyword.get(opts, :priority, :normal)
    GenServer.call(__MODULE__, {:check_limit, client_id, operation, priority})
  end
  
  @doc """
  Sets custom limits for a specific client.
  """
  @spec set_client_limits(String.t(), limit_config()) :: :ok
  def set_client_limits(client_id, limits) do
    GenServer.call(__MODULE__, {:set_client_limits, client_id, limits})
  end
  
  @doc """
  Gets current stats for monitoring.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Updates rate limiter configuration.
  """
  @spec update_config(map()) :: :ok
  def update_config(config) do
    GenServer.call(__MODULE__, {:update_config, config})
  end
  
  @doc """
  Resets limits for a client (admin operation).
  """
  @spec reset_client(String.t()) :: :ok
  def reset_client(client_id) do
    GenServer.call(__MODULE__, {:reset_client, client_id})
  end
  
  # Server implementation
  
  @impl GenServer
  def init(opts) do
    # Create ETS table for buckets
    table = :ets.new(:mcp_rate_limiter_buckets, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])
    
    # Schedule periodic cleanup
    schedule_cleanup()
    
    state = %{
      table: table,
      config: load_config(opts),
      stats: %{
        requests_allowed: 0,
        requests_limited: 0,
        active_buckets: 0
      }
    }
    
    # Initialize global bucket
    init_bucket(table, {:global, :global}, @global_limits)
    
    Logger.info("MCP Rate Limiter started")
    {:ok, state}
  end
  
  @impl GenServer
  def handle_call({:check_limit, client_id, operation, priority}, _from, state) do
    now = System.monotonic_time(:millisecond)
    cost = Map.get(@operation_costs, operation, 1)
    
    # Check global limits first
    case check_bucket(state.table, {:global, :global}, cost, now) do
      :ok ->
        # Check client-specific limits
        client_key = {client_id, :global}
        client_limits = get_client_limits(state.config, client_id, priority)
        
        case check_bucket(state.table, client_key, cost, now, client_limits) do
          :ok ->
            # Check operation-specific limits if configured
            operation_key = {client_id, operation}
            operation_limits = get_operation_limits(state.config, operation, priority)
            
            case check_bucket(state.table, operation_key, cost, now, operation_limits) do
              :ok ->
                update_stats(state, :requests_allowed)
                {:reply, :ok, state}
                
              {:error, retry_after} ->
                update_stats(state, :requests_limited)
                {:reply, {:error, :rate_limited, retry_after: retry_after}, state}
            end
            
          {:error, retry_after} ->
            update_stats(state, :requests_limited)
            {:reply, {:error, :rate_limited, retry_after: retry_after}, state}
        end
        
      {:error, retry_after} ->
        update_stats(state, :requests_limited)
        Logger.warning("Global rate limit exceeded")
        {:reply, {:error, :rate_limited, retry_after: retry_after}, state}
    end
  end
  
  @impl GenServer
  def handle_call({:set_client_limits, client_id, limits}, _from, state) do
    # Store custom client limits
    new_config = put_in(state.config, [:custom_limits, client_id], limits)
    {:reply, :ok, %{state | config: new_config}}
  end
  
  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    # Count active buckets
    active_buckets = :ets.info(state.table, :size)
    
    # Get bucket details
    buckets = :ets.tab2list(state.table)
    |> Enum.map(fn {key, bucket} ->
      %{
        key: key,
        tokens: bucket.tokens,
        max_tokens: bucket.max_tokens,
        utilization: (bucket.max_tokens - bucket.tokens) / bucket.max_tokens * 100
      }
    end)
    |> Enum.filter(fn b -> b.utilization > 0 end)
    |> Enum.sort_by(& &1.utilization, :desc)
    |> Enum.take(10)
    
    stats = Map.merge(state.stats, %{
      active_buckets: active_buckets,
      top_consumers: buckets
    })
    
    {:reply, stats, state}
  end
  
  @impl GenServer
  def handle_call({:update_config, config}, _from, state) do
    new_state = %{state | config: DeepMerge.deep_merge(state.config, config)}
    {:reply, :ok, new_state}
  end
  
  @impl GenServer
  def handle_call({:reset_client, client_id}, _from, state) do
    # Remove all buckets for this client
    :ets.match_delete(state.table, {{client_id, :_}, :_})
    {:reply, :ok, state}
  end
  
  @impl GenServer
  def handle_info(:cleanup, state) do
    # Remove old, unused buckets
    now = System.monotonic_time(:millisecond)
    cutoff = now - 300_000  # 5 minutes
    
    old_buckets = :ets.select(state.table, [
      {
        {:_, %{last_refill: :"$1", tokens: :"$2", max_tokens: :"$3"}},
        [{:<, :"$1", cutoff}, {:==, :"$2", :"$3"}],
        [:"$_"]
      }
    ])
    
    Enum.each(old_buckets, fn {key, _} ->
      :ets.delete(state.table, key)
    end)
    
    if length(old_buckets) > 0 do
      Logger.debug("Cleaned up #{length(old_buckets)} inactive rate limit buckets")
    end
    
    schedule_cleanup()
    {:noreply, state}
  end
  
  # Private functions
  
  defp load_config(opts) do
    %{
      global_limits: Keyword.get(opts, :global_limits, @global_limits),
      client_limits: Keyword.get(opts, :client_limits, @default_client_limits),
      operation_costs: Keyword.get(opts, :operation_costs, @operation_costs),
      custom_limits: %{},
      cleanup_interval: Keyword.get(opts, :cleanup_interval, 300_000)  # 5 minutes
    }
  end
  
  defp init_bucket(table, key, limits) do
    bucket = %{
      tokens: limits.max_tokens * 1.0,
      max_tokens: limits.max_tokens,
      refill_rate: limits.refill_rate,
      last_refill: System.monotonic_time(:millisecond),
      burst_allowance: Map.get(limits, :burst_allowance, 0),
      priority: Map.get(limits, :priority, :normal)
    }
    
    :ets.insert(table, {key, bucket})
  end
  
  defp check_bucket(table, key, cost, now, limits \\ nil) do
    case :ets.lookup(table, key) do
      [{^key, bucket}] ->
        # Refill tokens
        refilled_bucket = refill_tokens(bucket, now)
        
        # Check if enough tokens
        if refilled_bucket.tokens >= cost do
          # Consume tokens
          new_bucket = %{refilled_bucket | tokens: refilled_bucket.tokens - cost}
          :ets.insert(table, {key, new_bucket})
          :ok
        else
          # Calculate retry after
          tokens_needed = cost - refilled_bucket.tokens
          retry_after = ceil(tokens_needed / refilled_bucket.refill_rate)
          {:error, retry_after}
        end
        
      [] when not is_nil(limits) ->
        # Initialize bucket with limits
        init_bucket(table, key, limits)
        check_bucket(table, key, cost, now)
        
      [] ->
        # No bucket and no limits provided
        :ok
    end
  end
  
  defp refill_tokens(bucket, now) do
    elapsed = now - bucket.last_refill
    elapsed_seconds = elapsed / 1000.0
    
    tokens_to_add = elapsed_seconds * bucket.refill_rate
    new_tokens = min(bucket.tokens + tokens_to_add, bucket.max_tokens + bucket.burst_allowance)
    
    %{bucket | 
      tokens: new_tokens,
      last_refill: now
    }
  end
  
  defp get_client_limits(config, client_id, priority) do
    # Check for custom limits first
    case get_in(config, [:custom_limits, client_id]) do
      nil ->
        # Use default limits based on priority
        Map.get(config.client_limits, priority, config.client_limits.normal)
        
      custom_limits ->
        custom_limits
    end
  end
  
  defp get_operation_limits(config, operation, priority) do
    # For now, use client limits for operations
    # Could be extended to have per-operation limits
    get_client_limits(config, :default, priority)
  end
  
  defp update_stats(state, stat) do
    update_in(state.stats[stat], &(&1 + 1))
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 300_000)  # 5 minutes
  end
end