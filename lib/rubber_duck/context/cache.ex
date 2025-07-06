defmodule RubberDuck.Context.Cache do
  @moduledoc """
  ETS-based cache for context building with TTL support.
  
  Caches built contexts to avoid expensive rebuilding for repeated queries.
  Includes automatic expiration and cache statistics.
  """

  use GenServer
  require Logger

  @table_name :context_cache
  @default_ttl_minutes 15
  @cleanup_interval_ms 60_000  # 1 minute

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a cached context if available and not expired.
  """
  def get(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, context, expiry}] ->
        if DateTime.compare(DateTime.utc_now(), expiry) == :lt do
          update_stats(:hit)
          {:ok, context}
        else
          # Expired, remove it
          :ets.delete(@table_name, key)
          update_stats(:miss)
          {:error, :not_found}
        end
      [] ->
        update_stats(:miss)
        {:error, :not_found}
    end
  end

  @doc """
  Stores a context in the cache with TTL.
  """
  def put(key, context, ttl_minutes \\ @default_ttl_minutes) do
    expiry = DateTime.add(DateTime.utc_now(), ttl_minutes * 60, :second)
    :ets.insert(@table_name, {key, context, expiry})
    update_stats(:put)
    :ok
  end

  @doc """
  Invalidates a specific cache entry.
  """
  def invalidate(key) do
    :ets.delete(@table_name, key)
    update_stats(:invalidate)
    :ok
  end

  @doc """
  Invalidates all cache entries matching a pattern.
  Pattern can include user_id or session_id.
  """
  def invalidate_pattern(%{user_id: user_id}) do
    # Since cache keys are hashed, we need to iterate through all entries
    # and check if they belong to the user
    all_keys = :ets.select(@table_name, [{{:"$1", :_, :_}, [], [:"$1"]}])
    
    # Filter and delete keys that match the pattern
    Enum.each(all_keys, fn key ->
      if String.contains?(to_string(key), user_id) do
        :ets.delete(@table_name, key)
      end
    end)
    
    :ok
  end

  @doc """
  Clears the entire cache.
  """
  def clear() do
    # Preserve stats
    stats = case :ets.lookup(@table_name, :stats) do
      [{:stats, s}] -> s
      [] -> %{hits: 0, misses: 0, puts: 0, invalidations: 0}
    end
    
    # Clear all entries
    :ets.delete_all_objects(@table_name)
    
    # Restore stats
    :ets.insert(@table_name, {:stats, stats})
    
    :ok
  end

  @doc """
  Returns cache statistics.
  """
  def stats() do
    case :ets.lookup(@table_name, :stats) do
      [{:stats, stats}] -> stats
      [] -> %{hits: 0, misses: 0, puts: 0, invalidations: 0}
    end
  end

  @doc """
  Generates a cache key from query and options.
  """
  def generate_key(query, opts) do
    user_id = Keyword.get(opts, :user_id, "anonymous")
    session_id = Keyword.get(opts, :session_id, "default")
    strategy = Keyword.get(opts, :strategy, :auto)
    
    # Create a deterministic key
    data = "#{user_id}:#{session_id}:#{strategy}:#{query}"
    :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Create ETS table
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])
    
    # Initialize stats
    :ets.insert(@table_name, {:stats, %{hits: 0, misses: 0, puts: 0, invalidations: 0}})
    
    # Schedule periodic cleanup
    schedule_cleanup()
    
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup()
    {:noreply, state}
  end

  # Private functions

  defp schedule_cleanup() do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp cleanup_expired() do
    now = DateTime.utc_now()
    
    expired_count = :ets.select_delete(@table_name, [
      {{~c"$1", :_, ~c"$2"}, [{:>, now, ~c"$2"}], [true]}
    ])
    
    if expired_count > 0 do
      Logger.debug("Context cache: cleaned up #{expired_count} expired entries")
    end
  end

  defp update_stats(type) do
    try do
      # Get current stats
      case :ets.lookup(@table_name, :stats) do
        [{:stats, current_stats}] ->
          # Update the specific counter
          updated_stats = Map.update(current_stats, type, 1, &(&1 + 1))
          :ets.insert(@table_name, {:stats, updated_stats})
        [] ->
          # Initialize with this stat
          :ets.insert(@table_name, {:stats, %{hits: 0, misses: 0, puts: 0, invalidations: 0} |> Map.put(type, 1)})
      end
    catch
      :error, _ ->
        # Table might not exist yet, ignore
        :ok
    end
  end
end