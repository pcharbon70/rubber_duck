defmodule RubberDuck.Jido.Actions.Conversation.General.ClarificationResponseAction do
  @moduledoc """
  Action for handling clarification responses from users.
  
  This action processes user clarifications by:
  - Combining original query with clarification
  - Starting async conversation processing with clarified query
  - Managing conversation flow continuation
  """
  
  use Jido.Action,
    name: "clarification_response",
    description: "Handles user clarification responses and continues conversation processing",
    schema: [
      conversation_id: [type: :string, required: true, doc: "Conversation identifier"],
      clarification: [type: :string, required: true, doc: "User's clarification"],
      original_query: [type: :string, required: true, doc: "Original query that needed clarification"],
      context: [type: :map, default: %{}, doc: "Additional context"],
      user_id: [type: :string, default: nil, doc: "User identifier"],
      provider: [type: :string, default: "openai", doc: "LLM provider"],
      model: [type: :string, default: "gpt-4", doc: "LLM model"]
    ]

  require Logger
  
  alias RubberDuck.CoT.QuestionClassifier

  @impl true
  def run(params, context) do
    agent = context.agent
    
    # Combine original query with clarification
    clarified_query = "#{params.original_query} (Clarification: #{params.clarification})"
    
    # Start async processing with clarified query
    Task.start(fn ->
      process_clarified_conversation(agent.id, params, clarified_query)
    end)
    
    {:ok, %{
      processing_started: true,
      clarified_query: clarified_query,
      conversation_id: params.conversation_id
    }, %{agent: agent}}
  end

  # Private functions

  defp process_clarified_conversation(_agent_id, params, clarified_query) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      # Classify the clarified query
      classification = QuestionClassifier.classify(clarified_query, params.context)
      
      # Check if we should hand off to a specialized agent
      if should_handoff?(classification, clarified_query) do
        handle_handoff_async(params, classification, clarified_query)
      else
        # Process with general conversation
        response = generate_response_async(params, clarified_query, classification)
        
        # Calculate processing time
        duration = System.monotonic_time(:millisecond) - start_time
        
        # Emit result
        result_signal = %{
          type: "conversation.result",
          source: "agent:general_conversation",
          data: %{
            conversation_id: params.conversation_id,
            query: clarified_query,
            original_query: params.original_query,
            clarification: params.clarification,
            response: response,
            classification: Atom.to_string(classification),
            processing_time_ms: duration,
            timestamp: DateTime.utc_now()
          }
        }
        
        Jido.Signal.Bus.publish(RubberDuck.SignalBus, [Jido.Signal.new!(result_signal)])
      end
      
    rescue
      error ->
        Logger.error("Clarified conversation processing failed",
          conversation_id: params.conversation_id,
          error: Exception.message(error)
        )
        
        error_signal = %{
          type: "conversation.result",
          source: "agent:general_conversation",
          data: %{
            conversation_id: params.conversation_id,
            error: Exception.message(error),
            clarified_query: clarified_query,
            timestamp: DateTime.utc_now()
          }
        }
        
        Jido.Signal.Bus.publish(RubberDuck.SignalBus, [Jido.Signal.new!(error_signal)])
    end
  end

  defp should_handoff?(classification, query) do
    case classification do
      :complex_problem -> should_handoff_to_problem_solver?(query)
      :code_generation -> true
      :planning -> true
      :analysis -> true
      _ -> false
    end
  end

  defp should_handoff_to_problem_solver?(query) do
    problem_indicators = ["debug", "error", "fix", "solve", "issue", "problem"]
    query_lower = String.downcase(query)
    
    Enum.any?(problem_indicators, &String.contains?(query_lower, &1))
  end

  defp handle_handoff_async(params, classification, clarified_query) do
    target_agent = determine_target_agent(classification, clarified_query)
    
    handoff_context = %{
      "conversation_id" => params.conversation_id,
      "query" => clarified_query,
      "original_query" => params.original_query,
      "clarification" => params.clarification,
      "classification" => Atom.to_string(classification),
      "context" => params.context
    }
    
    signal = %{
      type: "conversation.handoff.request",
      source: "agent:general_conversation",
      data: %{
        conversation_id: params.conversation_id,
        target_agent: target_agent,
        context: handoff_context,
        reason: "Clarified query requires specialized handling",
        timestamp: DateTime.utc_now()
      }
    }
    
    Jido.Signal.Bus.publish(RubberDuck.SignalBus, [Jido.Signal.new!(signal)])
  end

  defp determine_target_agent(classification, query) do
    case classification do
      :code_generation -> "generation_conversation"
      :planning -> "planning_conversation"
      :analysis -> "code_analysis"
      :complex_problem ->
        if should_handoff_to_problem_solver?(query) do
          "problem_solver"
        else
          "complex_conversation"
        end
      _ -> "simple_conversation"
    end
  end

  defp generate_response_async(_params, clarified_query, classification) do
    # This would integrate with the LLM service
    # For now, returning a placeholder that includes clarification context
    "Generated response for clarified query: #{clarified_query} (classification: #{classification})"
  end
end