defmodule RubberDuck.Planning.TaskDecomposerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Planning.TaskDecomposer

  describe "init/1" do
    test "initializes with default configuration" do
      assert {:ok, state} = TaskDecomposer.init([])

      assert state.default_strategy == :hierarchical
      assert state.max_depth == 5
      assert state.min_task_size == 1
      assert state.validation_enabled == true
    end

    test "initializes with custom configuration" do
      config = [
        default_strategy: :linear,
        max_depth: 3,
        validation_enabled: false
      ]

      assert {:ok, state} = TaskDecomposer.init(config)

      assert state.default_strategy == :linear
      assert state.max_depth == 3
      assert state.validation_enabled == false
    end
  end

  describe "capabilities/0" do
    test "returns correct capabilities" do
      capabilities = TaskDecomposer.capabilities()

      assert :task_decomposition in capabilities
      assert :dependency_analysis in capabilities
      assert :complexity_estimation in capabilities
    end
  end

  describe "execute/2 with linear strategy" do
    setup do
      {:ok, state} = TaskDecomposer.init(validation_enabled: false)
      {:ok, state: state}
    end

    test "decomposes simple linear task", %{state: state} do
      input = %{
        query: "Write a function to calculate fibonacci numbers",
        strategy: :linear
      }

      # Mock LLM response
      mock_llm_response()

      assert {:ok, result} = TaskDecomposer.execute(input, state)

      assert result.strategy == :linear
      assert is_list(result.tasks)
      assert length(result.tasks) > 0
      assert is_list(result.dependencies)
    end
  end

  describe "execute/2 with hierarchical strategy" do
    setup do
      {:ok, state} = TaskDecomposer.init(validation_enabled: false)
      {:ok, state: state}
    end

    test "decomposes complex hierarchical task", %{state: state} do
      input = %{
        query: "Build a user authentication system with email verification",
        strategy: :hierarchical
      }

      # Mock CoT response
      mock_cot_response()

      assert {:ok, result} = TaskDecomposer.execute(input, state)

      assert result.strategy == :hierarchical
      assert is_list(result.tasks)
      assert result.metadata.total_tasks > 0
    end
  end

  describe "dependency analysis" do
    test "detects circular dependencies" do
      tasks = [
        %{"position" => 0, "name" => "Task A"},
        %{"position" => 1, "name" => "Task B"},
        %{"position" => 2, "name" => "Task C"}
      ]

      circular_deps = [
        %{from: "task_0", to: "task_1"},
        %{from: "task_1", to: "task_2"},
        # Creates cycle
        %{from: "task_2", to: "task_0"}
      ]

      # Test cycle detection logic
      assert TaskDecomposer.detect_cycles(circular_deps, tasks) == {:error, :cycle_detected}
    end

    test "allows valid dependencies" do
      tasks = [
        %{"position" => 0, "name" => "Task A"},
        %{"position" => 1, "name" => "Task B"},
        %{"position" => 2, "name" => "Task C"}
      ]

      valid_deps = [
        %{from: "task_0", to: "task_1"},
        %{from: "task_1", to: "task_2"}
      ]

      assert TaskDecomposer.detect_cycles(valid_deps, tasks) == :ok
    end
  end

  describe "validation" do
    setup do
      {:ok, state} = TaskDecomposer.init(validation_enabled: true)
      {:ok, state: state}
    end

    test "validates task completeness", %{state: state} do
      incomplete_tasks = [
        %{
          "name" => "Task without description",
          "complexity" => "medium",
          "success_criteria" => %{"criteria" => ["Done"]}
        }
      ]

      complete_tasks = [
        %{
          "name" => "Complete task",
          "description" => "This task has all required fields",
          "complexity" => "medium",
          "success_criteria" => %{"criteria" => ["All tests pass"]}
        }
      ]

      # Test validation logic
      assert {:error, {:incomplete_tasks, _}} =
               TaskDecomposer.validate_task_completeness(incomplete_tasks)

      assert {:ok, :complete} =
               TaskDecomposer.validate_task_completeness(complete_tasks)
    end

    test "validates complexity balance", %{state: state} do
      unbalanced_tasks = [
        %{"complexity" => "very_complex"},
        %{"complexity" => "very_complex"},
        %{"complexity" => "very_complex"},
        %{"complexity" => "simple"}
      ]

      balanced_tasks = [
        %{"complexity" => "simple"},
        %{"complexity" => "medium"},
        %{"complexity" => "complex"},
        %{"complexity" => "simple"}
      ]

      assert {:error, :too_many_complex_tasks} =
               TaskDecomposer.validate_complexity_balance(unbalanced_tasks)

      assert {:ok, :balanced} =
               TaskDecomposer.validate_complexity_balance(balanced_tasks)
    end
  end

  # Helper functions for mocking

  defp mock_llm_response do
    # In real tests, you would use a mocking library
    # This is a simplified version
    :ok
  end

  defp mock_cot_response do
    # In real tests, you would use a mocking library
    # This is a simplified version
    :ok
  end
end
