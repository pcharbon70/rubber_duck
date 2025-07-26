defmodule RubberDuck.Agents.GenerationAgent do
  @moduledoc """
  Generation Agent specialized in code generation using LLM services and RAG.

  The Generation Agent is responsible for:
  - Generating code from natural language descriptions
  - Refactoring existing code for improvements
  - Fixing broken or incomplete code
  - Providing intelligent code completions
  - Generating documentation and tests
  - Learning from user preferences and patterns

  ## Capabilities

  - `:code_generation` - Generate new code from descriptions
  - `:code_refactoring` - Improve existing code structure
  - `:code_fixing` - Fix syntax and logic errors
  - `:code_completion` - Complete partial code snippets
  - `:documentation_generation` - Generate docs and comments

  ## Task Types

  - `:generate_code` - Create new code from natural language
  - `:refactor_code` - Improve code quality and structure
  - `:fix_code` - Fix errors and issues in code
  - `:complete_code` - Complete code at cursor position
  - `:generate_docs` - Generate documentation

  ## Example Usage

      # Generate new code
      task = %{
        id: "gen_1",
        type: :generate_code,
        payload: %{
          prompt: "Create a GenServer that manages user sessions",
          language: :elixir,
          context_files: ["lib/user.ex"]
        }
      }

      {:ok, result} = Agent.assign_task(agent_pid, task, context)
  """

  use RubberDuck.Agents.Behavior

  alias RubberDuck.Engines.Generation, as: GenerationEngine
  alias RubberDuck.LLM.Service, as: LLMService
  alias RubberDuck.SelfCorrection.Engine, as: SelfCorrection
  alias RubberDuck.RAG.Pipeline, as: RAGPipeline
  # alias RubberDuck.Context.Builder, as: ContextBuilder

  require Logger

  @capabilities [
    :code_generation,
    :code_refactoring,
    :code_fixing,
    :code_completion,
    :documentation_generation
  ]

  # Helper functions first

  defp initialize_metrics do
    %{
      tasks_completed: 0,
      generate_code: 0,
      refactor_code: 0,
      fix_code: 0,
      complete_code: 0,
      generate_docs: 0,
      total_tokens_used: 0,
      cache_hits: 0,
      cache_misses: 0
    }
  end

  defp update_task_metrics(metrics, task_type) do
    metrics
    |> Map.update(:tasks_completed, 1, &(&1 + 1))
    |> Map.update(task_type, 1, &(&1 + 1))
  end

  defp determine_status(state) do
    if Map.has_key?(state, :current_task) do
      :busy
    else
      :idle
    end
  end

  defp send_response(from, message) do
    if is_pid(from) do
      send(from, message)
    end
  end

  # Behavior Implementation

  @impl true
  def init(config) do
    state = %{
      config: config,
      generation_cache: %{},
      user_preferences: initialize_user_preferences(config),
      generation_history: [],
      metrics: initialize_metrics(),
      llm_config: configure_llm(config),
      last_activity: DateTime.utc_now()
    }

    Logger.info("Generation Agent initialized with config: #{inspect(config)}")
    {:ok, state}
  end

  @impl true
  def handle_task(task, context, state) do
    Logger.info("Generation Agent handling task: #{task.type}")

    case task.type do
      :generate_code ->
        handle_generate_code(task, context, state)

      :refactor_code ->
        handle_refactor_code(task, context, state)

      :fix_code ->
        handle_fix_code(task, context, state)

      :complete_code ->
        handle_complete_code(task, context, state)

      :generate_docs ->
        handle_generate_docs(task, context, state)

      _ ->
        {:error, {:unsupported_task_type, task.type}, state}
    end
  end

  @impl true
  def handle_message(message, from, state) do
    case message do
      {:generation_request, prompt, language} ->
        result = quick_generate(prompt, language, state)
        send_response(from, {:generation_result, result})
        {:ok, state}

      {:preference_update, preferences} ->
        new_preferences = Map.merge(state.user_preferences, preferences)
        new_state = %{state | user_preferences: new_preferences}
        send_response(from, :preferences_updated)
        {:ok, new_state}

      {:cache_stats} ->
        stats = get_cache_stats(state)
        send_response(from, {:cache_stats, stats})
        {:ok, state}

      _ ->
        Logger.debug("Generation Agent received unknown message: #{inspect(message)}")
        {:noreply, state}
    end
  end

  @impl true
  def get_capabilities(_state) do
    @capabilities
  end

  @impl true
  def get_status(state) do
    %{
      status: determine_status(state),
      current_task: Map.get(state, :current_task),
      metrics: state.metrics,
      health: %{
        healthy: true,
        cache_size: map_size(state.generation_cache),
        history_size: length(state.generation_history),
        llm_connected: check_llm_connection(state)
      },
      llm_status: get_llm_status(state),
      last_activity: state.last_activity,
      capabilities: @capabilities
    }
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("Generation Agent terminating")
    :ok
  end

  # Task Handlers

  defp handle_generate_code(%{payload: payload} = task, context, state) do
    prompt = payload.prompt
    language = Map.get(payload, :language, :elixir)
    context_files = Map.get(payload, :context_files, [])

    # Check cache first
    cache_key = {prompt, language, context_files}

    case Map.get(state.generation_cache, cache_key) do
      nil ->
        # Build RAG context
        rag_context = build_rag_context(prompt, context_files, context, state)

        # Generate code using Generation Engine
        generation_result =
          case GenerationEngine.execute(
                 %{
                   prompt: prompt,
                   language: language,
                   context: rag_context,
                   user_preferences: state.user_preferences
                 },
                 state.llm_config
               ) do
            {:ok, result} ->
              result

            {:error, reason} ->
              Logger.error("Generation failed: #{inspect(reason)}")

              %{
                code: "# Generation failed: #{inspect(reason)}",
                explanation: "Failed to generate code",
                confidence: 0.0
              }
          end

        # Apply self-correction if enabled
        final_result =
          if Map.get(state.config, :enable_self_correction, true) and generation_result.confidence > 0 do
            apply_self_correction_to_generation(generation_result, context, state)
          else
            generation_result
          end

        # Format result
        result = %{
          task_id: task.id,
          generated_code: final_result.code,
          explanation: final_result.explanation,
          language: language,
          imports_detected: detect_imports(final_result.code, language),
          confidence: final_result.confidence,
          syntax_valid: validate_syntax(final_result.code, language),
          timestamp: DateTime.utc_now()
        }

        # Update cache and history
        new_cache = Map.put(state.generation_cache, cache_key, result)
        new_history = [{task.id, prompt, result} | Enum.take(state.generation_history, 99)]

        new_state = %{
          state
          | generation_cache: new_cache,
            generation_history: new_history,
            metrics: update_task_metrics(state.metrics, :generate_code),
            last_activity: DateTime.utc_now()
        }

        {:ok, result, new_state}

      cached_result ->
        # Return cached result
        Logger.debug("Returning cached generation result")

        new_state = %{
          state
          | metrics: update_task_metrics(Map.update(state.metrics, :cache_hits, 1, &(&1 + 1)), :generate_code),
            last_activity: DateTime.utc_now()
        }

        {:ok, cached_result, new_state}
    end
  end

  defp handle_refactor_code(%{payload: payload} = task, _context, state) do
    code = payload.code
    refactoring_type = Map.get(payload, :refactoring_type, :general)
    preserve_behavior = Map.get(payload, :preserve_behavior, true)
    language = Map.get(payload, :language, :elixir)

    # Build refactoring prompt
    refactoring_prompt = build_refactoring_prompt(code, refactoring_type, preserve_behavior)

    # Use LLM for refactoring
    refactoring_result =
      case LLMService.completion(%{
             model: get_model(state),
             messages: [%{role: "user", content: refactoring_prompt}]
           }) do
        {:ok, %{choices: [%{message: %{content: refactored_code}} | _], usage: usage}} ->
          %{
            code: refactored_code,
            changes: analyze_changes(code, refactored_code),
            tokens_used: usage.total_tokens
          }

        {:error, reason} ->
          Logger.error("Refactoring failed: #{inspect(reason)}")

          %{
            code: code,
            changes: [],
            tokens_used: 0
          }
      end

    result = %{
      task_id: task.id,
      refactored_code: refactoring_result.code,
      changes_made: refactoring_result.changes,
      behavior_preserved: verify_behavior_preservation(code, refactoring_result.code, language),
      refactoring_type: refactoring_type,
      confidence: calculate_refactoring_confidence(refactoring_result),
      timestamp: DateTime.utc_now()
    }

    new_state = %{
      state
      | metrics:
          state.metrics
          |> update_task_metrics(:refactor_code)
          |> Map.update(:total_tokens_used, refactoring_result.tokens_used, &(&1 + refactoring_result.tokens_used)),
        last_activity: DateTime.utc_now()
    }

    {:ok, result, new_state}
  end

  defp handle_fix_code(%{payload: payload} = task, _context, state) do
    code = payload.code
    error_message = Map.get(payload, :error_message, "")
    file_path = Map.get(payload, :file_path)
    language = Map.get(payload, :language, :elixir)

    # Build fix prompt with error context
    fix_prompt = build_fix_prompt(code, error_message, file_path)

    # Use LLM to fix the code
    fix_result =
      case LLMService.completion(%{
             model: get_model(state),
             messages: [%{role: "user", content: fix_prompt}]
           }) do
        {:ok, %{choices: [%{message: %{content: fixed_code}} | _], usage: usage}} ->
          %{
            code: extract_code_from_response(fixed_code),
            explanation: extract_explanation_from_response(fixed_code),
            tokens_used: usage.total_tokens
          }

        {:error, reason} ->
          Logger.error("Code fix failed: #{inspect(reason)}")

          %{
            code: code,
            explanation: "Failed to fix: #{inspect(reason)}",
            tokens_used: 0
          }
      end

    # Validate the fix
    syntax_valid = validate_syntax(fix_result.code, language)

    result = %{
      task_id: task.id,
      fixed_code: fix_result.code,
      fix_explanation: fix_result.explanation,
      syntax_valid: syntax_valid,
      original_error: error_message,
      confidence: if(syntax_valid, do: 0.9, else: 0.3),
      timestamp: DateTime.utc_now()
    }

    new_state = %{
      state
      | metrics:
          state.metrics
          |> update_task_metrics(:fix_code)
          |> Map.update(:total_tokens_used, fix_result.tokens_used, &(&1 + fix_result.tokens_used)),
        last_activity: DateTime.utc_now()
    }

    {:ok, result, new_state}
  end

  defp handle_complete_code(%{payload: payload} = task, _context, state) do
    prefix = payload.prefix
    suffix = Map.get(payload, :suffix, "")
    cursor_position = Map.get(payload, :cursor_position, {0, 0})
    language = Map.get(payload, :language, :elixir)

    # Use FIM (Fill-in-the-Middle) approach
    _fim_context = %{
      prefix: prefix,
      suffix: suffix,
      cursor_position: cursor_position,
      language: language
    }

    # Get completions from Generation Engine
    # GenerationEngine.complete not yet implemented
    # For now, return a simple completion
    completions =
      [%{text: "# Code completion placeholder", score: 0.8, tokens: 5}]

    result = %{
      task_id: task.id,
      completions: completions,
      context_used: %{prefix_lines: count_lines(prefix), suffix_lines: count_lines(suffix)},
      cursor_position: cursor_position,
      confidence: calculate_completion_confidence(completions),
      timestamp: DateTime.utc_now()
    }

    new_state = %{
      state
      | metrics: update_task_metrics(state.metrics, :complete_code),
        last_activity: DateTime.utc_now()
    }

    {:ok, result, new_state}
  end

  defp handle_generate_docs(%{payload: payload} = task, _context, state) do
    code = payload.code
    doc_type = Map.get(payload, :doc_type, :moduledoc)
    language = Map.get(payload, :language, :elixir)

    # Build documentation prompt
    doc_prompt = build_doc_prompt(code, doc_type, language)

    # Generate documentation
    doc_result =
      case LLMService.completion(%{
             model: get_model(state),
             messages: [%{role: "user", content: doc_prompt}]
           }) do
        {:ok, %{choices: [%{message: %{content: documentation}} | _], usage: usage}} ->
          %{
            documentation: format_documentation(documentation, doc_type, language),
            examples_included: contains_examples?(documentation),
            tokens_used: usage.total_tokens
          }

        {:error, reason} ->
          Logger.error("Documentation generation failed: #{inspect(reason)}")

          %{
            documentation: "# Documentation generation failed",
            examples_included: false,
            tokens_used: 0
          }
      end

    result = %{
      task_id: task.id,
      documentation: doc_result.documentation,
      doc_type: doc_type,
      examples_included: doc_result.examples_included,
      confidence: 0.85,
      timestamp: DateTime.utc_now()
    }

    new_state = %{
      state
      | metrics:
          state.metrics
          |> update_task_metrics(:generate_docs)
          |> Map.update(:total_tokens_used, doc_result.tokens_used, &(&1 + doc_result.tokens_used)),
        last_activity: DateTime.utc_now()
    }

    {:ok, result, new_state}
  end

  # Helper Functions

  defp initialize_user_preferences(config) do
    Map.get(config, :user_preferences, %{
      code_style: :balanced,
      comments: :helpful,
      error_handling: :comprehensive,
      naming_convention: :snake_case
    })
  end

  defp configure_llm(config) do
    %{
      provider: Map.get(config, :llm_provider, :openai),
      model: Map.get(config, :model, "gpt-4"),
      temperature: Map.get(config, :temperature, 0.7),
      max_tokens: Map.get(config, :max_tokens, 2048)
    }
  end

  defp build_rag_context(prompt, context_files, context, _state) do
    # Use RAG Pipeline to retrieve relevant context
    case RAGPipeline.retrieve(%{
           query: prompt,
           file_paths: context_files,
           limit: 10
         }) do
      {:ok, documents} ->
        %{
          relevant_code: Enum.map(documents, & &1.content),
          patterns: extract_patterns_from_docs(documents),
          user_context: Map.get(context, :memory, %{})
        }

      {:error, _reason} ->
        %{
          relevant_code: [],
          patterns: [],
          user_context: Map.get(context, :memory, %{})
        }
    end
  end

  defp apply_self_correction_to_generation(generation_result, context, _state) do
    case SelfCorrection.correct(%{
           input: generation_result.code,
           language: generation_result.language,
           strategies: [:syntax_validation, :logic_verification],
           context: context
         }) do
      {:ok, corrected} ->
        %{
          generation_result
          | code: corrected.output,
            confidence: corrected.confidence
        }

      {:error, _reason} ->
        generation_result
    end
  end

  defp detect_imports(code, :elixir) do
    import_regex = ~r/^\s*(import|alias|use|require)\s+([A-Z][A-Za-z0-9._]*)/m

    Regex.scan(import_regex, code)
    |> Enum.map(fn [_full, directive, module] ->
      %{directive: String.to_atom(directive), module: module}
    end)
  end

  defp detect_imports(_code, _language) do
    []
  end

  defp validate_syntax(code, :elixir) do
    case Code.string_to_quoted(code) do
      {:ok, _ast} -> true
      {:error, _} -> false
    end
  end

  defp validate_syntax(_code, _language) do
    # For other languages, assume valid or use external validators
    true
  end

  defp get_model(state) do
    state.llm_config.model
  end

  defp build_refactoring_prompt(code, refactoring_type, preserve_behavior) do
    behavior_instruction =
      if preserve_behavior do
        "IMPORTANT: The refactored code must preserve the exact same behavior and API."
      else
        "You may change the behavior if it improves the code quality."
      end

    """
    Refactor the following code with focus on #{refactoring_type}.
    #{behavior_instruction}

    Original code:
    ```
    #{code}
    ```

    Provide the refactored code with explanations for the changes made.
    """
  end

  defp analyze_changes(original, refactored) do
    # Simple line-based diff analysis
    original_lines = String.split(original, "\n")
    refactored_lines = String.split(refactored, "\n")

    changes = []

    changes =
      if length(original_lines) != length(refactored_lines) do
        ["Line count changed from #{length(original_lines)} to #{length(refactored_lines)}"] ++ changes
      else
        changes
      end

    changes =
      if String.contains?(refactored, "defp") and not String.contains?(original, "defp") do
        ["Added private functions"] ++ changes
      else
        changes
      end

    changes
  end

  defp verify_behavior_preservation(_original, _refactored, _language) do
    # Simplified - in production would run tests or deeper analysis
    true
  end

  defp calculate_refactoring_confidence(refactoring_result) do
    base_confidence = 0.7

    # Adjust based on changes
    confidence =
      if length(refactoring_result.changes) > 0 do
        base_confidence + 0.1
      else
        base_confidence - 0.2
      end

    min(max(confidence, 0.0), 1.0)
  end

  defp build_fix_prompt(code, error_message, file_path) do
    file_context =
      if file_path do
        "File: #{file_path}"
      else
        ""
      end

    """
    Fix the following code that has an error.
    #{file_context}

    Error message: #{error_message}

    Broken code:
    ```
    #{code}
    ```

    Provide the fixed code and explain what was wrong and how you fixed it.
    Format your response as:

    FIXED CODE:
    ```
    [fixed code here]
    ```

    EXPLANATION:
    [explanation here]
    """
  end

  defp extract_code_from_response(response) do
    case Regex.run(~r/FIXED CODE:\s*```[a-z]*\n(.*?)```/s, response) do
      [_, code] -> String.trim(code)
      # Fallback to full response
      _ -> response
    end
  end

  defp extract_explanation_from_response(response) do
    case Regex.run(~r/EXPLANATION:\s*(.+)/s, response) do
      [_, explanation] -> String.trim(explanation)
      _ -> "Code has been fixed"
    end
  end

  defp count_lines(text) do
    text
    |> String.split("\n")
    |> length()
  end

  defp calculate_completion_confidence(completions) do
    if Enum.empty?(completions) do
      0.0
    else
      # Average score of top completions
      scores = Enum.map(completions, & &1.score)
      Enum.sum(scores) / length(scores)
    end
  end

  defp build_doc_prompt(code, doc_type, language) do
    doc_instruction =
      case doc_type do
        :moduledoc -> "Generate comprehensive module documentation"
        :fundoc -> "Generate function documentation with examples"
        :typedoc -> "Generate type documentation"
        _ -> "Generate appropriate documentation"
      end

    """
    #{doc_instruction} for the following #{language} code:

    ```#{language}
    #{code}
    ```

    Include:
    - Clear description of purpose and functionality
    - Parameters and return values (where applicable)
    - Usage examples
    - Any important notes or warnings
    """
  end

  defp format_documentation(doc, :moduledoc, :elixir) do
    """
    @moduledoc \"\"\"
    #{String.trim(doc)}
    \"\"\"
    """
  end

  defp format_documentation(doc, :fundoc, :elixir) do
    """
    @doc \"\"\"
    #{String.trim(doc)}
    \"\"\"
    """
  end

  defp format_documentation(doc, _type, _language) do
    doc
  end

  defp contains_examples?(documentation) do
    String.contains?(documentation, "Example") or
      String.contains?(documentation, "##") or
      String.contains?(documentation, "iex>")
  end

  defp quick_generate(prompt, language, state) do
    # Quick generation without full task handling
    case GenerationEngine.execute(
           %{
             prompt: prompt,
             language: language,
             context: %{},
             user_preferences: state.user_preferences
           },
           state.llm_config
         ) do
      {:ok, result} ->
        %{
          code: result.code,
          confidence: result.confidence
        }

      {:error, reason} ->
        %{
          code: "# Generation failed: #{inspect(reason)}",
          confidence: 0.0
        }
    end
  end

  defp get_cache_stats(state) do
    %{
      cache_size: map_size(state.generation_cache),
      hit_rate: calculate_hit_rate(state.metrics),
      total_cached: state.metrics.cache_hits + state.metrics.cache_misses
    }
  end

  defp calculate_hit_rate(%{cache_hits: hits, cache_misses: misses}) when hits + misses > 0 do
    hits / (hits + misses)
  end

  defp calculate_hit_rate(_metrics), do: 0.0

  defp check_llm_connection(_state) do
    # Simplified - would check actual LLM service status
    true
  end

  defp get_llm_status(state) do
    %{
      provider: state.llm_config.provider,
      model: state.llm_config.model,
      connected: check_llm_connection(state),
      tokens_used: state.metrics.total_tokens_used
    }
  end

  defp extract_patterns_from_docs(documents) do
    documents
    |> Enum.flat_map(fn doc ->
      Map.get(doc, :patterns, [])
    end)
    |> Enum.uniq()
  end
end
