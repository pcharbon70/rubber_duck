defmodule RubberDuck.PerformanceOptimizer do
  @moduledoc """
  Optimizes Mnesia configuration and performance for AI workloads.
  
  This module handles:
  - Mnesia parameter tuning for AI data patterns
  - Table fragmentation strategies
  - Query optimization
  - Background maintenance tasks
  """
  
  use GenServer
  require Logger
  
  
  @optimization_interval :timer.minutes(30)
  @table_size_threshold 1_000_000
  @fragment_size 100_000
  
  # AI workload specific settings
  @ai_workload_config %{
    # Increase dump log threshold for batch writes
    dump_log_write_threshold: 50_000,
    dump_log_time_threshold: :timer.minutes(5),
    
    # Optimize for read-heavy workloads
    dc_dump_limit: 40,
    
    # Increase transaction retry limits
    max_wait_for_decision: :timer.seconds(60),
    
    # Memory management
    no_table_loaders: 4,
    send_compressed: 1,
    
    # Checkpoint settings for large context data  
    # Note: checkpoint_interval is not a valid Mnesia parameter
    # checkpoint_interval: :timer.minutes(10),
    # checkpoint_max_size: 100_000
  }
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Apply initial optimizations
    apply_mnesia_optimizations()
    
    # Schedule periodic optimization tasks
    schedule_optimization()
    
    state = %{
      last_optimization: DateTime.utc_now(),
      table_stats: %{},
      fragmentation_status: %{}
    }
    
    {:ok, state}
  end
  
  @doc """
  Applies Mnesia configuration optimizations for AI workloads
  """
  def apply_mnesia_optimizations do
    Logger.info("Applying Mnesia optimizations for AI workloads")
    
    Enum.each(@ai_workload_config, fn {param, value} ->
      case apply_mnesia_param(param, value) do
        :ok ->
          Logger.debug("Applied Mnesia parameter #{param} = #{inspect(value)}")
        {:error, reason} ->
          Logger.warning("Failed to apply Mnesia parameter #{param}: #{inspect(reason)}")
      end
    end)
  end
  
  @doc """
  Configures table fragmentation for large datasets
  """
  def configure_fragmentation(table, opts \\ []) do
    GenServer.call(__MODULE__, {:configure_fragmentation, table, opts})
  end
  
  @doc """
  Analyzes query patterns and suggests optimizations
  """
  def analyze_query_patterns(table) do
    GenServer.call(__MODULE__, {:analyze_patterns, table})
  end
  
  @doc """
  Returns current performance metrics
  """
  def get_performance_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end
  
  # Callbacks
  
  def handle_call({:configure_fragmentation, table, opts}, _from, state) do
    n_fragments = Keyword.get(opts, :n_fragments, calculate_optimal_fragments(table))
    node_pool = Keyword.get(opts, :node_pool, [node() | Node.list()])
    
    frag_props = [
      n_fragments: n_fragments,
      node_pool: node_pool,
      n_disc_copies: length(node_pool)
    ]
    
    result = case :mnesia.change_table_frag(table, {:activate, frag_props}) do
      {:atomic, :ok} ->
        Logger.info("Activated fragmentation for table #{table} with #{n_fragments} fragments")
        {:ok, n_fragments}
      {:aborted, reason} ->
        Logger.error("Failed to activate fragmentation for #{table}: #{inspect(reason)}")
        {:error, reason}
    end
    
    new_state = put_in(state.fragmentation_status[table], %{
      fragments: n_fragments,
      activated_at: DateTime.utc_now()
    })
    
    {:reply, result, new_state}
  end
  
  def handle_call({:analyze_patterns, table}, _from, state) do
    analysis = perform_query_analysis(table)
    {:reply, analysis, state}
  end
  
  def handle_call(:get_metrics, _from, state) do
    metrics = collect_performance_metrics(state)
    {:reply, metrics, state}
  end
  
  def handle_info(:optimize, state) do
    Logger.debug("Running periodic optimization tasks")
    
    # Update table statistics
    table_stats = collect_table_stats()
    
    # Check for tables needing fragmentation
    check_fragmentation_needs(table_stats)
    
    # Run maintenance tasks
    run_maintenance_tasks()
    
    # Schedule next optimization
    schedule_optimization()
    
    new_state = %{state | 
      last_optimization: DateTime.utc_now(),
      table_stats: table_stats
    }
    
    {:noreply, new_state}
  end
  
  # Private functions
  
  defp apply_mnesia_param(param, value) do
    try do
      :mnesia.system_info(param)
      :application.set_env(:mnesia, param, value)
      :ok
    rescue
      _ -> {:error, :invalid_parameter}
    end
  end
  
  defp calculate_optimal_fragments(table) do
    case :mnesia.table_info(table, :size) do
      size when size > @table_size_threshold ->
        max(2, div(size, @fragment_size))
      _ ->
        1
    end
  rescue
    _ -> 1
  end
  
  defp perform_query_analysis(table) do
    # Analyze index usage
    indexes = :mnesia.table_info(table, :index)
    
    # Get table access patterns
    wild_pattern = :mnesia.table_info(table, :wild_pattern)
    
    # Estimate read/write ratio
    stats = collect_access_stats(table)
    
    %{
      table: table,
      indexes: indexes,
      access_pattern: wild_pattern,
      read_write_ratio: calculate_ratio(stats),
      recommendations: generate_recommendations(table, indexes, stats)
    }
  rescue
    error ->
      Logger.error("Failed to analyze table #{table}: #{inspect(error)}")
      %{error: error}
  end
  
  defp collect_access_stats(_table) do
    # This would integrate with telemetry in a real implementation
    %{
      reads: :rand.uniform(1000),
      writes: :rand.uniform(100),
      index_reads: :rand.uniform(500)
    }
  end
  
  defp calculate_ratio(%{reads: reads, writes: writes}) when writes > 0 do
    Float.round(reads / writes, 2)
  end
  defp calculate_ratio(_), do: :infinity
  
  defp generate_recommendations(table, indexes, stats) do
    recommendations = []
    
    # Check if table needs more indexes
    recommendations = if stats.reads > stats.writes * 10 and length(indexes) < 2 do
      ["Consider adding indexes for frequently queried fields" | recommendations]
    else
      recommendations
    end
    
    # Check if table is too large
    size = :mnesia.table_info(table, :size)
    recommendations = if size > @table_size_threshold do
      ["Table size exceeds threshold, consider fragmentation" | recommendations]
    else
      recommendations
    end
    
    recommendations
  rescue
    _ -> []
  end
  
  defp collect_table_stats do
    tables = :mnesia.system_info(:tables) -- [:schema]
    
    Enum.reduce(tables, %{}, fn table, acc ->
      stats = %{
        size: safe_table_info(table, :size),
        memory: safe_table_info(table, :memory),
        type: safe_table_info(table, :type)
      }
      Map.put(acc, table, stats)
    end)
  end
  
  defp safe_table_info(table, key) do
    :mnesia.table_info(table, key)
  rescue
    _ -> nil
  end
  
  defp check_fragmentation_needs(table_stats) do
    Enum.each(table_stats, fn {table, stats} ->
      if stats.size > @table_size_threshold and not fragmented?(table) do
        Logger.info("Table #{table} exceeds size threshold, recommending fragmentation")
        # In production, this would trigger an alert or automatic fragmentation
      end
    end)
  end
  
  defp fragmented?(table) do
    case :mnesia.table_info(table, :frag_properties) do
      [] -> false
      _ -> true
    end
  rescue
    _ -> false
  end
  
  defp run_maintenance_tasks do
    # Force data durability by dumping tables
    try do
      # Dump all tables to ensure durability
      :mnesia.dump_tables(:mnesia.system_info(:tables))
      Logger.debug("Successfully dumped all tables")
    rescue
      error ->
        Logger.warning("Table dump failed: #{inspect(error)}")
    end
    
    # Trigger async log dump if needed
    :mnesia.dump_log()
  end
  
  defp collect_performance_metrics(state) do
    %{
      last_optimization: state.last_optimization,
      table_stats: state.table_stats,
      fragmentation_status: state.fragmentation_status,
      mnesia_metrics: %{
        held_locks: length(:mnesia.system_info(:held_locks)),
        lock_queue: length(:mnesia.system_info(:lock_queue)),
        transactions: :mnesia.system_info(:transaction_commits),
        log_writes: :mnesia.system_info(:transaction_log_writes)
      }
    }
  end
  
  defp schedule_optimization do
    Process.send_after(self(), :optimize, @optimization_interval)
  end
end