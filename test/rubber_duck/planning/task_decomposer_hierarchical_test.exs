defmodule RubberDuck.Planning.TaskDecomposerHierarchicalTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Planning.TaskDecomposer
  
  describe "hierarchical decomposition" do
    test "extracts tasks from hierarchical structure" do
      # Mock hierarchical data that would come from LLM
      hierarchical_data = %{
        "phases" => [
          %{
            "id" => "phase_1",
            "name" => "Design Phase",
            "description" => "Design the system architecture",
            "tasks" => [
              %{
                "id" => "task_1_1",
                "name" => "Create system design",
                "description" => "Design overall system architecture",
                "complexity" => "complex",
                "subtasks" => [
                  %{
                    "id" => "subtask_1_1_1",
                    "name" => "Design database schema",
                    "description" => "Define tables and relationships"
                  },
                  %{
                    "id" => "subtask_1_1_2",
                    "name" => "Design API structure",
                    "description" => "Define REST endpoints"
                  }
                ]
              },
              %{
                "id" => "task_1_2",
                "name" => "Create UI mockups",
                "description" => "Design user interface mockups",
                "complexity" => "medium",
                "subtasks" => []
              }
            ]
          },
          %{
            "id" => "phase_2",
            "name" => "Implementation Phase",
            "description" => "Implement the system",
            "tasks" => [
              %{
                "id" => "task_2_1",
                "name" => "Set up project",
                "description" => "Initialize project and dependencies",
                "complexity" => "simple",
                "subtasks" => []
              }
            ]
          }
        ],
        "dependencies" => [
          %{"from" => "task_1_1", "to" => "task_2_1", "type" => "finish_to_start"},
          %{"from" => "task_1_2", "to" => "task_2_1", "type" => "finish_to_start"}
        ],
        "critical_path" => ["task_1_1", "task_2_1"]
      }
      
      # Call the private function directly for testing
      tasks = TaskDecomposer.extract_hierarchical_tasks(hierarchical_data, %{})
      
      # Verify task count (2 main tasks in phase 1 + 2 subtasks + 1 task in phase 2 = 5 total)
      assert length(tasks) == 5
      
      # Verify main tasks
      task_1_1 = Enum.find(tasks, &(&1["id"] == "task_1_1"))
      assert task_1_1["name"] == "Create system design"
      assert task_1_1["phase_name"] == "Design Phase"
      assert task_1_1["hierarchy_level"] == 2
      assert task_1_1["is_critical"] == true
      assert task_1_1["position"] == 0
      
      # Verify subtasks
      subtask_1_1_1 = Enum.find(tasks, &(&1["id"] == "subtask_1_1_1"))
      assert subtask_1_1_1["name"] == "Design database schema"
      assert subtask_1_1_1["parent_task_id"] == "task_1_1"
      assert subtask_1_1_1["hierarchy_level"] == 3
      assert subtask_1_1_1["position"] == 0.1  # Decimal position for first subtask
      
      subtask_1_1_2 = Enum.find(tasks, &(&1["id"] == "subtask_1_1_2"))
      assert subtask_1_1_2["position"] == 0.2  # Decimal position for second subtask
      
      # Verify task from phase 2
      task_2_1 = Enum.find(tasks, &(&1["id"] == "task_2_1"))
      assert task_2_1["phase_name"] == "Implementation Phase"
      assert task_2_1["is_critical"] == true
      assert task_2_1["depends_on"] == [0, 1]  # Depends on both tasks from phase 1
    end
    
    test "handles empty phases gracefully" do
      hierarchical_data = %{"phases" => []}
      
      tasks = TaskDecomposer.extract_hierarchical_tasks(hierarchical_data, %{})
      
      assert tasks == []
    end
    
    test "handles missing subtasks" do
      hierarchical_data = %{
        "phases" => [
          %{
            "id" => "phase_1",
            "name" => "Simple Phase",
            "tasks" => [
              %{
                "id" => "task_1",
                "name" => "Simple task",
                "description" => "A task without subtasks"
              }
            ]
          }
        ]
      }
      
      tasks = TaskDecomposer.extract_hierarchical_tasks(hierarchical_data, %{})
      
      assert length(tasks) == 1
      assert List.first(tasks)["id"] == "task_1"
    end
    
    test "preserves metadata in hierarchical tasks" do
      hierarchical_data = %{
        "phases" => [
          %{
            "id" => "phase_1",
            "name" => "Test Phase",
            "tasks" => [
              %{
                "id" => "task_1",
                "name" => "Test task",
                "description" => "Task with metadata",
                "complexity" => "medium",
                "metadata" => %{
                  "custom_field" => "custom_value"
                }
              }
            ]
          }
        ]
      }
      
      tasks = TaskDecomposer.extract_hierarchical_tasks(hierarchical_data, %{})
      task = List.first(tasks)
      
      assert task["metadata"]["phase"] == "Test Phase"
      assert task["metadata"]["hierarchy_level"] == 2
    end
  end
  
  describe "dependency handling" do
    test "correctly maps dependencies to task positions" do
      tasks = [
        %{"id" => "task_a", "position" => 0},
        %{"id" => "task_b", "position" => 1},
        %{"id" => "task_c", "position" => 2}
      ]
      
      dependencies = [
        %{"from" => "task_a", "to" => "task_b"},
        %{"from" => "task_a", "to" => "task_c"},
        %{"from" => "task_b", "to" => "task_c"}
      ]
      
      tasks_with_deps = TaskDecomposer.add_dependencies_to_tasks(tasks, dependencies)
      
      task_b = Enum.find(tasks_with_deps, &(&1["id"] == "task_b"))
      assert task_b["depends_on"] == [0]  # Depends on task_a at position 0
      
      task_c = Enum.find(tasks_with_deps, &(&1["id"] == "task_c"))
      assert Enum.sort(task_c["depends_on"]) == [0, 1]  # Depends on both task_a and task_b
    end
  end
end

