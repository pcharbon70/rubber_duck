defmodule RubberDuck.CoT.Manager do
  @moduledoc """
  Manager for executing Chain-of-Thought reasoning chains.
  
  Coordinates the execution of reasoning chains, managing step execution,
  validation, and result collection.
  """
  
  alias RubberDuck.LLM.Service
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
      
      # Initialize session
      session = %{
        chain: chain_module,
        config: config,
        query: query,
        context: context,
        steps: %{},
        started_at: DateTime.utc_now(),
        status: :running
      }
      
      # Execute steps
      case execute_steps(steps, session) do
        {:ok, completed_session} ->
          {:ok, %{completed_session | status: :completed, completed_at: DateTime.utc_now()}}
          
        {:error, reason, partial_session} ->
          {:error, reason, %{partial_session | status: :failed, completed_at: DateTime.utc_now()}}
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
    if function_exported?(chain_module, :config, 0) do
      {:ok, chain_module.config()}
    else
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
      case execute_single_step(step, current_session) do
        {:ok, result} ->
          updated_session = update_session_with_result(current_session, step, result)
          {:cont, {:ok, updated_session}}
          
        {:error, reason} ->
          Logger.error("Step #{step.name} failed: #{inspect(reason)}")
          {:halt, {:error, reason, current_session}}
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
    prompt = prompt_template
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
    # Get LLM config from context, with fallbacks
    llm_config = get_in(session, [:context, :llm_config]) || %{}
    
    # Get default model from ModelConfig if available
    default_model = case Process.whereis(RubberDuck.LLM.ModelConfig) do
      nil -> "codellama"
      _pid -> 
        try do
          RubberDuck.LLM.ModelConfig.get_default_model()
        catch
          _, _ -> "codellama"
        end
    end
    
    options = %{
      model: Map.get(llm_config, :model) || default_model,
      max_tokens: Map.get(step, :max_tokens, Map.get(llm_config, :max_tokens, 2000)),
      temperature: Map.get(step, :temperature, Map.get(llm_config, :temperature, 0.7)),
      timeout: Map.get(step, :timeout, Map.get(llm_config, :timeout, 30_000)),
      from_cot: true
    }
    
    messages = [
      %{role: "system", content: get_system_prompt(session)},
      %{role: "user", content: prompt}
    ]
    
    Logger.debug("Executing step #{step.name} with model #{options.model}, prompt: #{String.slice(prompt, 0, 100)}...")
    
    # Convert map to keyword list for Service.completion/1
    opts = %{messages: messages} |> Map.merge(options) |> Map.to_list()
    case Service.completion(opts) do
      {:ok, response} ->
        {:ok, extract_content(response)}
        
      {:error, reason} = error ->
        Logger.error("LLM call failed for step #{step.name}: #{inspect(reason)}")
        error
    end
  end
  
  defp get_system_prompt(session) do
    template = Map.get(session.config, :template, :default)
    
    base_prompt = case template do
      :analytical -> "You are an analytical reasoning assistant. Provide detailed, structured analysis."
      :creative -> "You are a creative problem solver. Think outside the box while maintaining practicality."
      :conversational -> "You are a helpful conversational assistant. Be natural and engaging."
      _ -> "You are a helpful assistant using chain-of-thought reasoning."
    end
    
    "#{base_prompt}\n\nYou are executing step-by-step reasoning for: #{session.config.description}"
  end
  
  defp extract_content(response) do
    cond do
      is_binary(response) -> response
      is_struct(response, RubberDuck.LLM.Response) -> extract_llm_response_content(response)
      is_map(response) and Map.has_key?(response, :content) -> response.content
      is_map(response) and Map.has_key?(response, :choices) -> extract_choices_content(response.choices)
      true -> inspect(response)
    end
  end
  
  defp extract_llm_response_content(%{choices: choices}) when is_list(choices) do
    extract_choices_content(choices)
  end
  defp extract_llm_response_content(%{content: content}), do: content
  defp extract_llm_response_content(_), do: ""
  
  defp extract_choices_content([%{message: %{content: content}} | _]), do: content
  defp extract_choices_content([%{"message" => %{"content" => content}} | _]), do: content
  defp extract_choices_content([%{text: content} | _]), do: content
  defp extract_choices_content([%{"text" => content} | _]), do: content
  defp extract_choices_content(_), do: ""
  
  defp validate_result(step, result, session) do
    case Map.get(step, :validates) do
      nil -> :ok
      [] -> :ok
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
    
    chain_module = Map.get(step, :__chain_module__, session.chain)
    
    Enum.reduce_while(validators, :ok, fn validator, :ok ->
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
end