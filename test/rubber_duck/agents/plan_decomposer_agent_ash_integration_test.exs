defmodule RubberDuck.Agents.PlanDecomposerAgentAshIntegrationTest do
  use RubberDuck.DataCase, async: false
  
  alias RubberDuck.Agents.PlanDecomposerAgent
  alias RubberDuck.Planning.{Plan, Task}
  
  require Ash.Query
  
  describe "Ash resource integration" do
    setup do
      # Create a test plan
      {:ok, plan} = Ash.create(Plan, %{
        name: "Test Plan",
        description: "A plan for testing decomposition",
        type: :feature
      }, domain: RubberDuck.Planning)
      
      agent = %{
        id: "test_decomposer",
        state: %{
          active_decompositions: %{},
          cache: %{},
          cache_enabled: false,  # Disable cache for testing
          persist_to_db: true,
          strategies: [:linear, :hierarchical, :tree_of_thought],
          default_strategy: :linear,
          max_depth: 5,
          llm_config: %{},
          validation_enabled: false  # Disable validation for testing
        }
      }
      
      %{agent: agent, plan: plan}
    end
    
    test "persists decomposed tasks to database", %{plan: plan} do
      # Mock decomposition result
      decomposition_result = %{
        tasks: [
          %{
            "id" => "task_0",
            "name" => "Setup project",
            "description" => "Initialize the project structure",
            "complexity" => "simple",
            "position" => 0,
            "depends_on" => []
          },
          %{
            "id" => "task_1", 
            "name" => "Create models",
            "description" => "Define data models",
            "complexity" => "medium",
            "position" => 1,
            "depends_on" => ["task_0"]
          },
          %{
            "id" => "task_2",
            "name" => "Implement logic",
            "description" => "Write business logic",
            "complexity" => "complex",
            "position" => 2,
            "depends_on" => ["task_1"]
          }
        ],
        dependencies: [
          %{from: "task_0", to: "task_1"},
          %{from: "task_1", to: "task_2"}
        ],
        strategy: :linear,
        metadata: %{}
      }
      
      # Call persist_decomposition directly (since it's a private function,
      # we'll test through the public interface)
      # Mock the decomposer to return our test data
      # In a real test, we'd mock the LLM service
      
      # Test the persistence logic directly
      {:ok, _persist_result} = PlanDecomposerAgent.test_persist_decomposition(
        plan.id, 
        decomposition_result
      )
      
      # Verify tasks were created
      tasks = Task
      |> Ash.Query.new()
      |> Ash.Query.filter(plan_id: plan.id)
      |> Ash.read!(domain: RubberDuck.Planning)
      
      assert length(tasks) == 3
      
      # Verify task properties
      task_by_position = tasks |> Enum.map(&{&1.position, &1}) |> Map.new()
      
      assert task_by_position[0].name == "Setup project"
      assert task_by_position[0].complexity == :simple
      
      assert task_by_position[1].name == "Create models"
      assert task_by_position[1].complexity == :medium
      
      assert task_by_position[2].name == "Implement logic"
      assert task_by_position[2].complexity == :complex
      
      # Verify plan was updated
      {:ok, updated_plan} = Ash.get(Plan, plan.id, domain: RubberDuck.Planning)
      assert updated_plan.status == :ready
      assert updated_plan.metadata["decomposition_complete"] == true
      
      # Verify dependencies were created
      alias RubberDuck.Planning.TaskDependency
      
      dependencies = TaskDependency
      |> Ash.Query.new()
      |> Ash.read!(domain: RubberDuck.Planning)
      
      assert length(dependencies) == 2
      
      # Verify the dependency chain
      deps_by_task = dependencies
      |> Enum.group_by(& &1.task_id)
      
      # Task 1 should depend on Task 0
      task1_deps = Map.get(deps_by_task, task_by_position[1].id, [])
      assert length(task1_deps) == 1
      assert hd(task1_deps).dependency_id == task_by_position[0].id
      
      # Task 2 should depend on Task 1
      task2_deps = Map.get(deps_by_task, task_by_position[2].id, [])
      assert length(task2_deps) == 1
      assert hd(task2_deps).dependency_id == task_by_position[1].id
    end
    
    test "handles missing plan gracefully", %{agent: agent} do
      fake_plan_id = Ash.UUID.generate()
      
      signal = %{
        "type" => "decompose_plan",
        "plan_id" => fake_plan_id,
        "query" => "Test decomposition"
      }
      
      # This should not crash but emit a failure signal
      assert {:ok, _} = PlanDecomposerAgent.handle_signal(agent, signal)
    end
    
    test "respects persist_to_db setting", %{agent: agent, plan: plan} do
      # Disable persistence
      agent_no_persist = put_in(agent.state.persist_to_db, false)
      
      signal = %{
        "type" => "decompose_plan",
        "plan_id" => plan.id,
        "query" => "Test without persistence"
      }
      
      assert {:ok, _} = PlanDecomposerAgent.handle_signal(agent_no_persist, signal)
      
      # No tasks should be created
      tasks = Task
      |> Ash.Query.new()
      |> Ash.Query.filter(plan_id: plan.id)
      |> Ash.read!(domain: RubberDuck.Planning)
      
      assert length(tasks) == 0
    end
  end
end