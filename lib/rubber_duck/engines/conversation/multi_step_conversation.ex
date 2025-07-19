defmodule RubberDuck.Engines.Conversation.MultiStepConversation do
  @moduledoc """
  Engine for handling multi-step conversational processes that require
  maintaining context across multiple exchanges.

  This engine handles:
  - Follow-up questions
  - Step-by-step walkthroughs
  - Iterative problem solving
  - Context-aware responses

  It uses lightweight CoT chains for efficiency while maintaining context.
  """

  @behaviour RubberDuck.Engine

  require Logger

  alias RubberDuck.CoT.Manager, as: ConversationManager
  alias RubberDuck.CoT.Chains.LightweightConversationChain

  @impl true
  def init(config) do
    state = %{
      config: config,
      max_tokens: config[:max_tokens] || 1500,
      temperature: config[:temperature] || 0.5,
      model: config[:model] || "codellama",
      timeout: config[:timeout] || 30_000,
      chain_module: config[:chain_module] || LightweightConversationChain,
      max_context_messages: config[:max_context_messages] || 10
    }

    {:ok, state}
  end

  @impl true
  def execute(input, state) do
    with {:ok, validated} <- validate_input(input),
         {:ok, response} <- process_multi_step_query(validated, state) do
      result = %{
        query: validated.query,
        response: extract_response(response),
        conversation_type: :multi_step,
        step_number: calculate_step_number(validated.context),
        processing_time: extract_duration(response),
        metadata: %{
          model: state.model,
          temperature: state.temperature,
          max_tokens: state.max_tokens,
          context_messages: length(validated.context[:messages] || [])
        }
      }

      {:ok, result}
    end
  end

  @impl true
  def capabilities do
    [:multi_step_conversation, :context_aware, :follow_up_questions, :iterative_solving]
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

  defp process_multi_step_query(validated, state) do
    # Build CoT context with conversation history
    cot_context = build_cot_context(validated, state)

    Logger.info("Processing multi-step conversation query: #{String.slice(validated.query, 0, 50)}...")

    # Execute the lightweight CoT chain
    case ConversationManager.execute_chain(state.chain_module, validated.query, cot_context) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        Logger.error("Multi-step conversation engine error: #{inspect(reason)}")
        {:error, {:cot_error, reason}}
    end
  end

  defp build_cot_context(validated, state) do
    # Limit conversation history to prevent context overflow
    messages =
      case validated.context[:messages] do
        msgs when is_list(msgs) ->
          msgs
          |> Enum.take(-state.max_context_messages)
          |> format_messages_for_context()

        _ ->
          []
      end

    %{
      context:
        Map.merge(validated.context, %{
          conversation_type: :multi_step,
          messages: messages
        }),
      llm_config:
        Map.merge(
          %{
            model: state.model,
            temperature: state.temperature,
            max_tokens: state.max_tokens,
            timeout: state.timeout
          },
          validated.llm_config
        ),
      user_id: validated.context[:user_id],
      session_id: validated.context[:session_id] || generate_session_id()
    }
  end

  defp format_messages_for_context(messages) do
    Enum.map(messages, fn msg ->
      %{
        role: msg["role"] || msg[:role] || "user",
        content: msg["content"] || msg[:content] || ""
      }
    end)
  end

  defp calculate_step_number(context) do
    case context[:messages] do
      msgs when is_list(msgs) ->
        # Count user messages as steps
        Enum.count(msgs, fn msg ->
          (msg["role"] || msg[:role]) == "user"
        end) + 1

      _ ->
        1
    end
  end

  defp extract_response(response) when is_map(response) do
    response[:final_answer] || response["final_answer"] || "I couldn't generate a response."
  end

  defp extract_response(response) when is_binary(response), do: response
  defp extract_response(_), do: "I couldn't generate a response."

  defp extract_duration(response) when is_map(response) do
    response[:duration_ms] || response["duration_ms"] || 0
  end

  defp extract_duration(_), do: 0

  defp generate_session_id do
    "multi_step_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
end
