defmodule RubberDuck.Commands.Handlers.Conversation do
  @moduledoc """
  Command handler for conversation management operations.
  
  Handles commands for creating, managing, and interacting with conversations
  including starting conversations, sending messages, and managing conversation context.
  """

  @behaviour RubberDuck.Commands.Handler

  alias RubberDuck.Conversations
  alias RubberDuck.Commands.Command

  @impl true
  def execute(%Command{name: :conversation, subcommand: :start, args: args, options: options, context: context}) do
    with :ok <- ensure_llm_connected(),
         {:ok, title} <- extract_title(args, options),
         {:ok, conversation_type} <- extract_type(options),
         {:ok, conversation} <- create_conversation(context, title, conversation_type),
         {:ok, context_record} <- create_conversation_context(conversation, conversation_type) do
      
      format_conversation_created(conversation, context_record, options[:format])
    else
      {:error, :no_llm_connected} ->
        {:error, "No LLM provider is connected. Please connect an LLM provider first using: llm connect <provider>"}
      {:error, :connection_manager_not_started} ->
        {:error, "LLM connection manager is not running. Please restart the server."}
      {:error, :connection_manager_not_available} ->
        {:error, "LLM connection manager is not available. Please check system configuration."}
      {:error, :connection_manager_timeout} ->
        {:error, "Connection manager timed out. The system may be overloaded."}
      {:error, reason} -> 
        {:error, "Failed to create conversation: #{reason}"}
    end
  end

  @impl true
  def execute(%Command{name: :conversation, subcommand: :list, context: context, format: format}) do
    try do
      # Handle context that might be wrapped in {:ok, context} tuple
      actual_context = case context do
        {:ok, ctx} -> ctx
        ctx -> ctx
      end
      
      conversations = Conversations.list_user_conversations!(%{user_id: actual_context.user_id})
      format_conversation_list(conversations, format)
    rescue
      error -> 
        {:error, "Failed to list conversations: #{inspect(error)}"}
    end
  end

  @impl true
  def execute(%Command{name: :conversation, subcommand: :show, args: [conversation_id | _], options: options}) do
    with {:ok, conversation} <- get_conversation(conversation_id),
         messages <- get_conversation_messages(conversation_id) do
      
      format_conversation_details(conversation, messages, options[:format])
    else
      {:error, reason} -> 
        {:error, "Failed to show conversation: #{reason}"}
    end
  end

  @impl true
  def execute(%Command{name: :conversation, subcommand: :send, args: args, options: options, context: context}) do
    with :ok <- ensure_llm_connected(),
         {:ok, conversation_id} <- extract_conversation_id(options),
         {:ok, message_content} <- extract_message_content(args),
         {:ok, conversation} <- get_conversation(conversation_id),
         {:ok, user_message} <- create_user_message(conversation_id, message_content),
         {:ok, assistant_response} <- generate_assistant_response(conversation, user_message, context) do
      
      format_conversation_exchange(user_message, assistant_response, options[:format])
    else
      {:error, :no_llm_connected} ->
        {:error, "No LLM provider is connected. Please connect an LLM provider first using: llm connect <provider>"}
      {:error, :connection_manager_not_started} ->
        {:error, "LLM connection manager is not running. Please restart the server."}
      {:error, :connection_manager_not_available} ->
        {:error, "LLM connection manager is not available. Please check system configuration."}
      {:error, :connection_manager_timeout} ->
        {:error, "Connection manager timed out. The system may be overloaded."}
      {:error, :llm_service_not_started} ->
        {:error, "LLM service is not running. Please restart the server."}
      {:error, :llm_service_not_available} ->
        {:error, "LLM service is not available. Please check system configuration."}
      {:error, :llm_service_timeout} ->
        {:error, "LLM service timed out. The system may be overloaded."}
      {:error, reason} -> 
        {:error, "Failed to send message: #{reason}"}
    end
  end

  @impl true
  def execute(%Command{name: :conversation, subcommand: :delete, args: [conversation_id | _]}) do
    with {:ok, conversation} <- get_conversation(conversation_id),
         {:ok, _deleted} <- Conversations.delete_conversation(conversation) do
      
      {:ok, "Conversation deleted successfully"}
    else
      {:error, reason} -> 
        {:error, "Failed to delete conversation: #{reason}"}
    end
  end

  @impl true
  def execute(%Command{name: :conversation}) do
    {:error, "Unknown conversation subcommand. Available: start, list, show, send, delete"}
  end

  # Private helper functions

  defp ensure_llm_connected do
    # Check if ConnectionManager process is running
    case Process.whereis(RubberDuck.LLM.ConnectionManager) do
      nil -> 
        {:error, :connection_manager_not_started}
      
      _pid ->
        # ConnectionManager is running, check status with timeout handling
        try do
          case RubberDuck.LLM.ConnectionManager.status() do
            connections when is_map(connections) ->
              # Check if any provider is connected and healthy
              connected? = Enum.any?(connections, fn {_provider, info} ->
                info.status == :connected && info.health in [:ok, :healthy]
              end)
              
              if connected?, do: :ok, else: {:error, :no_llm_connected}
              
            _ ->
              {:error, :no_llm_connected}
          end
        catch
          :exit, {:noproc, _} -> 
            {:error, :connection_manager_not_available}
          :exit, {:timeout, _} -> 
            {:error, :connection_manager_timeout}
        end
    end
  end

  defp extract_title(args, options) do
    # Try to get title from options first, then from args
    cond do
      options[:title] && is_binary(options[:title]) -> 
        {:ok, options[:title]}
      
      is_map(args) && args[:title] && is_binary(args[:title]) ->
        {:ok, args[:title]}
      
      is_list(args) && length(args) > 0 ->
        case List.first(args) do
          title when is_binary(title) -> {:ok, title}
          _ -> {:ok, "New Conversation"}
        end
      
      true -> 
        {:ok, "New Conversation"}
    end
  end

  defp extract_type(options) do
    case options[:type] do
      nil -> {:ok, :general}
      type when type in ["general", "coding", "debugging", "planning", "review"] ->
        {:ok, String.to_atom(type)}
      type when is_atom(type) and type in [:general, :coding, :debugging, :planning, :review] ->
        {:ok, type}
      _ -> {:error, "Invalid conversation type. Must be one of: general, coding, debugging, planning, review"}
    end
  end

  defp create_conversation(context, title, conversation_type) do
    # Handle context that might be wrapped in {:ok, context} tuple
    actual_context = case context do
      {:ok, ctx} -> ctx
      ctx -> ctx
    end
    
    conversation_params = %{
      user_id: actual_context.user_id,
      project_id: actual_context.project_id,
      title: title,
      status: :active,
      metadata: %{
        created_via: "command",
        conversation_type: conversation_type,
        session_id: actual_context.session_id
      }
    }

    Conversations.create_conversation(conversation_params)
  end

  defp create_conversation_context(conversation, conversation_type) do
    context_params = %{
      conversation_id: conversation.id,
      conversation_type: conversation_type,
      context_window_size: get_context_window_size(conversation_type),
      llm_preferences: get_default_llm_preferences(conversation_type)
    }

    Conversations.create_context(context_params)
  end

  defp get_context_window_size(:coding), do: 8000
  defp get_context_window_size(:debugging), do: 6000
  defp get_context_window_size(:planning), do: 12000
  defp get_context_window_size(:review), do: 4000
  defp get_context_window_size(_), do: 4000

  defp get_default_llm_preferences(:coding) do
    %{
      temperature: 0.2,
      preferred_provider: "ollama",
      preferred_model: "codellama"
    }
  end

  defp get_default_llm_preferences(:debugging) do
    %{
      temperature: 0.1,
      preferred_provider: "anthropic",
      preferred_model: "claude-3-sonnet"
    }
  end

  defp get_default_llm_preferences(:planning) do
    %{
      temperature: 0.7,
      preferred_provider: "anthropic",
      preferred_model: "claude-3-opus"
    }
  end

  defp get_default_llm_preferences(_) do
    %{
      temperature: 0.5,
      preferred_provider: "ollama",
      preferred_model: "codellama"
    }
  end

  defp get_conversation(conversation_id) do
    try do
      conversation = Conversations.get_conversation!(conversation_id)
      {:ok, conversation}
    rescue
      Ash.Error.Query.NotFound -> {:error, "Conversation not found"}
      error -> {:error, "Failed to get conversation: #{inspect(error)}"}
    end
  end

  defp get_conversation_messages(conversation_id) do
    try do
      Conversations.list_conversation_messages!(conversation_id: conversation_id)
    rescue
      _error -> []
    end
  end

  defp extract_conversation_id(options) do
    case options[:conversation] || options[:id] do
      nil -> {:error, "No conversation ID provided"}
      id when is_binary(id) -> {:ok, id}
      _ -> {:error, "Invalid conversation ID format"}
    end
  end

  defp extract_message_content([]), do: {:error, "No message content provided"}
  defp extract_message_content(args) when is_list(args) do
    content = Enum.join(args, " ")
    if String.trim(content) == "" do
      {:error, "Message content cannot be empty"}
    else
      {:ok, content}
    end
  end

  defp create_user_message(conversation_id, content) do
    # Get message count for sequence number
    messages = get_conversation_messages(conversation_id)
    sequence_number = length(messages) + 1

    message_params = %{
      conversation_id: conversation_id,
      role: :user,
      content: content,
      sequence_number: sequence_number
    }

    Conversations.create_message(message_params)
  end

  defp generate_assistant_response(conversation, user_message, command_context) do
    # Get conversation history for context
    messages = get_conversation_messages(conversation.id)
    conversation_context = get_conversation_context(conversation.id)
    
    # Build conversation history as formatted messages for LLM
    history_messages = messages
    |> Enum.sort_by(& &1.sequence_number)
    |> Enum.take(-10)  # Last 10 messages for context
    |> Enum.map(fn msg ->
      %{role: String.to_atom(to_string(msg.role)), content: msg.content}
    end)
    
    # Add the current user message to the history
    all_messages = history_messages ++ [%{role: :user, content: user_message.content}]
    
    # Determine optimal model based on message analysis
    {model, temperature} = select_optimal_model_for_message(user_message, conversation_context)
    
    # Build LLM options
    llm_options = [
      model: model,
      messages: all_messages,
      temperature: temperature,
      max_tokens: get_max_tokens_for_context(conversation_context),
      timeout: 120_000,
      # Include conversation context for CoT if needed
      conversation_history: format_conversation_history(messages),
      conversation_type: conversation_context && conversation_context.conversation_type,
      user_preferences: conversation_context && conversation_context.llm_preferences || %{}
    ]
    
    # Use LLM Service which will intelligently decide whether to use CoT
    case RubberDuck.LLM.Service.completion(llm_options) do
      {:ok, response} ->
        # Extract response content
        response_content = extract_llm_response(response)
        
        # Create assistant message with the response
        sequence_number = length(messages) + 2 # +1 for user message, +1 for this response
        
        assistant_params = %{
          conversation_id: conversation.id,
          role: :assistant,
          content: response_content,
          sequence_number: sequence_number,
          model_used: model,
          provider_used: get_provider_from_response(response),
          tokens_used: get_tokens_from_response(response),
          generation_time_ms: get_duration_from_response(response),
          metadata: %{
            used_cot: was_cot_used(response),
            temperature: temperature
          }
        }
        
        Conversations.create_message(assistant_params)
        
      {:error, reason} ->
        # Handle errors
        case reason do
          :timeout ->
            {:error, "Request timed out. Please try again with a simpler question."}
          :model_required ->
            {:error, "No model configured. Please set a model using: llm set_model <model>"}
          _ ->
            {:error, "Failed to generate response: #{inspect(reason)}"}
        end
    end
  end
  
  defp format_conversation_history(messages) do
    messages
    |> Enum.sort_by(& &1.sequence_number)
    |> Enum.take(-10)  # Last 10 messages for context
    |> Enum.map(fn msg ->
      "#{msg.role}: #{msg.content}"
    end)
    |> Enum.join("\n")
  end
  
  defp extract_llm_response(response) do
    cond do
      # Handle LLM.Response struct
      is_struct(response, RubberDuck.LLM.Response) and is_list(response.choices) ->
        response.choices
        |> List.first()
        |> case do
          # Handle both atom and string keys
          %{message: %{content: content}} when is_binary(content) -> 
            String.trim(content)
          %{message: %{"content" => content}} when is_binary(content) -> 
            String.trim(content)
          %{"message" => %{"content" => content}} when is_binary(content) -> 
            String.trim(content)
          _ -> 
            "I apologize, but I couldn't generate a response."
        end
        
      # Handle plain map response
      is_map(response) and Map.has_key?(response, :content) ->
        String.trim(response.content)
        
      # Handle plain map with string key
      is_map(response) and Map.has_key?(response, "content") ->
        String.trim(response["content"])
        
      # Handle string response
      is_binary(response) ->
        String.trim(response)
        
      true ->
        "I apologize, but I couldn't generate a response."
    end
  end
  
  defp get_provider_from_response(response) do
    cond do
      is_struct(response, RubberDuck.LLM.Response) ->
        response.provider || "unknown"
      is_map(response) && Map.has_key?(response, :provider) ->
        response.provider
      true ->
        "unknown"
    end
  end
  
  defp get_tokens_from_response(response) do
    cond do
      is_struct(response, RubberDuck.LLM.Response) && is_map(response.usage) ->
        response.usage.total_tokens
      is_map(response) && is_map(Map.get(response, :usage)) ->
        response.usage.total_tokens
      true ->
        nil
    end
  end
  
  defp get_duration_from_response(response) do
    cond do
      is_struct(response, RubberDuck.LLM.Response) && is_map(response.metadata) && Map.has_key?(response.metadata, :reasoning_time) ->
        response.metadata.reasoning_time
      is_struct(response, RubberDuck.LLM.Response) && Map.has_key?(response, :processing_time_ms) ->
        Map.get(response, :processing_time_ms)
      is_map(response) && Map.has_key?(response, :processing_time_ms) ->
        response.processing_time_ms
      true ->
        nil
    end
  end
  
  defp was_cot_used(response) do
    cond do
      is_struct(response, RubberDuck.LLM.Response) && is_map(response.metadata) ->
        Map.get(response.metadata, :used_cot, false)
      is_map(response) && is_map(Map.get(response, :metadata)) ->
        get_in(response, [:metadata, :used_cot]) || false
      true ->
        false
    end
  end

  defp get_conversation_context(conversation_id) do
    try do
      Conversations.get_conversation_context!(conversation_id: conversation_id)
    rescue
      _error -> nil
    end
  end


  defp get_conversation_model(nil), do: "codellama"
  defp get_conversation_model(context) do
    context.llm_preferences["preferred_model"] || "codellama"
  end

  defp get_conversation_temperature(nil), do: 0.5
  defp get_conversation_temperature(context) do
    context.llm_preferences["temperature"] || 0.5
  end

  # Intelligent model selection based on message content and keywords
  defp select_optimal_model_for_message(message, conversation_context) do
    content = message.content
    base_model = get_conversation_model(conversation_context)
    base_temp = get_conversation_temperature(conversation_context)
    
    # Analyze message content for keywords and patterns
    analysis = analyze_message_content(content)
    
    # Select model and temperature based on analysis
    case determine_message_intent(analysis) do
      :code_generation ->
        {"codellama", 0.2}  # Low temperature for precise code
        
      :debugging ->
        {"claude-3-sonnet", 0.1}  # Very low temperature for logical debugging
        
      :code_review ->
        {"claude-3-sonnet", 0.3}  # Moderate temperature for thorough analysis
        
      :architecture_design ->
        {"claude-3-opus", 0.7}  # Higher temperature for creative solutions
        
      :explanation ->
        {base_model, 0.6}  # Moderate-high temperature for clear explanations
        
      :problem_solving ->
        {"claude-3-sonnet", 0.4}  # Balanced temperature for structured thinking
        
      :refactoring ->
        {"codellama", 0.3}  # Code-focused with some flexibility
        
      :testing ->
        {"codellama", 0.2}  # Precise test generation
        
      :documentation ->
        {base_model, 0.5}  # Balanced for clear documentation
        
      _ ->
        {base_model, base_temp}  # Fallback to conversation defaults
    end
  end

  # Analyze message content for programming-related keywords and patterns
  defp analyze_message_content(content) do
    content_lower = String.downcase(content)
    
    %{
      # Code generation indicators
      has_generate_keywords: contains_any?(content_lower, [
        "write", "create", "generate", "build", "implement", "make"
      ]),
      
      # Debugging indicators  
      has_debug_keywords: contains_any?(content_lower, [
        "debug", "fix", "error", "bug", "issue", "problem", "crash", "fail"
      ]),
      
      # Review indicators
      has_review_keywords: contains_any?(content_lower, [
        "review", "check", "improve", "optimize", "better", "best practice"
      ]),
      
      # Architecture indicators
      has_architecture_keywords: contains_any?(content_lower, [
        "design", "architecture", "pattern", "structure", "organize", "approach"
      ]),
      
      # Explanation indicators
      has_explanation_keywords: contains_any?(content_lower, [
        "explain", "how", "what", "why", "understand", "clarify", "describe"
      ]),
      
      # Testing indicators
      has_test_keywords: contains_any?(content_lower, [
        "test", "spec", "unit", "integration", "mock", "assert"
      ]),
      
      # Refactoring indicators
      has_refactor_keywords: contains_any?(content_lower, [
        "refactor", "clean", "reorganize", "restructure", "simplify"
      ]),
      
      # Documentation indicators
      has_docs_keywords: contains_any?(content_lower, [
        "document", "comment", "readme", "guide", "manual", "docs"
      ]),
      
      # Code presence
      has_code_blocks: String.contains?(content, "```") or String.contains?(content, "`"),
      has_file_paths: String.contains?(content, "/") or String.contains?(content, ".ex"),
      has_function_names: Regex.match?(~r/\w+\(.*\)/, content)
    }
  end

  # Determine the primary intent of the message based on keyword analysis
  defp determine_message_intent(analysis) do
    cond do
      analysis.has_debug_keywords and (analysis.has_code_blocks or analysis.has_function_names) ->
        :debugging
        
      analysis.has_generate_keywords and analysis.has_code_blocks ->
        :code_generation
        
      analysis.has_test_keywords ->
        :testing
        
      analysis.has_refactor_keywords and analysis.has_code_blocks ->
        :refactoring
        
      analysis.has_review_keywords and analysis.has_code_blocks ->
        :code_review
        
      analysis.has_architecture_keywords ->
        :architecture_design
        
      analysis.has_docs_keywords ->
        :documentation
        
      analysis.has_explanation_keywords ->
        :explanation
        
      analysis.has_code_blocks or analysis.has_function_names ->
        :problem_solving
        
      true ->
        :general
    end
  end

  # Helper function to check if content contains any of the given keywords
  defp contains_any?(content, keywords) do
    Enum.any?(keywords, fn keyword -> String.contains?(content, keyword) end)
  end


  defp get_max_tokens_for_context(nil), do: 4096
  defp get_max_tokens_for_context(context) do
    # Reserve some tokens for the prompt and context
    max(context.context_window_size - 1000, 1000)
  end

  # Formatting functions

  defp format_conversation_created(conversation, context, :json) do
    {:ok, %{
      conversation: %{
        id: conversation.id,
        title: conversation.title,
        type: context.conversation_type,
        created_at: conversation.inserted_at
      }
    }}
  end

  defp format_conversation_created(conversation, context, _format) do
    {:ok, """
    Conversation created successfully!
    
    ID: #{conversation.id}
    Title: #{conversation.title}
    Type: #{context.conversation_type}
    Created: #{conversation.inserted_at}
    
    Use 'conversation send --conversation #{conversation.id} <message>' to start chatting.
    """}
  end

  defp format_conversation_list([], _format) do
    {:ok, "No conversations found."}
  end

  defp format_conversation_list(conversations, :json) when is_list(conversations) do
    conversation_data = Enum.map(conversations, fn conv ->
      %{
        id: conv.id,
        title: conv.title,
        status: conv.status,
        message_count: conv.message_count,
        last_activity: conv.last_activity_at,
        created_at: conv.inserted_at
      }
    end)
    
    {:ok, %{conversations: conversation_data}}
  end

  defp format_conversation_list(conversations, _format) do
    formatted = conversations
    |> Enum.map(fn conv ->
      activity = if conv.last_activity_at do
        "#{format_relative_time(conv.last_activity_at)}"
      else
        "No activity"
      end
      
      "  #{conv.id} - #{conv.title} (#{conv.message_count} messages, #{activity})"
    end)
    |> Enum.join("\n")
    
    {:ok, "Conversations:\n#{formatted}"}
  end

  defp format_conversation_details(conversation, messages, :json) do
    message_data = Enum.map(messages, fn msg ->
      %{
        id: msg.id,
        role: msg.role,
        content: msg.content,
        sequence_number: msg.sequence_number,
        created_at: msg.inserted_at
      }
    end)
    
    {:ok, %{
      conversation: %{
        id: conversation.id,
        title: conversation.title,
        status: conversation.status,
        message_count: conversation.message_count
      },
      messages: message_data
    }}
  end

  defp format_conversation_details(conversation, messages, _format) do
    header = "Conversation: #{conversation.title}\nID: #{conversation.id}\n"
    
    formatted_messages = messages
    |> Enum.sort_by(& &1.sequence_number)
    |> Enum.map(fn msg ->
      role_icon = case msg.role do
        :user -> "👤"
        :assistant -> "🤖"
        :system -> "⚙️"
        _ -> "•"
      end
      
      "#{role_icon} #{String.capitalize(to_string(msg.role))}: #{msg.content}"
    end)
    |> Enum.join("\n\n")
    
    {:ok, "#{header}\n#{formatted_messages}"}
  end

  defp format_conversation_exchange(user_message, assistant_message, :json) do
    {:ok, %{
      user_message: %{
        content: user_message.content,
        created_at: user_message.inserted_at
      },
      assistant_message: %{
        content: assistant_message.content,
        model: assistant_message.model_used,
        tokens_used: assistant_message.tokens_used,
        created_at: assistant_message.inserted_at
      }
    }}
  end

  defp format_conversation_exchange(user_message, assistant_message, _format) do
    {:ok, """
    👤 You: #{user_message.content}
    
    🤖 Assistant: #{assistant_message.content}
    """}
  end

  defp format_relative_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)
    
    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end
end