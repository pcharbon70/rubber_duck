defmodule RubberDuck.Integration.RAGPipelineTest do
  use ExUnit.Case, async: false

  alias RubberDuck.Agents.{
    RAGPipelineAgent,
    ShortTermMemoryAgent,
    LongTermMemoryAgent,
    ContextBuilderAgent,
    TokenManagerAgent,
    ResponseProcessorAgent
  }
  alias RubberDuck.Services.{LLMService, VectorDB}

  setup do
    # Start test dependencies with mock services
    {:ok, _} = start_supervised({SignalBus, name: :test_signal_bus})
    {:ok, _} = start_supervised({MockLLMService, name: :test_llm})
    {:ok, _} = start_supervised({MockVectorDB, name: :test_vector_db})
    
    # Initialize all agents
    {:ok, rag} = RAGPipelineAgent.init(%{
      llm_service: :test_llm,
      vector_db: :test_vector_db
    })
    
    {:ok, short_term} = ShortTermMemoryAgent.init(%{})
    {:ok, long_term} = LongTermMemoryAgent.init(%{})
    {:ok, context_builder} = ContextBuilderAgent.init(%{})
    {:ok, token_manager} = TokenManagerAgent.init(%{})
    {:ok, response_processor} = ResponseProcessorAgent.init(%{})
    
    # Seed test data
    seed_test_data(short_term, long_term)
    
    {:ok,
      rag: rag,
      short_term: short_term,
      long_term: long_term,
      context_builder: context_builder,
      token_manager: token_manager,
      response_processor: response_processor
    }
  end

  describe "complete RAG pipeline execution" do
    test "executes full pipeline with retrieval and generation", %{rag: rag} do
      query = "How do I implement error handling in Elixir?"
      
      {:ok, result, _} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => query,
        "pipeline_config" => %{
          "retrieval_strategy" => "hybrid",
          "generation_model" => "gpt-4",
          "max_tokens" => 500
        }
      }, rag)
      
      assert result["success"] == true
      assert result["response"] != nil
      assert is_binary(result["response"])
      
      # Verify pipeline stages
      assert result["stages_completed"] == ["retrieval", "augmentation", "generation"]
      assert length(result["retrieved_documents"]) > 0
      assert result["tokens_used"] <= 500
    end

    test "handles multi-turn conversations", %{rag: rag} do
      conversation_id = "test_conversation_1"
      
      # First turn
      {:ok, result1, rag} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => "What is GenServer?",
        "conversation_id" => conversation_id
      }, rag)
      
      assert result1["success"] == true
      
      # Second turn with context
      {:ok, result2, rag} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => "How do I start one?",
        "conversation_id" => conversation_id
      }, rag)
      
      assert result2["success"] == true
      assert result2["conversation_context_used"] == true
      assert length(result2["conversation_history"]) == 2
      
      # Response should be contextual
      assert result2["response"] =~ "GenServer"
    end

    test "applies different retrieval strategies", %{rag: rag} do
      strategies = ["semantic", "keyword", "hybrid", "mmr"]
      query = "Explain supervision trees"
      
      results = Enum.map(strategies, fn strategy ->
        {:ok, result, _} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
          "query" => query,
          "pipeline_config" => %{
            "retrieval_strategy" => strategy,
            "retrieve_only" => true  # Skip generation for comparison
          }
        }, rag)
        
        {strategy, result["retrieved_documents"]}
      end)
      
      # Different strategies should yield different results
      doc_sets = Enum.map(results, fn {_, docs} -> 
        MapSet.new(docs, & &1["id"])
      end)
      
      # Not all strategies should return identical documents
      assert length(Enum.uniq(doc_sets)) > 1
      
      # Hybrid should include results from both semantic and keyword
      {_, semantic_docs} = Enum.find(results, fn {s, _} -> s == "semantic" end)
      {_, keyword_docs} = Enum.find(results, fn {s, _} -> s == "keyword" end)
      {_, hybrid_docs} = Enum.find(results, fn {s, _} -> s == "hybrid" end)
      
      semantic_ids = MapSet.new(semantic_docs, & &1["id"])
      keyword_ids = MapSet.new(keyword_docs, & &1["id"])
      hybrid_ids = MapSet.new(hybrid_docs, & &1["id"])
      
      # Hybrid should have some overlap with both
      assert MapSet.intersection(hybrid_ids, semantic_ids) |> MapSet.size() > 0
      assert MapSet.intersection(hybrid_ids, keyword_ids) |> MapSet.size() > 0
    end
  end

  describe "error handling and fallbacks" do
    test "handles retrieval failures gracefully", %{rag: rag} do
      # Configure to simulate retrieval failure
      {:ok, result, _} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => "test query",
        "pipeline_config" => %{
          "simulate_retrieval_failure" => true,
          "fallback_strategy" => "use_context_only"
        }
      }, rag)
      
      assert result["success"] == true
      assert result["fallback_used"] == true
      assert result["fallback_reason"] =~ "retrieval failed"
      assert result["response"] != nil  # Should still generate response
    end

    test "handles generation failures with retry", %{rag: rag} do
      {:ok, result, _} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => "test query",
        "pipeline_config" => %{
          "simulate_generation_failure" => true,
          "max_retries" => 3,
          "retry_with_backoff" => true
        }
      }, rag)
      
      assert result["retries_attempted"] > 0
      assert result["retry_strategy"] == "exponential_backoff"
      
      # Should eventually succeed or fail gracefully
      assert result["success"] in [true, false]
      if not result["success"] do
        assert result["error_type"] == "generation_failed_after_retries"
      end
    end

    test "applies token limit constraints", %{rag: rag, token_manager: tm} do
      # Set low token budget
      {:ok, _, tm} = TokenManagerAgent.handle_signal("set_budget", %{
        "agent_id" => "rag_pipeline",
        "budget" => 100
      }, tm)
      
      {:ok, result, _} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => "Write a very detailed explanation of OTP",
        "pipeline_config" => %{
          "respect_token_budget" => true,
          "token_manager" => tm
        }
      }, rag)
      
      assert result["token_limited"] == true
      assert result["tokens_used"] <= 100
      assert result["response"] =~ "limited"
    end
  end

  describe "augmentation strategies" do
    test "augments with relevant context", %{rag: rag, context_builder: cb} do
      # Build rich context
      {:ok, context, _} = ContextBuilderAgent.handle_signal("aggregate_context", %{
        "sources" => [
          %{"source_type" => "short_term_memory", "query" => "recent errors"},
          %{"source_type" => "long_term_memory", "query" => "error patterns"}
        ]
      }, cb)
      
      {:ok, result, _} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => "How should I handle this error?",
        "context" => context["context_items"],
        "pipeline_config" => %{
          "augmentation_strategy" => "context_first"
        }
      }, rag)
      
      assert result["augmentation_applied"] == true
      assert result["context_items_used"] > 0
      assert result["response"] =~ "error"  # Should be contextual
    end

    test "chains multiple augmentation steps", %{rag: rag} do
      {:ok, result, _} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => "Implement a supervised GenServer",
        "pipeline_config" => %{
          "augmentation_chain" => [
            %{"type" => "retrieve_examples", "count" => 3},
            %{"type" => "add_documentation", "sections" => ["GenServer", "Supervisor"]},
            %{"type" => "include_best_practices"}
          ]
        }
      }, rag)
      
      assert length(result["augmentation_steps_completed"]) == 3
      assert result["total_augmented_tokens"] > result["query_tokens"]
      
      # Response should include elements from all augmentation steps
      response = result["response"]
      assert response =~ "example"
      assert response =~ "documentation" or response =~ "docs"
      assert response =~ "best practice" or response =~ "recommended"
    end

    test "optimizes augmentation for token limits", %{rag: rag} do
      {:ok, result, _} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => "Quick example of Task.async",
        "pipeline_config" => %{
          "max_augmentation_tokens" => 200,
          "prioritize_augmentation" => ["examples", "documentation", "context"]
        }
      }, rag)
      
      assert result["augmentation_optimized"] == true
      assert result["augmentation_tokens"] <= 200
      
      # Should prioritize examples over other augmentation
      augmentation_breakdown = result["augmentation_breakdown"]
      assert augmentation_breakdown["examples"] > augmentation_breakdown["documentation"]
    end
  end

  describe "response processing integration" do
    test "processes responses through full pipeline", %{rag: rag, response_processor: rp} do
      {:ok, result, _} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => "Show me a GenServer example with explanation",
        "pipeline_config" => %{
          "response_processing" => %{
            "enabled" => true,
            "processor" => rp,
            "extract_code" => true,
            "format_markdown" => true
          }
        }
      }, rag)
      
      assert result["response_processed"] == true
      assert is_map(result["processed_response"])
      
      processed = result["processed_response"]
      assert Map.has_key?(processed, "code_blocks")
      assert Map.has_key?(processed, "formatted_content")
      assert length(processed["code_blocks"]) > 0
    end

    test "applies response validation", %{rag: rag, response_processor: rp} do
      {:ok, result, _} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => "Generate a function to calculate fibonacci",
        "pipeline_config" => %{
          "response_validation" => %{
            "enabled" => true,
            "validators" => [
              %{"type" => "code_syntax", "language" => "elixir"},
              %{"type" => "content_completeness"},
              %{"type" => "safety_check"}
            ]
          }
        }
      }, rag)
      
      assert result["validation_passed"] == true
      assert length(result["validation_results"]) == 3
      assert Enum.all?(result["validation_results"], & &1["passed"])
    end
  end

  describe "performance and optimization" do
    test "caches pipeline results", %{rag: rag} do
      query = "Explain supervisors in Elixir"
      config = %{"enable_caching" => true, "cache_ttl" => 3600}
      
      # First execution
      {:ok, result1, rag} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => query,
        "pipeline_config" => config
      }, rag)
      
      execution_time1 = result1["execution_time_ms"]
      
      # Second execution (should hit cache)
      {:ok, result2, _} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => query,
        "pipeline_config" => config
      }, rag)
      
      assert result2["cache_hit"] == true
      assert result2["execution_time_ms"] < execution_time1 / 10  # Much faster
      assert result2["response"] == result1["response"]
    end

    test "parallelizes independent operations", %{rag: rag} do
      {:ok, result, _} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => "Compare GenServer and Agent",
        "pipeline_config" => %{
          "parallel_retrieval" => true,
          "retrieval_sources" => ["memory", "documentation", "examples"],
          "track_parallelization" => true
        }
      }, rag)
      
      assert result["parallel_operations"] > 0
      assert result["parallelization_speedup"] > 1.0
      
      # Verify all sources were queried
      assert length(result["retrieval_timings"]) == 3
      
      # Parallel execution should be faster than sequential sum
      total_sequential = Enum.sum(Map.values(result["retrieval_timings"]))
      assert result["total_retrieval_time"] < total_sequential * 0.8
    end

    test "optimizes for latency-sensitive queries", %{rag: rag} do
      {:ok, result, _} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => "Quick answer: what is pid?",
        "pipeline_config" => %{
          "optimization_mode" => "low_latency",
          "target_latency_ms" => 100
        }
      }, rag)
      
      assert result["execution_time_ms"] <= 150  # Some buffer for test variance
      assert result["optimization_applied"] == true
      assert result["optimizations"] != []
      
      # Should skip some expensive operations
      optimizations = result["optimizations"]
      assert "skip_deep_retrieval" in optimizations or "use_cached_embeddings" in optimizations
    end
  end

  describe "monitoring and observability" do
    test "tracks detailed pipeline metrics", %{rag: rag} do
      # Execute several queries
      queries = [
        "What is OTP?",
        "How to use GenServer?",
        "Explain supervision trees",
        "Best practices for error handling"
      ]
      
      Enum.each(queries, fn query ->
        RAGPipelineAgent.handle_signal("execute_pipeline", %{
          "query" => query
        }, rag)
      end)
      
      # Get metrics
      {:ok, metrics, _} = RAGPipelineAgent.handle_signal("get_pipeline_metrics", %{}, rag)
      
      assert metrics["total_executions"] == 4
      assert metrics["average_latency_ms"] > 0
      assert metrics["success_rate"] == 1.0
      
      # Stage breakdown
      assert Map.has_key?(metrics, "stage_timings")
      assert metrics["stage_timings"]["retrieval"]["avg_ms"] > 0
      assert metrics["stage_timings"]["generation"]["avg_ms"] > 0
    end

    test "provides execution traces", %{rag: rag} do
      {:ok, result, _} = RAGPipelineAgent.handle_signal("execute_pipeline", %{
        "query" => "Debug this error: undefined function",
        "pipeline_config" => %{
          "enable_tracing" => true,
          "trace_level" => "detailed"
        }
      }, rag)
      
      assert Map.has_key?(result, "execution_trace")
      trace = result["execution_trace"]
      
      assert is_list(trace["events"])
      assert length(trace["events"]) > 5
      
      # Verify trace structure
      first_event = hd(trace["events"])
      assert Map.has_key?(first_event, "timestamp")
      assert Map.has_key?(first_event, "stage")
      assert Map.has_key?(first_event, "duration_ms")
      
      # Should have traces for all major stages
      stages = Enum.map(trace["events"], & &1["stage"]) |> Enum.uniq()
      assert "retrieval" in stages
      assert "augmentation" in stages
      assert "generation" in stages
    end
  end

  # Helper functions

  defp seed_test_data(short_term, long_term) do
    # Seed short-term memory
    short_term_data = [
      %{"type" => "error", "content" => "undefined function error in module X"},
      %{"type" => "code", "content" => "defmodule Example do\n  use GenServer\nend"},
      %{"type" => "interaction", "content" => "User asked about supervision trees"}
    ]
    
    Enum.each(short_term_data, fn data ->
      ShortTermMemoryAgent.handle_signal("store_memory", data, short_term)
    end)
    
    # Seed long-term memory
    long_term_data = [
      %{"type" => "pattern", "content" => "GenServer error handling pattern", "tags" => ["genserver", "error"]},
      %{"type" => "documentation", "content" => "Supervisor restart strategies", "tags" => ["supervisor", "otp"]},
      %{"type" => "example", "content" => "Task.async example code", "tags" => ["task", "concurrency"]}
    ]
    
    Enum.each(long_term_data, fn data ->
      LongTermMemoryAgent.handle_signal("store_memory", data, long_term)
    end)
  end
end

# Mock services for testing

defmodule MockLLMService do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, %{}, opts)
  end

  def init(_) do
    {:ok, %{call_count: 0}}
  end

  def handle_call({:generate, prompt, _config}, _from, state) do
    response = generate_mock_response(prompt)
    {:reply, {:ok, response}, %{state | call_count: state.call_count + 1}}
  end

  defp generate_mock_response(prompt) do
    cond do
      String.contains?(prompt, "GenServer") ->
        "GenServer is a behavior module for implementing the server of a client-server relation..."
      
      String.contains?(prompt, "error") ->
        "To handle errors in Elixir, you can use try/catch, pattern matching on {:error, reason} tuples..."
      
      String.contains?(prompt, "supervisor") ->
        "Supervisors are specialized processes that monitor other processes and restart them if they crash..."
      
      true ->
        "This is a mock response for testing purposes."
    end
  end
end

defmodule MockVectorDB do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, %{}, opts)
  end

  def init(_) do
    {:ok, %{documents: generate_mock_documents()}}
  end

  def handle_call({:search, query, _config}, _from, state) do
    results = search_mock_documents(query, state.documents)
    {:reply, {:ok, results}, state}
  end

  defp generate_mock_documents() do
    [
      %{id: "doc1", content: "GenServer implementation guide", embedding: random_embedding()},
      %{id: "doc2", content: "Error handling in Elixir", embedding: random_embedding()},
      %{id: "doc3", content: "OTP supervision trees explained", embedding: random_embedding()},
      %{id: "doc4", content: "Task and async operations", embedding: random_embedding()},
      %{id: "doc5", content: "Pattern matching best practices", embedding: random_embedding()}
    ]
  end

  defp search_mock_documents(query, documents) do
    # Simple keyword matching for testing
    Enum.filter(documents, fn doc ->
      String.contains?(String.downcase(doc.content), String.downcase(query))
    end)
    |> Enum.take(3)
    |> Enum.map(fn doc ->
      Map.put(doc, :score, :rand.uniform())
    end)
  end

  defp random_embedding() do
    Enum.map(1..768, fn _ -> :rand.uniform() end)
  end
end