defmodule RubberDuck.Planning.DecomposerUnitTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Planning.Decomposer
  
  describe "list_patterns/0" do
    test "returns available decomposition patterns" do
      patterns = Decomposer.list_patterns()
      
      assert is_list(patterns)
      assert "feature_implementation" in patterns
      assert "bug_fix" in patterns
      assert "refactoring" in patterns
      assert "api_integration" in patterns
      assert "database_migration" in patterns
      assert "performance_optimization" in patterns
    end
  end
  
  describe "decompose_with_pattern/2" do
    test "applies bug_fix pattern successfully" do
      # This tests the pattern library directly without engine execution
      result = Decomposer.decompose_with_pattern("bug_fix", %{})
      
      assert {:ok, tasks} = result
      assert is_list(tasks)
      assert length(tasks) > 0
      
      # Check task structure
      first_task = List.first(tasks)
      assert Map.has_key?(first_task, :name)
      assert Map.has_key?(first_task, :description)
      assert Map.has_key?(first_task, :position)
      assert Map.has_key?(first_task, :complexity)
      
      # Bug fix pattern should have specific phases
      task_names = Enum.map(tasks, & &1[:name])
      assert Enum.any?(task_names, &String.contains?(&1, "Reproduce"))
      assert Enum.any?(task_names, &String.contains?(&1, "Identify root cause"))
      assert Enum.any?(task_names, &String.contains?(&1, "Implement fix"))
    end
    
    test "applies feature_implementation pattern" do
      result = Decomposer.decompose_with_pattern("feature_implementation", %{})
      
      assert {:ok, tasks} = result
      assert length(tasks) > 5  # Feature implementation should have many tasks
      
      # Check for expected phases
      task_names = Enum.map(tasks, & &1[:name])
      assert Enum.any?(task_names, &String.contains?(&1, "requirements"))
      assert Enum.any?(task_names, &String.contains?(&1, "design"))
      assert Enum.any?(task_names, &String.contains?(&1, "test"))
      assert Enum.any?(task_names, &String.contains?(&1, "documentation"))
    end
    
    test "handles non-existent pattern gracefully" do
      result = Decomposer.decompose_with_pattern("non_existent_pattern", %{})
      
      assert {:error, :pattern_not_found} = result
    end
  end
  
  describe "task formatting" do
    test "decompose_with_pattern returns properly formatted tasks" do
      {:ok, tasks} = Decomposer.decompose_with_pattern("refactoring", %{})
      
      Enum.each(tasks, fn task ->
        # Required fields
        assert is_binary(task[:name])
        assert is_binary(task[:description])
        assert is_integer(task[:position])
        assert task[:complexity] in [:trivial, :simple, :medium, :complex, :very_complex]
        
        # Success criteria
        assert Map.has_key?(task, :success_criteria)
        assert is_map(task[:success_criteria])
        assert is_list(task[:success_criteria]["criteria"])
        
        # Metadata
        assert Map.has_key?(task, :metadata)
        assert is_map(task[:metadata])
      end)
    end
  end
end