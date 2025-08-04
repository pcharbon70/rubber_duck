defmodule RubberDuck.Jido.Actions.Middleware.CacheMiddleware do
  @moduledoc """
  Middleware for caching action results.
  
  This middleware caches action results to avoid redundant computation.
  It supports TTL-based expiration, cache key generation, and selective
  caching based on parameters and results.
  
  ## Options
  
  - `:ttl` - Time to live in seconds. Default: 300 (5 minutes)
  - `:cache_on` - When to cache (:success, :all). Default: :success
  - `:key_fn` - Custom cache key generation function
  - `:should_cache_fn` - Function to determine if result should be cached
  - `:max_size` - Maximum cache size in bytes. Default: nil (unlimited)
  """
  
  use RubberDuck.Jido.Actions.Middleware, priority: 70
  require Logger
  
  @ets_table :action_cache
  
  @impl true
  def init(opts) do
    config = %{
      ttl: Keyword.get(opts, :ttl, 300),
      cache_on: Keyword.get(opts, :cache_on, :success),
      key_fn: Keyword.get(opts, :key_fn),
      should_cache_fn: Keyword.get(opts, :should_cache_fn),
      max_size: Keyword.get(opts, :max_size)
    }
    
    # Ensure ETS table exists
    ensure_ets_table()
    
    {:ok, config}
  end
  
  @impl true
  def call(action, params, context, next) do
    {:ok, config} = init([])
    
    # Generate cache key
    cache_key = generate_cache_key(action, params, context, config)
    
    # Check cache
    case get_from_cache(cache_key) do
      {:ok, cached_result} ->
        log_cache_hit(action, cache_key)
        cached_result
        
      :miss ->
        # Execute action
        result = next.(params, context)
        
        # Cache result if appropriate
        maybe_cache_result(cache_key, result, config, action)
        
        result
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
  
  defp generate_cache_key(action, params, context, %{key_fn: key_fn}) when is_function(key_fn) do
    key_fn.(action, params, context)
  end
  
  defp generate_cache_key(action, params, _context, _config) do
    # Generate deterministic key from action and params
    data = {inspect(action), normalize_params(params)}
    :crypto.hash(:sha256, :erlang.term_to_binary(data))
    |> Base.encode16(case: :lower)
  end
  
  defp normalize_params(params) when is_map(params) do
    params
    |> Enum.sort()
    |> Enum.map(fn {k, v} -> {k, normalize_value(v)} end)
  end
  
  defp normalize_value(v) when is_map(v), do: normalize_params(v)
  defp normalize_value(v) when is_list(v), do: Enum.map(v, &normalize_value/1)
  defp normalize_value(v), do: v
  
  defp get_from_cache(key) do
    case :ets.lookup(@ets_table, key) do
      [{^key, entry}] ->
        if cache_entry_valid?(entry) do
          # Update access time
          updated_entry = %{entry | last_accessed: System.monotonic_time(:second)}
          :ets.insert(@ets_table, {key, updated_entry})
          
          # Update hit statistics
          update_cache_stats(:hit)
          
          {:ok, entry.result}
        else
          # Entry expired, remove it
          :ets.delete(@ets_table, key)
          update_cache_stats(:expired)
          :miss
        end
        
      [] ->
        update_cache_stats(:miss)
        :miss
    end
  end
  
  defp cache_entry_valid?(entry) do
    now = System.monotonic_time(:second)
    now - entry.cached_at < entry.ttl
  end
  
  defp maybe_cache_result(key, result, config, action) do
    should_cache = case {result, config.cache_on} do
      {{:ok, _, _}, :success} -> true
      {_, :all} -> true
      _ -> false
    end
    
    should_cache = should_cache and should_cache_result?(result, config)
    
    if should_cache do
      cache_entry = %{
        result: result,
        cached_at: System.monotonic_time(:second),
        last_accessed: System.monotonic_time(:second),
        ttl: config.ttl,
        size: estimate_size(result)
      }
      
      # Check size limit if configured
      if check_size_limit(cache_entry, config) do
        :ets.insert(@ets_table, {key, cache_entry})
        log_cache_store(action, key, cache_entry.size)
        update_cache_stats(:store)
      end
    end
  end
  
  defp should_cache_result?(result, %{should_cache_fn: fun}) when is_function(fun) do
    fun.(result)
  end
  defp should_cache_result?(_, _), do: true
  
  defp check_size_limit(entry, %{max_size: nil}), do: true
  defp check_size_limit(entry, %{max_size: max_size}) do
    entry.size <= max_size
  end
  
  defp estimate_size(term) do
    :erlang.external_size(term)
  end
  
  defp update_cache_stats(type) do
    stats_key = :cache_stats
    
    stats = case :ets.lookup(@ets_table, stats_key) do
      [{^stats_key, s}] -> s
      [] -> %{hits: 0, misses: 0, stores: 0, expired: 0}
    end
    
    updated_stats = case type do
      :hit -> %{stats | hits: stats.hits + 1}
      :miss -> %{stats | misses: stats.misses + 1}
      :store -> %{stats | stores: stats.stores + 1}
      :expired -> %{stats | expired: stats.expired + 1}
    end
    
    :ets.insert(@ets_table, {stats_key, updated_stats})
  end
  
  defp log_cache_hit(action, key) do
    Logger.debug("Cache hit", %{
      middleware: "CacheMiddleware",
      action: inspect(action),
      cache_key: key
    })
  end
  
  defp log_cache_store(action, key, size) do
    Logger.debug("Cached result", %{
      middleware: "CacheMiddleware",
      action: inspect(action),
      cache_key: key,
      size_bytes: size
    })
  end
end