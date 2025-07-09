defmodule RubberDuck.Engines.Completion do
  @moduledoc """
  Code completion engine using Fill-in-the-Middle (FIM) context strategy.

  This engine provides intelligent code suggestions by analyzing the context
  before and after the cursor position. It supports multiple languages and
  can generate various types of completions including:

  - Function completions
  - Variable name suggestions
  - Import/require statements
  - Pattern matching completions
  - Documentation snippets

  ## Configuration Options

  - `:max_suggestions` - Maximum number of suggestions to return (default: 5)
  - `:cache_ttl` - Cache time-to-live in milliseconds (default: 300_000 - 5 minutes)
  - `:min_confidence` - Minimum confidence score for suggestions (default: 0.5)
  - `:context_window` - Number of lines to include in context (default: 50)
  - `:language_rules` - Map of language-specific completion rules

  ## Example

      config = [
        max_suggestions: 3,
        min_confidence: 0.7,
        context_window: 30
      ]
      
      {:ok, state} = RubberDuck.Engines.Completion.init(config)
  """

  @behaviour RubberDuck.Engine

  require Logger

  alias RubberDuck.LLM

  # Default configuration
  @default_max_suggestions 5
  # 5 minutes
  @default_cache_ttl 300_000
  @default_min_confidence 0.5
  @default_context_window 50

  # FIM special tokens
  @fim_prefix "<|fim_prefix|>"
  @fim_suffix "<|fim_suffix|>"
  @fim_middle "<|fim_middle|>"

  @type state :: %{
          config: keyword(),
          cache: map(),
          cache_expiry: map(),
          language_rules: map()
        }

  @type completion_input :: %{
          required(:prefix) => String.t(),
          required(:suffix) => String.t(),
          required(:language) => atom(),
          required(:cursor_position) => {integer(), integer()},
          optional(:file_path) => String.t(),
          optional(:project_context) => map()
        }

  @type completion_result :: %{
          text: String.t(),
          score: float(),
          type: completion_type(),
          metadata: map()
        }

  @type completion_type :: :function | :variable | :import | :pattern | :snippet | :other

  @impl true
  def init(config) do
    state = %{
      config: Keyword.merge(default_config(), config),
      cache: %{},
      cache_expiry: %{},
      language_rules: load_language_rules(config)
    }

    {:ok, state}
  end

  @impl true
  def execute(input, state) do
    with {:ok, validated_input} <- validate_input(input),
         {:ok, fim_context} <- build_fim_context(validated_input, state),
         {:ok, completions} <- generate_completions(fim_context, validated_input, state),
         {:ok, ranked} <- rank_completions(completions, validated_input, state),
         {:ok, filtered} <- filter_completions(ranked, state) do
      # Cache successful completions
      cache_key = generate_cache_key(validated_input)
      updated_state = update_cache(state, cache_key, filtered)

      # Emit telemetry
      :telemetry.execute(
        [:rubber_duck, :completion, :generated],
        %{count: length(filtered)},
        %{language: validated_input.language}
      )

      {:ok, %{completions: filtered, state: updated_state}}
    end
  end

  @impl true
  def capabilities do
    [:code_completion, :incremental_completion, :multi_suggestion]
  end

  # Private functions

  defp default_config do
    [
      max_suggestions: @default_max_suggestions,
      cache_ttl: @default_cache_ttl,
      min_confidence: @default_min_confidence,
      context_window: @default_context_window
    ]
  end

  defp validate_input(%{prefix: prefix, suffix: suffix, language: language} = input)
       when is_binary(prefix) and is_binary(suffix) and is_atom(language) do
    validated = %{
      prefix: prefix,
      suffix: suffix,
      language: language,
      cursor_position: Map.get(input, :cursor_position, {0, 0}),
      file_path: Map.get(input, :file_path),
      project_context: Map.get(input, :project_context, %{})
    }

    {:ok, validated}
  end

  defp validate_input(_) do
    {:error, :invalid_input}
  end

  defp build_fim_context(%{prefix: prefix, suffix: suffix} = input, state) do
    # Extract relevant context based on window size
    context_lines = get_context_window(state)

    prefix_context = extract_prefix_context(prefix, context_lines)
    suffix_context = extract_suffix_context(suffix, context_lines)

    # Build FIM prompt
    fim_prompt = """
    #{@fim_prefix}
    #{prefix_context}
    #{@fim_suffix}
    #{suffix_context}
    #{@fim_middle}
    """

    context = %{
      prompt: fim_prompt,
      prefix_context: prefix_context,
      suffix_context: suffix_context,
      cursor_context: extract_cursor_context(input),
      language: input.language,
      metadata: extract_context_metadata(input)
    }

    {:ok, context}
  end

  defp get_context_window(%{config: config}) do
    Keyword.get(config, :context_window, @default_context_window)
  end

  defp extract_prefix_context(prefix, context_lines) do
    lines = String.split(prefix, "\n")

    # Take last N lines as context
    lines
    |> Enum.take(-context_lines)
    |> Enum.join("\n")
  end

  defp extract_suffix_context(suffix, context_lines) do
    lines = String.split(suffix, "\n")

    # Take first N lines as context
    lines
    |> Enum.take(context_lines)
    |> Enum.join("\n")
  end

  defp extract_cursor_context(%{prefix: prefix, cursor_position: {_line, col}}) do
    # Get the current line being edited
    current_line =
      prefix
      |> String.split("\n")
      |> List.last()
      |> Kernel.||("")

    # Extract tokens around cursor
    before_cursor = String.slice(current_line, 0, col)

    %{
      current_line: current_line,
      before_cursor: before_cursor,
      last_token: extract_last_token(before_cursor),
      indentation: extract_indentation(current_line)
    }
  end

  defp extract_last_token(text) do
    # Get the last non-whitespace token
    tokens = String.split(text, ~r/[\s\(\)]+/)

    # Find the last meaningful token
    tokens
    |> Enum.reverse()
    |> Enum.find("", fn token -> String.length(token) > 0 end)
  end

  defp extract_indentation(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, indent] -> String.length(indent)
      _ -> 0
    end
  end

  defp extract_context_metadata(input) do
    %{
      has_project_context: Map.has_key?(input, :project_context),
      file_type: detect_file_type(input.file_path),
      imports: extract_imports(input.prefix),
      functions: extract_functions(input.prefix)
    }
  end

  defp detect_file_type(nil), do: :unknown

  defp detect_file_type(path) do
    case Path.extname(path) do
      ".ex" -> :elixir
      ".exs" -> :elixir_script
      ".js" -> :javascript
      ".py" -> :python
      ".rs" -> :rust
      _ -> :unknown
    end
  end

  defp extract_imports(prefix) do
    # Simple import extraction for Elixir
    ~r/(?:import|alias|require|use)\s+([A-Z][\w.]+)/
    |> Regex.scan(prefix)
    |> Enum.map(&List.last/1)
  end

  defp extract_functions(prefix) do
    # Simple function extraction for Elixir
    ~r/def(?:p?)\s+(\w+)/
    |> Regex.scan(prefix)
    |> Enum.map(&List.last/1)
  end

  defp generate_completions(fim_context, input, state) do
    # Check cache first
    cache_key = generate_cache_key(input)

    case get_from_cache(state, cache_key) do
      {:ok, cached} ->
        {:ok, cached}

      :miss ->
        # Try LLM-based completion first
        case generate_llm_completions(fim_context, input, state) do
          {:ok, llm_completions} when llm_completions != [] ->
            {:ok, llm_completions}

          _ ->
            # Fallback to rule-based completions
            completions =
              case input.language do
                :elixir -> generate_elixir_completions(fim_context, input, state)
                :javascript -> generate_javascript_completions(fim_context, input, state)
                :python -> generate_python_completions(fim_context, input, state)
                _ -> generate_generic_completions(fim_context, input, state)
              end

            {:ok, completions}
        end
    end
  end

  defp generate_llm_completions(fim_context, input, state) do
    # Build FIM prompt for the LLM
    prompt = build_fim_prompt(fim_context, input)

    opts = [
      model: get_completion_model(input.language),
      messages: [
        %{"role" => "system", "content" => get_completion_system_prompt(input.language)},
        %{"role" => "user", "content" => prompt}
      ],
      temperature: 0.2,
      max_tokens: state.config[:max_tokens] || 256,
      # Stop sequences
      stop: ["\n\n", "def ", "class ", "function "]
    ]

    case LLM.Service.completion(opts) do
      {:ok, response} ->
        completions = parse_llm_completions(response, input.language)
        {:ok, completions}

      {:error, reason} ->
        Logger.debug("LLM completion failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_fim_prompt(fim_context, input) do
    """
    Complete the following #{input.language} code at the cursor position.

    Context before cursor:
    ```#{input.language}
    #{fim_context.prefix_context}
    ```

    Current line up to cursor: #{fim_context.cursor_context.before_cursor}

    Context after cursor:
    ```#{input.language}
    #{fim_context.suffix_context}
    ```

    Provide 3-5 short completions that would naturally follow at the cursor position.
    Each completion should be on a separate line.
    Only provide the text to insert, not the entire line.
    """
  end

  defp get_completion_model(:elixir), do: "codellama"
  defp get_completion_model(:python), do: "codellama"
  defp get_completion_model(:javascript), do: "codellama"
  defp get_completion_model(_), do: "llama2"

  defp get_completion_system_prompt(language) do
    """
    You are a code completion assistant for #{language}.
    Provide short, contextually relevant completions.
    Focus on completing the current expression or statement.
    Do not add unnecessary code or comments.
    """
  end

  defp parse_llm_completions(response, language) do
    content = get_in(response.choices, [Access.at(0), :message, "content"]) || ""

    content
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#") or String.starts_with?(&1, "//")))
    |> Enum.take(5)
    |> Enum.with_index()
    |> Enum.map(fn {text, index} ->
      %{
        text: text,
        # Higher score for earlier suggestions
        score: 1.0 - index * 0.1,
        type: detect_completion_type(text, language),
        metadata: %{
          source: :llm,
          model: response.model
        }
      }
    end)
  end

  defp detect_completion_type(text, :elixir) do
    cond do
      String.contains?(text, "def ") -> :function
      String.contains?(text, ["import ", "alias ", "use "]) -> :import
      String.match?(text, ~r/^[a-z_]/) -> :variable
      String.match?(text, ~r/^[A-Z]/) -> :module
      true -> :other
    end
  end

  defp detect_completion_type(text, _language) do
    cond do
      String.contains?(text, ["(", ")"]) -> :function
      String.contains?(text, ["import", "require", "include"]) -> :import
      true -> :other
    end
  end

  defp generate_cache_key(input) do
    # Create a unique key based on context
    data = "#{input.prefix}|#{input.suffix}|#{input.language}"
    :crypto.hash(:sha256, data) |> Base.encode16()
  end

  defp get_from_cache(%{cache: cache, cache_expiry: expiry}, key) do
    case Map.get(cache, key) do
      nil ->
        :miss

      value ->
        if DateTime.compare(DateTime.utc_now(), Map.get(expiry, key)) == :lt do
          {:ok, value}
        else
          :miss
        end
    end
  end

  defp update_cache(state, key, value) do
    ttl = Keyword.get(state.config, :cache_ttl, @default_cache_ttl)
    expiry_time = DateTime.add(DateTime.utc_now(), ttl, :millisecond)

    %{state | cache: Map.put(state.cache, key, value), cache_expiry: Map.put(state.cache_expiry, key, expiry_time)}
  end

  defp generate_elixir_completions(context, input, state) do
    cursor_context = context.cursor_context

    completions = []

    # Check if we're in a case statement context
    in_case =
      String.contains?(context.prefix_context, "case") and
        String.match?(cursor_context.current_line, ~r/^\s*$/)

    if in_case do
      # Just return pattern completions for case statements
      apply_language_rules(generate_pattern_completions(cursor_context, input), :elixir, state)
    else
      # Function completion
      completions = completions ++ generate_function_completions(cursor_context, input)

      # Module completion
      completions = completions ++ generate_module_completions(cursor_context, input)

      # Variable completion
      completions = completions ++ generate_variable_completions(context, input)

      # Pattern matching completion
      completions = completions ++ generate_pattern_completions(cursor_context, input)

      # Apply language-specific rules
      apply_language_rules(completions, :elixir, state)
    end
  end

  defp generate_function_completions(%{last_token: token, current_line: line}, _input) do
    # Simple function name suggestions based on common patterns
    suggestions =
      cond do
        String.starts_with?(token, "get_") or token == "get_" ->
          [
            %{text: "get_by_id(id)", score: 0.9, type: :function, metadata: %{snippet: true}},
            %{text: "get_all()", score: 0.8, type: :function, metadata: %{snippet: true}},
            %{text: "get_by(filters)", score: 0.7, type: :function, metadata: %{snippet: true}}
          ]

        String.starts_with?(token, "create_") ->
          [
            %{text: "create(attrs)", score: 0.9, type: :function, metadata: %{snippet: true}},
            %{text: "create!(attrs)", score: 0.8, type: :function, metadata: %{snippet: true}}
          ]

        String.starts_with?(token, "update_") ->
          [
            %{text: "update(record, attrs)", score: 0.9, type: :function, metadata: %{snippet: true}},
            %{text: "update!(record, attrs)", score: 0.8, type: :function, metadata: %{snippet: true}}
          ]

        String.ends_with?(token, "?") ->
          [
            %{text: "#{token}(value)", score: 0.8, type: :function, metadata: %{predicate: true}}
          ]

        # Suggest predicate for is_ prefix
        String.starts_with?(token, "is_") ->
          [
            %{text: "#{token}?(value)", score: 0.9, type: :function, metadata: %{predicate: true}},
            %{text: "#{token}?()", score: 0.8, type: :function, metadata: %{predicate: true}}
          ]

        # When just starting to type a function name
        String.match?(line, ~r/^\s*def\s+\w*$/) ->
          [
            %{text: "#{token}_by_id(id)", score: 0.7, type: :function, metadata: %{snippet: true}},
            %{text: "#{token}_all()", score: 0.6, type: :function, metadata: %{snippet: true}},
            %{text: "#{token}(params)", score: 0.5, type: :function, metadata: %{snippet: true}}
          ]

        # Default suggestions for any token
        String.length(token) > 0 ->
          [
            %{text: "#{token}()", score: 0.6, type: :function, metadata: %{snippet: true}},
            %{text: "#{token}(params)", score: 0.5, type: :function, metadata: %{snippet: true}}
          ]

        true ->
          []
      end

    suggestions
  end

  defp generate_module_completions(%{last_token: token}, _input) do
    # Module name completions
    cond do
      String.match?(token, ~r/^[A-Z]/) ->
        # Could integrate with project analysis here
        [
          %{text: "#{token}.Module", score: 0.7, type: :module, metadata: %{}},
          %{text: "#{token}.Server", score: 0.6, type: :module, metadata: %{}}
        ]

      true ->
        []
    end
  end

  defp generate_variable_completions(context, _input) do
    # Extract variables from context
    variables = extract_variables_from_context(context.prefix_context)

    variables
    |> Enum.map(fn var ->
      %{text: var, score: 0.6, type: :variable, metadata: %{}}
    end)
  end

  defp extract_variables_from_context(context) do
    # Simple variable extraction
    ~r/(\w+)\s*=/
    |> Regex.scan(context)
    |> Enum.map(&List.last/1)
    |> Enum.uniq()
  end

  defp generate_pattern_completions(%{last_token: token, current_line: line} = _cursor_context, input) do
    # Also check the prefix for case context
    prefix = Map.get(input, :prefix, "")

    cond do
      String.contains?(line, "case") and String.contains?(line, "do") ->
        [
          %{text: "{:ok, result} ->", score: 0.9, type: :pattern, metadata: %{context: :case}},
          %{text: "{:error, reason} ->", score: 0.8, type: :pattern, metadata: %{context: :case}},
          %{text: "_ ->", score: 0.7, type: :pattern, metadata: %{context: :case}}
        ]

      # Match case statements where 'do' is on the next line
      String.match?(line, ~r/case\s+\w+\s*$/) ->
        [
          %{text: "{:ok, result} ->", score: 0.9, type: :pattern, metadata: %{context: :case}},
          %{text: "{:error, reason} ->", score: 0.8, type: :pattern, metadata: %{context: :case}},
          %{text: "_ ->", score: 0.7, type: :pattern, metadata: %{context: :case}}
        ]

      # Check if previous line has case...do
      String.match?(prefix, ~r/case\s+.*\s+do\s*\n\s*$/m) ->
        [
          %{text: "{:ok, result} ->", score: 0.9, type: :pattern, metadata: %{context: :case}},
          %{text: "{:error, reason} ->", score: 0.8, type: :pattern, metadata: %{context: :case}},
          %{text: "_ ->", score: 0.7, type: :pattern, metadata: %{context: :case}}
        ]

      String.contains?(line, "def") and String.ends_with?(token, "(") ->
        [
          %{text: "%{} = params)", score: 0.8, type: :pattern, metadata: %{context: :function_args}},
          %{text: "opts \\\\ [])", score: 0.7, type: :pattern, metadata: %{context: :function_args}}
        ]

      true ->
        []
    end
  end

  defp generate_javascript_completions(_context, _input, _state) do
    # Placeholder for JavaScript-specific completions
    []
  end

  defp generate_python_completions(_context, _input, _state) do
    # Placeholder for Python-specific completions
    []
  end

  defp generate_generic_completions(context, _input, _state) do
    # Generic completions based on context
    token = context.cursor_context.last_token

    if String.length(token) >= 2 do
      [
        %{text: token, score: 0.5, type: :other, metadata: %{generic: true}}
      ]
    else
      []
    end
  end

  defp apply_language_rules(completions, language, %{language_rules: rules}) do
    case Map.get(rules, language) do
      nil ->
        completions

      language_rules ->
        Enum.map(completions, fn completion ->
          apply_rules_to_completion(completion, language_rules)
        end)
    end
  end

  defp apply_rules_to_completion(completion, _rules) do
    # Apply specific language rules to adjust completion
    # For now, just return as-is
    completion
  end

  defp rank_completions(completions, input, state) do
    ranked =
      completions
      |> Enum.map(fn completion ->
        score = calculate_completion_score(completion, input, state)
        %{completion | score: score}
      end)
      |> Enum.sort_by(& &1.score, :desc)

    {:ok, ranked}
  end

  defp calculate_completion_score(completion, input, _state) do
    base_score = completion.score

    # Adjust score based on various factors
    adjustments = [
      context_relevance_adjustment(completion, input),
      type_preference_adjustment(completion, input),
      length_adjustment(completion),
      recency_adjustment(completion, input)
    ]

    final_score =
      Enum.reduce(adjustments, base_score, fn adj, score ->
        score * adj
      end)

    # Ensure score is between 0 and 1
    max(0.0, min(1.0, final_score))
  end

  defp context_relevance_adjustment(completion, input) do
    # Boost if completion matches patterns in context
    if String.contains?(input.prefix, completion.text) do
      # Penalize exact matches (likely already typed)
      0.8
    else
      1.0
    end
  end

  defp type_preference_adjustment(%{type: type}, _input) do
    # Prefer certain completion types
    case type do
      :function -> 1.2
      :pattern -> 1.1
      :variable -> 1.0
      :module -> 0.9
      _ -> 0.8
    end
  end

  defp length_adjustment(%{text: text}) do
    # Slight preference for reasonable length completions
    length = String.length(text)

    cond do
      length < 3 -> 0.8
      length > 50 -> 0.7
      true -> 1.0
    end
  end

  defp recency_adjustment(_completion, _input) do
    # Could boost recently used completions
    # For now, no adjustment
    1.0
  end

  defp filter_completions(completions, state) do
    min_confidence = Keyword.get(state.config, :min_confidence, @default_min_confidence)
    max_suggestions = Keyword.get(state.config, :max_suggestions, @default_max_suggestions)

    filtered =
      completions
      |> Enum.filter(fn %{score: score} -> score >= min_confidence end)
      |> Enum.take(max_suggestions)

    {:ok, filtered}
  end

  defp load_language_rules(config) do
    # Load language-specific rules from config or defaults
    Keyword.get(config, :language_rules, %{
      elixir: %{
        prefer_pipeline: true,
        suggest_specs: true,
        enforce_conventions: true
      },
      javascript: %{
        prefer_const: true,
        suggest_async: true
      },
      python: %{
        prefer_type_hints: true,
        suggest_docstrings: true
      }
    })
  end
end
