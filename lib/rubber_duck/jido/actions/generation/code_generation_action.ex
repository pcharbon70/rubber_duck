defmodule RubberDuck.Jido.Actions.Generation.CodeGenerationAction do
  @moduledoc """
  Action for generating code from natural language descriptions using RAG.

  This action handles the core code generation functionality, leveraging
  context retrieval, language-specific templates, and iterative refinement
  to produce high-quality code from prompts.

  ## Parameters

  - `prompt` - Natural language description of the code to generate (required)
  - `language` - Target programming language (default: :elixir)
  - `context` - Additional context including files, imports, examples
  - `user_preferences` - User preferences for code style and patterns
  - `enable_self_correction` - Whether to apply self-correction (default: true)
  - `max_iterations` - Maximum refinement iterations (default: 3)

  ## Returns

  - `{:ok, result}` - Generation successful with code, confidence, metadata
  - `{:error, reason}` - Generation failed with error details

  ## Example

      params = %{
        prompt: "Create a GenServer that manages user sessions",
        language: :elixir,
        context: %{
          relevant_code: ["lib/user.ex"],
          patterns: [:genserver, :ets]
        }
      }

      {:ok, result} = CodeGenerationAction.run(params, context)
  """

  use Jido.Action,
    name: "code_generation",
    description: "Generate code from natural language descriptions",
    schema: [
      prompt: [
        type: :string,
        required: true,
        doc: "Natural language description of code to generate"
      ],
      language: [
        type: :atom,
        default: :elixir,
        doc: "Target programming language"
      ],
      context: [
        type: :map,
        default: %{},
        doc: "Additional context for generation (files, imports, examples)"
      ],
      user_preferences: [
        type: :map,
        default: %{
          code_style: :balanced,
          comments: :helpful,
          error_handling: :comprehensive,
          naming_convention: :snake_case
        },
        doc: "User preferences for code style and patterns"
      ],
      enable_self_correction: [
        type: :boolean,
        default: true,
        doc: "Whether to apply self-correction to results"
      ],
      max_iterations: [
        type: :integer,
        default: 3,
        doc: "Maximum refinement iterations"
      ]
    ]

  require Logger

  alias RubberDuck.Engines.Generation, as: GenerationEngine
  alias RubberDuck.SelfCorrection.Engine, as: SelfCorrection
  alias RubberDuck.RAG.Pipeline, as: RAGPipeline

  @impl true
  def run(params, context) do
    Logger.info("Starting code generation for prompt: #{String.slice(params.prompt, 0, 50)}...")

    with {:ok, rag_context} <- build_rag_context(params, context),
         {:ok, generation_result} <- generate_code(params, rag_context),
         {:ok, final_result} <- apply_self_correction(generation_result, params, context) do
      
      result = %{
        generated_code: final_result.code,
        explanation: final_result.explanation,
        language: params.language,
        confidence: final_result.confidence,
        imports_detected: detect_imports(final_result.code, params.language),
        syntax_valid: validate_syntax(final_result.code, params.language),
        metadata: %{
          prompt: params.prompt,
          iterations: Map.get(final_result, :iterations, 1),
          tokens_used: Map.get(final_result, :tokens_used, 0),
          generated_at: DateTime.utc_now(),
          rag_context_size: map_size(rag_context)
        }
      }

      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("Code generation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp build_rag_context(params, context) do
    case RAGPipeline.retrieve(%{
           query: params.prompt,
           file_paths: Map.get(params.context, :relevant_files, []),
           limit: 10
         }) do
      {:ok, documents} ->
        rag_context = %{
          relevant_code: Enum.map(documents, & &1.content),
          patterns: extract_patterns_from_docs(documents),
          user_context: Map.get(context, :memory, %{}),
          project_context: Map.get(params.context, :project_context, %{})
        }
        {:ok, rag_context}

      {:error, reason} ->
        Logger.warning("RAG retrieval failed, using empty context: #{inspect(reason)}")
        {:ok, %{relevant_code: [], patterns: [], user_context: %{}, project_context: %{}}}
    end
  end

  defp generate_code(params, rag_context) do
    case GenerationEngine.execute(
           %{
             prompt: params.prompt,
             language: params.language,
             context: rag_context,
             user_preferences: params.user_preferences
           },
           build_llm_config()
         ) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        # Return a fallback result instead of failing completely
        Logger.warning("Generation engine failed, providing fallback: #{inspect(reason)}")
        
        fallback_result = %{
          code: "# Code generation failed: #{inspect(reason)}\n# Please try again with a more specific prompt",
          explanation: "Generation failed, but fallback provided",
          confidence: 0.1
        }
        
        {:ok, fallback_result}
    end
  end

  defp apply_self_correction(generation_result, params, context) do
    if params.enable_self_correction and generation_result.confidence > 0.3 do
      case SelfCorrection.correct(%{
             input: generation_result.code,
             language: params.language,
             strategies: [:syntax_validation, :logic_verification],
             context: context,
             max_iterations: params.max_iterations
           }) do
        {:ok, corrected} ->
          enhanced_result = %{
            generation_result
            | code: corrected.output,
              confidence: corrected.confidence,
              iterations: Map.get(corrected, :iterations, 1)
          }
          {:ok, enhanced_result}

        {:error, _reason} ->
          # Return original result if correction fails
          {:ok, generation_result}
      end
    else
      {:ok, generation_result}
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

  defp extract_patterns_from_docs(documents) do
    documents
    |> Enum.flat_map(fn doc ->
      Map.get(doc, :patterns, [])
    end)
    |> Enum.uniq()
  end

  defp build_llm_config do
    %{
      provider: :openai,
      model: "gpt-4",
      temperature: 0.7,
      max_tokens: 2048
    }
  end
end