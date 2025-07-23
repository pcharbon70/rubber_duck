defmodule RubberDuck.Planning.Execution.ThoughtGeneratorTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Planning.Execution.ThoughtGenerator
  alias RubberDuck.Planning.Task

  describe "generate_thought/2" do
    test "generates thought for simple task" do
      task = build_simple_task()
      state = build_execution_state()

      thought = ThoughtGenerator.generate_thought(task, state)

      assert thought.task_id == task.id
      assert thought.reasoning
      assert thought.approach in [:direct_execution, :careful_execution]
      assert thought.confidence >= 0.0 and thought.confidence <= 1.0
    end

    test "generates careful approach for complex task" do
      task = build_complex_task()
      state = build_execution_state()

      thought = ThoughtGenerator.generate_thought(task, state)

      assert thought.approach in [:careful_execution, :validate_then_execute]
      assert thought.confidence <= 0.8
    end

    test "suggests retry with fixes for previously failed task" do
      task = build_simple_task()
      state = build_state_with_failures(task.id)

      thought = ThoughtGenerator.generate_thought(task, state)

      assert thought.approach in [:fix_and_retry, :retry_with_modifications]
      assert String.contains?(thought.reasoning, "previous failure")
    end

    test "generates extended timeout approach for slow tasks" do
      task = build_slow_task()
      state = build_execution_state()

      thought = ThoughtGenerator.generate_thought(task, state)

      assert thought.approach in [:execute_with_extended_timeout, :careful_execution]
      assert String.contains?(thought.reasoning, "timeout")
    end
  end

  describe "confidence calculation" do
    test "higher confidence for simple tasks with no failures" do
      task = %Task{
        id: "simple",
        complexity: :simple,
        dependencies: []
      }

      state = build_execution_state()

      thought = ThoughtGenerator.generate_thought(task, state)

      assert thought.confidence > 0.8
    end

    test "lower confidence for complex tasks with dependencies" do
      task = %Task{
        id: "complex",
        complexity: :very_complex,
        dependencies: ["dep1", "dep2", "dep3"]
      }

      state = build_execution_state()

      thought = ThoughtGenerator.generate_thought(task, state)

      assert thought.confidence < 0.7
    end

    test "very low confidence for tasks with multiple failures" do
      task = build_simple_task()
      state = build_state_with_multiple_failures(task.id, 3)

      thought = ThoughtGenerator.generate_thought(task, state)

      assert thought.confidence < 0.5
    end
  end

  describe "reasoning generation" do
    test "includes task complexity in reasoning" do
      task = build_complex_task()
      state = build_execution_state()

      thought = ThoughtGenerator.generate_thought(task, state)

      assert String.contains?(thought.reasoning, "complex")
    end

    test "mentions dependencies in reasoning" do
      task = %Task{
        id: "dependent",
        dependencies: ["task1", "task2"]
      }

      state = build_execution_state()

      thought = ThoughtGenerator.generate_thought(task, state)

      assert String.contains?(thought.reasoning, "dependencies")
    end

    test "references failure history in reasoning" do
      task = build_simple_task()
      state = build_state_with_failures(task.id)

      thought = ThoughtGenerator.generate_thought(task, state)

      assert String.contains?(thought.reasoning, "failed") or
               String.contains?(thought.reasoning, "previous")
    end
  end

  describe "approach selection" do
    test "selects direct execution for ideal conditions" do
      task = %Task{
        id: "ideal",
        complexity: :simple,
        dependencies: []
      }

      state = %{
        completed_tasks: MapSet.new(),
        failed_tasks: MapSet.new(),
        history: %{failures: %{}, retries: %{}}
      }

      thought = ThoughtGenerator.generate_thought(task, state)

      assert thought.approach == :direct_execution
    end

    test "selects validation approach for tasks with many dependencies" do
      task = %Task{
        id: "many_deps",
        dependencies: ["a", "b", "c", "d", "e"]
      }

      state = build_execution_state()

      thought = ThoughtGenerator.generate_thought(task, state)

      assert thought.approach in [:validate_then_execute, :careful_execution]
    end
  end

  # Helper functions

  defp build_simple_task do
    %Task{
      id: "simple_task",
      name: "Simple Task",
      description: "A simple task to execute",
      complexity: :simple,
      dependencies: []
    }
  end

  defp build_complex_task do
    %Task{
      id: "complex_task",
      name: "Complex Task",
      description: "A very complex task requiring careful execution",
      complexity: :very_complex,
      dependencies: ["dep1", "dep2"]
    }
  end

  defp build_slow_task do
    %Task{
      id: "slow_task",
      name: "Slow Task",
      description: "A task that takes a long time",
      complexity: :medium,
      metadata: %{expected_duration: 300_000}
    }
  end

  defp build_execution_state do
    %{
      completed_tasks: MapSet.new(["completed1", "completed2"]),
      failed_tasks: MapSet.new(),
      history: %{
        failures: %{},
        retries: %{},
        execution_times: %{}
      }
    }
  end

  defp build_state_with_failures(task_id) do
    %{
      completed_tasks: MapSet.new(),
      failed_tasks: MapSet.new([task_id]),
      history: %{
        failures: %{
          task_id => [
            %{error: {:error, :timeout}, timestamp: DateTime.utc_now()}
          ]
        },
        retries: %{task_id => 1},
        execution_times: %{}
      }
    }
  end

  defp build_state_with_multiple_failures(task_id, count) do
    failures =
      Enum.map(1..count, fn i ->
        %{
          error: {:error, "failure_#{i}"},
          timestamp: DateTime.utc_now()
        }
      end)

    %{
      completed_tasks: MapSet.new(),
      failed_tasks: MapSet.new([task_id]),
      history: %{
        failures: %{task_id => failures},
        retries: %{task_id => count},
        execution_times: %{}
      }
    }
  end
end
