defmodule RubberDuck.CodingAssistant.Engines.ExplanationCache do
  @moduledoc """
  Advanced caching system for ExplanationEngine with TTL, LRU eviction, and content-aware strategies.
  
  This module provides sophisticated caching capabilities specifically optimized for code explanations,
  including content-based hashing, quality validation, and intelligent eviction policies.
  """
  
  use GenServer
  
  require Logger
  
  @default_max_size 10_000
  @default_ttl :timer.hours(24)
  @default_cleanup_interval :timer.hours(1)
  @content_hash_algorithm :sha256
  
  defstruct [
    :table,
    :access_table,
    :config,
    max_size: @default_max_size,
    current_size: 0,
    hit_count: 0,
    miss_count: 0,
    eviction_count: 0,
    last_cleanup: nil
  ]
  
  @type cache_key :: String.t()
  @type cache_entry :: %{
    content: String.t(),
    metadata: map(),
    confidence: float(),
    timestamp: non_neg_integer(),
    access_count: non_neg_integer(),
    last_accessed: non_neg_integer()
  }
  
  @type cache_stats :: %{
    size: non_neg_integer(),
    max_size: non_neg_integer(),
    hit_rate: float(),
    eviction_count: non_neg_integer()
  }
  
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
  
  @doc """
  Get a cached explanation result.
  """
  def get(cache_pid \\ __MODULE__, request) do
    GenServer.call(cache_pid, {:get, request})
  end
  
  @doc """
  Store an explanation result in the cache.
  """
  def put(cache_pid \\ __MODULE__, request, result) do
    GenServer.call(cache_pid, {:put, request, result})
  end
  
  @doc """
  Clear cache entries matching specific patterns.
  """
  def clear_patterns(cache_pid \\ __MODULE__, patterns) do
    GenServer.call(cache_pid, {:clear_patterns, patterns})
  end
  
  @doc """
  Get cache statistics.
  """
  def stats(cache_pid \\ __MODULE__) do
    GenServer.call(cache_pid, :stats)
  end
  
  @doc """
  Manually trigger cache cleanup.
  """
  def cleanup(cache_pid \\ __MODULE__) do
    GenServer.call(cache_pid, :cleanup)
  end
  
  @doc """
  Generate a content-based cache key for an explanation request.
  """
  def generate_cache_key(request) do
    content_hash = hash_content(request.content)
    context_hash = hash_context(request.context)
    
    "#{request.type}:#{request.language}:#{content_hash}:#{context_hash}"
  end
  
  @doc """
  Validate if a cached result is still valid and high quality.
  """
  def validate_cache_entry(entry, min_confidence \\ 0.7) do
    now = System.system_time(:millisecond)
    ttl = @default_ttl
    
    cond do
      entry.timestamp + ttl < now ->
        {:invalid, :expired}
      
      entry.confidence < min_confidence ->
        {:invalid, :low_confidence}
      
      true ->
        {:valid, entry}
    end
  end
  
  # GenServer Callbacks
  
  @impl true
  def init(opts) do
    config = validate_config(opts)
    
    state = %__MODULE__{
      table: :ets.new(:explanation_cache, [:set, :private]),
      access_table: :ets.new(:explanation_access, [:ordered_set, :private]),
      config: config,
      max_size: Keyword.get(opts, :max_size, @default_max_size),
      last_cleanup: System.system_time(:millisecond)
    }
    
    schedule_cleanup(config.cleanup_interval)
    
    Logger.info("ExplanationCache initialized with max_size: #{state.max_size}")
    {:ok, state}
  end
  
  @impl true
  def handle_call({:get, request}, _from, state) do
    cache_key = generate_cache_key(request)
    
    case :ets.lookup(state.table, cache_key) do
      [{^cache_key, entry}] ->
        case validate_cache_entry(entry) do
          {:valid, valid_entry} ->
            updated_entry = update_access_info(valid_entry)
            :ets.insert(state.table, {cache_key, updated_entry})
            update_access_tracking(state.access_table, cache_key)
            
            new_state = %{state | hit_count: state.hit_count + 1}
            {:reply, {:hit, updated_entry}, new_state}
          
          {:invalid, reason} ->
            :ets.delete(state.table, cache_key)
            new_state = %{state | 
              miss_count: state.miss_count + 1,
              current_size: max(0, state.current_size - 1)
            }
            {:reply, {:miss, reason}, new_state}
        end
      
      [] ->
        new_state = %{state | miss_count: state.miss_count + 1}
        {:reply, {:miss, :not_found}, new_state}
    end
  end
  
  @impl true
  def handle_call({:put, request, result}, _from, state) do
    cache_key = generate_cache_key(request)
    
    entry = %{
      content: result.explanation,
      metadata: result.metadata,
      confidence: result.confidence,
      timestamp: System.system_time(:millisecond),
      access_count: 1,
      last_accessed: System.system_time(:millisecond)
    }
    
    new_state = if state.current_size >= state.max_size do
      evicted_state = evict_lru_entries(state, 1)
      %{evicted_state | eviction_count: evicted_state.eviction_count + 1}
    else
      state
    end
    
    :ets.insert(new_state.table, {cache_key, entry})
    update_access_tracking(new_state.access_table, cache_key)
    
    final_state = %{new_state | current_size: new_state.current_size + 1}
    
    {:reply, :ok, final_state}
  end
  
  @impl true
  def handle_call({:clear_patterns, patterns}, _from, state) do
    cleared_count = clear_matching_patterns(state.table, patterns)
    
    new_state = %{state | current_size: max(0, state.current_size - cleared_count)}
    
    {:reply, cleared_count, new_state}
  end
  
  @impl true
  def handle_call(:stats, _from, state) do
    total_requests = state.hit_count + state.miss_count
    hit_rate = if total_requests > 0, do: state.hit_count / total_requests, else: 0.0
    
    stats = %{
      size: state.current_size,
      max_size: state.max_size,
      hit_count: state.hit_count,
      miss_count: state.miss_count,
      hit_rate: hit_rate,
      eviction_count: state.eviction_count
    }
    
    {:reply, stats, state}
  end
  
  @impl true
  def handle_call(:cleanup, _from, state) do
    cleaned_state = perform_cleanup(state)
    {:reply, :ok, cleaned_state}
  end
  
  @impl true
  def handle_info(:scheduled_cleanup, state) do
    cleaned_state = perform_cleanup(state)
    schedule_cleanup(cleaned_state.config.cleanup_interval)
    {:noreply, cleaned_state}
  end
  
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  @impl true
  def terminate(_reason, state) do
    :ets.delete(state.table)
    :ets.delete(state.access_table)
    :ok
  end
  
  # Private Functions
  
  defp validate_config(opts) do
    %{
      ttl: Keyword.get(opts, :ttl, @default_ttl),
      cleanup_interval: Keyword.get(opts, :cleanup_interval, @default_cleanup_interval),
      min_confidence: Keyword.get(opts, :min_confidence, 0.7)
    }
  end
  
  defp hash_content(content) do
    :crypto.hash(@content_hash_algorithm, content)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)  # Use first 16 chars for reasonable key length
  end
  
  defp hash_context(context) when is_map(context) do
    context
    |> Enum.sort()
    |> :erlang.term_to_binary()
    |> (&:crypto.hash(@content_hash_algorithm, &1)).()
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)  # Shorter hash for context
  end
  
  defp hash_context(_), do: "default"
  
  defp update_access_info(entry) do
    %{entry |
      access_count: entry.access_count + 1,
      last_accessed: System.system_time(:millisecond)
    }
  end
  
  defp update_access_tracking(access_table, cache_key) do
    timestamp = System.system_time(:millisecond)
    :ets.insert(access_table, {timestamp, cache_key})
  end
  
  defp evict_lru_entries(state, count) do
    # Get oldest entries from access table
    oldest_entries = :ets.tab2list(state.access_table)
    |> Enum.sort_by(fn {timestamp, _key} -> timestamp end)
    |> Enum.take(count)
    
    # Remove from both tables
    Enum.each(oldest_entries, fn {timestamp, cache_key} ->
      :ets.delete(state.table, cache_key)
      :ets.delete(state.access_table, timestamp)
    end)
    
    %{state | current_size: max(0, state.current_size - length(oldest_entries))}
  end
  
  defp clear_matching_patterns(table, patterns) do
    all_keys = :ets.tab2list(table) |> Enum.map(fn {key, _} -> key end)
    
    matching_keys = Enum.filter(all_keys, fn key ->
      Enum.any?(patterns, fn pattern ->
        String.contains?(key, pattern) or match_pattern?(key, pattern)
      end)
    end)
    
    Enum.each(matching_keys, &:ets.delete(table, &1))
    
    length(matching_keys)
  end
  
  defp match_pattern?(key, pattern) do
    case Regex.compile(pattern) do
      {:ok, regex} -> Regex.match?(regex, key)
      {:error, _} -> false
    end
  end
  
  defp perform_cleanup(state) do
    now = System.system_time(:millisecond)
    ttl = state.config.ttl
    
    # Find expired entries
    expired_keys = :ets.tab2list(state.table)
    |> Enum.filter(fn {_key, entry} -> entry.timestamp + ttl < now end)
    |> Enum.map(fn {key, _entry} -> key end)
    
    # Remove expired entries
    Enum.each(expired_keys, fn key ->
      :ets.delete(state.table, key)
      # Clean up access tracking for this key
      cleanup_access_tracking(state.access_table, key)
    end)
    
    expired_count = length(expired_keys)
    
    if expired_count > 0 do
      Logger.debug("Cleaned up #{expired_count} expired cache entries")
    end
    
    %{state |
      current_size: max(0, state.current_size - expired_count),
      last_cleanup: now
    }
  end
  
  defp cleanup_access_tracking(access_table, cache_key) do
    # Find and remove access tracking entries for the given cache key
    matching_entries = :ets.tab2list(access_table)
    |> Enum.filter(fn {_timestamp, key} -> key == cache_key end)
    
    Enum.each(matching_entries, fn {timestamp, _key} ->
      :ets.delete(access_table, timestamp)
    end)
  end
  
  defp schedule_cleanup(interval) do
    Process.send_after(self(), :scheduled_cleanup, interval)
  end
end