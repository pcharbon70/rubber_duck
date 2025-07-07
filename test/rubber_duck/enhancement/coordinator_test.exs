defmodule RubberDuck.Enhancement.CoordinatorTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Enhancement.Coordinator

  setup do
    # Coordinator is already started by the application supervisor
    :ok
  end

  describe "enhance/2" do
    test "enhances content with default technique selection" do
      task = %{
        type: :code_generation,
        content: "Create a function that calculates fibonacci numbers",
        context: %{language: :elixir},
        options: []
      }

      assert {:ok, result} = Coordinator.enhance(task)
      assert result.enhanced != ""
      assert result.original == task.content
      assert length(result.techniques_applied) > 0
      assert is_map(result.metrics)
      assert result.metrics["quality_improvement"] >= 0
    end

    test "uses specified techniques when provided" do
      task = %{
        type: :text,
        content: "Explain the concept of recursion",
        context: %{},
        options: []
      }

      opts = [techniques: [{:cot, %{chain_type: :explanation}}]]

      assert {:ok, result} = Coordinator.enhance(task, opts)
      assert :cot in result.techniques_applied
      assert result.enhanced != ""
    end

    test "applies sequential pipeline by default" do
      task = %{
        type: :code_analysis,
        content: "def add(a, b), do: a + b",
        context: %{language: :elixir},
        options: []
      }

      assert {:ok, result} = Coordinator.enhance(task)
      assert result.metadata.pipeline_type == :sequential
    end

    test "handles parallel pipeline when specified" do
      task = %{
        type: :documentation,
        content: "Document the user authentication flow",
        context: %{},
        options: []
      }

      opts = [pipeline_type: :parallel]

      assert {:ok, result} = Coordinator.enhance(task, opts)
      assert result.metadata.pipeline_type == :parallel
    end

    test "respects timeout option" do
      task = %{
        type: :code_generation,
        content: "Generate a complex algorithm",
        context: %{},
        options: []
      }

      # This should work with a reasonable timeout
      assert {:ok, _result} = Coordinator.enhance(task, timeout: 5000)
    end

    test "handles enhancement errors gracefully" do
      task = %{
        type: :invalid_type,
        content: "",
        context: %{},
        options: []
      }

      # Should either succeed with minimal enhancement or return error
      result = Coordinator.enhance(task)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "ab_test/2" do
    test "runs A/B test with multiple variants" do
      task = %{
        type: :code_generation,
        content: "Create a sorting algorithm",
        context: %{language: :elixir},
        options: []
      }

      variants = [
        [techniques: [{:cot, %{}}, {:self_correction, %{}}]],
        [techniques: [{:rag, %{}}, {:cot, %{}}]],
        [pipeline_type: :parallel]
      ]

      assert {:ok, result} = Coordinator.ab_test(task, variants)
      assert length(result.variants) == 3
      assert result.analysis.winner != nil
      assert is_list(result.analysis.all_scores)
    end

    test "handles variant failures in A/B test" do
      task = %{
        type: :code_generation,
        content: "Test content",
        context: %{},
        options: []
      }

      variants = [
        [techniques: [{:invalid_technique, %{}}]],
        [techniques: [{:cot, %{}}]]
      ]

      assert {:ok, result} = Coordinator.ab_test(task, variants)
      assert Enum.any?(result.variants, & &1.success)
    end
  end

  describe "get_stats/0" do
    test "returns enhancement statistics" do
      stats = Coordinator.get_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :total_enhancements)
      assert Map.has_key?(stats, :technique_usage)
      assert Map.has_key?(stats, :avg_improvement)
      assert Map.has_key?(stats, :errors)
    end

    test "stats update after enhancement" do
      initial_stats = Coordinator.get_stats()

      task = %{
        type: :text,
        content: "Test content",
        context: %{},
        options: []
      }

      {:ok, _} = Coordinator.enhance(task)

      # Give some time for async update
      Process.sleep(100)

      updated_stats = Coordinator.get_stats()
      assert updated_stats.total_enhancements > initial_stats.total_enhancements
    end
  end

  describe "update_config/1" do
    test "updates configuration at runtime" do
      new_config = %{
        default_pipeline_type: :parallel,
        max_parallel_techniques: 5
      }

      assert :ok = Coordinator.update_config(new_config)

      # Config should affect subsequent enhancements
      task = %{
        type: :text,
        content: "Test",
        context: %{},
        options: []
      }

      {:ok, result} = Coordinator.enhance(task)
      # The effect would be visible in the pipeline type
      assert result.metadata.pipeline_type == :parallel
    end
  end

  describe "enhancement techniques integration" do
    test "CoT integration works correctly" do
      task = %{
        type: :question_answering,
        content: "Why is the sky blue?",
        context: %{},
        options: []
      }

      opts = [techniques: [{:cot, %{chain_type: :explanation}}]]

      {:ok, result} = Coordinator.enhance(task, opts)
      assert Map.has_key?(result.context || %{}, :cot_chain)
    end

    test "RAG integration retrieves relevant content" do
      task = %{
        type: :code_generation,
        content: "Create a GenServer module",
        context: %{language: :elixir},
        options: []
      }

      opts = [techniques: [{:rag, %{retrieval_strategy: :hybrid}}]]

      {:ok, result} = Coordinator.enhance(task, opts)
      assert result.enhanced != ""
    end

    test "Self-correction improves content iteratively" do
      task = %{
        type: :code_generation,
        # Intentional syntax error
        content: "def add(a, b do a + b",
        context: %{language: :elixir},
        options: []
      }

      opts = [
        techniques: [{:self_correction, %{strategies: [:syntax]}}],
        max_iterations: 2
      ]

      {:ok, result} = Coordinator.enhance(task, opts)
      assert result.enhanced != task.content
      assert result.metadata[:iterations] > 0
    end
  end

  describe "pipeline execution" do
    test "sequential pipeline executes in order" do
      task = %{
        type: :code_generation,
        content: "Generate a function",
        context: %{},
        options: []
      }

      opts = [
        techniques: [
          {:rag, %{}},
          {:cot, %{}},
          {:self_correction, %{}}
        ],
        pipeline_type: :sequential
      ]

      {:ok, result} = Coordinator.enhance(task, opts)
      assert length(result.techniques_applied) == 3
      assert result.techniques_applied == [:rag, :cot, :self_correction]
    end

    test "conditional pipeline evaluates conditions" do
      task = %{
        type: :code_generation,
        content: "def broken_function do error end",
        context: %{},
        options: []
      }

      opts = [
        pipeline_type: :conditional,
        techniques: [{:self_correction, %{}}]
      ]

      {:ok, result} = Coordinator.enhance(task, opts)
      assert result.enhanced != task.content
    end
  end
end
