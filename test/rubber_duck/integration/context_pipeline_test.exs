defmodule RubberDuck.Integration.ContextPipelineTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.{
    ContextBuilderAgent,
    ShortTermMemoryAgent,
    LongTermMemoryAgent,
    RAGPipelineAgent
  }

  setup do
    # Start test signal bus
    {:ok, _} = start_supervised({SignalBus, name: :test_signal_bus})
    
    # Initialize agents
    {:ok, context_builder} = ContextBuilderAgent.init(%{})
    {:ok, short_term} = ShortTermMemoryAgent.init(%{})
    {:ok, long_term} = LongTermMemoryAgent.init(%{})
    {:ok, rag_pipeline} = RAGPipelineAgent.init(%{})
    
    # Create test memories
    test_memories = create_test_memories(short_term, long_term)
    
    {:ok, 
      context_builder: context_builder,
      short_term: short_term,
      long_term: long_term,
      rag_pipeline: rag_pipeline,
      memories: test_memories
    }
  end

  describe "context aggregation" do
    test "aggregates context from multiple sources", %{context_builder: builder} do
      # Define sources
      sources = [
        %{
          "source_type" => "short_term_memory",
          "query" => "recent interactions",
          "max_items" => 5
        },
        %{
          "source_type" => "long_term_memory", 
          "query" => "user preferences",
          "max_items" => 3
        },
        %{
          "source_type" => "system_state",
          "include" => ["current_task", "active_agents"]
        }
      ]
      
      {:ok, result, _} = ContextBuilderAgent.handle_signal("aggregate_context", %{
        "sources" => sources,
        "max_tokens" => 2000
      }, builder)
      
      assert result["success"] == true
      assert is_list(result["context_items"])
      assert length(result["context_items"]) > 0
      assert result["total_tokens"] <= 2000
      
      # Verify all source types were included
      source_types = result["context_items"] |> Enum.map(& &1["source"]) |> Enum.uniq()
      assert "short_term_memory" in source_types
      assert "long_term_memory" in source_types
      assert "system_state" in source_types
    end

    test "handles source failures gracefully", %{context_builder: builder} do
      sources = [
        %{
          "source_type" => "invalid_source",
          "query" => "test"
        },
        %{
          "source_type" => "short_term_memory",
          "query" => "valid query"
        }
      ]
      
      {:ok, result, _} = ContextBuilderAgent.handle_signal("aggregate_context", %{
        "sources" => sources
      }, builder)
      
      # Should succeed with partial results
      assert result["success"] == true
      assert result["partial_failure"] == true
      assert length(result["failures"]) == 1
      assert Enum.any?(result["context_items"], & &1["source"] == "short_term_memory")
    end

    test "aggregates with priority ordering", %{context_builder: builder} do
      sources = [
        %{
          "source_type" => "short_term_memory",
          "query" => "recent",
          "priority" => 3
        },
        %{
          "source_type" => "long_term_memory",
          "query" => "important",
          "priority" => 1  # Highest priority
        },
        %{
          "source_type" => "system_state",
          "priority" => 2
        }
      ]
      
      {:ok, result, _} = ContextBuilderAgent.handle_signal("aggregate_context", %{
        "sources" => sources,
        "max_tokens" => 500  # Force prioritization
      }, builder)
      
      # Check that higher priority items appear first
      first_items = Enum.take(result["context_items"], 3)
      priorities = Enum.map(first_items, & &1["priority"])
      
      assert priorities == Enum.sort(priorities)  # Should be in priority order
    end
  end

  describe "context optimization" do
    test "optimizes context to fit token limit", %{context_builder: builder} do
      # Create large context that needs optimization
      large_items = Enum.map(1..20, fn i ->
        %{
          "id" => "item_#{i}",
          "content" => String.duplicate("Test content #{i} ", 50),
          "relevance" => :rand.uniform(),
          "priority" => rem(i, 3) + 1
        }
      end)
      
      {:ok, result, _} = ContextBuilderAgent.handle_signal("optimize_context", %{
        "context_items" => large_items,
        "max_tokens" => 1000,
        "strategy" => "relevance_priority"
      }, builder)
      
      assert result["optimized"] == true
      assert result["total_tokens"] <= 1000
      assert length(result["included_items"]) < length(large_items)
      assert length(result["excluded_items"]) > 0
      
      # Verify optimization strategy was applied
      included_scores = result["included_items"] 
        |> Enum.map(& &1["relevance"] * (4 - &1["priority"]))
      
      # Should be sorted by combined score
      assert included_scores == Enum.sort(included_scores, :desc)
    end

    test "applies different optimization strategies", %{context_builder: builder} do
      test_items = create_test_context_items()
      
      strategies = ["relevance_priority", "recency_first", "balanced"]
      
      results = Enum.map(strategies, fn strategy ->
        {:ok, result, _} = ContextBuilderAgent.handle_signal("optimize_context", %{
          "context_items" => test_items,
          "max_tokens" => 500,
          "strategy" => strategy
        }, builder)
        
        {strategy, result["included_items"]}
      end)
      
      # Different strategies should produce different results
      [first | rest] = results
      assert Enum.any?(rest, fn {_, items} -> 
        items != elem(first, 1)
      end)
    end

    test "handles token calculation accurately", %{context_builder: builder} do
      items = [
        %{"content" => "Short text", "metadata" => %{"type" => "test"}},
        %{"content" => String.duplicate("Medium length text ", 20)},
        %{"content" => String.duplicate("Very long text content ", 100)}
      ]
      
      {:ok, result, _} = ContextBuilderAgent.handle_signal("calculate_tokens", %{
        "items" => items
      }, builder)
      
      assert result["token_counts"] |> length() == 3
      assert result["total_tokens"] > 0
      
      # Longer content should have more tokens
      counts = result["token_counts"]
      assert Enum.at(counts, 0) < Enum.at(counts, 1)
      assert Enum.at(counts, 1) < Enum.at(counts, 2)
    end
  end

  describe "streaming context" do
    test "streams large contexts efficiently", %{context_builder: builder} do
      # Create context larger than streaming threshold
      large_context = Enum.map(1..100, fn i ->
        %{
          "id" => "large_#{i}",
          "content" => String.duplicate("Content #{i} ", 20),
          "relevance" => 0.5 + :rand.uniform() * 0.5
        }
      end)
      
      {:ok, stream_result, _} = ContextBuilderAgent.handle_signal("stream_context", %{
        "context_items" => large_context,
        "chunk_size" => 10
      }, builder)
      
      assert stream_result["streaming"] == true
      assert stream_result["total_chunks"] == 10
      
      # Collect streamed chunks
      chunks = collect_stream_chunks(builder, stream_result["stream_id"])
      
      assert length(chunks) == 10
      assert Enum.all?(chunks, & length(&1["items"]) == 10)
      
      # Verify all items were streamed
      all_streamed = Enum.flat_map(chunks, & &1["items"])
      assert length(all_streamed) == 100
    end

    test "handles stream interruption gracefully", %{context_builder: builder} do
      large_context = create_test_context_items(50)
      
      {:ok, stream_result, builder} = ContextBuilderAgent.handle_signal("stream_context", %{
        "context_items" => large_context,
        "chunk_size" => 5
      }, builder)
      
      stream_id = stream_result["stream_id"]
      
      # Get first few chunks
      _chunk1 = get_next_chunk(builder, stream_id)
      _chunk2 = get_next_chunk(builder, stream_id)
      
      # Cancel stream
      {:ok, cancel_result, _} = ContextBuilderAgent.handle_signal("cancel_stream", %{
        "stream_id" => stream_id
      }, builder)
      
      assert cancel_result["cancelled"] == true
      
      # Further chunk requests should fail
      {:error, error, _} = ContextBuilderAgent.handle_signal("get_stream_chunk", %{
        "stream_id" => stream_id
      }, builder)
      
      assert error =~ "cancelled"
    end
  end

  describe "caching and performance" do
    test "caches aggregated contexts", %{context_builder: builder} do
      sources = [
        %{"source_type" => "short_term_memory", "query" => "test query"}
      ]
      
      # First aggregation
      {:ok, result1, builder} = ContextBuilderAgent.handle_signal("aggregate_context", %{
        "sources" => sources,
        "cache_key" => "test_cache_1"
      }, builder)
      
      first_time = result1["processing_time_ms"]
      
      # Second aggregation with same cache key
      {:ok, result2, _} = ContextBuilderAgent.handle_signal("aggregate_context", %{
        "sources" => sources,
        "cache_key" => "test_cache_1"
      }, builder)
      
      assert result2["cache_hit"] == true
      assert result2["processing_time_ms"] < first_time
      assert result2["context_items"] == result1["context_items"]
    end

    test "invalidates cache on source updates", %{context_builder: builder} do
      cache_key = "invalidation_test"
      
      # Cache a context
      {:ok, _, builder} = ContextBuilderAgent.handle_signal("aggregate_context", %{
        "sources" => [%{"source_type" => "short_term_memory"}],
        "cache_key" => cache_key
      }, builder)
      
      # Notify of source update
      {:ok, _, builder} = ContextBuilderAgent.handle_signal("invalidate_cache", %{
        "source_type" => "short_term_memory",
        "reason" => "memory_updated"
      }, builder)
      
      # Next request should miss cache
      {:ok, result, _} = ContextBuilderAgent.handle_signal("aggregate_context", %{
        "sources" => [%{"source_type" => "short_term_memory"}],
        "cache_key" => cache_key
      }, builder)
      
      assert result["cache_hit"] == false
    end

    test "manages cache size limits", %{context_builder: builder} do
      # Fill cache beyond limit
      cache_entries = Enum.map(1..20, fn i ->
        {:ok, _, builder} = ContextBuilderAgent.handle_signal("aggregate_context", %{
          "sources" => [%{"source_type" => "test", "id" => i}],
          "cache_key" => "cache_#{i}"
        }, builder)
        builder
      end)
      
      final_builder = List.last(cache_entries)
      
      # Check cache stats
      {:ok, stats, _} = ContextBuilderAgent.handle_signal("get_cache_stats", %{}, final_builder)
      
      assert stats["cache_size"] <= stats["max_cache_size"]
      assert stats["evictions"] > 0
      assert stats["cache_hit_rate"] >= 0
    end
  end

  describe "integration with RAG pipeline" do
    test "provides context for RAG queries", %{context_builder: builder, rag_pipeline: rag} do
      # Build context
      {:ok, context_result, _} = ContextBuilderAgent.handle_signal("aggregate_context", %{
        "sources" => [
          %{"source_type" => "short_term_memory", "query" => "recent code"},
          %{"source_type" => "long_term_memory", "query" => "patterns"}
        ],
        "purpose" => "code_generation"
      }, builder)
      
      # Use context in RAG pipeline
      {:ok, rag_result, _} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => "Generate a function based on recent patterns",
        "context" => context_result["context_items"],
        "pipeline_config" => %{
          "use_context" => true,
          "max_context_tokens" => 1000
        }
      }, rag)
      
      assert rag_result["success"] == true
      assert rag_result["context_used"] == true
      assert length(rag_result["context_items_used"]) > 0
    end

    test "optimizes context for specific generation tasks", %{context_builder: builder} do
      task_types = ["code_generation", "documentation", "debugging", "refactoring"]
      
      results = Enum.map(task_types, fn task_type ->
        {:ok, result, _} = ContextBuilderAgent.handle_signal("build_task_context", %{
          "task_type" => task_type,
          "query" => "Test query for #{task_type}",
          "constraints" => %{
            "max_tokens" => 1500,
            "include_examples" => true
          }
        }, builder)
        
        {task_type, result}
      end)
      
      # Each task type should produce different context
      contexts = Enum.map(results, fn {_, r} -> r["context_items"] end)
      assert length(Enum.uniq(contexts)) == length(task_types)
      
      # Verify task-specific optimizations
      {_, code_gen} = Enum.find(results, fn {t, _} -> t == "code_generation" end)
      assert Enum.any?(code_gen["context_items"], & &1["type"] == "code_pattern")
      
      {_, docs} = Enum.find(results, fn {t, _} -> t == "documentation" end)
      assert Enum.any?(docs["context_items"], & &1["type"] == "doc_template")
    end
  end

  # Helper functions

  defp create_test_memories(short_term, long_term) do
    # Create short-term memories
    st_memories = Enum.map(1..10, fn i ->
      {:ok, result, _} = ShortTermMemoryAgent.handle_signal("store_memory", %{
        "type" => "interaction",
        "content" => "Short-term memory #{i}",
        "metadata" => %{
          "timestamp" => DateTime.add(DateTime.utc_now(), -i * 60, :second),
          "relevance" => 0.5 + :rand.uniform() * 0.5
        }
      }, short_term)
      result
    end)
    
    # Create long-term memories
    lt_memories = Enum.map(1..10, fn i ->
      {:ok, result, _} = LongTermMemoryAgent.handle_signal("store_memory", %{
        "type" => "knowledge",
        "content" => "Long-term knowledge #{i}",
        "metadata" => %{
          "category" => "pattern",
          "importance" => rem(i, 3) + 1
        }
      }, long_term)
      result
    end)
    
    %{short_term: st_memories, long_term: lt_memories}
  end

  defp create_test_context_items(count \\ 10) do
    Enum.map(1..count, fn i ->
      %{
        "id" => "test_#{i}",
        "content" => "Test content item #{i}",
        "relevance" => :rand.uniform(),
        "priority" => rem(i, 3) + 1,
        "timestamp" => DateTime.add(DateTime.utc_now(), -i * 3600, :second)
      }
    end)
  end

  defp collect_stream_chunks(builder, stream_id) do
    collect_chunks_recursive(builder, stream_id, [])
  end

  defp collect_chunks_recursive(builder, stream_id, acc) do
    case get_next_chunk(builder, stream_id) do
      {:ok, %{"items" => items, "has_more" => false}} ->
        Enum.reverse([%{"items" => items} | acc])
      
      {:ok, %{"items" => items, "has_more" => true}} ->
        collect_chunks_recursive(builder, stream_id, [%{"items" => items} | acc])
      
      {:error, _} ->
        Enum.reverse(acc)
    end
  end

  defp get_next_chunk(builder, stream_id) do
    case ContextBuilderAgent.handle_signal("get_stream_chunk", %{
      "stream_id" => stream_id
    }, builder) do
      {:ok, result, _} -> {:ok, result}
      error -> error
    end
  end
end