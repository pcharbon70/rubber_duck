defmodule RubberDuck.Jido.Agents.WorkflowCoordinatorTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Jido.Agents.{WorkflowCoordinator, Supervisor}
  alias RubberDuck.Jido.Workflows.{SimplePipeline, ValidationWorkflow}
  
  # Simple test workflow
  defmodule TestWorkflow do
    use Reactor
    
    input :value
    
    step :double do
      argument :value, input(:value)
      
      run fn %{value: value} ->
        {:ok, value * 2}
      end
    end
    
    step :add_ten do
      argument :value, result(:double)
      
      run fn %{value: value} ->
        {:ok, value + 10}
      end
    end
    
    return :add_ten
  end
  
  # Workflow that halts
  defmodule HaltingWorkflow do
    use Reactor
    
    input :should_halt
    
    step :check do
      argument :should_halt, input(:should_halt)
      
      run fn %{should_halt: should_halt} ->
        if should_halt do
          {:halt, :user_requested}
        else
          {:ok, :continued}
        end
      end
    end
    
    return :check
  end
  
  setup do
    # Start the workflow coordinator
    {:ok, _} = start_supervised(WorkflowCoordinator)
    
    # Start the agent supervisor for test agents
    {:ok, _} = start_supervised(Supervisor)
    
    :ok
  end
  
  describe "execute_workflow/3" do
    test "executes a simple workflow successfully" do
      assert {:ok, 32} = WorkflowCoordinator.execute_workflow(
        TestWorkflow,
        %{value: 11}
      )
    end
    
    test "executes with custom context" do
      assert {:ok, result} = WorkflowCoordinator.execute_workflow(
        ValidationWorkflow,
        %{data: %{test: "data"}},
        context: %{user_id: "123"}
      )
      
      assert result == :valid
    end
    
    test "handles workflow errors" do
      assert {:error, _errors} = WorkflowCoordinator.execute_workflow(
        ValidationWorkflow,
        %{data: nil}
      )
    end
    
    test "handles halted workflows" do
      assert {:halted, workflow_id} = WorkflowCoordinator.execute_workflow(
        HaltingWorkflow,
        %{should_halt: true}
      )
      
      assert is_binary(workflow_id)
      assert String.starts_with?(workflow_id, "wf_")
    end
    
    test "respects timeout option" do
      # Create a slow workflow
      defmodule SlowWorkflow do
        use Reactor
        
        step :slow do
          run fn _args ->
            Process.sleep(200)
            {:ok, :done}
          end
        end
        
        return :slow
      end
      
      assert {:error, :timeout} = 
        catch_exit(WorkflowCoordinator.execute_workflow(
          SlowWorkflow,
          %{},
          timeout: 100
        ))
    end
  end
  
  describe "start_workflow/3" do
    test "starts workflow asynchronously" do
      assert {:ok, workflow_id} = WorkflowCoordinator.start_workflow(
        TestWorkflow,
        %{value: 5}
      )
      
      assert is_binary(workflow_id)
      
      # Give it time to complete
      Process.sleep(100)
      
      # Check status
      assert {:ok, status} = WorkflowCoordinator.get_workflow_status(workflow_id)
      assert status.status in [:running, :completed]
    end
  end
  
  describe "get_workflow_status/1" do
    test "returns status for existing workflow" do
      {:ok, workflow_id} = WorkflowCoordinator.start_workflow(
        TestWorkflow,
        %{value: 5}
      )
      
      assert {:ok, status} = WorkflowCoordinator.get_workflow_status(workflow_id)
      assert status.module == TestWorkflow
      assert status.status == :running
      assert is_struct(status.started_at, DateTime)
    end
    
    test "returns error for non-existent workflow" do
      assert {:error, :not_found} = 
        WorkflowCoordinator.get_workflow_status("non_existent")
    end
  end
  
  describe "list_workflows/0" do
    test "lists all active workflows" do
      # Start a few workflows
      {:ok, id1} = WorkflowCoordinator.start_workflow(TestWorkflow, %{value: 1})
      {:ok, id2} = WorkflowCoordinator.start_workflow(TestWorkflow, %{value: 2})
      
      workflows = WorkflowCoordinator.list_workflows()
      
      assert length(workflows) >= 2
      assert Enum.any?(workflows, & &1.id == id1)
      assert Enum.any?(workflows, & &1.id == id2)
    end
  end
  
  @tag :skip  # Resume functionality needs more implementation
  describe "resume_workflow/2" do
    test "resumes a halted workflow" do
      # Execute a workflow that halts
      {:halted, workflow_id} = WorkflowCoordinator.execute_workflow(
        HaltingWorkflow,
        %{should_halt: true}
      )
      
      # Resume it with different inputs
      assert :ok = WorkflowCoordinator.resume_workflow(
        workflow_id,
        %{should_halt: false}
      )
      
      # Give it time to complete
      Process.sleep(100)
      
      # Check it completed
      {:ok, status} = WorkflowCoordinator.get_workflow_status(workflow_id)
      assert status.status == :completed
    end
  end
end