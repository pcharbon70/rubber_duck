defmodule RubberDuck.Planning.Execution.PlanExecutorTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Planning.Execution.PlanExecutor
  alias RubberDuck.Planning.{Plan, Task}

  describe "start_link/1" do
    test "starts executor with valid plan" do
      plan = build_test_plan()
      
      {:ok, pid} = PlanExecutor.start_link(plan: plan)
      
      assert Process.alive?(pid)
      assert {:ok, state} = PlanExecutor.get_state(pid)
      assert state.plan.id == plan.id
    end

    test "returns error for invalid plan" do
      assert {:error, :invalid_plan} = PlanExecutor.start_link(plan: nil)
    end
  end

  describe "execute/1" do
    test "executes plan successfully" do
      plan = build_test_plan()
      {:ok, pid} = PlanExecutor.start_link(plan: plan)
      
      assert :ok = PlanExecutor.execute(pid)
      
      # Wait for execution to start
      :timer.sleep(100)
      
      {:ok, state} = PlanExecutor.get_state(pid)
      assert state.status == :executing
    end

    test "handles plan already executing" do
      plan = build_test_plan()
      {:ok, pid} = PlanExecutor.start_link(plan: plan)
      
      :ok = PlanExecutor.execute(pid)
      assert {:error, :already_executing} = PlanExecutor.execute(pid)
    end
  end

  describe "pause/1 and resume/1" do
    test "pauses and resumes execution" do
      plan = build_test_plan()
      {:ok, pid} = PlanExecutor.start_link(plan: plan)
      
      :ok = PlanExecutor.execute(pid)
      :timer.sleep(50)
      
      :ok = PlanExecutor.pause(pid)
      {:ok, state} = PlanExecutor.get_state(pid)
      assert state.status == :paused
      
      :ok = PlanExecutor.resume(pid)
      {:ok, state} = PlanExecutor.get_state(pid)
      assert state.status == :executing
    end
  end

  describe "stop/1" do
    test "stops execution gracefully" do
      plan = build_test_plan()
      {:ok, pid} = PlanExecutor.start_link(plan: plan)
      
      :ok = PlanExecutor.execute(pid)
      :timer.sleep(50)
      
      :ok = PlanExecutor.stop(pid)
      {:ok, state} = PlanExecutor.get_state(pid)
      assert state.status == :stopped
    end
  end

  describe "get_progress/1" do
    test "returns execution progress" do
      plan = build_test_plan()
      {:ok, pid} = PlanExecutor.start_link(plan: plan)
      
      {:ok, progress} = PlanExecutor.get_progress(pid)
      
      assert progress.total_tasks == 3
      assert progress.completed_tasks == 0
      assert progress.failed_tasks == 0
      assert progress.progress_percentage == 0.0
    end
  end

  describe "get_history/1" do
    test "returns execution history" do
      plan = build_test_plan()
      {:ok, pid} = PlanExecutor.start_link(plan: plan)
      
      {:ok, history} = PlanExecutor.get_history(pid)
      
      assert history.execution_id
      assert history.entries == []
    end
  end

  describe "react cycle" do
    test "executes thought-action-observation cycle" do
      plan = build_simple_plan()
      {:ok, pid} = PlanExecutor.start_link(plan: plan)
      
      # Execute and wait for at least one cycle
      :ok = PlanExecutor.execute(pid)
      :timer.sleep(200)
      
      {:ok, history} = PlanExecutor.get_history(pid)
      
      # Should have at least one thought entry
      thoughts = Enum.filter(history.entries, &(&1.type == :thought))
      assert length(thoughts) > 0
    end
  end

  describe "failure recovery" do
    test "retries failed tasks with exponential backoff" do
      plan = build_failing_plan()
      {:ok, pid} = PlanExecutor.start_link(plan: plan)
      
      :ok = PlanExecutor.execute(pid)
      :timer.sleep(500)
      
      {:ok, history} = PlanExecutor.get_history(pid)
      
      # Should have retry attempts
      retry_count = history.retries["failing_task"] || 0
      assert retry_count > 0
    end
  end

  describe "progress tracking" do
    test "broadcasts progress updates" do
      plan = build_test_plan()
      {:ok, pid} = PlanExecutor.start_link(plan: plan)
      
      # Subscribe to progress updates
      PlanExecutor.subscribe_to_progress(pid)
      
      :ok = PlanExecutor.execute(pid)
      
      # Should receive progress update
      assert_receive {:progress_update, _progress}, 1000
    end
  end

  # Helper functions

  defp build_test_plan do
    %Plan{
      id: "test_plan",
      name: "Test Plan",
      description: "A test execution plan",
      tasks: [
        %Task{
          id: "task_1",
          name: "First Task",
          description: "Execute first task",
          complexity: :simple,
          dependencies: []
        },
        %Task{
          id: "task_2", 
          name: "Second Task",
          description: "Execute second task",
          complexity: :medium,
          dependencies: ["task_1"]
        },
        %Task{
          id: "task_3",
          name: "Third Task", 
          description: "Execute third task",
          complexity: :simple,
          dependencies: ["task_2"]
        }
      ],
      metadata: %{
        execution_type: :sequential
      }
    }
  end

  defp build_simple_plan do
    %Plan{
      id: "simple_plan",
      name: "Simple Plan",
      description: "A simple plan with one task",
      tasks: [
        %Task{
          id: "simple_task",
          name: "Simple Task",
          description: "A simple task",
          complexity: :simple,
          dependencies: []
        }
      ]
    }
  end

  defp build_failing_plan do
    %Plan{
      id: "failing_plan",
      name: "Failing Plan", 
      description: "A plan with a failing task",
      tasks: [
        %Task{
          id: "failing_task",
          name: "Failing Task",
          description: "This task will fail",
          complexity: :simple,
          dependencies: [],
          metadata: %{simulate_failure: true}
        }
      ]
    }
  end
end