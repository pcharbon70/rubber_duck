defmodule RubberDuck.CoT.Executor do
  @moduledoc """
  Executes Chain-of-Thought reasoning steps sequentially.

  Handles step dependencies, retries, and intermediate result tracking.
  """

  require Logger

  alias RubberDuck.Engine.Manager, as: EngineManager
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
          {:ok, _new_visited, new_acc} ->
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

    # Get LLM config from session opts
    llm_config = session.opts[:llm_config] || %{}

    # Get engine name from session or use default
    engine_name = session.opts[:engine_name] || :simple_conversation

    # Execute with retries
    max_retries = Map.get(step, :retries, 2)
    execute_with_retries(prompt, step, context_opts, llm_config, engine_name, max_retries)
  end

  defp build_step_prompt(step, session, chain_config) do
    # Get the template
    template_type = Map.get(chain_config, :template, :default)
    base_template = Templates.get_template(template_type)

    # Get step prompt
    step_prompt = Map.get(step, :prompt, "")

    # Build context from previous steps
    previous_results = build_previous_results_context(session.steps)

    # Build variables map including step-specific results
    base_variables = %{
      "query" => session.query,
      "previous_result" => get_last_result(session.steps),
      "previous_results" => previous_results,
      "step_name" => Atom.to_string(step.name),
      "context" => Map.get(session, :context, %{})
    }

    # Add specific step results by name (e.g., {{understand_code_result}})
    step_results =
      Enum.reduce(session.steps, %{}, fn step_record, acc ->
        Map.put(acc, "#{step_record.name}_result", step_record.result)
      end)

    # Merge all variables, also include session opts for access to context
    variables =
      Map.merge(base_variables, step_results)
      |> Map.merge(session.opts || %{})

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
      # Handle different value types
      string_value =
        case value do
          v when is_binary(v) -> v
          v when is_map(v) -> Jason.encode!(v)
          v when is_list(v) and length(v) > 0 and is_binary(hd(v)) -> Enum.join(v, "\n")
          v -> inspect(v)
        end

      String.replace(acc, "{{#{key}}}", string_value)
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
    last_step = List.last(steps)

    if last_step && Map.has_key?(last_step, :result) do
      last_step.result
    else
      ""
    end
  end

  defp execute_with_retries(prompt, step, context_opts, llm_config, engine_name, retries_left) do
    # Build engine input
    engine_input = %{
      query: prompt,
      context:
        Map.merge(context_opts, %{
          step_name: step.name,
          chain_step: true,
          messages: [%{role: "user", content: prompt}]
        }),
      options: %{
        temperature: Map.get(step, :temperature, llm_config[:temperature] || 0.7),
        max_tokens: Map.get(step, :max_tokens, llm_config[:max_tokens] || 1000)
      },
      llm_config: llm_config
    }

    timeout = llm_config[:timeout] || 30_000

    case EngineManager.execute(engine_name, engine_input, timeout) do
      {:ok, response} ->
        # Extract result from engine response
        result = extract_engine_result(response)

        # Validate if needed
        case validate_step_result(result, step) do
          :ok ->
            {:ok, result}

          {:error, validation_error} when retries_left > 0 ->
            Logger.warning("Step validation failed, retrying: #{inspect(validation_error)}")
            # Add validation feedback to prompt
            enhanced_prompt =
              prompt <> "\n\nPrevious attempt failed validation: #{validation_error}\nPlease correct and try again."

            execute_with_retries(enhanced_prompt, step, context_opts, llm_config, engine_name, retries_left - 1)

          {:error, validation_error} ->
            {:error, {:validation_failed, validation_error}}
        end

      {:error, reason} when retries_left > 0 ->
        Logger.warning("Engine request failed, retrying: #{inspect(reason)}")
        # Brief delay before retry
        Process.sleep(1000)
        execute_with_retries(prompt, step, context_opts, llm_config, engine_name, retries_left - 1)

      {:error, reason} ->
        {:error, {:engine_request_failed, reason}}
    end
  end

  defp extract_engine_result(response) do
    # Handle responses from conversation engines
    cond do
      # Handle conversation engine response format
      is_map(response) and Map.has_key?(response, :response) ->
        response.response

      # Handle raw response
      is_binary(response) ->
        response

      # Handle other formats by delegating to extract_result
      true ->
        extract_result(response)
    end
  end

  defp extract_result(response) do
    # Extract the actual result from LLM response - handle RubberDuck.LLM.Response struct
    cond do
      # Handle RubberDuck.LLM.Response struct
      is_struct(response, RubberDuck.LLM.Response) and is_list(response.choices) ->
        response.choices
        |> List.first()
        |> case do
          %{message: %{content: content}} when is_binary(content) -> String.trim(content)
          %{message: %{"content" => content}} when is_binary(content) -> String.trim(content)
          _ -> ""
        end

      # Handle plain maps with choices
      is_map(response) and Map.has_key?(response, :choices) and is_list(response.choices) ->
        response.choices
        |> List.first()
        |> case do
          %{message: %{content: content}} -> String.trim(content)
          %{"message" => %{"content" => content}} -> String.trim(content)
          %{text: content} -> String.trim(content)
          %{"text" => content} -> String.trim(content)
          _ -> ""
        end

      # Direct content
      is_map(response) and Map.has_key?(response, :content) ->
        String.trim(response.content)

      # String response
      is_binary(response) ->
        String.trim(response)

      true ->
        ""
    end
  end

  defp validate_step_result(result, step) do
    # Get validation function names
    validators =
      case Map.get(step, :validates) do
        nil -> []
        atom when is_atom(atom) -> [atom]
        list when is_list(list) -> list
      end

    if Enum.empty?(validators) do
      :ok
    else
      # Get the chain module from the step
      chain_module = Map.get(step, :__chain_module__)

      # Run each validator
      Enum.reduce_while(validators, :ok, fn validator_name, _acc ->
        if chain_module && function_exported?(chain_module, validator_name, 1) do
          # Call the validation function with result in a map
          validation_context = %{result: result}

          if apply(chain_module, validator_name, [validation_context]) do
            {:cont, :ok}
          else
            {:halt, {:error, "Validation '#{validator_name}' failed"}}
          end
        else
          # No validation function found, skip this validator
          {:cont, :ok}
        end
      end)
    end
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
