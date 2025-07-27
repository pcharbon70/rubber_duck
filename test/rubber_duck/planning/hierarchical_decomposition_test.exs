defmodule RubberDuck.Planning.HierarchicalDecompositionTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Planning.Decomposer
  
  describe "hierarchical pattern decomposition" do
    test "feature_implementation pattern creates hierarchical structure" do
      # Use the pattern library which has hierarchical structure
      {:ok, tasks} = Decomposer.decompose_with_pattern("feature_implementation", %{})
      
      assert length(tasks) > 5
      
      # Check that tasks have phase information
      phase_names = tasks
        |> Enum.map(& &1[:metadata][:phase])
        |> Enum.uniq()
        |> Enum.filter(&(&1 != nil))
      
      # Feature implementation pattern should have multiple phases
      assert length(phase_names) >= 3
      assert "Design" in phase_names
      assert "Implementation" in phase_names
      assert "Testing" in phase_names
    end
    
    test "tasks have proper hierarchical metadata" do
      {:ok, tasks} = Decomposer.decompose_with_pattern("feature_implementation", %{})
      
      # Find a task from the Design phase
      design_task = Enum.find(tasks, fn task ->
        task[:metadata][:phase] == "Design"
      end)
      
      assert design_task != nil
      assert design_task[:metadata][:hierarchy_level] != nil
      assert design_task[:position] != nil
    end
    
    test "tasks are properly ordered by position" do
      {:ok, tasks} = Decomposer.decompose_with_pattern("refactoring", %{})
      
      positions = Enum.map(tasks, & &1[:position])
      sorted_positions = Enum.sort(positions)
      
      # Positions should already be sorted
      assert positions == sorted_positions
    end
  end
  
  describe "decomposer output format" do
    test "all tasks have required fields" do
      {:ok, tasks} = Decomposer.decompose_with_pattern("api_integration", %{})
      
      Enum.each(tasks, fn task ->
        # Required fields
        assert is_binary(task[:name])
        assert is_binary(task[:description])
        assert is_number(task[:position])
        assert task[:complexity] in [:trivial, :simple, :medium, :complex, :very_complex]
        
        # Metadata
        assert is_map(task[:metadata])
        assert Map.has_key?(task, :success_criteria)
        assert Map.has_key?(task, :validation_rules)
      end)
    end
    
    test "hierarchical tasks can have decimal positions" do
      # This test verifies that the decomposer can handle decimal positions
      # which are used for subtasks in hierarchical decomposition
      
      # The decomposer should handle decimal positions properly
      # This tests the format_tasks_for_planning function indirectly
      {:ok, tasks} = Decomposer.decompose_with_pattern("bug_fix", %{})
      
      # Verify positions are numeric (integer or float)
      Enum.each(tasks, fn task ->
        assert is_number(task[:position])
      end)
    end
  end
end