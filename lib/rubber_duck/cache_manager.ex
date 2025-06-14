defmodule RubberDuck.CacheManager do
  @moduledoc """
  Manages distributed caching for AI queries and responses.
  
  Implements a multi-tier caching strategy:
  - L1: Local in-memory cache for hot data
  - L2: Distributed cache across cluster nodes
  - Persistent: Mnesia-backed cache for expensive computations
  """
  
  use GenServer
  require Logger
  
  @cache_name :ai_query_cache
  @ttl_default :timer.hours(24)
  @ttl_context :timer.hours(1)
  @ttl_analysis :timer.hours(6)
  @max_cache_size 10_000
  
  # Cache key prefixes
  @prefix_context "context:"
  @prefix_analysis "analysis:"
  @prefix_llm "llm:"
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Start Cachex with configuration optimized for AI workloads
    case Cachex.start_link(@cache_name, [
      limit: @max_cache_size,
      stats: true,
      # Set default TTL
      ttl: @ttl_default
    ]) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      error -> throw(error)
    end
    
    state = %{
      cache_name: @cache_name,
      hit_count: 0,
      miss_count: 0,
      last_cleanup: DateTime.utc_now()
    }
    
    # Schedule periodic maintenance
    schedule_maintenance()
    
    {:ok, state}
  end
  
  @doc """
  Caches an AI context with appropriate TTL
  """
  def cache_context(session_id, context) do
    key = @prefix_context <> session_id
    GenServer.cast(__MODULE__, {:cache, key, context, @ttl_context})
  end
  
  @doc """
  Retrieves cached context for a session
  """
  def get_context(session_id) do
    key = @prefix_context <> session_id
    get_cached(key)
  end
  
  @doc """
  Caches code analysis results
  """
  def cache_analysis(file_path, analysis) do
    key = @prefix_analysis <> file_path
    GenServer.cast(__MODULE__, {:cache, key, analysis, @ttl_analysis})
  end
  
  @doc """
  Retrieves cached analysis for a file
  """
  def get_analysis(file_path) do
    key = @prefix_analysis <> file_path
    get_cached(key)
  end
  
  @doc """
  Caches LLM responses with content-based key
  """
  def cache_llm_response(prompt, model, response) do
    key = generate_llm_key(prompt, model)
    ttl = calculate_llm_ttl(response)
    GenServer.cast(__MODULE__, {:cache, key, response, ttl})
  end
  
  @doc """
  Retrieves cached LLM response
  """
  def get_llm_response(prompt, model) do
    key = generate_llm_key(prompt, model)
    get_cached(key)
  end
  
  @doc """
  Precomputes and caches common queries
  """
  def precompute_common_queries(queries) do
    GenServer.cast(__MODULE__, {:precompute, queries})
  end
  
  @doc """
  Returns cache statistics
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  @doc """
  Clears specific cache entries by pattern
  """
  def clear_pattern(pattern) do
    GenServer.call(__MODULE__, {:clear_pattern, pattern})
  end
  
  # Callbacks
  
  def handle_cast({:cache, key, value, ttl}, state) do
    case Cachex.put(@cache_name, key, value, ttl: ttl) do
      {:ok, true} ->
        Logger.debug("Cached #{key} with TTL #{ttl}ms")
      {:error, reason} ->
        Logger.warning("Failed to cache #{key}: #{inspect(reason)}")
    end
    
    {:noreply, state}
  end
  
  def handle_cast({:precompute, queries}, state) do
    Task.async_stream(queries, fn query ->
      # Simulate precomputation
      result = compute_expensive_operation(query)
      key = "precomputed:" <> Base.encode64(:crypto.hash(:sha256, query))
      Cachex.put(@cache_name, key, result, ttl: @ttl_default)
    end, max_concurrency: 4)
    |> Stream.run()
    
    {:noreply, state}
  end
  
  def handle_call(:get_stats, _from, state) do
    {:ok, cachex_stats} = Cachex.stats(@cache_name)
    
    stats = %{
      hit_rate: calculate_hit_rate(cachex_stats),
      size: Cachex.size(@cache_name),
      memory: estimate_memory_usage(),
      cachex_stats: cachex_stats,
      last_cleanup: state.last_cleanup
    }
    
    {:reply, stats, state}
  end
  
  def handle_call({:clear_pattern, pattern}, _from, state) do
    count = clear_matching_keys(pattern)
    {:reply, {:ok, count}, state}
  end
  
  def handle_info(:maintenance, state) do
    Logger.debug("Running cache maintenance")
    
    # Clean expired entries
    {:ok, _cleaned} = Cachex.purge(@cache_name)
    
    # Persist important entries to Mnesia
    persist_valuable_entries()
    
    # Update statistics
    update_hit_miss_stats()
    
    # Schedule next maintenance
    schedule_maintenance()
    
    new_state = %{state | last_cleanup: DateTime.utc_now()}
    {:noreply, new_state}
  end
  
  # Private functions
  
  defp get_cached(key) do
    case Cachex.get(@cache_name, key) do
      {:ok, nil} ->
        # Try to load from Mnesia if not in cache
        load_from_persistent(key)
      {:ok, value} ->
        {:ok, value}
      {:error, reason} ->
        Logger.warning("Cache get error for #{key}: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp generate_llm_key(prompt, model) do
    content = "#{model}:#{prompt}"
    hash = Base.encode64(:crypto.hash(:sha256, content), padding: false)
    @prefix_llm <> hash
  end
  
  defp calculate_llm_ttl(response) do
    # Adjust TTL based on response characteristics
    cond do
      # Code explanations change less frequently
      String.contains?(response, ["def ", "defmodule", "function"]) ->
        :timer.hours(48)
      
      # Error messages might change with fixes
      String.contains?(response, ["error", "exception", "failed"]) ->
        :timer.hours(2)
      
      # Default TTL
      true ->
        @ttl_default
    end
  end
  
  defp compute_expensive_operation(query) do
    # Placeholder for expensive computation
    Process.sleep(100)
    "Precomputed result for: #{query}"
  end
  
  defp calculate_hit_rate(%{hits: hits, misses: misses}) when hits + misses > 0 do
    Float.round(hits / (hits + misses) * 100, 2)
  end
  defp calculate_hit_rate(_), do: 0.0
  
  defp estimate_memory_usage do
    case Cachex.size(@cache_name) do
      {:ok, size} ->
        # Rough estimate: 1KB average per entry
        size * 1024
      _ ->
        0
    end
  end
  
  defp clear_matching_keys(pattern) do
    regex = Regex.compile!(pattern)
    
    {:ok, keys} = Cachex.keys(@cache_name)
    matching_keys = Enum.filter(keys, &Regex.match?(regex, &1))
    
    Enum.each(matching_keys, fn key ->
      Cachex.del(@cache_name, key)
    end)
    
    length(matching_keys)
  end
  
  defp persist_valuable_entries do
    # Persist entries with high access count to Mnesia
    {:ok, keys} = Cachex.keys(@cache_name)
    
    # For now, just persist a sample of keys
    # In production, we'd track access counts separately
    keys
    |> Enum.take(100)  # Limit to top 100 entries
    |> Enum.each(fn key ->
      case Cachex.get(@cache_name, key) do
        {:ok, value} when value != nil ->
          persist_to_mnesia(key, value)
        _ ->
          :ok
      end
    end)
  end
  
  defp persist_to_mnesia(_key, _value) do
    # This would integrate with MnesiaManager in production
    Logger.debug("Would persist to Mnesia")
  end
  
  defp load_from_persistent(_key) do
    # This would load from Mnesia in production
    {:ok, nil}
  end
  
  defp update_hit_miss_stats do
    # Update internal statistics
    {:ok, stats} = Cachex.stats(@cache_name)
    Logger.info("Cache stats - Hit rate: #{calculate_hit_rate(stats)}%")
  end
  
  defp schedule_maintenance do
    Process.send_after(self(), :maintenance, :timer.minutes(15))
  end
end