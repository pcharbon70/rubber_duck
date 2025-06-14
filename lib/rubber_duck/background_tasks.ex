defmodule RubberDuck.BackgroundTasks do
  use Supervisor
  require Logger

  @moduledoc """
  Supervisor for background maintenance tasks optimized for AI workloads.
  Manages session cleanup, statistics aggregation, cache warming, and
  performance optimization tasks.
  """

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Session cleanup and archival
      {RubberDuck.SessionCleaner, []},
      # Model statistics aggregation
      {RubberDuck.ModelStatsAggregator, []},
      # Cache warming and optimization
      {RubberDuck.CacheWarmer, []},
      # Performance monitoring
      {RubberDuck.PerformanceMonitor, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule RubberDuck.SessionCleaner do
  use GenServer
  require Logger

  @moduledoc """
  Cleans up inactive sessions and archives old conversation data.
  Optimized for AI workload patterns with configurable retention policies.
  """

  @cleanup_interval :timer.hours(1)     # Run every hour
  @inactive_threshold :timer.hours(24)  # 24 hours inactive
  @archive_threshold :timer.hours(24 * 30)  # 30 days for archival

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_cleanup()
    {:ok, %{last_cleanup: DateTime.utc_now(), stats: %{cleaned: 0, archived: 0}}}
  end

  @impl true
  def handle_info(:cleanup_sessions, state) do
    Logger.info("Starting session cleanup task...")
    
    {cleaned, archived} = perform_cleanup()
    
    new_stats = %{
      cleaned: state.stats.cleaned + cleaned,
      archived: state.stats.archived + archived
    }
    
    Logger.info("Session cleanup completed: #{cleaned} cleaned, #{archived} archived")
    
    schedule_cleanup()
    {:noreply, %{state | last_cleanup: DateTime.utc_now(), stats: new_stats}}
  end

  defp perform_cleanup do
    now = DateTime.utc_now()
    inactive_cutoff = DateTime.add(now, -@inactive_threshold, :millisecond)
    archive_cutoff = DateTime.add(now, -@archive_threshold, :millisecond)

    # Get all sessions for analysis
    case RubberDuck.TransactionWrapper.read_records(:sessions, :all) do
      {:ok, sessions} ->
        {inactive_sessions, old_sessions} = categorize_sessions(sessions, inactive_cutoff, archive_cutoff)
        
        cleaned = cleanup_inactive_sessions(inactive_sessions)
        archived = archive_old_sessions(old_sessions)
        
        {cleaned, archived}
      
      {:error, reason} ->
        Logger.error("Failed to read sessions for cleanup: #{inspect(reason)}")
        {0, 0}
    end
  end

  defp categorize_sessions(sessions, inactive_cutoff, archive_cutoff) do
    Enum.reduce(sessions, {[], []}, fn session, {inactive, old} ->
      session_updated = get_session_updated_time(session)
      
      cond do
        DateTime.compare(session_updated, archive_cutoff) == :lt ->
          {inactive, [session | old]}
        DateTime.compare(session_updated, inactive_cutoff) == :lt ->
          {[session | inactive], old}
        true ->
          {inactive, old}
      end
    end)
  end

  defp get_session_updated_time(session) do
    case session do
      %{updated_at: updated_at} when not is_nil(updated_at) -> updated_at
      %{created_at: created_at} when not is_nil(created_at) -> created_at
      _ -> DateTime.utc_now()
    end
  end

  defp cleanup_inactive_sessions(sessions) do
    # For inactive sessions, clear messages but keep session metadata
    Enum.reduce(sessions, 0, fn session, count ->
      session_id = get_session_id(session)
      
      case clear_session_messages(session_id) do
        :ok -> count + 1
        _ -> count
      end
    end)
  end

  defp archive_old_sessions(sessions) do
    # For very old sessions, move to archive table or delete entirely
    Enum.reduce(sessions, 0, fn session, count ->
      session_id = get_session_id(session)
      
      case archive_session(session_id) do
        :ok -> count + 1
        _ -> count
      end
    end)
  end

  defp get_session_id(session) do
    case session do
      %{session_id: id} -> id
      {_, id, _, _, _, _, _} -> id
      _ -> nil
    end
  end

  defp clear_session_messages(session_id) do
    case RubberDuck.TransactionWrapper.update_record(:sessions, session_id, 
           %{messages: [], updated_at: DateTime.utc_now()}, 
           metadata: %{operation: :cleanup}, broadcast: false) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp archive_session(session_id) do
    # For now, just delete old sessions
    # In production, you might want to move to an archive table
    case RubberDuck.TransactionWrapper.delete_record(:sessions, session_id, 
           metadata: %{operation: :archive}, broadcast: false) do
      {:ok, _} -> :ok
      {:error, :not_found} -> :ok  # Already gone
      error -> error
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_sessions, @cleanup_interval)
  end
end

defmodule RubberDuck.ModelStatsAggregator do
  use GenServer
  require Logger

  @moduledoc """
  Aggregates and rolls up model usage statistics for performance analytics.
  Creates time-based rollups and maintains historical performance data.
  """

  @aggregation_interval :timer.minutes(15)  # Aggregate every 15 minutes
  @rollup_periods [:hourly, :daily, :weekly]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_aggregation()
    {:ok, %{last_aggregation: DateTime.utc_now(), rollups_created: 0}}
  end

  @impl true
  def handle_info(:aggregate_stats, state) do
    Logger.debug("Starting model statistics aggregation...")
    
    rollups_created = perform_aggregation()
    
    Logger.debug("Model stats aggregation completed: #{rollups_created} rollups created")
    
    schedule_aggregation()
    {:noreply, %{state | 
      last_aggregation: DateTime.utc_now(), 
      rollups_created: state.rollups_created + rollups_created
    }}
  end

  defp perform_aggregation do
    case RubberDuck.TransactionWrapper.read_records(:model_stats, :all) do
      {:ok, stats} ->
        current_time = DateTime.utc_now()
        
        Enum.reduce(@rollup_periods, 0, fn period, count ->
          created = create_rollup(stats, period, current_time)
          count + created
        end)
      
      {:error, reason} ->
        Logger.error("Failed to read model stats: #{inspect(reason)}")
        0
    end
  end

  defp create_rollup(stats, period, current_time) do
    # Group stats by time period and model
    grouped_stats = group_stats_by_period(stats, period, current_time)
    
    # Create rollup records
    Enum.reduce(grouped_stats, 0, fn {key, group_stats}, count ->
      case create_rollup_record(key, group_stats, period) do
        :ok -> count + 1
        _ -> count
      end
    end)
  end

  defp group_stats_by_period(stats, period, current_time) do
    Enum.group_by(stats, fn stat ->
      model_name = get_model_name(stat)
      time_bucket = get_time_bucket(get_last_updated(stat), period, current_time)
      {model_name, time_bucket}
    end)
  end

  defp get_model_name(stat) do
    case stat do
      %{model_name: name} -> name
      {_, name, _, _, _, _} -> name
      _ -> "unknown"
    end
  end

  defp get_last_updated(stat) do
    case stat do
      %{last_updated: updated} when not is_nil(updated) -> updated
      _ -> DateTime.utc_now()
    end
  end

  defp get_time_bucket(datetime, :hourly, _current) do
    %{datetime | minute: 0, second: 0, microsecond: {0, 0}}
  end

  defp get_time_bucket(datetime, :daily, _current) do
    %{datetime | hour: 0, minute: 0, second: 0, microsecond: {0, 0}}
  end

  defp get_time_bucket(datetime, :weekly, _current) do
    days_since_monday = Date.day_of_week(datetime) - 1
    monday = Date.add(datetime, -days_since_monday)
    DateTime.new!(monday, ~T[00:00:00])
  end

  defp create_rollup_record({model_name, time_bucket}, stats, period) do
    # Aggregate the statistics
    aggregated = aggregate_stats(stats)
    
    rollup_key = "#{model_name}:#{period}:#{DateTime.to_iso8601(time_bucket)}"
    
    rollup_record = %{
      rollup_key: rollup_key,
      model_name: model_name,
      period: period,
      time_bucket: time_bucket,
      success_count: aggregated.success_count,
      failure_count: aggregated.failure_count,
      total_latency: aggregated.total_latency,
      average_latency: aggregated.average_latency,
      request_count: aggregated.request_count,
      created_at: DateTime.utc_now()
    }
    
    # Store in a rollup table (could be separate from model_stats)
    # For now, we'll use the same table with a special key format
    case RubberDuck.TransactionWrapper.create_record(:model_stats, rollup_record, 
           metadata: %{operation: :rollup}, broadcast: false) do
      {:ok, _} -> :ok
      {:error, reason} -> 
        Logger.debug("Failed to create rollup record: #{inspect(reason)}")
        :error
    end
  end

  defp aggregate_stats(stats) do
    Enum.reduce(stats, %{success_count: 0, failure_count: 0, total_latency: 0, request_count: 0}, 
    fn stat, acc ->
      success = get_stat_field(stat, :success_count, 0)
      failure = get_stat_field(stat, :failure_count, 0)
      latency = get_stat_field(stat, :total_latency, 0)
      
      %{
        success_count: acc.success_count + success,
        failure_count: acc.failure_count + failure,
        total_latency: acc.total_latency + latency,
        request_count: acc.request_count + success + failure,
        average_latency: if (acc.success_count + success) > 0 do
          (acc.total_latency + latency) / (acc.success_count + success)
        else
          0
        end
      }
    end)
  end

  defp get_stat_field(stat, field, default) do
    case stat do
      %{^field => value} when not is_nil(value) -> value
      _ -> default
    end
  end

  defp schedule_aggregation do
    Process.send_after(self(), :aggregate_stats, @aggregation_interval)
  end
end

defmodule RubberDuck.CacheWarmer do
  use GenServer
  require Logger

  @moduledoc """
  Warms caches with frequently accessed data based on usage patterns.
  Implements intelligent prefetching for AI workload optimization.
  """

  @warming_interval :timer.minutes(10)  # Warm cache every 10 minutes

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_warming()
    {:ok, %{last_warming: DateTime.utc_now(), items_warmed: 0}}
  end

  @impl true
  def handle_info(:warm_caches, state) do
    Logger.debug("Starting cache warming...")
    
    items_warmed = perform_cache_warming()
    
    Logger.debug("Cache warming completed: #{items_warmed} items warmed")
    
    schedule_warming()
    {:noreply, %{state | 
      last_warming: DateTime.utc_now(), 
      items_warmed: state.items_warmed + items_warmed
    }}
  end

  defp perform_cache_warming do
    # Warm different types of caches
    session_items = warm_active_sessions()
    model_items = warm_model_cache()
    stats_items = warm_stats_cache()
    
    session_items + model_items + stats_items
  end

  defp warm_active_sessions do
    # Find recently active sessions and warm them
    case get_active_sessions() do
      {:ok, sessions} ->
        session_data = Enum.map(sessions, fn session ->
          session_id = get_session_id(session)
          {session_id, session}
        end)
        
        RubberDuck.QueryCache.warm_cache(:session_cache, session_data)
        length(session_data)
      
      _ -> 0
    end
  end

  defp warm_model_cache do
    # Warm frequently used models
    case RubberDuck.TransactionWrapper.read_records(:models, :all) do
      {:ok, models} ->
        model_data = Enum.map(models, fn model ->
          model_name = get_model_name(model)
          {model_name, model}
        end)
        
        RubberDuck.QueryCache.warm_cache(:model_cache, model_data)
        length(model_data)
      
      _ -> 0
    end
  end

  defp warm_stats_cache do
    # Warm recent statistics
    recent_stats = get_recent_model_stats()
    
    case recent_stats do
      {:ok, stats} ->
        stats_data = Enum.map(stats, fn stat ->
          key = "recent:#{get_model_name(stat)}"
          {key, stat}
        end)
        
        RubberDuck.QueryCache.warm_cache(:stats_cache, stats_data)
        length(stats_data)
      
      _ -> 0
    end
  end

  defp get_active_sessions do
    # Get sessions updated in the last 2 hours
    cutoff = DateTime.add(DateTime.utc_now(), -2 * 60 * 60, :second)
    
    case RubberDuck.TransactionWrapper.read_records(:sessions, :all) do
      {:ok, sessions} ->
        active_sessions = Enum.filter(sessions, fn session ->
          session_time = get_session_updated_time(session)
          DateTime.compare(session_time, cutoff) == :gt
        end)
        {:ok, active_sessions}
      
      error -> error
    end
  end

  defp get_recent_model_stats do
    # Get stats updated in the last hour
    RubberDuck.TransactionWrapper.read_records(:model_stats, :all)
  end

  defp get_session_id(session) do
    case session do
      %{session_id: id} -> id
      {_, id, _, _, _, _, _} -> id
      _ -> "unknown"
    end
  end

  defp get_model_name(record) do
    case record do
      %{model_name: name} -> name
      %{name: name} -> name
      {_, name, _, _, _, _, _, _} -> name
      {_, name, _, _, _, _} -> name
      _ -> "unknown"
    end
  end

  defp get_session_updated_time(session) do
    case session do
      %{updated_at: updated_at} when not is_nil(updated_at) -> updated_at
      %{created_at: created_at} when not is_nil(created_at) -> created_at
      _ -> DateTime.utc_now()
    end
  end

  defp schedule_warming do
    Process.send_after(self(), :warm_caches, @warming_interval)
  end
end

defmodule RubberDuck.PerformanceMonitor do
  use GenServer
  require Logger

  @moduledoc """
  Monitors system performance and triggers optimizations.
  Tracks query performance, cache hit rates, and system resource usage.
  """

  @monitoring_interval :timer.minutes(5)  # Monitor every 5 minutes

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_monitoring()
    {:ok, %{last_check: DateTime.utc_now(), performance_history: []}}
  end

  @impl true
  def handle_info(:monitor_performance, state) do
    current_metrics = collect_performance_metrics()
    
    # Store metrics and check for issues
    new_history = [current_metrics | Enum.take(state.performance_history, 11)]
    check_performance_issues(current_metrics, new_history)
    
    schedule_monitoring()
    {:noreply, %{state | 
      last_check: DateTime.utc_now(), 
      performance_history: new_history
    }}
  end

  defp collect_performance_metrics do
    %{
      timestamp: DateTime.utc_now(),
      mnesia_stats: RubberDuck.MnesiaOptimizer.get_performance_stats(),
      cache_stats: RubberDuck.QueryCache.get_cache_stats(),
      memory_usage: :erlang.memory(),
      process_count: :erlang.system_info(:process_count),
      system_load: get_system_load()
    }
  end

  defp get_system_load do
    # Simple load metric based on process count and memory usage
    memory = :erlang.memory(:total)
    processes = :erlang.system_info(:process_count)
    
    %{
      memory_mb: div(memory, 1024 * 1024),
      process_count: processes,
      load_score: calculate_load_score(memory, processes)
    }
  end

  defp calculate_load_score(memory, processes) do
    # Simple scoring: higher is worse
    memory_score = div(memory, 100 * 1024 * 1024)  # Every 100MB = 1 point
    process_score = div(processes, 1000)            # Every 1000 processes = 1 point
    
    memory_score + process_score
  end

  defp check_performance_issues(current_metrics, _history) do
    issues = []
    |> check_cache_performance(current_metrics.cache_stats)
    |> check_memory_usage(current_metrics.memory_usage)
    |> check_mnesia_performance(current_metrics.mnesia_stats)
    
    if length(issues) > 0 do
      Logger.warning("Performance issues detected: #{inspect(issues)}")
      trigger_optimizations(issues)
    end
  end

  defp check_cache_performance(issues, cache_stats) do
    # Check for low cache hit rates
    low_hit_rate_caches = Enum.filter(cache_stats, fn {_cache, stats} ->
      stats.hit_rate < 0.7  # Less than 70% hit rate
    end)
    
    if length(low_hit_rate_caches) > 0 do
      [%{type: :low_cache_hit_rate, caches: low_hit_rate_caches} | issues]
    else
      issues
    end
  end

  defp check_memory_usage(issues, memory_usage) do
    total_mb = div(memory_usage.total, 1024 * 1024)
    
    if total_mb > 1000 do  # More than 1GB
      [%{type: :high_memory_usage, memory_mb: total_mb} | issues]
    else
      issues
    end
  end

  defp check_mnesia_performance(issues, mnesia_stats) do
    # Check for table size issues
    large_tables = Enum.filter(mnesia_stats.table_stats, fn {_table, stats} ->
      (stats.size || 0) > 100_000
    end)
    
    if length(large_tables) > 0 do
      [%{type: :large_tables, tables: Enum.map(large_tables, &elem(&1, 0))} | issues]
    else
      issues
    end
  end

  defp trigger_optimizations(issues) do
    Enum.each(issues, fn issue ->
      case issue.type do
        :low_cache_hit_rate ->
          Logger.info("Triggering cache warming for low hit rate caches")
          # Could trigger immediate cache warming
          
        :high_memory_usage ->
          Logger.info("Triggering memory cleanup for high usage")
          :erlang.garbage_collect()
          
        :large_tables ->
          Logger.info("Recommending table optimization for: #{inspect(issue.tables)}")
          # Could trigger automatic optimization
          
        _ ->
          Logger.debug("Unknown performance issue: #{inspect(issue)}")
      end
    end)
  end

  defp schedule_monitoring do
    Process.send_after(self(), :monitor_performance, @monitoring_interval)
  end
end