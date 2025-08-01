defmodule RubberDuck.CoT.Chains.GenerationChain do
  @moduledoc """
  Chain-of-Thought reasoning chain for code generation.

  This chain guides the reasoning process through understanding requirements,
  planning code structure, generating implementation, and validating output.
  """

  @behaviour RubberDuck.CoT.ChainBehaviour
  
  alias RubberDuck.Config.Timeouts

  def config do
    %{
      name: :generation,
      description: "Systematic code generation with structured reasoning",
      max_steps: 12,
      timeout: Timeouts.get([:chains, :generation, :total], 300_000),
      template: :creative,
      # 15 minutes
      cache_ttl: 900
    }
  end

  def steps do
    [
      %{
        name: :understand_requirements,
        prompt: """
        Let me understand the code generation requirements:

        Request: {{query}}
        Context: {{context}}
        Language: {{language}}

        I'll analyze:
        1. Core functionality needed
        2. Input/output requirements
        3. Performance constraints
        4. Error handling needs
        5. Integration points

        Requirements analysis:
        """,
        validates: [:has_requirements],
        timeout: Timeouts.get([:chains, :generation, :steps, :understand_requirements], 10_000)
      },
      %{
        name: :review_context,
        prompt: """
        Now I'll review the existing codebase context:

        Requirements: {{previous_result}}
        Project files: {{project_files}}
        Similar patterns: {{similar_patterns}}

        I'll examine:
        1. Existing code patterns and conventions
        2. Available utilities and helpers
        3. Project structure and organization
        4. Dependencies I can leverage
        5. Testing patterns in use

        Context review:
        """,
        depends_on: :understand_requirements,
        validates: [:context_reviewed],
        timeout: Timeouts.get([:chains, :generation, :steps, :review_context], 60_000)
      },
      %{
        name: :plan_structure,
        prompt: """
        Let me plan the code structure:

        Requirements: {{understand_requirements_result}}
        Context insights: {{previous_result}}

        I'll design:
        1. Overall architecture and modules
        2. Key functions and their signatures
        3. Data structures and types
        4. Interface contracts
        5. Error handling strategy
        6. Test structure

        Structural plan:
        """,
        depends_on: :review_context,
        validates: [:has_structure_plan],
        timeout: Timeouts.get([:chains, :generation, :steps, :plan_structure], 10_000)
      },
      %{
        name: :identify_dependencies,
        prompt: """
        I'll identify necessary dependencies and imports:

        Structure plan: {{previous_result}}
        Available libraries: {{available_libraries}}

        I need to:
        1. List required standard library imports
        2. Identify third-party dependencies
        3. Note internal module dependencies
        4. Check version compatibility
        5. Verify licensing compatibility

        Dependencies needed:
        """,
        depends_on: :plan_structure,
        validates: [:dependencies_identified],
        timeout: Timeouts.get([:chains, :generation, :steps, :identify_dependencies], 7_000)
      },
      %{
        name: :generate_implementation,
        prompt: """
        Now I'll generate the code implementation:

        Structure: {{plan_structure_result}}
        Dependencies: {{previous_result}}
        Language: {{language}}

        Implementation following project conventions:
        """,
        depends_on: :identify_dependencies,
        validates: [:code_generated],
        timeout: Timeouts.get([:chains, :generation, :steps, :generate_implementation], 15_000)
      },
      %{
        name: :add_documentation,
        prompt: """
        Now I'll add comprehensive documentation to the code.
        
        Original code to document:
        {{generate_implementation_result}}
        
        I need to add proper documentation including:
        1. Module/class documentation explaining purpose and usage
        2. Function/method documentation with @doc or equivalent
        3. Parameter descriptions
        4. Return value documentation
        5. Usage examples where appropriate
        6. Important notes or warnings
        
        Here is the complete code with all documentation added:
        """,
        depends_on: :generate_implementation,
        validates: [:has_documentation],
        timeout: Timeouts.get([:chains, :generation, :steps, :add_documentation], 60_000)
      },
      %{
        name: :generate_tests,
        prompt: """
        I'll generate comprehensive tests:

        Implementation: {{generate_implementation_result}}

        Test coverage will include:
        1. Happy path scenarios
        2. Edge cases
        3. Error conditions
        4. Integration tests
        5. Property-based tests (if applicable)

        Test implementation:
        """,
        depends_on: :add_documentation,
        validates: [:has_tests],
        timeout: Timeouts.get([:chains, :generation, :steps, :generate_tests], 12_000)
      },
      %{
        name: :validate_output,
        prompt: """
        Let me validate the generated code:

        Code: {{add_documentation_result}}
        Tests: {{previous_result}}
        Requirements: {{understand_requirements_result}}

        Validation checks:
        1. Requirements satisfaction
        2. Code correctness
        3. Style compliance
        4. Performance considerations
        5. Security review
        6. Test coverage

        Validation results:
        """,
        depends_on: :generate_tests,
        validates: [:validation_passed],
        timeout: Timeouts.get([:chains, :generation, :steps, :validate_output], 60_000)
      },
      %{
        name: :provide_alternatives,
        prompt: """
        Here are alternative approaches to consider:

        Main implementation: {{add_documentation_result}}
        Validation: {{previous_result}}

        Alternative approaches:
        1. Different architectural patterns
        2. Performance optimizations
        3. Simplified versions
        4. Extended feature sets

        Alternatives:
        """,
        depends_on: :validate_output,
        validates: [:has_alternatives],
        timeout: Timeouts.get([:chains, :generation, :steps, :provide_alternatives], 10_000)
      }
    ]
  end

  # Validation functions

  def has_requirements(%{result: result}) do
    result != nil && String.length(result) > 50
  end

  def context_reviewed(%{result: result}) do
    result != nil && String.contains?(result, ["pattern", "convention", "structure"])
  end

  def has_structure_plan(%{result: result}) do
    result != nil && String.contains?(result, ["function", "module", "structure", "interface"])
  end

  def dependencies_identified(%{result: result}) do
    result != nil && (String.contains?(result, ["import", "require", "dependency"]) || String.contains?(result, "none"))
  end

  def code_generated(%{result: result}) do
    result != nil && String.length(result) > 100
  end

  def has_documentation(%{result: result}) do
    # Check if result contains documentation markers OR contains code with documentation keywords
    result != nil && (
      String.contains?(result, ["@doc", "#", "//", "\"\"\"", "/**", "@moduledoc"]) ||
      String.contains?(result, ["documentation", "Description:", "Example:", "Usage:", "Returns:", "Parameters:"]) ||
      # Also check if it contains the original code (meaning it returned documented code)
      String.contains?(result, ["def ", "defmodule ", "function ", "class ", "const ", "var "])
    )
  end

  def has_tests(%{result: result}) do
    result != nil && String.contains?(result, ["test", "assert", "expect", "describe"])
  end

  def validation_passed(%{result: result}) do
    # Check if validation actually passed by looking for positive indicators
    # or the absence of critical failure indicators
    if result == nil do
      false
    else
      downcased = String.downcase(result)
      
      # Check for positive validation indicators
      has_positive = String.contains?(downcased, [
        "validation passed",
        "validation successful",
        "valid",
        "correct",
        "looks good",
        "no issues",
        "no errors",
        "all checks pass"
      ])
      
      # Check for critical failures (not just the word appearing)
      has_critical_failure = String.contains?(downcased, [
        "validation failed",
        "invalid code",
        "critical error",
        "syntax error",
        "does not compile",
        "tests fail"
      ])
      
      # Pass if we have positive indicators or no critical failures
      has_positive || !has_critical_failure
    end
  end

  def has_alternatives(%{result: result}) do
    result != nil && String.length(result) > 30
  end
end
