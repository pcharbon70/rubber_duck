defmodule RubberDuckWeb.ConversationChannel do
  @moduledoc """
  Channel for handling AI conversations.

  This channel manages conversational interactions with the AI system,
  maintaining context across messages and routing to appropriate engines.

  ## Core Features

  ### Conversation Management
  - Real-time messaging with AI engines
  - Context preservation across sessions
  - Multi-turn conversation support
  - Engine routing based on message type

  ## Message Types

  ### Incoming
  - `"message"` - Send a message in the conversation
    - Params: `%{"content" => "...", "llm_config" => %{"provider" => "openai", "model" => "gpt-4"}}`
  - `"new_conversation"` - Start a new conversation (clears context)
  - `"set_context"` - Update conversation context
  - `"typing"` - User typing indicator
  - `"get_history"` - Get conversation message history
    - Params: `%{"limit" => 100}` (optional, defaults to 100)

  ### Outgoing
  - `"response"` - AI response to a message
  - `"thinking"` - AI is processing indicator
  - `"error"` - Error occurred during processing
  - `"context_updated"` - Context was updated
  - `"conversation_reset"` - Conversation was reset
  - `"history"` - Conversation history response
    - Payload: `%{conversation_id: "uuid", messages: [...], count: 50}`

  ## Error Handling

  The channel includes comprehensive error handling for:
  - Missing provider/model configuration
  - Invalid message formats
  - Engine processing failures
  - Timeout errors

  ## Usage Example

  ```javascript
  // Send a message with LLM configuration
  channel.push("message", {
    content: "Hello, how are you?",
    llm_config: {
      provider: "openai",
      model: "gpt-4",
      temperature: 0.7
    }
  })
  ```
  """

  use RubberDuckWeb, :channel
  require Logger

  alias RubberDuck.Engine.Manager, as: EngineManager
  alias RubberDuck.Engine.{TaskRegistry, CancellationToken}
  alias RubberDuck.Conversations
  alias RubberDuck.Status
  alias RubberDuck.LLM.ErrorHandler
  alias RubberDuck.Engine.InputValidator
  alias RubberDuck.Config.Timeouts

  @default_timeout Timeouts.get([:channels, :conversation], 60_000)
  @max_context_messages 20

  @impl true
  def join("conversation:" <> conversation_id, params, socket) do
    Logger.info("User joining conversation: #{conversation_id}")

    # Use authenticated user_id from socket, fall back to generated ID for anonymous users
    user_id = socket.assigns[:user_id] || generate_user_id()
    session_id = generate_session_id()

    # Handle lobby specially - load or create user's latest conversation
    actual_conversation_id = if conversation_id == "lobby" && socket.assigns[:user_id] do
      case load_or_create_user_conversation(user_id, params) do
        {:ok, conversation} ->
          Logger.info("Loaded/created conversation #{conversation.id} for user #{user_id} from lobby")
          conversation.id
          
        {:error, reason} ->
          Logger.error("Failed to load/create conversation for lobby: #{inspect(reason)}")
          # Fall back to using lobby as conversation_id (will likely fail downstream)
          conversation_id
      end
    else
      # For non-lobby conversations, ensure it exists
      if socket.assigns[:user_id] do
        ensure_conversation_exists(conversation_id, user_id, params)
      end
      conversation_id
    end

    # Initialize conversation state
    socket =
      socket
      |> assign(:conversation_id, actual_conversation_id)
      |> assign(:messages, [])
      |> assign(:context, %{})
      |> assign(:user_id, user_id)
      |> assign(:session_id, session_id)
      |> assign(:current_cancellation_token, nil)

    # Subscribe to status updates for this conversation
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:#{actual_conversation_id}:engine")
    Phoenix.PubSub.subscribe(RubberDuck.PubSub, "status:#{actual_conversation_id}:workflow")
    
    # Log session creation
    Logger.debug("Session created for user #{user_id}")

    {:ok, %{conversation_id: actual_conversation_id, session_id: session_id}, socket}
  end

  @impl true
  def handle_in("message", %{"content" => content} = params, socket) do
    Logger.debug("Received message: #{String.slice(content, 0, 50)}...")
    conversation_id = socket.assigns.conversation_id

    # Send status for message received
    Status.info(
      conversation_id,
      "Message received",
      %{
        message_length: String.length(content),
        user_id: socket.assigns.user_id,
        session_id: socket.assigns.session_id
      }
    )

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

    # Send status for processing start
    Status.progress(
      conversation_id,
      "Processing message",
      %{
        message_count: length(messages),
        context_size: map_size(socket.assigns.context)
      }
    )

    # Build input for conversation router
    llm_config = build_llm_config(socket, params)
    
    # Ensure provider and model are available
    if not Map.has_key?(llm_config, :provider) or not Map.has_key?(llm_config, :model) do
      push(socket, "error", %{
        message: "Please configure your LLM provider and model in settings.",
        type: "llm_not_configured"
      })
      {:noreply, socket}
    else
      # Create a cancellation token for this request
      cancellation_token = CancellationToken.create(conversation_id)
      
      # Clean up any previous token
      if socket.assigns.current_cancellation_token do
        CancellationToken.stop(socket.assigns.current_cancellation_token)
      end
      
      # Update socket with new token
      socket = assign(socket, :current_cancellation_token, cancellation_token)
      
      input = %{
        query: content,
        context: build_context(socket, params),
        options: Map.get(params, "options", %{}),
        llm_config: llm_config,
        # Pass provider and model at top level for engines
        provider: llm_config.provider,
        model: llm_config.model,
        user_id: socket.assigns.user_id,
        temperature: llm_config[:temperature],
        max_tokens: llm_config[:max_tokens],
        conversation_id: conversation_id
      }
      
      # Add cancellation token to input
      input = CancellationToken.add_to_input(input, cancellation_token)

    start_time = System.monotonic_time(:millisecond)

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

        # Log successful completion
        Logger.debug("Message processed successfully")

        # Send completion status
        Status.with_timing(
          conversation_id,
          :info,
          "Response sent",
          start_time,
          %{
            response_length: String.length(result.response),
            conversation_type: result.conversation_type,
            routed_to: result[:routed_to],
            model_used: input.llm_config[:model]
          }
        )

        # Send response
        push(socket, "response", format_response(result, content))
        {:noreply, socket}

      {:error, :cancelled} ->
        Logger.info("Conversation processing was cancelled")
        
        # Broadcast cancellation notification to all subscribers
        broadcast!(socket, "processing_cancelled", %{
          message: "Processing was cancelled",
          timestamp: DateTime.utc_now(),
          cancelled_by: socket.assigns.user_id
        })
        
        {:noreply, socket}
        
      {:error, reason} ->
        Logger.error("Conversation processing failed: #{inspect(reason)}")

        # Send error status
        Status.error(
          conversation_id,
          "Failed to process message",
          Status.build_error_metadata(:conversation_error, format_error(reason), %{
            user_id: socket.assigns.user_id,
            session_id: socket.assigns.session_id,
            message_length: String.length(content)
          })
        )

        # Try error recovery
        error_message = format_user_error(reason)
        
        push(socket, "error", %{
          message: error_message,
          type: extract_error_type(reason),
          recoverable: is_recoverable_error?(reason),
          details: format_error(reason)
        })

        {:noreply, socket}
    end
    end  # Close the if/else for provider/model check
  end

  @impl true
  def handle_in("message", _params, socket) do
    # Handle messages without content
    push(socket, "error", %{
      message: "Message content is required",
      type: "invalid_message"
    })
    {:noreply, socket}
  end

  @impl true
  def handle_in("new_conversation", _params, socket) do
    Logger.info("Starting new conversation")
    conversation_id = socket.assigns.conversation_id

    # Send status for conversation reset
    Status.info(
      conversation_id,
      "Conversation reset",
      %{
        user_id: socket.assigns.user_id,
        previous_message_count: length(socket.assigns.messages)
      }
    )

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





  
  @impl true
  def handle_in("get_history", params, socket) do
    conversation_id = socket.assigns.conversation_id
    limit = Map.get(params, "limit", 100)
    
    case get_conversation_messages(conversation_id, limit) do
      {:ok, page} ->
        # Extract messages from the Ash.Page.Keyset struct
        messages = page.results
        
        # Format messages for client
        formatted_messages = Enum.map(messages, fn msg ->
          %{
            id: msg.id,
            role: msg.role,
            content: msg.content,
            metadata: msg.metadata || %{},
            created_at: msg.inserted_at
          }
        end)
        
        push(socket, "history", %{
          conversation_id: conversation_id,
          messages: formatted_messages,
          count: length(formatted_messages)
        })
        
      {:error, reason} ->
        push(socket, "error", %{
          message: "Failed to load conversation history",
          details: format_error(reason)
        })
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_in("cancel_processing", _params, socket) do
    conversation_id = socket.assigns.conversation_id
    
    Logger.info("Received cancel request for conversation #{conversation_id}")
    
    # Cancel via the cancellation token if available
    if socket.assigns.current_cancellation_token do
      CancellationToken.cancel(socket.assigns.current_cancellation_token, :user_requested)
    end
    
    # Also cancel any registered tasks for this conversation
    {:ok, cancelled_count} = TaskRegistry.cancel_conversation_tasks(conversation_id)
    Logger.info("Cancelled #{cancelled_count} tasks for conversation #{conversation_id}")
    
    # Broadcast cancellation to all subscribers
    broadcast!(socket, "processing_cancelled", %{
      message: "Processing cancelled",
      tasks_cancelled: cancelled_count,
      timestamp: DateTime.utc_now(),
      cancelled_by: socket.assigns.user_id
    })
    
    {:noreply, socket}
  end


  @impl true
  def handle_info({:status_update, category, text, metadata}, socket) do
    # Forward status updates to the client
    push(socket, "status_update", %{
      category: category,
      text: text,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    })
    
    # Check if this is a cancellation-related status
    if String.contains?(text, "cancelled") || String.contains?(text, "cancelled") do
      # Also send a more specific cancellation event
      push(socket, "processing_cancelled", %{
        message: text,
        metadata: metadata,
        timestamp: DateTime.utc_now()
      })
    end
    
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
      timestamp: DateTime.utc_now()
    }
    |> Map.merge(Map.get(params, "context", %{}))
  end

  defp build_llm_config(socket, params) do
    defaults = %{
      temperature: 0.7,
      max_tokens: 2000
    }

    # Get llm_config from params and convert string keys to atoms
    llm_params = Map.get(params, "llm_config", %{})
    
    # Convert string keys to atoms for provider and model
    llm_config = if llm_params["provider"] && llm_params["model"] do
      %{
        provider: String.to_atom(llm_params["provider"]),
        model: llm_params["model"]
      }
    else
      %{}
    end

    # Merge with defaults and other parameters
    config =
      defaults
      |> Map.merge(llm_config)
      |> Map.merge(%{
        temperature: llm_params["temperature"] || defaults.temperature,
        max_tokens: llm_params["max_tokens"] || defaults.max_tokens
      })
      |> Map.put(:user_id, socket.assigns.user_id)

    config
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


  defp ensure_conversation_exists(conversation_id, user_id, params) do
    # First get the user to use as actor
    case get_user_for_actor(user_id) do
      {:ok, user} ->
        # Check if conversation already exists (using authorize?: false for read check)
        case Conversations.get_conversation(conversation_id, authorize?: false) do
          {:ok, conversation} ->
            # Verify the conversation belongs to this user
            if conversation.user_id == user_id do
              {:ok, conversation}
            else
              Logger.warning(
                "User #{user_id} tried to access conversation #{conversation_id} owned by #{conversation.user_id}"
              )

              {:error, :unauthorized}
            end

          {:error, _} ->
            # Create new conversation for the user
            attrs = %{
              user_id: user_id,
              title: Map.get(params, "title", "New Conversation"),
              metadata: Map.get(params, "metadata", %{}),
              status: :active
            }

            # Set the ID in the attributes directly
            attrs = Map.put(attrs, :id, conversation_id)
            
            case Conversations.create_conversation(attrs, actor: user) do
              {:ok, conversation} ->
                Logger.info("Created conversation #{conversation_id} for user #{user_id}")
                {:ok, conversation}

              {:error, reason} ->
                Logger.error("Failed to create conversation: #{inspect(reason)}")
                {:error, reason}
            end
        end

      {:error, _} ->
        Logger.error("Could not find user #{user_id} for conversation creation")
        {:error, :user_not_found}
    end
  end

  defp get_user_for_actor(user_id) do
    RubberDuck.Accounts.get_user(user_id, authorize?: false)
  end
  
  defp get_conversation_messages(conversation_id, limit) do
    # Get the user_id from the socket assigns through the calling function
    # For now, we'll use authorize?: false to allow access
    Conversations.get_conversation_history(
      %{conversation_id: conversation_id, limit: limit},
      authorize?: false
    )
  end
  
  defp load_or_create_user_conversation(user_id, params) do
    case get_user_for_actor(user_id) do
      {:ok, user} ->
        # Try to get the user's latest conversation
        case Conversations.get_latest_conversation_by_user(%{user_id: user_id}, actor: user) do
          {:ok, conversation} ->
            Logger.info("Found existing conversation #{conversation.id} for user #{user_id}")
            {:ok, conversation}
            
          {:error, _} ->
            # No existing conversation, create a new one
            attrs = %{
              id: Ecto.UUID.generate(),
              user_id: user_id,
              title: Map.get(params, "title", "New Conversation"),
              metadata: Map.get(params, "metadata", %{}),
              status: :active
            }
            
            case Conversations.create_conversation(attrs, actor: user) do
              {:ok, conversation} ->
                Logger.info("Created new conversation #{conversation.id} for user #{user_id}")
                {:ok, conversation}
                
              {:error, reason} = error ->
                Logger.error("Failed to create conversation: #{inspect(reason)}")
                error
            end
        end
        
      {:error, reason} = error ->
        Logger.error("Failed to get user for conversation: #{inspect(reason)}")
        error
    end
  end
  
  defp format_user_error(reason) do
    case reason do
      {:missing_required_field, _field, message} ->
        message
        
      {:missing_required_field, :provider} ->
        "Please configure your LLM provider in settings."
        
      {:missing_required_field, :model} ->
        "Please select a model for your LLM provider."
        
      {:engine_error, _engine, {:cot_error, _details}} ->
        "I'm having trouble processing your request. Please try rephrasing or simplifying your question."
        
      {:timeout, _} ->
        "The request took too long to process. Please try again with a shorter message."
        
      {error_type, %{details: details}} when is_map(details) ->
        ErrorHandler.format_user_error({error_type, details})
        
      error ->
        # Check if it's a validation error
        case error do
          {:error, validation_error} -> 
            InputValidator.format_validation_error(validation_error)
          _ ->
            "I encountered an issue processing your request. Please try again or contact support if the problem persists."
        end
    end
  end
  
  defp extract_error_type(reason) do
    case reason do
      {:missing_required_field, _} -> "configuration_error"
      {:missing_required_field, _, _} -> "configuration_error"
      {:timeout, _} -> "timeout_error"
      {:engine_error, _, _} -> "processing_error"
      {error_type, _} when is_atom(error_type) -> to_string(error_type)
      _ -> "unknown_error"
    end
  end
  
  defp is_recoverable_error?(reason) do
    case reason do
      {:timeout, _} -> true
      {:rate_limit_exceeded, _} -> true
      {:service_unavailable, _} -> true
      _ -> false
    end
  end
end
