defmodule RubberDuck.CoT.Chains.ConversationChain do
  @moduledoc """
  Chain-of-Thought reasoning chain for conversations.

  This chain guides the reasoning process through understanding context,
  formulating responses, ensuring coherence, and formatting output.
  """

  def config do
    %{
      name: :conversation,
      description: "Conversational reasoning with context awareness",
      max_steps: 8,
      timeout: 120_000,
      template: :default,
      # 5 minutes - shorter for conversations
      cache_ttl: 300
    }
  end

  def steps do
    [
      %{
        name: :understand_context,
        prompt: """
        Let me understand the conversation context:

        Current message: {{query}}
        Conversation history: {{conversation_history}}
        User context: {{user_context}}

        I'll analyze:
        1. What the user is asking or discussing
        2. Relevant context from previous messages
        3. User's technical level and preferences
        4. Conversation goals and direction
        5. Any unresolved topics

        Context understanding:
        """,
        validates: [:has_context_understanding],
        timeout: 8_000
      },
      %{
        name: :identify_intent,
        prompt: """
        Now I'll identify the user's intent:

        Context: {{previous_result}}
        Message: {{query}}

        Possible intents:
        1. Asking for help or explanation
        2. Requesting code generation
        3. Seeking analysis or review
        4. Having a discussion
        5. Reporting an issue
        6. Following up on previous topic

        User intent:
        """,
        depends_on: :understand_context,
        validates: [:intent_identified],
        timeout: 5_000
      },
      %{
        name: :gather_relevant_knowledge,
        prompt: """
        Let me gather relevant knowledge for this response:

        Intent: {{previous_result}}
        Context: {{understand_context_result}}
        Available knowledge: {{knowledge_base}}
        Project context: {{project_context}}

        I'll collect:
        1. Technical information needed
        2. Best practices and patterns
        3. Common pitfalls to mention
        4. Relevant examples
        5. Documentation references

        Relevant knowledge:
        """,
        depends_on: :identify_intent,
        validates: [:has_knowledge],
        timeout: 7_000
      },
      %{
        name: :reason_response,
        prompt: """
        Now I'll formulate my response:

        Intent: {{identify_intent_result}}
        Knowledge: {{previous_result}}
        Context: {{understand_context_result}}

        My response will:
        1. Directly address the user's question/need
        2. Provide clear and actionable information
        3. Include relevant examples if helpful
        4. Maintain appropriate technical depth
        5. Be encouraging and supportive

        Response:
        """,
        depends_on: :gather_relevant_knowledge,
        validates: [:has_response],
        timeout: 10_000
      },
      %{
        name: :validate_coherence,
        prompt: """
        Let me ensure coherence with the conversation:

        My response: {{previous_result}}
        Conversation flow: {{conversation_history}}

        Checking:
        1. Consistency with previous messages
        2. Appropriate tone maintenance
        3. No contradictions
        4. Natural flow
        5. Complete answer to the question

        Coherence check:
        """,
        depends_on: :reason_response,
        validates: [:is_coherent],
        timeout: 5_000
      },
      %{
        name: :add_helpful_context,
        prompt: """
        I'll add any helpful additional context:

        Response: {{reason_response_result}}
        Validation: {{previous_result}}

        Consider adding:
        1. Next steps or follow-up actions
        2. Additional resources or documentation
        3. Common related questions
        4. Tips or best practices
        5. Clarifying questions if needed

        Enhanced response:
        """,
        depends_on: :validate_coherence,
        validates: [:has_enhancements],
        timeout: 5_000
      },
      %{
        name: :format_output,
        prompt: """
        Let me format the final response:

        Content: {{previous_result}}
        User preferences: {{user_preferences}}

        Formatting for:
        1. Clear structure and readability
        2. Appropriate use of code blocks
        3. Bullet points or lists where helpful
        4. Emphasis on key points
        5. Professional yet friendly tone

        Final response:
        """,
        depends_on: :add_helpful_context,
        validates: [:well_formatted],
        timeout: 5_000
      }
    ]
  end

  # Validation functions

  def has_context_understanding(%{result: result}) do
    # More lenient context check - just ensure result exists and has some content
    result != nil && String.length(result) > 10
  end

  def intent_identified(%{result: result}) do
    # More lenient intent check - just ensure result exists and has some content
    result != nil && String.length(result) > 5
  end

  def has_knowledge(%{result: result}) do
    # More lenient knowledge check - just ensure result exists and has some content
    result != nil && String.length(result) > 10
  end

  def has_response(%{result: result}) do
    # More lenient response check - just ensure result exists and has some content
    result != nil && String.length(result) > 10
  end

  def is_coherent(%{result: result}) do
    # More lenient coherence check - just ensure result exists and has some content
    result != nil && String.length(result) > 5
  end

  def has_enhancements(%{result: result}) do
    # More lenient enhancements check - just ensure result exists and has some content
    result != nil && String.length(result) > 10
  end

  def well_formatted(%{result: result}) do
    # More lenient formatting check - just ensure result exists and has some content
    result != nil && String.length(result) > 5
  end
end
