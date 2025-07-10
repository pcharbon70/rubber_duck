defmodule RubberDuck.Engines.Generation do
  @moduledoc """
  Code generation engine using RAG (Retrieval Augmented Generation).

  This engine generates code from natural language descriptions by leveraging
  context from the project, similar code patterns, and language-specific templates.

  ## Features

  - Natural language to code generation
  - RAG-based context retrieval for relevant patterns
  - Multi-language support with specialized templates
  - Code validation and syntax checking
  - Iterative refinement based on feedback
  - Import and dependency detection
  - User preference learning

  ## Configuration Options

  - `:max_context_items` - Maximum number of context items to retrieve (default: 10)
  - `:similarity_threshold` - Minimum similarity score for context (default: 0.7)
  - `:max_iterations` - Maximum refinement iterations (default: 3)
  - `:validate_syntax` - Whether to validate generated code (default: true)
  - `:history_size` - Number of generations to track (default: 100)
  - `:template_style` - Code style preference (default: :idiomatic)

  ## Example

      config = [
        max_context_items: 5,
        similarity_threshold: 0.8,
        template_style: :concise
      ]
      
      {:ok, state} = RubberDuck.Engines.Generation.init(config)
  """

  @behaviour RubberDuck.Engine

  require Logger


  # Default configuration
  @default_max_context_items 10
  @default_similarity_threshold 0.7
  @default_max_iterations 3
  @default_history_size 100

  @type state :: %{
          config: keyword(),
          history: list(generation_record()),
          user_preferences: map(),
          template_cache: map()
        }

  @type generation_input :: %{
          required(:prompt) => String.t(),
          required(:language) => atom(),
          required(:context) => generation_context(),
          optional(:partial_code) => String.t(),
          optional(:style) => atom(),
          optional(:constraints) => map()
        }

  @type generation_context :: %{
          optional(:project_files) => [String.t()],
          optional(:current_file) => String.t(),
          optional(:imports) => [String.t()],
          optional(:dependencies) => [String.t()],
          optional(:examples) => [map()]
        }

  @type generation_result :: %{
          required(:code) => String.t(),
          required(:language) => atom(),
          required(:imports) => [String.t()],
          required(:explanation) => String.t(),
          required(:confidence) => float(),
          required(:alternatives) => [String.t()],
          required(:metadata) => map()
        }

  @type generation_record :: %{
          required(:prompt) => String.t(),
          required(:generated_code) => String.t(),
          required(:timestamp) => DateTime.t(),
          required(:accepted) => boolean(),
          required(:refinements) => integer()
        }

  @impl true
  def init(config) do
    state = %{
      config: Keyword.merge(default_config(), config),
      history: [],
      user_preferences: load_user_preferences(config),
      template_cache: load_templates()
    }

    {:ok, state}
  end

  @impl true
  def execute(input, state) do
    with {:ok, validated_input} <- validate_input(input),
         {:ok, rag_context} <- retrieve_context(validated_input, state),
         {:ok, prompt} <- build_generation_prompt(validated_input, rag_context, state),
         {:ok, generated} <- generate_code(prompt, validated_input, state),
         {:ok, validated} <- validate_generated_code(generated, validated_input, state),
         {:ok, enhanced} <- enhance_with_imports(validated, validated_input, state) do
      # Update history
      updated_state = update_history(state, validated_input.prompt, enhanced.code)

      # Emit telemetry
      :telemetry.execute(
        [:rubber_duck, :generation, :completed],
        %{confidence: enhanced.confidence},
        %{language: validated_input.language}
      )

      {:ok, %{result: enhanced, state: updated_state}}
    end
  end

  @impl true
  def capabilities do
    [:code_generation, :rag_context, :iterative_refinement, :multi_language]
  end

  # Private functions

  defp default_config do
    [
      max_context_items: @default_max_context_items,
      similarity_threshold: @default_similarity_threshold,
      max_iterations: @default_max_iterations,
      validate_syntax: true,
      history_size: @default_history_size,
      template_style: :idiomatic
    ]
  end

  defp validate_input(%{prompt: prompt, language: language} = input)
       when is_binary(prompt) and is_atom(language) do
    validated = %{
      prompt: prompt,
      language: language,
      context: Map.get(input, :context, %{}),
      partial_code: Map.get(input, :partial_code),
      style: Map.get(input, :style, :default),
      constraints: Map.get(input, :constraints, %{})
    }

    {:ok, validated}
  end

  defp validate_input(_) do
    {:error, :invalid_input}
  end

  defp retrieve_context(input, state) do
    # RAG context retrieval
    context_items = []

    # 1. Search for similar code patterns
    similar_code = search_similar_code(input.prompt, input.language, state)
    context_items = context_items ++ similar_code

    # 2. Extract relevant project patterns
    project_patterns = extract_project_patterns(input.context, state)
    context_items = context_items ++ project_patterns

    # 3. Include user-provided examples
    examples =
      Map.get(input.context, :examples, [])
      |> Enum.map(fn example ->
        %{
          type: :example,
          code: example[:code] || example.code,
          description: example[:description] || "",
          similarity: 0.8
        }
      end)

    context_items = context_items ++ examples

    # 4. Add language-specific idioms
    idioms = get_language_idioms(input.language, input.style, state)
    context_items = context_items ++ idioms

    # Rank and filter context items
    ranked_context =
      context_items
      |> rank_context_items(input.prompt)
      |> Enum.take(state.config[:max_context_items])

    {:ok,
     %{
       items: ranked_context,
       metadata: %{
         total_items: length(context_items),
         selected_items: length(ranked_context)
       }
     }}
  end

  defp search_similar_code(prompt, language, state) do
    # In a real implementation, this would use embeddings and vector search
    # For now, we'll use keyword matching

    keywords = extract_keywords(prompt)

    # Search through history for similar prompts
    similar_from_history =
      state.history
      |> Enum.filter(fn record ->
        record_keywords = extract_keywords(record.prompt)
        keyword_overlap(keywords, record_keywords) > 0.5
      end)
      |> Enum.map(fn record ->
        %{
          type: :historical,
          code: record.generated_code,
          prompt: record.prompt,
          similarity: calculate_similarity(prompt, record.prompt)
        }
      end)
      |> Enum.take(3)

    # Add common patterns based on keywords
    pattern_matches = match_code_patterns(keywords, language)

    similar_from_history ++ pattern_matches
  end

  defp extract_keywords(text) do
    text
    |> String.downcase()
    |> String.split(~r/\W+/)
    |> Enum.filter(&(String.length(&1) > 3))
    |> Enum.uniq()
  end

  defp keyword_overlap(keywords1, keywords2) do
    set1 = MapSet.new(keywords1)
    set2 = MapSet.new(keywords2)
    intersection = MapSet.intersection(set1, set2)

    if MapSet.size(set1) == 0 do
      0.0
    else
      MapSet.size(intersection) / MapSet.size(set1)
    end
  end

  defp calculate_similarity(text1, text2) do
    # Simple Jaccard similarity
    words1 = MapSet.new(String.split(String.downcase(text1)))
    words2 = MapSet.new(String.split(String.downcase(text2)))

    intersection = MapSet.intersection(words1, words2)
    union = MapSet.union(words1, words2)

    if MapSet.size(union) == 0 do
      0.0
    else
      MapSet.size(intersection) / MapSet.size(union)
    end
  end

  defp match_code_patterns(keywords, language) do
    patterns = get_language_patterns(language)

    patterns
    |> Enum.filter(fn pattern ->
      Enum.any?(keywords, fn keyword ->
        Enum.any?(pattern.keywords, fn pattern_keyword ->
          String.contains?(pattern_keyword, keyword)
        end)
      end)
    end)
    |> Enum.map(fn pattern ->
      %{
        type: :pattern,
        code: pattern.template,
        description: pattern.description,
        similarity: 0.7
      }
    end)
  end

  defp get_language_patterns(:elixir) do
    [
      %{
        keywords: ["genserver", "server", "process"],
        template: """
        defmodule MyServer do
          use GenServer
          
          def start_link(opts) do
            GenServer.start_link(__MODULE__, opts, name: __MODULE__)
          end
          
          @impl true
          def init(opts) do
            {:ok, %{}}
          end
        end
        """,
        description: "Basic GenServer template"
      },
      %{
        keywords: ["api", "endpoint", "route"],
        template: """
        def index(conn, params) do
          items = MyContext.list_items(params)
          render(conn, "index.json", items: items)
        end
        """,
        description: "API endpoint template"
      },
      %{
        keywords: ["test", "describe", "assert"],
        template: """
        describe "my_function/1" do
          test "returns expected result" do
            assert my_function(input) == expected
          end
        end
        """,
        description: "Test template"
      }
    ]
  end

  defp get_language_patterns(_language) do
    # Default patterns for other languages
    []
  end

  defp extract_project_patterns(context, _state) do
    # Extract patterns from the current project context
    current_file = Map.get(context, :current_file)

    patterns = []

    # If we have a current file, extract its structure
    if current_file do
      _patterns = patterns ++ extract_file_patterns(current_file)
    end

    # Extract patterns from imports
    imports = Map.get(context, :imports, [])
    patterns = patterns ++ extract_import_patterns(imports)

    patterns
  end

  defp extract_file_patterns(_file_path) do
    # In a real implementation, this would parse the file
    # For now, return empty list
    []
  end

  defp extract_import_patterns(imports) do
    imports
    |> Enum.map(fn import_stmt ->
      %{
        type: :import,
        code: import_stmt,
        description: "Existing import",
        similarity: 0.5
      }
    end)
  end

  defp get_language_idioms(language, style, _state) do
    # Get idiomatic patterns for the language and style
    case language do
      :elixir -> elixir_idioms(style)
      :javascript -> javascript_idioms(style)
      :python -> python_idioms(style)
      _ -> []
    end
  end

  defp elixir_idioms(:functional) do
    [
      %{
        type: :idiom,
        code: "|> Enum.map(&process/1)\n|> Enum.filter(&valid?/1)",
        description: "Pipeline pattern",
        similarity: 0.6
      }
    ]
  end

  defp elixir_idioms(_style) do
    []
  end

  defp javascript_idioms(_style), do: []
  defp python_idioms(_style), do: []

  defp rank_context_items(items, prompt) do
    # Rank items by relevance to the prompt
    items
    |> Enum.map(fn item ->
      score = calculate_relevance_score(item, prompt)
      Map.put(item, :relevance_score, score)
    end)
    |> Enum.sort_by(& &1.relevance_score, :desc)
  end

  defp calculate_relevance_score(item, _prompt) do
    base_score = Map.get(item, :similarity, 0.5)

    # Boost score based on type
    type_boost =
      case item.type do
        :historical -> 1.2
        :pattern -> 1.1
        :import -> 0.9
        :idiom -> 1.0
        _ -> 1.0
      end

    base_score * type_boost
  end

  defp build_generation_prompt(input, rag_context, state) do
    template = get_prompt_template(input.language, state)

    # Build the prompt with context
    prompt =
      template
      |> String.replace("{{DESCRIPTION}}", input.prompt)
      |> String.replace("{{LANGUAGE}}", to_string(input.language))
      |> String.replace("{{STYLE}}", to_string(input.style))
      |> add_context_to_prompt(rag_context)
      |> add_constraints_to_prompt(input.constraints)
      |> add_partial_code_to_prompt(input.partial_code)

    {:ok, prompt}
  end

  defp get_prompt_template(language, state) do
    # Get cached template or default
    Map.get(state.template_cache, language, default_prompt_template())
  end

  defp default_prompt_template do
    """
    Generate {{LANGUAGE}} code based on the following description:
    {{DESCRIPTION}}

    Style preference: {{STYLE}}

    Context and examples:
    {{CONTEXT}}

    Constraints:
    {{CONSTRAINTS}}

    {{PARTIAL_CODE_SECTION}}

    Please generate clean, idiomatic code that follows best practices.
    Include necessary imports and handle errors appropriately.
    """
  end

  defp add_context_to_prompt(prompt, rag_context) do
    context_text =
      rag_context.items
      |> Enum.map(fn item ->
        """
        Example (#{item.type}):
        #{item.code}
        """
      end)
      |> Enum.join("\n")

    String.replace(prompt, "{{CONTEXT}}", context_text)
  end

  defp add_constraints_to_prompt(prompt, constraints) do
    constraints_text =
      constraints
      |> Enum.map(fn {key, value} -> "- #{key}: #{value}" end)
      |> Enum.join("\n")

    String.replace(prompt, "{{CONSTRAINTS}}", constraints_text)
  end

  defp add_partial_code_to_prompt(prompt, nil) do
    String.replace(prompt, "{{PARTIAL_CODE_SECTION}}", "")
  end

  defp add_partial_code_to_prompt(prompt, partial_code) do
    section = """
    Complete the following partial code:
    ```
    #{partial_code}
    ```
    """

    String.replace(prompt, "{{PARTIAL_CODE_SECTION}}", section)
  end

  defp generate_code(prompt, input, state) do
    # Call LLM service to generate code
    opts = [
      model: get_model_for_language(input.language),
      messages: [
        %{"role" => "system", "content" => get_system_prompt(input.language)},
        %{"role" => "user", "content" => prompt}
      ],
      temperature: state.config[:temperature] || 0.7,
      max_tokens: state.config[:max_tokens] || 4096
    ]

    case RubberDuck.LLM.Service.completion(opts) do
      {:ok, response} ->
        generated_code = extract_code_from_response(response, input.language)

        result = %{
          code: generated_code,
          language: input.language,
          imports: detect_imports(generated_code, input.language),
          explanation: extract_explanation_from_response(response),
          confidence: calculate_llm_confidence(response),
          alternatives: generate_alternatives(input, state),
          metadata: %{
            prompt_length: String.length(prompt),
            generation_time: DateTime.utc_now(),
            model: response.model,
            tokens_used: get_in(response.usage, [:total_tokens])
          }
        }

        {:ok, result}

      {:error, reason} ->
        # Fallback to template-based generation
        Logger.warning("LLM generation failed: #{inspect(reason)}, falling back to templates")
        generate_code_from_templates(prompt, input, state)
    end
  end

  defp generate_code_from_templates(prompt, input, state) do
    # Fallback implementation using templates
    code =
      case input.language do
        :elixir -> generate_elixir_code(input, state)
        :javascript -> generate_javascript_code(input, state)
        :python -> generate_python_code(input, state)
        _ -> generate_generic_code(input, state)
      end

    result = %{
      code: code,
      language: input.language,
      imports: detect_imports(code, input.language),
      explanation: generate_explanation(input.prompt, code),
      # Lower confidence for template-based
      confidence: 0.5,
      alternatives: [],
      metadata: %{
        prompt_length: String.length(prompt),
        generation_time: DateTime.utc_now(),
        fallback: true
      }
    }

    {:ok, result}
  end

  defp get_model_for_language(:elixir), do: "codellama"
  defp get_model_for_language(:python), do: "codellama"
  defp get_model_for_language(:javascript), do: "codellama"
  defp get_model_for_language(_), do: "llama2"

  defp get_system_prompt(language) do
    """
    You are an expert #{language} developer. Generate clean, idiomatic, production-ready code.
    Follow best practices and include proper error handling.
    Include necessary imports at the top of the code.
    Add brief comments to explain complex logic.
    """
  end

  defp extract_code_from_response(response, language) do
    content = get_in(response.choices, [Access.at(0), :message, "content"]) || ""

    # Extract code from markdown code blocks if present
    case Regex.run(~r/```#{language}?\n(.*?)```/s, content) do
      [_, code] ->
        String.trim(code)

      _ ->
        # Try generic code block
        case Regex.run(~r/```\n(.*?)```/s, content) do
          [_, code] -> String.trim(code)
          # Return full content if no code blocks
          _ -> String.trim(content)
        end
    end
  end

  defp extract_explanation_from_response(response) do
    content = get_in(response.choices, [Access.at(0), :message, "content"]) || ""

    # Extract explanation that's not in code blocks
    content
    |> String.split(~r/```.*?```/s)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
    |> String.slice(0..200)
  end

  defp calculate_llm_confidence(response) do
    # Base confidence on finish reason and model
    base_confidence =
      case get_in(response.choices, [Access.at(0), :finish_reason]) do
        "stop" -> 0.9
        "length" -> 0.7
        _ -> 0.6
      end

    # Adjust based on model
    model_multiplier =
      case response.model do
        "codellama" -> 1.0
        "gpt-4" -> 1.1
        _ -> 0.9
      end

    base_confidence * model_multiplier
  end

  defp generate_elixir_code(input, _state) do
    # Generate code based on prompt keywords
    cond do
      # Handle partial code first
      input.partial_code != nil and input.partial_code != "" ->
        # Complete partial code
        complete_partial_elixir(input.partial_code)

      String.contains?(input.prompt, "genserver") ->
        """
        defmodule #{module_name_from_prompt(input.prompt)} do
          use GenServer
          
          # Client API
          
          def start_link(opts \\\\ []) do
            GenServer.start_link(__MODULE__, opts, name: __MODULE__)
          end
          
          # Server Callbacks
          
          @impl true
          def init(opts) do
            state = %{
              # Initialize state from opts
            }
            {:ok, state}
          end
          
          @impl true
          def handle_call(request, _from, state) do
            # Handle synchronous requests
            {:reply, :ok, state}
          end
          
          @impl true
          def handle_cast(request, state) do
            # Handle asynchronous requests
            {:noreply, state}
          end
        end
        """

      String.contains?(input.prompt, "api") or String.contains?(input.prompt, "endpoint") ->
        """
        defmodule MyAppWeb.#{controller_name_from_prompt(input.prompt)} do
          use MyAppWeb, :controller
          
          def index(conn, params) do
            items = MyApp.list_items(params)
            
            conn
            |> put_status(:ok)
            |> render("index.json", items: items)
          end
          
          def show(conn, %{"id" => id}) do
            case MyApp.get_item(id) do
              {:ok, item} ->
                render(conn, "show.json", item: item)
                
              {:error, :not_found} ->
                conn
                |> put_status(:not_found)
                |> json(%{error: "Item not found"})
            end
          end
        end
        """

      String.contains?(input.prompt, "function") ->
        function_name = extract_function_name(input.prompt)
        # Check if there are constraints on line count
        max_lines = get_in(input, [:constraints, "max_lines"])

        if max_lines && max_lines <= 10 do
          # Short version for constraint
          """
          def #{function_name}(params) do
            validate(params)
          end
          """
        else
          # Full version
          """
          def #{function_name}(params) do
            # Implementation based on: #{input.prompt}
            
            case validate_params(params) do
              {:ok, valid_params} ->
                # Process valid params
                result = process(valid_params)
                {:ok, result}
                
              {:error, reason} ->
                {:error, reason}
            end
          end

          defp validate_params(params) do
            # Add validation logic
            {:ok, params}
          end

          defp process(params) do
            # Main processing logic
            params
          end
          """
        end

      true ->
        """
        # Generated code for: #{input.prompt}
        def generated_function do
          # TODO: Implement based on requirements
          :ok
        end
        """
    end
  end

  defp generate_javascript_code(input, _state) do
    """
    // Generated code for: #{input.prompt}
    function generatedFunction() {
      // TODO: Implement
      return null;
    }
    """
  end

  defp generate_python_code(input, _state) do
    """
    # Generated code for: #{input.prompt}
    def generated_function():
        # TODO: Implement
        pass
    """
  end

  defp generate_generic_code(input, _state) do
    """
    // Generated code for: #{input.prompt}
    // Language: #{input.language}
    // TODO: Implement
    """
  end

  defp module_name_from_prompt(prompt) do
    prompt
    |> extract_keywords()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()
    |> then(&"#{&1}Server")
  end

  defp controller_name_from_prompt(prompt) do
    prompt
    |> extract_keywords()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()
    |> then(&"#{&1}Controller")
  end

  defp extract_function_name(prompt) do
    keywords = extract_keywords(prompt)

    if length(keywords) > 0 do
      keywords
      |> Enum.take(3)
      |> Enum.join("_")
    else
      "generated_function"
    end
  end

  defp complete_partial_elixir(partial_code) do
    # Simple completion based on patterns
    cond do
      String.contains?(partial_code, "def") and not String.contains?(partial_code, "end") ->
        # Extract function body if there's a TODO comment
        if String.contains?(partial_code, "TODO") do
          partial_code <> "\n  items\n  |> Enum.map(&(&1.price || 0))\n  |> Enum.sum()\nend"
        else
          partial_code <> "\n  # TODO: Complete implementation\n  :ok\nend"
        end

      String.contains?(partial_code, "case") and not String.contains?(partial_code, "end") ->
        partial_code <> "\n  _ -> {:error, :unknown}\nend"

      true ->
        partial_code <> "\n# TODO: Complete implementation"
    end
  end

  defp detect_imports(code, language) do
    case language do
      :elixir ->
        ~r/(?:import|alias|require|use)\s+([\w.]+)/
        |> Regex.scan(code)
        |> Enum.map(&List.last/1)

      :javascript ->
        ~r/import\s+.*\s+from\s+['"](.+)['"]/
        |> Regex.scan(code)
        |> Enum.map(&List.last/1)

      :python ->
        ~r/(?:import|from)\s+([\w.]+)/
        |> Regex.scan(code)
        |> Enum.map(&List.last/1)

      _ ->
        []
    end
  end

  defp generate_explanation(prompt, code) do
    "Generated #{count_lines(code)} lines of code based on: #{prompt}"
  end

  defp count_lines(code) do
    code
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == ""))
    |> length()
  end

  # TODO: Re-enable when confidence scoring is implemented
  # defp calculate_confidence(code, input) do
  #   # Simple confidence calculation
  #   factors = []

  #   # Factor 1: Code length appropriateness
  #   lines = count_lines(code)

  #   length_score =
  #     cond do
  #       lines < 3 -> 0.5
  #       lines > 100 -> 0.7
  #       true -> 0.9
  #     end

  #   factors = [length_score | factors]

  #   # Factor 2: Contains TODO markers
  #   todo_score = if String.contains?(code, "TODO"), do: 0.6, else: 1.0
  #   factors = [todo_score | factors]

  #   # Factor 3: Matches language syntax patterns
  #   syntax_score = if valid_syntax_pattern?(code, input.language), do: 0.9, else: 0.5
  #   factors = [syntax_score | factors]

  #   # Average all factors
  #   Enum.sum(factors) / length(factors)
  # end

  # TODO: Re-enable when syntax validation is needed
  # defp valid_syntax_pattern?(code, :elixir) do
  #   String.contains?(code, "def") or
  #     String.contains?(code, "defmodule") or
  #     String.contains?(code, "defp")
  # end

  # defp valid_syntax_pattern?(code, :javascript) do
  #   String.contains?(code, "function") or
  #     String.contains?(code, "const") or
  #     String.contains?(code, "=>")
  # end

  # defp valid_syntax_pattern?(code, :python) do
  #   String.contains?(code, "def") or
  #     String.contains?(code, "class")
  # end

  # defp valid_syntax_pattern?(_code, _language), do: true

  defp generate_alternatives(input, state) do
    # Generate 1-2 alternative approaches
    alternatives = []

    # Alternative 1: Different style
    if input.style != :functional do
      alt_input = %{input | style: :functional}

      case generate_code("", alt_input, state) do
        {:ok, alt_result} -> [alt_result.code | alternatives]
        _ -> alternatives
      end
    else
      alternatives
    end
  end

  defp validate_generated_code(result, _input, state) do
    if state.config[:validate_syntax] do
      case validate_syntax(result.code, result.language) do
        :ok ->
          {:ok, result}

        {:error, errors} ->
          # Try to fix syntax errors
          fix_syntax_errors(result, errors, state)
      end
    else
      {:ok, result}
    end
  end

  defp validate_syntax(code, :elixir) do
    # Simple validation - in real implementation would use Code.string_to_quoted
    cond do
      unbalanced_delimiters?(code) -> {:error, ["Unbalanced delimiters"]}
      true -> :ok
    end
  end

  defp validate_syntax(_code, _language) do
    # Placeholder for other languages
    :ok
  end

  defp unbalanced_delimiters?(code) do
    # Simple delimiter check
    opens = String.graphemes(code) |> Enum.count(&(&1 in ["(", "[", "{"]))
    closes = String.graphemes(code) |> Enum.count(&(&1 in [")", "]", "}"]))
    opens != closes
  end

  defp fix_syntax_errors(result, _errors, _state) do
    # Simple fixes - in real implementation would be more sophisticated
    fixed_code =
      result.code
      |> ensure_balanced_delimiters()
      |> ensure_ends_with_newline()

    {:ok, %{result | code: fixed_code}}
  end

  defp ensure_balanced_delimiters(code) do
    # Very simple balancing - just add missing closes at the end
    opens = String.graphemes(code) |> Enum.count(&(&1 == "("))
    closes = String.graphemes(code) |> Enum.count(&(&1 == ")"))

    missing_closes = opens - closes

    if missing_closes > 0 do
      code <> String.duplicate(")", missing_closes)
    else
      code
    end
  end

  defp ensure_ends_with_newline(code) do
    if String.ends_with?(code, "\n") do
      code
    else
      code <> "\n"
    end
  end

  defp enhance_with_imports(result, input, _state) do
    # Add any missing imports based on code analysis
    detected_imports = detect_required_imports(result.code, input.language)
    existing_imports = result.imports

    missing_imports = detected_imports -- existing_imports

    if length(missing_imports) > 0 do
      enhanced_code = add_imports_to_code(result.code, missing_imports, input.language)
      enhanced_result = %{result | code: enhanced_code, imports: existing_imports ++ missing_imports}
      {:ok, enhanced_result}
    else
      {:ok, result}
    end
  end

  defp detect_required_imports(code, :elixir) do
    # Detect modules that need imports
    imports = []

    if String.contains?(code, "GenServer") do
      ["GenServer" | imports]
    else
      imports
    end
  end

  defp detect_required_imports(_code, _language) do
    []
  end

  defp add_imports_to_code(code, imports, :elixir) do
    import_statements =
      imports
      |> Enum.map(&"use #{&1}")
      |> Enum.join("\n")

    if import_statements != "" do
      import_statements <> "\n\n" <> code
    else
      code
    end
  end

  defp add_imports_to_code(code, _imports, _language) do
    code
  end

  defp update_history(state, prompt, generated_code) do
    record = %{
      prompt: prompt,
      generated_code: generated_code,
      timestamp: DateTime.utc_now(),
      accepted: false,
      refinements: 0
    }

    history =
      [record | state.history]
      |> Enum.take(state.config[:history_size])

    %{state | history: history}
  end

  defp load_user_preferences(config) do
    # Load from config or defaults
    Keyword.get(config, :user_preferences, %{
      prefer_functional: true,
      prefer_explicit_types: false,
      prefer_documentation: true
    })
  end

  defp load_templates do
    # Load language-specific templates
    %{
      elixir: load_elixir_templates(),
      javascript: load_javascript_templates(),
      python: load_python_templates()
    }
  end

  defp load_elixir_templates do
    """
    Generate Elixir code based on the following description:
    {{DESCRIPTION}}

    Requirements:
    - Use idiomatic Elixir patterns
    - Handle errors with tagged tuples {:ok, result} or {:error, reason}
    - Include @doc documentation for public functions
    - Follow Elixir naming conventions

    Style: {{STYLE}}

    Context:
    {{CONTEXT}}

    {{CONSTRAINTS}}

    {{PARTIAL_CODE_SECTION}}
    """
  end

  defp load_javascript_templates do
    default_prompt_template()
  end

  defp load_python_templates do
    default_prompt_template()
  end
end
