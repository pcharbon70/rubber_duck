defmodule RubberDuck.CodingAssistant.Engines.ExplanationCacheTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.CodingAssistant.Engines.ExplanationCache
  
  @sample_request %{
    content: "def add(a, b), do: a + b",
    language: :elixir,
    type: :summary,
    context: %{symbols: ["add"]}
  }
  
  @sample_result %{
    explanation: "This function adds two numbers together.",
    metadata: %{type: :summary, language: :elixir},
    confidence: 0.9,
    processing_time: 150
  }
  
  setup do
    # Start a cache process for each test
    {:ok, cache_pid} = ExplanationCache.start_link(max_size: 10, ttl: :timer.seconds(1))
    {:ok, cache_pid: cache_pid}
  end
  
  describe "cache_key generation" do
    test "generates consistent cache keys for same request" do
      key1 = ExplanationCache.generate_cache_key(@sample_request)
      key2 = ExplanationCache.generate_cache_key(@sample_request)
      
      assert key1 == key2
      assert is_binary(key1)
    end
    
    test "generates different keys for different content" do
      request1 = @sample_request
      request2 = %{@sample_request | content: "def multiply(a, b), do: a * b"}
      
      key1 = ExplanationCache.generate_cache_key(request1)
      key2 = ExplanationCache.generate_cache_key(request2)
      
      assert key1 != key2
    end
    
    test "generates different keys for different types" do
      request1 = @sample_request
      request2 = %{@sample_request | type: :detailed}
      
      key1 = ExplanationCache.generate_cache_key(request1)
      key2 = ExplanationCache.generate_cache_key(request2)
      
      assert key1 != key2
    end
    
    test "generates different keys for different languages" do
      request1 = @sample_request
      request2 = %{@sample_request | language: :javascript}
      
      key1 = ExplanationCache.generate_cache_key(request1)
      key2 = ExplanationCache.generate_cache_key(request2)
      
      assert key1 != key2
    end
    
    test "includes context in cache key" do
      request1 = @sample_request
      request2 = %{@sample_request | context: %{symbols: ["add", "extra"]}}
      
      key1 = ExplanationCache.generate_cache_key(request1)
      key2 = ExplanationCache.generate_cache_key(request2)
      
      assert key1 != key2
    end
  end
  
  describe "cache operations" do
    test "stores and retrieves cache entries", %{cache_pid: cache_pid} do
      # Initially should be a cache miss
      assert {:miss, :not_found} = ExplanationCache.get(cache_pid, @sample_request)
      
      # Store the result
      assert :ok = ExplanationCache.put(cache_pid, @sample_request, @sample_result)
      
      # Should now be a cache hit
      assert {:hit, entry} = ExplanationCache.get(cache_pid, @sample_request)
      assert entry.content == @sample_result.explanation
      assert entry.confidence == @sample_result.confidence
    end
    
    test "updates access information on cache hit", %{cache_pid: cache_pid} do
      # Store initial result
      ExplanationCache.put(cache_pid, @sample_request, @sample_result)
      
      # Get the entry
      {:hit, entry1} = ExplanationCache.get(cache_pid, @sample_request)
      initial_access_count = entry1.access_count
      initial_last_accessed = entry1.last_accessed
      
      # Wait a small amount and access again
      Process.sleep(10)
      {:hit, entry2} = ExplanationCache.get(cache_pid, @sample_request)
      
      # Access count should increase and timestamp should update
      assert entry2.access_count == initial_access_count + 1
      assert entry2.last_accessed > initial_last_accessed
    end
    
    test "handles cache miss correctly", %{cache_pid: cache_pid} do
      nonexistent_request = %{@sample_request | content: "nonexistent code"}
      
      assert {:miss, :not_found} = ExplanationCache.get(cache_pid, nonexistent_request)
    end
  end
  
  describe "cache validation" do
    test "validates fresh entries as valid" do
      entry = %{
        content: "explanation",
        confidence: 0.8,
        timestamp: System.system_time(:millisecond),
        access_count: 1,
        last_accessed: System.system_time(:millisecond)
      }
      
      assert {:valid, ^entry} = ExplanationCache.validate_cache_entry(entry)
    end
    
    test "invalidates expired entries" do
      old_timestamp = System.system_time(:millisecond) - :timer.hours(25)
      
      entry = %{
        content: "explanation",
        confidence: 0.8,
        timestamp: old_timestamp,
        access_count: 1,
        last_accessed: old_timestamp
      }
      
      assert {:invalid, :expired} = ExplanationCache.validate_cache_entry(entry)
    end
    
    test "invalidates low confidence entries" do
      entry = %{
        content: "explanation",
        confidence: 0.5,  # Below default threshold of 0.7
        timestamp: System.system_time(:millisecond),
        access_count: 1,
        last_accessed: System.system_time(:millisecond)
      }
      
      assert {:invalid, :low_confidence} = ExplanationCache.validate_cache_entry(entry, 0.7)
    end
    
    test "allows custom confidence threshold" do
      entry = %{
        content: "explanation",
        confidence: 0.6,
        timestamp: System.system_time(:millisecond),
        access_count: 1,
        last_accessed: System.system_time(:millisecond)
      }
      
      assert {:invalid, :low_confidence} = ExplanationCache.validate_cache_entry(entry, 0.7)
      assert {:valid, ^entry} = ExplanationCache.validate_cache_entry(entry, 0.5)
    end
  end
  
  describe "cache expiration" do
    test "expired entries are removed on access", %{cache_pid: cache_pid} do
      # Store with very short TTL
      {:ok, short_ttl_cache} = ExplanationCache.start_link(ttl: 50)  # 50ms
      
      ExplanationCache.put(short_ttl_cache, @sample_request, @sample_result)
      
      # Should initially be a hit
      assert {:hit, _entry} = ExplanationCache.get(short_ttl_cache, @sample_request)
      
      # Wait for expiration
      Process.sleep(100)
      
      # Should now be a miss due to expiration
      assert {:miss, :expired} = ExplanationCache.get(short_ttl_cache, @sample_request)
    end
  end
  
  describe "cache size limits and eviction" do
    test "evicts LRU entries when cache is full", %{cache_pid: cache_pid} do
      # Create cache with size limit of 2
      {:ok, limited_cache} = ExplanationCache.start_link(max_size: 2)
      
      # Add first entry
      request1 = @sample_request
      ExplanationCache.put(limited_cache, request1, @sample_result)
      
      # Add second entry
      request2 = %{@sample_request | content: "def multiply(a, b), do: a * b"}
      ExplanationCache.put(limited_cache, request2, @sample_result)
      
      # Both should be cached
      assert {:hit, _} = ExplanationCache.get(limited_cache, request1)
      assert {:hit, _} = ExplanationCache.get(limited_cache, request2)
      
      # Add third entry (should evict oldest)
      request3 = %{@sample_request | content: "def divide(a, b), do: a / b"}
      ExplanationCache.put(limited_cache, request3, @sample_result)
      
      # First entry should be evicted, others should remain
      assert {:miss, :not_found} = ExplanationCache.get(limited_cache, request1)
      assert {:hit, _} = ExplanationCache.get(limited_cache, request2)
      assert {:hit, _} = ExplanationCache.get(limited_cache, request3)
    end
  end
  
  describe "cache statistics" do
    test "tracks hit and miss counts", %{cache_pid: cache_pid} do
      # Initial stats
      stats = ExplanationCache.stats(cache_pid)
      assert stats.hit_count == 0
      assert stats.miss_count == 0
      assert stats.hit_rate == 0.0
      
      # Cause a miss
      ExplanationCache.get(cache_pid, @sample_request)
      
      stats = ExplanationCache.stats(cache_pid)
      assert stats.miss_count == 1
      assert stats.hit_rate == 0.0
      
      # Store and cause a hit
      ExplanationCache.put(cache_pid, @sample_request, @sample_result)
      ExplanationCache.get(cache_pid, @sample_request)
      
      stats = ExplanationCache.stats(cache_pid)
      assert stats.hit_count == 1
      assert stats.miss_count == 1
      assert stats.hit_rate == 0.5
    end
    
    test "tracks cache size", %{cache_pid: cache_pid} do
      stats = ExplanationCache.stats(cache_pid)
      assert stats.size == 0
      
      ExplanationCache.put(cache_pid, @sample_request, @sample_result)
      
      stats = ExplanationCache.stats(cache_pid)
      assert stats.size == 1
    end
    
    test "tracks eviction count", %{cache_pid: cache_pid} do
      # Create cache with size limit of 1
      {:ok, limited_cache} = ExplanationCache.start_link(max_size: 1)
      
      # Add first entry
      request1 = @sample_request
      ExplanationCache.put(limited_cache, request1, @sample_result)
      
      stats = ExplanationCache.stats(limited_cache)
      assert stats.eviction_count == 0
      
      # Add second entry (should cause eviction)
      request2 = %{@sample_request | content: "different code"}
      ExplanationCache.put(limited_cache, request2, @sample_result)
      
      stats = ExplanationCache.stats(limited_cache)
      assert stats.eviction_count == 1
    end
  end
  
  describe "cache cleanup" do
    test "manually triggered cleanup removes expired entries", %{cache_pid: cache_pid} do
      # Create cache with very short TTL
      {:ok, short_ttl_cache} = ExplanationCache.start_link(ttl: 10)  # 10ms
      
      # Add entry
      ExplanationCache.put(short_ttl_cache, @sample_request, @sample_result)
      
      stats_before = ExplanationCache.stats(short_ttl_cache)
      assert stats_before.size == 1
      
      # Wait for expiration
      Process.sleep(50)
      
      # Trigger cleanup
      ExplanationCache.cleanup(short_ttl_cache)
      
      stats_after = ExplanationCache.stats(short_ttl_cache)
      assert stats_after.size == 0
    end
  end
  
  describe "pattern-based cache clearing" do
    test "clears entries matching specific patterns", %{cache_pid: cache_pid} do
      # Add multiple entries with different patterns
      elixir_request = @sample_request
      js_request = %{@sample_request | language: :javascript, content: "function add() {}"}
      
      ExplanationCache.put(cache_pid, elixir_request, @sample_result)
      ExplanationCache.put(cache_pid, js_request, @sample_result)
      
      # Both should be cached
      assert {:hit, _} = ExplanationCache.get(cache_pid, elixir_request)
      assert {:hit, _} = ExplanationCache.get(cache_pid, js_request)
      
      # Clear only elixir entries
      cleared_count = ExplanationCache.clear_patterns(cache_pid, ["elixir"])
      assert cleared_count == 1
      
      # Elixir entry should be gone, JavaScript should remain
      assert {:miss, :not_found} = ExplanationCache.get(cache_pid, elixir_request)
      assert {:hit, _} = ExplanationCache.get(cache_pid, js_request)
    end
    
    test "handles regex patterns", %{cache_pid: cache_pid} do
      # Add entries
      ExplanationCache.put(cache_pid, @sample_request, @sample_result)
      
      # Clear using regex pattern
      cleared_count = ExplanationCache.clear_patterns(cache_pid, [".*:elixir:.*"])
      assert cleared_count == 1
      
      assert {:miss, :not_found} = ExplanationCache.get(cache_pid, @sample_request)
    end
  end
  
  describe "concurrent access" do
    test "handles concurrent reads and writes safely", %{cache_pid: cache_pid} do
      # Spawn multiple processes doing concurrent operations
      tasks = for i <- 1..10 do
        Task.async(fn ->
          request = %{@sample_request | content: "code #{i}"}
          result = %{@sample_result | explanation: "explanation #{i}"}
          
          ExplanationCache.put(cache_pid, request, result)
          ExplanationCache.get(cache_pid, request)
        end)
      end
      
      # All tasks should complete successfully
      results = Task.await_many(tasks)
      assert length(results) == 10
      
      # All should be cache hits
      Enum.each(results, fn result ->
        assert match?({:hit, _}, result)
      end)
    end
  end
  
  describe "cache initialization" do
    test "starts with custom configuration" do
      config = [
        max_size: 100,
        ttl: :timer.hours(2),
        cleanup_interval: :timer.minutes(30)
      ]
      
      {:ok, cache_pid} = ExplanationCache.start_link(config)
      
      stats = ExplanationCache.stats(cache_pid)
      assert stats.max_size == 100
    end
    
    test "applies default configuration when not specified" do
      {:ok, cache_pid} = ExplanationCache.start_link([])
      
      stats = ExplanationCache.stats(cache_pid)
      assert is_integer(stats.max_size)
      assert stats.max_size > 0
    end
  end
end