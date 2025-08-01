defmodule RubberDuck.Agents.CacheManagementTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.{
    ShortTermMemoryAgent,
    LongTermMemoryAgent,
    ContextBuilderAgent,
    RAGPipelineAgent
  }
  alias RubberDuck.Cache.{Manager, Strategy}

  setup do
    # Start test dependencies
    {:ok, _} = start_supervised({SignalBus, name: :test_signal_bus})
    {:ok, cache_manager} = start_supervised({Manager, name: :test_cache})
    
    # Initialize agents with caching enabled
    {:ok, short_term} = ShortTermMemoryAgent.init(%{
      cache_enabled: true,
      cache_ttl: 300  # 5 minutes
    })
    
    {:ok, long_term} = LongTermMemoryAgent.init(%{
      cache_enabled: true,
      cache_strategy: :lru,
      max_cache_size: 100
    })
    
    {:ok, context_builder} = ContextBuilderAgent.init(%{
      cache_enabled: true,
      cache_ttl: 600
    })
    
    {:ok, rag_pipeline} = RAGPipelineAgent.init(%{
      cache_enabled: true,
      cache_strategies: [:memory, :disk]
    })
    
    {:ok,
      cache_manager: cache_manager,
      short_term: short_term,
      long_term: long_term,
      context_builder: context_builder,
      rag_pipeline: rag_pipeline
    }
  end

  describe "cache strategies" do
    test "LRU eviction strategy", %{long_term: agent} do
      # Fill cache to capacity
      memory_ids = Enum.map(1..100, fn i ->
        {:ok, result, agent} = LongTermMemoryAgent.handle_signal("store_memory", %{
          "type" => "knowledge",
          "content" => "Memory #{i}",
          "cache" => true
        }, agent)
        {result["memory_id"], agent}
      end)
      
      {ids, final_agent} = Enum.unzip(memory_ids)
      final_agent = List.last(final_agent)
      
      # Access some memories to update LRU order
      accessed_ids = Enum.take(ids, 10)
      Enum.each(accessed_ids, fn id ->
        LongTermMemoryAgent.handle_signal("retrieve_memory", %{
          "memory_id" => id
        }, final_agent)
      end)
      
      # Add new memory to trigger eviction
      {:ok, _, final_agent} = LongTermMemoryAgent.handle_signal("store_memory", %{
        "type" => "knowledge",
        "content" => "New memory",
        "cache" => true
      }, final_agent)
      
      # Check cache stats
      {:ok, stats, _} = LongTermMemoryAgent.handle_signal("get_cache_stats", %{}, final_agent)
      
      assert stats["evictions"] > 0
      assert stats["cache_size"] <= 100
      
      # Recently accessed memories should still be cached
      Enum.each(accessed_ids, fn id ->
        {:ok, result, _} = LongTermMemoryAgent.handle_signal("retrieve_memory", %{
          "memory_id" => id
        }, final_agent)
        assert result["cache_hit"] == true
      end)
    end

    test "TTL-based cache expiration", %{short_term: agent} do
      # Store memory with short TTL
      {:ok, result, agent} = ShortTermMemoryAgent.handle_signal("store_memory", %{
        "type" => "interaction",
        "content" => "Temporary memory",
        "cache_ttl" => 1  # 1 second
      }, agent)
      
      memory_id = result["memory_id"]
      
      # Immediate retrieval should hit cache
      {:ok, retrieve1, _} = ShortTermMemoryAgent.handle_signal("retrieve_memory", %{
        "memory_id" => memory_id
      }, agent)
      assert retrieve1["cache_hit"] == true
      
      # Wait for TTL to expire
      Process.sleep(1100)
      
      # Should miss cache after expiration
      {:ok, retrieve2, _} = ShortTermMemoryAgent.handle_signal("retrieve_memory", %{
        "memory_id" => memory_id
      }, agent)
      assert retrieve2["cache_hit"] == false
    end

    test "Adaptive cache strategy", %{rag_pipeline: agent} do
      # Simulate different access patterns
      patterns = [
        # Frequent access pattern
        {"frequent_query", 20, 50},
        # Occasional access pattern  
        {"occasional_query", 5, 200},
        # Rare access pattern
        {"rare_query", 1, 1000}
      ]
      
      results = Enum.map(patterns, fn {query, count, interval} ->
        Enum.map(1..count, fn _ ->
          {:ok, result, _} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
            "query" => query,
            "cache_key" => query
          }, agent)
          Process.sleep(interval)
          result
        end)
      end)
      
      # Check adaptive caching decisions
      {:ok, cache_analysis, _} = RAGPipelineAgent.handle_signal("analyze_cache_patterns", %{}, agent)
      
      assert cache_analysis["frequent_query"]["cache_priority"] == "high"
      assert cache_analysis["occasional_query"]["cache_priority"] == "medium"
      assert cache_analysis["rare_query"]["cache_priority"] == "low"
    end

    test "Multi-tier caching (memory + disk)", %{rag_pipeline: agent} do
      # Create large result that should go to disk cache
      large_content = String.duplicate("Large content ", 10000)
      
      {:ok, result, agent} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => "large query",
        "mock_response" => large_content,
        "cache_key" => "large_result"
      }, agent)
      
      # Check cache placement
      {:ok, cache_info, _} = RAGPipelineAgent.handle_signal("get_cache_info", %{
        "cache_key" => "large_result"
      }, agent)
      
      assert cache_info["tier"] == "disk"
      assert cache_info["size_bytes"] > 100000
      
      # Retrieval should still work
      {:ok, cached_result, _} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => "large query",
        "cache_key" => "large_result"
      }, agent)
      
      assert cached_result["cache_hit"] == true
      assert cached_result["cache_tier"] == "disk"
    end
  end

  describe "cache invalidation" do
    test "invalidates dependent caches on memory update", %{short_term: st_agent, context_builder: cb_agent} do
      # Store memory
      {:ok, memory_result, st_agent} = ShortTermMemoryAgent.handle_signal("store_memory", %{
        "type" => "interaction",
        "content" => "Original content"
      }, st_agent)
      
      memory_id = memory_result["memory_id"]
      
      # Build context using this memory
      {:ok, context_result, cb_agent} = ContextBuilderAgent.handle_signal("aggregate_context", %{
        "sources" => [%{"source_type" => "short_term_memory", "memory_ids" => [memory_id]}],
        "cache_key" => "context_with_memory"
      }, cb_agent)
      
      assert context_result["cache_hit"] == false  # First time
      
      # Retrieve again to confirm caching
      {:ok, cached_context, cb_agent} = ContextBuilderAgent.handle_signal("aggregate_context", %{
        "sources" => [%{"source_type" => "short_term_memory", "memory_ids" => [memory_id]}],
        "cache_key" => "context_with_memory"
      }, cb_agent)
      
      assert cached_context["cache_hit"] == true
      
      # Update the memory
      {:ok, _, st_agent} = ShortTermMemoryAgent.handle_signal("update_memory", %{
        "memory_id" => memory_id,
        "updates" => %{"content" => "Updated content"}
      }, st_agent)
      
      # Context cache should be invalidated
      {:ok, new_context, _} = ContextBuilderAgent.handle_signal("aggregate_context", %{
        "sources" => [%{"source_type" => "short_term_memory", "memory_ids" => [memory_id]}],
        "cache_key" => "context_with_memory"
      }, cb_agent)
      
      assert new_context["cache_hit"] == false
      assert new_context["context_items"] != context_result["context_items"]
    end

    test "cascading cache invalidation", %{short_term: st, long_term: lt, context_builder: cb} do
      # Create dependency chain: memory -> context -> rag result
      {:ok, mem_result, _} = ShortTermMemoryAgent.handle_signal("store_memory", %{
        "type" => "knowledge",
        "content" => "Base knowledge"
      }, st)
      
      memory_id = mem_result["memory_id"]
      
      # Promote to long-term
      {:ok, _, _} = LongTermMemoryAgent.handle_signal("store_memory", %{
        "source_memory_id" => memory_id,
        "type" => "knowledge"
      }, lt)
      
      # Build context
      {:ok, _, _} = ContextBuilderAgent.handle_signal("aggregate_context", %{
        "sources" => [
          %{"source_type" => "short_term_memory", "memory_ids" => [memory_id]},
          %{"source_type" => "long_term_memory", "related_to" => memory_id}
        ],
        "cache_key" => "dependent_context"
      }, cb)
      
      # Invalidate source memory
      {:ok, _, _} = ShortTermMemoryAgent.handle_signal("invalidate_cache", %{
        "memory_id" => memory_id,
        "cascade" => true
      }, st)
      
      # Check invalidation propagation
      {:ok, cache_status, _} = ContextBuilderAgent.handle_signal("check_cache_status", %{
        "cache_key" => "dependent_context"
      }, cb)
      
      assert cache_status["valid"] == false
      assert cache_status["invalidation_reason"] =~ "dependency"
    end

    test "selective cache invalidation", %{context_builder: agent} do
      # Create multiple cached contexts
      contexts = Enum.map(1..5, fn i ->
        {:ok, result, agent} = ContextBuilderAgent.handle_signal("aggregate_context", %{
          "sources" => [%{"source_type" => "test", "category" => rem(i, 2)}],
          "cache_key" => "context_#{i}"
        }, agent)
        {"context_#{i}", result, agent}
      end)
      
      {_, _, final_agent} = List.last(contexts)
      
      # Invalidate by pattern
      {:ok, invalidation_result, _} = ContextBuilderAgent.handle_signal("invalidate_cache_pattern", %{
        "pattern" => "context_[135]",  # Odd numbered contexts
        "reason" => "test invalidation"
      }, final_agent)
      
      assert invalidation_result["invalidated_count"] == 3
      
      # Even numbered contexts should still be cached
      {:ok, check2, _} = ContextBuilderAgent.handle_signal("check_cache_status", %{
        "cache_key" => "context_2"
      }, final_agent)
      assert check2["valid"] == true
      
      {:ok, check4, _} = ContextBuilderAgent.handle_signal("check_cache_status", %{
        "cache_key" => "context_4"
      }, final_agent)
      assert check4["valid"] == true
    end
  end

  describe "cache performance and monitoring" do
    test "tracks cache hit rates", %{short_term: agent} do
      # Create test data
      memory_ids = Enum.map(1..10, fn i ->
        {:ok, result, agent} = ShortTermMemoryAgent.handle_signal("store_memory", %{
          "type" => "test",
          "content" => "Memory #{i}"
        }, agent)
        {result["memory_id"], agent}
      end)
      
      {ids, agents} = Enum.unzip(memory_ids)
      final_agent = List.last(agents)
      
      # Access pattern: 70% hit rate
      access_pattern = Enum.flat_map(1..100, fn i ->
        if rem(i, 10) < 7 do
          [Enum.random(Enum.take(ids, 3))]  # Hit - access first 3 repeatedly
        else
          [Enum.random(ids)]  # Miss - access any
        end
      end)
      
      # Execute access pattern
      Enum.each(access_pattern, fn id ->
        ShortTermMemoryAgent.handle_signal("retrieve_memory", %{
          "memory_id" => id
        }, final_agent)
      end)
      
      # Check hit rate
      {:ok, stats, _} = ShortTermMemoryAgent.handle_signal("get_cache_stats", %{}, final_agent)
      
      assert stats["hit_rate"] >= 0.6 and stats["hit_rate"] <= 0.8
      assert stats["total_requests"] >= 100
    end

    test "monitors cache memory usage", %{long_term: agent} do
      # Store memories of different sizes
      memories = Enum.map(1..20, fn i ->
        size_multiplier = rem(i, 5) + 1
        {:ok, _, agent} = LongTermMemoryAgent.handle_signal("store_memory", %{
          "type" => "knowledge",
          "content" => String.duplicate("Content ", 100 * size_multiplier),
          "embeddings" => Enum.map(1..768, fn _ -> :rand.uniform() end)  # Simulate embeddings
        }, agent)
        agent
      end)
      
      final_agent = List.last(memories)
      
      # Get memory usage stats
      {:ok, mem_stats, _} = LongTermMemoryAgent.handle_signal("get_memory_stats", %{}, final_agent)
      
      assert mem_stats["cache_memory_bytes"] > 0
      assert mem_stats["cache_memory_mb"] > 0
      assert mem_stats["memory_pressure"] in ["low", "medium", "high"]
      
      # Check if memory limit is respected
      assert mem_stats["cache_memory_bytes"] <= mem_stats["max_memory_bytes"]
    end

    test "provides cache performance recommendations", %{rag_pipeline: agent} do
      # Simulate various usage patterns
      patterns = [
        # High miss rate pattern
        {:random_queries, Enum.map(1..50, fn i -> "unique_query_#{i}" end)},
        # High hit rate pattern
        {:repeated_queries, List.duplicate("common_query", 50)},
        # Mixed pattern
        {:mixed_queries, Enum.flat_map(1..10, fn i -> 
          ["query_#{rem(i, 3)}", "query_#{i}"] 
        end)}
      ]
      
      Enum.each(patterns, fn {_type, queries} ->
        Enum.each(queries, fn query ->
          RAGPipelineAgent.handle_signal("execute_pipeline", %{
            "query" => query,
            "cache_key" => query
          }, agent)
        end)
      end)
      
      # Get performance analysis
      {:ok, analysis, _} = RAGPipelineAgent.handle_signal("analyze_cache_performance", %{}, agent)
      
      assert is_list(analysis["recommendations"])
      assert length(analysis["recommendations"]) > 0
      
      # Should recommend different strategies based on patterns
      recommendations = analysis["recommendations"]
      assert Enum.any?(recommendations, & &1["type"] == "increase_cache_size")
      assert Enum.any?(recommendations, & &1["type"] == "adjust_ttl")
    end

    test "detects cache thrashing", %{short_term: agent} do
      # Create more memories than cache can hold
      memory_count = 150
      cache_size = 100
      
      agent = put_in(agent.config.max_cache_entries, cache_size)
      
      # Rapidly access all memories in cycle
      memory_ids = Enum.map(1..memory_count, fn i ->
        {:ok, result, agent} = ShortTermMemoryAgent.handle_signal("store_memory", %{
          "type" => "test",
          "content" => "Memory #{i}"
        }, agent)
        {result["memory_id"], agent}
      end)
      
      {ids, agents} = Enum.unzip(memory_ids)
      final_agent = List.last(agents)
      
      # Access in rotating pattern to cause thrashing
      Enum.each(1..300, fn i ->
        id = Enum.at(ids, rem(i, memory_count))
        ShortTermMemoryAgent.handle_signal("retrieve_memory", %{
          "memory_id" => id
        }, final_agent)
      end)
      
      # Check for thrashing detection
      {:ok, health, _} = ShortTermMemoryAgent.handle_signal("check_cache_health", %{}, final_agent)
      
      assert health["thrashing_detected"] == true
      assert health["recommendation"] =~ "increase cache size"
    end
  end

  describe "cache warming and preloading" do
    test "warms cache on startup", %{long_term: agent} do
      # Define warmup configuration
      warmup_config = %{
        "categories" => ["critical_knowledge", "frequent_patterns"],
        "max_items" => 50,
        "priority" => "high"
      }
      
      # Trigger cache warming
      {:ok, warmup_result, agent} = LongTermMemoryAgent.handle_signal("warm_cache", warmup_config, agent)
      
      assert warmup_result["warmed_count"] > 0
      assert warmup_result["duration_ms"] > 0
      
      # Verify warmed items are cached
      {:ok, stats, _} = LongTermMemoryAgent.handle_signal("get_cache_stats", %{}, agent)
      assert stats["cache_size"] >= warmup_result["warmed_count"]
    end

    test "predictive cache preloading", %{context_builder: agent} do
      # Simulate access pattern
      sequence = ["context_A", "context_B", "context_C", "context_A", "context_B"]
      
      Enum.each(sequence, fn context_key ->
        ContextBuilderAgent.handle_signal("aggregate_context", %{
          "sources" => [%{"source_type" => "test"}],
          "cache_key" => context_key
        }, agent)
        Process.sleep(100)
      end)
      
      # Train prediction model
      {:ok, _, agent} = ContextBuilderAgent.handle_signal("train_cache_predictor", %{}, agent)
      
      # Access context_A again - should trigger preloading of B
      {:ok, _, agent} = ContextBuilderAgent.handle_signal("aggregate_context", %{
        "sources" => [%{"source_type" => "test"}],
        "cache_key" => "context_A"
      }, agent)
      
      # Check if B was preloaded
      {:ok, preload_status, _} = ContextBuilderAgent.handle_signal("check_preload_status", %{
        "cache_key" => "context_B"
      }, agent)
      
      assert preload_status["preloaded"] == true
      assert preload_status["prediction_confidence"] > 0.7
    end

    test "adaptive cache preloading based on time patterns", %{short_term: agent} do
      # Simulate time-based access pattern (e.g., daily reports)
      now = DateTime.utc_now()
      
      # Historical pattern: access at 9 AM daily
      historical_accesses = Enum.map(1..7, fn days_ago ->
        timestamp = now
          |> DateTime.add(-days_ago * 24 * 3600, :second)
          |> DateTime.truncate(:second)
          |> Map.put(:hour, 9)
          |> Map.put(:minute, 0)
          |> Map.put(:second, 0)
        
        {:ok, result, agent} = ShortTermMemoryAgent.handle_signal("store_memory", %{
          "type" => "daily_report",
          "content" => "Report for #{Date.to_string(DateTime.to_date(timestamp))}",
          "accessed_at" => timestamp
        }, agent)
        
        {result["memory_id"], agent}
      end)
      
      {_, agents} = Enum.unzip(historical_accesses)
      final_agent = List.last(agents)
      
      # Configure time-based preloading
      {:ok, _, final_agent} = ShortTermMemoryAgent.handle_signal("configure_time_preloading", %{
        "enabled" => true,
        "lookahead_minutes" => 30
      }, final_agent)
      
      # Simulate time close to 9 AM
      current_time = Map.put(now, :hour, 8) |> Map.put(:minute, 45)
      
      {:ok, preload_result, _} = ShortTermMemoryAgent.handle_signal("check_time_preloads", %{
        "current_time" => current_time
      }, final_agent)
      
      assert preload_result["scheduled_preloads"] > 0
      assert Enum.any?(preload_result["preload_types"], & &1 == "daily_report")
    end
  end
end