defmodule RubberDuck.CodeCorrection.SyntaxCorrector do
  @moduledoc """
  Syntax correction module for fixing syntax errors in code.
  
  Provides pattern-based syntax fixes, parser integration, and
  safe transformation rules for common syntax errors.
  """

  require Logger

  @doc """
  Fixes syntax errors based on patterns and error information.
  """
  def fix_syntax_error(error_data, patterns, options \\ %{}) do
    code = error_data["code"]
    error_type = error_data["error_type"]
    error_message = error_data["error_message"] || ""
    
    Logger.debug("SyntaxCorrector: Fixing error_type=#{error_type}, error_message=#{error_message}")
    Logger.debug("SyntaxCorrector: Code=#{inspect(code)}")
    Logger.debug("SyntaxCorrector: Patterns=#{inspect(patterns)}")
    
    # Try pattern-based fixes first
    case apply_pattern_fixes(code, error_message, patterns) do
      {:ok, fixed_code} ->
        Logger.debug("SyntaxCorrector: Pattern-based fix succeeded")
        {:ok, %{
          corrected_code: fixed_code,
          changes: extract_changes(code, fixed_code),
          patterns_used: identify_used_patterns(code, fixed_code, patterns),
          confidence: 0.9,
          method: :pattern_based
        }}
        
      :no_match ->
        Logger.debug("SyntaxCorrector: No pattern match, trying heuristics")
        # Try heuristic-based fixes
        case apply_heuristic_fixes(code, error_type, error_message, options) do
          {:ok, fixed_code} ->
            Logger.debug("SyntaxCorrector: Heuristic fix succeeded")
            {:ok, %{
              corrected_code: fixed_code,
              changes: extract_changes(code, fixed_code),
              patterns_used: [],
              confidence: 0.7,
              method: :heuristic
            }}
            
          :no_fix ->
            Logger.debug("SyntaxCorrector: No fix found")
            {:error, "No applicable syntax fix found"}
        end
    end
  end

  @doc """
  Validates syntax of the given code.
  """
  def validate_syntax(code) do
    case Code.string_to_quoted(code) do
      {:ok, _ast} ->
        {:ok, %{valid: true, errors: []}}
        
      {:error, {line, error_desc, token}} ->
        {:error, %{
          valid: false,
          errors: [%{
            line: line,
            description: format_error_description(error_desc),
            token: token
          }]
        }}
    end
  end

  ## Private Functions - Pattern-Based Fixes

  defp apply_pattern_fixes(code, error_message, patterns) do
    applicable_patterns = find_applicable_patterns(error_message, patterns)
    
    Logger.debug("SyntaxCorrector: Found #{length(applicable_patterns)} applicable patterns")
    
    Enum.reduce_while(applicable_patterns, :no_match, fn {pattern_id, pattern}, _acc ->
      Logger.debug("SyntaxCorrector: Trying pattern #{pattern_id}")
      case apply_single_pattern(code, pattern) do
        {:ok, fixed_code} ->
          Logger.debug("SyntaxCorrector: Pattern #{pattern_id} matched!")
          {:halt, {:ok, fixed_code}}
          
        :no_match ->
          Logger.debug("SyntaxCorrector: Pattern #{pattern_id} did not match")
          {:cont, :no_match}
      end
    end)
  end

  defp find_applicable_patterns(error_message, patterns) do
    # For syntax errors, try all patterns
    # In production, use more sophisticated matching
    if String.contains?(error_message, "syntax error") or String.contains?(error_message, "before:") do
      patterns
      |> Enum.sort_by(fn {_id, pattern} -> pattern.success_rate end, :desc)
    else
      patterns
      |> Enum.filter(fn {_id, pattern} ->
        pattern_matches_error?(pattern, error_message)
      end)
      |> Enum.sort_by(fn {_id, pattern} -> pattern.success_rate end, :desc)
    end
  end

  defp pattern_matches_error?(pattern, error_message) do
    # Check if pattern keywords match error message
    keywords = extract_pattern_keywords(pattern)
    
    # Also check for common syntax error indicators
    syntax_keywords = ["comma", "missing", "before", "syntax"]
    all_keywords = keywords ++ syntax_keywords
    
    Enum.any?(all_keywords, fn keyword ->
      String.contains?(String.downcase(error_message), keyword)
    end)
  end

  defp apply_single_pattern(code, pattern) do
    # Use multiline and dotall flags for patterns
    compiled_pattern = Regex.compile!(Regex.source(pattern.pattern), [:multiline, :dotall])
    if Regex.match?(compiled_pattern, code) do
      # Convert template placeholders to proper replacement syntax
      replacement = pattern.fix_template
      |> String.replace("$1", "\\1")
      |> String.replace("$2", "\\2")
      |> String.replace("$3", "\\3")
      
      fixed_code = Regex.replace(compiled_pattern, code, replacement)
      {:ok, fixed_code}
    else
      :no_match
    end
  end

  ## Private Functions - Heuristic-Based Fixes

  defp apply_heuristic_fixes(code, error_type, error_message, _options) do
    fixes = [
      &fix_missing_end/3,
      &fix_missing_comma/3,
      &fix_missing_do/3,
      &fix_unclosed_delimiter/3,
      &fix_invalid_syntax/3,
      &fix_indentation_error/3
    ]
    
    Enum.reduce_while(fixes, :no_fix, fn fix_fn, _acc ->
      case fix_fn.(code, error_type, error_message) do
        {:ok, fixed_code} ->
          {:halt, {:ok, fixed_code}}
          
        :no_fix ->
          {:cont, :no_fix}
      end
    end)
  end

  defp fix_missing_end(code, _error_type, error_message) do
    if String.contains?(error_message, "missing terminator: end") or
       String.contains?(error_message, "unexpected token: end-of-file") do
      
      # Count opening and closing keywords
      opens = count_block_openers(code)
      ends = count_block_closers(code)
      
      if opens > ends do
        # Add missing ends
        missing_ends = String.duplicate("\nend", opens - ends)
        {:ok, code <> missing_ends}
      else
        :no_fix
      end
    else
      :no_fix
    end
  end

  defp fix_missing_comma(code, _error_type, error_message) do
    if String.contains?(error_message, "syntax error before:") do
      # Common pattern: missing comma in lists/tuples
      patterns = [
        # List elements
        {~r/\[\s*([^,\]]+)\s+([^,\]]+)\s*\]/, "[\\1, \\2]"},
        # Map/keyword list
        {~r/(%?\{[^}]*?)(\w+:\s*\w+)\s+(\w+:)/, "\\1\\2, \\3"},
        # Function arguments
        {~r/\(([^,)]+)\s+([^,)]+)\)/, "(\\1, \\2)"}
      ]
      
      fixed_code = Enum.reduce(patterns, code, fn {pattern, replacement}, acc ->
        Regex.replace(pattern, acc, replacement)
      end)
      
      if fixed_code != code do
        {:ok, fixed_code}
      else
        :no_fix
      end
    else
      :no_fix
    end
  end

  defp fix_missing_do(code, _error_type, error_message) do
    if String.contains?(error_message, "missing :do") or
       String.contains?(error_message, "unexpected token") do
      
      patterns = [
        # def without do
        {~r/(\s*def\s+\w+\([^)]*\))\s*\n/, "\\1 do\n"},
        # if without do
        {~r/(\s*if\s+[^,\n]+)\s*\n/, "\\1 do\n"},
        # case without do
        {~r/(\s*case\s+[^d][^o]\s+)\n/, "\\1 do\n"}
      ]
      
      fixed_code = Enum.reduce(patterns, code, fn {pattern, replacement}, acc ->
        Regex.replace(pattern, acc, replacement)
      end)
      
      if fixed_code != code do
        {:ok, fixed_code}
      else
        :no_fix
      end
    else
      :no_fix
    end
  end

  defp fix_unclosed_delimiter(code, _error_type, error_message) do
    delimiters = [
      {"(", ")", "parenthesis"},
      {"[", "]", "bracket"},
      {"{", "}", "brace"},
      {"\"", "\"", "quote"},
      {"'", "'", "single quote"}
    ]
    
    Enum.reduce_while(delimiters, :no_fix, fn {open_delim, close_delim, name}, _acc ->
      if String.contains?(error_message, name) or
         String.contains?(error_message, "unclosed") do
        
        open_count = count_occurrences(code, open_delim)
        close_count = count_occurrences(code, close_delim)
        
        cond do
          open_count > close_count ->
            {:halt, {:ok, code <> String.duplicate(close_delim, open_count - close_count)}}
            
          close_count > open_count ->
            {:halt, {:ok, String.duplicate(open_delim, close_count - open_count) <> code}}
            
          true ->
            {:cont, :no_fix}
        end
      else
        {:cont, :no_fix}
      end
    end)
  end

  defp fix_invalid_syntax(code, error_type, _error_message) do
    if error_type == "invalid_syntax" do
      fixes = [
        # Fix assignment in guard
        {~r/when\s+(\w+)\s*=\s*(.+)/, "when \\1 == \\2"},
        # Fix invalid pipe
        {~r/\|\>\s*$/, ""},
        # Fix double operators
        {~r/(\+\+|\-\-|&&|\|\|)\s*\1/, "\\1"}
      ]
      
      fixed_code = Enum.reduce(fixes, code, fn {pattern, replacement}, acc ->
        Regex.replace(pattern, acc, replacement)
      end)
      
      if fixed_code != code do
        {:ok, fixed_code}
      else
        :no_fix
      end
    else
      :no_fix
    end
  end

  defp fix_indentation_error(code, _error_type, error_message) do
    if String.contains?(error_message, "indentation") do
      # Simple indentation fix - ensure consistent spacing
      lines = String.split(code, "\n")
      
      fixed_lines = fix_indentation_levels(lines)
      fixed_code = Enum.join(fixed_lines, "\n")
      
      if fixed_code != code do
        {:ok, fixed_code}
      else
        :no_fix
      end
    else
      :no_fix
    end
  end

  ## Private Functions - Helpers

  defp extract_changes(original_code, fixed_code) do
    original_lines = String.split(original_code, "\n")
    fixed_lines = String.split(fixed_code, "\n")
    
    {changes, _, _} = Enum.reduce(fixed_lines, {[], original_lines, 1}, fn fixed_line, {changes, remaining_original, line_num} ->
      {original_line, rest} = case remaining_original do
        [line | rest] -> {line, rest}
        [] -> {"", []}
      end
      
      if fixed_line != original_line do
        change = %{
          line: line_num,
          original: original_line,
          fixed: fixed_line,
          type: categorize_change(original_line, fixed_line)
        }
        {[change | changes], rest, line_num + 1}
      else
        {changes, rest, line_num + 1}
      end
    end)
    
    Enum.reverse(changes)
  end

  defp identify_used_patterns(original_code, fixed_code, patterns) do
    patterns
    |> Enum.filter(fn {_id, pattern} ->
      # Check if pattern was likely used
      Regex.match?(pattern.pattern, original_code) and
      String.contains?(fixed_code, extract_fix_signature(pattern.fix_template))
    end)
    |> Enum.map(fn {id, _pattern} -> id end)
  end

  defp extract_pattern_keywords(pattern) do
    # Extract keywords from pattern ID and fix template
    pattern_str = inspect(pattern.pattern)
    
    keywords = pattern_str
    |> String.downcase()
    |> String.split(~r/[^a-z]+/)
    |> Enum.filter(&(String.length(&1) > 2))
    
    keywords
  end

  defp count_block_openers(code) do
    ~r/\b(def|defp|defmodule|if|unless|case|cond|fn|for|with|try|quote)\b/
    |> Regex.scan(code)
    |> length()
  end

  defp count_block_closers(code) do
    ~r/\bend\b/
    |> Regex.scan(code)
    |> length()
  end

  defp count_occurrences(string, substring) do
    string
    |> String.graphemes()
    |> Enum.count(&(&1 == substring))
  end

  defp fix_indentation_levels(lines) do
    lines
    |> Enum.reduce({[], 0}, fn line, {fixed_lines, indent_level} ->
      trimmed = String.trim_leading(line)
      
      # Adjust indent level based on keywords
      new_indent = cond do
        String.starts_with?(trimmed, "end") -> max(0, indent_level - 1)
        true -> indent_level
      end
      
      # Apply indentation
      indented_line = String.duplicate("  ", new_indent) <> trimmed
      
      # Update indent level for next line
      next_indent = cond do
        Regex.match?(~r/\b(def|defp|defmodule|if|unless|case|cond|fn|for|with|try|quote)\b/, trimmed) -> new_indent + 1
        String.starts_with?(trimmed, "end") -> new_indent
        true -> new_indent
      end
      
      {[indented_line | fixed_lines], next_indent}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp categorize_change(original, fixed) do
    cond do
      String.contains?(fixed, "end") and not String.contains?(original, "end") -> :added_end
      String.contains?(fixed, ",") and not String.contains?(original, ",") -> :added_comma
      String.contains?(fixed, "do") and not String.contains?(original, "do") -> :added_do
      String.trim(original) != String.trim(fixed) -> :modified_content
      true -> :indentation
    end
  end

  defp extract_fix_signature(fix_template) do
    # Extract a signature from the fix template for matching
    fix_template
    |> String.replace(~r/\$\d+/, "")
    |> String.replace(~r/\\\d+/, "")
    |> String.trim()
  end

  defp format_error_description(error_desc) when is_binary(error_desc), do: error_desc
  defp format_error_description(error_desc), do: inspect(error_desc)
end