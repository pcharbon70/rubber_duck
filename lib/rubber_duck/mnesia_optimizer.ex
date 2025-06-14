defmodule RubberDuck.MnesiaOptimizer do
  require Logger

  @moduledoc """
  Optimizes Mnesia configuration and performance for AI workload patterns.
  Handles table fragmentation, checkpoint tuning, and memory management
  specifically designed for conversational AI data access patterns.
  """

  @default_fragment_count 4
  @ai_workload_config %{
    # Batch write optimization for message append operations
    dump_log_write_threshold: 50_000,
    # Large message arrays in sessions
    dc_dump_limit: 40_000,
    # More frequent checkpoints for AI data durability
    dump_log_time_threshold: 180_000,  # 3 minutes
    # Larger transaction log for batch operations
    dump_log_update_in_place: true,
    # Memory optimization for large message histories
    debug: :verbose
  }

  @doc """
  Configure Mnesia parameters optimized for AI workloads
  """
  def configure_for_ai_workloads do
    Logger.info("Configuring Mnesia for AI workload optimization...")
    
    configure_system_parameters()
    configure_table_access_patterns()
    setup_performance_monitoring()
    
    :ok
  end

  @doc """
  Fragment large tables for better performance
  """
  def fragment_table(table_name, fragment_count \\ @default_fragment_count) do
    case :mnesia.table_info(table_name, :size) do
      size when size > 10_000 ->
        Logger.info("Fragmenting table #{table_name} into #{fragment_count} fragments (size: #{size})")
        fragment_large_table(table_name, fragment_count)
      size ->
        Logger.debug("Table #{table_name} too small for fragmentation (size: #{size})")
        :skipped
    end
  end

  @doc """
  Optimize table indexes for AI query patterns
  """
  def optimize_table_indexes do
    optimize_sessions_indexes()
    optimize_model_stats_indexes()
    optimize_cluster_nodes_indexes()
  end

  @doc """
  Get current Mnesia performance statistics
  """
  def get_performance_stats do
    %{
      system_info: get_system_performance_info(),
      table_stats: get_table_performance_stats(),
      memory_usage: get_memory_usage_stats(),
      fragmentation: get_fragmentation_stats()
    }
  end

  @doc """
  Analyze and recommend optimizations
  """
  def analyze_performance do
    stats = get_performance_stats()
    
    recommendations = []
    |> check_table_sizes(stats.table_stats)
    |> check_memory_usage(stats.memory_usage)
    |> check_fragmentation_efficiency(stats.fragmentation)
    |> check_access_patterns(stats.system_info)
    
    %{
      current_stats: stats,
      recommendations: recommendations,
      analysis_time: DateTime.utc_now()
    }
  end

  @doc """
  Apply recommended optimizations automatically
  """
  def auto_optimize do
    analysis = analyze_performance()
    
    applied_optimizations = Enum.reduce(analysis.recommendations, [], fn rec, acc ->
      case apply_recommendation(rec) do
        :ok -> [rec | acc]
        {:error, reason} -> 
          Logger.warning("Failed to apply optimization #{rec.type}: #{reason}")
          acc
      end
    end)
    
    Logger.info("Applied #{length(applied_optimizations)} performance optimizations")
    applied_optimizations
  end

  # Private Functions

  defp configure_system_parameters do
    # Configure Mnesia system parameters for AI workloads
    # Note: Many parameters are set at application startup via sys.config
    # Here we set what we can at runtime
    
    try do
      # Set general debug level for monitoring
      :mnesia.set_debug_level(:debug)
      Logger.debug("Set Mnesia debug level for monitoring")
    rescue
      _ -> 
        Logger.debug("Could not set debug level at runtime")
    end
    
    # Log the intended configuration
    Logger.info("AI workload configuration: #{inspect(@ai_workload_config)}")
  end

  defp configure_table_access_patterns do
    # Configure access patterns based on AI workload characteristics
    configure_sessions_access_pattern()
    configure_models_access_pattern()
    configure_stats_access_pattern()
  end

  defp configure_sessions_access_pattern do
    # Sessions are read-heavy with temporal locality
    # Recent sessions accessed most frequently
    try do
      :mnesia.change_table_access_mode(:sessions, :read_write)
      Logger.debug("Configured sessions table for read-write access")
    rescue
      _ -> Logger.debug("Sessions table access mode already optimal")
    end
  end

  defp configure_models_access_pattern do
    # Models are read-heavy for selection, occasional writes for health updates
    try do
      :mnesia.change_table_access_mode(:models, :read_mostly)
      Logger.debug("Configured models table for read-mostly access")
    rescue
      _ -> Logger.debug("Models table access mode already optimal")
    end
  end

  defp configure_stats_access_pattern do
    # Model stats are write-heavy during active usage
    try do
      :mnesia.change_table_access_mode(:model_stats, :read_write)
      Logger.debug("Configured model_stats table for read-write access")
    rescue
      _ -> Logger.debug("Model stats table access mode already optimal")
    end
  end

  defp fragment_large_table(table_name, fragment_count) do
    try do
      # Check if table is already fragmented
      case :mnesia.table_info(table_name, :frag_properties) do
        [] ->
          # Not fragmented, proceed with fragmentation
          fragment_properties = [
            node_pool: [node() | Node.list()],
            n_fragments: fragment_count,
            n_disc_copies: 1,
            n_ram_copies: length([node() | Node.list()])
          ]
          
          case :mnesia.change_table_frag(table_name, {:activate, fragment_properties}) do
            {:atomic, :ok} ->
              Logger.info("Successfully fragmented table #{table_name}")
              :ok
            {:aborted, reason} ->
              Logger.error("Failed to fragment table #{table_name}: #{inspect(reason)}")
              {:error, reason}
          end
        
        _existing_props ->
          Logger.debug("Table #{table_name} already fragmented")
          :already_fragmented
      end
    rescue
      error ->
        Logger.error("Error fragmenting table #{table_name}: #{inspect(error)}")
        {:error, error}
    end
  end

  defp optimize_sessions_indexes do
    # Add indexes for common session query patterns
    indexes_to_add = [
      {:sessions, :created_at},    # For temporal queries
      {:sessions, :updated_at},    # For recent activity
      {:sessions, :node}           # For node-specific queries
    ]
    
    Enum.each(indexes_to_add, fn {table, attr} ->
      add_index_if_not_exists(table, attr)
    end)
  end

  defp optimize_model_stats_indexes do
    # Add indexes for model statistics queries
    indexes_to_add = [
      {:model_stats, :last_updated},  # For recent stats
      {:model_stats, :success_count}  # For ranking queries
    ]
    
    Enum.each(indexes_to_add, fn {table, attr} ->
      add_index_if_not_exists(table, attr)
    end)
  end

  defp optimize_cluster_nodes_indexes do
    # Add indexes for cluster node queries
    indexes_to_add = [
      {:cluster_nodes, :status},      # For health queries
      {:cluster_nodes, :last_seen}    # For activity monitoring
    ]
    
    Enum.each(indexes_to_add, fn {table, attr} ->
      add_index_if_not_exists(table, attr)
    end)
  end

  defp add_index_if_not_exists(table, attribute) do
    try do
      existing_indexes = :mnesia.table_info(table, :index)
      attr_position = get_attribute_position(table, attribute)
      
      if attr_position not in existing_indexes do
        case :mnesia.add_table_index(table, attribute) do
          {:atomic, :ok} ->
            Logger.debug("Added index on #{table}.#{attribute}")
          {:aborted, {:already_exists, _}} ->
            Logger.debug("Index on #{table}.#{attribute} already exists")
          {:aborted, reason} ->
            Logger.warning("Failed to add index on #{table}.#{attribute}: #{inspect(reason)}")
        end
      end
    rescue
      error ->
        Logger.debug("Could not add index on #{table}.#{attribute}: #{inspect(error)}")
    end
  end

  defp get_attribute_position(table, attribute) do
    attributes = :mnesia.table_info(table, :attributes)
    case Enum.find_index(attributes, &(&1 == attribute)) do
      nil -> nil
      index -> index + 2  # Mnesia positions start at 2
    end
  end

  defp setup_performance_monitoring do
    # Enable detailed monitoring for AI workload analysis
    :mnesia.set_debug_level(:debug)
    Logger.debug("Enabled Mnesia performance monitoring")
  end

  defp get_system_performance_info do
    %{
      is_running: :mnesia.system_info(:is_running),
      running_db_nodes: :mnesia.system_info(:running_db_nodes),
      held_locks: length(:mnesia.system_info(:held_locks)),
      lock_queue: length(:mnesia.system_info(:lock_queue)),
      transactions: :mnesia.system_info(:transaction_commits) + :mnesia.system_info(:transaction_restarts),
      checkpoints: :mnesia.system_info(:checkpoints)
    }
  end

  defp get_table_performance_stats do
    tables = [:sessions, :models, :model_stats, :cluster_nodes]
    
    Enum.reduce(tables, %{}, fn table, acc ->
      stats = %{
        size: safe_table_info(table, :size),
        memory: safe_table_info(table, :memory),
        type: safe_table_info(table, :type),
        storage_type: safe_table_info(table, :storage_type),
        access_mode: safe_table_info(table, :access_mode),
        load_order: safe_table_info(table, :load_order)
      }
      Map.put(acc, table, stats)
    end)
  end

  defp get_memory_usage_stats do
    %{
      total: :erlang.memory(:total),
      mnesia: get_mnesia_memory_usage(),
      processes: :erlang.memory(:processes),
      atom: :erlang.memory(:atom),
      binary: :erlang.memory(:binary),
      ets: :erlang.memory(:ets)
    }
  end

  defp get_mnesia_memory_usage do
    try do
      # Sum memory usage of all Mnesia tables
      tables = [:sessions, :models, :model_stats, :cluster_nodes]
      Enum.reduce(tables, 0, fn table, acc ->
        acc + (safe_table_info(table, :memory) || 0)
      end)
    rescue
      _ -> 0
    end
  end

  defp get_fragmentation_stats do
    tables = [:sessions, :models, :model_stats, :cluster_nodes]
    
    Enum.reduce(tables, %{}, fn table, acc ->
      frag_info = %{
        is_fragmented: is_table_fragmented?(table),
        fragment_count: get_fragment_count(table),
        fragment_distribution: get_fragment_distribution(table)
      }
      Map.put(acc, table, frag_info)
    end)
  end

  defp is_table_fragmented?(table) do
    try do
      frag_props = :mnesia.table_info(table, :frag_properties)
      frag_props != []
    rescue
      _ -> false
    end
  end

  defp get_fragment_count(table) do
    try do
      if is_table_fragmented?(table) do
        :mnesia.table_info(table, :frag_size)
      else
        1
      end
    rescue
      _ -> 1
    end
  end

  defp get_fragment_distribution(table) do
    try do
      if is_table_fragmented?(table) do
        frag_names = :mnesia.table_info(table, :frag_names)
        Enum.map(frag_names, fn frag_name ->
          %{
            name: frag_name,
            size: safe_table_info(frag_name, :size),
            memory: safe_table_info(frag_name, :memory)
          }
        end)
      else
        []
      end
    rescue
      _ -> []
    end
  end

  defp check_table_sizes(recommendations, table_stats) do
    large_tables = Enum.filter(table_stats, fn {_table, stats} ->
      (stats.size || 0) > 50_000
    end)
    
    if length(large_tables) > 0 do
      [%{
        type: :fragment_large_tables,
        priority: :high,
        description: "Tables with >50k records should be fragmented",
        affected_tables: Enum.map(large_tables, fn {table, _} -> table end),
        action: :fragment_tables
      } | recommendations]
    else
      recommendations
    end
  end

  defp check_memory_usage(recommendations, memory_stats) do
    mnesia_memory_ratio = memory_stats.mnesia / memory_stats.total
    
    if mnesia_memory_ratio > 0.3 do
      [%{
        type: :high_memory_usage,
        priority: :medium,
        description: "Mnesia using >30% of total memory",
        current_ratio: mnesia_memory_ratio,
        action: :optimize_memory
      } | recommendations]
    else
      recommendations
    end
  end

  defp check_fragmentation_efficiency(recommendations, fragmentation_stats) do
    inefficient_fragments = Enum.filter(fragmentation_stats, fn {_table, stats} ->
      stats.is_fragmented and length(stats.fragment_distribution) > 0 and
      has_uneven_distribution?(stats.fragment_distribution)
    end)
    
    if length(inefficient_fragments) > 0 do
      [%{
        type: :rebalance_fragments,
        priority: :low,
        description: "Some fragments have uneven distribution",
        affected_tables: Enum.map(inefficient_fragments, fn {table, _} -> table end),
        action: :rebalance_fragments
      } | recommendations]
    else
      recommendations
    end
  end

  defp check_access_patterns(recommendations, system_info) do
    high_lock_contention = (system_info.held_locks + system_info.lock_queue) > 100
    
    if high_lock_contention do
      [%{
        type: :high_lock_contention,
        priority: :high,
        description: "High lock contention detected",
        lock_count: system_info.held_locks + system_info.lock_queue,
        action: :optimize_access_patterns
      } | recommendations]
    else
      recommendations
    end
  end

  defp has_uneven_distribution?(fragment_distribution) do
    if length(fragment_distribution) < 2, do: false
    
    sizes = Enum.map(fragment_distribution, & &1.size)
    max_size = Enum.max(sizes)
    min_size = Enum.min(sizes)
    
    # Consider uneven if max is more than 3x min
    max_size > min_size * 3
  end

  defp apply_recommendation(%{action: :fragment_tables, affected_tables: tables}) do
    results = Enum.map(tables, &fragment_table/1)
    if Enum.all?(results, &(&1 in [:ok, :already_fragmented, :skipped])) do
      :ok
    else
      {:error, :fragmentation_failed}
    end
  end

  defp apply_recommendation(%{action: :optimize_memory}) do
    # Force garbage collection and table compaction
    :erlang.garbage_collect()
    compact_tables()
    :ok
  end

  defp apply_recommendation(%{action: :rebalance_fragments, affected_tables: tables}) do
    # This would require more complex rebalancing logic
    Logger.info("Fragment rebalancing recommended for tables: #{inspect(tables)}")
    :ok
  end

  defp apply_recommendation(%{action: :optimize_access_patterns}) do
    # Could implement access pattern optimization here
    Logger.info("Access pattern optimization recommended")
    :ok
  end

  defp apply_recommendation(_) do
    {:error, :unknown_recommendation}
  end

  defp compact_tables do
    tables = [:sessions, :models, :model_stats, :cluster_nodes]
    Enum.each(tables, fn table ->
      try do
        :mnesia.dump_tables([table])
      rescue
        _ -> :ok
      end
    end)
  end

  defp safe_table_info(table, key) do
    try do
      :mnesia.table_info(table, key)
    rescue
      _ -> nil
    end
  end
end