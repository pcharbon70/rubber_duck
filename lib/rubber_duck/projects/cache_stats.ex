defmodule RubberDuck.Projects.CacheStats do
  @moduledoc """
  Real-time cache statistics tracking and analysis.
  
  Provides detailed metrics on cache performance including:
  - Hit/miss ratios
  - Memory usage
  - Access frequency
  - Hot key detection
  - Performance trends
  """
  
  use GenServer
  require Logger
  
  @stats_table :rubber_duck_cache_stats
  @hot_keys_table :rubber_duck_cache_hot_keys
  @window_size :timer.minutes(5)
  @cleanup_interval :timer.minutes(1)
  
  defstruct [
    :total_hits,
    :total_misses,
    :total_puts,
    :total_deletes,
    :total_memory_bytes,
    :start_time,
    :last_reset
  ]
  
  # Client API
  
  @doc """
  Starts the CacheStats GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Records a cache hit.
  """
  def record_hit(project_id, key, size_bytes \\ 0) do
    GenServer.cast(__MODULE__, {:record_hit, project_id, key, size_bytes})
  end
  
  @doc """
  Records a cache miss.
  """
  def record_miss(project_id, key) do
    GenServer.cast(__MODULE__, {:record_miss, project_id, key})
  end
  
  @doc """
  Records a cache put operation.
  """
  def record_put(project_id, key, size_bytes) do
    GenServer.cast(__MODULE__, {:record_put, project_id, key, size_bytes})
  end
  
  @doc """
  Records a cache delete operation.
  """
  def record_delete(project_id, key, size_bytes \\ 0) do
    GenServer.cast(__MODULE__, {:record_delete, project_id, key, size_bytes})
  end
  
  @doc """
  Gets current statistics for a project or all projects.
  """
  def get_stats(project_id \\ :all) do
    GenServer.call(__MODULE__, {:get_stats, project_id})
  end
  
  @doc """
  Gets hot keys for a project.
  """
  def get_hot_keys(project_id, limit \\ 10) do
    GenServer.call(__MODULE__, {:get_hot_keys, project_id, limit})
  end
  
  @doc """
  Gets cache performance metrics.
  """
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end
  
  @doc """
  Resets statistics for a project or all projects.
  """
  def reset_stats(project_id \\ :all) do
    GenServer.call(__MODULE__, {:reset_stats, project_id})
  end
  
  # Server Callbacks
  
  @impl true
  def init(_opts) do
    # Create ETS tables for statistics
    :ets.new(@stats_table, [:named_table, :public, :set, {:write_concurrency, true}])
    :ets.new(@hot_keys_table, [:named_table, :public, :set, {:write_concurrency, true}])
    
    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_old_entries, @cleanup_interval)
    
    # Initialize telemetry metrics
    init_telemetry()
    
    state = %__MODULE__{
      total_hits: 0,
      total_misses: 0,
      total_puts: 0,
      total_deletes: 0,
      total_memory_bytes: 0,
      start_time: DateTime.utc_now(),
      last_reset: DateTime.utc_now()
    }
    
    {:ok, state}
  end
  
  @impl true
  def handle_cast({:record_hit, project_id, key, size_bytes}, state) do
    # Update global stats
    state = %{state | 
      total_hits: state.total_hits + 1,
      total_memory_bytes: state.total_memory_bytes + size_bytes
    }
    
    # Update project stats
    update_project_stats(project_id, :hits, 1)
    update_project_stats(project_id, :memory_bytes, size_bytes)
    
    # Update hot key tracking
    update_hot_key(project_id, key, :hit)
    
    # Emit telemetry
    :telemetry.execute(
      [:rubber_duck, :cache, :hit],
      %{count: 1, size: size_bytes},
      %{project_id: project_id}
    )
    
    {:noreply, state}
  end
  
  @impl true
  def handle_cast({:record_miss, project_id, key}, state) do
    # Update global stats
    state = %{state | total_misses: state.total_misses + 1}
    
    # Update project stats
    update_project_stats(project_id, :misses, 1)
    
    # Update hot key tracking (misses can indicate needed keys)
    update_hot_key(project_id, key, :miss)
    
    # Emit telemetry
    :telemetry.execute(
      [:rubber_duck, :cache, :miss],
      %{count: 1},
      %{project_id: project_id}
    )
    
    {:noreply, state}
  end
  
  @impl true
  def handle_cast({:record_put, project_id, key, size_bytes}, state) do
    # Update global stats
    state = %{state | 
      total_puts: state.total_puts + 1,
      total_memory_bytes: state.total_memory_bytes + size_bytes
    }
    
    # Update project stats
    update_project_stats(project_id, :puts, 1)
    update_project_stats(project_id, :memory_bytes, size_bytes)
    
    # Update hot key tracking
    update_hot_key(project_id, key, :put)
    
    # Emit telemetry
    :telemetry.execute(
      [:rubber_duck, :cache, :put],
      %{count: 1, size: size_bytes},
      %{project_id: project_id}
    )
    
    {:noreply, state}
  end
  
  @impl true
  def handle_cast({:record_delete, project_id, key, size_bytes}, state) do
    # Update global stats
    state = %{state | 
      total_deletes: state.total_deletes + 1,
      total_memory_bytes: max(0, state.total_memory_bytes - size_bytes)
    }
    
    # Update project stats - ensure we don't go negative
    current_project_memory = get_counter_value({project_id, :memory_bytes})
    new_memory = max(0, current_project_memory - size_bytes)
    memory_delta = new_memory - current_project_memory
    
    update_project_stats(project_id, :deletes, 1)
    if memory_delta != 0 do
      update_project_stats(project_id, :memory_bytes, memory_delta)
    end
    
    # Remove from hot keys
    remove_hot_key(project_id, key)
    
    # Emit telemetry
    :telemetry.execute(
      [:rubber_duck, :cache, :delete],
      %{count: 1, size: size_bytes},
      %{project_id: project_id}
    )
    
    {:noreply, state}
  end
  
  @impl true
  def handle_call({:get_stats, :all}, _from, state) do
    # Get global stats
    stats = %{
      hit_rate: calculate_hit_rate(state.total_hits, state.total_misses),
      total_hits: state.total_hits,
      total_misses: state.total_misses,
      total_puts: state.total_puts,
      total_deletes: state.total_deletes,
      total_memory_bytes: state.total_memory_bytes,
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.start_time),
      last_reset: state.last_reset
    }
    
    # Add per-project stats
    project_stats = get_all_project_stats()
    
    {:reply, {:ok, Map.put(stats, :projects, project_stats)}, state}
  end
  
  @impl true
  def handle_call({:get_stats, project_id}, _from, state) do
    stats = get_project_stats(project_id)
    {:reply, {:ok, stats}, state}
  end
  
  @impl true
  def handle_call({:get_hot_keys, project_id, limit}, _from, state) do
    hot_keys = get_project_hot_keys(project_id, limit)
    {:reply, {:ok, hot_keys}, state}
  end
  
  @impl true
  def handle_call(:get_metrics, _from, state) do
    metrics = %{
      hit_rate: calculate_hit_rate(state.total_hits, state.total_misses),
      operations_per_second: calculate_ops_per_second(state),
      average_memory_per_entry: calculate_avg_memory(state),
      cache_efficiency_score: calculate_efficiency_score(state)
    }
    
    {:reply, {:ok, metrics}, state}
  end
  
  @impl true
  def handle_call({:reset_stats, :all}, _from, state) do
    # Clear all ETS entries
    :ets.delete_all_objects(@stats_table)
    :ets.delete_all_objects(@hot_keys_table)
    
    # Reset state
    new_state = %{state | 
      total_hits: 0,
      total_misses: 0,
      total_puts: 0,
      total_deletes: 0,
      total_memory_bytes: 0,
      last_reset: DateTime.utc_now()
    }
    
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call({:reset_stats, project_id}, _from, state) do
    # Clear project-specific entries
    :ets.match_delete(@stats_table, {{project_id, :_}, :_})
    :ets.match_delete(@hot_keys_table, {{project_id, :_}, :_})
    
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_info(:cleanup_old_entries, state) do
    # Clean up old hot key entries
    cutoff_time = System.monotonic_time(:millisecond) - @window_size
    
    :ets.select_delete(@hot_keys_table, [
      {
        {:_, %{last_access: :"$1", access_count: :"$2"}},
        [{:<, :"$1", cutoff_time}, {:<, :"$2", 5}],
        [true]
      }
    ])
    
    # Schedule next cleanup
    Process.send_after(self(), :cleanup_old_entries, @cleanup_interval)
    
    {:noreply, state}
  end
  
  @impl true
  def handle_info(_msg, state) do
    # Ignore any other messages (like telemetry events)
    {:noreply, state}
  end
  
  # Private Functions
  
  defp init_telemetry do
    # Define telemetry events
    events = [
      [:rubber_duck, :cache, :hit],
      [:rubber_duck, :cache, :miss],
      [:rubber_duck, :cache, :put],
      [:rubber_duck, :cache, :delete]
    ]
    
    # Attach default handlers if needed
    Enum.each(events, fn event ->
      :telemetry.attach(
        "#{inspect(event)}-logger",
        event,
        &handle_telemetry_event/4,
        nil
      )
    end)
  end
  
  defp handle_telemetry_event(_event, _measurements, _metadata, _config) do
    # Default telemetry handler - do nothing for now
    # We can add logging here if needed, but it should not send messages to self
    :ok
  end
  
  defp update_project_stats(project_id, metric, delta) do
    key = {project_id, metric}
    try do
      :ets.update_counter(@stats_table, key, delta)
    rescue
      ArgumentError ->
        # Entry doesn't exist, insert it with the delta value
        :ets.insert(@stats_table, {key, delta})
        delta
    end
  end
  
  defp update_hot_key(project_id, key, operation) do
    hot_key = {project_id, key}
    now = System.monotonic_time(:millisecond)
    
    case :ets.lookup(@hot_keys_table, hot_key) do
      [{^hot_key, data}] ->
        # Update existing entry
        updated = Map.update(data, :access_count, 1, &(&1 + 1))
        |> Map.put(:last_access, now)
        |> Map.update(operation, 1, &(&1 + 1))
        
        :ets.insert(@hot_keys_table, {hot_key, updated})
        
      [] ->
        # Create new entry
        data = %{
          access_count: 1,
          last_access: now,
          hit: if(operation == :hit, do: 1, else: 0),
          miss: if(operation == :miss, do: 1, else: 0),
          put: if(operation == :put, do: 1, else: 0)
        }
        
        :ets.insert(@hot_keys_table, {hot_key, data})
    end
  end
  
  defp remove_hot_key(project_id, key) do
    :ets.delete(@hot_keys_table, {project_id, key})
  end
  
  defp get_project_stats(project_id) do
    hits = get_counter_value({project_id, :hits})
    misses = get_counter_value({project_id, :misses})
    
    %{
      project_id: project_id,
      hit_rate: calculate_hit_rate(hits, misses),
      total_hits: hits,
      total_misses: misses,
      total_puts: get_counter_value({project_id, :puts}),
      total_deletes: get_counter_value({project_id, :deletes}),
      memory_bytes: get_counter_value({project_id, :memory_bytes})
    }
  end
  
  defp get_all_project_stats do
    # Get unique project IDs
    project_ids = :ets.select(@stats_table, [
      {
        {{:"$1", :_}, :_},
        [],
        [:"$1"]
      }
    ])
    |> Enum.uniq()
    
    # Get stats for each project
    Enum.map(project_ids, &get_project_stats/1)
  end
  
  defp get_project_hot_keys(project_id, limit) do
    # Get all entries for the project
    all_entries = :ets.tab2list(@hot_keys_table)
    
    # Filter by project_id and extract key + data
    project_entries = all_entries
    |> Enum.filter(fn {{pid, _key}, _data} -> pid == project_id end)
    |> Enum.map(fn {{_pid, key}, data} -> {key, data} end)
    
    # Sort by access count and take top N
    project_entries
    |> Enum.sort_by(fn {_key, data} -> -data.access_count end)
    |> Enum.take(limit)
    |> Enum.map(fn {key, data} ->
      %{
        key: key,
        access_count: data.access_count,
        hit_rate: calculate_hit_rate(data[:hit] || 0, data[:miss] || 0),
        last_access: data.last_access
      }
    end)
  end
  
  defp get_counter_value(key) do
    case :ets.lookup(@stats_table, key) do
      [{^key, value}] -> value
      [] -> 0
    end
  end
  
  defp calculate_hit_rate(hits, misses) when hits + misses > 0 do
    Float.round(hits / (hits + misses) * 100, 2)
  end
  defp calculate_hit_rate(_, _), do: 0.0
  
  defp calculate_ops_per_second(state) do
    uptime = DateTime.diff(DateTime.utc_now(), state.start_time)
    total_ops = state.total_hits + state.total_misses + state.total_puts + state.total_deletes
    
    if uptime > 0 do
      Float.round(total_ops / uptime, 2)
    else
      0.0
    end
  end
  
  defp calculate_avg_memory(state) do
    total_entries = state.total_puts - state.total_deletes
    
    if total_entries > 0 do
      round(state.total_memory_bytes / total_entries)
    else
      0
    end
  end
  
  defp calculate_efficiency_score(state) do
    # Simple efficiency score based on hit rate and memory usage
    hit_rate = calculate_hit_rate(state.total_hits, state.total_misses)
    memory_efficiency = if state.total_memory_bytes > 0 do
      min(100, state.total_hits / (state.total_memory_bytes / 1024) * 100)
    else
      0
    end
    
    Float.round((hit_rate + memory_efficiency) / 2, 2)
  end
end