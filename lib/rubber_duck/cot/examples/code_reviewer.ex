defmodule RubberDuck.CoT.Examples.CodeReviewer do
  @moduledoc """
  Example Chain-of-Thought reasoning chain for code review.
  """
  
  use RubberDuck.CoT.Chain
  
  reasoning_chain do
    name :code_reviewer
    description "Systematic code review process"
    template :analytical
    max_steps 6
    
    step :understand_context do
      prompt """
      Let me understand the code context:
      - What is the purpose of this code?
      - What language/framework is being used?
      - What are the main components?
      
      Code/Query: {{query}}
      """
    end
    
    step :check_correctness do
      prompt """
      Now I'll check for correctness:
      
      Context: {{previous_result}}
      
      Examining:
      - Logic errors
      - Edge cases
      - Error handling
      - Data validation
      """
      depends_on :understand_context
      validates :has_code_analysis
    end
    
    step :review_style do
      prompt """
      Let me review code style and conventions:
      
      Based on the code analysis: {{previous_result}}
      
      Checking:
      - Naming conventions
      - Code organization
      - Documentation
      - Consistency
      """
      depends_on :check_correctness
    end
    
    step :assess_performance do
      prompt """
      Performance assessment:
      
      Given the implementation: {{previous_result}}
      
      Looking for:
      - Algorithmic complexity
      - Resource usage
      - Potential bottlenecks
      - Optimization opportunities
      """
      depends_on :check_correctness
      optional true
    end
    
    step :security_review do
      prompt """
      Security considerations:
      
      Based on the code: {{previous_result}}
      
      Checking for:
      - Input validation
      - Authentication/authorization
      - Data exposure risks
      - Common vulnerabilities
      """
      depends_on :check_correctness
      optional true
    end
    
    step :provide_feedback do
      prompt """
      Based on my complete review:
      
      {{previous_results}}
      
      Here's my comprehensive feedback with specific recommendations:
      """
      depends_on [:check_correctness, :review_style]
      validates :has_recommendations
      max_tokens 2000
    end
  end
  
  # Custom validators
  
  def has_code_analysis(result) do
    if String.length(result) > 100 and 
       String.contains?(String.downcase(result), ["error", "correct", "logic", "handle"]) do
      :ok
    else
      {:error, "Code analysis must examine logic, errors, or handling"}
    end
  end
  
  def has_recommendations(result) do
    if String.contains?(String.downcase(result), ["recommend", "suggest", "should", "could"]) do
      :ok
    else
      {:error, "Feedback must include specific recommendations"}
    end
  end
end