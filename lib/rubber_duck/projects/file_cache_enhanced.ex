defmodule RubberDuck.Projects.FileCacheEnhanced do
  @moduledoc """
  Enhanced ETS-based caching system with advanced features.
  
  Improvements over basic FileCache:
  - Integration with CacheStats for metrics
  - Cascading invalidation
  - Soft invalidation with background refresh
  - Memory management with LRU eviction
  - Version-based invalidation
  - Cache warming capabilities
  """
  
  use GenServer
  require Logger
  
  alias RubberDuck.Projects.CacheStats
  
  @table_name :rubber_duck_file_cache_v2
  @meta_table :rubber_duck_cache_meta
  @default_ttl :timer.minutes(5)
  @cleanup_interval :timer.minutes(1)
  @max_cache_size 100_000_000  # 100MB default
  @lru_check_interval :timer.seconds(30)
  
  defstruct [
    :max_size,
    :current_size,
    :version,
    :warmup_queue,
    :refresh_queue
  ]
  
  # Client API
  
  @doc """
  Starts the enhanced FileCache GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Gets a value from the cache with integrated statistics.
  """
  def get(project_id, path, opts \\ []) do
    key = build_key(project_id, path)
    
    case :ets.lookup(@table_name, key) do
      [{^key, entry}] ->
        handle_cache_hit(project_id, path, entry, opts)
        
      [] ->
        CacheStats.record_miss(project_id, path)
        
        if Keyword.get(opts, :refresh_on_miss, false) do
          GenServer.cast(__MODULE__, {:queue_refresh, project_id, path})
        end
        
        :miss
    end
  end
  
  @doc """
  Puts a value with enhanced metadata and versioning.
  """
  def put(project_id, path, value, opts \\ []) do
    GenServer.call(__MODULE__, {:put, project_id, path, value, opts})
  end
  
  @doc """
  Invalidates entries with cascading support.
  """
  def invalidate(project_id, path, opts \\ []) do
    GenServer.call(__MODULE__, {:invalidate, project_id, path, opts})
  end
  
  @doc """
  Performs soft invalidation - marks entries for refresh without removing.
  """
  def soft_invalidate(project_id, path) do
    GenServer.call(__MODULE__, {:soft_invalidate, project_id, path})
  end
  
  @doc """
  Invalidates by version - useful for bulk updates.
  """
  def invalidate_version(project_id, version) do
    GenServer.call(__MODULE__, {:invalidate_version, project_id, version})
  end
  
  @doc """
  Warms the cache with frequently accessed paths.
  """
  def warm_cache(project_id, paths, loader_fun) do
    GenServer.cast(__MODULE__, {:warm_cache, project_id, paths, loader_fun})
  end
  
  @doc """
  Gets memory usage information.
  """
  def memory_info do
    GenServer.call(__MODULE__, :memory_info)
  end
  
  @doc """
  Registers an invalidation hook.
  """
  def register_invalidation_hook(name, fun) do
    GenServer.call(__MODULE__, {:register_hook, name, fun})
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    # Create ETS tables
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])
    
    :ets.new(@meta_table, [
      :set,
      :private,
      :named_table
    ])
    
    # Start CacheStats if not already started
    ensure_cache_stats_started()
    
    # Schedule periodic tasks
    schedule_cleanup()
    schedule_lru_check()
    
    state = %__MODULE__{
      max_size: Keyword.get(opts, :max_size, @max_cache_size),
      current_size: 0,
      version: 1,
      warmup_queue: :queue.new(),
      refresh_queue: :queue.new()
    }
    
    # Store invalidation hooks
    :ets.insert(@meta_table, {:hooks, %{}})
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:put, project_id, path, value, opts}, _from, state) do
    key = build_key(project_id, path)
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    expiry = DateTime.add(DateTime.utc_now(), ttl, :millisecond)
    
    # Calculate entry size
    size = estimate_size(value)
    
    # Check if we need to evict entries
    state = maybe_evict_lru(state, size)
    
    # Create cache entry with metadata
    entry = %{
      value: value,
      expiry: expiry,
      size: size,
      version: state.version,
      access_count: 0,
      last_access: System.monotonic_time(:millisecond),
      metadata: Keyword.get(opts, :metadata, %{})
    }
    
    # Check if replacing existing entry
    old_size = case :ets.lookup(@table_name, key) do
      [{^key, old_entry}] -> old_entry.size
      [] -> 0
    end
    
    # Insert new entry
    :ets.insert(@table_name, {key, entry})
    
    # Update state and stats
    new_size = state.current_size - old_size + size
    CacheStats.record_put(project_id, path, size)
    
    {:reply, :ok, %{state | current_size: new_size}}
  end
  
  @impl true
  def handle_call({:invalidate, project_id, path, opts}, _from, state) do
    cascade = Keyword.get(opts, :cascade, false)
    
    if cascade do
      count = invalidate_cascade(project_id, path)
      {:reply, {:ok, count}, state}
    else
      key = build_key(project_id, path)
      size = delete_entry(key)
      
      # Run hooks
      run_invalidation_hooks(project_id, path)
      
      {:reply, :ok, %{state | current_size: state.current_size - size}}
    end
  end
  
  @impl true
  def handle_call({:soft_invalidate, project_id, path}, _from, state) do
    key = build_key(project_id, path)
    
    case :ets.lookup(@table_name, key) do
      [{^key, entry}] ->
        # Mark as stale
        updated_entry = Map.put(entry, :stale, true)
        :ets.insert(@table_name, {key, updated_entry})
        
        # Queue for refresh
        new_queue = :queue.in({project_id, path}, state.refresh_queue)
        {:reply, :ok, %{state | refresh_queue: new_queue}}
        
      [] ->
        {:reply, :ok, state}
    end
  end
  
  @impl true
  def handle_call({:invalidate_version, project_id, version}, _from, state) do
    # Find all entries with matching version
    pattern = [
      {
        {{project_id, :_}, %{version: version}},
        [],
        [:"$_"]
      }
    ]
    
    entries = :ets.select(@table_name, pattern)
    total_size = Enum.reduce(entries, 0, fn {{key, _}, entry}, acc ->
      :ets.delete(@table_name, key)
      acc + entry.size
    end)
    
    {:reply, {:ok, length(entries)}, %{state | current_size: state.current_size - total_size}}
  end
  
  @impl true
  def handle_call(:memory_info, _from, state) do
    info = %{
      current_size: state.current_size,
      max_size: state.max_size,
      utilization: Float.round(state.current_size / state.max_size * 100, 2),
      entry_count: :ets.info(@table_name, :size),
      table_memory: :ets.info(@table_name, :memory) * :erlang.system_info(:wordsize)
    }
    
    {:reply, info, state}
  end
  
  @impl true
  def handle_call({:register_hook, name, fun}, _from, state) do
    [{:hooks, hooks}] = :ets.lookup(@meta_table, :hooks)
    updated_hooks = Map.put(hooks, name, fun)
    :ets.insert(@meta_table, {:hooks, updated_hooks})
    
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_cast({:warm_cache, project_id, paths, loader_fun}, state) do
    # Add paths to warmup queue
    new_queue = Enum.reduce(paths, state.warmup_queue, fn path, queue ->
      :queue.in({project_id, path, loader_fun}, queue)
    end)
    
    # Process queue asynchronously
    send(self(), :process_warmup_queue)
    
    {:noreply, %{state | warmup_queue: new_queue}}
  end
  
  @impl true
  def handle_cast({:queue_refresh, project_id, path}, state) do
    new_queue = :queue.in({project_id, path}, state.refresh_queue)
    send(self(), :process_refresh_queue)
    
    {:noreply, %{state | refresh_queue: new_queue}}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    {evicted_count, evicted_size} = cleanup_expired()
    
    Logger.debug("Cache cleanup: evicted #{evicted_count} entries, freed #{evicted_size} bytes")
    
    # Update stats
    state = %{state | current_size: state.current_size - evicted_size}
    
    # Schedule next cleanup
    schedule_cleanup()
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:lru_check, state) do
    # Check if we're over capacity
    state = if state.current_size > state.max_size do
      evict_lru_entries(state, state.current_size - state.max_size)
    else
      state
    end
    
    # Schedule next check
    schedule_lru_check()
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info(:process_warmup_queue, state) do
    # Process up to 10 items from warmup queue
    {_processed, new_queue} = process_queue_batch(state.warmup_queue, 10, fn {project_id, path, loader_fun} ->
      case loader_fun.(path) do
        {:ok, value} ->
          put(project_id, path, value, [ttl: :timer.hours(1)])
          Logger.debug("Warmed cache for #{project_id}:#{path}")
          
        error ->
          Logger.warning("Failed to warm cache for #{project_id}:#{path}: #{inspect(error)}")
      end
    end)
    
    # Schedule more processing if queue not empty
    if not :queue.is_empty(new_queue) do
      Process.send_after(self(), :process_warmup_queue, 100)
    end
    
    {:noreply, %{state | warmup_queue: new_queue}}
  end
  
  @impl true
  def handle_info(:process_refresh_queue, state) do
    # Process refresh queue similarly
    # Implementation would depend on how to refresh entries
    {:noreply, state}
  end
  
  # Private Functions
  
  defp handle_cache_hit(project_id, path, entry, opts) do
    now = System.monotonic_time(:millisecond)
    
    # Check expiry
    if DateTime.compare(DateTime.utc_now(), entry.expiry) == :lt do
      # Check if stale
      if Map.get(entry, :stale, false) and not Keyword.get(opts, :allow_stale, false) do
        CacheStats.record_miss(project_id, path)
        :miss
      else
        # Update access metadata
        updated_entry = entry
        |> Map.update(:access_count, 1, &(&1 + 1))
        |> Map.put(:last_access, now)
        
        key = build_key(project_id, path)
        :ets.insert(@table_name, {key, updated_entry})
        
        CacheStats.record_hit(project_id, path, entry.size)
        {:ok, entry.value}
      end
    else
      # Expired
      key = build_key(project_id, path)
      :ets.delete(@table_name, key)
      CacheStats.record_miss(project_id, path)
      :miss
    end
  end
  
  defp build_key(project_id, path) do
    {project_id, normalize_path(path)}
  end
  
  defp normalize_path(path) do
    path
    |> Path.expand("/")
    |> Path.relative_to("/")
  end
  
  defp estimate_size(value) do
    :erlang.external_size(value)
  end
  
  defp maybe_evict_lru(state, needed_size) do
    if state.current_size + needed_size > state.max_size do
      evict_lru_entries(state, needed_size)
    else
      state
    end
  end
  
  defp evict_lru_entries(state, target_size) do
    # Get all entries sorted by last access time
    entries = :ets.tab2list(@table_name)
    |> Enum.sort_by(fn {_key, entry} -> entry.last_access end)
    
    # Evict until we have enough space
    {evicted_size, _remaining} = Enum.reduce_while(entries, {0, []}, fn {key, entry}, {size, keep} ->
      if size >= target_size do
        {:halt, {size, keep}}
      else
        :ets.delete(@table_name, key)
        log_eviction(key, entry)
        {:cont, {size + entry.size, keep}}
      end
    end)
    
    %{state | current_size: state.current_size - evicted_size}
  end
  
  defp delete_entry(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, entry}] ->
        :ets.delete(@table_name, key)
        {project_id, path} = key
        CacheStats.record_delete(project_id, path, entry.size)
        entry.size
        
      [] ->
        0
    end
  end
  
  defp invalidate_cascade(project_id, path) do
    # Invalidate the entry and all children
    pattern = build_cascade_pattern(project_id, path)
    
    entries = :ets.select(@table_name, pattern)
    _total_size = Enum.reduce(entries, 0, fn {key, entry}, acc ->
      :ets.delete(@table_name, key)
      acc + entry.size
    end)
    
    length(entries)
  end
  
  defp build_cascade_pattern(project_id, path) do
    # Match all paths that start with the given path
    [
      {
        {{project_id, :"$1"}, :_},
        [{:orelse, 
          {:==, :"$1", path},
          {:andalso,
            {:>=, {:byte_size, :"$1"}, {:byte_size, path}},
            {:==, {:binary_part, :"$1", 0, {:byte_size, path}}, path}
          }
        }],
        [:"$_"]
      }
    ]
  end
  
  defp cleanup_expired do
    now = DateTime.utc_now()
    
    # Find all expired entries
    pattern = [
      {
        {:_, %{expiry: :"$1", size: :"$2"}},
        [{:<, :"$1", {:const, now}}],
        [{{:"$_", :"$2"}}]
      }
    ]
    
    results = :ets.select(@table_name, pattern)
    
    # Delete and sum sizes
    {count, total_size} = Enum.reduce(results, {0, 0}, fn {{key, _}, size}, {c, s} ->
      :ets.delete(@table_name, key)
      {c + 1, s + size}
    end)
    
    {count, total_size}
  end
  
  defp run_invalidation_hooks(project_id, path) do
    [{:hooks, hooks}] = :ets.lookup(@meta_table, :hooks)
    
    Enum.each(hooks, fn {_name, hook_fun} ->
      try do
        hook_fun.(project_id, path)
      rescue
        error ->
          Logger.error("Invalidation hook error: #{inspect(error)}")
      end
    end)
  end
  
  defp log_eviction({project_id, path}, entry) do
    Logger.debug("LRU eviction: #{project_id}:#{path}, size: #{entry.size}, last_access: #{entry.last_access}")
  end
  
  defp process_queue_batch(queue, batch_size, processor) do
    process_queue_batch(queue, batch_size, processor, 0, queue)
  end
  
  defp process_queue_batch(_queue, batch_size, _processor, processed, new_queue) when processed >= batch_size do
    {processed, new_queue}
  end
  
  defp process_queue_batch(queue, batch_size, processor, processed, _) do
    case :queue.out(queue) do
      {{:value, item}, rest} ->
        processor.(item)
        process_queue_batch(rest, batch_size, processor, processed + 1, rest)
        
      {:empty, _} ->
        {processed, queue}
    end
  end
  
  defp ensure_cache_stats_started do
    case Process.whereis(CacheStats) do
      nil -> CacheStats.start_link()
      _pid -> :ok
    end
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
  
  defp schedule_lru_check do
    Process.send_after(self(), :lru_check, @lru_check_interval)
  end
end