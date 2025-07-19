defmodule RubberDuck.Planning.PatternLibraryTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Planning.PatternLibrary

  describe "list_patterns/0" do
    test "returns all available patterns" do
      patterns = PatternLibrary.list_patterns()

      assert "feature_implementation" in patterns
      assert "bug_fix" in patterns
      assert "refactoring" in patterns
      assert "api_integration" in patterns
      assert "database_migration" in patterns
      assert "performance_optimization" in patterns
    end
  end

  describe "get_pattern/1" do
    test "returns pattern when it exists" do
      assert {:ok, pattern} = PatternLibrary.get_pattern("feature_implementation")

      assert pattern.name == "Feature Implementation"
      assert pattern.strategy == :hierarchical
      assert is_list(pattern.phases)
      # Design, Implementation, Testing, Documentation
      assert length(pattern.phases) == 4
    end

    test "returns error for non-existent pattern" do
      assert {:error, :pattern_not_found} = PatternLibrary.get_pattern("non_existent")
    end

    test "bug_fix pattern has correct structure" do
      assert {:ok, pattern} = PatternLibrary.get_pattern("bug_fix")

      assert pattern.strategy == :linear
      assert pattern.typical_dependencies == "strictly_linear"

      phase_names = Enum.map(pattern.phases, & &1.name)
      assert "Investigation" in phase_names
      assert "Fix" in phase_names
      assert "Verification" in phase_names
    end
  end

  describe "find_matching_patterns/1" do
    test "finds patterns matching characteristics" do
      assert {:ok, matches} = PatternLibrary.find_matching_patterns("new functionality")

      pattern_names = Enum.map(matches, fn {name, _} -> name end)
      assert "feature_implementation" in pattern_names
    end

    test "finds multiple matches for broad characteristics" do
      assert {:ok, matches} = PatternLibrary.find_matching_patterns("improving")

      pattern_names = Enum.map(matches, fn {name, _} -> name end)
      assert "refactoring" in pattern_names
      assert "performance_optimization" in pattern_names
    end

    test "returns empty list for no matches" do
      assert {:ok, matches} = PatternLibrary.find_matching_patterns("xyz123")
      assert matches == []
    end
  end

  describe "apply_pattern/2" do
    test "creates task decomposition from pattern" do
      assert {:ok, decomposition} = PatternLibrary.apply_pattern("bug_fix")

      assert is_list(decomposition.tasks)
      assert length(decomposition.tasks) > 0
      assert decomposition.pattern == "bug_fix"
      assert decomposition.strategy == :linear

      # Check task structure
      first_task = List.first(decomposition.tasks)
      assert Map.has_key?(first_task, "id")
      assert Map.has_key?(first_task, "name")
      assert Map.has_key?(first_task, "phase")
      assert Map.has_key?(first_task, "complexity")
      assert Map.has_key?(first_task, "success_criteria")
    end

    test "generates correct dependencies for linear pattern" do
      assert {:ok, decomposition} = PatternLibrary.apply_pattern("bug_fix")

      deps = decomposition.dependencies
      assert is_list(deps)

      # Linear pattern should have sequential dependencies
      Enum.each(deps, fn dep ->
        assert dep["type"] == "finish_to_start"
      end)
    end

    test "marks optional tasks correctly" do
      assert {:ok, decomposition} = PatternLibrary.apply_pattern("feature_implementation")

      optional_tasks = Enum.filter(decomposition.tasks, & &1["optional"])
      assert length(optional_tasks) > 0

      # UI/UX mockups should be optional
      ui_task = Enum.find(decomposition.tasks, &(&1["name"] == "Design UI/UX mockups"))
      assert ui_task["optional"] == true
    end
  end

  describe "adapt_pattern/2" do
    test "merges modifications into pattern" do
      modifications = %{
        phases: [
          %{
            name: "Extra Phase",
            tasks: [
              %{name: "Extra Task", complexity: :simple}
            ]
          }
        ]
      }

      assert {:ok, adapted} = PatternLibrary.adapt_pattern("bug_fix", modifications)

      phase_names = Enum.map(adapted.phases, & &1.name)
      assert "Extra Phase" in phase_names
    end
  end

  describe "learn_pattern/3" do
    test "creates new pattern from decomposition" do
      decomposition = %{
        strategy: :linear,
        tasks: [
          %{"name" => "Task 1", "phase" => "Phase 1", "complexity" => "simple"},
          %{"name" => "Task 2", "phase" => "Phase 1", "complexity" => "medium"}
        ],
        dependencies: [
          %{"from" => "task_0", "to" => "task_1", "type" => "finish_to_start"}
        ]
      }

      metadata = %{
        description: "Test pattern",
        applicable_when: ["testing"]
      }

      assert {:ok, pattern} = PatternLibrary.learn_pattern("test_pattern", decomposition, metadata)

      assert pattern.name == "test_pattern"
      assert pattern.description == "Test pattern"
      assert pattern.strategy == :linear
      assert is_list(pattern.phases)
    end
  end

  describe "pattern content validation" do
    test "all patterns have required fields" do
      patterns = PatternLibrary.list_patterns()

      Enum.each(patterns, fn pattern_name ->
        {:ok, pattern} = PatternLibrary.get_pattern(pattern_name)

        assert pattern.name != nil
        assert pattern.description != nil
        assert pattern.applicable_when != nil
        assert pattern.strategy in [:linear, :hierarchical, :tree_of_thought]
        assert is_list(pattern.phases)
        assert pattern.typical_dependencies != nil
      end)
    end

    test "all tasks have required attributes" do
      patterns = PatternLibrary.list_patterns()

      Enum.each(patterns, fn pattern_name ->
        {:ok, pattern} = PatternLibrary.get_pattern(pattern_name)

        Enum.each(pattern.phases, fn phase ->
          assert phase.name != nil
          assert is_list(phase.tasks)

          Enum.each(phase.tasks, fn task ->
            assert task.name != nil
            assert task.complexity in [:trivial, :simple, :medium, :complex, :very_complex, :variable]
            assert is_list(task.success_criteria)
          end)
        end)
      end)
    end
  end
end
