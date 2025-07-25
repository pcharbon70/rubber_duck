defmodule RubberDuck.Engines.Conversation.ProblemSolver do
  @moduledoc """
  Engine specialized for debugging and problem-solving conversations.

  This engine handles:
  - Error analysis and debugging
  - Troubleshooting issues
  - Root cause analysis
  - Solution suggestions
  - Fix verification

  It uses the ProblemSolverChain for systematic problem analysis.
  """

  @behaviour RubberDuck.Engine

  require Logger

  alias RubberDuck.CoT.Manager, as: ConversationManager
  alias RubberDuck.CoT.Chains.ProblemSolverChain
  alias RubberDuck.Engine.InputValidator

  @impl true
  def init(config) do
    state = %{
      config: config,
      max_tokens: config[:max_tokens] || 2500,
      temperature: config[:temperature] || 0.4,
      # Remove hardcoded model - will come from input
      timeout: config[:timeout] || 60_000,
      chain_module: config[:chain_module] || ProblemSolverChain
    }

    {:ok, state}
  end

  @impl true
  def execute(input, state) do
    with {:ok, validated} <- validate_input(input),
         {:ok, response} <- solve_problem(validated, state) do
      result = %{
        query: validated.query,
        response: response.final_answer,
        conversation_type: :problem_solving,
        reasoning_steps: response.reasoning_steps,
        solution_steps: extract_solution_steps(response),
        root_cause: extract_root_cause(response),
        processing_time: response.duration_ms,
        metadata: %{
          provider: validated.provider,
          model: validated.model,
          temperature: validated.temperature || state.temperature,
          max_tokens: validated.max_tokens || state.max_tokens,
          total_steps: response.total_steps
        }
      }

      {:ok, result}
    end
  end

  @impl true
  def capabilities do
    [:debugging, :troubleshooting, :error_analysis, :root_cause_analysis, :solution_generation]
  end

  # Private functions

  defp validate_input(%{query: query} = input) when is_binary(query) do
    case InputValidator.validate_llm_input(input, [:query]) do
      {:ok, validated} ->
        validated = Map.merge(validated, %{
          query: String.trim(query),
          llm_config: Map.get(input, :llm_config, %{}),
          error_details: Map.get(input, :error_details, %{})
        })
        {:ok, validated}
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_input(_), do: {:error, :invalid_input}

  defp solve_problem(validated, state) do
    # Build CoT context with error information
    cot_context = build_cot_context(validated, state)

    Logger.info("Processing problem-solving query: #{String.slice(validated.query, 0, 50)}...")

    # Execute the problem solver chain
    case ConversationManager.execute_chain(state.chain_module, validated.query, cot_context) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        Logger.error("Problem solver engine error: #{inspect(reason)}")
        {:error, {:cot_error, reason}}
    end
  end

  defp build_cot_context(validated, state) do
    %{
      # Required LLM parameters
      provider: validated.provider,
      model: validated.model,
      user_id: validated.user_id,
      # Context
      context:
        Map.merge(validated.context, %{
          problem_type: detect_problem_type(validated.query),
          error_details: validated.error_details,
          conversation_type: :problem_solving
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

  defp detect_problem_type(query) do
    query_lower = String.downcase(query)

    cond do
      String.contains?(query_lower, ["compile", "compilation", "syntax"]) ->
        :compilation_error

      String.contains?(query_lower, ["runtime", "crash", "exception"]) ->
        :runtime_error

      String.contains?(query_lower, ["test", "failing", "assertion"]) ->
        :test_failure

      String.contains?(query_lower, ["performance", "slow", "timeout"]) ->
        :performance_issue

      String.contains?(query_lower, ["memory", "leak", "oom"]) ->
        :memory_issue

      true ->
        :general_problem
    end
  end

  defp extract_solution_steps(response) do
    # Extract solution steps from reasoning steps
    response.reasoning_steps
    |> Enum.filter(fn step ->
      step.name in [:propose_solutions, :implement_fix, :verify_solution]
    end)
    |> Enum.map(& &1.result)
  end

  defp extract_root_cause(response) do
    # Find the root cause analysis step
    response.reasoning_steps
    |> Enum.find(fn step ->
      step.name == :identify_root_cause
    end)
    |> case do
      nil -> "Root cause not identified"
      step -> step.result
    end
  end

  defp generate_session_id do
    "problem_solver_#{:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)}"
  end
end
