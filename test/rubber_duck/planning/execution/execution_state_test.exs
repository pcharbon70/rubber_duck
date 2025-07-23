defmodule RubberDuck.Planning.Execution.ExecutionStateTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Planning.Execution.ExecutionState
  alias RubberDuck.Planning.Task

  describe "new/1" do
    test "creates new execution state" do
      execution_id = "test_execution"

      state = ExecutionState.new(execution_id)

      assert state.execution_id == execution_id
      assert MapSet.size(state.all_tasks) == 0
      assert MapSet.size(state.completed_tasks) == 0
      assert MapSet.size(state.failed_tasks) == 0
      assert map_size(state.current_tasks) == 0
      assert state.created_at
      assert state.updated_at
    end
  end

  describe "initialize/2" do
    test "initializes state with tasks" do
      state = ExecutionState.new("test")

      tasks = [
        %Task{id: "task1", dependencies: []},
        %Task{id: "task2", dependencies: ["task1"]},
        %Task{id: "task3", dependencies: ["task2"]}
      ]

      initialized_state = ExecutionState.initialize(state, tasks)

      assert MapSet.size(initialized_state.all_tasks) == 3
      assert MapSet.member?(initialized_state.all_tasks, "task1")
      assert MapSet.member?(initialized_state.all_tasks, "task2")
      assert MapSet.member?(initialized_state.all_tasks, "task3")
      assert initialized_state.task_dependencies["task2"] == ["task1"]
      assert initialized_state.task_dependencies["task3"] == ["task2"]
    end
  end

  describe "task execution lifecycle" do
    test "starts, completes, and tracks task" do
      state =
        ExecutionState.new("test")
        |> ExecutionState.initialize([%Task{id: "task1", dependencies: []}])

      # Start task
      process_ref = make_ref()
      state = ExecutionState.start_task(state, "task1", process_ref)

      assert Map.has_key?(state.current_tasks, "task1")
      assert state.current_tasks["task1"].process_ref == process_ref
      assert state.current_tasks["task1"].started_at

      # Complete task
      result = %{status: :success, data: "completed"}
      state = ExecutionState.complete_task(state, "task1", result)

      assert MapSet.member?(state.completed_tasks, "task1")
      assert not Map.has_key?(state.current_tasks, "task1")
      assert state.metadata[{:task_result, "task1"}] == result
    end

    test "handles task failure" do
      state =
        ExecutionState.new("test")
        |> ExecutionState.initialize([%Task{id: "task1", dependencies: []}])
        |> ExecutionState.start_task("task1", make_ref())

      error = {:error, :timeout}
      state = ExecutionState.fail_task(state, "task1", error)

      assert MapSet.member?(state.failed_tasks, "task1")
      assert not Map.has_key?(state.current_tasks, "task1")
      assert state.metadata[{:task_error, "task1"}] == error
    end
  end

  describe "resource management" do
    test "allocates and releases resources" do
      state = ExecutionState.new("test")
      resources = %{cpu: 2, memory: 1024}

      # Allocate resources
      state = ExecutionState.allocate_resources(state, "task1", resources)

      assert state.resource_allocations["task1"] == resources

      # Release resources
      state = ExecutionState.release_resources(state, "task1")

      assert not Map.has_key?(state.resource_allocations, "task1")
    end
  end

  describe "get_ready_tasks/1" do
    test "returns tasks with satisfied dependencies" do
      tasks = [
        %Task{id: "task1", dependencies: []},
        %Task{id: "task2", dependencies: ["task1"]},
        %Task{id: "task3", dependencies: ["task1", "task2"]},
        %Task{id: "task4", dependencies: []}
      ]

      state =
        ExecutionState.new("test")
        |> ExecutionState.initialize(tasks)

      # Initially, only tasks without dependencies are ready
      ready_tasks = ExecutionState.get_ready_tasks(state)
      assert "task1" in ready_tasks
      assert "task4" in ready_tasks
      assert length(ready_tasks) == 2

      # After completing task1, task2 should be ready
      state = ExecutionState.complete_task(state, "task1", %{})
      ready_tasks = ExecutionState.get_ready_tasks(state)
      assert "task2" in ready_tasks
      assert "task4" in ready_tasks

      # After completing task2, task3 should be ready
      state = ExecutionState.complete_task(state, "task2", %{})
      ready_tasks = ExecutionState.get_ready_tasks(state)
      assert "task3" in ready_tasks
      assert "task4" in ready_tasks
    end

    test "excludes executing tasks from ready list" do
      tasks = [
        %Task{id: "task1", dependencies: []},
        %Task{id: "task2", dependencies: []}
      ]

      state =
        ExecutionState.new("test")
        |> ExecutionState.initialize(tasks)
        |> ExecutionState.start_task("task1", make_ref())

      ready_tasks = ExecutionState.get_ready_tasks(state)
      assert "task1" not in ready_tasks
      assert "task2" in ready_tasks
    end
  end

  describe "execution_complete?/1" do
    test "returns true when all tasks are completed or failed" do
      tasks = [
        %Task{id: "task1", dependencies: []},
        %Task{id: "task2", dependencies: []}
      ]

      state =
        ExecutionState.new("test")
        |> ExecutionState.initialize(tasks)

      assert not ExecutionState.execution_complete?(state)

      # Complete one task
      state = ExecutionState.complete_task(state, "task1", %{})
      assert not ExecutionState.execution_complete?(state)

      # Fail the other task
      state = ExecutionState.fail_task(state, "task2", {:error, :failed})
      assert ExecutionState.execution_complete?(state)
    end
  end

  describe "progress_percentage/1" do
    test "calculates progress correctly" do
      tasks = [
        %Task{id: "task1", dependencies: []},
        %Task{id: "task2", dependencies: []},
        %Task{id: "task3", dependencies: []},
        %Task{id: "task4", dependencies: []}
      ]

      state =
        ExecutionState.new("test")
        |> ExecutionState.initialize(tasks)

      # 0% complete
      assert ExecutionState.progress_percentage(state) == 0.0

      # 25% complete (1 of 4 tasks)
      state = ExecutionState.complete_task(state, "task1", %{})
      assert ExecutionState.progress_percentage(state) == 25.0

      # 50% complete (2 of 4 tasks)
      state = ExecutionState.complete_task(state, "task2", %{})
      assert ExecutionState.progress_percentage(state) == 50.0

      # 100% complete (4 of 4 tasks)
      state =
        ExecutionState.complete_task(state, "task3", %{})
        |> ExecutionState.complete_task("task4", %{})

      assert ExecutionState.progress_percentage(state) == 100.0
    end

    test "handles empty task list" do
      state = ExecutionState.new("test")

      assert ExecutionState.progress_percentage(state) == 100.0
    end
  end

  describe "snapshot and restore" do
    test "creates and restores from snapshot" do
      tasks = [%Task{id: "task1", dependencies: []}]

      original_state =
        ExecutionState.new("test")
        |> ExecutionState.initialize(tasks)
        |> ExecutionState.complete_task("task1", %{result: "success"})
        |> ExecutionState.allocate_resources("task2", %{cpu: 1})

      # Create snapshot
      snapshot = ExecutionState.snapshot(original_state)

      assert snapshot.execution_id == "test"
      assert "task1" in snapshot.completed_tasks
      assert snapshot.resource_allocations == %{"task2" => %{cpu: 1}}
      assert snapshot.timestamp

      # Restore from snapshot
      new_state =
        ExecutionState.new("test")
        |> ExecutionState.initialize(tasks)
        |> ExecutionState.restore(snapshot)

      assert MapSet.member?(new_state.completed_tasks, "task1")
      assert new_state.resource_allocations == %{"task2" => %{cpu: 1}}
      # Current tasks are reset
      assert map_size(new_state.current_tasks) == 0
    end
  end

  describe "get_statistics/1" do
    test "provides comprehensive statistics" do
      tasks = [
        %Task{id: "task1", dependencies: []},
        %Task{id: "task2", dependencies: []},
        %Task{id: "task3", dependencies: []}
      ]

      state =
        ExecutionState.new("test")
        |> ExecutionState.initialize(tasks)
        |> ExecutionState.complete_task("task1", %{})
        |> ExecutionState.fail_task("task2", {:error, :failed})
        |> ExecutionState.start_task("task3", make_ref())

      stats = ExecutionState.get_statistics(state)

      assert stats.total_tasks == 3
      assert stats.completed_tasks == 1
      assert stats.failed_tasks == 1
      assert stats.executing_tasks == 1
      assert stats.progress_percentage == 33.3
      assert stats.execution_duration >= 0
    end
  end
end
