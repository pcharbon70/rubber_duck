defmodule RubberDuck.Agents.LongTermMemoryAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.LongTermMemoryAgent
  alias RubberDuck.Memory.{MemoryEntry, MemoryIndex, MemoryVersion, MemoryQuery}

  describe "LongTermMemoryAgent initialization" do
    test "initializes with default configuration" do
      {:ok, agent} = LongTermMemoryAgent.init(%{})
      
      assert agent.storage_backend == :postgresql
      assert agent.indices != %{}
      assert agent.cache == %{}
      assert agent.pending_writes == []
      assert agent.versions == %{}
      assert agent.metrics.total_memories == 0
      assert agent.config.cache_size == 1000
      assert agent.config.compression_enabled == true
    end

    test "initializes default indices" do
      {:ok, agent} = LongTermMemoryAgent.init(%{})
      
      assert Map.has_key?(agent.indices, "fulltext")
      assert Map.has_key?(agent.indices, "type")
      assert Map.has_key?(agent.indices, "tags")
      assert Map.has_key?(agent.indices, "metadata")
      
      assert agent.indices["fulltext"].type == :fulltext
      assert agent.indices["type"].type == :metadata
    end
  end

  describe "store_memory signal" do
    setup do
      {:ok, agent} = LongTermMemoryAgent.init(%{})
      {:ok, agent: agent}
    end

    test "stores memory successfully", %{agent: agent} do
      data = %{
        "type" => "code_pattern",
        "content" => %{"pattern" => "singleton", "description" => "Singleton pattern"},
        "metadata" => %{"language" => "elixir", "complexity" => "low"},
        "ttl" => 3600,
        "tags" => ["pattern", "design", "elixir"]
      }
      
      {:ok, result, updated_agent} = LongTermMemoryAgent.handle_signal("store_memory", data, agent)
      
      assert Map.has_key?(result, "memory_id")
      assert result["stored"] == true
      assert length(updated_agent.pending_writes) == 1
      
      # Check the stored memory
      [memory | _] = updated_agent.pending_writes
      assert memory.type == :code_pattern
      assert memory.content == data["content"]
      assert memory.tags == data["tags"]
    end

    test "validates memory type", %{agent: agent} do
      data = %{
        "type" => "invalid_type",
        "content" => "test",
        "metadata" => %{},
        "ttl" => nil,
        "tags" => []
      }
      
      {:error, reason, _} = LongTermMemoryAgent.handle_signal("store_memory", data, agent)
      
      assert reason =~ "Invalid memory type"
    end

    test "flushes buffer when full", %{agent: agent} do
      # Set small buffer size
      agent = put_in(agent.config.write_buffer_size, 2)
      
      # Store first memory
      data1 = base_memory_data("pattern1")
      {:ok, _, agent} = LongTermMemoryAgent.handle_signal("store_memory", data1, agent)
      assert length(agent.pending_writes) == 1
      
      # Store second memory - should trigger flush
      data2 = base_memory_data("pattern2")
      {:ok, _, agent} = LongTermMemoryAgent.handle_signal("store_memory", data2, agent)
      assert length(agent.pending_writes) == 0  # Buffer flushed
    end

    test "applies compression when enabled", %{agent: agent} do
      # Ensure compression is enabled
      agent = put_in(agent.config.compression_enabled, true)
      
      # Create large content that should trigger compression
      large_content = String.duplicate("This is a test content. ", 1000)
      
      data = %{
        "type" => "knowledge",
        "content" => large_content,
        "metadata" => %{},
        "ttl" => nil,
        "tags" => []
      }
      
      {:ok, _, updated_agent} = LongTermMemoryAgent.handle_signal("store_memory", data, agent)
      
      [memory | _] = updated_agent.pending_writes
      assert memory.compressed == true
    end
  end

  describe "update_memory signal" do
    setup do
      {:ok, agent} = LongTermMemoryAgent.init(%{})
      
      # Create and store a memory
      memory = MemoryEntry.new(%{
        type: :code_pattern,
        content: %{"pattern" => "observer"},
        metadata: %{"version" => "1.0"},
        tags: ["pattern", "behavioral"]
      })
      
      agent = put_in(agent.cache[memory.id], memory)
      
      {:ok, agent: agent, memory: memory}
    end

    test "updates memory successfully", %{agent: agent, memory: memory} do
      data = %{
        "memory_id" => memory.id,
        "updates" => %{
          "content" => %{"pattern" => "observer", "updated" => true},
          "metadata" => %{"version" => "1.1"}
        },
        "reason" => "Added update flag"
      }
      
      {:ok, result, updated_agent} = LongTermMemoryAgent.handle_signal("update_memory", data, agent)
      
      assert result["memory"].version == memory.version + 1
      assert result["memory"].content["updated"] == true
      assert result["memory"].metadata["version"] == "1.1"
      
      # Check version was created
      assert Map.has_key?(updated_agent.versions, memory.id)
      assert length(updated_agent.versions[memory.id]) == 1
    end

    test "handles non-existent memory", %{agent: agent} do
      data = %{
        "memory_id" => "non_existent",
        "updates" => %{"content" => "new"},
        "reason" => "Test"
      }
      
      {:error, reason, _} = LongTermMemoryAgent.handle_signal("update_memory", data, agent)
      
      assert reason != nil
    end
  end

  describe "delete_memory signal" do
    setup do
      {:ok, agent} = LongTermMemoryAgent.init(%{})
      
      # Create and cache a memory
      memory = MemoryEntry.new(%{
        type: :interaction,
        content: "test interaction"
      })
      
      agent = put_in(agent.cache[memory.id], memory)
      
      {:ok, agent: agent, memory: memory}
    end

    test "soft deletes memory by default", %{agent: agent, memory: memory} do
      data = %{"memory_id" => memory.id}
      
      {:ok, result, updated_agent} = LongTermMemoryAgent.handle_signal("delete_memory", data, agent)
      
      assert result["deleted"] == true
      assert result["soft_delete"] == true
      
      # Memory should be removed from cache
      refute Map.has_key?(updated_agent.cache, memory.id)
    end

    test "hard deletes memory when specified", %{agent: agent, memory: memory} do
      data = %{
        "memory_id" => memory.id,
        "soft_delete" => false
      }
      
      {:ok, result, updated_agent} = LongTermMemoryAgent.handle_signal("delete_memory", data, agent)
      
      assert result["deleted"] == true
      assert result["hard_delete"] == true
      refute Map.has_key?(updated_agent.cache, memory.id)
    end
  end

  describe "bulk_store signal" do
    setup do
      {:ok, agent} = LongTermMemoryAgent.init(%{})
      {:ok, agent: agent}
    end

    test "stores multiple memories", %{agent: agent} do
      memories_data = [
        %{
          "type" => "code_pattern",
          "content" => "Pattern 1",
          "metadata" => %{},
          "ttl" => nil,
          "tags" => ["test"]
        },
        %{
          "type" => "knowledge",
          "content" => "Knowledge 1",
          "metadata" => %{"source" => "test"},
          "ttl" => 3600,
          "tags" => []
        },
        %{
          "type" => "interaction",
          "content" => "Interaction 1",
          "metadata" => %{},
          "ttl" => nil,
          "tags" => ["user"]
        }
      ]
      
      data = %{"memories" => memories_data}
      
      {:ok, result, updated_agent} = LongTermMemoryAgent.handle_signal("bulk_store", data, agent)
      
      assert length(result["memory_ids"]) == 3
      assert result["count"] == 3
      
      # Bulk store forces flush
      assert updated_agent.pending_writes == []
    end
  end

  describe "search_memories signal" do
    setup do
      {:ok, agent} = LongTermMemoryAgent.init(%{})
      {:ok, agent: agent}
    end

    test "searches memories with query", %{agent: agent} do
      data = %{
        "query" => "elixir pattern",
        "types" => ["code_pattern", "knowledge"],
        "limit" => 10,
        "offset" => 0
      }
      
      {:ok, result, updated_agent} = LongTermMemoryAgent.handle_signal("search_memories", data, agent)
      
      assert Map.has_key?(result, "results")
      assert Map.has_key?(result, "count")
      assert updated_agent.metrics.queries_processed == 1
    end

    test "handles empty search parameters", %{agent: agent} do
      data = %{
        "query" => "",
        "types" => nil,
        "limit" => nil,
        "offset" => nil
      }
      
      {:ok, result, _} = LongTermMemoryAgent.handle_signal("search_memories", data, agent)
      
      assert Map.has_key?(result, "results")
      assert Map.has_key?(result, "count")
    end
  end

  describe "query_memories signal" do
    setup do
      {:ok, agent} = LongTermMemoryAgent.init(%{})
      {:ok, agent: agent}
    end

    test "executes complex query", %{agent: agent} do
      query_data = %{
        "filters" => [
          %{"field" => "type", "operator" => "eq", "value" => "code_pattern"},
          %{"field" => "metadata.language", "operator" => "eq", "value" => "elixir"}
        ],
        "sort" => [
          %{"field" => "created_at", "direction" => "desc"}
        ],
        "pagination" => %{
          "page" => 1,
          "page_size" => 20
        }
      }
      
      {:ok, result, _} = LongTermMemoryAgent.handle_signal("query_memories", query_data, agent)
      
      assert Map.has_key?(result, "results")
      assert Map.has_key?(result, "total_count")
      assert result["page"] == 1
      assert result["page_size"] == 20
    end
  end

  describe "get_memory signal" do
    setup do
      {:ok, agent} = LongTermMemoryAgent.init(%{})
      
      # Create and cache a memory
      memory = MemoryEntry.new(%{
        type: :knowledge,
        content: "test knowledge"
      })
      
      agent = put_in(agent.cache[memory.id], memory)
      
      {:ok, agent: agent, memory: memory}
    end

    test "retrieves memory by ID", %{agent: agent, memory: memory} do
      data = %{"memory_id" => memory.id}
      
      {:ok, result, updated_agent} = LongTermMemoryAgent.handle_signal("get_memory", data, agent)
      
      assert result["memory"].id == memory.id
      assert result["memory"].access_count == memory.access_count + 1
      
      # Should update cache hit metrics
      assert updated_agent.metrics.cache_hits > agent.metrics.cache_hits
    end

    test "handles non-existent memory", %{agent: agent} do
      data = %{"memory_id" => "non_existent"}
      
      {:error, reason, _} = LongTermMemoryAgent.handle_signal("get_memory", data, agent)
      
      assert reason != nil
    end
  end

  describe "get_related signal" do
    setup do
      {:ok, agent} = LongTermMemoryAgent.init(%{})
      
      # Create a memory with relationships
      memory = MemoryEntry.new(%{
        type: :code_pattern,
        content: "observer pattern"
      })
      |> MemoryEntry.add_relationship(:implements, "mem_123", %{})
      |> MemoryEntry.add_relationship(:related_to, "mem_456", %{})
      
      agent = put_in(agent.cache[memory.id], memory)
      
      {:ok, agent: agent, memory: memory}
    end

    test "finds related memories", %{agent: agent, memory: memory} do
      data = %{
        "memory_id" => memory.id,
        "relationship_types" => [:implements, :related_to],
        "limit" => 5
      }
      
      {:ok, result, _} = LongTermMemoryAgent.handle_signal("get_related", data, agent)
      
      assert Map.has_key?(result, "related")
      assert is_list(result["related"])
    end
  end

  describe "management signals" do
    setup do
      {:ok, agent} = LongTermMemoryAgent.init(%{})
      {:ok, agent: agent}
    end

    test "starts storage optimization", %{agent: agent} do
      {:ok, result, updated_agent} = LongTermMemoryAgent.handle_signal("optimize_storage", %{}, agent)
      
      assert result["optimization_started"] == true
      assert updated_agent.metrics.last_optimization != agent.metrics.last_optimization
    end

    test "gets memory statistics", %{agent: agent} do
      # Add some test data
      agent = %{agent |
        metrics: %{agent.metrics |
          total_memories: 100,
          storage_size_bytes: 1_048_576,
          queries_processed: 50,
          cache_hits: 30,
          cache_misses: 20
        },
        cache: %{"mem1" => %{}, "mem2" => %{}},
        pending_writes: [%{}, %{}, %{}]
      }
      
      {:ok, stats, _} = LongTermMemoryAgent.handle_signal("get_memory_stats", %{}, agent)
      
      assert stats["total_memories"] == 100
      assert stats["storage_size_mb"] == 1.0
      assert stats["cache_size"] == 2
      assert stats["cache_hit_rate"] == 60.0
      assert stats["pending_writes"] == 3
    end

    test "gets memory versions", %{agent: agent} do
      memory_id = "mem_123"
      versions = [
        %MemoryVersion{version: 2, changes: %{}},
        %MemoryVersion{version: 1, changes: %{}}
      ]
      
      agent = put_in(agent.versions[memory_id], versions)
      
      data = %{"memory_id" => memory_id}
      {:ok, result, _} = LongTermMemoryAgent.handle_signal("get_memory_versions", data, agent)
      
      assert length(result["versions"]) == 2
    end
  end

  describe "scheduled tasks" do
    test "handles buffer flush message" do
      {:ok, agent} = LongTermMemoryAgent.init(%{})
      
      # Add pending writes
      memory = MemoryEntry.new(%{type: :knowledge, content: "test"})
      agent = %{agent | pending_writes: [memory]}
      
      {:noreply, updated_agent} = LongTermMemoryAgent.handle_info(:flush_writes, agent)
      
      assert updated_agent.pending_writes == []
    end

    test "handles index update message" do
      {:ok, agent} = LongTermMemoryAgent.init(%{})
      
      original_updated = agent.indices["fulltext"].last_updated
      
      # Sleep briefly to ensure time difference
      Process.sleep(10)
      
      {:noreply, updated_agent} = LongTermMemoryAgent.handle_info(:update_indices, agent)
      
      assert updated_agent.indices["fulltext"].last_updated > original_updated
    end
  end

  # Helper functions

  defp base_memory_data(content) do
    %{
      "type" => "code_pattern",
      "content" => content,
      "metadata" => %{},
      "ttl" => nil,
      "tags" => []
    }
  end
end