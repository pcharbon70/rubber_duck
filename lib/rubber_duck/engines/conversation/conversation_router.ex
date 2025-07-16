defmodule RubberDuck.Engines.Conversation.ConversationRouter do
  @moduledoc """
  Router engine that classifies incoming queries and routes them to the
  appropriate conversation engine based on their complexity and type.
  
  This engine:
  - Uses QuestionClassifier to determine query type
  - Routes to simple or complex conversation engines
  - Maintains conversation context across engines
  - Provides unified interface for all conversation types
  """
  
  @behaviour RubberDuck.Engine
  
  require Logger
  
  alias RubberDuck.CoT.QuestionClassifier
  alias RubberDuck.Engine.Manager, as: EngineManager
  
  @simple_types [:factual, :basic_code, :straightforward]
  @complex_types [:complex_problem, :multi_step]
  
  @impl true
  def init(config) do
    state = %{
      config: config,
      simple_engine: config[:simple_engine] || :simple_conversation,
      complex_engine: config[:complex_engine] || :complex_conversation,
      analysis_engine: config[:analysis_engine] || :analysis_conversation,
      generation_engine: config[:generation_engine] || :generation_conversation,
      problem_solver_engine: config[:problem_solver_engine] || :problem_solver,
      multi_step_engine: config[:multi_step_engine] || :multi_step_conversation,
      timeout: config[:timeout] || 60_000
    }
    
    {:ok, state}
  end
  
  @impl true
  def execute(input, state) do
    with {:ok, validated} <- validate_input(input),
         {:ok, classification} <- classify_query(validated),
         {:ok, engine_name} <- select_engine(classification, validated, state),
         {:ok, result} <- route_to_engine(engine_name, validated, state) do
      
      # Add routing metadata to result
      enriched_result = Map.merge(result, %{
        routed_to: engine_name,
        classification: classification,
        router_metadata: %{
          question_type: classification.question_type,
          complexity: classification.complexity,
          explanation: classification.explanation
        }
      })
      
      {:ok, enriched_result}
    end
  end
  
  @impl true
  def capabilities do
    [:conversation_routing, :question_classification, :dynamic_routing]
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
  
  defp classify_query(validated) do
    # Use QuestionClassifier to analyze the query
    classification = QuestionClassifier.classify(validated.query, validated.context)
    question_type = QuestionClassifier.determine_question_type(validated.query, validated.context)
    explanation = QuestionClassifier.explain_classification(validated.query, validated.context)
    
    Logger.debug("Query classified as #{classification} (#{question_type}): #{explanation}")
    
    {:ok, %{
      complexity: classification,
      question_type: question_type,
      explanation: explanation
    }}
  end
  
  defp select_engine(classification, validated, state) do
    # Check for specific intent indicators in the query
    query_lower = String.downcase(validated.query)
    
    engine_name = cond do
      # Specific engine routing based on content
      contains_any?(query_lower, ["analyze", "review", "check", "inspect", "examine"]) ->
        state.analysis_engine
        
      contains_any?(query_lower, ["generate", "create", "write", "build", "implement"]) ->
        state.generation_engine
        
      contains_any?(query_lower, ["debug", "fix", "error", "issue", "problem", "troubleshoot"]) ->
        state.problem_solver_engine
        
      # Multi-step from context
      classification.question_type == :multi_step ->
        state.multi_step_engine
        
      # Simple vs complex routing
      classification.question_type in @simple_types ->
        state.simple_engine
        
      classification.question_type in @complex_types ->
        state.complex_engine
        
      # Default to complex for safety
      true ->
        state.complex_engine
    end
    
    Logger.info("Routing conversation to engine: #{engine_name}")
    {:ok, engine_name}
  end
  
  defp route_to_engine(engine_name, validated, state) do
    # Prepare input for the target engine
    engine_input = %{
      query: validated.query,
      context: validated.context,
      options: validated.options,
      llm_config: validated.llm_config
    }
    
    # Execute on the selected engine
    case EngineManager.execute(engine_name, engine_input, state.timeout) do
      {:ok, result} ->
        {:ok, result}
        
      {:error, :engine_not_found} ->
        Logger.warning("Engine #{engine_name} not found, falling back to simple conversation")
        EngineManager.execute(state.simple_engine, engine_input, state.timeout)
        
      {:error, reason} ->
        Logger.error("Engine execution failed: #{inspect(reason)}")
        {:error, {:engine_error, engine_name, reason}}
    end
  end
  
  defp contains_any?(text, keywords) do
    Enum.any?(keywords, fn keyword ->
      String.contains?(text, keyword)
    end)
  end
end