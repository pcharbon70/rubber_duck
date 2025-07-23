defmodule RubberDuck.Projects.CacheStatsTest do
  use RubberDuck.DataCase, async: true
  alias RubberDuck.Projects.CacheStats
  
  setup do
    # CacheStats is already started by the application
    # Just reset stats before each test
    CacheStats.reset_stats(:all)
    
    :ok
  end
  
  describe "record_hit/3" do
    test "records a cache hit with size" do
      CacheStats.record_hit("project_1", "path/to/file.ex", 1024)
      
      {:ok, stats} = CacheStats.get_stats("project_1")
      
      assert stats.total_hits == 1
      assert stats.total_misses == 0
      assert stats.memory_bytes == 1024
      assert stats.hit_rate == 100.0
    end
    
    test "records multiple hits" do
      CacheStats.record_hit("project_1", "file1.ex", 500)
      CacheStats.record_hit("project_1", "file2.ex", 300)
      CacheStats.record_hit("project_1", "file1.ex", 500)
      
      {:ok, stats} = CacheStats.get_stats("project_1")
      
      assert stats.total_hits == 3
      assert stats.memory_bytes == 1300 # 500 + 300 + 500
    end
  end
  
  describe "record_miss/2" do
    test "records a cache miss" do
      CacheStats.record_miss("project_1", "missing_file.ex")
      
      {:ok, stats} = CacheStats.get_stats("project_1")
      
      assert stats.total_hits == 0
      assert stats.total_misses == 1
      assert stats.hit_rate == 0.0
    end
    
    test "calculates correct hit rate with mixed hits and misses" do
      CacheStats.record_hit("project_1", "file1.ex", 100)
      CacheStats.record_hit("project_1", "file2.ex", 200)
      CacheStats.record_miss("project_1", "file3.ex")
      
      {:ok, stats} = CacheStats.get_stats("project_1")
      
      assert stats.total_hits == 2
      assert stats.total_misses == 1
      assert_in_delta stats.hit_rate, 66.67, 0.01
    end
  end
  
  describe "record_put/3" do
    test "records a cache put operation" do
      CacheStats.record_put("project_1", "new_file.ex", 2048)
      
      {:ok, stats} = CacheStats.get_stats("project_1")
      
      assert stats.total_puts == 1
      assert stats.memory_bytes == 2048
    end
  end
  
  describe "record_delete/3" do
    test "records a cache delete and adjusts memory" do
      CacheStats.record_put("project_1", "file.ex", 1000)
      CacheStats.record_delete("project_1", "file.ex", 1000)
      
      {:ok, stats} = CacheStats.get_stats("project_1")
      
      assert stats.total_puts == 1
      assert stats.total_deletes == 1
      assert stats.memory_bytes == 0
    end
    
    test "prevents negative memory bytes" do
      CacheStats.record_delete("project_1", "file.ex", 1000)
      
      {:ok, stats} = CacheStats.get_stats("project_1")
      
      assert stats.total_deletes == 1
      assert stats.memory_bytes == 0
    end
  end
  
  describe "get_hot_keys/2" do
    test "returns most accessed keys" do
      # Create access patterns
      for _ <- 1..10, do: CacheStats.record_hit("project_1", "hot_file.ex", 100)
      for _ <- 1..5, do: CacheStats.record_hit("project_1", "warm_file.ex", 100)
      for _ <- 1..2, do: CacheStats.record_hit("project_1", "cold_file.ex", 100)
      
      {:ok, hot_keys} = CacheStats.get_hot_keys("project_1", 2)
      
      assert length(hot_keys) == 2
      assert Enum.at(hot_keys, 0).key == "hot_file.ex"
      assert Enum.at(hot_keys, 0).access_count == 10
      assert Enum.at(hot_keys, 1).key == "warm_file.ex"
      assert Enum.at(hot_keys, 1).access_count == 5
    end
    
    test "tracks hit rate per key" do
      CacheStats.record_hit("project_1", "file.ex", 100)
      CacheStats.record_hit("project_1", "file.ex", 100)
      CacheStats.record_miss("project_1", "file.ex")
      
      {:ok, hot_keys} = CacheStats.get_hot_keys("project_1", 1)
      
      assert length(hot_keys) == 1
      hot_key = Enum.at(hot_keys, 0)
      assert hot_key.key == "file.ex"
      assert_in_delta hot_key.hit_rate, 66.67, 0.01
    end
  end
  
  describe "get_metrics/0" do
    test "calculates overall metrics" do
      # Add some data
      CacheStats.record_hit("project_1", "file1.ex", 1000)
      CacheStats.record_hit("project_1", "file2.ex", 2000)
      CacheStats.record_miss("project_1", "file3.ex")
      CacheStats.record_put("project_1", "file4.ex", 3000)
      
      # Wait a moment to have measurable time
      Process.sleep(10)
      
      {:ok, metrics} = CacheStats.get_metrics()
      
      assert metrics.hit_rate > 0
      assert metrics.operations_per_second >= 0
      assert metrics.average_memory_per_entry > 0
      assert metrics.cache_efficiency_score >= 0
    end
  end
  
  describe "reset_stats/1" do
    test "resets all statistics" do
      CacheStats.record_hit("project_1", "file.ex", 1000)
      CacheStats.record_miss("project_1", "file2.ex")
      
      CacheStats.reset_stats(:all)
      
      {:ok, stats} = CacheStats.get_stats(:all)
      
      assert stats.total_hits == 0
      assert stats.total_misses == 0
      assert stats.total_memory_bytes == 0
    end
    
    test "resets project-specific statistics" do
      CacheStats.record_hit("project_1", "file.ex", 1000)
      CacheStats.record_hit("project_2", "file.ex", 2000)
      
      CacheStats.reset_stats("project_1")
      
      {:ok, stats1} = CacheStats.get_stats("project_1")
      {:ok, stats2} = CacheStats.get_stats("project_2")
      
      assert stats1.total_hits == 0
      assert stats2.total_hits == 1
    end
  end
  
  describe "telemetry integration" do
    test "emits telemetry events on operations" do
      ref = make_ref()
      test_pid = self()
      
      # Attach a test handler
      :telemetry.attach(
        "test-handler-#{inspect(ref)}",
        [:rubber_duck, :cache, :hit],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )
      
      CacheStats.record_hit("project_1", "file.ex", 1024)
      
      assert_receive {:telemetry_event, [:rubber_duck, :cache, :hit], measurements, metadata}
      assert measurements.count == 1
      assert measurements.size == 1024
      assert metadata.project_id == "project_1"
      
      :telemetry.detach("test-handler-#{inspect(ref)}")
    end
  end
  
  describe "concurrent operations" do
    test "handles concurrent updates correctly" do
      # Spawn multiple processes to update stats concurrently
      tasks = for i <- 1..100 do
        Task.async(fn ->
          CacheStats.record_hit("project_1", "file_#{i}.ex", 100)
        end)
      end
      
      # Wait for all tasks to complete
      Enum.each(tasks, &Task.await/1)
      
      {:ok, stats} = CacheStats.get_stats("project_1")
      
      assert stats.total_hits == 100
      assert stats.memory_bytes == 10_000
    end
  end
end