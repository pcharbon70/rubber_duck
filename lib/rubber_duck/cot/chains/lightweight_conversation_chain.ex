defmodule RubberDuck.CoT.Chains.LightweightConversationChain do
  @moduledoc """
  Lightweight Chain-of-Thought reasoning chain for conversational responses.
  
  This is a streamlined version of the full ConversationChain that:
  - Skips detailed knowledge gathering
  - Focuses on direct response generation
  - Maintains conversational flow
  - Uses shorter timeouts
  
  Ideal for ongoing conversations where full context analysis isn't needed.
  """
  
  def config do
    %{
      name: :lightweight_conversation,
      description: "Streamlined conversational reasoning",
      max_steps: 4,
      timeout: 75_000,  # 75 seconds to accommodate longer step timeouts
      template: :conversational,
      cache_ttl: 600  # 10 minutes
    }
  end
  
  def steps do
    [
      %{
        name: :understand_request,
        prompt: """
        Let me understand what you're asking:
        
        Current message: {{query}}
        Previous context: {{conversation_history}}
        
        I need to identify:
        1. The main question or request
        2. How it relates to our conversation
        3. What kind of response you need
        
        Understanding:
        """,
        validates: [:has_understanding],
        timeout: 15_000
      },
      %{
        name: :plan_response,
        prompt: """
        Based on my understanding, I'll plan my response:
        
        Understanding: {{previous_result}}
        Message: {{query}}
        
        My response should:
        1. Address your specific question
        2. Build on our conversation context
        3. Provide helpful, actionable information
        
        Response plan:
        """,
        depends_on: :understand_request,
        validates: [:has_plan],
        timeout: 15_000
      },
      %{
        name: :generate_response,
        prompt: """
        Now I'll generate my response:
        
        Plan: {{previous_result}}
        Context: {{understand_request_result}}
        
        I'll provide a clear, helpful response that:
        1. Directly answers your question
        2. Maintains conversational flow
        3. Offers practical guidance
        
        Response:
        """,
        depends_on: :plan_response,
        validates: [:has_response],
        timeout: 25_000
      },
      %{
        name: :polish_response,
        prompt: """
        Let me polish and finalize my response:
        
        Draft: {{previous_result}}
        
        Final response (natural, helpful, and clear):
        """,
        depends_on: :generate_response,
        validates: [:is_polished],
        timeout: 15_000
      }
    ]
  end
  
  # Validation functions - balanced between quality and speed
  
  def has_understanding(%{result: result}) do
    result != nil && String.length(result) > 15
  end
  
  def has_plan(%{result: result}) do
    result != nil && String.length(result) > 20
  end
  
  def has_response(%{result: result}) do
    result != nil && String.length(result) > 25
  end
  
  def is_polished(%{result: result}) do
    result != nil && String.length(result) > 15
  end
end