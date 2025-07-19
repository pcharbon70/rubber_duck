defmodule RubberDuck.CoT.Chains.ProblemSolverChain do
  @moduledoc """
  Chain-of-Thought reasoning chain for general problem solving.

  This chain provides a systematic approach to decomposing and solving
  complex problems through structured reasoning.
  """

  @behaviour RubberDuck.CoT.ChainBehaviour

  def config do
    %{
      name: :problem_solver,
      description: "General purpose problem solving with systematic reasoning",
      max_steps: 10,
      timeout: 45_000,
      template: :analytical,
      # 20 minutes
      cache_ttl: 1200
    }
  end

  def steps do
    [
      %{
        name: :understand_problem,
        prompt: """
        Let me understand the problem at hand:

        Problem statement: {{query}}
        Context: {{context}}

        I'll identify:
        1. Core problem to be solved
        2. Given constraints and requirements
        3. Available resources and information
        4. Success criteria
        5. Potential challenges

        Problem understanding:
        """,
        validates: [:problem_understood],
        timeout: 8_000
      },
      %{
        name: :decompose_problem,
        prompt: """
        Now I'll break down the problem into manageable components:

        Problem: {{previous_result}}

        Decomposition approach:
        1. Identify main components
        2. Find sub-problems within each component
        3. Determine dependencies between components
        4. Order by logical sequence
        5. Identify parallel vs sequential tasks

        Problem decomposition:
        """,
        depends_on: :understand_problem,
        validates: [:has_components],
        timeout: 7_000
      },
      %{
        name: :analyze_components,
        prompt: """
        Let me analyze each component in detail:

        Components: {{previous_result}}

        For each component, I'll examine:
        1. Specific requirements
        2. Potential solutions
        3. Trade-offs and constraints
        4. Required expertise or tools
        5. Risk factors

        Component analysis:
        """,
        depends_on: :decompose_problem,
        validates: [:components_analyzed],
        timeout: 10_000
      },
      %{
        name: :explore_solutions,
        prompt: """
        I'll explore potential solutions for each component:

        Analysis: {{previous_result}}
        Available tools: {{available_tools}}

        Solution exploration:
        1. Standard approaches
        2. Creative alternatives
        3. Hybrid solutions
        4. Proven patterns
        5. Novel approaches

        Potential solutions:
        """,
        depends_on: :analyze_components,
        validates: [:has_solutions],
        timeout: 10_000
      },
      %{
        name: :evaluate_tradeoffs,
        prompt: """
        Let me evaluate the trade-offs of different approaches:

        Solutions: {{previous_result}}
        Constraints: {{constraints}}

        Evaluation criteria:
        1. Complexity vs simplicity
        2. Performance vs maintainability
        3. Time to implement vs long-term benefits
        4. Resource requirements
        5. Risk vs reward

        Trade-off analysis:
        """,
        depends_on: :explore_solutions,
        validates: [:tradeoffs_evaluated],
        timeout: 8_000
      },
      %{
        name: :synthesize_solution,
        prompt: """
        Now I'll synthesize the best overall solution:

        Components: {{analyze_components_result}}
        Solutions: {{explore_solutions_result}}
        Trade-offs: {{previous_result}}

        Synthesis approach:
        1. Select best approach for each component
        2. Ensure component compatibility
        3. Optimize interfaces between components
        4. Create cohesive overall solution
        5. Validate against original requirements

        Synthesized solution:
        """,
        depends_on: :evaluate_tradeoffs,
        validates: [:solution_synthesized],
        timeout: 10_000
      },
      %{
        name: :create_action_plan,
        prompt: """
        Let me create a concrete action plan:

        Solution: {{previous_result}}

        Action plan structure:
        1. Step-by-step implementation guide
        2. Required preparations
        3. Milestones and checkpoints
        4. Testing and validation steps
        5. Rollback procedures

        Detailed action plan:
        """,
        depends_on: :synthesize_solution,
        validates: [:has_action_plan],
        timeout: 8_000
      },
      %{
        name: :verify_approach,
        prompt: """
        Finally, let me verify this approach:

        Solution: {{synthesize_solution_result}}
        Action plan: {{previous_result}}
        Original problem: {{understand_problem_result}}

        Verification checklist:
        1. Does it solve the original problem?
        2. Are all constraints satisfied?
        3. Is the approach practical?
        4. Are there any gaps or risks?
        5. Is the solution maintainable?

        Verification results:
        """,
        depends_on: :create_action_plan,
        validates: [:approach_verified],
        timeout: 7_000
      }
    ]
  end

  # Validation functions

  def problem_understood(%{result: result}) do
    result != nil && String.length(result) > 40
  end

  def has_components(%{result: result}) do
    result != nil && String.contains?(result, ["component", "part", "sub-problem", "element"])
  end

  def components_analyzed(%{result: result}) do
    result != nil && String.length(result) > 50
  end

  def has_solutions(%{result: result}) do
    result != nil && String.contains?(result, ["solution", "approach", "method", "strategy"])
  end

  def tradeoffs_evaluated(%{result: result}) do
    result != nil && String.contains?(result, ["trade-off", "vs", "balance", "consideration"])
  end

  def solution_synthesized(%{result: result}) do
    result != nil && String.length(result) > 60
  end

  def has_action_plan(%{result: result}) do
    result != nil && String.contains?(result, ["step", "action", "implement", "plan"])
  end

  def approach_verified(%{result: result}) do
    result != nil && !String.contains?(String.downcase(result), ["fail", "missing", "gap", "risk"])
  end
end
