defmodule RubberDuck.Workflows.Cache do
  @moduledoc """
  Caching layer for workflow step results.
  
  Provides:
  - In-memory caching with ETS
  - Configurable TTL per step
  - Optional persistence to database
  - Cache invalidation strategies
  """
  
  use GenServer
  
  require Logger
  
  @table_name :workflow_cache
  @cleanup_interval :timer.minutes(5)
  @default_ttl :timer.hours(1)
  
  # Client API
  
  @doc """
  Starts the cache server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Gets a value from the cache.
  """
  def get(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, expiry}] ->
        if DateTime.compare(expiry, DateTime.utc_now()) == :gt do
          {:ok, value}
        else
          # Expired, remove it
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
  def put(key, value, ttl \\ nil) do
    ttl = ttl || @default_ttl
    expiry = DateTime.add(DateTime.utc_now(), ttl, :millisecond)
    
    :ets.insert(@table_name, {key, value, expiry})
    :ok
  end
  
  @doc """
  Deletes a value from the cache.
  """
  def delete(key) do
    :ets.delete(@table_name, key)
    :ok
  end
  
  @doc """
  Clears the entire cache.
  """
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  end
  
  @doc """
  Invalidates cache entries matching a pattern.
  """
  def invalidate_pattern(pattern) do
    GenServer.call(__MODULE__, {:invalidate_pattern, pattern})
  end
  
  @doc """
  Gets cache statistics.
  """
  def stats do
    GenServer.call(__MODULE__, :stats)
  end
  
  @doc """
  Generates a cache key for a workflow and input.
  """
  def generate_key(workflow, input) do
    workflow_name = get_workflow_name(workflow)
    input_hash = :erlang.phash2(input)
    
    "#{workflow_name}:#{input_hash}"
  end
  
  @doc """
  Wraps a function with caching.
  """
  def cached(key, ttl \\ nil, fun) do
    case get(key) do
      {:ok, value} ->
        Logger.debug("Cache hit for key: #{key}")
        value
        
      :miss ->
        Logger.debug("Cache miss for key: #{key}")
        value = fun.()
        put(key, value, ttl)
        value
    end
  end
  
  # Server callbacks
  
  @impl true
  def init(opts) do
    # Create ETS table
    :ets.new(@table_name, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true
    ])
    
    # Schedule periodic cleanup
    schedule_cleanup()
    
    state = %{
      stats: %{
        hits: 0,
        misses: 0,
        puts: 0,
        deletes: 0
      },
      persist?: opts[:persist?] || false,
      cleanup_interval: opts[:cleanup_interval] || @cleanup_interval
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:invalidate_pattern, pattern}, _from, state) do
    # Find all keys matching the pattern
    match_spec = [{{:"$1", :_, :_}, [{:match, :"$1", pattern}], [:"$1"]}]
    keys = :ets.select(@table_name, match_spec)
    
    # Delete matching keys
    Enum.each(keys, &:ets.delete(@table_name, &1))
    
    count = length(keys)
    Logger.info("Invalidated #{count} cache entries matching pattern: #{inspect(pattern)}")
    
    new_state = update_in(state.stats.deletes, &(&1 + count))
    
    {:reply, {:ok, count}, new_state}
  end
  
  @impl true
  def handle_call(:stats, _from, state) do
    cache_size = :ets.info(@table_name, :size)
    memory = :ets.info(@table_name, :memory)
    
    stats = Map.merge(state.stats, %{
      size: cache_size,
      memory_bytes: memory * :erlang.system_info(:wordsize)
    })
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    # Remove expired entries
    expired_count = cleanup_expired()
    
    if expired_count > 0 do
      Logger.debug("Cleaned up #{expired_count} expired cache entries")
    end
    
    # Schedule next cleanup
    schedule_cleanup()
    
    {:noreply, state}
  end
  
  # Private functions
  
  defp get_workflow_name(workflow) when is_atom(workflow) do
    workflow |> to_string() |> String.split(".") |> List.last()
  end
  
  defp get_workflow_name(workflow) when is_binary(workflow), do: workflow
  
  defp get_workflow_name(%{name: name}), do: to_string(name)
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
  
  defp cleanup_expired do
    now = DateTime.utc_now()
    
    # Find expired entries
    match_spec = [{{:"$1", :"$2", :"$3"}, [{:<, :"$3", now}], [:"$1"]}]
    expired_keys = :ets.select(@table_name, match_spec)
    
    # Delete them
    Enum.each(expired_keys, &:ets.delete(@table_name, &1))
    
    length(expired_keys)
  end
  
  defmodule Persistence do
    @moduledoc """
    Optional persistence layer for workflow cache.
    Stores cache entries in database for recovery after restart.
    """
    
    # This would integrate with your database layer
    # For now, it's a placeholder for future implementation
    
    def save(_key, _value, _expiry), do: :ok
    
    def load(_key), do: nil
    
    def delete(_key), do: :ok
    
    def restore_to_ets(_table_name), do: :ok
  end
end