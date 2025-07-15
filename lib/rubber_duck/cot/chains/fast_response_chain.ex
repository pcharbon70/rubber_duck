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
      timeout: 60_000,  # 60 seconds to accommodate longer step timeouts
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
        timeout: 15_000
      },
      %{
        name: :generate_response,
        prompt: """
        Question: {{query}}
        
        Based on my analysis: {{previous_result}}
        
        Provide the direct answer to the question. Be factual and concise:
        """,
        depends_on: :quick_analysis,
        validates: [:has_response],
        timeout: 20_000
      },
      %{
        name: :finalize_answer,
        prompt: """
        Based on the question "{{query}}" and my analysis, here is the direct answer:
        
        {{previous_result}}
        
        Now, provide ONLY the final answer without any reasoning or explanation. Be direct and concise:
        """,
        depends_on: :generate_response,
        validates: [:is_complete],
        timeout: 15_000
      }
    ]
  end
  
  # Validation functions - more lenient than full ConversationChain
  
  def has_analysis(%{result: result}) do
    case result do
      nil -> false
      "" -> false
      str when is_binary(str) -> true
      _ -> false
    end
  end
  
  def has_response(%{result: result}) do
    case result do
      nil -> false
      "" -> false
      str when is_binary(str) -> true
      _ -> false
    end
  end
  
  def is_complete(%{result: result}) do
    case result do
      nil -> false
      "" -> false
      str when is_binary(str) -> true
      _ -> false
    end
  end
end