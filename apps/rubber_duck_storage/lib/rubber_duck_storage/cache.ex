defmodule RubberDuckStorage.Cache do
  @moduledoc """
  Caching layer with ETS-based local cache and optional Redis support.

  This module provides:
  - ETS-based local caching for fast access
  - Cache warming strategies
  - Cache invalidation patterns
  - Optional Redis adapter for distributed caching
  """

  use GenServer
  require Logger

  alias RubberDuckCore.Protocols.Cacheable

  @local_cache_table :rubber_duck_cache
  @cache_stats_table :rubber_duck_cache_stats
  @cleanup_interval :timer.minutes(5)
  @default_ttl 1800  # 30 minutes

  defstruct [
    :cache_table,
    :stats_table,
    :cleanup_timer,
    :redis_adapter,
    :config
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a value from cache by key.
  """
  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  @doc """
  Puts a value in cache with optional TTL.
  """
  def put(key, value, ttl \\ nil) do
    GenServer.call(__MODULE__, {:put, key, value, ttl})
  end

  @doc """
  Puts a cacheable struct in cache using its protocol implementation.
  """
  def put_cacheable(data) do
    if Cacheable.cacheable?(data) do
      key = Cacheable.cache_key(data)
      ttl = Cacheable.cache_ttl(data)
      put(key, data, ttl)
    else
      {:ok, :not_cacheable}
    end
  end

  @doc """
  Gets a cacheable struct from cache using its protocol implementation.
  """
  def get_cacheable(data) do
    key = Cacheable.cache_key(data)
    get(key)
  end

  @doc """
  Deletes a value from cache by key.
  """
  def delete(key) do
    GenServer.call(__MODULE__, {:delete, key})
  end

  @doc """
  Deletes multiple keys matching a pattern.
  """
  def delete_pattern(pattern) do
    GenServer.call(__MODULE__, {:delete_pattern, pattern})
  end

  @doc """
  Checks if a key exists in cache.
  """
  def exists?(key) do
    GenServer.call(__MODULE__, {:exists, key})
  end

  @doc """
  Warms the cache with frequently accessed data.
  """
  def warm_cache(warming_functions) when is_list(warming_functions) do
    GenServer.cast(__MODULE__, {:warm_cache, warming_functions})
  end

  @doc """
  Gets cache statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Clears all cache entries.
  """
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # Server Implementation

  @impl true
  def init(opts) do
    # Create ETS tables
    cache_table = :ets.new(@local_cache_table, [:set, :protected, :named_table])
    stats_table = :ets.new(@cache_stats_table, [:set, :protected, :named_table])

    # Initialize stats
    :ets.insert(stats_table, {:hits, 0})
    :ets.insert(stats_table, {:misses, 0})
    :ets.insert(stats_table, {:evictions, 0})

    # Set up periodic cleanup
    cleanup_timer = Process.send_after(self(), :cleanup_expired, @cleanup_interval)

    # Optional Redis configuration
    redis_adapter = Keyword.get(opts, :redis_adapter)
    
    state = %__MODULE__{
      cache_table: cache_table,
      stats_table: stats_table,
      cleanup_timer: cleanup_timer,
      redis_adapter: redis_adapter,
      config: opts
    }

    Logger.info("Cache started with local table: #{inspect(cache_table)}")
    {:ok, state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    case :ets.lookup(state.cache_table, key) do
      [{^key, value, expires_at}] ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          increment_stat(state.stats_table, :hits)
          {:reply, {:ok, value}, state}
        else
          # Expired entry
          :ets.delete(state.cache_table, key)
          increment_stat(state.stats_table, :misses)
          increment_stat(state.stats_table, :evictions)
          
          # Try Redis if available
          case get_from_redis(key, state) do
            {:ok, value} -> {:reply, {:ok, value}, state}
            _ -> {:reply, {:error, :not_found}, state}
          end
        end

      [] ->
        increment_stat(state.stats_table, :misses)
        
        # Try Redis if available
        case get_from_redis(key, state) do
          {:ok, value} -> {:reply, {:ok, value}, state}
          _ -> {:reply, {:error, :not_found}, state}
        end
    end
  end

  @impl true
  def handle_call({:put, key, value, ttl}, _from, state) do
    ttl = ttl || @default_ttl
    expires_at = DateTime.utc_now() |> DateTime.add(ttl, :second)
    
    # Store in local cache
    :ets.insert(state.cache_table, {key, value, expires_at})
    
    # Store in Redis if available
    put_to_redis(key, value, ttl, state)
    
    Logger.debug("Cached #{key} with TTL #{ttl}s")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:delete, key}, _from, state) do
    :ets.delete(state.cache_table, key)
    delete_from_redis(key, state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:delete_pattern, pattern}, _from, state) do
    # Convert pattern to match spec
    match_spec = [{{pattern, :_, :_}, [], [true]}]
    keys = :ets.select(state.cache_table, match_spec)
    
    Enum.each(keys, fn key ->
      :ets.delete(state.cache_table, key)
      delete_from_redis(key, state)
    end)
    
    deleted_count = length(keys)
    Logger.debug("Deleted #{deleted_count} keys matching pattern: #{pattern}")
    {:reply, {:ok, deleted_count}, state}
  end

  @impl true
  def handle_call({:exists, key}, _from, state) do
    exists = case :ets.lookup(state.cache_table, key) do
      [{^key, _value, expires_at}] ->
        DateTime.compare(DateTime.utc_now(), expires_at) == :lt
      [] ->
        false
    end
    
    {:reply, exists, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = :ets.tab2list(state.stats_table) |> Enum.into(%{})
    cache_size = :ets.info(state.cache_table, :size)
    
    enhanced_stats = Map.put(stats, :cache_size, cache_size)
    {:reply, enhanced_stats, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(state.cache_table)
    clear_redis(state)
    Logger.info("Cache cleared")
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:warm_cache, warming_functions}, state) do
    Logger.info("Starting cache warming with #{length(warming_functions)} functions")
    
    Task.start(fn ->
      Enum.each(warming_functions, fn warming_fn ->
        try do
          case warming_fn.() do
            {key, value, ttl} -> put(key, value, ttl)
            {key, value} -> put(key, value)
            _ -> :ok
          end
        rescue
          error ->
            Logger.error("Cache warming function failed: #{inspect(error)}")
        end
      end)
      
      Logger.info("Cache warming completed")
    end)
    
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    now = DateTime.utc_now()
    
    # Find expired entries
    expired_keys = :ets.foldl(fn {key, _value, expires_at}, acc ->
      if DateTime.compare(now, expires_at) == :gt do
        [key | acc]
      else
        acc
      end
    end, [], state.cache_table)
    
    # Delete expired entries
    Enum.each(expired_keys, fn key ->
      :ets.delete(state.cache_table, key)
      increment_stat(state.stats_table, :evictions)
    end)
    
    if length(expired_keys) > 0 do
      Logger.debug("Cleaned up #{length(expired_keys)} expired cache entries")
    end
    
    # Schedule next cleanup
    cleanup_timer = Process.send_after(self(), :cleanup_expired, @cleanup_interval)
    {:noreply, %{state | cleanup_timer: cleanup_timer}}
  end

  @impl true
  def terminate(_reason, state) do
    if state.cleanup_timer do
      Process.cancel_timer(state.cleanup_timer)
    end
    :ok
  end

  # Redis Integration (optional)

  defp get_from_redis(_key, %{redis_adapter: nil}), do: {:error, :not_available}
  defp get_from_redis(key, %{redis_adapter: adapter}) do
    # This would integrate with a Redis client like Redix
    # For now, it's a placeholder for future Redis integration
    Logger.debug("Redis get attempted for key: #{key}")
    {:error, :not_implemented}
  end

  defp put_to_redis(_key, _value, _ttl, %{redis_adapter: nil}), do: :ok
  defp put_to_redis(key, value, ttl, %{redis_adapter: adapter}) do
    # This would integrate with a Redis client like Redix
    Logger.debug("Redis put attempted for key: #{key} with TTL: #{ttl}")
    :ok
  end

  defp delete_from_redis(_key, %{redis_adapter: nil}), do: :ok
  defp delete_from_redis(key, %{redis_adapter: adapter}) do
    # This would integrate with a Redis client like Redix
    Logger.debug("Redis delete attempted for key: #{key}")
    :ok
  end

  defp clear_redis(%{redis_adapter: nil}), do: :ok
  defp clear_redis(%{redis_adapter: adapter}) do
    # This would integrate with a Redis client like Redix
    Logger.debug("Redis clear attempted")
    :ok
  end

  # Helper Functions

  defp increment_stat(stats_table, stat) do
    :ets.update_counter(stats_table, stat, {2, 1}, {stat, 0})
  end
end