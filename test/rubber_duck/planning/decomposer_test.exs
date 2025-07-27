defmodule RubberDuck.Planning.DecomposerTest do
  use RubberDuck.DataCase, async: true
  
  alias RubberDuck.Planning.Decomposer
  alias RubberDuck.LLM.Providers.Mock, as: MockProvider
  
  setup do
    # Set up mock responses for the LLM calls
    MockProvider.set_completion_response(%{
      content: "linear",
      model: "test-model",
      usage: %{total_tokens: 10}
    })
    
    :ok
  end
  
  describe "decompose/2" do
    test "decomposes a simple task description" do
      description = "Create a user authentication system with email and password"
      context = %{
        strategy: :linear,
        provider: :mock,
        model: "test-model"
      }
      
      assert {:ok, tasks} = Decomposer.decompose(description, context)
      assert is_list(tasks)
      assert length(tasks) > 0
      
      # Check the structure of the first task
      [first_task | _] = tasks
      assert Map.has_key?(first_task, :name)
      assert Map.has_key?(first_task, :description)
      assert Map.has_key?(first_task, :position)
      assert Map.has_key?(first_task, :complexity)
      assert Map.has_key?(first_task, :success_criteria)
    end
    
    test "uses hierarchical strategy for feature requests" do
      description = "Build a comprehensive dashboard feature with charts and analytics"
      context = %{
        provider: :mock,
        model: "test-model"
      }
      
      assert {:ok, tasks} = Decomposer.decompose(description, context)
      assert is_list(tasks)
      
      # Should detect hierarchical strategy automatically
      # Tasks should be grouped by component/phase
      assert length(tasks) > 3
    end
    
    test "handles errors gracefully" do
      description = ""
      context = %{
        strategy: :invalid_strategy,
        provider: :mock,
        model: "test-model"
      }
      
      # Should still return a result even with invalid strategy
      assert {:ok, tasks} = Decomposer.decompose(description, context)
      assert is_list(tasks)
    end
  end
  
  describe "list_patterns/0" do
    test "returns available decomposition patterns" do
      patterns = Decomposer.list_patterns()
      
      assert is_list(patterns)
      assert "feature_implementation" in patterns
      assert "bug_fix" in patterns
      assert "refactoring" in patterns
    end
  end
  
  describe "decompose_with_pattern/2" do
    test "applies a specific pattern" do
      pattern_name = "bug_fix"
      context = %{
        description: "Fix login timeout issue",
        provider: :mock,
        model: "test-model"
      }
      
      assert {:ok, tasks} = Decomposer.decompose_with_pattern(pattern_name, context)
      assert is_list(tasks)
      
      # Bug fix pattern should have investigation phase
      task_names = Enum.map(tasks, & &1[:name])
      assert Enum.any?(task_names, &String.contains?(&1, "Reproduce"))
    end
  end
end