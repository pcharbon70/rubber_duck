defmodule RubberDuckWeb.ConversationChannel do
  @moduledoc """
  Channel for handling AI conversations and LLM preference management.
  
  This channel manages conversational interactions with the AI system,
  maintaining context across messages, routing to appropriate engines,
  and providing real-time management of user LLM preferences.
  
  ## Core Features
  
  ### Conversation Management
  - Real-time messaging with AI engines
  - Context preservation across sessions
  - Multi-turn conversation support
  - Engine routing based on message type
  
  ### LLM Preference Management
  - Per-user LLM provider/model configuration
  - Real-time preference updates
  - Usage statistics tracking
  - Session-aware configuration resolution
  
  ## Message Types
  
  ### Incoming - Conversation
  - `"message"` - Send a message in the conversation
  - `"new_conversation"` - Start a new conversation (clears context)
  - `"set_context"` - Update conversation context
  - `"typing"` - User typing indicator
  
  ### Incoming - LLM Preferences
  - `"set_llm_preference"` - Set user's LLM provider/model preference
    - Params: `%{"provider" => "openai", "model" => "gpt-4", "is_default" => true}`
  - `"add_llm_model"` - Add a new LLM model to user's configuration
    - Params: `%{"provider" => "anthropic", "model" => "claude-3-sonnet"}`
  - `"get_llm_preferences"` - Get user's LLM preferences
    - Params: `%{}`
  - `"get_llm_default"` - Get user's default LLM configuration
    - Params: `%{}`
  - `"remove_llm_provider"` - Remove a provider from user's configuration
    - Params: `%{"provider" => "openai"}`
  - `"get_llm_usage_stats"` - Get usage statistics for user's LLM configurations
    - Params: `%{}`
  
  ### Outgoing - Conversation
  - `"response"` - AI response to a message
  - `"thinking"` - AI is processing indicator
  - `"error"` - Error occurred during processing
  - `"context_updated"` - Context was updated
  - `"conversation_reset"` - Conversation was reset
  
  ### Outgoing - LLM Preferences
  - `"llm_preference_set"` - LLM preference was set successfully
    - Data: `%{"provider" => "openai", "model" => "gpt-4", "is_default" => true, "config" => %{...}}`
  - `"llm_preferences"` - User's LLM preferences
    - Data: `%{"configs" => [...], "count" => 2}`
  - `"llm_default"` - User's default LLM configuration
    - Data: `%{"provider" => "openai", "model" => "gpt-4", "user_id" => "user_123"}`
  - `"llm_provider_removed"` - Provider was removed from configuration
    - Data: `%{"provider" => "openai", "removed_count" => 1}`
  - `"llm_usage_stats"` - Usage statistics for user's LLM configurations
    - Data: `%{"stats" => %{...}, "user_id" => "user_123"}`
  - `"llm_error"` - Error occurred during LLM preference operation
    - Data: `%{"operation" => "set_preference", "message" => "...", "details" => "..."}`
  
  ## Session Integration
  
  The channel automatically integrates with SessionContext to:
  - Cache user LLM preferences for performance
  - Track LLM usage statistics
  - Update session-specific configurations
  - Maintain preference consistency across WebSocket connections
  
  ## Error Handling
  
  All LLM preference operations include comprehensive error handling:
  - Invalid provider/model validation
  - Database constraint violations
  - User authorization checks
  - Graceful degradation for missing configurations
  
  ## Usage Example
  
  ```javascript
  // Set user's default LLM preference
  channel.push("set_llm_preference", {
    provider: "openai",
    model: "gpt-4",
    is_default: true
  })
  
  // Get current preferences
  channel.push("get_llm_preferences", {})
  
  // Remove a provider
  channel.push("remove_llm_provider", {
    provider: "anthropic"
  })
  ```
  """
  
  use RubberDuckWeb, :channel
  require Logger
  
  alias RubberDuck.Engine.Manager, as: EngineManager
  alias RubberDuck.SessionContext
  alias RubberDuck.UserConfig
  
  @default_timeout 60_000
  @max_context_messages 20
  
  @impl true
  def join("conversation:" <> conversation_id, params, socket) do
    Logger.info("User joining conversation: #{conversation_id}")
    
    user_id = params["user_id"] || generate_user_id()
    session_id = generate_session_id()
    preferences = Map.get(params, "preferences", %{})
    
    # Initialize conversation state
    socket =
      socket
      |> assign(:conversation_id, conversation_id)
      |> assign(:messages, [])
      |> assign(:context, %{})
      |> assign(:user_id, user_id)
      |> assign(:session_id, session_id)
      |> assign(:preferences, preferences)
    
    # Create session context with user LLM preferences
    case SessionContext.ensure_context(session_id, user_id, %{preferences: preferences}) do
      {:ok, _context} ->
        Logger.debug("Session context created for user #{user_id}")
        
      {:error, reason} ->
        Logger.warning("Failed to create session context: #{inspect(reason)}")
    end
    
    {:ok, %{conversation_id: conversation_id, session_id: session_id}, socket}
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
        
        # Record LLM usage for this session
        if Map.has_key?(input.llm_config, :provider) and Map.has_key?(input.llm_config, :model) do
          SessionContext.record_llm_usage(
            socket.assigns.session_id,
            input.llm_config.provider,
            input.llm_config.model
          )
        end
        
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
  
  @impl true
  def handle_in("set_llm_preference", %{"provider" => provider, "model" => model} = params, socket) do
    user_id = socket.assigns.user_id
    is_default = Map.get(params, "is_default", true)
    
    case UserConfig.set_default(user_id, String.to_atom(provider), model) do
      {:ok, config} ->
        # Update session context if this is the default
        if is_default do
          SessionContext.update_preferences(socket.assigns.session_id, %{
            llm_provider: String.to_atom(provider),
            llm_model: model
          })
        end
        
        push(socket, "llm_preference_set", %{
          provider: provider,
          model: model,
          is_default: is_default,
          config: %{
            id: config.id,
            usage_count: config.usage_count,
            created_at: config.created_at
          }
        })
        
      {:error, reason} ->
        push(socket, "llm_error", %{
          operation: "set_preference",
          message: "Failed to set LLM preference",
          details: format_llm_error(reason)
        })
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_in("add_llm_model", %{"provider" => provider, "model" => model}, socket) do
    user_id = socket.assigns.user_id
    
    case UserConfig.add_model(user_id, String.to_atom(provider), model) do
      {:ok, config} ->
        push(socket, "llm_preference_set", %{
          provider: provider,
          model: model,
          is_default: false,
          config: %{
            id: config.id,
            usage_count: config.usage_count,
            created_at: config.created_at
          }
        })
        
      {:error, reason} ->
        push(socket, "llm_error", %{
          operation: "add_model",
          message: "Failed to add LLM model",
          details: format_llm_error(reason)
        })
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_in("get_llm_preferences", _params, socket) do
    user_id = socket.assigns.user_id
    
    case UserConfig.get_all_configs(user_id) do
      {:ok, configs} ->
        formatted_configs = Enum.map(configs, fn config ->
          %{
            id: config.id,
            provider: to_string(config.provider),
            model: config.model,
            is_default: config.is_default,
            usage_count: config.usage_count,
            created_at: config.created_at,
            updated_at: config.updated_at,
            metadata: config.metadata
          }
        end)
        
        push(socket, "llm_preferences", %{
          configs: formatted_configs,
          count: length(formatted_configs)
        })
        
      {:error, reason} ->
        push(socket, "llm_error", %{
          operation: "get_preferences",
          message: "Failed to get LLM preferences",
          details: format_llm_error(reason)
        })
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_in("get_llm_default", _params, socket) do
    user_id = socket.assigns.user_id
    
    case UserConfig.get_default(user_id) do
      {:ok, %{provider: provider, model: model}} ->
        push(socket, "llm_default", %{
          provider: to_string(provider),
          model: model,
          user_id: user_id
        })
        
      {:error, :not_found} ->
        push(socket, "llm_default", %{
          provider: nil,
          model: nil,
          user_id: user_id,
          message: "No default LLM configuration found"
        })
        
      {:error, reason} ->
        push(socket, "llm_error", %{
          operation: "get_default",
          message: "Failed to get default LLM configuration",
          details: format_llm_error(reason)
        })
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_in("remove_llm_provider", %{"provider" => provider}, socket) do
    user_id = socket.assigns.user_id
    
    case UserConfig.remove_provider(user_id, String.to_atom(provider)) do
      {:ok, removed_count} ->
        push(socket, "llm_provider_removed", %{
          provider: provider,
          removed_count: removed_count
        })
        
      {:error, reason} ->
        push(socket, "llm_error", %{
          operation: "remove_provider",
          message: "Failed to remove LLM provider",
          details: format_llm_error(reason)
        })
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def handle_in("get_llm_usage_stats", _params, socket) do
    user_id = socket.assigns.user_id
    
    case UserConfig.get_usage_stats(user_id) do
      {:ok, stats} ->
        push(socket, "llm_usage_stats", %{
          stats: stats,
          user_id: user_id
        })
        
      {:error, reason} ->
        push(socket, "llm_error", %{
          operation: "get_usage_stats",
          message: "Failed to get usage statistics",
          details: format_llm_error(reason)
        })
    end
    
    {:noreply, socket}
  end
  
  @impl true
  def terminate(_reason, socket) do
    # Clean up session context when channel terminates
    if Map.has_key?(socket.assigns, :session_id) do
      SessionContext.remove_context(socket.assigns.session_id)
    end
    
    :ok
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
    
    # Start with defaults and preferences
    config = defaults
    |> Map.merge(socket.assigns.preferences)
    |> Map.merge(Map.get(params, "llm_config", %{}))
    
    # Enhance with user's session context LLM config
    case SessionContext.get_llm_config(socket.assigns.session_id) do
      {:ok, %{provider: provider, model: model}} ->
        config
        |> Map.put(:provider, provider)
        |> Map.put(:model, model)
        |> Map.put(:user_id, socket.assigns.user_id)
      
      {:error, _} ->
        # Fall back to original config
        config
        |> Map.put(:user_id, socket.assigns.user_id)
    end
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
  
  defp format_llm_error(reason) do
    case reason do
      {:validation_error, field, message} ->
        "Validation error on #{field}: #{message}"
      {:invalid_provider, provider} ->
        "Invalid provider: #{provider}"
      {:invalid_model, model} ->
        "Invalid model: #{model}"
      {:user_not_found, user_id} ->
        "User not found: #{user_id}"
      {:database_error, details} ->
        "Database error: #{inspect(details)}"
      _ ->
        "Unknown error: #{inspect(reason)}"
    end
  end
end