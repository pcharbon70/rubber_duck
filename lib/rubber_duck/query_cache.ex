defmodule RubberDuck.QueryCache do
  use GenServer
  require Logger

  @moduledoc """
  Intelligent query caching system optimized for AI workload patterns.
  Provides multi-level caching with TTL, LRU eviction, and cache warming
  specifically designed for conversational AI data access patterns.
  """

  defstruct [
    :session_cache,
    :query_cache, 
    :model_cache,
    :stats_cache,
    :config
  ]

  @cache_names [:session_cache, :query_cache, :model_cache, :stats_cache]
  
  @default_config %{
    session_cache: %{
      limit: 1000,           # Active sessions
      ttl: :timer.hours(2),  # 2 hours for active sessions
      stats: true
    },
    query_cache: %{
      limit: 500,            # Query results
      ttl: :timer.minutes(15), # 15 minutes for query results
      stats: true
    },
    model_cache: %{
      limit: 100,            # Model information
      ttl: :timer.hours(1),  # 1 hour for model data
      stats: true
    },
    stats_cache: %{
      limit: 200,            # Aggregated statistics
      ttl: :timer.minutes(5), # 5 minutes for stats
      stats: true
    }
  }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get session data with caching
  """
  def get_session(session_id, fetch_fun) do
    cache_fetch(:session_cache, session_id, fetch_fun)
  end

  @doc """
  Cache session data
  """
  def put_session(session_id, session_data, ttl \\ nil) do
    cache_put(:session_cache, session_id, session_data, ttl)
  end

  @doc """
  Invalidate session cache
  """
  def invalidate_session(session_id) do
    cache_delete(:session_cache, session_id)
  end

  @doc """
  Get cached query result
  """
  def get_query_result(query_key, fetch_fun) do
    cache_fetch(:query_cache, query_key, fetch_fun)
  end

  @doc """
  Cache query result
  """
  def put_query_result(query_key, result, ttl \\ nil) do
    cache_put(:query_cache, query_key, result, ttl)
  end

  @doc """
  Get model data with caching
  """
  def get_model(model_name, fetch_fun) do
    cache_fetch(:model_cache, model_name, fetch_fun)
  end

  @doc """
  Cache model data
  """
  def put_model(model_name, model_data, ttl \\ nil) do
    cache_put(:model_cache, model_name, model_data, ttl)
  end

  @doc """
  Invalidate model cache
  """
  def invalidate_model(model_name) do
    cache_delete(:model_cache, model_name)
  end

  @doc """
  Get cached statistics
  """
  def get_stats(stats_key, fetch_fun) do
    cache_fetch(:stats_cache, stats_key, fetch_fun)
  end

  @doc """
  Cache statistics
  """
  def put_stats(stats_key, stats_data, ttl \\ nil) do
    cache_put(:stats_cache, stats_key, stats_data, ttl)
  end

  @doc """
  Get cache performance statistics
  """
  def get_cache_stats do
    GenServer.call(__MODULE__, :get_cache_stats)
  end

  @doc """
  Warm cache with frequently accessed data
  """
  def warm_cache(type, data_list) when type in @cache_names do
    GenServer.cast(__MODULE__, {:warm_cache, type, data_list})
  end

  @doc """
  Clear specific cache
  """
  def clear_cache(cache_name) when cache_name in @cache_names do
    GenServer.call(__MODULE__, {:clear_cache, cache_name})
  end

  @doc """
  Clear all caches
  """
  def clear_all_caches do
    GenServer.call(__MODULE__, :clear_all_caches)
  end

  @doc """
  Generate cache key from query parameters
  """
  def generate_query_key(table, operation, params) do
    data = {table, operation, params}
    :crypto.hash(:sha256, :erlang.term_to_binary(data))
    |> Base.encode16()
    |> binary_part(0, 16)
  end

  @doc """
  Prefetch data into cache
  """
  def prefetch_sessions(session_ids) do
    GenServer.cast(__MODULE__, {:prefetch_sessions, session_ids})
  end

  @doc """
  Prefetch model data
  """
  def prefetch_models(model_names) do
    GenServer.cast(__MODULE__, {:prefetch_models, model_names})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config = Keyword.get(opts, :config, @default_config)
    
    # Start Cachex processes
    cache_pids = start_caches(config)
    
    state = %__MODULE__{
      session_cache: cache_pids.session_cache,
      query_cache: cache_pids.query_cache,
      model_cache: cache_pids.model_cache,
      stats_cache: cache_pids.stats_cache,
      config: config
    }

    # Schedule periodic maintenance
    schedule_maintenance()
    
    Logger.info("QueryCache started with multi-level caching")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_cache_stats, _from, state) do
    stats = collect_cache_statistics(state)
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:clear_cache, cache_name}, _from, state) do
    result = Cachex.clear(cache_name)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:clear_all_caches, _from, state) do
    results = Enum.map(@cache_names, &Cachex.clear/1)
    all_success = Enum.all?(results, &(&1 == {:ok, 0} or elem(&1, 0) == :ok))
    {:reply, if(all_success, do: :ok, else: {:error, results}), state}
  end

  @impl true
  def handle_cast({:warm_cache, cache_type, data_list}, state) do
    warm_cache_with_data(cache_type, data_list)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:prefetch_sessions, session_ids}, state) do
    Task.start(fn -> prefetch_session_data(session_ids) end)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:prefetch_models, model_names}, state) do
    Task.start(fn -> prefetch_model_data(model_names) end)
    {:noreply, state}
  end

  @impl true
  def handle_info(:cache_maintenance, state) do
    perform_cache_maintenance(state)
    schedule_maintenance()
    {:noreply, state}
  end

  # Private Functions

  defp start_caches(config) do
    cache_results = Enum.map(@cache_names, fn cache_name ->
      cache_config = Map.get(config, cache_name, %{})
      
      options = [
        limit: Map.get(cache_config, :limit, 1000),
        expiration: expiration_options(cache_config),
        stats: Map.get(cache_config, :stats, true)
      ]
      
      case Cachex.start_link(cache_name, options) do
        {:ok, pid} -> {cache_name, pid}
        {:error, {:already_started, pid}} -> {cache_name, pid}
        error -> 
          Logger.error("Failed to start cache #{cache_name}: #{inspect(error)}")
          {cache_name, nil}
      end
    end)
    
    Map.new(cache_results)
  end

  defp expiration_options(cache_config) do
    ttl = Map.get(cache_config, :ttl, :timer.minutes(30))
    
    # Cachex expiration configuration
    import Cachex.Spec
    
    expiration(
      default: ttl,
      interval: :timer.minutes(1),  # Check every minute
      lazy: true                    # Only check on access
    )
  end

  defp cache_fetch(cache_name, key, fetch_fun) do
    case Cachex.fetch(cache_name, key, fetch_fun) do
      {:ok, value} -> 
        {:ok, value}
      {:commit, value} -> 
        # Value was fetched and cached
        {:ok, value}
      {:error, reason} -> 
        Logger.debug("Cache fetch failed for #{cache_name}:#{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp cache_put(cache_name, key, value, ttl) do
    options = if ttl, do: [ttl: ttl], else: []
    
    case Cachex.put(cache_name, key, value, options) do
      {:ok, true} -> :ok
      {:error, reason} -> 
        Logger.debug("Cache put failed for #{cache_name}:#{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp cache_delete(cache_name, key) do
    case Cachex.del(cache_name, key) do
      {:ok, _} -> :ok
      {:error, reason} -> 
        Logger.debug("Cache delete failed for #{cache_name}:#{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp collect_cache_statistics(_state) do
    Enum.reduce(@cache_names, %{}, fn cache_name, acc ->
      stats = case Cachex.stats(cache_name) do
        {:ok, cache_stats} -> 
          %{
            hit_rate: calculate_hit_rate(cache_stats),
            size: cache_stats.count || 0,
            memory: cache_stats.memory || 0,
            operations: %{
              hits: cache_stats.hits || 0,
              misses: cache_stats.misses || 0,
              writes: cache_stats.writes || 0,
              deletes: cache_stats.deletes || 0
            }
          }
        _ -> 
          %{hit_rate: 0.0, size: 0, memory: 0, operations: %{}}
      end
      
      Map.put(acc, cache_name, stats)
    end)
  end

  defp calculate_hit_rate(%{hits: hits, misses: misses}) when hits + misses > 0 do
    hits / (hits + misses)
  end
  defp calculate_hit_rate(_), do: 0.0

  defp warm_cache_with_data(cache_type, data_list) do
    Logger.info("Warming #{cache_type} with #{length(data_list)} items")
    
    Enum.each(data_list, fn {key, value} ->
      cache_put(cache_type, key, value, nil)
    end)
  end

  defp prefetch_session_data(session_ids) do
    Logger.debug("Prefetching #{length(session_ids)} sessions")
    
    Enum.each(session_ids, fn session_id ->
      # This would integrate with your actual data layer
      case RubberDuck.TransactionWrapper.read_records(:sessions, {:id, session_id}) do
        {:ok, [session]} ->
          put_session(session_id, session)
        _ ->
          :ok
      end
    end)
  end

  defp prefetch_model_data(model_names) do
    Logger.debug("Prefetching #{length(model_names)} models")
    
    Enum.each(model_names, fn model_name ->
      # This would integrate with your actual data layer  
      case RubberDuck.TransactionWrapper.read_records(:models, {:id, model_name}) do
        {:ok, [model]} ->
          put_model(model_name, model)
        _ ->
          :ok
      end
    end)
  end

  defp perform_cache_maintenance(_state) do
    # Perform periodic maintenance tasks
    maintenance_tasks = [
      &log_cache_performance/0,
      &cleanup_expired_entries/0,
      &rebalance_cache_sizes/0
    ]
    
    Enum.each(maintenance_tasks, fn task ->
      try do
        task.()
      rescue
        error ->
          Logger.warning("Cache maintenance task failed: #{inspect(error)}")
      end
    end)
  end

  defp log_cache_performance do
    stats = collect_cache_statistics(%{})
    
    # Log performance metrics
    Enum.each(stats, fn {cache_name, cache_stats} ->
      Logger.info("Cache #{cache_name}: #{cache_stats.size} items, " <>
                 "#{Float.round(cache_stats.hit_rate * 100, 1)}% hit rate, " <>
                 "#{div(cache_stats.memory, 1024)}KB memory")
    end)
  end

  defp cleanup_expired_entries do
    # Force cleanup of expired entries
    Enum.each(@cache_names, fn cache_name ->
      Cachex.purge(cache_name)
    end)
  end

  defp rebalance_cache_sizes do
    # Could implement dynamic cache size adjustment based on usage patterns
    # For now, just log cache sizes
    Enum.each(@cache_names, fn cache_name ->
      case Cachex.size(cache_name) do
        {:ok, size} ->
          if size > 0 do
            Logger.debug("Cache #{cache_name} size: #{size}")
          end
        _ -> :ok
      end
    end)
  end

  defp schedule_maintenance do
    Process.send_after(self(), :cache_maintenance, :timer.minutes(5))
  end
end