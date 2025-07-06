defmodule RubberDuck.Integration.EnhancementIntegrationTest do
  use ExUnit.Case
  
  alias RubberDuck.Enhancement.Coordinator
  
  @moduletag :integration
  
  setup do
    # Ensure all required services are running
    # The application supervisor should have started everything
    :ok
  end
  
  describe "end-to-end enhancement flow" do
    test "enhances code generation with multiple techniques" do
      task = %{
        type: :code_generation,
        content: """
        Create a GenServer that manages a counter with increment and decrement operations.
        It should handle concurrent access and provide a way to get the current value.
        """,
        context: %{language: :elixir},
        options: []
      }
      
      assert {:ok, result} = Coordinator.enhance(task, timeout: 30_000)
      
      # Should have applied multiple techniques
      assert length(result.techniques_applied) >= 2
      
      # Enhanced content should be different and longer
      assert result.enhanced != result.original
      assert String.length(result.enhanced) > String.length(result.original)
      
      # Should have quality improvement
      assert result.metrics["quality_improvement"] > 0
      
      # Should contain GenServer code
      assert result.enhanced =~ "GenServer"
      assert result.enhanced =~ "def handle_call"
    end
    
    test "enhances text with reasoning" do
      task = %{
        type: :question_answering,
        content: "Explain why Elixir is good for building concurrent systems",
        context: %{},
        options: []
      }
      
      assert {:ok, result} = Coordinator.enhance(task, timeout: 20_000)
      
      # Should use CoT for reasoning
      assert :cot in result.techniques_applied
      
      # Should produce a reasonable explanation
      assert String.length(result.enhanced) > 100
      assert result.enhanced =~ "concurrent" || result.enhanced =~ "Elixir"
    end
    
    test "corrects code with syntax errors" do
      task = %{
        type: :debugging,
        content: """
        def calculate_total(items) do
          items
          |> Enum.map(fn item -> item.price * item.quantity
          |> Enum.sum()
        end
        """,
        context: %{language: :elixir},
        options: []
      }
      
      assert {:ok, result} = Coordinator.enhance(task, timeout: 20_000)
      
      # Should use self-correction
      assert :self_correction in result.techniques_applied
      
      # Should fix the syntax error
      assert result.enhanced != result.original
      assert result.enhanced =~ "end)"  # Fixed the missing closing paren
    end
    
    test "uses RAG for context-aware enhancement" do
      task = %{
        type: :code_analysis,
        content: "How can I improve the performance of this code based on Elixir best practices?",
        context: %{
          code: """
          def process_list(list) do
            list
            |> Enum.map(&expensive_operation/1)
            |> Enum.filter(&(&1 != nil))
            |> Enum.take(10)
          end
          """
        },
        options: []
      }
      
      assert {:ok, result} = Coordinator.enhance(task, timeout: 25_000)
      
      # Should use RAG to retrieve relevant context
      assert :rag in result.techniques_applied
      
      # Should provide performance suggestions
      assert result.enhanced =~ "performance" || result.enhanced =~ "optimize"
    end
  end
  
  describe "A/B testing functionality" do
    test "compares different technique combinations" do
      task = %{
        type: :code_generation,
        content: "Create a function to validate email addresses",
        context: %{language: :elixir},
        options: []
      }
      
      variants = [
        [techniques: [{:cot, %{}}]],
        [techniques: [{:rag, %{}}, {:cot, %{}}]],
        [techniques: [{:cot, %{}}, {:self_correction, %{}}]]
      ]
      
      assert {:ok, ab_result} = Coordinator.ab_test(task, variants)
      
      # Should have results for all variants
      assert length(ab_result.variants) == 3
      
      # Should identify a winner
      assert ab_result.winner != nil
      
      # Should have analysis data
      assert ab_result.analysis.all_scores != nil
      assert length(ab_result.analysis.all_scores) == 3
    end
  end
  
  describe "pipeline types" do
    test "sequential pipeline maintains order" do
      task = %{
        type: :code_generation,
        content: "Simple function",
        context: %{},
        options: []
      }
      
      opts = [
        techniques: [{:rag, %{}}, {:cot, %{}}, {:self_correction, %{}}],
        pipeline_type: :sequential
      ]
      
      assert {:ok, result} = Coordinator.enhance(task, opts)
      
      # Techniques should be applied in order
      assert result.techniques_applied == [:rag, :cot, :self_correction]
      assert result.metadata.pipeline_type == :sequential
    end
    
    test "parallel pipeline executes concurrently" do
      task = %{
        type: :documentation,
        content: "Document this API endpoint",
        context: %{},
        options: []
      }
      
      opts = [
        techniques: [{:rag, %{}}, {:cot, %{}}],
        pipeline_type: :parallel
      ]
      
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, result} = Coordinator.enhance(task, opts)
      duration = System.monotonic_time(:millisecond) - start_time
      
      # Parallel execution should be faster than sequential
      assert result.metadata.pipeline_type == :parallel
      assert duration < 10_000  # Should complete reasonably fast
    end
  end
  
  describe "metrics and monitoring" do
    test "collects comprehensive metrics" do
      task = %{
        type: :code_generation,
        content: "Create a module",
        context: %{},
        options: []
      }
      
      assert {:ok, result} = Coordinator.enhance(task)
      
      # Should have all key metrics
      assert result.metrics["execution_time_ms"] > 0
      assert result.metrics["quality_improvement"] >= 0
      assert result.metrics["techniques_count"] > 0
      assert result.metrics["content_length_original"] > 0
      assert result.metrics["content_length_enhanced"] > 0
    end
    
    test "tracks statistics across enhancements" do
      initial_stats = Coordinator.get_stats()
      
      # Run a few enhancements
      tasks = [
        %{type: :text, content: "Test 1", context: %{}, options: []},
        %{type: :code_generation, content: "Test 2", context: %{}, options: []},
        %{type: :documentation, content: "Test 3", context: %{}, options: []}
      ]
      
      Enum.each(tasks, fn task ->
        {:ok, _} = Coordinator.enhance(task, timeout: 10_000)
      end)
      
      # Wait for async updates
      Process.sleep(500)
      
      final_stats = Coordinator.get_stats()
      
      # Stats should be updated
      assert final_stats.total_enhancements >= initial_stats.total_enhancements + 3
      assert map_size(final_stats.technique_usage) > 0
    end
  end
  
  describe "error handling and resilience" do
    test "handles technique failures gracefully" do
      # Task that might cause issues
      task = %{
        type: :invalid_type,
        content: "",
        context: %{},
        options: []
      }
      
      # Should not crash
      result = Coordinator.enhance(task, timeout: 5000)
      assert match?({:ok, _} | {:error, _}, result)
    end
    
    test "respects timeouts" do
      task = %{
        type: :code_generation,
        content: String.duplicate("Generate complex code. ", 100),
        context: %{},
        options: []
      }
      
      # Very short timeout
      start_time = System.monotonic_time(:millisecond)
      _result = Coordinator.enhance(task, timeout: 100)
      duration = System.monotonic_time(:millisecond) - start_time
      
      # Should timeout quickly
      assert duration < 1000
    end
  end
end