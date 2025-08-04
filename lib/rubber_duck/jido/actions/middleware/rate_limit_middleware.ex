defmodule RubberDuck.Jido.Actions.Middleware.RateLimitMiddleware do
  @moduledoc """
  Middleware for rate limiting action execution.
  
  This middleware implements token bucket algorithm for rate limiting,
  preventing excessive action execution. It supports per-user, per-action,
  and global rate limits with configurable windows and burst capacity.
  
  ## Options
  
  - `:max_requests` - Maximum requests allowed in window. Default: 100
  - `:window_ms` - Time window in milliseconds. Default: 60_000 (1 minute)
  - `:burst_size` - Burst capacity above normal rate. Default: 10
  - `:scope` - Rate limit scope (:global, :per_user, :per_action). Default: :per_user
  - `:key_fn` - Custom function to generate rate limit key
  """
  
  use RubberDuck.Jido.Actions.Middleware, priority: 85
  require Logger
  
  @ets_table :rate_limit_buckets
  
  @impl true
  def init(opts) do
    config = %{
      max_requests: Keyword.get(opts, :max_requests, 100),
      window_ms: Keyword.get(opts, :window_ms, 60_000),
      burst_size: Keyword.get(opts, :burst_size, 10),
      scope: Keyword.get(opts, :scope, :per_user),
      key_fn: Keyword.get(opts, :key_fn),
      refill_rate: calculate_refill_rate(
        Keyword.get(opts, :max_requests, 100),
        Keyword.get(opts, :window_ms, 60_000)
      )
    }
    
    # Ensure ETS table exists
    ensure_ets_table()
    
    {:ok, config}
  end
  
  @impl true
  def call(action, params, context, next) do
    {:ok, config} = init([])
    
    # Generate rate limit key
    key = generate_key(action, context, config)
    
    # Check rate limit
    case check_rate_limit(key, config) do
      :ok ->
        # Execute action
        result = next.(params, context)
        
        # Log successful execution
        log_request_allowed(action, key)
        
        result
        
      {:error, :rate_limited, info} ->
        log_rate_limited(action, key, info)
        
        {:error, {:rate_limited, %{
          retry_after_ms: info.retry_after_ms,
          limit: config.max_requests,
          window_ms: config.window_ms,
          key: key
        }}}
    end
  end
  
  # Private functions
  
  defp ensure_ets_table do
    case :ets.whereis(@ets_table) do
      :undefined ->
        :ets.new(@ets_table, [:set, :public, :named_table, {:read_concurrency, true}])
      _ ->
        :ok
    end
  end
  
  defp generate_key(action, context, %{key_fn: key_fn}) when is_function(key_fn) do
    key_fn.(action, context)
  end
  
  defp generate_key(action, context, %{scope: scope}) do
    case scope do
      :global ->
        "global"
        
      :per_user ->
        user_id = Map.get(context, :user_id, "anonymous")
        "user:#{user_id}"
        
      :per_action ->
        "action:#{inspect(action)}"
        
      :per_user_action ->
        user_id = Map.get(context, :user_id, "anonymous")
        "user:#{user_id}:action:#{inspect(action)}"
    end
  end
  
  defp check_rate_limit(key, config) do
    now = System.monotonic_time(:millisecond)
    
    # Get or initialize bucket
    bucket = get_or_init_bucket(key, config, now)
    
    # Refill tokens based on elapsed time
    elapsed = now - bucket.last_refill
    tokens_to_add = min(
      config.max_requests + config.burst_size - bucket.tokens,
      trunc(elapsed * config.refill_rate / 1000)
    )
    
    updated_bucket = if tokens_to_add > 0 do
      %{bucket | 
        tokens: bucket.tokens + tokens_to_add,
        last_refill: now
      }
    else
      bucket
    end
    
    # Check if we have tokens available
    if updated_bucket.tokens >= 1 do
      # Consume a token
      final_bucket = %{updated_bucket | 
        tokens: updated_bucket.tokens - 1,
        last_request: now,
        request_count: updated_bucket.request_count + 1
      }
      
      # Save updated bucket
      :ets.insert(@ets_table, {key, final_bucket})
      
      :ok
    else
      # Calculate retry after
      tokens_needed = 1 - updated_bucket.tokens
      retry_after_ms = trunc(tokens_needed * 1000 / config.refill_rate)
      
      # Save bucket state (even though rate limited)
      :ets.insert(@ets_table, {key, updated_bucket})
      
      {:error, :rate_limited, %{
        retry_after_ms: retry_after_ms,
        tokens_available: updated_bucket.tokens,
        request_count: updated_bucket.request_count
      }}
    end
  end
  
  defp get_or_init_bucket(key, config, now) do
    case :ets.lookup(@ets_table, key) do
      [{^key, bucket}] ->
        # Check if bucket should be reset (window expired)
        if now - bucket.window_start > config.window_ms do
          init_bucket(config, now)
        else
          bucket
        end
        
      [] ->
        init_bucket(config, now)
    end
  end
  
  defp init_bucket(config, now) do
    %{
      tokens: config.max_requests + config.burst_size,
      last_refill: now,
      last_request: now,
      window_start: now,
      request_count: 0
    }
  end
  
  defp calculate_refill_rate(max_requests, window_ms) do
    max_requests / (window_ms / 1000)
  end
  
  defp log_request_allowed(action, key) do
    Logger.debug("Rate limit check passed", %{
      middleware: "RateLimitMiddleware",
      action: inspect(action),
      key: key
    })
  end
  
  defp log_rate_limited(action, key, info) do
    Logger.warning("Request rate limited", %{
      middleware: "RateLimitMiddleware",
      action: inspect(action),
      key: key,
      retry_after_ms: info.retry_after_ms,
      request_count: info.request_count
    })
  end
end