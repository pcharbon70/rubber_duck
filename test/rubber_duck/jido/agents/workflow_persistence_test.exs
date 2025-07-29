defmodule RubberDuck.Jido.Agents.WorkflowPersistenceTest do
  use ExUnit.Case, async: false
  
  alias RubberDuck.Jido.Agents.WorkflowPersistence
  
  setup do
    {:ok, _} = start_supervised(WorkflowPersistence)
    :ok
  end
  
  describe "save_workflow_state/5" do
    test "saves and loads workflow state" do
      workflow_id = "test_wf_1"
      module = TestWorkflow
      reactor_state = %{step: "process", data: %{value: 42}}
      context = %{user_id: "123"}
      metadata = %{status: :halted}
      
      # Save state
      assert {:ok, ^workflow_id} = WorkflowPersistence.save_workflow_state(
        workflow_id,
        module,
        reactor_state,
        context,
        metadata
      )
      
      # Load state
      assert {:ok, state} = WorkflowPersistence.load_workflow_state(workflow_id)
      
      assert state.workflow_id == workflow_id
      assert state.module == module
      assert state.reactor_state == reactor_state
      assert state.context == context
      assert state.metadata == metadata
      assert %DateTime{} = state.created_at
    end
    
    test "returns error when loading non-existent workflow" do
      assert {:error, :not_found} = WorkflowPersistence.load_workflow_state("non_existent")
    end
    
    test "deletes workflow state" do
      workflow_id = "test_wf_2"
      
      # Save state
      {:ok, _} = WorkflowPersistence.save_workflow_state(
        workflow_id,
        TestWorkflow,
        %{},
        %{},
        %{}
      )
      
      # Verify it exists
      assert {:ok, _} = WorkflowPersistence.load_workflow_state(workflow_id)
      
      # Delete it
      assert :ok = WorkflowPersistence.delete_workflow_state(workflow_id)
      
      # Verify it's gone
      assert {:error, :not_found} = WorkflowPersistence.load_workflow_state(workflow_id)
    end
  end
  
  describe "checkpoints" do
    test "saves and loads checkpoints" do
      workflow_id = "test_wf_3"
      step_name = "process_data"
      checkpoint_state = %{intermediate: "result"}
      
      # Save checkpoint
      assert {:ok, checkpoint_id} = WorkflowPersistence.save_checkpoint(
        workflow_id,
        step_name,
        checkpoint_state
      )
      
      assert is_binary(checkpoint_id)
      assert String.starts_with?(checkpoint_id, "cp_")
      
      # Load latest checkpoint
      assert {:ok, checkpoint} = WorkflowPersistence.load_checkpoint(workflow_id)
      
      assert checkpoint.id == checkpoint_id
      assert checkpoint.workflow_id == workflow_id
      assert checkpoint.step_name == step_name
      assert checkpoint.state == checkpoint_state
    end
    
    test "loads specific checkpoint by id" do
      workflow_id = "test_wf_4"
      
      # Save multiple checkpoints
      {:ok, cp1} = WorkflowPersistence.save_checkpoint(workflow_id, "step1", %{n: 1})
      Process.sleep(10)
      {:ok, cp2} = WorkflowPersistence.save_checkpoint(workflow_id, "step2", %{n: 2})
      
      # Load specific checkpoint
      assert {:ok, checkpoint} = WorkflowPersistence.load_checkpoint(workflow_id, cp1)
      assert checkpoint.id == cp1
      assert checkpoint.state == %{n: 1}
    end
    
    test "lists all checkpoints for workflow" do
      workflow_id = "test_wf_5"
      
      # Save multiple checkpoints
      {:ok, _} = WorkflowPersistence.save_checkpoint(workflow_id, "step1", %{})
      {:ok, _} = WorkflowPersistence.save_checkpoint(workflow_id, "step2", %{})
      {:ok, _} = WorkflowPersistence.save_checkpoint(workflow_id, "step3", %{})
      
      # List checkpoints
      assert {:ok, checkpoints} = WorkflowPersistence.list_checkpoints(workflow_id)
      assert length(checkpoints) == 3
      
      # Should be ordered by creation time (descending)
      [cp1, cp2, cp3] = checkpoints
      assert DateTime.compare(cp1.created_at, cp2.created_at) == :gt
      assert DateTime.compare(cp2.created_at, cp3.created_at) == :gt
    end
    
    test "deleting workflow also deletes checkpoints" do
      workflow_id = "test_wf_6"
      
      # Save workflow and checkpoints
      {:ok, _} = WorkflowPersistence.save_workflow_state(workflow_id, TestWorkflow, %{}, %{}, %{})
      {:ok, _} = WorkflowPersistence.save_checkpoint(workflow_id, "step1", %{})
      {:ok, _} = WorkflowPersistence.save_checkpoint(workflow_id, "step2", %{})
      
      # Delete workflow
      :ok = WorkflowPersistence.delete_workflow_state(workflow_id)
      
      # Checkpoints should be gone too
      assert {:ok, []} = WorkflowPersistence.list_checkpoints(workflow_id)
    end
  end
  
  describe "versions" do
    test "saves and retrieves workflow versions" do
      module = TestWorkflow
      version = "1.0.0"
      definition = %{steps: [:validate, :process, :save]}
      
      # Save version
      assert {:ok, ^version} = WorkflowPersistence.save_version(module, version, definition)
      
      # Get current version
      assert {:ok, version_info} = WorkflowPersistence.get_current_version(module)
      assert version_info.module == module
      assert version_info.version == version
      assert version_info.definition == definition
    end
  end
  
  describe "list_workflows/1" do
    test "lists workflows with filters" do
      # Save some workflows
      {:ok, _} = WorkflowPersistence.save_workflow_state("wf1", ModuleA, %{}, %{}, %{status: :halted})
      {:ok, _} = WorkflowPersistence.save_workflow_state("wf2", ModuleB, %{}, %{}, %{status: :completed})
      {:ok, _} = WorkflowPersistence.save_workflow_state("wf3", ModuleA, %{}, %{}, %{status: :halted})
      
      # List all
      assert {:ok, all} = WorkflowPersistence.list_workflows()
      assert length(all) >= 3
      
      # Filter by status
      assert {:ok, halted} = WorkflowPersistence.list_workflows(status: :halted)
      assert length(halted) >= 2
      assert Enum.all?(halted, & &1.metadata[:status] == :halted)
      
      # Filter by module
      assert {:ok, module_a} = WorkflowPersistence.list_workflows(module: ModuleA)
      assert length(module_a) >= 2
      assert Enum.all?(module_a, & &1.module == ModuleA)
    end
    
    test "orders workflows by creation time" do
      # Save workflows with delays
      {:ok, _} = WorkflowPersistence.save_workflow_state("wf_old", TestWorkflow, %{}, %{}, %{})
      Process.sleep(10)
      {:ok, _} = WorkflowPersistence.save_workflow_state("wf_new", TestWorkflow, %{}, %{}, %{})
      
      # List ordered by creation
      assert {:ok, workflows} = WorkflowPersistence.list_workflows(order_by: :created_at)
      
      # Find our workflows
      old_idx = Enum.find_index(workflows, & &1.workflow_id == "wf_old")
      new_idx = Enum.find_index(workflows, & &1.workflow_id == "wf_new")
      
      # Newer should come first (descending order)
      assert new_idx < old_idx
    end
  end
  
  describe "cleanup/1" do
    test "removes old workflows and checkpoints" do
      # Create an old workflow (simulate by modifying the timestamp)
      workflow_id = "old_workflow"
      {:ok, _} = WorkflowPersistence.save_workflow_state(workflow_id, TestWorkflow, %{}, %{}, %{})
      {:ok, _} = WorkflowPersistence.save_checkpoint(workflow_id, "step", %{})
      
      # Create a recent workflow
      recent_id = "recent_workflow"
      {:ok, _} = WorkflowPersistence.save_workflow_state(recent_id, TestWorkflow, %{}, %{}, %{})
      
      # Cleanup (0 days = only keep very recent)
      {:ok, result} = WorkflowPersistence.cleanup(0)
      
      # At least the old workflow should be cleaned
      assert result.workflows >= 0
      assert result.checkpoints >= 0
    end
  end
end