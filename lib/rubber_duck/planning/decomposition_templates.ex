defmodule RubberDuck.Planning.DecompositionTemplates do
  @moduledoc """
  Prompt templates for task decomposition operations.

  Provides structured templates for different aspects of task decomposition,
  complexity estimation, and validation.
  """

  @doc """
  Template for analyzing a request to determine decomposition strategy.
  """
  def strategy_selection_template do
    """
    Analyze this request and determine the most appropriate decomposition strategy.

    REQUEST: {{request}}
    CONTEXT: {{context}}

    Consider these factors:
    1. Request complexity (simple action vs multi-phase project)
    2. Dependencies (sequential vs parallel work possible)
    3. Uncertainty level (well-defined vs exploratory)
    4. Scope (single feature vs system-wide change)

    Available strategies:
    - LINEAR: Best for simple, sequential tasks with clear steps
    - HIERARCHICAL: Best for complex features with multiple components
    - TREE_OF_THOUGHT: Best for exploratory tasks where approach is uncertain

    Respond with:
    {
      "strategy": "LINEAR|HIERARCHICAL|TREE_OF_THOUGHT",
      "reasoning": "Brief explanation of why this strategy fits",
      "complexity_indicator": "low|medium|high",
      "estimated_tasks": <approximate number>
    }
    """
  end

  @doc """
  Template for linear task decomposition.
  """
  def linear_decomposition_template do
    """
    Break down this request into a linear sequence of tasks.

    REQUEST: {{request}}
    CONTEXT: {{context}}
    CONSTRAINTS: {{constraints}}

    Create a step-by-step task list where each task:
    1. Has a clear, actionable name (verb + noun)
    2. Includes a detailed description
    3. Can be completed independently (once dependencies are met)
    4. Has measurable completion criteria

    Format each task as:
    {
      "position": <number starting from 0>,
      "name": "Clear task name",
      "description": "Detailed description of what needs to be done",
      "complexity": "trivial|simple|medium|complex|very_complex",
      "estimated_duration": "15m|30m|1h|2h|4h|1d|2d|1w",
      "success_criteria": {
        "criteria": ["Specific measurable outcome 1", "Specific measurable outcome 2"]
      },
      "dependencies": [<positions of tasks this depends on>],
      "risks": ["Potential risk or blocker"],
      "prerequisites": ["Required knowledge or resources"]
    }

    Return as JSON array ordered by execution sequence.
    """
  end

  @doc """
  Template for hierarchical task decomposition.
  """
  def hierarchical_decomposition_template do
    """
    Decompose this complex request into a hierarchical task structure.

    REQUEST: {{request}}
    CONTEXT: {{context}}
    SCOPE: {{scope}}

    Create a multi-level breakdown:

    LEVEL 1 - Major Phases/Components:
    - High-level phases or major system components
    - Each should represent a significant milestone

    LEVEL 2 - Primary Tasks:
    - Concrete tasks within each phase
    - Should be independently assignable

    LEVEL 3 - Sub-tasks (if needed):
    - Detailed steps within complex tasks
    - Only when task is too large for single work session

    Format as:
    {
      "phases": [
        {
          "id": "phase_1",
          "name": "Phase name",
          "description": "Phase description",
          "tasks": [
            {
              "id": "task_1_1",
              "name": "Task name",
              "description": "Task description",
              "complexity": "trivial|simple|medium|complex|very_complex",
              "subtasks": [
                {
                  "id": "subtask_1_1_1",
                  "name": "Subtask name",
                  "description": "Subtask description"
                }
              ]
            }
          ]
        }
      ],
      "dependencies": [
        {"from": "task_id", "to": "task_id", "type": "finish_to_start|start_to_start"}
      ],
      "critical_path": ["task_1_1", "task_2_1", ...]
    }
    """
  end

  @doc """
  Template for tree-of-thought exploration.
  """
  def tree_of_thought_template do
    """
    Explore multiple approaches for decomposing this request.

    REQUEST: {{request}}
    GOALS: {{goals}}
    CONSTRAINTS: {{constraints}}

    Generate 3 distinct approaches, each with different:
    - Philosophy (e.g., iterative vs waterfall, bottom-up vs top-down)
    - Risk profile (conservative vs aggressive)
    - Resource usage (time vs quality trade-offs)

    For each approach provide:
    {
      "approach_name": "Descriptive name",
      "philosophy": "Brief description of the approach",
      "pros": ["Advantage 1", "Advantage 2"],
      "cons": ["Disadvantage 1", "Disadvantage 2"],
      "best_when": "Conditions where this approach excels",
      "tasks": [<list of tasks as in linear template>],
      "estimated_total_effort": "2d|1w|2w|1m",
      "risk_level": "low|medium|high",
      "confidence_score": 0.0-1.0
    }

    Return as JSON array of 3 approaches.
    """
  end

  @doc """
  Template for complexity estimation.
  """
  def complexity_estimation_template do
    """
    Estimate the complexity of this task.

    TASK: {{task_name}}
    DESCRIPTION: {{task_description}}
    CONTEXT: {{context}}
    DEPENDENCIES: {{dependencies}}

    Consider these factors:

    TECHNICAL COMPLEXITY:
    - Algorithm complexity
    - Integration points
    - Technology stack familiarity
    - Performance requirements

    DOMAIN COMPLEXITY:
    - Business logic intricacy
    - Edge cases
    - Compliance/regulatory requirements
    - User experience considerations

    COORDINATION COMPLEXITY:
    - Team dependencies
    - External dependencies
    - Communication overhead
    - Approval processes

    RISK FACTORS:
    - Uncertainty level
    - Potential for scope creep
    - Technical debt
    - Testing difficulty

    Provide:
    {
      "complexity": "trivial|simple|medium|complex|very_complex",
      "technical_score": 1-5,
      "domain_score": 1-5,
      "coordination_score": 1-5,
      "risk_score": 1-5,
      "confidence": 0.0-1.0,
      "reasoning": "Brief explanation of the rating",
      "key_challenges": ["Challenge 1", "Challenge 2"],
      "mitigation_strategies": ["Strategy 1", "Strategy 2"]
    }
    """
  end

  @doc """
  Template for generating success criteria.
  """
  def success_criteria_template do
    """
    Generate specific, measurable success criteria for this task.

    TASK: {{task_name}}
    DESCRIPTION: {{task_description}}
    TYPE: {{task_type}}
    DELIVERABLES: {{expected_deliverables}}

    Create criteria that are:
    - SPECIFIC: Clearly defined, no ambiguity
    - MEASURABLE: Quantifiable or objectively verifiable
    - ACHIEVABLE: Realistic given constraints
    - RELEVANT: Directly related to task goals
    - TIME-BOUND: Clear completion indicators

    Categories to consider:
    1. Functional Requirements
    2. Performance Metrics
    3. Quality Standards
    4. User Acceptance
    5. Technical Specifications

    Format:
    {
      "criteria": [
        {
          "category": "functional|performance|quality|acceptance|technical",
          "description": "Specific criterion",
          "measurement": "How to measure/verify",
          "target": "Specific target value or state",
          "priority": "must_have|should_have|nice_to_have"
        }
      ],
      "acceptance_tests": [
        {
          "test_name": "Name of test",
          "steps": ["Step 1", "Step 2"],
          "expected_result": "What should happen"
        }
      ],
      "definition_of_done": "Overall criteria for task completion"
    }
    """
  end

  @doc """
  Template for dependency analysis.
  """
  def dependency_analysis_template do
    """
    Analyze dependencies between these tasks.

    TASKS: {{task_list}}
    PROJECT_CONTEXT: {{context}}

    Identify dependencies based on:
    1. Data flow (output of one task needed by another)
    2. Logical sequence (one must complete before another makes sense)
    3. Resource constraints (shared resources or tools)
    4. Technical requirements (setup needed before implementation)

    For each dependency specify:
    - Type: finish_to_start (default), start_to_start, finish_to_finish, start_to_finish
    - Strength: required, recommended, optional
    - Lag time: any delay needed between tasks

    Also identify:
    - Tasks that can run in parallel
    - Critical path through the tasks
    - Potential bottlenecks

    Format:
    {
      "dependencies": [
        {
          "from": "task_id",
          "to": "task_id",
          "type": "finish_to_start",
          "strength": "required",
          "lag": "0h",
          "reason": "Why this dependency exists"
        }
      ],
      "parallel_groups": [
        ["task_id_1", "task_id_2"]
      ],
      "critical_path": ["task_id_1", "task_id_3", "task_id_7"],
      "bottlenecks": [
        {
          "task": "task_id",
          "reason": "Why this is a bottleneck",
          "mitigation": "How to address it"
        }
      ]
    }
    """
  end

  @doc """
  Template for validation feedback.
  """
  def validation_feedback_template do
    """
    Validate this task decomposition and provide feedback.

    ORIGINAL_REQUEST: {{request}}
    DECOMPOSITION: {{tasks}}
    DEPENDENCIES: {{dependencies}}

    Check for:

    COMPLETENESS:
    - Does decomposition fully address the request?
    - Are all requirements covered?
    - Any missing edge cases?

    CORRECTNESS:
    - Are tasks properly scoped?
    - Dependencies make logical sense?
    - No circular dependencies?

    FEASIBILITY:
    - Realistic complexity estimates?
    - Achievable success criteria?
    - Resource requirements reasonable?

    CLARITY:
    - Task descriptions unambiguous?
    - Clear ownership possible?
    - Success criteria measurable?

    Provide:
    {
      "overall_assessment": "excellent|good|adequate|needs_work|poor",
      "completeness_score": 0.0-1.0,
      "correctness_score": 0.0-1.0,
      "feasibility_score": 0.0-1.0,
      "clarity_score": 0.0-1.0,
      "issues": [
        {
          "severity": "critical|major|minor",
          "type": "completeness|correctness|feasibility|clarity",
          "description": "Issue description",
          "affected_tasks": ["task_id"],
          "recommendation": "How to fix"
        }
      ],
      "strengths": ["What was done well"],
      "improvement_priority": ["Most important fixes first"]
    }
    """
  end

  @doc """
  Template for pattern matching.
  """
  def pattern_matching_template do
    """
    Match this request against known decomposition patterns.

    REQUEST: {{request}}
    CHARACTERISTICS: {{characteristics}}

    Known patterns:
    {{available_patterns}}

    For each potential match:
    1. Calculate similarity score
    2. Identify matching elements
    3. Note differences
    4. Assess applicability

    Return:
    {
      "matches": [
        {
          "pattern_name": "Pattern name",
          "similarity_score": 0.0-1.0,
          "matching_elements": ["Element 1", "Element 2"],
          "differences": ["Difference 1", "Difference 2"],
          "applicability": "high|medium|low",
          "adaptations_needed": ["Required change 1", "Required change 2"]
        }
      ],
      "best_match": "pattern_name",
      "confidence": 0.0-1.0,
      "recommendation": "use_pattern|adapt_pattern|create_new"
    }
    """
  end

  @doc """
  Get a template by name with variable substitution.
  """
  def get_template(name, variables \\ %{}) do
    template =
      case name do
        :strategy_selection -> strategy_selection_template()
        :linear_decomposition -> linear_decomposition_template()
        :hierarchical_decomposition -> hierarchical_decomposition_template()
        :tree_of_thought -> tree_of_thought_template()
        :complexity_estimation -> complexity_estimation_template()
        :success_criteria -> success_criteria_template()
        :dependency_analysis -> dependency_analysis_template()
        :validation_feedback -> validation_feedback_template()
        :pattern_matching -> pattern_matching_template()
        _ -> raise "Unknown template: #{name}"
      end

    # Substitute variables
    Enum.reduce(variables, template, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", to_string(value))
    end)
  end
end
