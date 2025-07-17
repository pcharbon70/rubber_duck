defmodule RubberDuck.Cache.ETS do
  @moduledoc """
  ETS-based caching implementation for tool results.
  
  Provides a simple in-memory cache using ETS tables with TTL support.
  """
  
  use GenServer
  require Logger
  
  @table_name :rubber_duck_cache
  @cleanup_interval 60_000 # 1 minute
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Stores a value in the cache with optional TTL.
  """
  @spec put(String.t(), term(), non_neg_integer()) :: :ok | {:error, atom()}
  def put(key, value, ttl \\ 3600) do
    expire_at = System.system_time(:second) + ttl
    
    try do
      :ets.insert(@table_name, {key, value, expire_at})
      :ok
    rescue
      ArgumentError -> {:error, :table_not_found}
      error -> {:error, error}
    end
  end
  
  @doc """
  Retrieves a value from the cache.
  """
  @spec get(String.t()) :: {:ok, term()} | {:error, :not_found}
  def get(key) do
    current_time = System.system_time(:second)
    
    try do
      case :ets.lookup(@table_name, key) do
        [{^key, value, expire_at}] when expire_at > current_time ->
          {:ok, value}
        [{^key, _value, _expire_at}] ->
          # Expired, remove it
          :ets.delete(@table_name, key)
          {:error, :not_found}
        [] ->
          {:error, :not_found}
      end
    rescue
      ArgumentError -> {:error, :not_found}
      error -> {:error, error}
    end
  end
  
  @doc """
  Removes a value from the cache.
  """
  @spec delete(String.t()) :: :ok
  def delete(key) do
    try do
      :ets.delete(@table_name, key)
      :ok
    rescue
      ArgumentError -> :ok
      _error -> :ok
    end
  end
  
  @doc """
  Clears all entries from the cache.
  """
  @spec clear() :: :ok
  def clear do
    try do
      :ets.delete_all_objects(@table_name)
      :ok
    rescue
      ArgumentError -> :ok
      _error -> :ok
    end
  end
  
  @doc """
  Gets cache statistics.
  """
  @spec stats() :: map()
  def stats do
    try do
      current_time = System.system_time(:second)
      
      all_entries = :ets.tab2list(@table_name)
      total_entries = length(all_entries)
      
      {active_entries, expired_entries} = 
        Enum.split_with(all_entries, fn {_key, _value, expire_at} ->
          expire_at > current_time
        end)
      
      memory_usage = :ets.info(@table_name, :memory) || 0
      
      %{
        total_entries: total_entries,
        active_entries: length(active_entries),
        expired_entries: length(expired_entries),
        memory_usage_words: memory_usage,
        table_size: :ets.info(@table_name, :size) || 0
      }
    rescue
      ArgumentError -> %{error: "Cache table not found"}
      error -> %{error: inspect(error)}
    end
  end
  
  # GenServer callbacks
  
  @impl true
  def init(_opts) do
    # Create ETS table
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    # Schedule cleanup
    schedule_cleanup()
    
    Logger.info("Started ETS cache with table: #{@table_name}")
    
    {:ok, %{}}
  end
  
  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_entries()
    schedule_cleanup()
    {:noreply, state}
  end
  
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  # Private functions
  
  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
  
  defp cleanup_expired_entries do
    current_time = System.system_time(:second)
    
    try do
      expired_keys = 
        :ets.tab2list(@table_name)
        |> Enum.filter(fn {_key, _value, expire_at} -> expire_at <= current_time end)
        |> Enum.map(fn {key, _value, _expire_at} -> key end)
      
      Enum.each(expired_keys, fn key ->
        :ets.delete(@table_name, key)
      end)
      
      if length(expired_keys) > 0 do
        Logger.debug("Cleaned up #{length(expired_keys)} expired cache entries")
      end
    rescue
      ArgumentError -> 
        Logger.warning("Cache table not found during cleanup")
      error -> 
        Logger.error("Error during cache cleanup: #{inspect(error)}")
    end
  end
end