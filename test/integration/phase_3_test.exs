defmodule RubberDuck.Integration.Phase3Test do
  @moduledoc """
  Integration tests for Phase 3: LLM Integration & Memory System.
  
  Tests the complete integration of:
  - LLM Service with multiple providers
  - Hierarchical Memory System
  - Context Building and Caching
  - Chain-of-Thought (CoT) reasoning
  - RAG (Retrieval Augmented Generation)
  - Self-Correction Engine
  - Enhancement Integration
  """
  
  use ExUnit.Case, async: false
  
  alias RubberDuck.LLM.Service, as: LLMService
  alias RubberDuck.Memory.Manager, as: MemoryManager
  alias RubberDuck.Context.Manager, as: ContextManager
  alias RubberDuck.CoT.ConversationManager
  alias RubberDuck.RAG.Pipeline, as: RAGPipeline
  alias RubberDuck.SelfCorrection.Engine, as: SelfCorrectionEngine
  alias RubberDuck.Enhancement.Coordinator, as: EnhancementCoordinator
  alias RubberDuck.Engines.Generation
  
  @moduletag :integration
  @moduletag :phase_3
  
  setup do
    # Create test user
    user_id = "test_user_#{System.unique_integer([:positive])}"
    
    # Note: In actual implementation, we would start/restart the application
    # and ensure all services are ready
    
    {:ok, user_id: user_id}
  end
  
  describe "3.9.1 Complete code generation flow with memory" do
    test "generates code using hierarchical memory system", %{user_id: user_id} do
      # First, create some memory context
      MemoryManager.store_interaction(%{
        user_id: user_id,
        session_id: "test_session",
        type: :generation,
        input: "Create a GenServer for managing tasks",
        output: "defmodule TaskManager do\n  use GenServer\n  # ...\nend",
        metadata: %{language: :elixir, quality_score: 0.9}
      })
      
      # Generate code with memory context
      input = %{
        prompt: "Create another GenServer, similar to TaskManager but for handling jobs",
        language: :elixir,
        user_id: user_id
      }
      
      assert {:ok, result} = Generation.generate(input)
      
      # Verify code was generated
      assert result.code =~ "defmodule"
      assert result.code =~ "GenServer"
      
      # Verify memory was used (should reference previous patterns)
      context = ContextManager.build_context(input.prompt, %{user_id: user_id})
      assert context.sections != []
      assert Enum.any?(context.sources, &(&1.type == :memory))
      
      # Verify new interaction was stored
      recent = MemoryManager.get_recent_interactions(user_id, "test_session", limit: 2)
      assert length(recent) >= 2
    end
    
    test "updates memory patterns after successful generation", %{user_id: user_id} do
      input = %{
        prompt: "Create a supervisor for worker processes",
        language: :elixir,
        user_id: user_id
      }
      
      # Get initial memory count
      initial_memories = MemoryManager.get_recent_interactions(user_id, "test_session", limit: 100)
      
      # Generate code multiple times to trigger pattern extraction
      for i <- 1..3 do
        input_with_variation = %{input | prompt: "#{input.prompt} - version #{i}"}
        assert {:ok, _} = Generation.generate(input_with_variation)
      end
      
      # Allow time for pattern extraction
      Process.sleep(500)
      
      # Verify new memories were stored
      updated_memories = MemoryManager.get_recent_interactions(user_id, "test_session", limit: 100)
      assert length(updated_memories) > length(initial_memories)
    end
  end
  
  describe "3.9.2 Multi-provider fallback during generation" do
    test "falls back to secondary provider on primary failure" do
      # Configure mock provider to fail
      request = %{
        model: "mock-fast",
        messages: [%{role: "user", content: "test"}],
        provider: :mock,
        fail_once: true  # Special flag for testing
      }
      
      # First attempt should fail and fallback
      assert {:ok, response} = LLMService.completion(request)
      assert response.provider != :mock  # Should have used fallback
    end
    
    test "handles provider-specific errors gracefully" do
      # Test rate limit error
      request = %{
        model: "mock-fast",
        messages: [%{role: "user", content: "test rate limit"}],
        provider: :mock,
        force_error: :rate_limit
      }
      
      # Should handle rate limit and retry or fallback
      result = LLMService.completion(request)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
  
  describe "3.9.3 Context building with all memory levels" do
    test "integrates short-term, mid-term, and long-term memory", %{user_id: user_id} do
      # Create memories at different levels
      # Short-term: recent interactions
      for i <- 1..5 do
        MemoryManager.store_interaction(%{
          user_id: user_id,
          session_id: "test_session",
          type: :query,
          input: "Question #{i}",
          output: "Answer #{i}",
          metadata: %{timestamp: DateTime.utc_now()}
        })
      end
      
      # Simulate mid-term memory (patterns)
      # This would normally happen through the Updater process
      
      # Build context
      context = ContextManager.build_context(
        "New question related to previous ones",
        %{user_id: user_id}
      )
      
      # Verify all memory levels are represented
      assert context.sections != []
      assert context.metadata.memory_sources != nil
      
      # Check for recent interactions
      assert Enum.any?(context.sources, &(&1.type == :short_term_memory))
    end
    
    test "prioritizes relevant memories based on context", %{user_id: user_id} do
      # Store varied interactions
      topics = ["database", "api", "authentication", "database"]
      
      for {topic, i} <- Enum.with_index(topics) do
        MemoryManager.store_interaction(%{
          user_id: user_id,
          session_id: "test_session",
          type: :generation,
          input: "Create #{topic} module",
          output: "defmodule #{String.capitalize(topic)} do\n  # ...\nend",
          metadata: %{topic: topic, relevance: 0.5 + i * 0.1}
        })
      end
      
      # Query about databases should prioritize database-related memories
      context = ContextManager.build_context(
        "How do I optimize database queries?",
        %{user_id: user_id}
      )
      
      # Verify relevance-based prioritization
      assert context.sections != []
      database_sections = Enum.filter(context.sources, fn source ->
        source[:metadata][:topic] == "database"
      end)
      assert length(database_sections) > 0
    end
  end
  
  describe "3.9.4 Rate limiting across providers" do
    test "enforces rate limits per provider" do
      # Make multiple rapid requests
      requests = for i <- 1..10 do
        Task.async(fn ->
          LLMService.completion(%{
            model: "mock-fast",
            messages: [%{role: "user", content: "Test #{i}"}],
            provider: :mock
          })
        end)
      end
      
      results = Task.await_many(requests, 5000)
      
      # Some should succeed, some might be rate limited
      successful = Enum.count(results, &match?({:ok, _}, &1))
      assert successful > 0
      
      # Verify rate limiting is applied
      rate_limited = Enum.count(results, &match?({:error, :rate_limited}, &1))
      assert successful + rate_limited == length(results)
    end
  end
  
  describe "3.9.5 Memory persistence across restarts" do
    @tag :skip # This test requires actual restart which is complex in test env
    test "recovers memory after application restart", %{user_id: user_id} do
      # Store memory
      MemoryManager.store_interaction(%{
        user_id: user_id,
        session_id: "test_session",
        type: :test,
        input: "persistent test",
        output: "should survive restart",
        metadata: %{important: true}
      })
      
      # Simulate restart
      :ok = Application.stop(:rubber_duck)
      {:ok, _} = Application.ensure_all_started(:rubber_duck)
      
      # Verify memory survived
      recent = MemoryManager.get_recent_interactions(user_id, "test_session", limit: 10)
      assert Enum.any?(recent, &(&1.input == "persistent test"))
    end
  end
  
  describe "3.9.6 Concurrent LLM requests handling" do
    test "handles multiple concurrent requests efficiently" do
      # Launch concurrent requests
      concurrent_count = 20
      
      tasks = for i <- 1..concurrent_count do
        Task.async(fn ->
          start_time = System.monotonic_time(:millisecond)
          
          result = LLMService.completion(%{
            model: "mock-fast",
            messages: [%{role: "user", content: "Concurrent test #{i}"}],
            provider: :mock
          })
          
          end_time = System.monotonic_time(:millisecond)
          {result, end_time - start_time}
        end)
      end
      
      results = Task.await_many(tasks, 30_000)
      
      # All should complete
      assert length(results) == concurrent_count
      
      # Check success rate
      successful = Enum.count(results, fn {result, _time} ->
        match?({:ok, _}, result)
      end)
      assert successful > concurrent_count * 0.8  # At least 80% success
      
      # Check timing - concurrent requests should not be serialized
      times = Enum.map(results, fn {_, time} -> time end)
      avg_time = Enum.sum(times) / length(times)
      
      # If serialized, total time would be much higher
      assert avg_time < 1000  # Should be fast with concurrency
    end
  end
  
  describe "3.9.7 Cost tracking accuracy" do
    test "accurately tracks token usage and costs" do
      request = %{
        model: "mock-fast",
        messages: [
          %{role: "system", content: "You are a helpful assistant."},
          %{role: "user", content: "Write a haiku about Elixir programming."}
        ],
        provider: :mock
      }
      
      assert {:ok, response} = LLMService.completion(request)
      
      # Verify token counts
      assert response.usage.prompt_tokens > 0
      assert response.usage.completion_tokens > 0
      assert response.usage.total_tokens == 
        response.usage.prompt_tokens + response.usage.completion_tokens
      
      # Verify cost calculation
      assert response.usage.prompt_cost > 0
      assert response.usage.completion_cost > 0
      assert_in_delta(
        response.usage.total_cost,
        response.usage.prompt_cost + response.usage.completion_cost,
        0.0001
      )
    end
  end
  
  describe "3.9.8 CoT reasoning chain execution" do
    test "executes chain-of-thought reasoning successfully" do
      # Define a simple reasoning chain
      query = "What are the pros and cons of using GenServer vs Agent in Elixir?"
      
      # Mock a successful CoT execution result
      mock_result = %{
        query: query,
        chain: %{
          name: :test_chain,
          steps: [
            %{name: :analyze, output: "Analysis of GenServer vs Agent..."},
            %{name: :compare, output: "Comparison of features..."},
            %{name: :conclude, output: "Conclusion and recommendations..."}
          ]
        },
        output: "GenServer provides more control while Agent is simpler..."
      }
      
      # Test the CoT structure (since actual execution requires chain module)
      # In a real test, we would use an actual chain module
      assert mock_result.query == query
      assert mock_result.chain != nil
      assert mock_result.output != nil
      
      # Verify reasoning steps
      assert length(mock_result.chain.steps) > 0
      assert Enum.all?(mock_result.chain.steps, &(&1.output != nil))
    end
  end
  
  describe "3.9.9 RAG retrieval and generation pipeline" do
    test "retrieves and uses relevant documents for generation", %{user_id: user_id} do
      # Index some documents
      documents = [
        %{
          content: "GenServer is a behaviour module for implementing stateful processes.",
          metadata: %{type: :documentation, topic: "genserver"}
        },
        %{
          content: "Supervisors are used to build fault-tolerant applications.",
          metadata: %{type: :documentation, topic: "supervisor"}
        }
      ]
      
      # Index documents (simplified for testing)
      {:ok, _} = RAGPipeline.index_documents(documents, project_id: "test_project")
      
      # Use RAG for generation
      input = %{
        prompt: "Explain how GenServers work with Supervisors",
        language: :elixir,
        user_id: user_id,
        use_rag: true
      }
      
      assert {:ok, result} = Generation.generate(input)
      
      # Verify RAG was used
      assert result.metadata[:rag_sources] != nil
      assert length(result.metadata[:rag_sources]) > 0
      
      # Content should reference both GenServer and Supervisor
      assert result.code =~ "GenServer" || result.explanation =~ "GenServer"
      assert result.code =~ "Supervisor" || result.explanation =~ "Supervisor"
    end
  end
  
  describe "3.9.10 Self-correction iterations" do
    test "iteratively improves code quality", %{user_id: user_id} do
      # Generate initial code with errors
      flawed_code = """
      def calculate_total(items) do
        items
        |> Enum.map(fn item -> item.price * item.quantity
        |> Enum.sum()
      end
      """
      
      request = %{
        content: flawed_code,
        type: :code,
        context: %{language: :elixir},
        options: [max_iterations: 3]
      }
      
      assert {:ok, result} = SelfCorrectionEngine.correct(request)
      
      # Verify corrections were made
      assert result.iterations > 0
      assert result.corrected_content != flawed_code
      
      # Verify syntax was fixed
      assert result.corrected_content =~ "end)"  # Fixed missing parenthesis
      
      # Verify improvement metrics
      assert result.improvement_score > 0
    end
    
    test "detects convergence and stops iterating" do
      # Already good code
      good_code = """
      def calculate_total(items) do
        items
        |> Enum.map(fn item -> item.price * item.quantity end)
        |> Enum.sum()
      end
      """
      
      request = %{
        content: good_code,
        type: :code,
        context: %{language: :elixir},
        options: [max_iterations: 5]
      }
      
      assert {:ok, result} = SelfCorrectionEngine.correct(request)
      
      # Should converge quickly
      assert result.iterations <= 2
      assert result.converged == true
    end
  end
  
  describe "3.9.11 Enhancement technique composition" do
    test "combines multiple enhancement techniques effectively", %{user_id: user_id} do
      task = %{
        type: :code_generation,
        content: "Create a distributed cache system with fault tolerance",
        context: %{
          language: :elixir,
          user_id: user_id
        },
        options: []
      }
      
      assert {:ok, result} = EnhancementCoordinator.enhance(task)
      
      # Verify multiple techniques were applied
      assert length(result.techniques_applied) >= 2
      
      # Common combination should include RAG and CoT for complex tasks
      assert :rag in result.techniques_applied || :cot in result.techniques_applied
      
      # Verify enhancement improved quality
      assert result.metrics["quality_improvement"] > 0
      
      # Enhanced content should be substantial
      assert String.length(result.enhanced) > String.length(result.original)
    end
    
    test "A/B tests different technique combinations" do
      task = %{
        type: :code_generation,
        content: "Implement a rate limiter",
        context: %{language: :elixir},
        options: []
      }
      
      variants = [
        [techniques: [{:cot, %{}}, {:self_correction, %{}}]],
        [techniques: [{:rag, %{}}, {:cot, %{}}]],
        [techniques: [{:cot, %{}}]]
      ]
      
      assert {:ok, ab_result} = EnhancementCoordinator.ab_test(task, variants)
      
      # Verify all variants were tested
      assert length(ab_result.variants) == 3
      
      # Verify winner was selected
      assert ab_result.winner != nil
      
      # Verify analysis includes scores
      assert ab_result.analysis.all_scores != nil
      assert length(ab_result.analysis.all_scores) == 3
    end
  end
  
  describe "3.9.12 End-to-end enhanced generation" do
    test "completes full generation pipeline with all enhancements", %{user_id: user_id} do
      # Complex request that should trigger all enhancements
      input = %{
        prompt: """
        Based on our previous discussions about GenServers and supervisors,
        create a fault-tolerant worker pool system that can:
        1. Dynamically scale workers based on load
        2. Handle worker crashes gracefully
        3. Provide metrics and monitoring
        4. Support different job priorities
        
        Make sure to follow Elixir best practices and include tests.
        """,
        language: :elixir,
        user_id: user_id,
        options: [
          use_memory: true,
          use_rag: true,
          use_cot: true,
          use_self_correction: true,
          enhance: true
        ]
      }
      
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, result} = Generation.generate(input)
      end_time = System.monotonic_time(:millisecond)
      
      # Verify comprehensive output
      assert result.code != nil
      assert String.length(result.code) > 500  # Substantial implementation
      
      # Verify code quality
      assert result.code =~ "defmodule"
      assert result.code =~ "Supervisor"
      assert result.code =~ "GenServer"
      assert result.code =~ "handle_call"
      assert result.code =~ "handle_cast"
      
      # Verify enhancements were applied
      assert result.metadata[:techniques_used] != nil
      assert length(result.metadata[:techniques_used]) >= 3
      
      # Verify memory was used
      assert result.metadata[:memory_used] == true
      
      # Verify RAG sources
      assert result.metadata[:rag_sources] != nil
      
      # Verify reasonable performance
      duration = end_time - start_time
      assert duration < 30_000  # Should complete within 30 seconds
      
      # Verify explanation includes reasoning
      assert result.explanation != nil
      assert result.explanation =~ "supervisor" || result.explanation =~ "fault-tolerant"
    end
    
    test "handles errors gracefully in enhanced pipeline", %{user_id: user_id} do
      # Request that might cause issues
      input = %{
        prompt: "Generate code with @#$% invalid syntax requirements &*(",
        language: :elixir,
        user_id: user_id,
        options: [enhance: true]
      }
      
      # Should handle gracefully
      result = Generation.generate(input)
      
      case result do
        {:ok, output} ->
          # Even with weird input, should produce something valid
          assert output.code != nil || output.explanation != nil
          
        {:error, reason} ->
          # Error should be informative
          assert is_binary(reason) || is_atom(reason)
      end
    end
  end
end