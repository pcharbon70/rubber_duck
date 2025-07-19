defmodule RubberDuck.Planning.DecompositionChains do
  @moduledoc """
  Chain-of-Thought reasoning chains for task decomposition.

  Provides structured reasoning chains for different decomposition strategies
  and validation workflows.
  """

  defmodule LinearDecomposition do
    @moduledoc """
    Chain for linear task decomposition - simple sequential tasks.
    """

    @behaviour RubberDuck.CoT.ChainBehaviour

    def config do
      %{
        name: :linear_decomposition,
        description: "Decompose a request into sequential tasks",
        max_steps: 10,
        timeout: 30_000,
        template: :structured,
        cache_ttl: 1800
      }
    end

    def steps do
      [
        %{
          name: :understand_request,
          prompt: """
          Analyze this request and identify the main goal:

          {{query}}

          What is the user trying to achieve? Be specific.
          """,
          validates: [:has_goal_understanding],
          timeout: 5_000
        },
        %{
          name: :identify_steps,
          prompt: """
          Based on the goal: {{understand_request}}

          List the sequential steps needed to achieve this goal.
          Each step should be:
          - Atomic (can't be broken down further)
          - Actionable (clear what needs to be done)
          - Measurable (clear when it's complete)

          Number each step.
          """,
          depends_on: [:understand_request],
          validates: [:has_steps],
          timeout: 8_000
        },
        %{
          name: :add_details,
          prompt: """
          For each step identified:
          {{identify_steps}}

          Add:
          1. Estimated complexity (trivial/simple/medium/complex/very_complex)
          2. Success criteria (how to know it's done)
          3. Any prerequisites or dependencies
          """,
          depends_on: [:identify_steps],
          validates: [:has_detailed_steps],
          timeout: 10_000
        },
        %{
          name: :validate_sequence,
          prompt: """
          Review the task sequence:
          {{add_details}}

          Check for:
          - Missing steps
          - Incorrect ordering
          - Unrealistic complexity estimates

          Provide a final, validated task list.
          """,
          depends_on: [:add_details],
          validates: [:has_validated_sequence],
          timeout: 5_000
        }
      ]
    end

    def validators do
      %{
        has_goal_understanding: fn result ->
          String.length(result) > 20
        end,
        has_steps: fn result ->
          String.contains?(result, ["1.", "2.", "step", "Step"])
        end,
        has_detailed_steps: fn result ->
          String.contains?(result, ["complexity", "criteria", "Complexity", "Criteria"])
        end,
        has_validated_sequence: fn result ->
          String.contains?(result, ["task", "Task", "validated", "final"])
        end
      }
    end
  end

  defmodule HierarchicalDecomposition do
    @moduledoc """
    Chain for hierarchical task decomposition - complex features with sub-tasks.
    """

    @behaviour RubberDuck.CoT.ChainBehaviour

    def config do
      %{
        name: :hierarchical_decomposition,
        description: "Decompose a complex request into hierarchical tasks",
        max_steps: 12,
        timeout: 45_000,
        template: :structured,
        cache_ttl: 1800
      }
    end

    def steps do
      [
        %{
          name: :analyze_scope,
          prompt: """
          Analyze the scope and complexity of this request:

          {{query}}

          Identify:
          1. Main components or modules
          2. Key phases or milestones
          3. Major dependencies or constraints
          """,
          validates: [:has_scope_analysis],
          timeout: 8_000
        },
        %{
          name: :create_hierarchy,
          prompt: """
          Based on the analysis:
          {{analyze_scope}}

          Create a hierarchical task structure:
          - Level 1: Major phases or components
          - Level 2: Tasks within each phase
          - Level 3: Sub-tasks if needed

          Use indentation to show hierarchy.
          """,
          depends_on: [:analyze_scope],
          validates: [:has_hierarchy],
          timeout: 12_000
        },
        %{
          name: :define_relationships,
          prompt: """
          For the hierarchy:
          {{create_hierarchy}}

          Define relationships:
          1. Dependencies between tasks (which must complete before others)
          2. Parallel tasks (which can be done simultaneously)
          3. Optional vs required tasks
          """,
          depends_on: [:create_hierarchy],
          validates: [:has_relationships],
          timeout: 8_000
        },
        %{
          name: :estimate_effort,
          prompt: """
          For each task in the hierarchy:
          {{create_hierarchy}}

          Estimate:
          1. Complexity level
          2. Approximate effort (in relative units)
          3. Risk factors

          Roll up estimates to parent tasks.
          """,
          depends_on: [:create_hierarchy],
          validates: [:has_estimates],
          timeout: 10_000
        },
        %{
          name: :generate_success_criteria,
          prompt: """
          For each task and phase:
          {{create_hierarchy}}

          Define clear success criteria:
          - Measurable outcomes
          - Quality standards
          - Acceptance criteria

          Ensure child task criteria support parent task success.
          """,
          depends_on: [:create_hierarchy],
          validates: [:has_success_criteria],
          timeout: 10_000
        }
      ]
    end

    def validators do
      %{
        has_scope_analysis: fn result ->
          String.contains?(result, ["component", "phase", "depend", "Component", "Phase"])
        end,
        has_hierarchy: fn result ->
          String.contains?(result, ["Level", "level", "-", "  ", "\t"])
        end,
        has_relationships: fn result ->
          String.contains?(result, ["depend", "parallel", "optional", "Depend", "Parallel"])
        end,
        has_estimates: fn result ->
          String.contains?(result, ["complex", "effort", "risk", "Complex", "Effort"])
        end,
        has_success_criteria: fn result ->
          String.contains?(result, ["criteria", "outcome", "standard", "Criteria", "Outcome"])
        end
      }
    end
  end

  defmodule TreeOfThoughtDecomposition do
    @moduledoc """
    Chain for tree-of-thought decomposition - exploring multiple approaches.
    """

    @behaviour RubberDuck.CoT.ChainBehaviour

    def config do
      %{
        name: :tree_of_thought_decomposition,
        description: "Explore multiple decomposition approaches",
        max_steps: 15,
        timeout: 60_000,
        template: :exploratory,
        cache_ttl: 1800
      }
    end

    def steps do
      [
        %{
          name: :brainstorm_approaches,
          prompt: """
          For this request:
          {{query}}

          Brainstorm 3-4 different approaches to tackle it:
          1. Name each approach
          2. Briefly describe the strategy
          3. List pros and cons

          Be creative and consider different perspectives.
          """,
          validates: [:has_multiple_approaches],
          timeout: 10_000
        },
        %{
          name: :detail_approach_1,
          prompt: """
          For the first approach from:
          {{brainstorm_approaches}}

          Create a detailed task breakdown:
          - List all tasks needed
          - Identify dependencies
          - Estimate complexity
          - Note any risks or assumptions
          """,
          depends_on: [:brainstorm_approaches],
          validates: [:has_task_breakdown],
          timeout: 8_000
        },
        %{
          name: :detail_approach_2,
          prompt: """
          For the second approach from:
          {{brainstorm_approaches}}

          Create a detailed task breakdown:
          - List all tasks needed
          - Identify dependencies
          - Estimate complexity
          - Note any risks or assumptions
          """,
          depends_on: [:brainstorm_approaches],
          validates: [:has_task_breakdown],
          timeout: 8_000
        },
        %{
          name: :detail_approach_3,
          prompt: """
          For the third approach from:
          {{brainstorm_approaches}}

          Create a detailed task breakdown:
          - List all tasks needed
          - Identify dependencies
          - Estimate complexity
          - Note any risks or assumptions
          """,
          depends_on: [:brainstorm_approaches],
          validates: [:has_task_breakdown],
          timeout: 8_000
        },
        %{
          name: :evaluate_approaches,
          prompt: """
          Compare the detailed approaches:

          Approach 1: {{detail_approach_1}}
          Approach 2: {{detail_approach_2}}
          Approach 3: {{detail_approach_3}}

          Evaluate based on:
          1. Total complexity
          2. Risk level
          3. Resource requirements
          4. Time to completion
          5. Likelihood of success

          Recommend the best approach and explain why.
          """,
          depends_on: [:detail_approach_1, :detail_approach_2, :detail_approach_3],
          validates: [:has_evaluation],
          timeout: 10_000
        },
        %{
          name: :synthesize_best_approach,
          prompt: """
          Based on the evaluation:
          {{evaluate_approaches}}

          Create the final task decomposition:
          1. Take the recommended approach
          2. Incorporate any good ideas from other approaches
          3. Address identified risks
          4. Provide final task list with all details
          """,
          depends_on: [:evaluate_approaches],
          validates: [:has_final_decomposition],
          timeout: 10_000
        }
      ]
    end

    def validators do
      %{
        has_multiple_approaches: fn result ->
          String.contains?(result, ["Approach", "approach", "1.", "2.", "3."])
        end,
        has_task_breakdown: fn result ->
          String.contains?(result, ["task", "Task", "depend", "complex"])
        end,
        has_evaluation: fn result ->
          String.contains?(result, ["recommend", "best", "Recommend", "Best"])
        end,
        has_final_decomposition: fn result ->
          String.contains?(result, ["final", "task", "Final", "Task"])
        end
      }
    end
  end

  defmodule TaskValidation do
    @moduledoc """
    Chain for validating decomposed tasks.
    """

    @behaviour RubberDuck.CoT.ChainBehaviour

    def config do
      %{
        name: :task_validation,
        description: "Validate a task decomposition",
        max_steps: 8,
        timeout: 30_000,
        template: :analytical,
        cache_ttl: 900
      }
    end

    def steps do
      [
        %{
          name: :check_completeness,
          prompt: """
          Review this task decomposition:
          {{tasks}}

          Check for completeness:
          1. Does it fully address the original request?
          2. Are there any missing steps?
          3. Are all edge cases considered?
          4. Is error handling included where needed?
          """,
          validates: [:has_completeness_check],
          timeout: 6_000
        },
        %{
          name: :verify_dependencies,
          prompt: """
          Analyze task dependencies:
          {{tasks}}
          {{dependencies}}

          Verify:
          1. All dependencies make logical sense
          2. No circular dependencies exist
          3. Dependencies are minimal (no unnecessary ones)
          4. Critical path is reasonable
          """,
          depends_on: [:check_completeness],
          validates: [:has_dependency_verification],
          timeout: 6_000
        },
        %{
          name: :assess_complexity,
          prompt: """
          Review complexity estimates:
          {{tasks}}

          Assess:
          1. Are complexity ratings realistic?
          2. Is the overall complexity manageable?
          3. Should any complex tasks be further decomposed?
          4. Is the complexity evenly distributed?
          """,
          depends_on: [:check_completeness],
          validates: [:has_complexity_assessment],
          timeout: 5_000
        },
        %{
          name: :validate_criteria,
          prompt: """
          Examine success criteria:
          {{tasks}}

          Validate that each task has:
          1. Clear, measurable success criteria
          2. Realistic acceptance standards
          3. Testable outcomes
          4. No ambiguous requirements
          """,
          depends_on: [:check_completeness],
          validates: [:has_criteria_validation],
          timeout: 5_000
        },
        %{
          name: :final_recommendations,
          prompt: """
          Based on all validations:
          - Completeness: {{check_completeness}}
          - Dependencies: {{verify_dependencies}}
          - Complexity: {{assess_complexity}}
          - Criteria: {{validate_criteria}}

          Provide:
          1. Overall assessment (valid/needs work)
          2. Specific improvements needed
          3. Risk factors to monitor
          4. Final recommendation
          """,
          depends_on: [:verify_dependencies, :assess_complexity, :validate_criteria],
          validates: [:has_final_assessment],
          timeout: 8_000
        }
      ]
    end

    def validators do
      %{
        has_completeness_check: fn result ->
          String.contains?(result, ["complete", "missing", "Complete", "Missing"])
        end,
        has_dependency_verification: fn result ->
          String.contains?(result, ["depend", "circular", "Depend", "Circular"])
        end,
        has_complexity_assessment: fn result ->
          String.contains?(result, ["complex", "realistic", "Complex", "Realistic"])
        end,
        has_criteria_validation: fn result ->
          String.contains?(result, ["criteria", "measurable", "Criteria", "Measurable"])
        end,
        has_final_assessment: fn result ->
          String.contains?(result, ["assessment", "recommend", "Assessment", "Recommend"])
        end
      }
    end
  end

  defmodule RefinementChain do
    @moduledoc """
    Chain for iterative refinement of task decompositions.
    """

    @behaviour RubberDuck.CoT.ChainBehaviour

    def config do
      %{
        name: :task_refinement,
        description: "Refine and improve a task decomposition",
        max_steps: 6,
        timeout: 25_000,
        template: :iterative,
        cache_ttl: 900
      }
    end

    def steps do
      [
        %{
          name: :identify_issues,
          prompt: """
          Review this task decomposition and feedback:
          {{tasks}}
          {{feedback}}

          Identify specific issues:
          1. Which tasks need clarification?
          2. What dependencies are problematic?
          3. Where is complexity underestimated?
          4. What success criteria are vague?
          """,
          validates: [:has_issue_identification],
          timeout: 5_000
        },
        %{
          name: :propose_solutions,
          prompt: """
          For each issue identified:
          {{identify_issues}}

          Propose specific solutions:
          1. How to clarify unclear tasks
          2. How to fix dependency problems
          3. How to better estimate complexity
          4. How to improve success criteria
          """,
          depends_on: [:identify_issues],
          validates: [:has_solutions],
          timeout: 6_000
        },
        %{
          name: :apply_refinements,
          prompt: """
          Apply the proposed solutions:
          {{propose_solutions}}

          To the original tasks:
          {{tasks}}

          Provide the refined task list with all improvements incorporated.
          """,
          depends_on: [:propose_solutions],
          validates: [:has_refined_tasks],
          timeout: 8_000
        },
        %{
          name: :verify_improvements,
          prompt: """
          Compare refined version:
          {{apply_refinements}}

          With original:
          {{tasks}}

          Verify:
          1. All issues have been addressed
          2. No new problems introduced
          3. Overall quality improved
          4. Ready for execution
          """,
          depends_on: [:apply_refinements],
          validates: [:has_verification],
          timeout: 6_000
        }
      ]
    end

    def validators do
      %{
        has_issue_identification: fn result ->
          String.contains?(result, ["issue", "problem", "Issue", "Problem"])
        end,
        has_solutions: fn result ->
          String.contains?(result, ["solution", "fix", "improve", "Solution", "Fix"])
        end,
        has_refined_tasks: fn result ->
          String.contains?(result, ["refined", "improved", "Refined", "Improved"])
        end,
        has_verification: fn result ->
          String.contains?(result, ["verify", "addressed", "improved", "Verify", "Addressed"])
        end
      }
    end
  end
end
