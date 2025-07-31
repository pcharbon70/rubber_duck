defmodule RubberDuck.Agents.GeneralConversationAgent do
  @moduledoc """
  Autonomous agent for handling general conversations.
  
  This agent provides flexible conversation handling for queries that don't
  fit into specific categories. It manages conversation context, handles
  topic changes, and can hand off to specialized agents when needed.
  
  ## Signals
  
  ### Input Signals
  - `conversation_request`: General conversation request
  - `context_switch`: Request to switch conversation context
  - `clarification_response`: Response to clarification request
  - `get_conversation_metrics`: Request current metrics
  
  ### Output Signals
  - `conversation_result`: Response to conversation
  - `clarification_request`: Request for clarification
  - `topic_change`: Notification of topic change
  - `context_switch`: Context has been switched
  - `conversation_summary`: Summary of conversation
  - `handoff_request`: Request to hand off to specialized agent
  - `conversation_metrics`: Current metrics data
  """
  
  use RubberDuck.Agents.BaseAgent,
    name: "general_conversation",
    description: "Handles general conversations with flexible context management",
    category: "conversation",
    schema: [
      active_conversations: [type: :map, default: %{}],
      conversation_history: [type: {:list, :map}, default: []],
      context_stack: [type: {:list, :map}, default: []],
      current_context: [type: :map, default: %{}],
      response_strategies: [type: :map, default: %{
        simple: true,
        detailed: false,
        technical: false,
        casual: true
      }],
      metrics: [type: :map, default: %{
        total_conversations: 0,
        context_switches: 0,
        clarifications_requested: 0,
        handoffs: 0,
        avg_response_time_ms: 0
      }],
      conversation_config: [type: :map, default: %{
        max_history_length: 100,
        context_timeout_ms: 300_000,  # 5 minutes
        enable_learning: true,
        enable_personalization: false
      }]
    ]
  
  require Logger
  
  alias RubberDuck.LLM.Service, as: LLMService
  alias RubberDuck.CoT.QuestionClassifier
  
  # Signal Handlers
  
  @impl true
  def handle_signal(agent, %{"type" => "conversation_request"} = signal) do
    %{
      "data" => %{
        "query" => query,
        "conversation_id" => conversation_id,
        "context" => context
      } = data
    } = signal
    
    # Get or create conversation
    conversation = get_or_create_conversation(agent, conversation_id, context)
    
    # Check if we need clarification
    if needs_clarification?(query, conversation) do
      handle_clarification_needed(agent, conversation_id, query)
    else
      # Process the conversation request
      agent = update_conversation(agent, conversation_id, %{
        last_query: query,
        last_activity: System.monotonic_time(:millisecond)
      })
      
      # Start async processing
      Task.start(fn ->
        process_conversation(agent.id, conversation_id, query, data)
      end)
      
      {:ok, agent}
    end
  end
  
  def handle_signal(agent, %{"type" => "context_switch"} = signal) do
    %{
      "data" => %{
        "conversation_id" => conversation_id,
        "new_context" => new_context,
        "preserve_history" => preserve_history
      }
    } = signal
    
    case agent.state.active_conversations[conversation_id] do
      nil ->
        {:ok, agent}
      
      conversation ->
        # Save current context to stack
        agent = if preserve_history do
          update_in(agent.state.context_stack, fn stack ->
            [conversation.context | Enum.take(stack, 9)]  # Keep last 10 contexts
          end)
        else
          agent
        end
        
        # Switch context
        agent = update_conversation(agent, conversation_id, %{
          context: new_context,
          context_switched_at: System.monotonic_time(:millisecond)
        })
        
        # Update metrics
        agent = update_in(agent.state.metrics.context_switches, &(&1 + 1))
        
        # Emit context switch notification
        signal = Jido.Signal.new!(%{
          type: "conversation.context.switch",
          source: "agent:#{agent.id}",
          data: %{
            conversation_id: conversation_id,
            previous_context: conversation.context,
            new_context: new_context,
            timestamp: DateTime.utc_now()
          }
        })
        emit_signal(agent, signal)
        
        {:ok, agent}
    end
  end
  
  def handle_signal(agent, %{"type" => "clarification_response"} = signal) do
    %{
      "data" => %{
        "conversation_id" => conversation_id,
        "clarification" => clarification,
        "original_query" => original_query
      } = data
    } = signal
    
    # Process with clarification
    Task.start(fn ->
      clarified_query = "#{original_query} (Clarification: #{clarification})"
      process_conversation(agent.id, conversation_id, clarified_query, data)
    end)
    
    {:ok, agent}
  end
  
  def handle_signal(agent, %{"type" => "get_conversation_metrics"} = _signal) do
    # Calculate additional metrics
    active_count = map_size(agent.state.active_conversations)
    total_messages = Enum.reduce(agent.state.active_conversations, 0, fn {_, conv}, acc ->
      acc + length(conv[:messages] || [])
    end)
    
    signal = Jido.Signal.new!(%{
      type: "conversation.metrics",
      source: "agent:#{agent.id}",
      data: %{
        metrics: agent.state.metrics,
        active_conversations: active_count,
        total_messages: total_messages,
        history_size: length(agent.state.conversation_history),
        context_stack_depth: length(agent.state.context_stack),
        config: agent.state.conversation_config,
        timestamp: DateTime.utc_now()
      }
    })
    emit_signal(agent, signal)
    
    {:ok, agent}
  end
  
  def handle_signal(agent, signal) do
    Logger.warning("GeneralConversationAgent received unknown signal: #{inspect(signal["type"])}")
    {:ok, agent}
  end
  
  # Private Functions
  
  defp get_or_create_conversation(agent, conversation_id, context) do
    case agent.state.active_conversations[conversation_id] do
      nil ->
        %{
          id: conversation_id,
          context: context || %{},
          messages: [],
          created_at: System.monotonic_time(:millisecond),
          last_activity: System.monotonic_time(:millisecond)
        }
      
      existing ->
        existing
    end
  end
  
  defp update_conversation(agent, conversation_id, updates) do
    conversation = get_or_create_conversation(agent, conversation_id, %{})
    updated_conversation = Map.merge(conversation, updates)
    
    put_in(agent.state.active_conversations[conversation_id], updated_conversation)
  end
  
  defp needs_clarification?(query, _conversation) do
    # Simple heuristic - check for ambiguous indicators
    ambiguous_terms = ["it", "that", "this", "they", "them"]
    query_lower = String.downcase(query)
    
    # Check if query is too short and contains ambiguous terms
    if String.length(query) < 20 do
      Enum.any?(ambiguous_terms, &String.contains?(query_lower, &1))
    else
      false
    end
  end
  
  defp handle_clarification_needed(agent, conversation_id, query) do
    # Request clarification
    signal = Jido.Signal.new!(%{
      type: "conversation.clarification.request",
      source: "agent:#{agent.id}",
      data: %{
        conversation_id: conversation_id,
        original_query: query,
        reason: "Query is ambiguous",
        suggestions: [
          "Could you provide more context?",
          "What specifically are you referring to?",
          "Can you elaborate on your question?"
        ],
        timestamp: DateTime.utc_now()
      }
    })
    emit_signal(agent, signal)
    
    # Update metrics
    agent = update_in(agent.state.metrics.clarifications_requested, &(&1 + 1))
    
    {:ok, agent}
  end
  
  defp process_conversation(_agent_id, conversation_id, query, data) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      # Classify the query
      classification = QuestionClassifier.classify(query, data["context"] || %{})
      
      # Check if we should hand off to a specialized agent
      if should_handoff?(classification, query) do
        handle_handoff(conversation_id, query, classification, data)
      else
        # Process with general conversation
        response = generate_response(query, data, classification)
        
        # Calculate processing time
        duration = System.monotonic_time(:millisecond) - start_time
        
        # Emit result
        signal = Jido.Signal.new!(%{
          type: "conversation.result",
          source: "agent:general_conversation",
          data: %{
            conversation_id: conversation_id,
            query: query,
            response: response,
            classification: Atom.to_string(classification),
            processing_time_ms: duration,
            timestamp: DateTime.utc_now()
          }
        })
        # In async context, publish directly to signal bus
        Jido.Signal.Bus.publish(RubberDuck.SignalBus, [signal])
        
        # Check for topic change
        if topic_changed?(query, data) do
          signal = Jido.Signal.new!(%{
            type: "conversation.topic.change",
            source: "agent:general_conversation",
            data: %{
              conversation_id: conversation_id,
              new_topic: extract_topic(query),
              timestamp: DateTime.utc_now()
            }
          })
          # In async context, publish directly to signal bus
          Jido.Signal.Bus.publish(RubberDuck.SignalBus, [signal])
        end
      end
      
    rescue
      error ->
        Logger.error("Conversation processing failed",
          conversation_id: conversation_id,
          error: Exception.message(error)
        )
        
        signal = Jido.Signal.new!(%{
          type: "conversation.result",
          source: "agent:general_conversation",
          data: %{
            conversation_id: conversation_id,
            error: Exception.message(error),
            timestamp: DateTime.utc_now()
          }
        })
        # In async context, publish directly to signal bus
        Jido.Signal.Bus.publish(RubberDuck.SignalBus, [signal])
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
    # Check if it's a debugging or complex technical problem
    problem_indicators = ["debug", "error", "fix", "solve", "issue", "problem"]
    query_lower = String.downcase(query)
    
    Enum.any?(problem_indicators, &String.contains?(query_lower, &1))
  end
  
  defp handle_handoff(conversation_id, query, classification, data) do
    target_agent = determine_target_agent(classification, query)
    
    # Package conversation context
    handoff_context = %{
      "conversation_id" => conversation_id,
      "query" => query,
      "classification" => Atom.to_string(classification),
      "context" => data["context"],
      "history" => data["messages"] || []
    }
    
    signal = Jido.Signal.new!(%{
      type: "conversation.handoff.request",
      source: "agent:general_conversation",
      data: %{
        conversation_id: conversation_id,
        target_agent: target_agent,
        context: handoff_context,
        reason: "Query requires specialized handling",
        timestamp: DateTime.utc_now()
      }
    })
    # In async context, publish directly to signal bus
    Jido.Signal.Bus.publish(RubberDuck.SignalBus, [signal])
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
  
  defp generate_response(query, data, classification) do
    # Build messages for LLM
    messages = build_messages(query, data)
    
    # Select appropriate model parameters based on classification
    llm_opts = build_llm_options(data, messages, classification)
    
    case LLMService.completion(llm_opts) do
      {:ok, response} ->
        extract_content(response)
      
      {:error, reason} ->
        Logger.error("LLM call failed: #{inspect(reason)}")
        "I apologize, but I encountered an error processing your request. Please try again."
    end
  end
  
  defp build_messages(query, data) do
    system_message = build_system_message(data["context"])
    
    messages = [%{"role" => "system", "content" => system_message}]
    
    # Add conversation history
    history = data["messages"] || []
    messages = messages ++ format_history(history)
    
    # Add current query
    messages ++ [%{"role" => "user", "content" => query}]
  end
  
  defp build_system_message(context) do
    base_prompt = """
    You are a helpful AI assistant engaged in a general conversation.
    Provide clear, appropriate responses based on the context and query type.
    Be conversational but informative. Adapt your tone to match the user's style.
    """
    
    # Add context-specific instructions
    case context["style"] do
      "technical" -> base_prompt <> "\nUse technical language and be precise."
      "casual" -> base_prompt <> "\nKeep the tone casual and friendly."
      "professional" -> base_prompt <> "\nMaintain a professional tone."
      _ -> base_prompt
    end
  end
  
  defp format_history(messages) do
    messages
    |> Enum.take(-10)  # Keep last 10 messages for context
    |> Enum.map(fn msg ->
      %{
        "role" => msg["role"] || "user",
        "content" => msg["content"] || ""
      }
    end)
  end
  
  defp build_llm_options(data, messages, classification) do
    # Base options
    base_opts = [
      provider: data["provider"] || "openai",
      model: data["model"] || "gpt-4",
      messages: messages,
      user_id: data["user_id"]
    ]
    
    # Adjust based on classification
    case classification do
      c when c in [:simple, :factual] ->
        base_opts ++ [
          temperature: 0.3,
          max_tokens: 500
        ]
      
      c when c in [:creative, :brainstorming] ->
        base_opts ++ [
          temperature: 0.8,
          max_tokens: 1500
        ]
      
      _ ->
        base_opts ++ [
          temperature: 0.6,
          max_tokens: 1000
        ]
    end
  end
  
  defp extract_content(response) do
    case response do
      %{choices: [%{message: %{"content" => content}} | _]} ->
        String.trim(content)
      
      %{choices: [%{message: %{content: content}} | _]} ->
        String.trim(content)
      
      _ ->
        "I couldn't generate a proper response."
    end
  end
  
  defp topic_changed?(query, data) do
    # Simple topic change detection
    previous_queries = (data["messages"] || [])
    |> Enum.filter(fn m -> m["role"] == "user" end)
    |> Enum.map(fn m -> m["content"] end)
    |> Enum.take(-3)  # Last 3 user messages
    
    if Enum.empty?(previous_queries) do
      false
    else
      # Check if current query is significantly different
      avg_similarity = previous_queries
      |> Enum.map(&calculate_similarity(&1, query))
      |> Enum.sum()
      |> Kernel./(length(previous_queries))
      
      avg_similarity < 0.3  # Low similarity indicates topic change
    end
  end
  
  defp calculate_similarity(text1, text2) do
    # Simple word overlap similarity
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
    # Simple topic extraction - in production would use NLP
    query
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.split()
    |> Enum.filter(&(String.length(&1) > 4))  # Keep meaningful words
    |> Enum.take(3)
    |> Enum.join(" ")
  end
end