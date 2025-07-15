defmodule RubberDuck.CoT.Chains.FastResponseChain do
  @moduledoc """
  Optimized Chain-of-Thought reasoning chain for fast responses.
  
  This chain is designed for questions that need some reasoning but
  not the full 7-8 step process. It focuses on:
  - Quick context understanding
  - Direct response generation
  - Minimal validation
  
  Ideal for moderately complex questions that benefit from structured
  thinking but don't require extensive analysis.
  """
  
  def config do
    %{
      name: :fast_response,
      description: "Fast reasoning chain for moderately complex questions",
      max_steps: 3,
      timeout: 30_000,  # 30 seconds vs 2 minutes
      template: :streamlined,
      cache_ttl: 900  # 15 minutes
    }
  end
  
  def steps do
    [
      %{
        name: :quick_analysis,
        prompt: """
        Let me quickly analyze this question:
        
        Question: {{query}}
        Context: {{context}}
        
        I need to understand:
        1. What exactly is being asked
        2. What type of response is needed
        3. Key information to include
        
        Quick analysis:
        """,
        validates: [:has_analysis],
        timeout: 8_000
      },
      %{
        name: :generate_response,
        prompt: """
        Based on my analysis, I'll provide a direct response:
        
        Analysis: {{previous_result}}
        Question: {{query}}
        
        I'll provide:
        1. A clear, direct answer
        2. Essential information only
        3. Practical guidance if needed
        
        Response:
        """,
        depends_on: :quick_analysis,
        validates: [:has_response],
        timeout: 15_000
      },
      %{
        name: :finalize_answer,
        prompt: """
        Let me finalize and format my response:
        
        Draft response: {{previous_result}}
        
        Final answer (clear, concise, and helpful):
        """,
        depends_on: :generate_response,
        validates: [:is_complete],
        timeout: 7_000
      }
    ]
  end
  
  # Validation functions - more lenient than full ConversationChain
  
  def has_analysis(%{result: result}) do
    result != nil && String.length(result) > 20
  end
  
  def has_response(%{result: result}) do
    result != nil && String.length(result) > 30
  end
  
  def is_complete(%{result: result}) do
    result != nil && String.length(result) > 10
  end
end