defmodule RubberDuck.Engines.Conversation.SimpleConversation do
  @moduledoc """
  Engine for handling simple conversational queries that don't require
  Chain-of-Thought reasoning.
  
  This engine handles:
  - Factual questions
  - Basic code explanations
  - Straightforward requests
  - Quick reference lookups
  
  It bypasses the CoT system for faster responses while maintaining
  quality for simple queries.
  """
  
  @behaviour RubberDuck.Engine
  
  require Logger
  
  alias RubberDuck.LLM.Service, as: LLMService
  
  @impl true
  def init(config) do
    state = %{
      config: config,
      max_tokens: config[:max_tokens] || 500,
      temperature: config[:temperature] || 0.3,
      model: config[:model] || "codellama",
      timeout: config[:timeout] || 10_000
    }
    
    {:ok, state}
  end
  
  @impl true
  def execute(input, state) do
    with {:ok, validated} <- validate_input(input),
         {:ok, response} <- process_simple_query(validated, state) do
      
      result = %{
        query: validated.query,
        response: response,
        conversation_type: :simple,
        processing_time: validated.start_time |> DateTime.diff(DateTime.utc_now(), :millisecond),
        metadata: %{
          model: state.model,
          temperature: state.temperature,
          max_tokens: state.max_tokens
        }
      }
      
      {:ok, result}
    end
  end
  
  @impl true
  def capabilities do
    [:simple_questions, :factual_queries, :basic_code, :quick_reference]
  end
  
  # Private functions
  
  defp validate_input(%{query: query} = input) when is_binary(query) do
    validated = %{
      query: String.trim(query),
      context: Map.get(input, :context, %{}),
      options: Map.get(input, :options, %{}),
      start_time: DateTime.utc_now()
    }
    
    {:ok, validated}
  end
  
  defp validate_input(_), do: {:error, :invalid_input}
  
  defp process_simple_query(validated, state) do
    # Build messages for LLM
    messages = build_messages(validated)
    
    # Prepare LLM request
    llm_opts = [
      model: state.model,
      messages: messages,
      temperature: state.temperature,
      max_tokens: state.max_tokens,
      timeout: state.timeout
    ]
    
    Logger.debug("Processing simple conversation query: #{String.slice(validated.query, 0, 50)}...")
    
    case LLMService.completion(llm_opts) do
      {:ok, response} ->
        content = extract_content(response)
        {:ok, content}
        
      {:error, reason} ->
        Logger.error("Simple conversation engine error: #{inspect(reason)}")
        {:error, {:llm_error, reason}}
    end
  end
  
  defp build_messages(validated) do
    system_message = build_system_message(validated.context)
    
    messages = [
      %{role: "system", content: system_message}
    ]
    
    # Add conversation history if available
    messages = case validated.context[:messages] do
      msgs when is_list(msgs) ->
        messages ++ format_conversation_history(msgs)
      _ ->
        messages
    end
    
    # Add the current query
    messages ++ [%{role: "user", content: validated.query}]
  end
  
  defp build_system_message(context) do
    base_prompt = """
    You are a helpful AI assistant focused on providing clear, concise answers.
    For simple questions, provide direct responses without unnecessary elaboration.
    For code questions, include brief examples when helpful.
    """
    
    # Add any additional context
    case context[:project_type] do
      nil -> base_prompt
      project_type -> base_prompt <> "\n\nProject context: #{project_type} application"
    end
  end
  
  defp format_conversation_history(messages) do
    messages
    |> Enum.take(-5)  # Only keep last 5 messages for context
    |> Enum.map(fn msg ->
      %{
        role: msg["role"] || msg[:role] || "user",
        content: msg["content"] || msg[:content] || ""
      }
    end)
  end
  
  defp extract_content(response) do
    cond do
      # Handle RubberDuck.LLM.Response struct
      is_struct(response, RubberDuck.LLM.Response) and is_list(response.choices) ->
        response.choices
        |> List.first()
        |> case do
          %{message: %{content: content}} when is_binary(content) -> 
            String.trim(content)
          %{message: %{"content" => content}} when is_binary(content) -> 
            String.trim(content)
          _ -> 
            "I couldn't generate a response."
        end
        
      # Handle plain maps
      is_map(response) and Map.has_key?(response, :choices) ->
        response.choices
        |> List.first()
        |> get_in([:message, :content])
        |> case do
          nil -> "I couldn't generate a response."
          content -> String.trim(content)
        end
        
      # Direct content
      is_binary(response) ->
        String.trim(response)
        
      true ->
        "I couldn't generate a response."
    end
  end
end