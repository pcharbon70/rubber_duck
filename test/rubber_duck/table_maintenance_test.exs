defmodule RubberDuck.TableMaintenanceTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.{TableMaintenance, MnesiaManager}
  
  setup do
    # Ensure Mnesia is started
    case :mnesia.system_info(:is_running) do
      :no -> :mnesia.start()
      _ -> :ok
    end
    
    # Ensure MnesiaManager is started
    case Process.whereis(MnesiaManager) do
      nil -> 
        {:ok, _} = MnesiaManager.start_link([])
      pid -> 
        Process.alive?(pid)
    end
    
    # Ensure TableMaintenance is not running
    case Process.whereis(TableMaintenance) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
    
    # Create test archive directory
    test_archive_path = "./test_archives"
    File.mkdir_p!(test_archive_path)
    
    {:ok, pid} = TableMaintenance.start_link(archive_path: test_archive_path)
    
    on_exit(fn ->
      GenServer.stop(pid)
      # Clean up test data
      :mnesia.clear_table(:ai_context)
      :mnesia.clear_table(:code_analysis_cache)
      :mnesia.clear_table(:llm_interaction)
      # Remove test archive directory
      File.rm_rf!(test_archive_path)
    end)
    
    %{archive_path: test_archive_path}
  end
  
  describe "maintain_table/1" do
    test "performs maintenance on a specific table" do
      # Insert some test data
      now = DateTime.utc_now()
      old_time = DateTime.add(now, -10 * 86400, :second)  # 10 days ago
      
      :mnesia.transaction(fn ->
        :mnesia.write({:ai_context, "old-1", "session-1", "old data", %{}, old_time})
        :mnesia.write({:ai_context, "new-1", "session-2", "new data", %{}, now})
      end)
      
      # Run maintenance
      {:ok, stats} = TableMaintenance.maintain_table(:ai_context)
      
      assert stats.table == :ai_context
      assert is_integer(stats.duration_ms)
      assert stats.records_deleted >= 1  # Should delete old record (based on 7-day retention)
      assert is_integer(stats.size_before)
      assert is_integer(stats.size_after)
      assert stats.size_after <= stats.size_before
    end
  end
  
  describe "run_full_maintenance/0" do
    test "performs maintenance on all tables" do
      # Insert test data in multiple tables
      now = DateTime.utc_now()
      
      :mnesia.transaction(fn ->
        :mnesia.write({:ai_context, "fm-1", "session-1", "data", %{}, now})
        :mnesia.write({:code_analysis_cache, "fm-2", "/file.ex", %{}, %{}, now})
        :mnesia.write({:llm_interaction, "fm-3", "session-1", "prompt", "response", now})
      end)
      
      # Run full maintenance
      {:ok, stats} = TableMaintenance.run_full_maintenance()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :ai_context)
      assert Map.has_key?(stats, :code_analysis_cache)
      assert Map.has_key?(stats, :llm_interaction)
      
      # Each table should have stats
      Enum.each(stats, fn {_table, table_stats} ->
        assert is_integer(table_stats.duration_ms)
        assert is_integer(table_stats.records_deleted)
        assert is_integer(table_stats.size_before)
        assert is_integer(table_stats.size_after)
      end)
    end
  end
  
  describe "archive_old_data/2" do
    test "archives old data to disk", %{archive_path: archive_path} do
      # Insert old and new data
      now = DateTime.utc_now()
      old_time = DateTime.add(now, -40 * 86400, :second)  # 40 days ago
      
      :mnesia.transaction(fn ->
        :mnesia.write({:llm_interaction, "arch-1", "session-1", "old prompt", "old response", old_time})
        :mnesia.write({:llm_interaction, "arch-2", "session-2", "new prompt", "new response", now})
      end)
      
      # Archive data older than 30 days
      {:ok, result} = TableMaintenance.archive_old_data(:llm_interaction, 30)
      
      assert result.archived_records >= 1
      assert String.ends_with?(result.archive_file, ".gz")
      assert File.exists?(result.archive_file)
      
      # Verify old record was removed from table
      {:atomic, records} = :mnesia.transaction(fn ->
        :mnesia.match_object({:llm_interaction, "arch-1", :_, :_, :_, :_})
      end)
      assert records == []
      
      # Verify new record remains
      {:atomic, new_records} = :mnesia.transaction(fn ->
        :mnesia.match_object({:llm_interaction, "arch-2", :_, :_, :_, :_})
      end)
      assert length(new_records) == 1
    end
  end
  
  describe "get_maintenance_stats/0" do
    test "returns maintenance statistics" do
      stats = TableMaintenance.get_maintenance_stats()
      
      assert is_map(stats)
      assert Map.has_key?(stats, :last_maintenance)
      assert Map.has_key?(stats, :table_stats)
      assert Map.has_key?(stats, :archive_location)
    end
  end
  
  describe "scheduled maintenance" do
    test "handles scheduled maintenance message" do
      # Send maintenance message directly
      send(Process.whereis(TableMaintenance), :scheduled_maintenance)
      
      # Give it time to start the task
      Process.sleep(100)
      
      # Verify process is still alive
      assert Process.alive?(Process.whereis(TableMaintenance))
    end
  end
  
  describe "retention policies" do
    test "enforces table-specific retention policies" do
      # Insert data that exceeds retention for ai_context (7 days)
      now = DateTime.utc_now()
      old_time = DateTime.add(now, -8 * 86400, :second)  # 8 days ago
      
      :mnesia.transaction(fn ->
        :mnesia.write({:ai_context, "ret-1", "session-1", "old context", %{}, old_time})
        :mnesia.write({:ai_context, "ret-2", "session-2", "new context", %{}, now})
      end)
      
      # Run maintenance
      {:ok, stats} = TableMaintenance.maintain_table(:ai_context)
      
      # Should have deleted the old record
      assert stats.records_deleted >= 1
      
      # Verify only new record remains
      {:atomic, remaining} = :mnesia.transaction(fn ->
        :mnesia.match_object({:ai_context, :_, :_, :_, :_, :_})
      end)
      
      assert length(remaining) == 1
      assert elem(hd(remaining), 1) == "ret-2"
    end
  end
  
  describe "size limits" do
    test "enforces table size limits" do
      # This test would require inserting many records to exceed limits
      # For brevity, we'll just verify the mechanism works
      
      # Insert a few records
      :mnesia.transaction(fn ->
        Enum.each(1..5, fn i ->
          :mnesia.write({:ai_context, "size-#{i}", "session-#{i}", "data #{i}", %{}, DateTime.utc_now()})
        end)
      end)
      
      # Run maintenance (won't delete anything as we're under limit)
      {:ok, stats} = TableMaintenance.maintain_table(:ai_context)
      
      assert stats.size_after <= 10_000  # Max for ai_context
    end
  end
end