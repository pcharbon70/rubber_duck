defmodule RubberDuckWeb.ConversationChannel do
  @moduledoc """
  Channel for handling AI conversations.
  
  This channel manages conversational interactions with the AI system,
  maintaining context across messages and routing to appropriate engines.
  
  ## Message Types
  
  ### Incoming
  - `"message"` - Send a message in the conversation
  - `"new_conversation"` - Start a new conversation (clears context)
  - `"set_context"` - Update conversation context
  - `"typing"` - User typing indicator
  
  ### Outgoing  
  - `"response"` - AI response to a message
  - `"thinking"` - AI is processing indicator
  - `"error"` - Error occurred during processing
  - `"context_updated"` - Context was updated
  - `"conversation_reset"` - Conversation was reset
  """
  
  use RubberDuckWeb, :channel
  require Logger
  
  alias RubberDuck.Engine.Manager, as: EngineManager
  
  @default_timeout 60_000
  @max_context_messages 20
  
  @impl true
  def join("conversation:" <> conversation_id, params, socket) do
    Logger.info("User joining conversation: #{conversation_id}")
    
    # Initialize conversation state
    socket =
      socket
      |> assign(:conversation_id, conversation_id)
      |> assign(:messages, [])
      |> assign(:context, %{})
      |> assign(:user_id, params["user_id"] || generate_user_id())
      |> assign(:session_id, generate_session_id())
      |> assign(:preferences, Map.get(params, "preferences", %{}))
    
    {:ok, %{conversation_id: conversation_id, session_id: socket.assigns.session_id}, socket}
  end
  
  @impl true
  def handle_in("message", %{"content" => content} = params, socket) do
    Logger.debug("Received message: #{String.slice(content, 0, 50)}...")
    
    # Send thinking indicator
    push(socket, "thinking", %{})
    
    # Add user message to history
    user_message = %{
      role: "user",
      content: content,
      timestamp: DateTime.utc_now()
    }
    
    messages = add_message(socket.assigns.messages, user_message)
    socket = assign(socket, :messages, messages)
    
    # Build input for conversation router
    input = %{
      query: content,
      context: build_context(socket, params),
      options: Map.get(params, "options", %{}),
      llm_config: build_llm_config(socket, params)
    }
    
    # Process through conversation router
    case EngineManager.execute(:conversation_router, input, @default_timeout) do
      {:ok, result} ->
        # Add assistant message to history
        assistant_message = %{
          role: "assistant",
          content: result.response,
          timestamp: DateTime.utc_now(),
          metadata: Map.take(result, [:conversation_type, :routed_to, :processing_time])
        }
        
        messages = add_message(messages, assistant_message)
        socket = assign(socket, :messages, messages)
        
        # Send response
        push(socket, "response", format_response(result, content))
        {:noreply, socket}
        
      {:error, reason} ->
        Logger.error("Conversation processing failed: #{inspect(reason)}")
        push(socket, "error", %{
          message: "I encountered an error processing your message.",
          details: format_error(reason)
        })
        {:noreply, socket}
    end
  end
  
  @impl true
  def handle_in("new_conversation", _params, socket) do
    Logger.info("Starting new conversation")
    
    # Reset conversation state
    socket =
      socket
      |> assign(:messages, [])
      |> assign(:context, %{})
      |> assign(:session_id, generate_session_id())
    
    push(socket, "conversation_reset", %{
      session_id: socket.assigns.session_id,
      timestamp: DateTime.utc_now()
    })
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_in("set_context", %{"context" => context}, socket) do
    # Merge new context with existing
    updated_context = Map.merge(socket.assigns.context, context)
    socket = assign(socket, :context, updated_context)
    
    push(socket, "context_updated", %{
      context: updated_context,
      timestamp: DateTime.utc_now()
    })
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_in("typing", %{"typing" => _typing}, socket) do
    # Broadcast typing indicator to other participants if needed
    # For now, just acknowledge
    {:noreply, socket}
  end
  
  # Private functions
  
  defp build_context(socket, params) do
    %{
      user_id: socket.assigns.user_id,
      session_id: socket.assigns.session_id,
      conversation_id: socket.assigns.conversation_id,
      messages: format_messages_for_context(socket.assigns.messages),
      custom_context: socket.assigns.context,
      message_count: length(socket.assigns.messages),
      preferences: socket.assigns.preferences,
      timestamp: DateTime.utc_now()
    }
    |> Map.merge(Map.get(params, "context", %{}))
  end
  
  defp build_llm_config(socket, params) do
    defaults = %{
      temperature: 0.7,
      max_tokens: 2000,
      model: nil  # Let engine decide
    }
    
    defaults
    |> Map.merge(socket.assigns.preferences)
    |> Map.merge(Map.get(params, "llm_config", %{}))
  end
  
  defp format_messages_for_context(messages) do
    messages
    |> Enum.take(-@max_context_messages)
    |> Enum.map(fn msg ->
      %{
        role: msg.role,
        content: msg.content
      }
    end)
  end
  
  defp add_message(messages, new_message) do
    # Keep only recent messages to prevent memory issues
    (messages ++ [new_message])
    |> Enum.take(-(@max_context_messages * 2))
  end
  
  defp format_response(result, original_query) do
    %{
      query: original_query,
      response: result.response,
      conversation_type: result.conversation_type,
      routed_to: result[:routed_to],
      timestamp: DateTime.utc_now(),
      metadata: extract_metadata(result)
    }
  end
  
  defp extract_metadata(result) do
    %{
      processing_time: result[:processing_time],
      model_used: result[:metadata][:model],
      steps: result[:reasoning_steps] || result[:solution_steps],
      analysis_points: result[:analysis_points],
      recommendations: result[:recommendations],
      generated_code: result[:generated_code],
      implementation_plan: result[:implementation_plan],
      root_cause: result[:root_cause]
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end
  
  defp format_error(reason) do
    case reason do
      {:engine_error, engine, details} ->
        "Engine #{engine} error: #{inspect(details)}"
      {:timeout, _} ->
        "Request timed out. Please try again."
      _ ->
        "An unexpected error occurred."
    end
  end
  
  defp generate_user_id do
    "user_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
  
  defp generate_session_id do
    "session_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
end