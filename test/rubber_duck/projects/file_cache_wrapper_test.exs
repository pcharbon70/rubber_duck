defmodule RubberDuck.Projects.FileCacheWrapperTest do
  use RubberDuck.DataCase, async: true
  alias RubberDuck.Projects.{FileCacheWrapper, CacheStats}
  
  setup do
    # Services are already started by the application
    # Just reset stats before each test
    CacheStats.reset_stats(:all)
    FileCacheWrapper.clear()
    
    :ok
  end
  
  describe "get/2" do
    test "records hit when value is found" do
      # Put a value in the cache
      FileCacheWrapper.put("project_1", "test/file.ex", %{content: "test"})
      
      # Get the value
      result = FileCacheWrapper.get("project_1", "test/file.ex")
      
      assert {:ok, %{content: "test"}} = result
      
      # Check that hit was recorded
      {:ok, stats} = CacheStats.get_stats("project_1")
      assert stats.total_hits == 1
      assert stats.total_misses == 0
    end
    
    test "records miss when value not found" do
      result = FileCacheWrapper.get("project_1", "missing/file.ex")
      
      assert result == :miss
      
      # Check that miss was recorded
      {:ok, stats} = CacheStats.get_stats("project_1")
      assert stats.total_hits == 0
      assert stats.total_misses == 1
    end
  end
  
  describe "put/4" do
    test "records put operation with size tracking" do
      value = %{content: "This is a test file content"}
      
      result = FileCacheWrapper.put("project_1", "test/file.ex", value)
      
      assert result == :ok
      
      # Check that put was recorded with size
      {:ok, stats} = CacheStats.get_stats("project_1")
      assert stats.total_puts == 1
      assert stats.memory_bytes > 0
    end
    
    test "accepts options and passes them through" do
      value = %{content: "test"}
      ttl = :timer.minutes(10)
      
      result = FileCacheWrapper.put("project_1", "test/file.ex", value, ttl: ttl)
      
      assert result == :ok
      assert {:ok, ^value} = FileCacheWrapper.get("project_1", "test/file.ex")
    end
  end
  
  describe "invalidate/2" do
    test "records delete operation with size" do
      value = %{content: "test content"}
      
      # Put and then invalidate
      FileCacheWrapper.put("project_1", "test/file.ex", value)
      result = FileCacheWrapper.invalidate("project_1", "test/file.ex")
      
      assert result == :ok
      
      # Check that delete was recorded
      {:ok, stats} = CacheStats.get_stats("project_1")
      assert stats.total_puts == 1
      assert stats.total_deletes == 1
      # Memory should be back to 0 after delete
      assert stats.memory_bytes == 0
    end
    
    test "handles invalidation of non-existent entry" do
      result = FileCacheWrapper.invalidate("project_1", "missing/file.ex")
      
      assert result == :ok
      
      # No delete should be recorded for missing entry
      {:ok, stats} = CacheStats.get_stats("project_1")
      assert stats.total_deletes == 0
    end
  end
  
  describe "invalidate_project/1" do
    test "clears all entries and resets stats for project" do
      # Add multiple entries
      FileCacheWrapper.put("project_1", "file1.ex", %{content: "1"})
      FileCacheWrapper.put("project_1", "file2.ex", %{content: "2"})
      FileCacheWrapper.put("project_1", "file3.ex", %{content: "3"})
      
      # Record some hits
      FileCacheWrapper.get("project_1", "file1.ex")
      FileCacheWrapper.get("project_1", "file2.ex")
      
      # Invalidate entire project
      result = FileCacheWrapper.invalidate_project("project_1")
      
      assert result == :ok
      
      # Check that stats were reset
      {:ok, stats} = CacheStats.get_stats("project_1")
      assert stats.total_hits == 0
      assert stats.total_puts == 0
      assert stats.memory_bytes == 0
      
      # Verify entries are gone
      assert FileCacheWrapper.get("project_1", "file1.ex") == :miss
    end
  end
  
  describe "get_combined_stats/1" do
    test "combines FileCache and CacheStats statistics" do
      # Add some data
      FileCacheWrapper.put("project_1", "file1.ex", %{content: "test"})
      FileCacheWrapper.get("project_1", "file1.ex")
      FileCacheWrapper.get("project_1", "missing.ex")
      
      combined_stats = FileCacheWrapper.get_combined_stats()
      
      # Should have both FileCache stats (size, memory) and CacheStats data
      assert is_map(combined_stats)
      assert Map.has_key?(combined_stats, :size)
      assert Map.has_key?(combined_stats, :total_hits)
      assert Map.has_key?(combined_stats, :hit_rate)
    end
  end
  
  describe "delegated functions" do
    test "invalidate_pattern/2 is delegated to FileCache" do
      # Add multiple files
      FileCacheWrapper.put("project_1", "dir/file1.ex", %{content: "1"})
      FileCacheWrapper.put("project_1", "dir/file2.ex", %{content: "2"})
      FileCacheWrapper.put("project_1", "other/file3.ex", %{content: "3"})
      
      # Invalidate pattern
      {:ok, count} = FileCacheWrapper.invalidate_pattern("project_1", "dir/*")
      
      assert count == 2
      assert FileCacheWrapper.get("project_1", "dir/file1.ex") == :miss
      assert FileCacheWrapper.get("project_1", "dir/file2.ex") == :miss
      assert {:ok, _} = FileCacheWrapper.get("project_1", "other/file3.ex")
    end
    
    test "clear/0 clears all cache entries" do
      FileCacheWrapper.put("project_1", "file1.ex", %{content: "1"})
      FileCacheWrapper.put("project_2", "file2.ex", %{content: "2"})
      
      FileCacheWrapper.clear()
      
      assert FileCacheWrapper.get("project_1", "file1.ex") == :miss
      assert FileCacheWrapper.get("project_2", "file2.ex") == :miss
    end
    
    test "stats/0 returns FileCache statistics" do
      FileCacheWrapper.put("project_1", "file.ex", %{content: "test"})
      
      stats = FileCacheWrapper.stats()
      
      assert is_map(stats)
      assert stats.size == 1
    end
  end
  
  describe "size estimation" do
    test "estimates sizes for different data types" do
      # Small string
      FileCacheWrapper.put("project_1", "small.txt", "hello")
      
      # Large map
      large_map = for i <- 1..100, into: %{}, do: {"key_#{i}", "value_#{i}"}
      FileCacheWrapper.put("project_1", "large.json", large_map)
      
      # Binary data
      binary_data = :crypto.strong_rand_bytes(1024)
      FileCacheWrapper.put("project_1", "binary.dat", binary_data)
      
      {:ok, stats} = CacheStats.get_stats("project_1")
      
      # Memory should reflect different sizes
      assert stats.memory_bytes > 1024
      assert stats.total_puts == 3
    end
  end
end