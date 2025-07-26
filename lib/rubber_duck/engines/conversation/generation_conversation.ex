defmodule RubberDuck.Engines.Conversation.GenerationConversation do
  @moduledoc """
  Engine for handling code generation conversations.

  This engine handles:
  - Code generation discussions
  - Implementation planning
  - API design conversations
  - Feature development
  - Code scaffolding

  It uses the GenerationChain for thoughtful code creation.
  """

  @behaviour RubberDuck.Engine

  require Logger

  alias RubberDuck.CoT.Manager, as: ConversationManager
  alias RubberDuck.CoT.Chains.GenerationChain
  alias RubberDuck.Engine.InputValidator

  @impl true
  def init(config) do
    state = %{
      config: config,
      max_tokens: config[:max_tokens] || 3000,
      temperature: config[:temperature] || 0.6,
      # Remove hardcoded model - will come from input
      timeout: config[:timeout] || 180_000,
      chain_module: config[:chain_module] || GenerationChain
    }

    {:ok, state}
  end

  @impl true
  def execute(input, state) do
    with {:ok, validated} <- validate_input(input),
         {:ok, response} <- generate_code_conversation(validated, state) do
      result = %{
        query: validated.query,
        response: response.final_answer,
        conversation_type: :generation,
        generated_code: extract_generated_code(response),
        implementation_plan: extract_implementation_plan(response),
        processing_time: response.duration_ms,
        metadata: %{
          provider: validated.provider,
          model: validated.model,
          temperature: validated.temperature || state.temperature,
          max_tokens: validated.max_tokens || state.max_tokens,
          generation_type: validated.generation_type
        }
      }

      {:ok, result}
    end
  end

  @impl true
  def capabilities do
    [:code_generation, :implementation_planning, :api_design, :feature_development, :scaffolding]
  end

  # Private functions

  defp validate_input(%{query: query} = input) when is_binary(query) do
    case InputValidator.validate_llm_input(input, [:query]) do
      {:ok, validated} ->
        validated = Map.merge(validated, %{
          query: String.trim(query),
          llm_config: Map.get(input, :llm_config, %{}),
          requirements: Map.get(input, :requirements, %{}),
          generation_type: detect_generation_type(query)
        })
        {:ok, validated}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_input(_), do: {:error, :invalid_input}

  defp generate_code_conversation(validated, state) do
    # Build CoT context with generation requirements
    cot_context = build_cot_context(validated, state)

    Logger.info("Processing generation conversation: #{String.slice(validated.query, 0, 50)}...")

    # Execute the generation chain
    case ConversationManager.execute_chain(state.chain_module, validated.query, cot_context) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        Logger.error("Generation conversation engine error: #{inspect(reason)}")
        {:error, {:cot_error, reason}}
    end
  end

  defp build_cot_context(validated, state) do
    %{
      # Required LLM parameters
      provider: validated.provider,
      model: validated.model,
      user_id: validated.user_id,
      # Pass through cancellation token if present
      cancellation_token: validated[:cancellation_token],
      # Context
      context:
        Map.merge(validated.context, %{
          generation_type: validated.generation_type,
          conversation_type: :generation,
          language: validated.context[:language] || "elixir",
          requirements: validated.requirements,
          existing_code: validated.context[:existing_code],
          project_structure: validated.context[:project_structure]
        }),
      llm_config:
        Map.merge(
          %{
            provider: validated.provider,
            model: validated.model,
            temperature: validated.temperature || state.temperature,
            max_tokens: validated.max_tokens || state.max_tokens,
            timeout: state.timeout
          },
          validated.llm_config
        ),
      session_id: validated.context[:session_id] || generate_session_id()
    }
  end

  defp detect_generation_type(query) do
    query_lower = String.downcase(query)

    cond do
      String.contains?(query_lower, ["function", "method", "def"]) ->
        :function

      String.contains?(query_lower, ["module", "class", "component"]) ->
        :module

      String.contains?(query_lower, ["api", "endpoint", "route"]) ->
        :api

      String.contains?(query_lower, ["test", "spec", "example"]) ->
        :test

      String.contains?(query_lower, ["scaffold", "boilerplate", "template"]) ->
        :scaffold

      String.contains?(query_lower, ["implement", "feature", "functionality"]) ->
        :feature

      true ->
        :general_generation
    end
  end

  defp extract_generated_code(response) do
    # Look for code blocks in the final answer
    response.final_answer
    |> extract_code_blocks()
    |> case do
      [] ->
        # Try to find code in reasoning steps
        response.reasoning_steps
        |> Enum.find(fn step ->
          step.name in [:generate_code, :implement_solution]
        end)
        |> case do
          nil -> nil
          step -> extract_code_blocks(step.result) |> List.first()
        end

      blocks ->
        blocks |> List.first()
    end
  end

  defp extract_implementation_plan(response) do
    response.reasoning_steps
    |> Enum.find(fn step ->
      step.name == :plan_implementation
    end)
    |> case do
      nil -> []
      step -> parse_plan_steps(step.result)
    end
  end

  defp extract_code_blocks(text) when is_binary(text) do
    ~r/```(?:\w+)?\n(.*?)```/s
    |> Regex.scan(text)
    |> Enum.map(fn [_, code] -> String.trim(code) end)
  end

  defp extract_code_blocks(_), do: []

  defp parse_plan_steps(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.filter(&String.match?(&1, ~r/^\d+\.|^-|^•|^Step/))
    |> Enum.map(&String.trim/1)
  end

  defp parse_plan_steps(_), do: []

  defp generate_session_id do
    "generation_conv_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
end
