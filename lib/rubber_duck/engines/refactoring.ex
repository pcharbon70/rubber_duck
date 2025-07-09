defmodule RubberDuck.Engines.Refactoring do
  @moduledoc """
  Code refactoring engine that suggests and applies code improvements.

  This engine uses LLMs to:
  - Suggest refactoring opportunities
  - Apply specific refactoring patterns
  - Improve code readability and maintainability
  - Extract functions and modules
  - Rename variables and functions for clarity
  """

  @behaviour RubberDuck.Engine

  require Logger

  alias RubberDuck.LLM

  @impl true
  def init(config) do
    state = %{
      config: config,
      patterns: load_refactoring_patterns()
    }

    {:ok, state}
  end

  @impl true
  def execute(input, state) do
    with {:ok, validated} <- validate_input(input),
         {:ok, analysis} <- analyze_code_for_refactoring(validated, state),
         {:ok, suggestions} <- generate_refactoring_suggestions(analysis, validated, state),
         {:ok, result} <- apply_refactoring_if_requested(suggestions, validated, state) do
      {:ok, result}
    end
  end

  @impl true
  def capabilities do
    [:code_refactoring, :pattern_detection, :automated_fixes]
  end

  defp validate_input(%{file_path: path, instruction: instruction} = input)
       when is_binary(path) and is_binary(instruction) do
    content = read_file_content(path)
    language = detect_language(path)

    validated = %{
      file_path: path,
      content: content,
      instruction: instruction,
      language: language,
      apply_changes: Map.get(input, :apply_changes, false),
      diff_only: Map.get(input, :diff_only, false)
    }

    {:ok, validated}
  end

  defp validate_input(_), do: {:error, :invalid_input}

  defp read_file_content(path) do
    case File.read(path) do
      {:ok, content} -> content
      {:error, _} -> ""
    end
  end

  defp detect_language(path) do
    case Path.extname(path) do
      ".ex" -> :elixir
      ".exs" -> :elixir
      ".js" -> :javascript
      ".py" -> :python
      _ -> :unknown
    end
  end

  defp analyze_code_for_refactoring(input, _state) do
    # Analyze code structure
    analysis = %{
      functions: extract_functions(input.content, input.language),
      complexity: calculate_complexity(input.content),
      patterns: detect_patterns(input.content, input.language),
      code_smells: detect_code_smells(input.content)
    }

    {:ok, analysis}
  end

  defp extract_functions(content, :elixir) do
    ~r/def\s+(\w+).*?(?=\n\s*def|\n\s*defp|\z)/s
    |> Regex.scan(content)
    |> Enum.map(fn [full_match, name] ->
      %{
        name: name,
        body: full_match,
        length: count_lines(full_match)
      }
    end)
  end

  defp extract_functions(_content, _language), do: []

  defp calculate_complexity(content) do
    # Simple complexity metrics
    lines = String.split(content, "\n")

    %{
      total_lines: length(lines),
      max_nesting: calculate_max_nesting(lines),
      cyclomatic_complexity: estimate_cyclomatic_complexity(content)
    }
  end

  defp calculate_max_nesting(lines) do
    lines
    |> Enum.map(&calculate_indentation/1)
    |> Enum.max(fn -> 0 end)
    |> div(2)
  end

  defp calculate_indentation(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, spaces] -> String.length(spaces)
      _ -> 0
    end
  end

  defp estimate_cyclomatic_complexity(content) do
    # Count decision points
    decision_keywords = ~r/\b(if|unless|case|cond|try|rescue|catch)\b/

    Regex.scan(decision_keywords, content)
    |> length()
    # Base complexity
    |> Kernel.+(1)
  end

  defp detect_patterns(content, language) do
    patterns = []

    # Detect common patterns that could be refactored
    if String.contains?(content, ["if", "else"]) and
         Regex.match?(~r/if.*?\n.*?else.*?\n.*?end/s, content) do
      patterns ++ [:nested_conditionals]
    else
      patterns
    end
  end

  defp detect_code_smells(content) do
    smells = []

    # Long parameter lists
    if Regex.match?(~r/def\s+\w+\([^)]{50,}\)/, content) do
      smells ++ [:long_parameter_list]
    else
      smells
    end
  end

  defp generate_refactoring_suggestions(analysis, input, state) do
    # Use LLM to generate refactoring suggestions
    prompt = build_refactoring_prompt(analysis, input)

    request = %LLM.Request{
      model: get_refactoring_model(input.language),
      messages: [
        %{"role" => "system", "content" => get_refactoring_system_prompt(input.language)},
        %{"role" => "user", "content" => prompt}
      ],
      options: %{
        temperature: 0.4,
        max_tokens: state.config[:max_tokens] || 4096
      }
    }

    case LLM.Service.chat(request) do
      {:ok, response} ->
        parse_refactoring_response(response, input)

      {:error, reason} ->
        Logger.warning("LLM refactoring failed: #{inspect(reason)}")
        generate_fallback_suggestions(analysis, input)
    end
  end

  defp build_refactoring_prompt(analysis, input) do
    """
    Refactor the following #{input.language} code according to this instruction:
    "#{input.instruction}"

    Current code:
    ```#{input.language}
    #{input.content}
    ```

    Code analysis:
    - Total lines: #{analysis.complexity.total_lines}
    - Max nesting level: #{analysis.complexity.max_nesting}
    - Cyclomatic complexity: #{analysis.complexity.cyclomatic_complexity}
    - Detected patterns: #{inspect(analysis.patterns)}
    - Code smells: #{inspect(analysis.code_smells)}

    Please provide:
    1. The refactored code
    2. A list of changes made
    3. Explanation of improvements

    Focus on the specific instruction while also addressing any obvious code quality issues.
    """
  end

  defp get_refactoring_model(:elixir), do: "codellama"
  defp get_refactoring_model(:python), do: "codellama"
  defp get_refactoring_model(:javascript), do: "codellama"
  defp get_refactoring_model(_), do: "llama2"

  defp get_refactoring_system_prompt(language) do
    """
    You are an expert #{language} developer specializing in code refactoring.
    Apply clean code principles and #{language}-specific best practices.
    Make the code more readable, maintainable, and efficient.
    Preserve all functionality while improving structure.
    """
  end

  defp parse_refactoring_response(response, input) do
    content = get_in(response.choices, [Access.at(0), :message, "content"]) || ""

    # Extract refactored code
    refactored_code = extract_code_block(content, input.language)

    # Extract changes and explanation
    changes = extract_changes_list(content)
    explanation = extract_explanation(content)

    result = %{
      original_code: input.content,
      refactored_code: refactored_code,
      changes: changes,
      explanation: explanation,
      diff: generate_diff(input.content, refactored_code)
    }

    {:ok, result}
  end

  defp extract_code_block(content, language) do
    case Regex.run(~r/```#{language}?\n(.*?)```/s, content) do
      [_, code] ->
        String.trim(code)

      _ ->
        # Try generic code block
        case Regex.run(~r/```\n(.*?)```/s, content) do
          [_, code] -> String.trim(code)
          # Return full content if no code blocks
          _ -> content
        end
    end
  end

  defp extract_changes_list(content) do
    # Extract bullet points after "changes" or similar keywords
    case Regex.run(~r/(?:changes|improvements|modifications):\s*\n((?:[-*]\s*.+\n?)+)/i, content) do
      [_, changes_text] ->
        changes_text
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&String.starts_with?(&1, ["-", "*"]))
        |> Enum.map(&String.trim(&1, "- "))
        |> Enum.map(&String.trim(&1, "* "))

      _ ->
        []
    end
  end

  defp extract_explanation(content) do
    # Extract explanation section
    sections = String.split(content, ~r/```.*?```/s)

    explanation_section =
      Enum.find(sections, fn section ->
        String.contains?(String.downcase(section), ["explanation", "improvements", "benefits"])
      end)

    if explanation_section do
      explanation_section
      |> String.trim()
      |> String.slice(0..500)
    else
      "Code has been refactored according to the instruction."
    end
  end

  defp generate_diff(original, refactored) do
    # Simple line-based diff
    original_lines = String.split(original, "\n")
    refactored_lines = String.split(refactored, "\n")

    max_lines = max(length(original_lines), length(refactored_lines))

    0..(max_lines - 1)
    |> Enum.map(fn i ->
      orig_line = Enum.at(original_lines, i, "")
      ref_line = Enum.at(refactored_lines, i, "")

      cond do
        orig_line == ref_line -> "  #{orig_line}"
        orig_line == "" -> "+ #{ref_line}"
        ref_line == "" -> "- #{orig_line}"
        true -> "- #{orig_line}\n+ #{ref_line}"
      end
    end)
    |> Enum.join("\n")
  end

  defp generate_fallback_suggestions(analysis, input) do
    # Rule-based fallback suggestions
    suggestions = []

    if analysis.complexity.max_nesting > 3 do
      suggestions ++ ["Reduce nesting by extracting functions or using guard clauses"]
    end

    if :long_parameter_list in analysis.code_smells do
      suggestions ++ ["Consider using a configuration struct instead of many parameters"]
    end

    {:ok,
     %{
       original_code: input.content,
       # No changes in fallback
       refactored_code: input.content,
       changes: [],
       explanation: "Automated refactoring unavailable. Consider: #{Enum.join(suggestions, "; ")}",
       diff: ""
     }}
  end

  defp apply_refactoring_if_requested(result, input, _state) do
    cond do
      input.diff_only ->
        # Return only the diff
        {:ok, %{diff: result.diff, explanation: result.explanation}}

      input.apply_changes ->
        # Write the refactored code back to the file
        case File.write(input.file_path, result.refactored_code) do
          :ok ->
            {:ok, Map.put(result, :applied, true)}

          {:error, reason} ->
            {:error, {:write_failed, reason}}
        end

      true ->
        # Return full result without applying
        {:ok, result}
    end
  end

  defp count_lines(text) do
    text
    |> String.split("\n")
    |> length()
  end

  defp load_refactoring_patterns do
    # Load common refactoring patterns
    %{
      extract_function: "Extract repeated code into a function",
      inline_variable: "Inline single-use variables",
      rename_variable: "Rename variables for clarity",
      simplify_conditional: "Simplify complex conditionals"
    }
  end
end
