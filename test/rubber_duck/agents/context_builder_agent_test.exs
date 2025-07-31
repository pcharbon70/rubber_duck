defmodule RubberDuck.Agents.ContextBuilderAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.ContextBuilderAgent
  alias RubberDuck.Context.{ContextEntry, ContextSource, ContextRequest}

  describe "ContextBuilderAgent initialization" do
    test "initializes with default configuration" do
      {:ok, agent} = ContextBuilderAgent.init(%{})
      
      assert Map.has_key?(agent.sources, "memory_source")
      assert Map.has_key?(agent.sources, "code_source")
      assert agent.cache == %{}
      assert agent.active_builds == %{}
      assert agent.priorities.relevance_weight == 0.4
      assert agent.priorities.recency_weight == 0.3
      assert agent.priorities.importance_weight == 0.3
      assert agent.config.max_cache_size == 100
      assert agent.config.default_max_tokens == 4000
    end

    test "initializes metrics correctly" do
      {:ok, agent} = ContextBuilderAgent.init(%{})
      
      assert agent.metrics.builds_completed == 0
      assert agent.metrics.avg_build_time_ms == 0.0
      assert agent.metrics.cache_hits == 0
      assert agent.metrics.cache_misses == 0
    end
  end

  describe "build_context signal" do
    setup do
      {:ok, agent} = ContextBuilderAgent.init(%{})
      {:ok, agent: agent}
    end

    test "builds new context when not cached", %{agent: agent} do
      data = %{
        "request_id" => "test_req_1",
        "purpose" => "code_generation",
        "max_tokens" => 2000,
        "required_sources" => [],
        "filters" => %{},
        "preferences" => %{"language" => "elixir"}
      }
      
      {:ok, context, updated_agent} = ContextBuilderAgent.handle_signal("build_context", data, agent)
      
      assert context["request_id"] == "test_req_1"
      assert context["purpose"] == "code_generation"
      assert is_list(context["entries"])
      assert Map.has_key?(context["metadata"], "total_entries")
      assert updated_agent.metrics.cache_misses == 1
      assert updated_agent.metrics.builds_completed == 1
    end

    test "returns cached context when available", %{agent: agent} do
      # Pre-populate cache
      cached_context = %{
        "request_id" => "cached_req",
        "purpose" => "general",
        "entries" => [],
        "timestamp" => DateTime.utc_now()
      }
      
      agent = put_in(agent.cache["cached_req"], cached_context)
      
      data = %{"request_id" => "cached_req"}
      
      {:ok, context, updated_agent} = ContextBuilderAgent.handle_signal("build_context", data, agent)
      
      assert context == cached_context
      assert updated_agent.metrics.cache_hits == 1
      assert updated_agent.metrics.cache_misses == 0
    end

    test "respects max_tokens limit", %{agent: agent} do
      data = %{
        "purpose" => "general",
        "max_tokens" => 100  # Very small limit
      }
      
      {:ok, context, _} = ContextBuilderAgent.handle_signal("build_context", data, agent)
      
      total_tokens = Enum.sum(Enum.map(context["entries"], & &1.size_tokens))
      assert total_tokens <= 100
    end
  end

  describe "update_context signal" do
    setup do
      {:ok, agent} = ContextBuilderAgent.init(%{})
      
      # Add a context to cache
      context = %{
        "request_id" => "update_test",
        "entries" => [],
        "metadata" => %{"version" => 1}
      }
      
      agent = put_in(agent.cache["update_test"], context)
      
      {:ok, agent: agent}
    end

    test "updates existing context", %{agent: agent} do
      data = %{
        "request_id" => "update_test",
        "updates" => %{
          "metadata" => %{"version" => 2, "updated" => true}
        }
      }
      
      {:ok, updated_context, _} = ContextBuilderAgent.handle_signal("update_context", data, agent)
      
      assert updated_context["metadata"]["version"] == 2
      assert updated_context["metadata"]["updated"] == true
    end

    test "returns error for non-existent context", %{agent: agent} do
      data = %{
        "request_id" => "non_existent",
        "updates" => %{}
      }
      
      {:error, message, _} = ContextBuilderAgent.handle_signal("update_context", data, agent)
      
      assert message == "Context not found"
    end
  end

  describe "source management signals" do
    setup do
      {:ok, agent} = ContextBuilderAgent.init(%{})
      {:ok, agent: agent}
    end

    test "registers new source", %{agent: agent} do
      data = %{
        "id" => "test_source",
        "name" => "Test Source",
        "type" => "custom",
        "weight" => 0.8,
        "config" => %{"test" => true}
      }
      
      {:ok, result, updated_agent} = ContextBuilderAgent.handle_signal("register_source", data, agent)
      
      assert result["source_id"] == "test_source"
      assert Map.has_key?(updated_agent.sources, "test_source")
      
      source = updated_agent.sources["test_source"]
      assert source.name == "Test Source"
      assert source.type == :custom
      assert source.weight == 0.8
    end

    test "rejects invalid source type", %{agent: agent} do
      data = %{
        "name" => "Invalid Source",
        "type" => "invalid_type"
      }
      
      {:error, message, _} = ContextBuilderAgent.handle_signal("register_source", data, agent)
      
      assert message =~ "Invalid source type"
    end

    test "updates existing source", %{agent: agent} do
      data = %{
        "source_id" => "memory_source",
        "updates" => %{
          "weight" => 0.5,
          "config" => %{"updated" => true}
        }
      }
      
      {:ok, result, updated_agent} = ContextBuilderAgent.handle_signal("update_source", data, agent)
      
      assert result["source"].weight == 0.5
      assert result["source"].config["updated"] == true
    end

    test "removes source", %{agent: agent} do
      {:ok, _, _} = ContextBuilderAgent.handle_signal("remove_source", %{"source_id" => "code_source"}, agent)
      
      refute Map.has_key?(agent.sources, "code_source")
    end

    test "gets source status", %{agent: agent} do
      data = %{"source_id" => "memory_source"}
      
      {:ok, status, _} = ContextBuilderAgent.handle_signal("get_source_status", data, agent)
      
      assert status["id"] == "memory_source"
      assert status["name"] == "Memory System"
      assert status["type"] == :memory
      assert status["status"] == :active
      assert status["weight"] == 1.0
    end
  end

  describe "configuration signals" do
    setup do
      {:ok, agent} = ContextBuilderAgent.init(%{})
      {:ok, agent: agent}
    end

    test "sets priorities with normalization", %{agent: agent} do
      data = %{
        "relevance_weight" => 2.0,
        "recency_weight" => 1.0,
        "importance_weight" => 1.0
      }
      
      {:ok, priorities, updated_agent} = ContextBuilderAgent.handle_signal("set_priorities", data, agent)
      
      # Should be normalized to sum to 1.0
      assert_in_delta priorities.relevance_weight, 0.5, 0.01
      assert_in_delta priorities.recency_weight, 0.25, 0.01
      assert_in_delta priorities.importance_weight, 0.25, 0.01
      
      total = priorities.relevance_weight + priorities.recency_weight + priorities.importance_weight
      assert_in_delta total, 1.0, 0.01
    end

    test "configures limits", %{agent: agent} do
      data = %{
        "max_cache_size" => 200,
        "default_max_tokens" => 8000,
        "compression_threshold" => 500
      }
      
      {:ok, config, updated_agent} = ContextBuilderAgent.handle_signal("configure_limits", data, agent)
      
      assert config.max_cache_size == 200
      assert config.default_max_tokens == 8000
      assert config.compression_threshold == 500
    end

    test "preserves unspecified config values", %{agent: agent} do
      original_timeout = agent.config.source_timeout
      
      data = %{"max_cache_size" => 150}
      
      {:ok, _, updated_agent} = ContextBuilderAgent.handle_signal("configure_limits", data, agent)
      
      assert updated_agent.config.max_cache_size == 150
      assert updated_agent.config.source_timeout == original_timeout
    end
  end

  describe "metrics signal" do
    test "returns comprehensive metrics" do
      {:ok, agent} = ContextBuilderAgent.init(%{})
      
      # Add some data
      agent = %{agent |
        cache: %{"req1" => %{}, "req2" => %{}},
        active_builds: %{"build1" => %{}},
        metrics: %{agent.metrics |
          builds_completed: 10,
          cache_hits: 8,
          cache_misses: 2,
          avg_build_time_ms: 50.5
        }
      }
      
      {:ok, metrics, _} = ContextBuilderAgent.handle_signal("get_metrics", %{}, agent)
      
      assert metrics["cache_size"] == 2
      assert metrics["active_builds"] == 1
      assert metrics["registered_sources"] == 2
      assert metrics["cache_hit_rate"] == 80.0
      assert metrics.builds_completed == 10
      assert metrics.avg_build_time_ms == 50.5
    end
  end

  describe "streaming context signal" do
    setup do
      {:ok, agent} = ContextBuilderAgent.init(%{})
      {:ok, agent: agent}
    end

    test "initiates streaming build", %{agent: agent} do
      data = %{
        "purpose" => "general",
        "max_tokens" => 2000,
        "chunk_size" => 500
      }
      
      {:ok, result, updated_agent} = ContextBuilderAgent.handle_signal("stream_context", data, agent)
      
      assert result["streaming"] == true
      assert Map.has_key?(result, "build_id")
      assert map_size(updated_agent.active_builds) == 1
    end
  end

  describe "cache management" do
    setup do
      {:ok, agent} = ContextBuilderAgent.init(%{})
      {:ok, agent: agent}
    end

    test "invalidates cache entries by pattern", %{agent: agent} do
      # Add some cache entries
      agent = agent
      |> put_in([Access.key(:cache), "req_test_1"], %{})
      |> put_in([Access.key(:cache), "req_test_2"], %{})
      |> put_in([Access.key(:cache), "req_other"], %{})
      
      data = %{"pattern" => "test"}
      
      {:ok, result, updated_agent} = ContextBuilderAgent.handle_signal("invalidate_context", data, agent)
      
      assert result["invalidated"] == 2
      assert Map.has_key?(updated_agent.cache, "req_other")
      refute Map.has_key?(updated_agent.cache, "req_test_1")
      refute Map.has_key?(updated_agent.cache, "req_test_2")
    end
  end

  describe "scheduled tasks" do
    test "handles cache cleanup message" do
      {:ok, agent} = ContextBuilderAgent.init(%{})
      
      # Add expired and valid cache entries
      now = DateTime.utc_now()
      old_timestamp = DateTime.add(now, -600, :second)  # 10 minutes old
      
      agent = agent
      |> put_in([Access.key(:cache), "old"], %{"timestamp" => old_timestamp})
      |> put_in([Access.key(:cache), "new"], %{"timestamp" => now})
      
      {:noreply, updated_agent} = ContextBuilderAgent.handle_info(:cleanup_cache, agent)
      
      assert Map.has_key?(updated_agent.cache, "new")
      refute Map.has_key?(updated_agent.cache, "old")
    end

    test "handles streaming completion message" do
      {:ok, agent} = ContextBuilderAgent.init(%{})
      
      # Add active build
      agent = put_in(agent.active_builds["test_build"], %{})
      
      {:noreply, updated_agent} = ContextBuilderAgent.handle_info({:streaming_complete, "test_build"}, agent)
      
      refute Map.has_key?(updated_agent.active_builds, "test_build")
    end
  end

  describe "context entry helpers" do
    test "creates valid context entry" do
      entry = ContextEntry.new(%{
        source: "test",
        content: "This is test content",
        relevance_score: 0.8
      })
      
      assert entry.source == "test"
      assert entry.content == "This is test content"
      assert entry.relevance_score == 0.8
      assert entry.size_tokens > 0
      refute entry.compressed
      refute entry.summarized
    end

    test "compresses large entries" do
      large_content = String.duplicate("This is a very long content. ", 100)
      
      entry = ContextEntry.new(%{
        content: large_content,
        size_tokens: 2000
      })
      
      compressed = ContextEntry.compress(entry)
      
      assert compressed.compressed
      assert compressed.size_tokens < entry.size_tokens
      assert compressed.original_content == large_content
    end

    test "summarizes entries" do
      content = "This is a long piece of content that needs to be summarized. " <>
                "It contains multiple sentences and ideas. " <>
                "The summary should be shorter than the original."
      
      entry = ContextEntry.new(%{content: content})
      
      summarized = ContextEntry.summarize(entry, 0.5)
      
      assert summarized.summarized
      assert String.length(summarized.content) < String.length(content)
    end
  end

  describe "context source helpers" do
    test "creates valid context source" do
      source = ContextSource.new(%{
        name: "Test Source",
        type: :custom,
        weight: 0.8
      })
      
      assert source.name == "Test Source"
      assert source.type == :custom
      assert source.weight == 0.8
      assert source.status == :active
      assert source.failure_count == 0
    end

    test "records successful fetch" do
      source = ContextSource.new(%{name: "Test"})
      
      updated = ContextSource.record_success(source, 100, 5)
      
      assert updated.metrics.total_fetches == 1
      assert updated.metrics.successful_fetches == 1
      assert updated.metrics.avg_fetch_time_ms == 100.0
      assert updated.metrics.total_entries_provided == 5
      assert updated.failure_count == 0
    end

    test "records failed fetch" do
      source = ContextSource.new(%{name: "Test"})
      
      updated = ContextSource.record_failure(source, "Connection timeout")
      
      assert updated.failure_count == 1
      assert updated.metrics.last_error == "Connection timeout"
      assert updated.status == :active
      
      # Multiple failures change status
      updated = source
      |> ContextSource.record_failure("Error 1")
      |> ContextSource.record_failure("Error 2")
      |> ContextSource.record_failure("Error 3")
      
      assert updated.failure_count == 3
      assert updated.status == :failing
    end
  end

  describe "context request helpers" do
    test "creates valid context request" do
      request = ContextRequest.new(%{
        purpose: "code_generation",
        max_tokens: 3000,
        required_sources: ["memory", "code"],
        priority: :high
      })
      
      assert request.purpose == "code_generation"
      assert request.max_tokens == 3000
      assert request.required_sources == ["memory", "code"]
      assert request.priority == :high
      refute request.streaming
    end

    test "validates conflicting source requirements" do
      assert_raise ArgumentError, fn ->
        ContextRequest.new(%{
          required_sources: ["source1"],
          excluded_sources: ["source1"]  # Same source required and excluded
        })
      end
    end

    test "calculates urgency score" do
      # High priority, no deadline
      request1 = ContextRequest.new(%{priority: :high})
      score1 = ContextRequest.urgency_score(request1)
      assert score1 > 0.5
      
      # Critical priority with imminent deadline
      deadline = DateTime.add(DateTime.utc_now(), 60, :second)
      request2 = ContextRequest.new(%{
        priority: :critical,
        deadline: deadline
      })
      score2 = ContextRequest.urgency_score(request2)
      assert score2 > score1
    end
  end
end