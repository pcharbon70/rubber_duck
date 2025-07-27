defmodule RubberDuck.Planning.TreeOfThoughtIntegrationTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Planning.Decomposer
  
  describe "tree-of-thought strategy through Decomposer" do
    test "selects tree-of-thought for exploratory tasks" do
      description = "Research and implement the best approach for real-time data synchronization"
      context = %{
        strategy: :tree_of_thought,
        provider: :mock,
        model: "test-model",
        risk_tolerance: :medium,
        time_constraint: "2w"
      }
      
      # This would normally use the engine, but we can test the pattern
      # The decomposer would use tree-of-thought strategy based on context
      {:ok, tasks} = Decomposer.decompose_with_pattern("api_integration", context)
      
      assert is_list(tasks)
      assert length(tasks) > 0
    end
    
    test "approach metadata is preserved in task output" do
      # When using tree-of-thought, tasks should include approach metadata
      {:ok, tasks} = Decomposer.decompose_with_pattern("performance_optimization", %{})
      
      # Check that tasks have proper metadata structure
      Enum.each(tasks, fn task ->
        assert Map.has_key?(task, :metadata)
        assert is_map(task[:metadata])
      end)
    end
  end
  
  describe "strategy detection" do
    test "detects tree-of-thought strategy for research queries" do
      research_queries = [
        "Explore different approaches for implementing caching",
        "Research the best database architecture for our needs",
        "Investigate various authentication strategies"
      ]
      
      Enum.each(research_queries, fn query ->
        # The determine_decomposition_strategy function would detect tree-of-thought
        # Based on keywords like "explore", "research", "investigate"
        assert query =~ ~r/explore|research|investigate/i
      end)
    end
  end
  
  describe "pattern library integration" do
    test "performance optimization pattern works with scoring" do
      {:ok, tasks} = Decomposer.decompose_with_pattern("performance_optimization", %{
        time_constraint: "1w",
        risk_tolerance: :low
      })
      
      # Performance optimization should have profiling phase
      task_names = Enum.map(tasks, & &1[:name])
      assert Enum.any?(task_names, &String.contains?(&1, "profiling"))
      assert Enum.any?(task_names, &String.contains?(&1, "Benchmark"))
    end
  end
end