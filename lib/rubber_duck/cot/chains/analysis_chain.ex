defmodule RubberDuck.CoT.Chains.AnalysisChain do
  @moduledoc """
  Chain-of-Thought reasoning chain for code analysis.
  
  This chain guides the reasoning process through systematic code analysis,
  pattern identification, issue detection, and improvement suggestions.
  """
  
  @behaviour RubberDuck.CoT.ChainBehaviour
  
  def config do
    %{
      name: :analysis,
      description: "Systematic code analysis with structured reasoning",
      max_steps: 10,
      timeout: 45_000,
      template: :analytical,
      cache_ttl: 1800  # 30 minutes
    }
  end
  
  def steps do
    [
      %{
        name: :understand_code,
        prompt: """
        First, let me understand the code structure and purpose:
        
        Code to analyze:
        {{code}}
        
        Context:
        {{context}}
        
        I'll examine:
        1. Overall structure and organization
        2. Main components and their responsibilities
        3. Key algorithms and data flows
        4. External dependencies and interfaces
        
        Understanding:
        """,
        validates: [:has_understanding],
        timeout: 10_000
      },
      %{
        name: :identify_patterns,
        prompt: """
        Now I'll identify patterns and architectural decisions:
        
        Based on my understanding: {{previous_result}}
        
        I'll look for:
        1. Design patterns used (or that should be used)
        2. Code style and conventions
        3. Recurring structures or abstractions
        4. Framework-specific patterns
        
        Patterns identified:
        """,
        depends_on: :understand_code,
        validates: [:found_patterns],
        timeout: 8_000
      },
      %{
        name: :analyze_issues,
        prompt: """
        Let me analyze potential issues and areas for improvement:
        
        Code understanding: {{understand_code_result}}
        Patterns found: {{previous_result}}
        
        I'll check for:
        1. Code smells and anti-patterns
        2. Performance bottlenecks
        3. Security vulnerabilities
        4. Maintainability concerns
        5. Missing error handling
        6. Test coverage gaps
        
        Issues found:
        """,
        depends_on: :identify_patterns,
        validates: [:issues_analyzed],
        timeout: 10_000
      },
      %{
        name: :suggest_improvements,
        prompt: """
        Based on my analysis, here are my improvement suggestions:
        
        Issues identified: {{previous_result}}
        
        I'll provide:
        1. Specific code improvements with examples
        2. Refactoring recommendations
        3. Best practices to adopt
        4. Testing strategies
        5. Documentation needs
        
        Recommendations:
        """,
        depends_on: :analyze_issues,
        validates: [:has_suggestions],
        timeout: 10_000
      },
      %{
        name: :prioritize_actions,
        prompt: """
        Let me prioritize the suggested improvements:
        
        All suggestions: {{previous_result}}
        
        I'll categorize by:
        1. Critical (security, bugs, data loss risks)
        2. High (performance, maintainability)
        3. Medium (code quality, conventions)
        4. Low (nice-to-have improvements)
        
        Prioritized action plan:
        """,
        depends_on: :suggest_improvements,
        validates: [:has_priorities],
        timeout: 7_000
      }
    ]
  end
  
  # Validation functions
  
  def has_understanding(%{result: result}) do
    result != nil && String.length(result) > 50
  end
  
  def found_patterns(%{result: result}) do
    result != nil && String.contains?(result, ["pattern", "structure", "design"])
  end
  
  def issues_analyzed(%{result: result}) do
    result != nil && String.length(result) > 30
  end
  
  def has_suggestions(%{result: result}) do
    result != nil && String.contains?(result, ["suggest", "recommend", "improve", "should"])
  end
  
  def has_priorities(%{result: result}) do
    result != nil && String.contains?(result, ["critical", "high", "medium", "low"])
  end
end