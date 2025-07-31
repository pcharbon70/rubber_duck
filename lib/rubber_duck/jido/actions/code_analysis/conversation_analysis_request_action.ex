defmodule RubberDuck.Jido.Actions.CodeAnalysis.ConversationAnalysisRequestAction do
  @moduledoc """
  Action for handling conversational code analysis requests.
  
  This action processes conversational analysis requests by:
  - Extracting code from conversation context
  - Building appropriate CoT context
  - Executing analysis chain with LLM
  - Extracting analysis points and recommendations
  - Emitting the analysis result
  """
  
  use Jido.Action,
    name: "conversation_analysis_request",
    description: "Handles conversational code analysis with CoT reasoning",
    schema: [
      query: [
        type: :string,
        required: true,
        doc: "The analysis query from the user"
      ],
      code: [
        type: :string,
        default: nil,
        doc: "Code to analyze (optional if in context)"
      ],
      context: [
        type: :map,
        default: %{},
        doc: "Conversation context including code and metadata"
      ],
      request_id: [
        type: :string,
        required: true,
        doc: "Unique identifier for the request"
      ],
      llm_params: [
        type: :map,
        required: true,
        doc: "LLM parameters including provider, model, and user_id"
      ]
    ]

  alias RubberDuck.CoT.Manager, as: ConversationManager
  alias RubberDuck.CoT.Chains.AnalysisChain
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  require Logger

  @impl true
  def run(params, context) do
    agent = context.agent
    %{query: query, code: code, context: analysis_context, request_id: request_id, llm_params: llm_params} = params
    
    Logger.info("Processing conversational analysis request")
    
    # Create analysis request and add to queue
    analysis_request = %{
      type: :conversation,
      query: query,
      code: code,
      context: analysis_context,
      llm_params: llm_params,
      request_id: request_id,
      started_at: System.monotonic_time(:millisecond)
    }
    
    # Update state and start processing
    with {:ok, _, %{agent: queued_agent}} <- add_to_queue(agent, analysis_request),
         {:ok, _} <- emit_analysis_progress(queued_agent, params, "started") do
      
      # Start conversational analysis asynchronously
      Task.start(fn ->
        analyze_conversation_async(analysis_request)
      end)
      
      {:ok, %{processing_started: true}, %{agent: queued_agent}}
    end
  end

  # Private functions
  
  defp analyze_conversation_async(request) do
    try do
      # Build CoT context
      cot_context = %{
        provider: request.llm_params["provider"],
        model: request.llm_params["model"],
        user_id: request.llm_params["user_id"],
        code: request.code || extract_code_from_context(request.context),
        context: Map.merge(request.context || %{}, %{
          analysis_type: detect_analysis_type(request.query),
          conversation_type: :analysis
        }),
        llm_config: %{
          temperature: 0.3,
          max_tokens: 2000
        }
      }
      
      # Execute AnalysisChain
      case ConversationManager.execute_chain(AnalysisChain, request.query, cot_context) do
        {:ok, cot_session} ->
          # Extract and emit result
          result = extract_conversation_result(cot_session, request)
          emit_async_result(request, result, nil)
          
        {:error, reason} ->
          Logger.error("Conversation analysis failed: #{inspect(reason)}")
          emit_async_result(request, nil, "Analysis failed: #{inspect(reason)}")
      end
      
    rescue
      error ->
        Logger.error("Conversation analysis error: #{inspect(error)}")
        emit_async_result(request, nil, Exception.message(error))
    end
  end
  
  defp extract_conversation_result(cot_session, request) do
    # Extract key information from CoT session
    analysis_points = extract_analysis_points(cot_session.reasoning_steps)
    recommendations = extract_recommendations(cot_session.reasoning_steps)
    
    %{
      query: request.query,
      response: cot_session.final_answer,
      conversation_type: :analysis,
      analysis_points: analysis_points,
      recommendations: recommendations,
      processing_time: cot_session.duration_ms,
      metadata: %{
        provider: request.llm_params["provider"],
        model: request.llm_params["model"],
        analysis_type: detect_analysis_type(request.query)
      }
    }
  end
  
  defp extract_analysis_points(reasoning_steps) do
    reasoning_steps
    |> Enum.filter(fn step ->
      step.name in [:identify_patterns, :analyze_code, :evaluate_quality]
    end)
    |> Enum.flat_map(fn step ->
      parse_analysis_points(step.result)
    end)
  end
  
  defp extract_recommendations(reasoning_steps) do
    reasoning_steps
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
  
  defp detect_analysis_type(query) do
    query_lower = String.downcase(query)
    
    cond do
      String.contains?(query_lower, ["security", "vulnerability", "exploit"]) -> :security
      String.contains?(query_lower, ["performance", "optimize", "speed", "efficiency"]) -> :performance
      String.contains?(query_lower, ["architecture", "design", "structure"]) -> :architecture
      String.contains?(query_lower, ["review", "quality", "best practice"]) -> :code_review
      String.contains?(query_lower, ["complexity", "maintainability", "readability"]) -> :complexity
      true -> :general_analysis
    end
  end
  
  defp extract_code_from_context(context) do
    context[:code] || context[:current_code] || ""
  end
  
  # State management helpers
  
  defp add_to_queue(agent, request) do
    state_updates = %{
      analysis_queue: agent.state.analysis_queue ++ [request],
      active_analyses: Map.put(agent.state.active_analyses, request.request_id, request)
    }
    UpdateStateAction.run(%{updates: state_updates}, %{agent: agent})
  end
  
  defp emit_analysis_progress(agent, params, status) do
    signal_params = %{
      signal_type: "analysis.progress",
      data: %{
        request_id: params.request_id,
        status: status,
        analysis_type: detect_analysis_type(params.query),
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end
  
  defp emit_async_result(request, result, error) do
    signal_data = case {result, error} do
      {result, nil} ->
        %{
          request_id: request.request_id,
          result: result,
          timestamp: DateTime.utc_now()
        }
      {nil, error} ->
        %{
          request_id: request.request_id,
          error: error,
          timestamp: DateTime.utc_now()
        }
    end
    
    signal = Jido.Signal.new!(%{
      type: "analysis.result",
      source: "agent:code_analysis",
      data: signal_data
    })
    
    # Publish directly to signal bus from async context
    Jido.Signal.Bus.publish(RubberDuck.SignalBus, [signal])
  end
end