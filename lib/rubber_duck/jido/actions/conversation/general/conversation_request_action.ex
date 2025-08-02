defmodule RubberDuck.Jido.Actions.Conversation.General.ConversationRequestAction do
  @moduledoc """
  Action for handling general conversation requests.
  
  This action processes conversation requests by:
  - Creating or retrieving conversation context
  - Checking if clarification is needed
  - Starting async conversation processing
  - Managing conversation state
  """
  
  use Jido.Action,
    name: "conversation_request",
    description: "Handles general conversation requests with context management",
    schema: [
      query: [type: :string, required: true, doc: "The conversation query"],
      conversation_id: [type: :string, required: true, doc: "Unique conversation identifier"],
      context: [type: :map, default: %{}, doc: "Conversation context"],
      user_id: [type: :string, default: nil, doc: "User identifier"],
      messages: [type: {:list, :map}, default: [], doc: "Previous conversation messages"],
      provider: [type: :string, default: "openai", doc: "LLM provider"],
      model: [type: :string, default: "gpt-4", doc: "LLM model"]
    ]

  require Logger
  
  alias RubberDuck.Jido.Actions.Base.{UpdateStateAction, EmitSignalAction}
  alias RubberDuck.CoT.QuestionClassifier

  @impl true
  def run(params, context) do
    agent = context.agent
    
    with {:ok, conversation} <- get_or_create_conversation(agent, params),
         {:ok, needs_clarification?} <- check_clarification_needed(params.query, conversation),
         {:ok, updated_agent} <- update_conversation_state(agent, params.conversation_id, conversation) do
      
      if needs_clarification? do
        handle_clarification_needed(updated_agent, params)
      else
        start_conversation_processing(updated_agent, params)
      end
    end
  end

  # Private functions

  defp get_or_create_conversation(agent, params) do
    conversation = case agent.state.active_conversations[params.conversation_id] do
      nil ->
        %{
          id: params.conversation_id,
          context: params.context,
          messages: params.messages,
          created_at: System.monotonic_time(:millisecond),
          last_activity: System.monotonic_time(:millisecond)
        }
      
      existing ->
        existing
    end
    
    {:ok, conversation}
  end

  defp check_clarification_needed(query, _conversation) do
    # Simple heuristic - check for ambiguous indicators
    ambiguous_terms = ["it", "that", "this", "they", "them"]
    query_lower = String.downcase(query)
    
    needs_clarification = if String.length(query) < 20 do
      Enum.any?(ambiguous_terms, &String.contains?(query_lower, &1))
    else
      false
    end
    
    {:ok, needs_clarification}
  end

  defp update_conversation_state(agent, conversation_id, conversation) do
    updated_conversation = Map.merge(conversation, %{
      last_query: conversation.query || "",
      last_activity: System.monotonic_time(:millisecond)
    })
    
    state_updates = %{
      active_conversations: Map.put(agent.state.active_conversations, conversation_id, updated_conversation)
    }
    
    case UpdateStateAction.run(%{updates: state_updates}, %{agent: agent}) do
      {:ok, _, %{agent: updated_agent}} -> {:ok, updated_agent}
      {:error, reason} -> {:error, reason}
    end
  end

  defp handle_clarification_needed(agent, params) do
    # Update metrics
    metrics_updates = %{
      metrics: update_in(agent.state.metrics.clarifications_requested, &(&1 + 1))
    }
    
    with {:ok, _, %{agent: updated_agent}} <- UpdateStateAction.run(%{updates: metrics_updates}, %{agent: agent}),
         {:ok, _} <- emit_clarification_request(updated_agent, params) do
      {:ok, %{clarification_requested: true}, %{agent: updated_agent}}
    end
  end

  defp start_conversation_processing(agent, params) do
    # Start async processing
    Task.start(fn ->
      process_conversation_async(agent.id, params)
    end)
    
    {:ok, %{processing_started: true}, %{agent: agent}}
  end

  defp emit_clarification_request(agent, params) do
    signal_params = %{
      signal_type: "conversation.clarification.request",
      data: %{
        conversation_id: params.conversation_id,
        original_query: params.query,
        reason: "Query is ambiguous",
        suggestions: [
          "Could you provide more context?",
          "What specifically are you referring to?",
          "Can you elaborate on your question?"
        ],
        timestamp: DateTime.utc_now()
      }
    }
    
    EmitSignalAction.run(signal_params, %{agent: agent})
  end

  defp process_conversation_async(_agent_id, params) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      # Classify the query
      classification = QuestionClassifier.classify(params.query, params.context)
      
      # Check if we should hand off to a specialized agent
      if should_handoff?(classification, params.query) do
        handle_handoff_async(params, classification)
      else
        # Process with general conversation
        response = generate_response_async(params, classification)
        
        # Calculate processing time
        duration = System.monotonic_time(:millisecond) - start_time
        
        # Emit result
        result_signal = %{
          type: "conversation.result",
          source: "agent:general_conversation",
          data: %{
            conversation_id: params.conversation_id,
            query: params.query,
            response: response,
            classification: Atom.to_string(classification),
            processing_time_ms: duration,
            timestamp: DateTime.utc_now()
          }
        }
        
        Jido.Signal.Bus.publish(RubberDuck.SignalBus, [Jido.Signal.new!(result_signal)])
        
        # Check for topic change
        if topic_changed?(params.query, params) do
          topic_signal = %{
            type: "conversation.topic.change",
            source: "agent:general_conversation",
            data: %{
              conversation_id: params.conversation_id,
              new_topic: extract_topic(params.query),
              timestamp: DateTime.utc_now()
            }
          }
          
          Jido.Signal.Bus.publish(RubberDuck.SignalBus, [Jido.Signal.new!(topic_signal)])
        end
      end
      
    rescue
      error ->
        Logger.error("Conversation processing failed",
          conversation_id: params.conversation_id,
          error: Exception.message(error)
        )
        
        error_signal = %{
          type: "conversation.result",
          source: "agent:general_conversation",
          data: %{
            conversation_id: params.conversation_id,
            error: Exception.message(error),
            timestamp: DateTime.utc_now()
          }
        }
        
        Jido.Signal.Bus.publish(RubberDuck.SignalBus, [Jido.Signal.new!(error_signal)])
    end
  end

  # Helper functions (extracted from original agent)
  
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

  defp handle_handoff_async(params, classification) do
    target_agent = determine_target_agent(classification, params.query)
    
    handoff_context = %{
      "conversation_id" => params.conversation_id,
      "query" => params.query,
      "classification" => Atom.to_string(classification),
      "context" => params.context,
      "history" => params.messages
    }
    
    signal = %{
      type: "conversation.handoff.request",
      source: "agent:general_conversation",
      data: %{
        conversation_id: params.conversation_id,
        target_agent: target_agent,
        context: handoff_context,
        reason: "Query requires specialized handling",
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

  defp generate_response_async(params, classification) do
    # This would integrate with the LLM service
    # For now, returning a placeholder
    "Generated response for: #{params.query} (classification: #{classification})"
  end

  defp topic_changed?(query, params) do
    previous_queries = params.messages
    |> Enum.filter(fn m -> m["role"] == "user" end)
    |> Enum.map(fn m -> m["content"] end)
    |> Enum.take(-3)
    
    if Enum.empty?(previous_queries) do
      false
    else
      avg_similarity = previous_queries
      |> Enum.map(&calculate_similarity(&1, query))
      |> Enum.sum()
      |> Kernel./(length(previous_queries))
      
      avg_similarity < 0.3
    end
  end

  defp calculate_similarity(text1, text2) do
    words1 = text1 |> String.downcase() |> String.split()
    words2 = text2 |> String.downcase() |> String.split()
    
    intersection = MapSet.intersection(MapSet.new(words1), MapSet.new(words2))
    union = MapSet.union(MapSet.new(words1), MapSet.new(words2))
    
    if MapSet.size(union) == 0 do
      0.0
    else
      MapSet.size(intersection) / MapSet.size(union)
    end
  end

  defp extract_topic(query) do
    query
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.split()
    |> Enum.filter(&(String.length(&1) > 4))
    |> Enum.take(3)
    |> Enum.join(" ")
  end
end