defmodule RubberDuck.CoT.Examples.ProblemSolver do
  @moduledoc """
  Example Chain-of-Thought reasoning chain for general problem solving.
  """
  
  use RubberDuck.CoT.Chain
  
  reasoning_chain do
    name :problem_solver
    description "Systematic problem-solving approach"
    template :analytical
    
    step :understand do
      prompt """
      First, let me understand the problem:
      - What exactly is being asked?
      - What are the constraints?
      - What is the desired outcome?
      
      Query: {{query}}
      """
      validates :has_problem_statement
    end
    
    step :analyze do
      prompt """
      Now I'll analyze the key components:
      
      Based on my understanding: {{previous_result}}
      
      Let me identify:
      - Root causes
      - Key dependencies
      - Available resources
      - Potential obstacles
      """
      depends_on :understand
      validates :has_analysis
    end
    
    step :brainstorm do
      prompt """
      Let me brainstorm potential solutions:
      
      Given the analysis: {{previous_result}}
      
      Possible approaches:
      """
      depends_on :analyze
      temperature 0.8
    end
    
    step :evaluate do
      prompt """
      Now I'll evaluate the solutions:
      
      Solutions considered: {{previous_result}}
      
      For each solution, I'll consider:
      - Feasibility
      - Resource requirements
      - Potential impact
      - Risks and mitigation
      """
      depends_on :brainstorm
    end
    
    step :recommend do
      prompt """
      Based on my evaluation: {{previous_result}}
      
      Here's my recommendation with implementation steps:
      """
      depends_on :evaluate
      validates :has_solution
      max_tokens 1500
    end
  end
  
  # Custom validators
  
  def has_analysis(result) do
    required_elements = ["cause", "depend", "resource", "obstacle"]
    
    if Enum.any?(required_elements, &String.contains?(String.downcase(result), &1)) do
      :ok
    else
      {:error, "Analysis must identify causes, dependencies, resources, or obstacles"}
    end
  end
end