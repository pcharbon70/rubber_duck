defmodule RubberDuck.SelfCorrection.Evaluator do
  @moduledoc """
  Evaluates content quality across multiple dimensions.

  Provides comprehensive quality assessment that guides
  the self-correction process.
  """

  @type evaluation_result :: %{
          overall_score: float(),
          dimensions: %{
            syntax: float(),
            semantics: float(),
            logic: float(),
            clarity: float(),
            completeness: float(),
            coherence: float()
          },
          metadata: map(),
          reasoning_chain: map() | nil
        }

  @doc """
  Evaluates content quality across multiple dimensions.

  Returns a comprehensive evaluation that can guide correction strategies.
  """
  @spec evaluate(String.t(), atom(), map(), map()) :: evaluation_result()
  def evaluate(content, type, context, _strategies \\ %{}) do
    # Perform base evaluation
    base_eval = perform_base_evaluation(content, type, context)

    # Add specialized evaluations based on type
    enhanced_eval =
      case type do
        :code -> enhance_with_code_evaluation(base_eval, content, context)
        :text -> enhance_with_text_evaluation(base_eval, content, context)
        :mixed -> enhance_with_mixed_evaluation(base_eval, content, context)
      end

    # Calculate overall score
    Map.put(enhanced_eval, :overall_score, calculate_overall_score(enhanced_eval))
  end

  @doc """
  Compares two evaluations to determine improvement.
  """
  @spec compare_evaluations(evaluation_result(), evaluation_result()) :: map()
  def compare_evaluations(eval1, eval2) do
    %{
      overall_improvement: eval2.overall_score - eval1.overall_score,
      dimension_improvements: compare_dimensions(eval1.dimensions, eval2.dimensions),
      improved: eval2.overall_score > eval1.overall_score,
      convergence_delta: abs(eval2.overall_score - eval1.overall_score)
    }
  end

  @doc """
  Determines if content meets quality threshold.
  """
  @spec meets_threshold?(evaluation_result(), float()) :: boolean()
  def meets_threshold?(evaluation, threshold \\ 0.8) do
    evaluation.overall_score >= threshold
  end

  # Private functions

  defp perform_base_evaluation(content, _type, _context) do
    %{
      dimensions: %{
        syntax: evaluate_syntax_quality(content),
        semantics: evaluate_semantic_quality(content),
        logic: evaluate_logical_quality(content),
        clarity: evaluate_clarity(content),
        completeness: evaluate_completeness(content),
        coherence: evaluate_coherence(content)
      },
      metadata: %{
        content_length: String.length(content),
        line_count: length(String.split(content, "\n")),
        evaluated_at: DateTime.utc_now()
      }
    }
  end

  defp evaluate_syntax_quality(content) do
    # Basic syntax quality evaluation
    _issues = []

    # Check for balanced delimiters
    delimiter_pairs = [{"(", ")"}, {"{", "}"}, {"[", "]"}, {"\"", "\""}, {"'", "'"}]

    balanced =
      Enum.all?(delimiter_pairs, fn {open, close} ->
        open_count = count_occurrences(content, open)
        close_count = count_occurrences(content, close)

        if open == close do
          rem(open_count, 2) == 0
        else
          open_count == close_count
        end
      end)

    # Check for common syntax patterns
    has_proper_spacing = !Regex.match?(~r/\w\(|\)\w/, content)
    has_consistent_quotes = !Regex.match?(~r/["'][^"']*["']/, content)

    # Calculate score
    base_score = if balanced, do: 0.7, else: 0.3
    spacing_bonus = if has_proper_spacing, do: 0.15, else: 0
    quotes_bonus = if has_consistent_quotes, do: 0.15, else: 0

    min(1.0, base_score + spacing_bonus + quotes_bonus)
  end

  defp evaluate_semantic_quality(content) do
    # Evaluate semantic clarity and consistency

    # Check for meaningful variable/function names (if code)
    good_naming =
      if Regex.match?(~r/def|function|class/, content) do
        # Check for descriptive names
        !Regex.match?(~r/\b[a-z]\s*[=\(]|\bvar\d+\b|\btemp\d*\b/, content)
      else
        true
      end

    # Check for clear language
    words = String.split(content, ~r/\s+/)

    avg_word_length =
      if length(words) > 0 do
        Enum.sum(Enum.map(words, &String.length/1)) / length(words)
      else
        0
      end

    # Reasonable word length indicates clarity
    clarity_score =
      cond do
        # Too simple
        avg_word_length < 3 -> 0.5
        # Too complex
        avg_word_length > 12 -> 0.6
        true -> 0.8
      end

    naming_bonus = if good_naming, do: 0.2, else: 0

    min(1.0, clarity_score + naming_bonus)
  end

  defp evaluate_logical_quality(content) do
    # Evaluate logical consistency

    # Check for obvious logical issues
    has_contradictions = Regex.match?(~r/always.*never|true.*false.*same/i, content)
    has_tautologies = Regex.match?(~r/if\s+true|while\s+true/, content)

    # Check for proper control flow
    if Regex.match?(~r/if|while|for|case/, content) do
      # Code logic checks
      has_unreachable = Regex.match?(~r/return.*\n\s*\w+|break.*\n\s*\w+/, content)

      has_infinite_loop =
        Regex.match?(~r/while\s*\(\s*true\s*\)|loop\s*do/, content) &&
          !Regex.match?(~r/break|return/, content)

      base = 0.7
      base = if has_contradictions, do: base - 0.2, else: base
      base = if has_tautologies, do: base - 0.1, else: base
      base = if has_unreachable, do: base - 0.15, else: base
      base = if has_infinite_loop, do: base - 0.25, else: base

      max(0.1, base)
    else
      # Text logic checks
      if has_contradictions, do: 0.5, else: 0.85
    end
  end

  defp evaluate_clarity(content) do
    # Evaluate clarity and readability

    sentences = String.split(content, ~r/[.!?]+/)

    # Average sentence length
    avg_sentence_length =
      if length(sentences) > 0 do
        total_words =
          Enum.sum(
            Enum.map(sentences, fn s ->
              length(String.split(s, ~r/\s+/))
            end)
          )

        total_words / length(sentences)
      else
        0
      end

    # Clarity scoring based on sentence length
    clarity_score =
      cond do
        # Too terse
        avg_sentence_length < 5 -> 0.6
        # Too complex
        avg_sentence_length > 30 -> 0.5
        # Getting long
        avg_sentence_length > 20 -> 0.7
        # Good range
        true -> 0.9
      end

    # Check for unclear references
    unclear_refs = Regex.scan(~r/\b(it|this|that|they)\b/i, content) |> length()
    ref_penalty = min(0.2, unclear_refs * 0.02)

    max(0.3, clarity_score - ref_penalty)
  end

  defp evaluate_completeness(content) do
    # Evaluate if content appears complete

    # Check for incomplete patterns
    incomplete_patterns = [
      # Trailing ellipsis
      ~r/\.\.\.$/,
      ~r/TODO|FIXME|XXX/,
      ~r/\betc\b\.?$/,
      ~r/and so on$/
    ]

    incomplete_count = Enum.count(incomplete_patterns, &Regex.match?(&1, content))

    # Check for proper endings
    has_proper_ending = Regex.match?(~r/[.!?]\s*$/, String.trim(content))

    # For code, check for balanced blocks
    if Regex.match?(~r/def|function|class|if|while/, content) do
      open_blocks = Regex.scan(~r/\bdo\b|\{/, content) |> length()
      close_blocks = Regex.scan(~r/\bend\b|\}/, content) |> length()
      balanced = open_blocks == close_blocks

      base = if balanced, do: 0.8, else: 0.4
      base = base - incomplete_count * 0.1
      max(0.2, base)
    else
      # Text completeness
      base = if has_proper_ending, do: 0.9, else: 0.7
      base - incomplete_count * 0.15
    end
  end

  defp evaluate_coherence(content) do
    # Evaluate overall coherence and flow

    lines = String.split(content, "\n")

    # Check for consistent indentation (if code)
    if Regex.match?(~r/^\s{2,}/, content) do
      indentations =
        lines
        |> Enum.map(&count_leading_spaces/1)
        |> Enum.filter(&(&1 > 0))

      if length(indentations) > 0 do
        # Check if indentations are multiples of a common factor
        gcd = Enum.reduce(indentations, 0, &Integer.gcd/2)
        consistent_indents = gcd > 1 && Enum.all?(indentations, &(rem(&1, gcd) == 0))

        if consistent_indents, do: 0.9, else: 0.6
      else
        0.8
      end
    else
      # Text coherence - check for topic consistency
      # Simple heuristic: repeated key terms indicate focus
      words =
        content
        |> String.downcase()
        |> String.split(~r/\W+/)
        |> Enum.filter(&(String.length(&1) > 4))

      if length(words) > 10 do
        frequencies = Enum.frequencies(words)
        repeated_terms = Enum.count(frequencies, fn {_, count} -> count > 1 end)

        repetition_ratio = repeated_terms / length(Enum.uniq(words))

        cond do
          # Too scattered
          repetition_ratio < 0.1 -> 0.6
          # Too repetitive
          repetition_ratio > 0.5 -> 0.7
          # Good balance
          true -> 0.85
        end
      else
        # Default for short content
        0.7
      end
    end
  end

  defp enhance_with_code_evaluation(eval, content, context) do
    # Add code-specific evaluations
    _language = context[:language] || detect_language(content)

    # For now, calculate a simple code score based on dimensions
    # In production, this would integrate with the Context.Scorer
    code_score = (eval.dimensions.syntax + eval.dimensions.semantics + eval.dimensions.logic) / 3.0

    put_in(eval, [:metadata, :code_score], code_score)
  end

  defp enhance_with_text_evaluation(eval, content, _context) do
    # Add text-specific evaluations

    # Readability metrics
    sentences = String.split(content, ~r/[.!?]+/)
    words = String.split(content, ~r/\s+/)

    flesch_score =
      if length(sentences) > 0 && length(words) > 0 do
        avg_sentence_length = length(words) / length(sentences)
        avg_syllables = estimate_avg_syllables(words)

        # Flesch Reading Ease formula (simplified)
        206.835 - 1.015 * avg_sentence_length - 84.6 * avg_syllables
      else
        50.0
      end

    # Normalize to 0-1 range
    readability = max(0, min(100, flesch_score)) / 100

    eval
    |> put_in([:metadata, :readability], readability)
    |> put_in([:dimensions, :readability], readability)
  end

  defp enhance_with_mixed_evaluation(eval, content, _context) do
    # For mixed content, evaluate both aspects
    {code_parts, _text_parts} = split_mixed_content(content)

    # Weight scores based on content proportion
    total_length = String.length(content)

    code_weight =
      if total_length > 0 do
        code_length = Enum.sum(Enum.map(code_parts, &String.length/1))
        code_length / total_length
      else
        0
      end

    text_weight = 1 - code_weight

    eval
    |> put_in([:metadata, :content_mix], %{code: code_weight, text: text_weight})
  end

  defp calculate_overall_score(evaluation) do
    dimensions = evaluation.dimensions

    # Weighted average of dimensions
    weights = %{
      syntax: 0.25,
      semantics: 0.20,
      logic: 0.25,
      clarity: 0.15,
      completeness: 0.10,
      coherence: 0.05
    }

    # Add any additional dimensions with default weight
    all_dimensions =
      Map.merge(
        # Defaults
        %{readability: 0.0},
        dimensions
      )

    weighted_sum =
      Enum.reduce(weights, 0.0, fn {dim, weight}, acc ->
        score = Map.get(all_dimensions, dim, 0.5)
        acc + score * weight
      end)

    # Ensure it's between 0 and 1
    max(0.0, min(1.0, weighted_sum))
  end

  defp compare_dimensions(dim1, dim2) do
    Map.keys(dim1)
    |> Enum.map(fn key ->
      {key, Map.get(dim2, key, 0) - Map.get(dim1, key, 0)}
    end)
    |> Enum.into(%{})
  end

  defp count_occurrences(string, substring) do
    string
    |> String.split(substring)
    |> length()
    |> Kernel.-(1)
  end

  defp count_leading_spaces(line) do
    String.length(line) - String.length(String.trim_leading(line))
  end

  defp detect_language(content) do
    cond do
      String.contains?(content, ["defmodule", "def ", "|>"]) -> "elixir"
      String.contains?(content, ["function", "=>", "const"]) -> "javascript"
      String.contains?(content, ["def ", "import ", "class"]) -> "python"
      true -> "unknown"
    end
  end

  defp estimate_avg_syllables(words) do
    # Simple syllable estimation
    total_syllables =
      Enum.sum(
        Enum.map(words, fn word ->
          # Count vowel groups as syllables (simplified)
          vowel_groups = Regex.scan(~r/[aeiouAEIOU]+/, word)
          max(1, length(vowel_groups))
        end)
      )

    if length(words) > 0 do
      total_syllables / length(words)
    else
      1.0
    end
  end

  defp split_mixed_content(content) do
    # Simple split - in production use more sophisticated parsing
    lines = String.split(content, "\n")

    {code_parts, text_parts} =
      lines
      |> Enum.reduce({[], [], [], :text}, fn line, {code, text, current, mode} ->
        cond do
          String.starts_with?(line, "```") && mode == :text ->
            text_content = Enum.join(current, "\n")
            new_text = if text_content != "", do: [text_content | text], else: text
            {code, new_text, [], :code}

          String.starts_with?(line, "```") && mode == :code ->
            code_content = Enum.join(current, "\n")
            new_code = if code_content != "", do: [code_content | code], else: code
            {new_code, text, [], :text}

          true ->
            {code, text, current ++ [line], mode}
        end
      end)
      |> finalize_split()

    {Enum.reverse(code_parts), Enum.reverse(text_parts)}
  end

  defp finalize_split({code, text, current, mode}) do
    if current != [] do
      final_content = Enum.join(current, "\n")

      case mode do
        :code -> {[final_content | code], text}
        :text -> {code, [final_content | text]}
      end
    else
      {code, text}
    end
  end
end
