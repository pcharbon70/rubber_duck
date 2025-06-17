defmodule RubberDuck.TableMaintenance do
  @moduledoc """
  Handles periodic maintenance and cleanup procedures for Mnesia tables.
  
  This module ensures optimal performance by:
  - Cleaning up old/expired data
  - Compacting tables
  - Managing table size limits
  - Archiving historical data
  """
  
  use GenServer
  require Logger
  
  
  @maintenance_interval :timer.hours(6)
  @cleanup_batch_size 1000
  @max_table_size 5_000_000
  @archive_after_days 30
  @retention_days 90
  
  # Table-specific retention policies
  @retention_policies %{
    ai_context: %{days: 7, max_records: 10_000},
    code_analysis_cache: %{days: 30, max_records: 50_000},
    llm_interaction: %{days: 90, max_records: 100_000}
  }
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    state = %{
      last_maintenance: nil,
      maintenance_stats: %{},
      archive_location: Keyword.get(Application.get_env(:rubber_duck, __MODULE__, []), :archive_path, "./archives")
    }
    
    # Schedule first maintenance
    schedule_maintenance()
    
    {:ok, state}
  end
  
  @doc """
  Triggers immediate maintenance for a specific table
  """
  def maintain_table(table_name) do
    GenServer.call(__MODULE__, {:maintain_table, table_name}, :infinity)
  end
  
  @doc """
  Runs full maintenance on all tables
  """
  def run_full_maintenance do
    GenServer.call(__MODULE__, :full_maintenance, :infinity)
  end
  
  @doc """
  Archives old data to disk
  """
  def archive_old_data(table_name, days_old \\ @archive_after_days) do
    GenServer.call(__MODULE__, {:archive_data, table_name, days_old}, :infinity)
  end
  
  @doc """
  Gets maintenance statistics
  """
  def get_maintenance_stats do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  # Callbacks
  
  def handle_call({:maintain_table, table_name}, _from, state) do
    Logger.info("Starting maintenance for table: #{table_name}")
    
    stats = perform_table_maintenance(table_name)
    
    new_state = put_in(state.maintenance_stats[table_name], stats)
    {:reply, {:ok, stats}, new_state}
  end
  
  def handle_call(:full_maintenance, _from, state) do
    Logger.info("Starting full maintenance for all tables")
    
    tables = :mnesia.system_info(:tables) -- [:schema]
    
    stats = Enum.reduce(tables, %{}, fn table, acc ->
      table_stats = perform_table_maintenance(table)
      Map.put(acc, table, table_stats)
    end)
    
    new_state = %{state | 
      last_maintenance: DateTime.utc_now(),
      maintenance_stats: Map.merge(state.maintenance_stats, stats)
    }
    
    {:reply, {:ok, stats}, new_state}
  end
  
  def handle_call({:archive_data, table_name, days_old}, _from, state) do
    Logger.info("Archiving data older than #{days_old} days from #{table_name}")
    
    result = archive_table_data(table_name, days_old, state.archive_location)
    
    {:reply, result, state}
  end
  
  def handle_call(:get_stats, _from, state) do
    stats = %{
      last_maintenance: state.last_maintenance,
      table_stats: state.maintenance_stats,
      archive_location: state.archive_location
    }
    
    {:reply, stats, state}
  end
  
  def handle_info(:scheduled_maintenance, state) do
    Logger.info("Running scheduled maintenance")
    
    # Run maintenance in background
    Task.start(fn ->
      GenServer.call(__MODULE__, :full_maintenance, :infinity)
    end)
    
    # Schedule next maintenance
    schedule_maintenance()
    
    {:noreply, state}
  end
  
  # Private functions
  
  defp perform_table_maintenance(table) do
    start_time = System.monotonic_time(:millisecond)
    
    # Get retention policy for table
    policy = Map.get(@retention_policies, table, %{days: @retention_days, max_records: @max_table_size})
    
    # Perform maintenance tasks
    cleanup_stats = cleanup_old_records(table, policy.days)
    size_stats = enforce_size_limit(table, policy.max_records)
    compact_stats = compact_table(table)
    
    end_time = System.monotonic_time(:millisecond)
    
    %{
      table: table,
      duration_ms: end_time - start_time,
      records_deleted: cleanup_stats.deleted,
      records_archived: cleanup_stats.archived,
      size_before: size_stats.before,
      size_after: size_stats.after,
      compacted: compact_stats.success,
      timestamp: DateTime.utc_now()
    }
  end
  
  defp cleanup_old_records(table, retention_days) do
    cutoff_date = DateTime.add(DateTime.utc_now(), -retention_days * 86400, :second)
    
    deleted = delete_old_records_batch(table, cutoff_date, 0)
    
    %{deleted: deleted, archived: 0}
  end
  
  defp delete_old_records_batch(table, cutoff_date, total_deleted) do
    query_fun = fn ->
      # Find old records
      old_records = :mnesia.foldl(
        fn record, acc ->
          if should_delete_record?(record, cutoff_date) do
            [record | acc]
          else
            acc
          end
        end,
        [],
        table
      )
      |> Enum.take(@cleanup_batch_size)
      
      # Delete them
      Enum.each(old_records, fn record ->
        :mnesia.delete_object(record)
      end)
      
      length(old_records)
    end
    
    case :mnesia.transaction(query_fun) do
      {:atomic, deleted_count} when deleted_count > 0 ->
        # Continue deleting in batches
        delete_old_records_batch(table, cutoff_date, total_deleted + deleted_count)
      
      {:atomic, 0} ->
        total_deleted
      
      {:aborted, reason} ->
        Logger.error("Failed to delete old records from #{table}: #{inspect(reason)}")
        total_deleted
    end
  end
  
  defp should_delete_record?(record, cutoff_date) do
    # Extract timestamp based on table structure
    timestamp = case record do
      {_table, _id, _session_id, _field4, _field5, timestamp} ->
        timestamp
      {_table, _id, _session_id, _prompt, _response, timestamp, _metadata} ->
        timestamp
      _ ->
        nil
    end
    
    case timestamp do
      %DateTime{} ->
        DateTime.compare(timestamp, cutoff_date) == :lt
      _ ->
        false
    end
  end
  
  defp enforce_size_limit(table, max_records) do
    current_size = :mnesia.table_info(table, :size)
    
    if current_size > max_records do
      # Delete oldest records to bring under limit
      to_delete = current_size - max_records
      deleted = delete_oldest_records(table, to_delete)
      
      %{before: current_size, after: current_size - deleted}
    else
      %{before: current_size, after: current_size}
    end
  rescue
    _ -> %{before: 0, after: 0}
  end
  
  defp delete_oldest_records(table, count) do
    query_fun = fn ->
      # Get all records sorted by timestamp
      records = :mnesia.foldl(
        fn record, acc -> [record | acc] end,
        [],
        table
      )
      |> Enum.sort_by(&extract_timestamp/1)
      |> Enum.take(count)
      
      # Delete the oldest ones
      Enum.each(records, fn record ->
        :mnesia.delete_object(record)
      end)
      
      length(records)
    end
    
    case :mnesia.transaction(query_fun) do
      {:atomic, deleted} -> deleted
      {:aborted, _reason} -> 0
    end
  end
  
  defp extract_timestamp(record) do
    case record do
      {_table, _id, _session_id, _field4, _field5, timestamp} ->
        timestamp
      {_table, _id, _session_id, _prompt, _response, timestamp, _metadata} ->
        timestamp
      _ ->
        DateTime.utc_now()
    end
  end
  
  defp compact_table(table) do
    # Force table compaction by dumping to disk
    try do
      case :mnesia.dump_tables([table]) do
        {:atomic, :ok} ->
          %{success: true, error: nil}
        {:aborted, reason} ->
          %{success: false, error: reason}
      end
    rescue
      error ->
        %{success: false, error: error}
    end
  end
  
  defp archive_table_data(table, days_old, archive_path) do
    cutoff_date = DateTime.add(DateTime.utc_now(), -days_old * 86400, :second)
    
    # Ensure archive directory exists
    File.mkdir_p!(archive_path)
    
    # Create archive file name
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601() |> String.replace(~r/[:]/, "-")
    archive_file = Path.join(archive_path, "#{table}_#{timestamp}.dets")
    
    # Open DETS file for archiving
    {:ok, dets_table} = :dets.open_file(String.to_atom(archive_file), [
      type: :set,
      file: String.to_charlist(archive_file)
    ])
    
    # Archive old records
    archived_count = archive_records_batch(table, dets_table, cutoff_date, 0)
    
    # Close DETS file
    :dets.close(dets_table)
    
    # Compress archive file
    compress_archive(archive_file)
    
    {:ok, %{
      archived_records: archived_count,
      archive_file: archive_file <> ".gz",
      cutoff_date: cutoff_date
    }}
  end
  
  defp archive_records_batch(table, dets_table, cutoff_date, total_archived) do
    query_fun = fn ->
      # Find records to archive
      records_to_archive = :mnesia.foldl(
        fn record, acc ->
          if should_delete_record?(record, cutoff_date) do
            [record | acc]
          else
            acc
          end
        end,
        [],
        table
      )
      |> Enum.take(@cleanup_batch_size)
      
      # Archive to DETS
      Enum.each(records_to_archive, fn record ->
        :dets.insert(dets_table, record)
        :mnesia.delete_object(record)
      end)
      
      length(records_to_archive)
    end
    
    case :mnesia.transaction(query_fun) do
      {:atomic, archived_count} when archived_count > 0 ->
        # Continue archiving in batches
        archive_records_batch(table, dets_table, cutoff_date, total_archived + archived_count)
      
      {:atomic, 0} ->
        total_archived
      
      {:aborted, reason} ->
        Logger.error("Failed to archive records from #{table}: #{inspect(reason)}")
        total_archived
    end
  end
  
  defp compress_archive(file_path) do
    # Compress using gzip
    {:ok, data} = File.read(file_path)
    compressed = :zlib.gzip(data)
    File.write!(file_path <> ".gz", compressed)
    File.rm!(file_path)
  end
  
  defp schedule_maintenance do
    Process.send_after(self(), :scheduled_maintenance, @maintenance_interval)
  end
end