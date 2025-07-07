defmodule RubberDuck.CoT.Validator do
  @moduledoc """
  Validates Chain-of-Thought reasoning results for logical consistency
  and quality.
  """

  require Logger

  @doc """
  Validates the final result of a reasoning chain.
  """
  def validate_chain_result(result, session) do
    validations = [
      &validate_completeness/2,
      &validate_consistency/2,
      &validate_logical_flow/2,
      &validate_answer_quality/2
    ]

    errors =
      Enum.reduce(validations, [], fn validator, acc ->
        case validator.(result, session) do
          :ok -> acc
          {:error, reason} -> [reason | acc]
        end
      end)

    if Enum.empty?(errors) do
      :ok
    else
      {:error, Enum.reverse(errors)}
    end
  end

  @doc """
  Calculates a quality score for the reasoning chain.
  """
  def calculate_quality_score(result, session) do
    scores = %{
      completeness: score_completeness(result, session),
      consistency: score_consistency(result, session),
      clarity: score_clarity(result, session),
      depth: score_depth(result, session)
    }

    # Calculate weighted average
    weights = %{completeness: 0.3, consistency: 0.3, clarity: 0.2, depth: 0.2}

    total_score =
      Enum.reduce(scores, 0.0, fn {metric, score}, acc ->
        acc + score * Map.get(weights, metric, 0.0)
      end)

    %{
      total: Float.round(total_score, 2),
      breakdown: scores
    }
  end

  # Private validation functions

  defp validate_completeness(_result, session) do
    # Check that all required steps were executed
    expected_steps = get_expected_steps(session)
    executed_steps = Enum.map(session.steps, & &1.name)

    missing_steps = expected_steps -- executed_steps

    if Enum.empty?(missing_steps) do
      :ok
    else
      {:error, {:incomplete_reasoning, missing_steps}}
    end
  end

  defp validate_consistency(_result, session) do
    # Check for contradictions between steps
    contradictions = find_contradictions(session.steps)

    if Enum.empty?(contradictions) do
      :ok
    else
      {:error, {:contradictions_found, contradictions}}
    end
  end

  defp validate_logical_flow(_result, session) do
    # Check that reasoning follows logically from step to step
    flow_issues = check_logical_flow(session.steps)

    if Enum.empty?(flow_issues) do
      :ok
    else
      {:error, {:logical_flow_issues, flow_issues}}
    end
  end

  defp validate_answer_quality(result, _session) do
    # Basic quality checks on the final answer
    cond do
      is_nil(result.final_answer) or result.final_answer == "" ->
        {:error, :empty_final_answer}

      String.length(result.final_answer) < 20 ->
        {:error, :answer_too_brief}

      contains_placeholder_text?(result.final_answer) ->
        {:error, :incomplete_answer}

      true ->
        :ok
    end
  end

  # Scoring functions

  defp score_completeness(_result, session) do
    # Score based on how many steps were completed
    expected_count = length(get_expected_steps(session))
    actual_count = length(session.steps)

    if expected_count > 0 do
      min(1.0, actual_count / expected_count)
    else
      1.0
    end
  end

  defp score_consistency(_result, session) do
    # Score based on absence of contradictions
    contradictions = find_contradictions(session.steps)

    case length(contradictions) do
      0 -> 1.0
      1 -> 0.7
      2 -> 0.4
      _ -> 0.2
    end
  end

  defp score_clarity(result, _session) do
    # Score based on clarity of final answer
    answer = result.final_answer || ""

    clarity_factors = [
      has_clear_structure?(answer),
      has_concrete_examples?(answer),
      uses_clear_language?(answer),
      has_proper_formatting?(answer)
    ]

    score = Enum.count(clarity_factors, & &1) / length(clarity_factors)
    Float.round(score, 2)
  end

  defp score_depth(_result, session) do
    # Score based on depth of reasoning
    avg_step_length = calculate_average_step_length(session.steps)

    cond do
      avg_step_length > 500 -> 1.0
      avg_step_length > 300 -> 0.8
      avg_step_length > 150 -> 0.6
      avg_step_length > 50 -> 0.4
      true -> 0.2
    end
  end

  # Helper functions

  defp get_expected_steps(_session) do
    # In a real implementation, this would get the expected steps
    # from the chain configuration
    [:understand, :analyze, :solve]
  end

  defp find_contradictions(steps) do
    # Simple contradiction detection

    # Check for conflicting statements
    for {step1, idx1} <- Enum.with_index(steps),
        {step2, idx2} <- Enum.with_index(steps),
        idx1 < idx2 do
      if contradicts?(step1.result, step2.result) do
        [{step1.name, step2.name, "Conflicting statements"}]
      else
        []
      end
    end
    |> List.flatten()
  end

  defp contradicts?(text1, text2) do
    # Simple contradiction detection
    negations = ["not", "cannot", "won't", "isn't", "aren't", "no"]

    words1 = String.downcase(text1) |> String.split()
    words2 = String.downcase(text2) |> String.split()

    # Very basic check - in production would use more sophisticated NLP
    has_negation1 = Enum.any?(words1, &(&1 in negations))
    has_negation2 = Enum.any?(words2, &(&1 in negations))

    # If one has negation and other doesn't, might be contradiction
    has_negation1 != has_negation2 and shares_key_terms?(words1, words2)
  end

  defp shares_key_terms?(words1, words2) do
    # Check if they share significant terms
    shared = MapSet.intersection(MapSet.new(words1), MapSet.new(words2))
    MapSet.size(shared) > 3
  end

  defp check_logical_flow(steps) do
    # Check that each step builds on previous ones

    for {step, idx} <- Enum.with_index(steps), idx > 0 do
      prev_step = Enum.at(steps, idx - 1)

      if not references_previous?(step.result, prev_step.result) do
        ["Step #{step.name} doesn't clearly build on #{prev_step.name}"]
      else
        []
      end
    end
    |> List.flatten()
  end

  defp references_previous?(current_text, previous_text) do
    # Check if current step references concepts from previous
    prev_keywords = extract_keywords(previous_text)
    current_text_lower = String.downcase(current_text)

    Enum.any?(prev_keywords, &String.contains?(current_text_lower, &1))
  end

  defp extract_keywords(text) do
    # Extract key terms (simplified)
    text
    |> String.downcase()
    |> String.split()
    |> Enum.filter(&(String.length(&1) > 4))
    |> Enum.take(5)
  end

  defp contains_placeholder_text?(text) do
    placeholders = ["todo", "tbd", "placeholder", "fill in", "[", "]"]
    text_lower = String.downcase(text)

    Enum.any?(placeholders, &String.contains?(text_lower, &1))
  end

  defp has_clear_structure?(text) do
    # Check for structural elements
    String.contains?(text, ["\n", ".", ":", "-"])
  end

  defp has_concrete_examples?(text) do
    # Check for example indicators
    example_indicators = ["example", "for instance", "such as", "e.g.", "like"]
    text_lower = String.downcase(text)

    Enum.any?(example_indicators, &String.contains?(text_lower, &1))
  end

  defp uses_clear_language?(text) do
    # Check readability (simplified)
    words = String.split(text)
    avg_word_length = Enum.sum(Enum.map(words, &String.length/1)) / length(words)

    # Not too many complex words
    avg_word_length < 8
  end

  defp has_proper_formatting?(text) do
    # Check for basic formatting
    String.contains?(text, ["\n"]) or String.length(text) > 200
  end

  defp calculate_average_step_length(steps) do
    if Enum.empty?(steps) do
      0
    else
      total_length = Enum.sum(Enum.map(steps, &String.length(&1.result)))
      div(total_length, length(steps))
    end
  end
end
