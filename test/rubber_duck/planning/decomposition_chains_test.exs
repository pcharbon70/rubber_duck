defmodule RubberDuck.Planning.DecompositionChainsTest do
  use ExUnit.Case, async: true
  
  alias RubberDuck.Planning.DecompositionChains.{
    LinearDecomposition,
    HierarchicalDecomposition,
    TreeOfThoughtDecomposition,
    TaskValidation,
    RefinementChain
  }
  
  describe "LinearDecomposition chain" do
    test "has correct chain structure" do
      config = LinearDecomposition.config()
      
      assert config.name == :linear_decomposition
      assert config.description =~ "sequential tasks"
      
      steps = LinearDecomposition.steps()
      assert length(steps) == 4
      
      step_names = Enum.map(steps, & &1.name)
      assert :understand_request in step_names
      assert :identify_steps in step_names
      assert :add_details in step_names
      assert :validate_sequence in step_names
    end
    
    test "steps have proper dependencies" do
      steps = LinearDecomposition.steps()
      
      identify_steps = Enum.find(steps, & &1.name == :identify_steps)
      assert identify_steps.depends_on == [:understand_request]
      
      add_details = Enum.find(steps, & &1.name == :add_details)
      assert add_details.depends_on == [:identify_steps]
      
      validate_sequence = Enum.find(steps, & &1.name == :validate_sequence)
      assert validate_sequence.depends_on == [:add_details]
    end
    
    test "has validators" do
      validators = LinearDecomposition.validators()
      assert is_map(validators)
      assert Map.has_key?(validators, :has_goal_understanding)
      assert Map.has_key?(validators, :has_steps)
    end
  end
  
  describe "HierarchicalDecomposition chain" do
    test "has correct chain structure" do
      config = HierarchicalDecomposition.config()
      
      assert config.name == :hierarchical_decomposition
      assert config.description =~ "hierarchical tasks"
      
      steps = HierarchicalDecomposition.steps()
      assert length(steps) == 5
      
      step_names = Enum.map(steps, & &1.name)
      assert :analyze_scope in step_names
      assert :create_hierarchy in step_names
      assert :define_relationships in step_names
      assert :estimate_effort in step_names
      assert :generate_success_criteria in step_names
    end
    
    test "all steps depend on create_hierarchy except first" do
      steps = HierarchicalDecomposition.steps()
      
      analyze_scope = Enum.find(steps, & &1.name == :analyze_scope)
      assert analyze_scope[:depends_on] == nil
      
      create_hierarchy = Enum.find(steps, & &1.name == :create_hierarchy)
      assert create_hierarchy.depends_on == [:analyze_scope]
      
      other_steps = Enum.filter(steps, & &1.name not in [:analyze_scope, :create_hierarchy])
      
      Enum.each(other_steps, fn step ->
        assert :create_hierarchy in (step[:depends_on] || [])
      end)
    end
  end
  
  describe "TreeOfThoughtDecomposition chain" do
    test "has correct chain structure" do
      config = TreeOfThoughtDecomposition.config()
      
      assert config.name == :tree_of_thought_decomposition
      assert config.description =~ "multiple approaches"
      
      steps = TreeOfThoughtDecomposition.steps()
      assert length(steps) == 6
      
      # Should have brainstorm and 3 detail steps
      step_names = Enum.map(steps, & &1.name)
      assert :brainstorm_approaches in step_names
      assert :detail_approach_1 in step_names
      assert :detail_approach_2 in step_names
      assert :detail_approach_3 in step_names
      assert :evaluate_approaches in step_names
      assert :synthesize_best_approach in step_names
    end
    
    test "evaluation depends on all detail steps" do
      steps = TreeOfThoughtDecomposition.steps()
      
      evaluate = Enum.find(steps, & &1.name == :evaluate_approaches)
      
      assert :detail_approach_1 in evaluate.depends_on
      assert :detail_approach_2 in evaluate.depends_on
      assert :detail_approach_3 in evaluate.depends_on
    end
  end
  
  describe "TaskValidation chain" do
    test "has correct validation steps" do
      config = TaskValidation.config()
      
      assert config.name == :task_validation
      
      steps = TaskValidation.steps()
      step_names = Enum.map(steps, & &1.name)
      
      assert :check_completeness in step_names
      assert :verify_dependencies in step_names
      assert :assess_complexity in step_names
      assert :validate_criteria in step_names
      assert :final_recommendations in step_names
    end
    
    test "final recommendations depends on all validations" do
      steps = TaskValidation.steps()
      
      final_rec = Enum.find(steps, & &1.name == :final_recommendations)
      
      assert :verify_dependencies in final_rec.depends_on
      assert :assess_complexity in final_rec.depends_on
      assert :validate_criteria in final_rec.depends_on
    end
  end
  
  describe "RefinementChain" do
    test "has correct refinement flow" do
      config = RefinementChain.config()
      
      assert config.name == :task_refinement
      
      steps = RefinementChain.steps()
      assert length(steps) == 4
      
      # Check step order makes sense
      step_names = Enum.map(steps, & &1.name)
      expected_names = [
        :identify_issues,
        :propose_solutions,
        :apply_refinements,
        :verify_improvements
      ]
      
      Enum.each(expected_names, fn name ->
        assert name in step_names
      end)
    end
    
    test "steps have linear dependencies" do
      steps = RefinementChain.steps()
      
      propose = Enum.find(steps, & &1.name == :propose_solutions)
      assert propose.depends_on == [:identify_issues]
      
      apply = Enum.find(steps, & &1.name == :apply_refinements)
      assert apply.depends_on == [:propose_solutions]
      
      verify = Enum.find(steps, & &1.name == :verify_improvements)
      assert verify.depends_on == [:apply_refinements]
    end
  end
  
  describe "prompt templates" do
    test "all chains have non-empty prompts" do
      chains = [
        LinearDecomposition,
        HierarchicalDecomposition,
        TreeOfThoughtDecomposition,
        TaskValidation,
        RefinementChain
      ]
      
      Enum.each(chains, fn chain_module ->
        steps = chain_module.steps()
        
        Enum.each(steps, fn step ->
          assert step.prompt != nil
          assert String.length(step.prompt) > 10
          assert step.prompt =~ ~r/\{\{.*\}\}/  # Has template variables
        end)
      end)
    end
  end
  
  describe "all chains implement behaviour" do
    test "all chains have required functions" do
      chains = [
        LinearDecomposition,
        HierarchicalDecomposition,
        TreeOfThoughtDecomposition,
        TaskValidation,
        RefinementChain
      ]
      
      Enum.each(chains, fn chain_module ->
        assert function_exported?(chain_module, :config, 0)
        assert function_exported?(chain_module, :steps, 0)
        assert function_exported?(chain_module, :validators, 0)
      end)
    end
  end
end