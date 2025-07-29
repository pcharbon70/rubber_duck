defmodule RubberDuck.Jido.Agents.WorkflowPersistenceTest do
  @moduledoc """
  Integration tests for workflow persistence using Ash resources.
  
  These tests verify that workflows are properly persisted to the database,
  can be retrieved after restarts, and that all state transitions are
  correctly saved.
  """
  
  use RubberDuck.DataCase, async: false
  
  alias RubberDuck.Jido.Agents.{WorkflowPersistenceAsh, WorkflowCoordinator}
  alias RubberDuck.Workflows.Workflow
  
  # Test workflow modules for persistence tests
  defmodule TestWorkflow do
    use Reactor
    
    input :value
    
    step :process do
      argument :value, input(:value)
      run fn args -> {:ok, args.value * 2} end
    end
    
    return :process
  end
  
  defmodule ModuleA do
    use Reactor
    step :dummy do
      run fn _ -> {:ok, :a} end
    end
    return :dummy
  end
  
  defmodule ModuleB do
    use Reactor
    step :dummy do
      run fn _ -> {:ok, :b} end
    end
    return :dummy
  end
  
  setup do
    # Start workflow coordinator with persistence enabled
    {:ok, _} = start_supervised({WorkflowCoordinator, [persist: true]})
    :ok
  end
  
  describe "save_workflow_state/5 with Ash resources" do
    test "saves and loads workflow state using Ash" do
      workflow_id = "test_wf_1"
      module = TestWorkflow
      reactor_state = %{step: "process", data: %{value: 42}}
      context = %{user_id: "123"}
      metadata = %{status: :halted}
      
      # Save state
      assert {:ok, ^workflow_id} = WorkflowPersistenceAsh.save_workflow_state(
        workflow_id,
        module,
        reactor_state,
        context,
        metadata
      )
      
      # Load state
      assert {:ok, state} = WorkflowPersistenceAsh.load_workflow_state(workflow_id)
      
      assert state.workflow_id == workflow_id
      assert state.module == module
      # Maps are stored with string keys in JSON columns
      assert state.reactor_state == %{"data" => %{"value" => 42}, "step" => "process"}
      # Maps are stored with string keys in JSON columns
      assert state.context == %{"user_id" => "123"}
      # Maps are stored with string keys in JSON columns  
      assert state.metadata == %{"status" => "halted"}
      assert %DateTime{} = state.created_at
    end
    
    test "returns error when loading non-existent workflow" do
      assert {:error, :not_found} = WorkflowPersistenceAsh.load_workflow_state("non_existent")
    end
    
    test "deletes workflow state" do
      workflow_id = "test_wf_2"
      
      # Save state
      {:ok, _} = WorkflowPersistenceAsh.save_workflow_state(
        workflow_id,
        TestWorkflow,
        %{},
        %{},
        %{}
      )
      
      # Verify it exists
      assert {:ok, _} = WorkflowPersistenceAsh.load_workflow_state(workflow_id)
      
      # Delete it
      assert :ok = WorkflowPersistenceAsh.delete_workflow_state(workflow_id)
      
      # Verify it's gone
      assert {:error, :not_found} = WorkflowPersistenceAsh.load_workflow_state(workflow_id)
    end
    
    @tag :pending
    test "workflow persistence through coordinator" do
      # Use a workflow that takes some time
      defmodule SlowTestWorkflow do
        use Reactor
        
        input :value
        
        step :process do
          argument :value, input(:value)
          run fn args -> 
            Process.sleep(200)  # Ensure it takes some time
            {:ok, args.value * 2}
          end
        end
        
        return :process
      end
      
      # Start a workflow through coordinator
      {:ok, workflow_id} = WorkflowCoordinator.start_workflow(
        SlowTestWorkflow,
        %{value: 21}
      )
      
      # Wait for initial persistence
      Process.sleep(100)
      
      # Load from Ash resource - should be running
      assert {:ok, workflow} = WorkflowPersistenceAsh.load_workflow_state(workflow_id)
      assert workflow.status == :running
      assert workflow.module == SlowTestWorkflow
      
      # Wait for completion (200ms workflow + processing time)
      Process.sleep(800)
      
      # Check status changed in database
      assert {:ok, updated} = WorkflowPersistenceAsh.load_workflow_state(workflow_id)
      
      # If still running, wait a bit more and check again
      updated = if updated.status == :running do
        Process.sleep(500)
        {:ok, final_updated} = WorkflowPersistenceAsh.load_workflow_state(workflow_id)
        final_updated
      else
        updated
      end
      
      assert updated.status == :completed
    end
  end
  
  describe "checkpoints with Ash resources" do
    test "saves and loads checkpoints" do
      workflow_id = "test_wf_3"
      step_name = "process_data"
      checkpoint_state = %{intermediate: "result"}
      
      # Create workflow first
      {:ok, _} = WorkflowPersistenceAsh.save_workflow_state(
        workflow_id,
        TestWorkflow,
        %{},
        %{},
        %{status: :running}
      )
      
      # Save checkpoint
      assert {:ok, checkpoint_id} = WorkflowPersistenceAsh.save_checkpoint(
        workflow_id,
        step_name,
        checkpoint_state
      )
      
      assert is_binary(checkpoint_id)
      assert String.starts_with?(checkpoint_id, "cp_")
      
      # Load latest checkpoint
      assert {:ok, checkpoint} = WorkflowPersistenceAsh.load_checkpoint(workflow_id)
      
      assert checkpoint.checkpoint_id == checkpoint_id
      assert checkpoint.workflow_id == workflow_id
      assert checkpoint.step_name == step_name
      # Maps are stored with string keys in JSON columns
      assert checkpoint.state == %{"intermediate" => "result"}
    end
    
    test "loads specific checkpoint by id" do
      workflow_id = "test_wf_4"
      
      # Create workflow
      {:ok, _} = WorkflowPersistenceAsh.save_workflow_state(
        workflow_id,
        TestWorkflow,
        %{},
        %{},
        %{}
      )
      
      # Save multiple checkpoints
      {:ok, cp1} = WorkflowPersistenceAsh.save_checkpoint(workflow_id, "step1", %{n: 1})
      Process.sleep(10)
      {:ok, _cp2} = WorkflowPersistenceAsh.save_checkpoint(workflow_id, "step2", %{n: 2})
      
      # Load specific checkpoint
      assert {:ok, checkpoint} = WorkflowPersistenceAsh.load_checkpoint(workflow_id, cp1)
      assert checkpoint.checkpoint_id == cp1
      # Maps are stored with string keys in JSON columns
      assert checkpoint.state == %{"n" => 1}
    end
    
    test "lists all checkpoints for workflow" do
      workflow_id = "test_wf_5"
      
      # Create workflow
      {:ok, _} = WorkflowPersistenceAsh.save_workflow_state(
        workflow_id,
        TestWorkflow,
        %{},
        %{},
        %{}
      )
      
      # Save multiple checkpoints
      {:ok, _} = WorkflowPersistenceAsh.save_checkpoint(workflow_id, "step1", %{})
      {:ok, _} = WorkflowPersistenceAsh.save_checkpoint(workflow_id, "step2", %{})
      {:ok, _} = WorkflowPersistenceAsh.save_checkpoint(workflow_id, "step3", %{})
      
      # List checkpoints
      assert {:ok, checkpoints} = WorkflowPersistenceAsh.list_checkpoints(workflow_id)
      assert length(checkpoints) == 3
      
      # Should be ordered by creation time (descending)
      step_names = Enum.map(checkpoints, & &1.step_name)
      assert "step1" in step_names
      assert "step2" in step_names
      assert "step3" in step_names
    end
    
    test "workflow persistence survives coordinator restart" do
      workflow_id = "test_wf_restart"
      
      # Save workflow state
      {:ok, _} = WorkflowPersistenceAsh.save_workflow_state(
        workflow_id,
        TestWorkflow,
        %{step: "in_progress"},
        %{user_id: "test"},
        %{status: :halted}
      )
      
      # Stop coordinator
      stop_supervised(WorkflowCoordinator)
      
      # Restart coordinator
      {:ok, _} = start_supervised({WorkflowCoordinator, [persist: true]})
      
      # Should be able to query workflow
      assert {:ok, status} = WorkflowCoordinator.get_workflow_status(workflow_id)
      assert status.id == workflow_id
      assert status.status == :halted
    end
  end
  
  describe "versions with Ash resources" do
    test "saves and retrieves workflow versions" do
      module = TestWorkflow
      version = "1.0.0"
      definition = %{steps: [:validate, :process, :save]}
      
      # Save version
      assert {:ok, ^version} = WorkflowPersistenceAsh.save_version(module, version, definition)
      
      # Get current version
      assert {:ok, version_info} = WorkflowPersistenceAsh.get_current_version(module)
      assert version_info.module == module
      assert version_info.version == version
      # Maps are stored with string keys in JSON columns
      assert version_info.definition == %{"steps" => ["validate", "process", "save"]}
    end
  end
  
  describe "list_workflows/1 with Ash resources" do
    test "lists workflows with filters" do
      # Save some workflows
      {:ok, _} = WorkflowPersistenceAsh.save_workflow_state("wf1", ModuleA, %{}, %{}, %{status: :halted})
      {:ok, _} = WorkflowPersistenceAsh.save_workflow_state("wf2", ModuleB, %{}, %{}, %{status: :completed})
      {:ok, _} = WorkflowPersistenceAsh.save_workflow_state("wf3", ModuleA, %{}, %{}, %{status: :halted})
      
      # List all
      assert {:ok, all} = WorkflowPersistenceAsh.list_workflows()
      assert length(all) >= 3
      
      # Filter by status
      assert {:ok, halted} = WorkflowPersistenceAsh.list_workflows(status: :halted)
      assert length(halted) >= 2
      assert Enum.all?(halted, & &1.status == :halted)
      
      # Filter by module
      assert {:ok, module_a} = WorkflowPersistenceAsh.list_workflows(module: ModuleA)
      assert length(module_a) >= 2
      assert Enum.all?(module_a, & &1.module == ModuleA)
    end
    
    test "orders workflows by creation time" do
      # Save workflows with delays
      {:ok, _} = WorkflowPersistenceAsh.save_workflow_state("wf_old", TestWorkflow, %{}, %{}, %{})
      Process.sleep(10)
      {:ok, _} = WorkflowPersistenceAsh.save_workflow_state("wf_new", TestWorkflow, %{}, %{}, %{})
      
      # List ordered by creation
      assert {:ok, workflows} = WorkflowPersistenceAsh.list_workflows(order_by: :created_at)
      
      # Find our workflows
      old_idx = Enum.find_index(workflows, & &1.workflow_id == "wf_old")
      new_idx = Enum.find_index(workflows, & &1.workflow_id == "wf_new")
      
      # Newer should come first (descending order)
      assert new_idx < old_idx
    end
    
    test "coordinator lists active workflows from database" do
      # Start some workflows
      {:ok, id1} = WorkflowCoordinator.start_workflow(ModuleA, %{})
      {:ok, id2} = WorkflowCoordinator.start_workflow(ModuleB, %{})
      
      # Wait for persistence
      Process.sleep(100)
      
      # List workflows through coordinator
      workflows = WorkflowCoordinator.list_workflows()
      workflow_ids = Enum.map(workflows, & &1.id)
      
      assert id1 in workflow_ids
      assert id2 in workflow_ids
      
      # All should be from database, not memory
      assert Enum.all?(workflows, fn w ->
        {:ok, _} = WorkflowPersistenceAsh.load_workflow_state(w.id)
        true
      end)
    end
  end
  
  describe "cleanup/1 with Ash resources" do
    test "removes old workflows and checkpoints" do
      # Create old workflow
      old_workflow_id = "old_workflow_" <> :crypto.strong_rand_bytes(4) |> Base.encode16()
      
      # Create workflow with Ash
      attrs = %{
        workflow_id: old_workflow_id,
        module: TestWorkflow,
        status: :completed,
        reactor_state: %{},
        context: %{},
        metadata: %{}
      }
      
      {:ok, old_workflow} = 
        Workflow
        |> Ash.Changeset.for_create(:create, attrs)
        |> Ash.create()
      
      # Manually update created_at to be 10 days ago
      old_date = DateTime.add(DateTime.utc_now(), -10 * 24 * 60 * 60, :second)
      
      {:ok, _} = 
        old_workflow
        |> Ash.Changeset.for_update(:update, %{})
        |> Ash.Changeset.force_change_attribute(:created_at, old_date)
        |> Ash.update()
      
      # Create a recent workflow
      recent_id = "recent_workflow_" <> :crypto.strong_rand_bytes(4) |> Base.encode16()
      {:ok, _} = WorkflowPersistenceAsh.save_workflow_state(recent_id, TestWorkflow, %{}, %{}, %{})
      
      # Cleanup workflows older than 7 days
      {:ok, result} = WorkflowPersistenceAsh.cleanup(7)
      
      # At least the old workflow should be cleaned
      assert result.workflows >= 1
      
      # Old workflow should be gone
      assert {:error, :not_found} = WorkflowPersistenceAsh.load_workflow_state(old_workflow_id)
      
      # Recent workflow should still exist
      assert {:ok, _} = WorkflowPersistenceAsh.load_workflow_state(recent_id)
    end
  end
  
  describe "database persistence integration" do
    test "workflow update through coordinator persists to database" do
      # Start workflow
      {:ok, workflow_id} = WorkflowCoordinator.start_workflow(TestWorkflow, %{value: 10})
      
      # Wait for initial persistence
      Process.sleep(50)
      
      # Update workflow
      updates = %{
        context: %{updated_by: "test_user"},
        metadata: %{note: "test update"}
      }
      
      assert {:ok, _} = WorkflowCoordinator.update_workflow(workflow_id, updates)
      
      # Load from database directly
      assert {:ok, workflow} = WorkflowPersistenceAsh.load_workflow_state(workflow_id)
      # Context is stored with string keys in JSON
      assert workflow.context["updated_by"] == "test_user"
      # Metadata is stored with string keys in JSON
      assert workflow.metadata["note"] == "test update"
    end
    
    test "concurrent workflow operations maintain consistency" do
      # Start multiple workflows concurrently
      tasks = for i <- 1..5 do
        Task.async(fn ->
          WorkflowCoordinator.start_workflow(TestWorkflow, %{value: i})
        end)
      end
      
      workflow_ids = Task.await_many(tasks)
      |> Enum.map(fn {:ok, id} -> id end)
      
      # Wait for all to persist
      Process.sleep(200)
      
      # All should be in database
      for workflow_id <- workflow_ids do
        assert {:ok, workflow} = WorkflowPersistenceAsh.load_workflow_state(workflow_id)
        assert workflow.status in [:running, :completed]
      end
    end
  end
end