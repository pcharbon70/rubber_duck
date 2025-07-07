defmodule RubberDuck.CoT.Executor do
  @moduledoc """
  Executes Chain-of-Thought reasoning steps sequentially.

  Handles step dependencies, retries, and intermediate result tracking.
  """

  require Logger

  alias RubberDuck.LLM.Service, as: LLMService
  alias RubberDuck.CoT.Templates

  @doc """
  Executes a list of reasoning steps in order.
  """
  def execute_steps(steps, session, chain_config) do
    # Sort steps by dependencies
    sorted_steps = sort_steps_by_dependencies(steps)

    # Execute each step
    execute_steps_sequential(sorted_steps, session, chain_config)
  end

  # Private functions

  defp sort_steps_by_dependencies(steps) do
    # Build dependency graph
    graph = build_dependency_graph(steps)

    # Topological sort
    case topological_sort(graph, steps) do
      {:ok, sorted} ->
        sorted

      {:error, :circular_dependency} ->
        Logger.error("Circular dependency detected in reasoning chain")
        # Fall back to original order
        steps
    end
  end

  defp build_dependency_graph(steps) do
    Enum.reduce(steps, %{}, fn step, graph ->
      deps =
        case Map.get(step, :depends_on) do
          nil -> []
          atom when is_atom(atom) -> [atom]
          list when is_list(list) -> list
        end

      Map.put(graph, step.name, deps)
    end)
  end

  defp topological_sort(graph, steps) do
    # Simple topological sort implementation
    sorted = []
    visited = MapSet.new()
    temp_visited = MapSet.new()

    step_map = Map.new(steps, &{&1.name, &1})

    result =
      Enum.reduce_while(Map.keys(graph), {:ok, sorted}, fn node, {:ok, acc} ->
        case visit_node(node, graph, visited, temp_visited, acc, step_map) do
          {:ok, new_visited, new_acc} ->
            {:cont, {:ok, new_acc}}

          {:error, :circular_dependency} ->
            {:halt, {:error, :circular_dependency}}
        end
      end)

    case result do
      {:ok, sorted_names} ->
        sorted_steps = Enum.map(sorted_names, &Map.get(step_map, &1))
        {:ok, Enum.reverse(sorted_steps)}

      error ->
        error
    end
  end

  defp visit_node(node, graph, visited, temp_visited, sorted, step_map) do
    cond do
      MapSet.member?(visited, node) ->
        {:ok, visited, sorted}

      MapSet.member?(temp_visited, node) ->
        {:error, :circular_dependency}

      true ->
        temp_visited = MapSet.put(temp_visited, node)
        deps = Map.get(graph, node, [])

        result =
          Enum.reduce_while(deps, {:ok, visited, sorted}, fn dep, {:ok, vis, srt} ->
            case visit_node(dep, graph, vis, temp_visited, srt, step_map) do
              {:ok, new_vis, new_srt} ->
                {:cont, {:ok, new_vis, new_srt}}

              error ->
                {:halt, error}
            end
          end)

        case result do
          {:ok, new_visited, new_sorted} ->
            new_visited = MapSet.put(new_visited, node)
            new_sorted = [node | new_sorted]
            {:ok, new_visited, new_sorted}

          error ->
            error
        end
    end
  end

  defp execute_steps_sequential([], session, _chain_config) do
    # All steps completed
    final_result = build_final_result(session)
    {:ok, final_result, session}
  end

  defp execute_steps_sequential([step | remaining], session, chain_config) do
    Logger.info("Executing step: #{step.name}")

    # Check if step should be skipped
    if should_skip_step?(step, session) do
      Logger.info("Skipping optional step: #{step.name}")
      execute_steps_sequential(remaining, session, chain_config)
    else
      # Execute the step
      case execute_single_step(step, session, chain_config) do
        {:ok, step_result} ->
          # Update session with step result
          updated_session = add_step_result(session, step, step_result)

          # Continue with remaining steps
          execute_steps_sequential(remaining, updated_session, chain_config)

        {:error, reason} ->
          # Step failed
          Logger.error("Step #{step.name} failed: #{inspect(reason)}")
          {:error, {:step_failed, step.name, reason}, session}
      end
    end
  end

  defp should_skip_step?(step, _session) do
    # For now, only skip if explicitly marked as optional
    # In future, could add more complex logic
    Map.get(step, :optional, false)
  end

  defp execute_single_step(step, session, chain_config) do
    # Build the prompt
    prompt = build_step_prompt(step, session, chain_config)

    # Build context
    context_opts = [
      strategy: :long_context,
      max_tokens: Map.get(step, :max_tokens, 1000),
      user_id: Map.get(session.opts, :user_id),
      session_id: session.id
    ]

    # Execute with retries
    max_retries = Map.get(step, :retries, 2)
    execute_with_retries(prompt, step, context_opts, max_retries)
  end

  defp build_step_prompt(step, session, chain_config) do
    # Get the template
    template_type = Map.get(chain_config, :template, :default)
    base_template = Templates.get_template(template_type)

    # Get step prompt
    step_prompt = Map.get(step, :prompt, "")

    # Build context from previous steps
    previous_results = build_previous_results_context(session.steps)

    # Interpolate variables
    variables = %{
      "query" => session.query,
      "previous_result" => get_last_result(session.steps),
      "previous_results" => previous_results,
      "step_name" => Atom.to_string(step.name),
      "context" => Map.get(session, :context, %{})
    }

    # Combine base template with step prompt
    full_prompt = """
    #{base_template}

    Current Step: #{step.name}
    #{interpolate_template(step_prompt, variables)}
    """

    full_prompt
  end

  defp interpolate_template(template, variables) do
    Enum.reduce(variables, template, fn {key, value}, acc ->
      String.replace(acc, "{{#{key}}}", to_string(value))
    end)
  end

  defp build_previous_results_context(steps) do
    steps
    |> Enum.map(fn step ->
      "#{step.name}: #{step.result}"
    end)
    |> Enum.join("\n\n")
  end

  defp get_last_result([]), do: ""

  defp get_last_result(steps) do
    List.last(steps).result
  end

  defp execute_with_retries(prompt, step, context_opts, retries_left) do
    # Build LLM request
    request = %{
      # Could be configurable
      model: "gpt-4",
      messages: [
        %{role: "user", content: prompt}
      ],
      temperature: Map.get(step, :temperature, 0.7),
      max_tokens: Map.get(step, :max_tokens, 1000)
    }

    case LLMService.completion(request) do
      {:ok, response} ->
        result = extract_result(response)

        # Validate if needed
        case validate_step_result(result, step) do
          :ok ->
            {:ok, result}

          {:error, validation_error} when retries_left > 0 ->
            Logger.warning("Step validation failed, retrying: #{inspect(validation_error)}")
            # Add validation feedback to prompt
            enhanced_prompt =
              prompt <> "\n\nPrevious attempt failed validation: #{validation_error}\nPlease correct and try again."

            execute_with_retries(enhanced_prompt, step, context_opts, retries_left - 1)

          {:error, validation_error} ->
            {:error, {:validation_failed, validation_error}}
        end

      {:error, reason} when retries_left > 0 ->
        Logger.warning("LLM request failed, retrying: #{inspect(reason)}")
        # Brief delay before retry
        Process.sleep(1000)
        execute_with_retries(prompt, step, context_opts, retries_left - 1)

      {:error, reason} ->
        {:error, {:llm_request_failed, reason}}
    end
  end

  defp extract_result(response) do
    # Extract the actual result from LLM response
    case response do
      %{choices: [%{message: %{content: content}} | _]} ->
        String.trim(content)

      _ ->
        ""
    end
  end

  defp validate_step_result(result, step) do
    # Get validation rules
    validators =
      case Map.get(step, :validates) do
        nil -> []
        atom when is_atom(atom) -> [atom]
        list when is_list(list) -> list
      end

    # Run each validator
    Enum.reduce_while(validators, :ok, fn validator, _acc ->
      case apply_validator(validator, result) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp apply_validator(:has_problem_statement, result) do
    if String.contains?(result, ["problem", "issue", "question", "challenge"]) do
      :ok
    else
      {:error, "Result must contain a clear problem statement"}
    end
  end

  defp apply_validator(:has_solution, result) do
    if String.contains?(result, ["solution", "answer", "approach", "resolve"]) do
      :ok
    else
      {:error, "Result must contain a solution"}
    end
  end

  defp apply_validator(:has_code, result) do
    if Regex.match?(~r/```[\s\S]*?```/, result) do
      :ok
    else
      {:error, "Result must contain code blocks"}
    end
  end

  defp apply_validator(:has_explanation, result) do
    if String.length(result) > 100 do
      :ok
    else
      {:error, "Result must contain a detailed explanation"}
    end
  end

  defp apply_validator(validator, result) do
    Logger.warning("Unknown validator: #{validator}")
    :ok
  end

  defp add_step_result(session, step, result) do
    step_record = %{
      name: step.name,
      result: result,
      executed_at: DateTime.utc_now()
    }

    Map.update(session, :steps, [step_record], &(&1 ++ [step_record]))
  end

  defp build_final_result(session) do
    # Combine all step results into final result
    %{
      query: session.query,
      reasoning_steps: session.steps,
      final_answer: get_last_result(session.steps),
      total_steps: length(session.steps),
      duration_ms: calculate_duration(session)
    }
  end

  defp calculate_duration(session) do
    if session.started_at do
      DateTime.diff(DateTime.utc_now(), session.started_at, :millisecond)
    else
      0
    end
  end
end
