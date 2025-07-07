defmodule RubberDuck.CoT.Templates do
  @moduledoc """
  Pre-built reasoning templates for different types of problems.

  Provides structured reasoning patterns that guide the LLM through
  systematic problem-solving approaches.
  """

  @templates %{
    default: """
    I'll work through this step-by-step to ensure a thorough and accurate response.

    Let me begin by understanding what's being asked and then proceed systematically.
    """,
    analytical: """
    I'll analyze this systematically using the following approach:
    1. Break down the problem into its core components
    2. Examine each component individually
    3. Identify relationships and dependencies
    4. Synthesize findings into a cohesive solution

    Let me start:
    """,
    creative: """
    I'll approach this creatively by:
    1. Exploring multiple perspectives
    2. Considering unconventional solutions
    3. Combining ideas in novel ways
    4. Evaluating feasibility and impact

    Let me begin with some creative exploration:
    """,
    troubleshooting: """
    I'll troubleshoot this issue systematically:
    1. Identify symptoms and error indicators
    2. Form hypotheses about root causes
    3. Test each hypothesis methodically
    4. Verify the solution works correctly

    Starting with symptom analysis:
    """,
    custom: """
    Following the custom reasoning approach for this specific problem:
    """
  }

  @doc """
  Gets a reasoning template by type.
  """
  def get_template(type) when is_atom(type) do
    Map.get(@templates, type, @templates.default)
  end

  @doc """
  Gets all available template types.
  """
  def available_templates() do
    Map.keys(@templates)
  end

  @doc """
  Creates a custom template for a specific reasoning pattern.
  """
  def create_custom_template(pattern_name, steps) when is_list(steps) do
    """
    Custom Reasoning Pattern: #{pattern_name}

    I'll follow these specific steps:
    #{steps |> Enum.with_index(1) |> Enum.map(fn {step, idx} -> "#{idx}. #{step}" end) |> Enum.join("\n")}

    Let me begin:
    """
  end

  @doc """
  Gets a template for code-related reasoning.
  """
  def code_reasoning_template(language \\ nil) do
    lang_specific = if language, do: " #{language}", else: ""

    """
    I'll analyze this#{lang_specific} code systematically:

    1. Understanding the requirements
    2. Examining the current implementation
    3. Identifying issues or improvements
    4. Proposing solutions with examples
    5. Considering edge cases and testing

    Let me start by understanding what we're working with:
    """
  end

  @doc """
  Gets a template for mathematical reasoning.
  """
  def math_reasoning_template() do
    """
    I'll solve this mathematical problem step-by-step:

    1. Identify given information
    2. Determine what needs to be found
    3. Select appropriate methods/formulas
    4. Work through calculations systematically
    5. Verify the answer makes sense

    Starting with the given information:
    """
  end

  @doc """
  Gets a template for logical reasoning.
  """
  def logical_reasoning_template() do
    """
    I'll apply logical reasoning to this problem:

    1. Identify premises and assumptions
    2. Examine logical relationships
    3. Apply deductive/inductive reasoning
    4. Check for logical fallacies
    5. Draw valid conclusions

    Let me begin with the premises:
    """
  end

  @doc """
  Builds a template for multi-step planning.
  """
  def planning_template(goal) do
    """
    I'll create a comprehensive plan to achieve: #{goal}

    My planning approach:
    1. Define success criteria
    2. Identify required resources
    3. Break down into actionable steps
    4. Consider dependencies and sequencing
    5. Identify potential obstacles
    6. Create contingency plans

    Let me start with defining what success looks like:
    """
  end

  @doc """
  Combines multiple templates for complex reasoning.
  """
  def combine_templates(template_types) when is_list(template_types) do
    templates = Enum.map(template_types, &get_template/1)

    """
    I'll use a combined reasoning approach for this complex problem:

    #{Enum.join(templates, "\n\nAdditionally:\n")}
    """
  end

  @doc """
  Gets a template with specific constraints.
  """
  def constrained_template(constraints) when is_list(constraints) do
    constraint_text =
      constraints
      |> Enum.map(fn c -> "- #{c}" end)
      |> Enum.join("\n")

    """
    I'll reason through this problem while adhering to these constraints:
    #{constraint_text}

    Let me work through this systematically within these boundaries:
    """
  end
end
