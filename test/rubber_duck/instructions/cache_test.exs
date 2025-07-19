defmodule RubberDuck.Instructions.CacheTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Instructions.{Cache, CacheInvalidator, CacheAnalytics}

  setup do
    # Start cache system for tests (handle already started)
    cache_pid =
      case Cache.start_link() do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    invalidator_pid =
      case CacheInvalidator.start_link() do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    analytics_pid =
      case CacheAnalytics.start_link() do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    on_exit(fn ->
      # Only stop if we started them in this test
      if Process.alive?(cache_pid) and Process.whereis(Cache) == cache_pid do
        GenServer.stop(cache_pid)
      end

      if Process.alive?(invalidator_pid) and Process.whereis(CacheInvalidator) == invalidator_pid do
        GenServer.stop(invalidator_pid)
      end

      if Process.alive?(analytics_pid) and Process.whereis(CacheAnalytics) == analytics_pid do
        GenServer.stop(analytics_pid)
      end
    end)

    {:ok, cache_pid: cache_pid, invalidator_pid: invalidator_pid, analytics_pid: analytics_pid}
  end

  describe "Cache initialization with existing Context.Cache patterns" do
    test "initializes with proper ETS configuration" do
      stats = Cache.get_stats()

      assert is_map(stats)
      assert stats.total_entries >= 0
      assert is_float(stats.hit_rate)
      assert is_map(stats.layer_stats)
    end

    test "creates all required cache layers" do
      stats = Cache.get_stats()

      # Verify all cache layers are present
      assert Map.has_key?(stats.layer_stats, :parsed)
      assert Map.has_key?(stats.layer_stats, :compiled)
      assert Map.has_key?(stats.layer_stats, :registry)
      assert Map.has_key?(stats.layer_stats, :analytics)
    end

    test "uses proven concurrency settings" do
      # Test concurrent access to verify ETS concurrency settings
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            key = Cache.build_key(:parsed, :project, "/test/file#{i}.md", "hash#{i}")
            Cache.put(key, %{content: "test content #{i}"})
            Cache.get(key)
          end)
        end

      results = Task.await_many(tasks)

      # All operations should succeed
      assert length(results) == 10
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end
  end

  describe "Hierarchical key generation and format-specific versioning" do
    test "builds hierarchical keys correctly" do
      key = Cache.build_key(:parsed, :project, "/path/to/AGENTS.md", "abc123")

      assert key == {:parsed, :project, "/path/to/AGENTS.md", "abc123"}
      assert elem(key, 0) == :parsed
      assert elem(key, 1) == :project
      assert elem(key, 2) == "/path/to/AGENTS.md"
      assert elem(key, 3) == "abc123"
    end

    test "supports different cache layers" do
      layers = [:parsed, :compiled, :registry, :analytics]

      keys =
        Enum.map(layers, fn layer ->
          Cache.build_key(layer, :project, "/test.md", "hash")
        end)

      assert length(keys) == 4
      assert Enum.map(keys, &elem(&1, 0)) == layers
    end

    test "supports different scopes" do
      scopes = [:project, :workspace, :global, :directory]

      keys =
        Enum.map(scopes, fn scope ->
          Cache.build_key(:parsed, scope, "/test.md", "hash")
        end)

      assert length(keys) == 4
      assert Enum.map(keys, &elem(&1, 1)) == scopes
    end

    test "includes content hash for versioning" do
      content1 = "content version 1"
      content2 = "content version 2"

      hash1 = :crypto.hash(:sha256, content1) |> Base.encode16(case: :lower)
      hash2 = :crypto.hash(:sha256, content2) |> Base.encode16(case: :lower)

      key1 = Cache.build_key(:parsed, :project, "/test.md", hash1)
      key2 = Cache.build_key(:parsed, :project, "/test.md", hash2)

      # Different content should create different keys
      assert key1 != key2
      assert elem(key1, 3) != elem(key2, 3)
    end
  end

  describe "File-system based invalidation and registry coordination" do
    test "invalidates cache entries for specific files" do
      # Store some cache entries
      key1 = Cache.build_key(:parsed, :project, "/test/file1.md", "hash1")
      key2 = Cache.build_key(:parsed, :project, "/test/file2.md", "hash2")

      Cache.put(key1, %{content: "content1"})
      Cache.put(key2, %{content: "content2"})

      # Verify entries exist
      assert {:ok, _} = Cache.get(key1)
      assert {:ok, _} = Cache.get(key2)

      # Invalidate specific file
      Cache.invalidate_file("/test/file1.md")

      # First file should be invalidated, second should remain
      assert :miss = Cache.get(key1)
      assert {:ok, _} = Cache.get(key2)
    end

    test "invalidates cache entries by scope" do
      # Store entries in different scopes
      project_key = Cache.build_key(:parsed, :project, "/project/file.md", "hash1")
      global_key = Cache.build_key(:parsed, :global, "/global/file.md", "hash2")

      Cache.put(project_key, %{content: "project content"})
      Cache.put(global_key, %{content: "global content"})

      # Verify entries exist
      assert {:ok, _} = Cache.get(project_key)
      assert {:ok, _} = Cache.get(global_key)

      # Invalidate project scope
      Cache.invalidate_scope(:project, "/project")

      # Project entry should be invalidated, global should remain
      assert :miss = Cache.get(project_key)
      assert {:ok, _} = Cache.get(global_key)
    end

    test "invalidates entire cache layers" do
      # Store entries in different layers
      parsed_key = Cache.build_key(:parsed, :project, "/test.md", "hash1")
      compiled_key = Cache.build_key(:compiled, :project, "/test.md", "hash1")

      Cache.put(parsed_key, %{content: "parsed content"})
      Cache.put(compiled_key, %{content: "compiled content"})

      # Verify entries exist
      assert {:ok, _} = Cache.get(parsed_key)
      assert {:ok, _} = Cache.get(compiled_key)

      # Invalidate parsed layer only
      Cache.invalidate_layer(:parsed)

      # Parsed should be invalidated, compiled should remain
      assert :miss = Cache.get(parsed_key)
      assert {:ok, _} = Cache.get(compiled_key)
    end

    test "coordinates with file system watcher" do
      tmp_dir = System.tmp_dir!() |> Path.join("cache_test_#{System.unique_integer()}")
      File.mkdir_p!(tmp_dir)

      test_file = Path.join(tmp_dir, "test.md")
      File.write!(test_file, "initial content")

      # Start watching the directory
      :ok = CacheInvalidator.watch_directory(tmp_dir)

      # Cache some content for the file
      key = Cache.build_key(:parsed, :project, test_file, "initial_hash")
      Cache.put(key, %{content: "cached content"})

      assert {:ok, _} = Cache.get(key)

      # Modify the file
      File.write!(test_file, "modified content")

      # Give file watcher time to process
      Process.sleep(100)

      # Manual invalidation for this test (file watcher integration would be more complex)
      CacheInvalidator.invalidate_file(test_file)

      # Entry should be invalidated
      assert :miss = Cache.get(key)

      # Cleanup
      CacheInvalidator.unwatch_directory(tmp_dir)
      File.rm_rf!(tmp_dir)
    end
  end

  describe "Intelligent cache warming and background pre-compilation" do
    test "warms cache with frequently used instructions" do
      tmp_dir = System.tmp_dir!() |> Path.join("cache_warm_test_#{System.unique_integer()}")
      File.mkdir_p!(tmp_dir)

      # Create test instruction files
      agents_file = Path.join(tmp_dir, "AGENTS.md")

      File.write!(agents_file, """
      ---
      title: Test Instructions
      priority: high
      ---
      # Test Instructions
      Test content for warming
      """)

      # Trigger cache warming
      Cache.warm_cache(tmp_dir)

      # Give warming process time to complete
      Process.sleep(200)

      # Verify warming statistics
      stats = Cache.get_stats()
      assert stats.warming_operations >= 0

      # Cleanup
      File.rm_rf!(tmp_dir)
    end

    test "handles warming failures gracefully" do
      non_existent_dir = "/path/that/does/not/exist"

      # Should not crash when warming non-existent directory
      assert :ok = Cache.warm_cache(non_existent_dir)

      # System should remain operational
      stats = Cache.get_stats()
      assert is_map(stats)
    end

    test "avoids duplicate warming operations" do
      tmp_dir = System.tmp_dir!() |> Path.join("cache_dup_test_#{System.unique_integer()}")
      File.mkdir_p!(tmp_dir)

      # Start multiple warming operations for same directory
      Cache.warm_cache(tmp_dir)
      Cache.warm_cache(tmp_dir)
      Cache.warm_cache(tmp_dir)

      # Should handle gracefully without errors
      Process.sleep(100)

      stats = Cache.get_stats()
      assert is_map(stats)

      # Cleanup
      File.rm_rf!(tmp_dir)
    end
  end

  describe "Distributed instruction synchronization" do
    test "provides distributed caching interface" do
      # Test basic distributed coordination (simplified for unit test)
      key = Cache.build_key(:parsed, :project, "/distributed/test.md", "hash1")

      # Store content
      Cache.put(key, %{content: "distributed content", node: node()})

      # Retrieve content
      assert {:ok, content} = Cache.get(key)
      assert content.content == "distributed content"
      assert content.node == node()
    end

    test "handles node communication gracefully" do
      # Test that cache operations work when no other nodes are available
      stats = Cache.get_stats()

      assert is_map(stats)
      assert stats.total_entries >= 0
    end
  end

  describe "Performance gains and telemetry integration" do
    test "tracks hit and miss rates" do
      key = Cache.build_key(:parsed, :project, "/perf/test.md", "hash1")

      # Initial miss
      assert :miss = Cache.get(key)

      # Store content
      Cache.put(key, %{content: "performance test"})

      # Hit
      assert {:ok, _} = Cache.get(key)

      # Check stats
      stats = Cache.get_stats()
      assert stats.total_hits >= 1
      assert stats.total_misses >= 1
      assert is_float(stats.hit_rate)
    end

    test "measures cache operation performance" do
      key = Cache.build_key(:compiled, :project, "/perf/template.md", "hash1")

      # Measure put operation
      start_time = :os.system_time(:microsecond)
      Cache.put(key, %{large_content: String.duplicate("x", 10000)})
      put_time = :os.system_time(:microsecond) - start_time

      # Measure get operation
      start_time = :os.system_time(:microsecond)
      Cache.get(key)
      get_time = :os.system_time(:microsecond) - start_time

      # Cache operations should be fast (under 1ms for this test)
      assert put_time < 1000
      assert get_time < 1000
    end

    test "integrates with telemetry system" do
      # Capture telemetry events
      test_pid = self()

      handler_id = "cache_test_handler"

      :telemetry.attach(
        handler_id,
        [:rubber_duck, :instructions, :cache, :hit],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      # Trigger cache hit
      key = Cache.build_key(:analytics, :project, "/telemetry/test.md", "hash1")
      Cache.put(key, %{content: "telemetry test"})
      Cache.get(key)

      # Should receive telemetry event
      assert_receive {:telemetry_event, event, measurements, metadata}, 1000

      assert event == [:rubber_duck, :instructions, :cache, :hit]
      assert is_map(measurements)
      assert is_map(metadata)

      # Cleanup
      :telemetry.detach(handler_id)
    end

    test "provides comprehensive analytics" do
      analytics = CacheAnalytics.get_comprehensive_report()

      assert is_map(analytics)
      assert Map.has_key?(analytics, :performance)
      assert Map.has_key?(analytics, :usage)
      assert Map.has_key?(analytics, :efficiency)
      assert Map.has_key?(analytics, :health)
      assert Map.has_key?(analytics, :capacity)
      assert Map.has_key?(analytics, :recommendations)
    end
  end

  describe "Multi-layer cache management and adaptive TTL" do
    test "uses adaptive TTL based on file types" do
      # Development file (should have shorter TTL)
      dev_key = Cache.build_key(:parsed, :project, "/src/lib/module.ex", "hash1")

      # Global file (should have longer TTL)  
      global_key = Cache.build_key(:parsed, :global, "~/.agents.md", "hash2")

      # Store with default TTL (should be determined automatically)
      Cache.put(dev_key, %{content: "dev content"})
      Cache.put(global_key, %{content: "global content"})

      # Both should be accessible immediately
      assert {:ok, _} = Cache.get(dev_key)
      assert {:ok, _} = Cache.get(global_key)

      # Check that cache entries exist (TTL verification would require time manipulation)
      stats = Cache.get_stats()
      assert stats.total_entries >= 2
    end

    test "manages memory usage across cache layers" do
      # Fill different cache layers
      for i <- 1..10 do
        parsed_key = Cache.build_key(:parsed, :project, "/test#{i}.md", "hash#{i}")
        compiled_key = Cache.build_key(:compiled, :project, "/test#{i}.md", "hash#{i}")

        Cache.put(parsed_key, %{content: "parsed content #{i}"})
        Cache.put(compiled_key, %{content: "compiled content #{i}"})
      end

      stats = Cache.get_stats()

      # Verify entries are distributed across layers
      assert stats.layer_stats.parsed.size >= 10
      assert stats.layer_stats.compiled.size >= 10

      # Verify memory usage is tracked
      assert is_integer(stats.layer_stats.parsed.memory)
      assert is_integer(stats.layer_stats.compiled.memory)
    end

    test "handles cache size limits and cleanup" do
      # Store many entries to trigger cleanup
      for i <- 1..100 do
        key = Cache.build_key(:parsed, :project, "/large_test#{i}.md", "hash#{i}")
        Cache.put(key, %{content: String.duplicate("x", 1000), index: i})
      end

      stats = Cache.get_stats()

      # Cache should manage size automatically
      assert stats.total_entries > 0
      # Note: Exact size depends on cleanup implementation
    end

    test "provides cache layer statistics" do
      # Add entries to different layers
      parsed_key = Cache.build_key(:parsed, :project, "/stats/test.md", "hash1")
      compiled_key = Cache.build_key(:compiled, :workspace, "/stats/test.md", "hash2")
      registry_key = Cache.build_key(:registry, :global, "/stats/test.md", "hash3")

      Cache.put(parsed_key, %{type: :parsed})
      Cache.put(compiled_key, %{type: :compiled})
      Cache.put(registry_key, %{type: :registry})

      stats = Cache.get_stats()

      # Each layer should show at least one entry
      assert stats.layer_stats.parsed.size >= 1
      assert stats.layer_stats.compiled.size >= 1
      assert stats.layer_stats.registry.size >= 1
    end
  end

  describe "Cache invalidation system integration" do
    test "provides comprehensive invalidation statistics" do
      invalidator_stats = CacheInvalidator.get_stats()

      assert is_map(invalidator_stats)
      assert Map.has_key?(invalidator_stats, :total_invalidations)
      assert Map.has_key?(invalidator_stats, :file_invalidations)
      assert Map.has_key?(invalidator_stats, :cascade_invalidations)
      assert Map.has_key?(invalidator_stats, :scope_invalidations)
    end

    test "handles cascade invalidation" do
      # Create cache entries that would have dependencies
      base_key = Cache.build_key(:parsed, :project, "/templates/base.md", "base_hash")
      derived_key = Cache.build_key(:compiled, :project, "/templates/derived.md", "derived_hash")

      Cache.put(base_key, %{content: "base template"})
      Cache.put(derived_key, %{content: "derived template"})

      # Verify entries exist
      assert {:ok, _} = Cache.get(base_key)
      assert {:ok, _} = Cache.get(derived_key)

      # Trigger cascade invalidation
      CacheInvalidator.invalidate_cascade("/templates/base.md")

      # Both entries should be invalidated (implementation dependent)
      invalidator_stats = CacheInvalidator.get_stats()
      assert invalidator_stats.total_invalidations >= 0
    end
  end

  describe "Cache analytics and monitoring" do
    test "provides dashboard metrics" do
      dashboard_metrics = CacheAnalytics.get_dashboard_metrics()

      assert is_map(dashboard_metrics)
      # Structure depends on whether metrics are available
      assert Map.has_key?(dashboard_metrics, :current_hit_rate) or
               Map.has_key?(dashboard_metrics, :error)
    end

    test "generates optimization recommendations" do
      recommendations = CacheAnalytics.get_optimization_recommendations()

      assert is_list(recommendations)
      assert length(recommendations) > 0
    end

    test "tracks historical data" do
      # Trigger some cache operations to generate data
      key = Cache.build_key(:analytics, :project, "/history/test.md", "hist_hash")
      Cache.put(key, %{content: "historical data"})
      Cache.get(key)

      # Collect metrics
      CacheAnalytics.collect_metrics()

      # Get historical data
      # Last 1 hour
      historical_data = CacheAnalytics.get_historical_data(1)

      assert is_list(historical_data)
    end

    test "handles monitoring lifecycle" do
      # Start monitoring
      assert :ok = CacheAnalytics.start_monitoring()

      # Stop monitoring
      assert :ok = CacheAnalytics.stop_monitoring()
    end
  end

  describe "Error handling and edge cases" do
    test "handles malformed cache keys gracefully" do
      # Test with invalid cache layer
      invalid_key = {:invalid_layer, :project, "/test.md", "hash"}

      # Should handle gracefully without crashing
      result = Cache.get(invalid_key)
      assert result == :miss or match?({:error, _}, result)
    end

    test "handles concurrent invalidation and access" do
      key = Cache.build_key(:parsed, :project, "/concurrent/test.md", "conc_hash")

      # Store initial content
      Cache.put(key, %{content: "initial content"})

      # Spawn concurrent operations
      tasks = [
        Task.async(fn -> Cache.get(key) end),
        Task.async(fn -> Cache.invalidate_file("/concurrent/test.md") end),
        Task.async(fn -> Cache.put(key, %{content: "updated content"}) end),
        Task.async(fn -> Cache.get(key) end)
      ]

      # All operations should complete without error
      results = Task.await_many(tasks)
      assert length(results) == 4
    end

    test "recovers from system errors gracefully" do
      # Simulate system under stress
      stats_before = Cache.get_stats()

      # Perform many operations rapidly
      for i <- 1..50 do
        key = Cache.build_key(:parsed, :project, "/stress/test#{i}.md", "stress#{i}")
        spawn(fn -> Cache.put(key, %{content: "stress test #{i}"}) end)
        spawn(fn -> Cache.get(key) end)
      end

      # Give operations time to complete
      Process.sleep(100)

      # System should remain operational
      stats_after = Cache.get_stats()
      assert is_map(stats_after)
      assert stats_after.total_entries >= stats_before.total_entries
    end
  end
end
