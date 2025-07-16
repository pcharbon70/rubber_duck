defmodule RubberDuck.Engines.Conversation.ComplexConversation do
  @moduledoc """
  Engine for handling complex conversational queries that require
  Chain-of-Thought reasoning.
  
  This engine handles:
  - Complex problem solving
  - Multi-step reasoning
  - Architecture and design questions
  - Debugging and troubleshooting
  - Trade-off analysis
  
  It uses the CoT system to provide thorough, well-reasoned responses.
  """
  
  @behaviour RubberDuck.Engine
  
  require Logger
  
  alias RubberDuck.CoT.Manager, as: ConversationManager
  alias RubberDuck.CoT.Chains.ConversationChain
  
  @impl true
  def init(config) do
    state = %{
      config: config,
      max_tokens: config[:max_tokens] || 2000,
      temperature: config[:temperature] || 0.7,
      model: config[:model] || "codellama",
      timeout: config[:timeout] || 60_000,
      chain_module: config[:chain_module] || ConversationChain
    }
    
    {:ok, state}
  end
  
  @impl true
  def execute(input, state) do
    with {:ok, validated} <- validate_input(input),
         {:ok, response} <- process_complex_query(validated, state) do
      
      result = %{
        query: validated.query,
        response: response.final_answer,
        conversation_type: :complex,
        reasoning_steps: response.reasoning_steps,
        processing_time: response.duration_ms,
        metadata: %{
          model: state.model,
          temperature: state.temperature,
          max_tokens: state.max_tokens,
          total_steps: response.total_steps
        }
      }
      
      {:ok, result}
    end
  end
  
  @impl true
  def capabilities do
    [:complex_reasoning, :multi_step_analysis, :problem_solving, :architecture_design, :debugging]
  end
  
  # Private functions
  
  defp validate_input(%{query: query} = input) when is_binary(query) do
    validated = %{
      query: String.trim(query),
      context: Map.get(input, :context, %{}),
      options: Map.get(input, :options, %{}),
      llm_config: Map.get(input, :llm_config, %{})
    }
    
    {:ok, validated}
  end
  
  defp validate_input(_), do: {:error, :invalid_input}
  
  defp process_complex_query(validated, state) do
    # Build CoT context
    cot_context = build_cot_context(validated, state)
    
    Logger.info("Processing complex conversation query with CoT: #{String.slice(validated.query, 0, 50)}...")
    
    # Execute the CoT chain
    case ConversationManager.execute_chain(state.chain_module, validated.query, cot_context) do
      {:ok, result} ->
        {:ok, result}
        
      {:error, reason} ->
        Logger.error("Complex conversation engine error: #{inspect(reason)}")
        {:error, {:cot_error, reason}}
    end
  end
  
  defp build_cot_context(validated, state) do
    %{
      context: validated.context,
      llm_config: Map.merge(
        %{
          model: state.model,
          temperature: state.temperature,
          max_tokens: state.max_tokens,
          timeout: state.timeout
        },
        validated.llm_config
      ),
      user_id: validated.context[:user_id],
      session_id: validated.context[:session_id] || generate_session_id(),
      messages: validated.context[:messages] || []
    }
  end
  
  defp generate_session_id do
    "complex_conv_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
end