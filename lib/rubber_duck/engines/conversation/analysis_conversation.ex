defmodule RubberDuck.Engines.Conversation.AnalysisConversation do
  @moduledoc """
  Engine for handling code analysis conversations.
  
  This engine handles:
  - Code review discussions
  - Architecture analysis
  - Performance analysis
  - Security review
  - Best practices discussions
  
  It uses the AnalysisChain for thorough code examination.
  """
  
  @behaviour RubberDuck.Engine
  
  require Logger
  
  alias RubberDuck.CoT.Manager, as: ConversationManager
  alias RubberDuck.CoT.Chains.AnalysisChain
  
  @impl true
  def init(config) do
    state = %{
      config: config,
      max_tokens: config[:max_tokens] || 2000,
      temperature: config[:temperature] || 0.3,
      model: config[:model] || "codellama",
      timeout: config[:timeout] || 45_000,
      chain_module: config[:chain_module] || AnalysisChain
    }
    
    {:ok, state}
  end
  
  @impl true
  def execute(input, state) do
    with {:ok, validated} <- validate_input(input),
         {:ok, response} <- analyze_code_conversation(validated, state) do
      
      result = %{
        query: validated.query,
        response: response.final_answer,
        conversation_type: :analysis,
        analysis_points: extract_analysis_points(response),
        recommendations: extract_recommendations(response),
        processing_time: response.duration_ms,
        metadata: %{
          model: state.model,
          temperature: state.temperature,
          max_tokens: state.max_tokens,
          analysis_type: validated.analysis_type
        }
      }
      
      {:ok, result}
    end
  end
  
  @impl true
  def capabilities do
    [:code_review, :architecture_analysis, :performance_analysis, :security_review, :best_practices]
  end
  
  # Private functions
  
  defp validate_input(%{query: query} = input) when is_binary(query) do
    validated = %{
      query: String.trim(query),
      context: Map.get(input, :context, %{}),
      options: Map.get(input, :options, %{}),
      llm_config: Map.get(input, :llm_config, %{}),
      code: Map.get(input, :code),
      analysis_type: detect_analysis_type(query)
    }
    
    {:ok, validated}
  end
  
  defp validate_input(_), do: {:error, :invalid_input}
  
  defp analyze_code_conversation(validated, state) do
    # Build CoT context with code and analysis focus
    cot_context = build_cot_context(validated, state)
    
    Logger.info("Processing analysis conversation: #{String.slice(validated.query, 0, 50)}...")
    
    # Execute the analysis chain
    case ConversationManager.execute_chain(state.chain_module, validated.query, cot_context) do
      {:ok, result} ->
        {:ok, result}
        
      {:error, reason} ->
        Logger.error("Analysis conversation engine error: #{inspect(reason)}")
        {:error, {:cot_error, reason}}
    end
  end
  
  defp build_cot_context(validated, state) do
    %{
      code: validated.code || extract_code_from_context(validated.context),
      context: Map.merge(validated.context, %{
        analysis_type: validated.analysis_type,
        conversation_type: :analysis,
        file_path: validated.context[:file_path],
        language: validated.context[:language] || "elixir"
      }),
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
      session_id: validated.context[:session_id] || generate_session_id()
    }
  end
  
  defp detect_analysis_type(query) do
    query_lower = String.downcase(query)
    
    cond do
      String.contains?(query_lower, ["security", "vulnerability", "exploit"]) ->
        :security
        
      String.contains?(query_lower, ["performance", "optimize", "speed", "efficiency"]) ->
        :performance
        
      String.contains?(query_lower, ["architecture", "design", "structure"]) ->
        :architecture
        
      String.contains?(query_lower, ["review", "quality", "best practice"]) ->
        :code_review
        
      String.contains?(query_lower, ["complexity", "maintainability", "readability"]) ->
        :complexity
        
      true ->
        :general_analysis
    end
  end
  
  defp extract_code_from_context(context) do
    context[:code] || context[:current_code] || ""
  end
  
  defp extract_analysis_points(response) do
    response.reasoning_steps
    |> Enum.filter(fn step ->
      step.name in [:identify_patterns, :analyze_code, :evaluate_quality]
    end)
    |> Enum.flat_map(fn step ->
      parse_analysis_points(step.result)
    end)
  end
  
  defp extract_recommendations(response) do
    response.reasoning_steps
    |> Enum.find(fn step ->
      step.name == :suggest_improvements
    end)
    |> case do
      nil -> []
      step -> parse_recommendations(step.result)
    end
  end
  
  defp parse_analysis_points(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, ["•", "-", "*", "Issue:", "Finding:"]))
    |> Enum.map(&String.trim/1)
  end
  defp parse_analysis_points(_), do: []
  
  defp parse_recommendations(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, ["Recommend", "Suggest", "Consider", "Should"]))
    |> Enum.map(&String.trim/1)
  end
  defp parse_recommendations(_), do: []
  
  defp generate_session_id do
    "analysis_conv_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
end