defmodule RubberDuck.Agents.RAGPipelineAgentTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Agents.RAGPipelineAgent
  alias RubberDuck.RAG.{RAGQuery, RetrievedDocument, AugmentedContext}

  describe "RAGPipelineAgent initialization" do
    test "initializes with default configuration" do
      {:ok, agent} = RAGPipelineAgent.init(%{})
      
      assert agent.pipelines == %{}
      assert agent.cache == %{}
      assert agent.active_tests == %{}
      assert agent.retrieval_config.vector_weight == 0.7
      assert agent.retrieval_config.keyword_weight == 0.3
      assert agent.retrieval_config.rerank_enabled == true
      assert agent.config.max_documents == 10
      assert agent.config.default_max_tokens == 4000
    end

    test "initializes metrics correctly" do
      {:ok, agent} = RAGPipelineAgent.init(%{})
      
      assert agent.metrics.queries_processed == 0
      assert agent.metrics.pipelines_completed == 0
      assert agent.metrics.cache_hits == 0
      assert agent.metrics.cache_misses == 0
    end
  end

  describe "execute_rag_pipeline signal" do
    setup do
      {:ok, agent} = RAGPipelineAgent.init(%{})
      {:ok, agent: agent}
    end

    test "executes complete pipeline for new query", %{agent: agent} do
      data = %{
        "query" => "What is Elixir?",
        "retrieval_config" => %{"max_documents" => 5},
        "augmentation_config" => %{},
        "generation_config" => %{"template" => "default"}
      }
      
      {:ok, result, updated_agent} = RAGPipelineAgent.handle_signal("execute_rag_pipeline", data, agent)
      
      assert Map.has_key?(result, "pipeline_id")
      assert Map.has_key?(result, "query")
      assert result["query"] == "What is Elixir?"
      assert Map.has_key?(result, "documents_retrieved")
      assert Map.has_key?(result, "total_time_ms")
      
      # Should update metrics
      assert updated_agent.metrics.cache_misses == 1
      assert updated_agent.metrics.pipelines_completed == 1
    end

    test "returns cached results when available", %{agent: agent} do
      # Create a cached result
      query = RAGQuery.new(%{query: "cached query"})
      cache_key = RAGQuery.cache_key(query)
      
      cached_result = %{
        "result" => %{"cached" => true, "data" => "test"},
        "cached_at" => DateTime.utc_now()
      }
      
      agent = put_in(agent.cache[cache_key], cached_result)
      
      data = %{"query" => "cached query"}
      
      {:ok, result, updated_agent} = RAGPipelineAgent.handle_signal("execute_rag_pipeline", data, agent)
      
      assert result["cached"] == true
      assert updated_agent.metrics.cache_hits == 1
      assert updated_agent.metrics.cache_misses == 0
    end
  end

  describe "retrieve_documents signal" do
    setup do
      {:ok, agent} = RAGPipelineAgent.init(%{})
      {:ok, agent: agent}
    end

    test "retrieves documents successfully", %{agent: agent} do
      data = %{
        "query" => "Elixir programming",
        "retrieval_config" => %{"max_documents" => 3}
      }
      
      {:ok, result, updated_agent} = RAGPipelineAgent.handle_signal("retrieve_documents", data, agent)
      
      assert Map.has_key?(result, "documents")
      assert is_list(result["documents"])
      assert length(result["documents"]) <= 3
      assert Map.has_key?(result, "retrieval_time_ms")
      
      # Check metrics were updated
      assert updated_agent.metrics.queries_processed == 1
    end

    test "filters by minimum relevance score", %{agent: agent} do
      # Set high minimum relevance
      agent = put_in(agent.config.min_relevance_score, 0.8)
      
      data = %{"query" => "test query"}
      
      {:ok, result, _} = RAGPipelineAgent.handle_signal("retrieve_documents", data, agent)
      
      # All returned documents should meet minimum score
      Enum.each(result["documents"], fn doc ->
        assert doc["relevance_score"] >= 0.8
      end)
    end
  end

  describe "augment_context signal" do
    setup do
      {:ok, agent} = RAGPipelineAgent.init(%{})
      {:ok, agent: agent}
    end

    test "augments documents into context", %{agent: agent} do
      documents = [
        %{
          "id" => "doc1",
          "content" => "Test content 1",
          "relevance_score" => 0.9
        },
        %{
          "id" => "doc2",
          "content" => "Test content 2",
          "relevance_score" => 0.8
        }
      ]
      
      data = %{
        "query_id" => "test_query",
        "documents" => documents
      }
      
      {:ok, result, _} = RAGPipelineAgent.handle_signal("augment_context", data, agent)
      
      assert result["query_id"] == "test_query"
      assert length(result["documents"]) == 2
      assert Map.has_key?(result, "summary")
      assert Map.has_key?(result, "total_tokens")
    end
  end

  describe "configuration signals" do
    setup do
      {:ok, agent} = RAGPipelineAgent.init(%{})
      {:ok, agent: agent}
    end

    test "configures retrieval settings", %{agent: agent} do
      data = %{
        "max_documents" => 20,
        "min_relevance_score" => 0.6,
        "vector_weight" => 0.8,
        "keyword_weight" => 0.2,
        "rerank_enabled" => false
      }
      
      {:ok, result, updated_agent} = RAGPipelineAgent.handle_signal("configure_retrieval", data, agent)
      
      assert result["updated"] == true
      assert updated_agent.config.max_documents == 20
      assert updated_agent.config.min_relevance_score == 0.6
      assert updated_agent.retrieval_config.vector_weight == 0.8
      assert updated_agent.retrieval_config.keyword_weight == 0.2
      assert updated_agent.retrieval_config.rerank_enabled == false
    end

    test "configures augmentation settings", %{agent: agent} do
      data = %{
        "dedup_threshold" => 0.9,
        "summarization_enabled" => false,
        "format_standardization" => true
      }
      
      {:ok, result, updated_agent} = RAGPipelineAgent.handle_signal("configure_augmentation", data, agent)
      
      assert result["updated"] == true
      assert updated_agent.augmentation_config.dedup_threshold == 0.9
      assert updated_agent.augmentation_config.summarization_enabled == false
    end

    test "configures generation settings", %{agent: agent} do
      data = %{
        "max_context_tokens" => 6000,
        "streaming_enabled" => false,
        "quality_check_enabled" => true
      }
      
      {:ok, result, updated_agent} = RAGPipelineAgent.handle_signal("configure_generation", data, agent)
      
      assert result["updated"] == true
      assert updated_agent.config.max_context_tokens == 6000
      assert updated_agent.config.streaming_enabled == false
      assert updated_agent.generation_config.quality_check_enabled == true
    end
  end

  describe "analytics signals" do
    setup do
      {:ok, agent} = RAGPipelineAgent.init(%{})
      
      # Add some metrics
      agent = %{agent |
        metrics: %{agent.metrics |
          queries_processed: 100,
          pipelines_completed: 95,
          cache_hits: 30,
          cache_misses: 70,
          avg_retrieval_time_ms: 150.5,
          avg_relevance_score: 0.75
        }
      }
      
      {:ok, agent: agent}
    end

    test "gets pipeline metrics", %{agent: agent} do
      {:ok, metrics, _} = RAGPipelineAgent.handle_signal("get_pipeline_metrics", %{}, agent)
      
      assert metrics["queries_processed"] == 100
      assert metrics["pipelines_completed"] == 95
      assert metrics["cache_hit_rate"] == 30.0
      assert metrics["success_rate"] == 100.0  # No errors recorded
      assert Map.has_key?(metrics, "avg_pipeline_time_ms")
    end

    test "starts A/B test", %{agent: agent} do
      data = %{
        "name" => "Retrieval Strategy Test",
        "variant_a" => %{"strategy" => "hybrid"},
        "variant_b" => %{"strategy" => "ensemble"},
        "metrics" => ["relevance_score", "response_time"],
        "sample_size" => 50
      }
      
      {:ok, result, updated_agent} = RAGPipelineAgent.handle_signal("run_ab_test", data, agent)
      
      assert Map.has_key?(result, "test_id")
      assert result["status"] == "started"
      
      # Check test was added
      test_id = result["test_id"]
      assert Map.has_key?(updated_agent.active_tests, test_id)
      
      test = updated_agent.active_tests[test_id]
      assert test.name == "Retrieval Strategy Test"
      assert test.sample_size == 50
    end

    test "provides optimization recommendations", %{agent: agent} do
      {:ok, result, _} = RAGPipelineAgent.handle_signal("optimize_pipeline", %{"type" => "auto"}, agent)
      
      assert Map.has_key?(result, "optimizations")
      assert result["applied"] == true
      
      # Should have recommendations for all components
      assert Map.has_key?(result["optimizations"], "retrieval")
      assert Map.has_key?(result["optimizations"], "augmentation")
      assert Map.has_key?(result["optimizations"], "generation")
    end
  end

  describe "RAG data structures" do
    test "creates valid RAG query" do
      query = RAGQuery.new(%{
        query: "Test query",
        retrieval_config: %{max_documents: 15},
        priority: :high
      })
      
      assert query.query == "Test query"
      assert query.retrieval_config.max_documents == 15
      assert query.priority == :high
      assert RAGQuery.valid?(query)
    end

    test "creates retrieved document" do
      doc = RetrievedDocument.new(%{
        content: "Document content",
        relevance_score: 0.85,
        source: "test_source"
      })
      
      assert doc.content == "Document content"
      assert doc.relevance_score == 0.85
      assert doc.source == "test_source"
      assert doc.size_tokens > 0
    end

    test "creates augmented context" do
      docs = [
        RetrievedDocument.new(%{content: "Doc 1", relevance_score: 0.9}),
        RetrievedDocument.new(%{content: "Doc 2", relevance_score: 0.8})
      ]
      
      context = AugmentedContext.new(%{
        query_id: "test",
        documents: docs
      })
      
      assert context.query_id == "test"
      assert length(context.documents) == 2
      assert context.total_tokens > 0
      assert AugmentedContext.valid?(context)
    end

    test "document similarity calculation" do
      doc1 = RetrievedDocument.new(%{content: "Elixir is a functional language"})
      doc2 = RetrievedDocument.new(%{content: "Elixir is a functional programming language"})
      doc3 = RetrievedDocument.new(%{content: "Python is an object-oriented language"})
      
      # Similar documents should have high similarity
      assert RetrievedDocument.similarity(doc1, doc2) > 0.7
      
      # Different documents should have lower similarity
      assert RetrievedDocument.similarity(doc1, doc3) < 0.5
    end

    test "context optimization" do
      # Create context that exceeds token limit
      large_docs = Enum.map(1..10, fn i ->
        RetrievedDocument.new(%{
          content: String.duplicate("Large content #{i} ", 100),
          relevance_score: 1.0 - (i * 0.1)
        })
      end)
      
      context = AugmentedContext.new(%{documents: large_docs})
      
      # Fit to limit
      optimized = AugmentedContext.fit_to_limit(context, 1000)
      
      assert optimized.total_tokens <= 1000
      assert length(optimized.documents) < length(context.documents)
      assert :token_limit in optimized.optimization_applied
    end
  end

  describe "cache management" do
    test "cache cleanup removes expired entries" do
      {:ok, agent} = RAGPipelineAgent.init(%{})
      
      # Add expired and valid cache entries
      now = DateTime.utc_now()
      old_timestamp = DateTime.add(now, -400, :second)  # Older than TTL
      
      agent = agent
      |> put_in([Access.key(:cache), "old"], %{"cached_at" => old_timestamp, "result" => %{}})
      |> put_in([Access.key(:cache), "new"], %{"cached_at" => now, "result" => %{}})
      
      {:noreply, updated_agent} = RAGPipelineAgent.handle_info(:cleanup_cache, agent)
      
      assert Map.has_key?(updated_agent.cache, "new")
      refute Map.has_key?(updated_agent.cache, "old")
    end
  end
end