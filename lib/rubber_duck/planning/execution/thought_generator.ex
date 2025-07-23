defmodule RubberDuck.Planning.Execution.ThoughtGenerator do
  @moduledoc """
  Generates thoughts for the ReAct execution framework.

  The ThoughtGenerator analyzes tasks and the current execution state
  to produce reasoning about what actions to take and how to approach
  task execution.
  """

  alias RubberDuck.Planning.Task
  alias RubberDuck.CoT

  require Logger

  @type thought :: %{
          task_id: String.t(),
          reasoning: String.t(),
          approach: atom(),
          considerations: [String.t()],
          dependencies_status: map(),
          confidence: float(),
          metadata: map()
        }

  @doc """
  Generates a thought about how to execute the given task.
  """
  @spec generate_thought(Task.t(), map()) :: thought()
  def generate_thought(%Task{} = task, execution_state) do
    Logger.debug("Generating thought for task #{task.id}")

    # Analyze task context
    context = build_task_context(task, execution_state)

    # Generate reasoning using CoT
    reasoning = generate_reasoning(task, context)

    # Determine approach based on reasoning
    approach = determine_approach(task, reasoning, context)

    # Build complete thought
    %{
      task_id: task.id,
      reasoning: reasoning,
      approach: approach,
      considerations: extract_considerations(reasoning),
      dependencies_status: analyze_dependencies(task, execution_state),
      confidence: calculate_confidence(task, reasoning, context),
      metadata: %{
        complexity: task.complexity,
        retry_count: get_retry_count(execution_state, task.id),
        generated_at: DateTime.utc_now()
      }
    }
  end

  defp build_task_context(task, execution_state) do
    %{
      task: task,
      completed_tasks: execution_state.completed_tasks,
      failed_tasks: execution_state.failed_tasks,
      current_tasks: execution_state.current_tasks,
      previous_attempts: get_previous_attempts(execution_state, task.id),
      available_resources: get_available_resources(execution_state),
      time_constraints: get_time_constraints(task, execution_state)
    }
  end

  defp generate_reasoning(task, context) do
    prompt = build_reasoning_prompt(task, context)

    case CoT.simple_reason(prompt, build_cot_options(task)) do
      {:ok, reasoning} ->
        reasoning

      {:error, error} ->
        Logger.error("Failed to generate reasoning: #{inspect(error)}")
        fallback_reasoning(task, context)
    end
  end

  defp build_reasoning_prompt(task, context) do
    """
    Analyze this task and determine the best approach for execution:

    Task: #{task.name}
    Description: #{task.description}
    Complexity: #{task.complexity}
    Dependencies: #{inspect(task.dependencies || [])}

    Context:
    - Completed tasks: #{MapSet.size(context.completed_tasks)}
    - Failed tasks: #{MapSet.size(context.failed_tasks)}
    - Currently executing: #{map_size(context.current_tasks)}
    - Previous attempts: #{length(context.previous_attempts)}

    Consider:
    1. What is the best approach to execute this task?
    2. What potential issues or challenges might arise?
    3. How should we handle failures or unexpected results?
    4. Are there any optimizations we can apply?

    Provide your reasoning and recommended approach.
    """
  end

  defp build_cot_options(task) do
    [
      model: determine_model_for_task(task),
      temperature: 0.3,
      max_tokens: 500
    ]
  end

  defp determine_model_for_task(%{complexity: :very_complex}), do: "gpt-4"
  defp determine_model_for_task(%{complexity: :complex}), do: "gpt-4"
  defp determine_model_for_task(_), do: "gpt-3.5-turbo"

  defp fallback_reasoning(task, context) do
    """
    Task analysis for #{task.name}:
    - Complexity: #{task.complexity}
    - Dependencies: #{length(task.dependencies || [])} tasks must complete first
    - Previous attempts: #{length(context.previous_attempts)}

    Approach: Execute task using standard workflow with monitoring.
    """
  end

  defp determine_approach(task, _reasoning, context) do
    cond do
      # Retry logic for previously failed tasks
      length(context.previous_attempts) > 0 ->
        determine_retry_approach(task, context)

      # Complex tasks need careful execution
      task.complexity in [:complex, :very_complex] ->
        :careful_execution

      # Tasks with many dependencies need validation
      length(task.dependencies || []) > 3 ->
        :validate_then_execute

      # Simple tasks can be executed directly
      task.complexity == :simple ->
        :direct_execution

      # Default approach
      true ->
        :standard_execution
    end
  end

  defp determine_retry_approach(_task, context) do
    last_attempt = List.first(context.previous_attempts)

    case last_attempt do
      %{failure_reason: :timeout} ->
        :execute_with_extended_timeout

      %{failure_reason: :resource_unavailable} ->
        :wait_and_retry

      %{failure_reason: :validation_failed} ->
        :fix_and_retry

      _ ->
        :retry_with_modifications
    end
  end

  defp extract_considerations(reasoning) do
    # Extract key considerations from the reasoning text
    # This is a simplified implementation
    reasoning
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, ["consider", "note", "important", "warning"]))
    |> Enum.map(&String.trim/1)
    |> Enum.take(5)
  end

  defp analyze_dependencies(task, execution_state) do
    case task.dependencies do
      nil ->
        %{}

      [] ->
        %{}

      deps ->
        Enum.reduce(deps, %{}, fn dep_id, acc ->
          status =
            cond do
              MapSet.member?(execution_state.completed_tasks, dep_id) -> :completed
              MapSet.member?(execution_state.failed_tasks, dep_id) -> :failed
              Map.has_key?(execution_state.current_tasks, dep_id) -> :in_progress
              true -> :pending
            end

          Map.put(acc, dep_id, status)
        end)
    end
  end

  defp calculate_confidence(task, reasoning, context) do
    # Calculate confidence based on various factors
    base_confidence = 0.8

    modifiers = [
      # Reduce confidence for complex tasks
      complexity_modifier(task.complexity),
      # Reduce confidence for previously failed tasks
      retry_modifier(context.previous_attempts),
      # Increase confidence if all dependencies completed
      dependency_modifier(task, context),
      # Adjust based on reasoning quality
      reasoning_quality_modifier(reasoning)
    ]

    confidence = Enum.reduce(modifiers, base_confidence, &(&1 + &2))
    min(1.0, max(0.0, confidence))
  end

  defp complexity_modifier(:simple), do: 0.1
  defp complexity_modifier(:medium), do: 0.0
  defp complexity_modifier(:complex), do: -0.1
  defp complexity_modifier(:very_complex), do: -0.2
  defp complexity_modifier(_), do: 0.0

  defp retry_modifier([]), do: 0.0

  defp retry_modifier(attempts) do
    -0.05 * min(length(attempts), 3)
  end

  defp dependency_modifier(%{dependencies: nil}, _), do: 0.05
  defp dependency_modifier(%{dependencies: []}, _), do: 0.05

  defp dependency_modifier(%{dependencies: deps}, context) do
    all_completed = Enum.all?(deps, &MapSet.member?(context.completed_tasks, &1))
    if all_completed, do: 0.1, else: -0.05
  end

  defp reasoning_quality_modifier(reasoning) do
    # Simple heuristic based on reasoning length and structure
    word_count = length(String.split(reasoning))

    cond do
      word_count < 20 -> -0.1
      word_count > 100 -> 0.05
      true -> 0.0
    end
  end

  defp get_retry_count(execution_state, task_id) do
    execution_state.history
    |> Map.get(:retries, %{})
    |> Map.get(task_id, 0)
  end

  defp get_previous_attempts(execution_state, task_id) do
    execution_state.history
    |> Map.get(:attempts, %{})
    |> Map.get(task_id, [])
  end

  defp get_available_resources(_execution_state) do
    # TODO: Implement resource tracking
    %{
      memory: :sufficient,
      cpu: :available,
      external_services: :online
    }
  end

  defp get_time_constraints(task, execution_state) do
    # TODO: Implement time constraint analysis
    %{
      deadline: task[:deadline],
      time_elapsed: calculate_time_elapsed(execution_state),
      estimated_remaining: estimate_remaining_time(task)
    }
  end

  defp calculate_time_elapsed(%{start_time: start}) when not is_nil(start) do
    DateTime.diff(DateTime.utc_now(), start, :second)
  end

  defp calculate_time_elapsed(_), do: 0

  defp estimate_remaining_time(task) do
    # Simple estimation based on complexity
    case task.complexity do
      # 1 minute
      :simple -> 60
      # 5 minutes
      :medium -> 300
      # 15 minutes
      :complex -> 900
      # 30 minutes
      :very_complex -> 1800
      _ -> 300
    end
  end
end
