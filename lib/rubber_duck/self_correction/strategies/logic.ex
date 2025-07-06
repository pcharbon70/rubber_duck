defmodule RubberDuck.SelfCorrection.Strategies.Logic do
  @moduledoc """
  Logic verification and correction strategy.
  
  Focuses on detecting and fixing logical errors, inconsistencies,
  and flawed reasoning in code and text.
  """
  
  @behaviour RubberDuck.SelfCorrection.Strategy
  
  import RubberDuck.SelfCorrection.Strategy
  
  @impl true
  def name(), do: :logic
  
  @impl true
  def supported_types(), do: [:code, :text, :mixed]
  
  @impl true
  def priority(), do: 90  # Very high priority - logic errors are critical
  
  @impl true
  def analyze(content, type, context, evaluation) do
    issues = detect_logic_issues(content, type, context, evaluation)
    corrections = generate_logic_corrections(content, issues, type, context)
    
    %{
      strategy: :logic,
      issues: issues,
      corrections: corrections,
      confidence: calculate_logic_confidence(issues, evaluation),
      metadata: %{
        content_type: type,
        checks_performed: [:flow, :consistency, :completeness, :correctness]
      }
    }
  end
  
  @impl true
  def validate_correction(content, correction) do
    # Ensure logical corrections don't introduce new inconsistencies
    if maintains_logical_integrity?(content, correction) do
      {:ok, correction}
    else
      {:error, "Correction may introduce logical inconsistencies"}
    end
  end
  
  # Private functions
  
  defp detect_logic_issues(content, type, context, evaluation) do
    base_issues = case type do
      :code -> detect_code_logic_issues(content, context)
      :text -> detect_text_logic_issues(content, context)
      :mixed -> detect_mixed_logic_issues(content, context)
    end
    
    # Add issues from CoT validator if available
    validation_issues = if evaluation[:reasoning_chain] do
      analyze_reasoning_chain(evaluation.reasoning_chain)
    else
      []
    end
    
    base_issues ++ validation_issues
  end
  
  defp detect_code_logic_issues(content, context) do
    language = context[:language] || detect_language(content)
    
    issues = []
    
    # Control flow issues
    issues = issues ++ check_control_flow(content, language)
    
    # Condition logic issues
    issues = issues ++ check_condition_logic(content, language)
    
    # Return consistency
    issues = issues ++ check_return_consistency(content, language)
    
    # Error handling logic
    issues = issues ++ check_error_handling(content, language)
    
    # Recursion and loops
    issues = issues ++ check_iteration_logic(content, language)
    
    issues
  end
  
  defp detect_text_logic_issues(content, _context) do
    issues = []
    
    # Logical flow and structure
    issues = issues ++ check_argument_flow(content)
    
    # Contradictions
    issues = issues ++ check_contradictions(content)
    
    # Cause and effect relationships
    issues = issues ++ check_causality(content)
    
    # Completeness of arguments
    issues = issues ++ check_argument_completeness(content)
    
    issues
  end
  
  defp detect_mixed_logic_issues(content, context) do
    # Analyze both code and text logic
    {code_sections, text_sections} = split_content(content)
    
    code_issues = Enum.flat_map(code_sections, fn {code, loc} ->
      detect_code_logic_issues(code, context)
      |> Enum.map(&Map.update!(&1, :location, fn l -> Map.merge(l, loc) end))
    end)
    
    text_issues = Enum.flat_map(text_sections, fn {text, loc} ->
      detect_text_logic_issues(text, context)
      |> Enum.map(&Map.update!(&1, :location, fn l -> Map.merge(l, loc) end))
    end)
    
    code_issues ++ text_issues
  end
  
  defp check_control_flow(content, "elixir") do
    issues = []
    
    # Check for infinite loops
    if Regex.match?(~r/def.*do\s*\w+\(\)/s, content) do
      # Simple recursive call without base case
      issues = [issue(:possible_infinite_recursion, :warning,
        "Recursive function may lack proper base case", %{}) | issues]
    end
    
    # Check for unreachable case clauses
    case_blocks = Regex.scan(~r/case.*do(.*?)end/s, content)
    
    Enum.flat_map(case_blocks, fn [_full, block] ->
      if String.contains?(block, "_ ->") && !String.ends_with?(String.trim(block), "_ ->") do
        [issue(:unreachable_case, :warning,
          "Case clauses after catch-all pattern are unreachable", %{})]
      else
        []
      end
    end) ++ issues
  end
  
  defp check_control_flow(content, _language) do
    # Generic control flow checks
    issues = []
    
    # Check for always-true/false conditions
    if Regex.match?(~r/if\s+(true|false)\s*[\{\(]/, content) do
      issues = [issue(:constant_condition, :warning,
        "Condition is always true or false", %{}) | issues]
    end
    
    # Empty control blocks
    if Regex.match?(~r/(if|while|for).*\{\s*\}/, content) do
      issues = [issue(:empty_control_block, :warning,
        "Empty control flow block detected", %{}) | issues]
    end
    
    issues
  end
  
  defp check_condition_logic(content, _language) do
    issues = []
    
    # Check for redundant conditions
    if Regex.match?(~r/(\w+)\s*==\s*true/, content) do
      issues = [issue(:redundant_boolean_comparison, :info,
        "Redundant comparison with boolean literal", %{}) | issues]
    end
    
    # Check for impossible conditions
    if Regex.match?(~r/(\w+)\s*&&\s*!\1/, content) do
      issues = [issue(:impossible_condition, :error,
        "Condition can never be true (x && !x)", %{}) | issues]
    end
    
    # Check for always-true conditions
    if Regex.match?(~r/(\w+)\s*\|\|\s*!\1/, content) do
      issues = [issue(:tautology, :warning,
        "Condition is always true (x || !x)", %{}) | issues]
    end
    
    issues
  end
  
  defp check_return_consistency(content, "elixir") do
    # In Elixir, check for consistent return types
    function_blocks = Regex.scan(~r/def\s+\w+.*?do(.*?)end/s, content)
    
    Enum.flat_map(function_blocks, fn [_full, body] ->
      # Check if function has mixed return types
      has_tuple_return = Regex.match?(~r/\{:ok,.*\}|\{:error,.*\}/, body)
      has_bare_return = Regex.match?(~r/^\s*\w+\s*$|^\s*".*"\s*$/m, body)
      
      if has_tuple_return && has_bare_return do
        [issue(:inconsistent_returns, :warning,
          "Function has inconsistent return types", %{})]
      else
        []
      end
    end)
  end
  
  defp check_return_consistency(content, _language) do
    # Generic return consistency checks
    if Regex.match?(~r/return\s+null.*return\s+\w+|return\s+\w+.*return\s+null/s, content) do
      [issue(:mixed_null_returns, :warning,
        "Function returns both null and non-null values", %{})]
    else
      []
    end
  end
  
  defp check_error_handling(content, "elixir") do
    issues = []
    
    # Check for unhandled error tuples
    if Regex.match?(~r/\{:error,.*\}/, content) && !Regex.match?(~r/case.*{:error/, content) do
      issues = [issue(:unhandled_errors, :warning,
        "Error tuples may not be properly handled", %{}) | issues]
    end
    
    # Check for bare raises without context
    bare_raises = Regex.scan(~r/raise\s+"[^"]*"$/, content, multiline: true)
    if length(bare_raises) > 0 do
      issues = [issue(:uninformative_errors, :info,
        "Error messages lack context information", %{}) | issues]
    end
    
    issues
  end
  
  defp check_error_handling(content, _language) do
    # Generic error handling checks
    empty_catches = Regex.scan(~r/catch.*\{\s*\}|except:\s*pass/s, content)
    
    if length(empty_catches) > 0 do
      [issue(:empty_error_handling, :warning,
        "Empty error handling blocks detected", %{})]
    else
      []
    end
  end
  
  defp check_iteration_logic(content, _language) do
    issues = []
    
    # Check for off-by-one errors in loops
    if Regex.match?(~r/for.*[<>]=.*length|for.*\.\.[^\.].*\+\s*1/, content) do
      issues = [issue(:possible_off_by_one, :warning,
        "Possible off-by-one error in loop boundary", %{}) | issues]
    end
    
    # Check for modifying collection during iteration
    if Regex.match?(~r/for.*in\s+(\w+).*\1\s*=|each.*do.*delete|each.*do.*push/, content) do
      issues = [issue(:collection_modification, :error,
        "Modifying collection during iteration", %{}) | issues]
    end
    
    issues
  end
  
  defp check_argument_flow(content) do
    # Analyze logical flow in text
    paragraphs = String.split(content, ~r/\n\n+/)
    
    issues = []
    
    # Check for conclusion without premises
    if length(paragraphs) > 0 do
      last_paragraph = List.last(paragraphs)
      conclusion_words = ["therefore", "thus", "hence", "consequently", "in conclusion"]
      
      has_conclusion = Enum.any?(conclusion_words, fn word ->
        String.contains?(String.downcase(last_paragraph), word)
      end)
      
      if has_conclusion && length(paragraphs) < 3 do
        issues = [issue(:unsupported_conclusion, :warning,
          "Conclusion appears without sufficient supporting arguments", %{}) | issues]
      end
    end
    
    issues
  end
  
  defp check_contradictions(content) do
    sentences = String.split(content, ~r/[.!?]+/)
    
    # Simple contradiction detection
    contradictions = []
    
    # Check for direct negations
    Enum.each(sentences, fn sentence ->
      words = String.split(String.downcase(sentence), ~r/\s+/)
      
      # Look for "not X" followed by "X" patterns
      if Regex.match?(~r/not\s+\w+.*\bsame\s+\w+|never.*always/, String.downcase(sentence)) do
        contradictions ++ [issue(:contradiction, :warning,
          "Potential contradiction detected", %{})]
      else
        contradictions
      end
    end)
  end
  
  defp check_causality(content) do
    # Check for flawed cause-effect relationships
    causality_words = ["because", "since", "therefore", "causes", "leads to", "results in"]
    
    issues = Enum.flat_map(causality_words, fn word ->
      pattern = Regex.compile!("\\b#{word}\\b", "i")
      
      if Regex.match?(pattern, content) do
        # Check if causality is properly established
        sentences = String.split(content, ~r/[.!?]+/)
        causal_sentences = Enum.filter(sentences, &String.contains?(&1, word))
        
        Enum.flat_map(causal_sentences, fn sentence ->
          words_before = sentence
          |> String.split(word)
          |> List.first()
          |> String.split()
          |> length()
          
          if words_before < 3 do
            [issue(:weak_causality, :info,
              "Causal relationship may not be properly established", %{})]
          else
            []
          end
        end)
      else
        []
      end
    end)
    
    issues
  end
  
  defp check_argument_completeness(content) do
    # Check if arguments are complete
    issues = []
    
    # Check for unfinished thoughts
    if Regex.match?(~r/such as\s*\.|\bfor example\s*\.|including\s*\./, content) do
      issues = [issue(:incomplete_enumeration, :warning,
        "Enumeration or example list appears incomplete", %{}) | issues]
    end
    
    # Check for missing evidence
    claim_words = ["clearly", "obviously", "certainly", "definitely"]
    claims_without_evidence = Enum.count(claim_words, fn word ->
      String.contains?(String.downcase(content), word)
    end)
    
    if claims_without_evidence > 2 do
      issues = [issue(:unsupported_claims, :info,
        "Multiple claims made without supporting evidence", %{}) | issues]
    end
    
    issues
  end
  
  defp analyze_reasoning_chain(_chain) do
    # TODO: Integrate with CoT Validator when available
    []
  end
  
  defp generate_logic_corrections(content, issues, type, context) do
    # Generate corrections for high-priority logic issues
    critical_issues = Enum.filter(issues, fn issue ->
      issue.severity == :error || 
      (issue.severity == :warning && issue.type in [:impossible_condition, :contradiction])
    end)
    
    Enum.map(critical_issues, fn issue ->
      generate_correction_for_logic_issue(content, issue, type, context)
    end)
    |> Enum.filter(& &1)
  end
  
  defp generate_correction_for_logic_issue(content, issue, _type, _context) do
    case issue.type do
      :impossible_condition ->
        correction(:fix_impossible_condition,
          "Remove or fix impossible condition",
          [], # Specific changes would be determined by context
          0.9,
          :high)
      
      :constant_condition ->
        correction(:simplify_condition,
          "Simplify or remove constant condition",
          [],
          0.8,
          :medium)
      
      :unhandled_errors ->
        correction(:add_error_handling,
          "Add proper error handling",
          [],
          0.7,
          :high)
      
      :contradiction ->
        correction(:resolve_contradiction,
          "Resolve logical contradiction",
          [],
          0.6,
          :high)
      
      _ ->
        nil
    end
  end
  
  defp calculate_logic_confidence(issues, evaluation) do
    # Base confidence on issue severity
    base_score = 1.0
    
    issue_penalty = Enum.reduce(issues, 0, fn issue, acc ->
      case issue.severity do
        :error -> acc + 0.15
        :warning -> acc + 0.08
        :info -> acc + 0.03
      end
    end)
    
    # Consider validation scores if available
    validation_boost = 0  # TODO: Integrate with CoT Validator
    
    max(0.0, min(1.0, base_score - issue_penalty + validation_boost))
  end
  
  defp maintains_logical_integrity?(_content, correction) do
    # Verify correction doesn't break logic
    # This would involve more sophisticated analysis in production
    correction.confidence > 0.7 && correction.impact != :high
  end
  
  defp detect_language(content) do
    cond do
      String.contains?(content, ["defmodule", "def ", "|>"]) -> "elixir"
      String.contains?(content, ["function", "const", "=>"]) -> "javascript"
      String.contains?(content, ["def ", "class ", "import"]) -> "python"
      true -> "unknown"
    end
  end
  
  defp split_content(content) do
    # Split mixed content into code and text sections
    lines = String.split(content, "\n")
    in_code = false
    
    {code_sections, text_sections, current, mode} = 
      Enum.reduce(lines ++ [""], {[], [], [], :text}, fn line, {code, text, current, mode} ->
        cond do
          String.starts_with?(line, "```") && mode == :text ->
            {code, [{Enum.join(current, "\n"), %{}} | text], [], :code}
          
          String.starts_with?(line, "```") && mode == :code ->
            {[{Enum.join(current, "\n"), %{}} | code], text, [], :text}
          
          true ->
            {code, text, current ++ [line], mode}
        end
      end)
    
    {Enum.reverse(code_sections), Enum.reverse(text_sections)}
  end
end