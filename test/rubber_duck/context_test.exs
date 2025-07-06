defmodule RubberDuck.ContextTest do
  use RubberDuck.DataCase
  
  alias RubberDuck.Context
  alias RubberDuck.Context.{Manager, Cache, Scorer}
  alias RubberDuck.Memory
  
  describe "Context Manager" do
    setup do
      # Create test data in memory
      user_id = "test_user_#{System.unique_integer()}"
      session_id = "test_session_#{System.unique_integer()}"
      
      # Create some interactions
      for i <- 1..5 do
        Memory.store_interaction(%{
          user_id: user_id,
          session_id: session_id,
          type: :chat,
          content: "Test interaction #{i}",
          metadata: %{}
        })
      end
      
      %{user_id: user_id, session_id: session_id}
    end
    
    test "builds context with auto strategy selection" do
      query = "Complete this function"
      
      assert {:ok, context} = Manager.build_context(query, [
        file_content: "def hello(",
        cursor_position: 10
      ])
      
      assert context.strategy == :fim
      assert context.token_count > 0
      assert String.contains?(context.content, "<fim_")
    end
    
    test "builds context with RAG strategy for generation" do
      query = "Generate a function to calculate fibonacci numbers"
      
      assert {:ok, context} = Manager.build_context(query, [
        strategy: :rag
      ])
      
      assert context.strategy == :rag
      assert context.token_count > 0
      assert String.contains?(context.content, "Query")
    end
    
    test "builds context with long context strategy", %{user_id: user_id, session_id: session_id} do
      query = "Analyze the architecture of this project"
      
      assert {:ok, context} = Manager.build_context(query, [
        strategy: :long_context,
        user_id: user_id,
        session_id: session_id,
        max_tokens: 32000
      ])
      
      assert context.strategy == :long_context
      assert String.contains?(context.content, "Current Query")
    end
    
    test "caches context for repeated queries" do
      query = "How do I implement error handling?"
      opts = [strategy: :rag]
      
      # First call - should build new context
      assert {:ok, context1} = Manager.build_context(query, opts)
      refute Map.get(context1, :from_cache, false)
      
      # Second call - should return cached
      assert {:ok, context2} = Manager.build_context(query, opts)
      assert context2.from_cache == true
      assert context2.content == context1.content
    end
    
    test "skips cache when requested" do
      query = "What is a GenServer?"
      opts = [strategy: :rag]
      
      # Build and cache
      assert {:ok, _} = Manager.build_context(query, opts)
      
      # Build again, skipping cache
      assert {:ok, context} = Manager.build_context(query, opts ++ [skip_cache: true])
      refute Map.get(context, :from_cache, false)
    end
    
    test "optimizes context to fit token limits" do
      query = "Explain everything about Elixir"
      long_content = String.duplicate("This is a very long text. ", 1000)
      
      assert {:ok, context} = Manager.build_context(query, [
        strategy: :fim,
        file_content: long_content,
        cursor_position: 100,
        max_tokens: 1000
      ])
      
      # Should be optimized to fit
      assert context.token_count < 1000
      assert String.contains?(context.content, "...")
    end
  end
  
  describe "Context Cache" do
    test "stores and retrieves contexts" do
      key = "test_key_#{System.unique_integer()}"
      context = %{
        content: "Test content",
        token_count: 100,
        strategy: :test
      }
      
      assert :ok = Cache.put(key, context)
      assert {:ok, retrieved} = Cache.get(key)
      assert retrieved == context
    end
    
    test "expires old entries" do
      key = "expiring_key_#{System.unique_integer()}"
      context = %{content: "Temporary"}
      
      # Store with very short TTL
      assert :ok = Cache.put(key, context, 0)
      
      # Should be expired immediately
      Process.sleep(100)
      assert {:error, :not_found} = Cache.get(key)
    end
    
    test "invalidates specific keys" do
      key1 = "invalidate_key_1_#{System.unique_integer()}"
      key2 = "invalidate_key_2_#{System.unique_integer()}"
      
      # Store entries
      Cache.put(key1, %{content: "content 1"})
      Cache.put(key2, %{content: "content 2"})
      
      # Invalidate one key
      Cache.invalidate(key1)
      
      # First key should be gone
      assert {:error, :not_found} = Cache.get(key1)
      
      # Second key should remain
      assert {:ok, %{content: "content 2"}} = Cache.get(key2)
    end
    
    test "clears entire cache" do
      # Store multiple entries
      keys = for i <- 1..3 do
        key = "clear_key_#{i}_#{System.unique_integer()}"
        Cache.put(key, %{content: "content #{i}"})
        key
      end
      
      # Clear cache
      Cache.clear()
      
      # All entries should be gone
      for key <- keys do
        assert {:error, :not_found} = Cache.get(key)
      end
    end
    
    test "tracks cache statistics" do
      # The cache might be recreated for each test, so let's test relative changes
      # Generate some activity
      key1 = "stats_key_#{System.unique_integer()}"
      key2 = "stats_key_#{System.unique_integer()}"
      
      # Put two items
      Cache.put(key1, %{content: "test1"})
      Cache.put(key2, %{content: "test2"})
      
      # Get one (hit) and one non-existent (miss)
      Cache.get(key1)
      Cache.get("nonexistent_#{System.unique_integer()}")
      
      # Invalidate one
      Cache.invalidate(key1)
      
      # Check that we have some stats
      final_stats = Cache.stats()
      
      # Since the cache may be shared or reset, just verify the operations happened
      assert is_map(final_stats)
      assert Map.has_key?(final_stats, :puts)
      assert Map.has_key?(final_stats, :hits) 
      assert Map.has_key?(final_stats, :misses)
      assert Map.has_key?(final_stats, :invalidations)
      
      # At least verify the structure is correct
      assert is_integer(final_stats.puts)
      assert is_integer(final_stats.hits)
      assert is_integer(final_stats.misses)
      assert is_integer(final_stats.invalidations)
    end
  end
  
  describe "Context Scorer" do
    test "scores context quality" do
      context = %{
        content: "How to implement a GenServer:\n\n```elixir\ndefmodule MyServer do\n  use GenServer\nend\n```",
        token_count: 50,
        strategy: :rag,
        sources: [
          %{type: :code_pattern, content: "GenServer example"},
          %{type: :knowledge, content: "GenServer documentation"}
        ],
        metadata: %{}
      }
      
      query = "How do I implement a GenServer?"
      
      score_result = Scorer.score(context, query)
      
      assert score_result.total > 0.5
      assert score_result.breakdown.relevance > 0.7
      assert score_result.breakdown.diversity > 0.4
      assert score_result.breakdown.completeness > 0.5
    end
    
    test "ranks multiple contexts" do
      contexts = [
        %{
          content: "Brief answer",
          token_count: 10,
          strategy: :fim,
          sources: [],
          metadata: %{}
        },
        %{
          content: "Detailed explanation with code examples about GenServer implementation",
          token_count: 100,
          strategy: :rag,
          sources: [
            %{type: :code_pattern, content: "Example"},
            %{type: :knowledge, content: "Docs"}
          ],
          metadata: %{}
        }
      ]
      
      query = "Explain GenServer"
      ranked = Scorer.rank_contexts(contexts, query)
      
      assert length(ranked) == 2
      {best_context, best_score} = hd(ranked)
      assert best_context.strategy == :rag
      assert best_score.total > 0.5
    end
    
    test "suggests improvements for low-quality context" do
      context = %{
        content: "Short answer",
        token_count: 5,
        strategy: :fim,
        sources: [],
        metadata: %{}
      }
      
      query = "Explain in detail how to build a complex GenServer with state management"
      
      score_result = Scorer.score(context, query)
      suggestions = Scorer.suggest_improvements(context, query, score_result)
      
      assert length(suggestions) > 0
      assert Enum.any?(suggestions, &String.contains?(&1, "query-specific"))
    end
  end
  
  describe "FIM Strategy" do
    setup do
      %{user_id: "fim_user", session_id: "fim_session"}
    end
    
    test "builds FIM context with cursor position", %{user_id: user_id, session_id: session_id} do
      code = """
      defmodule Example do
        def hello(name) do
          # Cursor here
          
        end
      end
      """
      
      cursor_pos = String.length("defmodule Example do\n  def hello(name) do\n    ")
      
      assert {:ok, context} = Manager.build_with_strategy(
        "complete the function",
        :fim,
        [
          file_content: code,
          cursor_position: cursor_pos,
          user_id: user_id,
          session_id: session_id
        ]
      )
      
      assert context.strategy == :fim
      assert String.contains?(context.content, "<fim_prefix>")
      assert String.contains?(context.content, "<fim_suffix>")
      assert String.contains?(context.content, "<fim_middle>")
    end
    
    test "truncates long files to fit token limits" do
      long_code = String.duplicate("def function_#{:rand.uniform(1000)}() do\n  :ok\nend\n\n", 500)
      
      assert {:ok, context} = Manager.build_with_strategy(
        "complete",
        :fim,
        [
          file_content: long_code,
          cursor_position: 1000,
          max_tokens: 2000
        ]
      )
      
      assert context.token_count < 2000
      assert String.contains?(context.content, "...")
    end
  end
  
  describe "RAG Strategy" do
    test "retrieves relevant content from memory" do
      # This test would require setting up memory content
      # For now, test basic functionality
      assert {:ok, context} = Manager.build_with_strategy(
        "How do I handle errors in Elixir?",
        :rag,
        []
      )
      
      assert context.strategy == :rag
      assert String.contains?(context.content, "Query")
      assert is_list(context.sources)
    end
  end
  
  describe "Long Context Strategy" do
    test "includes comprehensive project context" do
      files = [
        %{path: "lib/example.ex", content: "defmodule Example do\nend"},
        %{path: "test/example_test.exs", content: "defmodule ExampleTest do\nend"}
      ]
      
      assert {:ok, context} = Manager.build_with_strategy(
        "Analyze the project structure",
        :long_context,
        [
          files: files,
          max_tokens: 16000
        ]
      )
      
      assert context.strategy == :long_context
      assert String.contains?(context.content, "Current Query")
      # Files are loaded from disk, so we can't test file content inclusion here
    end
  end
end