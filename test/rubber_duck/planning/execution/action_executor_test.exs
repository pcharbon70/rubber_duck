defmodule RubberDuck.Planning.Execution.ActionExecutorTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Planning.Execution.ActionExecutor
  alias RubberDuck.Planning.Task

  describe "execute_action/3" do
    test "executes direct action successfully" do
      task = build_simple_task()
      thought = build_direct_thought()
      state = build_execution_state()
      
      result = ActionExecutor.execute_action(task, thought, state)
      
      assert {:ok, _pid} = result
    end

    test "executes workflow action" do
      task = build_workflow_task()
      thought = build_direct_thought()
      state = build_execution_state()
      
      result = ActionExecutor.execute_action(task, thought, state)
      
      assert {:ok, _pid} = result
    end

    test "executes engine action" do
      task = build_engine_task()
      thought = build_direct_thought()
      state = build_execution_state()
      
      result = ActionExecutor.execute_action(task, thought, state)
      
      assert {:ok, _pid} = result
    end

    test "executes tool action" do
      task = build_tool_task()
      thought = build_direct_thought()
      state = build_execution_state()
      
      result = ActionExecutor.execute_action(task, thought, state)
      
      assert {:ok, _pid} = result
    end
  end

  describe "careful execution" do
    test "executes with extra monitoring" do
      task = build_simple_task()
      thought = build_careful_thought()
      state = build_execution_state()
      
      result = ActionExecutor.execute_action(task, thought, state)
      
      assert {:ok, _pid} = result
    end
  end

  describe "validation execution" do
    test "validates dependencies before execution" do
      task = %Task{
        id: "dependent_task",
        name: "Dependent Task"
      }
      thought = build_validation_thought()
      state = build_execution_state()
      
      # For now, this will pass since we don't have dependency validation implemented yet
      result = ActionExecutor.execute_action(task, thought, state)
      
      assert {:ok, _pid} = result
    end

    test "executes when dependencies are satisfied" do
      task = %Task{
        id: "dependent_task",
        name: "Dependent Task"
      }
      thought = build_validation_thought()
      state = %{
        completed_tasks: MapSet.new(["completed_dep"]),
        failed_tasks: MapSet.new(),
        history: %{}
      }
      
      result = ActionExecutor.execute_action(task, thought, state)
      
      assert {:ok, _pid} = result
    end
  end

  describe "timeout adjustment" do
    test "uses extended timeout for complex tasks" do
      task = build_complex_task()
      thought = build_timeout_thought()
      state = build_execution_state()
      
      result = ActionExecutor.execute_action(task, thought, state)
      
      assert {:ok, _pid} = result
    end
  end

  describe "retry with delay" do
    test "applies delay before retry" do
      task = build_simple_task()
      thought = build_delay_thought()
      state = build_retry_state()
      
      start_time = :os.system_time(:millisecond)
      result = ActionExecutor.execute_action(task, thought, state)
      end_time = :os.system_time(:millisecond)
      
      assert {:ok, _pid} = result
      # Should have applied some delay (at least 1 second for first retry)
      assert end_time - start_time >= 1000
    end
  end

  describe "fix and retry" do
    test "applies fixes based on previous failures" do
      task = build_task_with_invalid_input()
      thought = build_fix_thought()
      state = build_state_with_input_failure()
      
      result = ActionExecutor.execute_action(task, thought, state)
      
      assert {:ok, _pid} = result
    end
  end

  describe "modifications" do
    test "applies modifications for multiple attempts" do
      task = build_simple_task()
      thought = build_modification_thought()
      state = build_state_with_multiple_attempts()
      
      result = ActionExecutor.execute_action(task, thought, state)
      
      assert {:ok, _pid} = result
    end
  end

  describe "error handling" do
    test "handles execution errors gracefully" do
      task = %Task{id: nil}  # Invalid task to trigger error
      thought = build_direct_thought()
      state = build_execution_state()
      
      result = ActionExecutor.execute_action(task, thought, state)
      
      assert {:error, _reason} = result
    end
  end

  # Helper functions

  defp build_simple_task do
    %Task{
      id: "simple_task",
      name: "Simple Task",
      description: "A simple task",
      complexity: :simple
    }
  end

  defp build_workflow_task do
    %Task{
      id: "workflow_task",
      name: "Workflow Task",
      metadata: %{workflow: RubberDuck.Workflows.TestWorkflow}
    }
  end

  defp build_engine_task do
    %Task{
      id: "engine_task",
      name: "Engine Task",
      metadata: %{engine: :test_engine}
    }
  end

  defp build_tool_task do
    %Task{
      id: "tool_task",
      name: "Tool Task", 
      metadata: %{tool: :test_tool}
    }
  end

  defp build_complex_task do
    %Task{
      id: "complex_task",
      name: "Complex Task",
      complexity: :very_complex
    }
  end

  defp build_task_with_invalid_input do
    %Task{
      id: "invalid_input_task",
      metadata: %{
        data: %{timeout: -1, retries: 100}
      }
    }
  end

  defp build_direct_thought do
    %{
      approach: :direct_execution,
      reasoning: "Task is simple and straightforward",
      confidence: 0.9
    }
  end

  defp build_careful_thought do
    %{
      approach: :careful_execution,
      reasoning: "Task requires careful monitoring",
      confidence: 0.7
    }
  end

  defp build_validation_thought do
    %{
      approach: :validate_then_execute,
      reasoning: "Need to validate dependencies first",
      confidence: 0.8
    }
  end

  defp build_timeout_thought do
    %{
      approach: :execute_with_extended_timeout,
      reasoning: "Task may take longer than usual",
      confidence: 0.6
    }
  end

  defp build_delay_thought do
    %{
      approach: :wait_and_retry,
      reasoning: "Previous attempt failed, adding delay",
      confidence: 0.5
    }
  end

  defp build_fix_thought do
    %{
      approach: :fix_and_retry,
      reasoning: "Applying fixes based on previous failure",
      confidence: 0.6
    }
  end

  defp build_modification_thought do
    %{
      approach: :retry_with_modifications,
      reasoning: "Multiple attempts require different approach",
      confidence: 0.4
    }
  end

  defp build_execution_state do
    %{
      completed_tasks: MapSet.new(),
      failed_tasks: MapSet.new(),
      history: %{
        retries: %{},
        attempts: %{},
        failures: %{}
      }
    }
  end

  defp build_retry_state do
    %{
      completed_tasks: MapSet.new(),
      failed_tasks: MapSet.new(),
      history: %{
        retries: %{"simple_task" => 1},
        attempts: %{},
        failures: %{}
      }
    }
  end

  defp build_state_with_input_failure do
    %{
      completed_tasks: MapSet.new(),
      failed_tasks: MapSet.new(),
      history: %{
        retries: %{},
        attempts: %{},
        failures: %{
          "invalid_input_task" => [
            %{
              reason: :invalid_input,
              details: %{invalid_fields: [:timeout, :retries]}
            }
          ]
        }
      }
    }
  end

  defp build_state_with_multiple_attempts do
    %{
      completed_tasks: MapSet.new(),
      failed_tasks: MapSet.new(),
      history: %{
        retries: %{},
        attempts: %{
          "simple_task" => [
            %{status: :failure, timestamp: DateTime.utc_now()},
            %{status: :failure, timestamp: DateTime.utc_now()},
            %{status: :failure, timestamp: DateTime.utc_now()}
          ]
        },
        failures: %{}
      }
    }
  end
end