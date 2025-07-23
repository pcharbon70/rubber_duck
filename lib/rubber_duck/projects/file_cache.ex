defmodule RubberDuck.Projects.FileCache do
  @moduledoc """
  ETS-based caching system for file metadata and directory listings.
  
  Provides efficient caching with project-based partitioning, TTL management,
  and automatic invalidation on file system changes.
  """
  
  use GenServer
  require Logger
  
  @table_name :rubber_duck_file_cache
  @default_ttl :timer.minutes(5)
  @cleanup_interval :timer.minutes(1)
  
  # Client API
  
  @doc """
  Starts the FileCache GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Gets a value from the cache.
  
  Returns {:ok, value} if found and not expired, :miss otherwise.
  """
  def get(project_id, path) do
    key = build_key(project_id, path)
    
    case :ets.lookup(@table_name, key) do
      [{^key, value, expiry}] ->
        if DateTime.compare(DateTime.utc_now(), expiry) == :lt do
          {:ok, value}
        else
          # Expired entry, delete it
          :ets.delete(@table_name, key)
          :miss
        end
        
      [] ->
        :miss
    end
  end
  
  @doc """
  Puts a value in the cache with optional TTL.
  """
  def put(project_id, path, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    key = build_key(project_id, path)
    expiry = DateTime.add(DateTime.utc_now(), ttl, :millisecond)
    
    :ets.insert(@table_name, {key, value, expiry})
    :ok
  end
  
  @doc """
  Invalidates a specific cache entry.
  """
  def invalidate(project_id, path) do
    key = build_key(project_id, path)
    :ets.delete(@table_name, key)
    :ok
  end
  
  @doc """
  Invalidates all cache entries for a project.
  """
  def invalidate_project(project_id) do
    pattern = {{project_id, :_}, :_, :_}
    :ets.match_delete(@table_name, pattern)
    :ok
  end
  
  @doc """
  Invalidates cache entries matching a path pattern.
  
  Supports wildcards: "*" matches any single segment, "**" matches any number of segments.
  """
  def invalidate_pattern(project_id, path_pattern) do
    GenServer.call(__MODULE__, {:invalidate_pattern, project_id, path_pattern})
  end
  
  @doc """
  Gets cache statistics for monitoring.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end
  
  @doc """
  Clears all cache entries.
  """
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  end
  
  # Server callbacks
  
  @impl true
  def init(_opts) do
    # Create ETS table
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])
    
    # Schedule periodic cleanup
    schedule_cleanup()
    
    state = %{
      hits: 0,
      misses: 0,
      evictions: 0,
      last_cleanup: DateTime.utc_now()
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:invalidate_pattern, project_id, pattern}, _from, state) do
    count = do_invalidate_pattern(project_id, pattern)
    {:reply, {:ok, count}, state}
  end
  
  @impl true
  def handle_call(:stats, _from, state) do
    table_info = :ets.info(@table_name)
    
    stats = %{
      size: Keyword.get(table_info, :size, 0),
      memory: Keyword.get(table_info, :memory, 0),
      hits: state.hits,
      misses: state.misses,
      evictions: state.evictions,
      hit_rate: calculate_hit_rate(state.hits, state.misses),
      last_cleanup: state.last_cleanup
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    evicted = cleanup_expired()
    
    # Schedule next cleanup
    schedule_cleanup()
    
    new_state = %{state | 
      evictions: state.evictions + evicted,
      last_cleanup: DateTime.utc_now()
    }
    
    {:noreply, new_state}
  end
  
  # Private functions
  
  defp build_key(project_id, path) do
    {project_id, normalize_path(path)}
  end
  
  defp normalize_path(path) do
    path
    |> Path.expand("/")
    |> Path.relative_to("/")
  end
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
  
  defp cleanup_expired do
    now = DateTime.utc_now()
    
    # Find all expired entries
    expired = :ets.select(@table_name, [
      {
        {:_, :_, :"$1"},
        [{:<, :"$1", {:const, now}}],
        [:"$_"]
      }
    ])
    
    # Delete them
    Enum.each(expired, fn {key, _, _} ->
      :ets.delete(@table_name, key)
    end)
    
    length(expired)
  end
  
  defp do_invalidate_pattern(project_id, pattern) do
    # Convert pattern to regex
    regex = pattern_to_regex(pattern)
    
    # Find all matching keys
    matches = :ets.select(@table_name, [
      {
        {{project_id, :"$1"}, :_, :_},
        [],
        [:"$1"]
      }
    ])
    
    # Filter by regex and delete
    count = matches
    |> Enum.filter(&Regex.match?(regex, &1))
    |> Enum.map(&:ets.delete(@table_name, {project_id, &1}))
    |> length()
    
    count
  end
  
  defp pattern_to_regex(pattern) do
    pattern
    |> String.replace("**", "DOUBLE_STAR")
    |> String.replace("*", "[^/]+")
    |> String.replace("DOUBLE_STAR", ".*")
    |> then(&"^#{&1}$")
    |> Regex.compile!()
  end
  
  defp calculate_hit_rate(0, 0), do: 0.0
  defp calculate_hit_rate(hits, misses) do
    Float.round(hits / (hits + misses) * 100, 2)
  end
end