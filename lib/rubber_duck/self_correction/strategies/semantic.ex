defmodule RubberDuck.SelfCorrection.Strategies.Semantic do
  @moduledoc """
  Semantic consistency and clarity correction strategy.

  Focuses on meaning, clarity, coherence, and appropriate
  language use in both code and text content.
  """

  @behaviour RubberDuck.SelfCorrection.Strategy

  import RubberDuck.SelfCorrection.Strategy

  @impl true
  def name(), do: :semantic

  @impl true
  def supported_types(), do: [:code, :text, :mixed]

  @impl true
  # Lower than syntax but still important
  def priority(), do: 80

  @impl true
  def analyze(content, type, context, evaluation) do
    issues = detect_semantic_issues(content, type, context, evaluation)
    corrections = generate_semantic_corrections(content, issues, type, context)

    %{
      strategy: :semantic,
      issues: issues,
      corrections: corrections,
      confidence: calculate_semantic_confidence(issues, corrections, evaluation),
      metadata: %{
        content_type: type,
        checks_performed: [:clarity, :consistency, :naming, :coherence]
      }
    }
  end

  @impl true
  def validate_correction(content, correction) do
    # Validate that semantic corrections maintain meaning
    if preserves_intent?(content, correction) do
      {:ok, correction}
    else
      {:error, "Correction may alter intended meaning"}
    end
  end

  # Private functions

  defp detect_semantic_issues(content, type, context, evaluation) do
    base_issues =
      case type do
        :code -> detect_code_semantic_issues(content, context)
        :text -> detect_text_semantic_issues(content, context)
        :mixed -> detect_mixed_semantic_issues(content, context)
      end

    # Add issues based on evaluation scores
    base_issues ++ detect_evaluation_based_issues(content, evaluation)
  end

  defp detect_code_semantic_issues(content, context) do
    language = context[:language] || detect_language(content)

    _issues = []

    # Variable naming issues
    issues = check_variable_naming(content, language)

    # Function naming and purpose clarity
    issues = issues ++ check_function_clarity(content, language)

    # Code comments and documentation
    issues = issues ++ check_documentation_quality(content, language)

    # Consistency in style and patterns
    issues = issues ++ check_style_consistency(content, language)

    # Dead code detection
    issues = issues ++ check_dead_code(content, language)

    issues
  end

  defp detect_text_semantic_issues(content, _context) do
    _issues = []

    # Check for clarity and coherence
    issues = check_text_clarity(content)

    # Check for redundancy
    issues = issues ++ check_redundancy(content)

    # Check for ambiguous references
    issues = issues ++ check_ambiguous_references(content)

    # Check for consistency in terminology
    issues = issues ++ check_terminology_consistency(content)

    issues
  end

  defp detect_mixed_semantic_issues(content, context) do
    # Split into code and text sections
    {code_sections, text_sections} = split_mixed_content(content)

    code_issues =
      Enum.flat_map(code_sections, fn {code, loc} ->
        detect_code_semantic_issues(code, context)
        |> Enum.map(fn issue -> Map.update!(issue, :location, &Map.merge(&1, loc)) end)
      end)

    text_issues =
      Enum.flat_map(text_sections, fn {text, loc} ->
        detect_text_semantic_issues(text, context)
        |> Enum.map(fn issue -> Map.update!(issue, :location, &Map.merge(&1, loc)) end)
      end)

    code_issues ++ text_issues
  end

  defp detect_evaluation_based_issues(_content, evaluation) do
    issues = []

    # Check clarity score
    _issues =
      if Map.get(evaluation, :clarity_score, 1.0) < 0.7 do
        [
          issue(:low_clarity, :warning, "Content clarity is below threshold", %{}, %{
            clarity_score: evaluation.clarity_score
          })
          | issues
        ]
      else
        issues
      end

    # Check coherence
    _issues =
      if Map.get(evaluation, :coherence_score, 1.0) < 0.7 do
        [
          issue(:low_coherence, :warning, "Content coherence needs improvement", %{}, %{
            coherence_score: evaluation.coherence_score
          })
          | issues
        ]
      else
        issues
      end

    issues
  end

  defp check_variable_naming(content, "elixir") do
    # Check for non-idiomatic variable names in Elixir
    _issues = []

    # Single letter variables (except in specific contexts)
    single_letter_pattern = ~r/\b([a-z])\s*=/
    matches = Regex.scan(single_letter_pattern, content)

    issues =
      if length(matches) > 2 do
        [issue(:poor_variable_naming, :warning, "Multiple single-letter variables detected", %{})]
      else
        []
      end

    # Non-snake_case variables
    camelcase_pattern = ~r/\b([a-z]+[A-Z][a-zA-Z]*)\s*=/

    issues =
      issues ++
        if Regex.match?(camelcase_pattern, content) do
          [issue(:naming_convention, :warning, "Variables should use snake_case in Elixir", %{})]
        else
          []
        end

    issues
  end

  defp check_variable_naming(content, _language) do
    # Generic variable naming checks
    vague_names = ["data", "temp", "var", "val", "obj", "item"]

    issues =
      Enum.flat_map(vague_names, fn name ->
        pattern = Regex.compile!("\\b#{name}\\d*\\s*=")

        if Regex.match?(pattern, content) do
          [issue(:vague_variable_name, :info, "Variable name '#{name}' is too generic", %{})]
        else
          []
        end
      end)

    issues
  end

  defp check_function_clarity(content, "elixir") do
    # Check for unclear function names and missing docs
    _issues = []

    # Functions without documentation
    function_pattern = ~r/^\s*def\s+([a-z_]+)/m
    functions = Regex.scan(function_pattern, content, capture: :all_but_first)

    Enum.flat_map(functions, fn [func_name] ->
      # Check if function has doc above it
      doc_pattern = Regex.compile!("@doc\\s+[\"'].*?[\"']\\s*\\n\\s*def\\s+#{func_name}")

      if !Regex.match?(doc_pattern, content) && String.length(func_name) > 5 do
        [issue(:missing_documentation, :info, "Function '#{func_name}' lacks documentation", %{})]
      else
        []
      end
    end)
  end

  defp check_function_clarity(_content, _language), do: []

  defp check_documentation_quality(content, _language) do
    _issues = []

    # Check for TODO/FIXME comments
    todo_pattern = ~r/(TODO|FIXME|HACK|XXX):/i
    todos = Regex.scan(todo_pattern, content)

    issues =
      if length(todos) > 3 do
        [issue(:excessive_todos, :warning, "Multiple TODO/FIXME comments found", %{}, %{count: length(todos)})]
      else
        []
      end

    # Check for commented out code
    commented_code_lines =
      content
      |> String.split("\n")
      |> Enum.count(fn line ->
        trimmed = String.trim(line)

        String.starts_with?(trimmed, "#") &&
          Regex.match?(~r/[=\(\{]/, trimmed)
      end)

    issues =
      issues ++
        if commented_code_lines > 5 do
          [
            issue(:commented_code, :warning, "Excessive commented-out code detected", %{}, %{
              lines: commented_code_lines
            })
          ]
        else
          []
        end

    issues
  end

  defp check_style_consistency(content, "elixir") do
    _issues = []

    # Check for inconsistent pipeline usage
    lines = String.split(content, "\n")

    # Count different styles
    nested_calls = Enum.count(lines, &Regex.match?(~r/\w+\(\w+\(\w+\(/, &1))
    pipelines = Enum.count(lines, &String.contains?(&1, "|>"))

    issues =
      if nested_calls > 3 && pipelines > 0 do
        [issue(:inconsistent_style, :info, "Inconsistent use of pipelines vs nested function calls", %{})]
      else
        []
      end

    issues
  end

  defp check_style_consistency(_content, _language), do: []

  defp check_dead_code(content, _language) do
    # Check for unreachable code patterns

    # Check for unreachable code patterns
    unreachable_patterns = [
      # Code after return
      ~r/return.*\n\s*\w+/,
      # Code after raise
      ~r/raise.*\n\s*\w+/,
      # Code after throw
      ~r/throw.*\n\s*\w+/
    ]

    Enum.flat_map(unreachable_patterns, fn pattern ->
      if Regex.match?(pattern, content) do
        [issue(:unreachable_code, :warning, "Potentially unreachable code detected", %{})]
      else
        []
      end
    end)
  end

  defp check_text_clarity(content) do
    _issues = []

    # Check sentence length
    sentences = String.split(content, ~r/[.!?]+/)

    long_sentences =
      Enum.filter(sentences, fn s ->
        word_count = length(String.split(s, ~r/\s+/))
        word_count > 40
      end)

    issues =
      if length(long_sentences) > 0 do
        [issue(:long_sentences, :info, "#{length(long_sentences)} sentences are too long (>40 words)", %{})]
      else
        []
      end

    # Check for passive voice (simple heuristic)
    passive_pattern = ~r/\b(was|were|been|being|is|are|am)\s+\w+ed\b/
    passive_matches = Regex.scan(passive_pattern, content)

    issues =
      issues ++
        if length(passive_matches) > 5 do
          [issue(:passive_voice, :info, "Excessive use of passive voice", %{}, %{count: length(passive_matches)})]
        else
          []
        end

    issues
  end

  defp check_redundancy(content) do
    # Check for repeated phrases
    words = String.split(String.downcase(content), ~r/\s+/)

    # Find 3-word phrases that repeat
    trigrams =
      words
      |> Enum.chunk_every(3, 1, :discard)
      |> Enum.map(&Enum.join(&1, " "))
      |> Enum.frequencies()
      |> Enum.filter(fn {_, count} -> count > 2 end)

    if map_size(trigrams) > 0 do
      repeated = trigrams |> Map.keys() |> Enum.take(3) |> Enum.join(", ")
      [issue(:redundancy, :info, "Repeated phrases detected: #{repeated}", %{})]
    else
      []
    end
  end

  defp check_ambiguous_references(content) do
    # Check for ambiguous pronouns
    pronouns = ["it", "this", "that", "they", "them"]

    Enum.flat_map(pronouns, fn pronoun ->
      pattern = Regex.compile!("\\b#{pronoun}\\b", "i")
      matches = Regex.scan(pattern, content)

      if length(matches) > 5 do
        [
          issue(:ambiguous_reference, :info, "Frequent use of ambiguous pronoun '#{pronoun}'", %{}, %{
            count: length(matches)
          })
        ]
      else
        []
      end
    end)
  end

  defp check_terminology_consistency(content) do
    # Check for inconsistent terminology
    term_variations = [
      ["function", "method", "procedure"],
      ["parameter", "argument", "param"],
      ["return", "output", "result"]
    ]

    Enum.flat_map(term_variations, fn terms ->
      used_terms =
        Enum.filter(terms, fn term ->
          Regex.match?(Regex.compile!("\\b#{term}\\b", "i"), content)
        end)

      if length(used_terms) > 1 do
        [issue(:inconsistent_terminology, :info, "Inconsistent use of terms: #{Enum.join(used_terms, ", ")}", %{})]
      else
        []
      end
    end)
  end

  defp generate_semantic_corrections(content, issues, type, context) do
    # For semantic issues, we'll use LLM assistance for corrections
    high_priority_issues =
      Enum.filter(issues, fn issue ->
        issue.severity in [:error, :warning]
      end)

    if length(high_priority_issues) > 0 do
      suggest_llm_corrections(content, high_priority_issues, type, context)
    else
      []
    end
  end

  defp suggest_llm_corrections(_content, issues, _type, _context) do
    # Group similar issues
    grouped_issues = Enum.group_by(issues, & &1.type)

    Enum.map(grouped_issues, fn {issue_type, _issue_list} ->
      case issue_type do
        :poor_variable_naming ->
          correction(
            :improve_naming,
            "Improve variable naming for clarity",
            # LLM will provide specific changes
            [],
            0.7,
            :medium
          )

        :missing_documentation ->
          correction(
            :add_documentation,
            "Add missing documentation",
            [],
            0.8,
            :medium
          )

        :long_sentences ->
          correction(
            :split_sentences,
            "Split long sentences for better readability",
            [],
            0.6,
            :low
          )

        _ ->
          correction(
            :general_improvement,
            "Improve #{issue_type}",
            [],
            0.5,
            :low
          )
      end
    end)
  end

  defp calculate_semantic_confidence(issues, corrections, evaluation) do
    base_score = Map.get(evaluation, :overall_score, 0.7)

    # Adjust based on issue severity
    issue_penalty =
      Enum.reduce(issues, 0, fn issue, acc ->
        case issue.severity do
          :error -> acc + 0.1
          :warning -> acc + 0.05
          :info -> acc + 0.02
        end
      end)

    # Boost for available corrections
    correction_boost = length(corrections) * 0.05

    max(0.0, min(1.0, base_score - issue_penalty + correction_boost))
  end

  defp preserves_intent?(_content, correction) do
    # For now, assume LLM-suggested corrections preserve intent
    # In production, this would involve more sophisticated analysis
    correction.confidence > 0.6
  end

  defp detect_language(content) do
    cond do
      String.contains?(content, ["defmodule", "def ", "defp"]) -> "elixir"
      String.contains?(content, ["function", "const", "=>"]) -> "javascript"
      String.contains?(content, ["def ", "class ", "import"]) -> "python"
      true -> "unknown"
    end
  end

  defp split_mixed_content(content) do
    # Simple splitting - in production, use more sophisticated parsing
    lines = String.split(content, "\n")

    {code_sections, text_sections, _, _, _} =
      Enum.reduce(lines, {[], [], :text, [], 0}, fn line, {code, text, mode, current, line_num} ->
        cond do
          String.starts_with?(line, "```") && mode == :text ->
            # Start of code block
            {code, [{Enum.join(current, "\n"), %{start_line: line_num - length(current)}} | text], :code, [],
             line_num + 1}

          String.starts_with?(line, "```") && mode == :code ->
            # End of code block
            {[{Enum.join(current, "\n"), %{start_line: line_num - length(current)}} | code], text, :text, [],
             line_num + 1}

          true ->
            {code, text, mode, current ++ [line], line_num + 1}
        end
      end)

    {Enum.reverse(code_sections), Enum.reverse(text_sections)}
  end
end
