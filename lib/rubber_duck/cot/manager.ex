defmodule RubberDuck.CoT.Manager do
  @moduledoc """
  Manager for executing Chain-of-Thought reasoning chains.

  Coordinates the execution of reasoning chains, managing step execution,
  validation, and result collection.
  """

  alias RubberDuck.LLM.Service
  alias RubberDuck.Engine.CancellationToken
  alias RubberDuck.Status
  require Logger

  @doc """
  Executes a reasoning chain with the given query and context.

  ## Parameters

    * `chain_module` - The chain module implementing ChainBehaviour
    * `query` - The main query or prompt
    * `context` - Additional context for the chain

  ## Returns

    * `{:ok, session}` - Successfully completed chain execution
    * `{:error, reason}` - Chain execution failed
  """
  def execute_chain(chain_module, query, context \\ %{}) do
    with {:ok, config} <- get_chain_config(chain_module),
         {:ok, steps} <- get_chain_steps(chain_module) do
      # Extract cancellation token from context
      cancellation_token = CancellationToken.from_input(context)
      
      # Check if already cancelled before starting
      if cancellation_token && CancellationToken.cancelled?(cancellation_token) do
        {:error, :cancelled}
      else
        # Initialize session
        session = %{
          chain: chain_module,
          config: config,
          query: query,
          context: context,
          steps: %{},
          started_at: DateTime.utc_now(),
          status: :running,
          cancellation_token: cancellation_token
        }

        # Execute steps
        case execute_steps(steps, session) do
          {:ok, completed_session} ->
            final_session =
              completed_session
              |> Map.put(:status, :completed)
              |> Map.put(:completed_at, DateTime.utc_now())

            # Build the result structure expected by engines
            final_result = build_final_result(final_session)
            
            {:ok, final_result}

          {:error, :cancelled, _partial_session} ->
            # Clean cancellation error
            {:error, :cancelled}

          {:error, reason, _partial_session} ->
            # Return simple error without trying to modify session
            {:error, reason}

          {:error, reason} ->
            # Handle case where execute_steps returns 2-tuple error
            {:error, reason}
        end
      end
    end
  end

  @doc """
  Executes a single step from a chain.
  """
  def execute_step(step_name, chain_module, session) do
    with {:ok, steps} <- get_chain_steps(chain_module),
         {:ok, step} <- find_step(steps, step_name) do
      execute_single_step(step, session)
    end
  end

  # Private functions

  defp get_chain_config(chain_module) do
    Logger.debug("Checking chain module: #{inspect(chain_module)}")
    
    if function_exported?(chain_module, :config, 0) do
      Logger.debug("Chain module #{inspect(chain_module)} has config/0")
      {:ok, chain_module.config()}
    else
      Logger.error("Chain module #{inspect(chain_module)} missing config/0. Exported functions: #{inspect(chain_module.__info__(:functions))}")
      {:error, "Chain module must implement config/0"}
    end
  end

  defp get_chain_steps(chain_module) do
    if function_exported?(chain_module, :steps, 0) do
      {:ok, chain_module.steps()}
    else
      {:error, "Chain module must implement steps/0"}
    end
  end

  defp execute_steps(steps, session) do
    Enum.reduce_while(steps, {:ok, session}, fn step, {:ok, current_session} ->
      # Check cancellation before each step
      if current_session.cancellation_token && CancellationToken.cancelled?(current_session.cancellation_token) do
        Logger.info("Chain execution cancelled before step #{step.name}")
        
        # Broadcast cancellation if we have a conversation_id
        conversation_id = get_in(current_session, [:context, :conversation_id])
        if conversation_id do
          Status.workflow(
            conversation_id,
            "Chain execution cancelled at step #{step.name}",
            %{
              chain: inspect(current_session.chain),
              step: step.name,
              cancelled_at: DateTime.utc_now()
            }
          )
        end
        
        {:halt, {:error, :cancelled, current_session}}
      else
        case execute_single_step(step, current_session) do
          {:ok, result} ->
            updated_session = update_session_with_result(current_session, step, result)
            {:cont, {:ok, updated_session}}

          {:error, :cancelled} ->
            Logger.info("Step #{step.name} was cancelled")
            {:halt, {:error, :cancelled, current_session}}

          {:error, reason} ->
            Logger.error("Step #{step.name} failed: #{inspect(reason)}")
            {:halt, {:error, reason, current_session}}
        end
      end
    end)
  end

  defp execute_single_step(step, session) do
    # Check dependencies
    with :ok <- check_dependencies(step, session),
         # Build prompt with variable substitution
         {:ok, prompt} <- build_prompt(step.prompt, session),
         # Execute LLM call
         {:ok, result} <- call_llm(prompt, step, session),
         # Validate result
         :ok <- validate_result(step, result, session) do
      {:ok, result}
    end
  end

  defp check_dependencies(%{depends_on: nil}, _session), do: :ok

  defp check_dependencies(%{depends_on: deps}, session) when is_list(deps) do
    missing = Enum.filter(deps, fn dep -> not Map.has_key?(session.steps, dep) end)

    case missing do
      [] -> :ok
      _ -> {:error, "Missing dependencies: #{inspect(missing)}"}
    end
  end

  defp check_dependencies(%{depends_on: dep}, session) do
    if Map.has_key?(session.steps, dep) do
      :ok
    else
      {:error, "Missing dependency: #{dep}"}
    end
  end

  defp check_dependencies(_, _), do: :ok

  defp build_prompt(prompt_template, session) do
    # Replace variables in prompt template
    prompt =
      prompt_template
      |> replace_variable("{{query}}", session.query)
      |> replace_variable("{{context}}", format_context(session.context))
      |> replace_previous_results(session)
      |> replace_context_variables(session.context)

    {:ok, prompt}
  end

  defp replace_variable(template, pattern, value) when is_binary(value) do
    String.replace(template, pattern, value)
  end

  defp replace_variable(template, pattern, value) do
    String.replace(template, pattern, inspect(value))
  end

  defp replace_previous_results(template, session) do
    # Replace {{previous_result}} with the last step's result
    case get_last_result(session) do
      nil -> template
      result -> replace_variable(template, "{{previous_result}}", result)
    end
    |> replace_named_results(session)
  end

  defp replace_named_results(template, session) do
    # Replace {{step_name_result}} patterns
    Regex.replace(~r/{{(\w+)_result}}/, template, fn _, step_name ->
      atom_key = String.to_existing_atom(step_name)

      case Map.get(session.steps, atom_key) do
        %{result: result} -> result
        _ -> ""
      end
    end)
  end

  defp replace_context_variables(template, context) when is_map(context) do
    # Replace any {{variable}} from context
    Enum.reduce(context, template, fn {key, value}, acc ->
      pattern = "{{#{key}}}"
      replace_variable(acc, pattern, value)
    end)
  end

  defp replace_context_variables(template, _), do: template

  defp format_context(context) when is_map(context) do
    context
    |> Enum.map(fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> Enum.join("\n")
  end

  defp format_context(context), do: inspect(context)

  defp get_last_result(session) do
    session.steps
    |> Map.values()
    |> Enum.sort_by(& &1.executed_at)
    |> List.last()
    |> case do
      %{result: result} -> result
      _ -> nil
    end
  end

  defp call_llm(prompt, step, session) do
    # Check cancellation before making LLM call
    if session.cancellation_token && CancellationToken.cancelled?(session.cancellation_token) do
      {:error, :cancelled}
    else
      # Get LLM config from context
      llm_config = get_in(session, [:context, :llm_config]) || %{}
      
      # Require provider and model from context
      provider = Map.get(session.context, :provider) || Map.get(llm_config, :provider)
      model = Map.get(session.context, :model) || Map.get(llm_config, :model)
      
      if is_nil(provider) or is_nil(model) do
        {:error, {:missing_llm_config, "Provider and model must be specified in context"}}
      else
        options = %{
          provider: provider,  # Required
          model: model,        # Required
          max_tokens: Map.get(step, :max_tokens, Map.get(llm_config, :max_tokens, 2000)),
          temperature: Map.get(step, :temperature, Map.get(llm_config, :temperature, 0.7)),
          timeout: Map.get(step, :timeout, Map.get(llm_config, :timeout, 30_000)),
          user_id: Map.get(session.context, :user_id),
          conversation_id: Map.get(session.context, :conversation_id),
          from_cot: true
        }

        # Add cancellation token if available
        options = if session.cancellation_token do
          CancellationToken.add_to_input(options, session.cancellation_token)
        else
          options
        end

        messages = [
          %{role: "system", content: get_system_prompt(session)},
          %{role: "user", content: prompt}
        ]

        Logger.debug("Executing step #{step.name} with #{provider}/#{model}")

        # Convert map to keyword list for Service.completion/1
        opts = %{messages: messages} |> Map.merge(options) |> Map.to_list()

        case Service.completion(opts) do
          {:ok, response} ->
            content = extract_content(response)
            Logger.debug("Step #{step.name} completed")
            {:ok, content}

          {:error, :cancelled} = error ->
            Logger.info("LLM call cancelled for step #{step.name}")
            error

          {:error, reason} = error ->
            Logger.error("LLM call failed for step #{step.name}: #{inspect(reason)}")
            error
        end
      end
    end
  end

  defp get_system_prompt(session) do
    template = Map.get(session.config, :template, :default)

    base_prompt =
      case template do
        :analytical -> "You are an analytical reasoning assistant. Provide detailed, structured analysis."
        :creative -> "You are a creative problem solver. Think outside the box while maintaining practicality."
        :conversational -> "You are a helpful conversational assistant. Be natural and engaging."
        _ -> "You are a helpful assistant using chain-of-thought reasoning."
      end

    "#{base_prompt}\n\nYou are executing step-by-step reasoning for: #{session.config.description}"
  end

  defp extract_content(response) do
    cond do
      is_binary(response) ->
        response

      is_struct(response, RubberDuck.LLM.Response) ->
        extract_llm_response_content(response)

      is_map(response) and Map.has_key?(response, :content) ->
        response.content

      is_map(response) and Map.has_key?(response, :choices) ->
        extract_choices_content(response.choices)

      true ->
        ""
    end
  end

  defp extract_llm_response_content(%{choices: choices}) when is_list(choices) do
    extract_choices_content(choices)
  end

  defp extract_llm_response_content(%{content: content}), do: content

  defp extract_llm_response_content(_response) do
    Logger.error("Unknown LLM response format")
    ""
  end

  defp extract_choices_content([%{message: %{content: content}} | _]), do: content
  defp extract_choices_content([%{message: %{"content" => content}} | _]), do: content
  defp extract_choices_content([%{"message" => %{"content" => content}} | _]), do: content
  defp extract_choices_content([%{text: content} | _]), do: content
  defp extract_choices_content([%{"text" => content} | _]), do: content

  defp extract_choices_content(_choices) do
    Logger.error("Failed to extract content from choices")
    ""
  end

  defp validate_result(step, result, session) do
    case Map.get(step, :validates) do
      nil ->
        :ok

      [] ->
        :ok

      validators when is_list(validators) ->
        run_validators(validators, result, session, step)
    end
  end

  defp run_validators(validators, result, session, step) do
    validation_context = %{
      result: result,
      session: session,
      step: step
    }

    Logger.debug("Validating step #{step.name}")
    
    # Broadcast validation status if we have a conversation_id
    conversation_id = get_in(session, [:context, :conversation_id])
    if conversation_id do
      Status.workflow(
        conversation_id,
        "Validating step: #{step.name}",
        %{
          step_name: step.name,
          chain: inspect(session.chain),
          status: :validating
        }
      )
    end

    chain_module = Map.get(step, :__chain_module__, session.chain)

    Enum.reduce_while(validators, :ok, fn validator, :ok ->
      # Check cancellation before each validator
      if session.cancellation_token && CancellationToken.cancelled?(session.cancellation_token) do
        {:halt, {:error, :cancelled}}
      else
        if function_exported?(chain_module, validator, 1) do
          case apply(chain_module, validator, [validation_context]) do
            true -> {:cont, :ok}
            false -> {:halt, {:error, "Validation failed: #{validator}"}}
            {:error, _} = error -> {:halt, error}
          end
        else
          Logger.warning("Validator #{validator} not found in #{chain_module}")
          {:cont, :ok}
        end
      end
    end)
  end

  defp update_session_with_result(session, step, result) do
    step_result = %{
      name: step.name,
      result: result,
      executed_at: DateTime.utc_now()
    }

    %{session | steps: Map.put(session.steps, step.name, step_result)}
  end

  defp find_step(steps, step_name) do
    case Enum.find(steps, fn s -> s.name == step_name end) do
      nil -> {:error, "Step not found: #{step_name}"}
      step -> {:ok, step}
    end
  end

  defp build_final_result(session) do
    # Extract the steps from the session
    steps = extract_steps_list(session.steps)
    
    # Build the result structure expected by engines
    %{
      query: session.query,
      reasoning_steps: steps,
      final_answer: get_final_answer(steps),
      total_steps: length(steps),
      duration_ms: calculate_duration(session),
      status: session.status,
      config: session.config,
      context: session.context,
      started_at: session.started_at
    }
  end

  defp extract_steps_list(steps_map) when is_map(steps_map) do
    steps_map
    |> Map.values()
    |> Enum.sort_by(& &1[:executed_at])
  end

  defp extract_steps_list(_), do: []

  defp get_final_answer([]), do: ""

  defp get_final_answer(steps) do
    last_step = List.last(steps)

    if last_step && Map.has_key?(last_step, :result) do
      last_step.result
    else
      ""
    end
  end

  defp calculate_duration(%{started_at: started_at, completed_at: completed_at}) 
       when not is_nil(started_at) and not is_nil(completed_at) do
    DateTime.diff(completed_at, started_at, :millisecond)
  end

  defp calculate_duration(_), do: 0
end
