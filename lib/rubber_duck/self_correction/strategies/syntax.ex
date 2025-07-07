defmodule RubberDuck.SelfCorrection.Strategies.Syntax do
  @moduledoc """
  Syntax validation and correction strategy.

  Focuses on detecting and fixing syntax errors, formatting issues,
  and structural problems in code and text.
  """

  @behaviour RubberDuck.SelfCorrection.Strategy

  import RubberDuck.SelfCorrection.Strategy

  @impl true
  def name(), do: :syntax

  @impl true
  def supported_types(), do: [:code, :mixed]

  @impl true
  # High priority - syntax must be correct first
  def priority(), do: 100

  @impl true
  def analyze(content, type, context, _evaluation) do
    issues = detect_syntax_issues(content, type, context)
    corrections = generate_corrections(content, issues, type, context)

    %{
      strategy: :syntax,
      issues: issues,
      corrections: corrections,
      confidence: calculate_confidence(issues, corrections),
      metadata: %{
        language: context[:language] || detect_language(content),
        checks_performed: [:syntax, :formatting, :structure]
      }
    }
  end

  @impl true
  def validate_correction(content, correction) do
    # Validate that the correction won't introduce new syntax errors
    case apply_correction_changes(content, correction.changes) do
      {:ok, corrected} ->
        if valid_syntax?(corrected, correction.metadata[:language]) do
          {:ok, correction}
        else
          {:error, "Correction would introduce syntax errors"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp detect_syntax_issues(content, :code, context) do
    language = context[:language] || detect_language(content)

    case language do
      "elixir" -> detect_elixir_syntax_issues(content)
      "python" -> detect_python_syntax_issues(content)
      "javascript" -> detect_javascript_syntax_issues(content)
      _ -> detect_generic_syntax_issues(content)
    end
  end

  defp detect_syntax_issues(content, :mixed, _context) do
    # For mixed content, detect code blocks and analyze them
    code_blocks = extract_code_blocks(content)

    Enum.flat_map(code_blocks, fn {code, language, location} ->
      detect_syntax_issues(code, :code, %{language: language})
      |> Enum.map(fn issue ->
        Map.update!(issue, :location, &Map.merge(&1, location))
      end)
    end)
  end

  defp detect_elixir_syntax_issues(content) do
    issues = []

    # Check for common Elixir syntax issues
    issues = issues ++ check_unmatched_delimiters(content, ["do", "end"])
    issues = issues ++ check_unmatched_delimiters(content, ["{", "}"])
    issues = issues ++ check_unmatched_delimiters(content, ["[", "]"])
    issues = issues ++ check_unmatched_delimiters(content, ["(", ")"])
    issues = issues ++ check_missing_commas(content)
    issues = issues ++ check_invalid_atoms(content)
    issues = issues ++ check_pipe_operator_usage(content)

    # Try to parse with Code.string_to_quoted
    case Code.string_to_quoted(content) do
      {:ok, _ast} ->
        # Only formatting/style issues
        issues

      {:error, {metadata, error_desc, _token}} when is_list(metadata) ->
        line = Keyword.get(metadata, :line, 1)

        [
          issue(:syntax_error, :error, "Syntax error at line #{line}: #{error_desc}", %{line: line}, %{
            parser_error: metadata
          })
          | issues
        ]

      {:error, {line, error_desc, _token}} when is_integer(line) ->
        [
          issue(:syntax_error, :error, "Syntax error at line #{line}: #{error_desc}", %{line: line}, %{
            parser_error: error_desc
          })
          | issues
        ]

      {:error, error} ->
        [issue(:syntax_error, :error, "Syntax error: #{inspect(error)}", %{}, %{parser_error: error}) | issues]
    end
  end

  defp detect_python_syntax_issues(content) do
    issues = []

    # Check for common Python syntax issues
    issues = issues ++ check_indentation_consistency(content)
    issues = issues ++ check_unmatched_delimiters(content, ["(", ")"])
    issues = issues ++ check_unmatched_delimiters(content, ["[", "]"])
    issues = issues ++ check_unmatched_delimiters(content, ["{", "}"])
    issues = issues ++ check_colon_usage(content)

    issues
  end

  defp detect_javascript_syntax_issues(content) do
    issues = []

    # Check for common JavaScript syntax issues
    issues = issues ++ check_unmatched_delimiters(content, ["{", "}"])
    issues = issues ++ check_unmatched_delimiters(content, ["[", "]"])
    issues = issues ++ check_unmatched_delimiters(content, ["(", ")"])
    issues = issues ++ check_semicolon_consistency(content)
    issues = issues ++ check_arrow_function_syntax(content)

    issues
  end

  defp detect_generic_syntax_issues(content) do
    # Basic checks that apply to most languages
    issues = []

    issues = issues ++ check_unmatched_quotes(content)
    issues = issues ++ check_unmatched_delimiters(content, ["(", ")"])
    issues = issues ++ check_unmatched_delimiters(content, ["[", "]"])
    issues = issues ++ check_unmatched_delimiters(content, ["{", "}"])

    issues
  end

  defp check_unmatched_delimiters(content, [open_delim, close_delim]) do
    lines = String.split(content, "\n")

    {_, issues} =
      Enum.reduce(lines, {0, []}, fn line, {depth, issues} ->
        open_count = count_occurrences(line, open_delim)
        close_count = count_occurrences(line, close_delim)
        new_depth = depth + open_count - close_count

        cond do
          new_depth < 0 ->
            issue =
              issue(:unmatched_delimiter, :error, "Unmatched '#{close_delim}' without corresponding '#{open_delim}'", %{
                line: length(issues) + 1
              })

            {0, [issue | issues]}

          true ->
            {new_depth, issues}
        end
      end)

    if elem({0, issues}, 0) > 0 do
      [issue(:unmatched_delimiter, :error, "Unclosed '#{open_delim}' - missing '#{close_delim}'", %{}) | issues]
    else
      issues
    end
  end

  defp check_unmatched_quotes(content) do
    # Check for unmatched quotes
    single_quotes = count_occurrences(content, "'")
    double_quotes = count_occurrences(content, "\"")

    _issues = []

    issues =
      if rem(single_quotes, 2) != 0 do
        [issue(:unmatched_quote, :error, "Unmatched single quote", %{})]
      else
        []
      end

    issues =
      issues ++
        if rem(double_quotes, 2) != 0 do
          [issue(:unmatched_quote, :error, "Unmatched double quote", %{})]
        else
          []
        end

    issues
  end

  defp check_missing_commas(content) do
    # Elixir-specific: Check for missing commas in lists/maps
    pattern = ~r/\}\s*\n\s*[a-zA-Z_]/

    if Regex.match?(pattern, content) do
      [issue(:missing_comma, :warning, "Possible missing comma between map/list elements", %{})]
    else
      []
    end
  end

  defp check_invalid_atoms(content) do
    # Elixir-specific: Check for invalid atom syntax
    pattern = ~r/:[0-9]/

    if Regex.match?(pattern, content) do
      [issue(:invalid_atom, :error, "Invalid atom syntax - atoms cannot start with numbers", %{})]
    else
      []
    end
  end

  defp check_pipe_operator_usage(content) do
    # Elixir-specific: Check for incorrect pipe operator usage
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> String.contains?(line, "|>") end)
    |> Enum.flat_map(fn {line, line_num} ->
      if String.ends_with?(String.trim(line), "|>") do
        [issue(:incomplete_pipe, :error, "Pipe operator at end of line without continuation", %{line: line_num})]
      else
        []
      end
    end)
  end

  defp check_indentation_consistency(content) do
    # Python-specific: Check for inconsistent indentation
    lines = String.split(content, "\n")

    indentations =
      lines
      |> Enum.filter(fn line -> String.trim(line) != "" end)
      |> Enum.map(fn line ->
        leading_spaces = String.length(line) - String.length(String.trim_leading(line))
        {leading_spaces, String.contains?(line, "\t")}
      end)

    has_tabs = Enum.any?(indentations, fn {_, has_tab} -> has_tab end)
    has_spaces = Enum.any?(indentations, fn {spaces, _} -> spaces > 0 end)

    if has_tabs && has_spaces do
      [issue(:mixed_indentation, :error, "Mixed tabs and spaces for indentation", %{})]
    else
      []
    end
  end

  defp check_colon_usage(content) do
    # Python-specific: Check for missing colons
    lines = String.split(content, "\n")

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      trimmed = String.trim(line)

      if Regex.match?(~r/^(if|elif|else|for|while|def|class|try|except|finally|with)\s+.*[^:]$/, trimmed) do
        [issue(:missing_colon, :error, "Missing colon after control structure", %{line: line_num})]
      else
        []
      end
    end)
  end

  defp check_semicolon_consistency(content) do
    # JavaScript: Check for inconsistent semicolon usage
    lines = String.split(content, "\n")

    statement_lines =
      lines
      |> Enum.filter(fn line ->
        trimmed = String.trim(line)

        trimmed != "" && !String.starts_with?(trimmed, "//") &&
          !String.starts_with?(trimmed, "{") && !String.starts_with?(trimmed, "}")
      end)

    with_semicolon = Enum.count(statement_lines, &String.ends_with?(&1, ";"))
    without_semicolon = length(statement_lines) - with_semicolon

    if with_semicolon > 0 && without_semicolon > 0 && without_semicolon > with_semicolon * 0.2 do
      [issue(:inconsistent_semicolons, :warning, "Inconsistent semicolon usage", %{})]
    else
      []
    end
  end

  defp check_arrow_function_syntax(content) do
    # JavaScript: Check for invalid arrow function syntax
    if Regex.match?(~r/=>\s*\n\s*{/, content) && !Regex.match?(~r/\)\s*=>\s*\n\s*{/, content) do
      [issue(:invalid_arrow_function, :error, "Invalid arrow function syntax", %{})]
    else
      []
    end
  end

  defp generate_corrections(content, issues, _type, context) do
    language = context[:language] || detect_language(content)

    issues
    |> Enum.map(fn issue ->
      generate_correction_for_issue(content, issue, language)
    end)
    |> Enum.filter(& &1)
  end

  defp generate_correction_for_issue(_content, %{type: :unmatched_delimiter} = issue, _language) do
    # Try to fix unmatched delimiters
    delimiter = extract_delimiter_from_description(issue.description)

    changes =
      case delimiter do
        "}" -> [insert_change("", "}", %{position: :end})]
        ")" -> [insert_change("", ")", %{position: :end})]
        "]" -> [insert_change("", "]", %{position: :end})]
        "end" -> [insert_change("", "\nend", %{position: :end})]
        _ -> []
      end

    if length(changes) > 0 do
      correction(
        :add_delimiter,
        "Add missing #{delimiter}",
        changes,
        0.8,
        :high
      )
    else
      nil
    end
  end

  defp generate_correction_for_issue(content, %{type: :missing_comma} = _issue, "elixir") do
    # Add missing commas in Elixir maps/lists
    corrected = Regex.replace(~r/(\})\s*\n\s*([a-zA-Z_])/, content, "\\1,\n  \\2")

    if corrected != content do
      correction(
        :add_comma,
        "Add missing comma between elements",
        [replace_change(content, corrected)],
        0.7,
        :medium
      )
    else
      nil
    end
  end

  defp generate_correction_for_issue(_content, _issue, _language) do
    # Default: no automatic correction available
    nil
  end

  defp extract_delimiter_from_description(description) do
    cond do
      String.contains?(description, "'}'") -> "}"
      String.contains?(description, "')'") -> ")"
      String.contains?(description, "']'") -> "]"
      String.contains?(description, "'end'") -> "end"
      true -> nil
    end
  end

  defp calculate_confidence(issues, corrections) do
    if length(issues) == 0 do
      1.0
    else
      # Confidence based on severity and correction availability
      error_count = Enum.count(issues, &(&1.severity == :error))
      warning_count = Enum.count(issues, &(&1.severity == :warning))
      correction_count = length(corrections)

      base_score = 1.0 - error_count * 0.2 - warning_count * 0.05
      correction_bonus = correction_count * 0.1

      min(1.0, max(0.0, base_score + correction_bonus))
    end
  end

  defp detect_language(content) do
    cond do
      String.contains?(content, ["defmodule", "def ", "defp"]) ->
        "elixir"

      String.contains?(content, ["def ", "import ", "class "]) &&
          String.contains?(content, [":", "    "]) ->
        "python"

      String.contains?(content, ["function", "const ", "=>"]) ->
        "javascript"

      true ->
        "unknown"
    end
  end

  defp extract_code_blocks(content) do
    # Extract code blocks from markdown-style content
    Regex.scan(~r/```(\w*)\n(.*?)```/s, content)
    |> Enum.map(fn [_full, language, code] ->
      {code, language, %{type: :code_block}}
    end)
  end

  defp count_occurrences(string, substring) do
    string
    |> String.split(substring)
    |> length()
    |> Kernel.-(1)
  end

  defp apply_correction_changes(content, changes) do
    try do
      corrected =
        Enum.reduce(changes, content, fn change, acc ->
          case change.action do
            :replace -> String.replace(acc, change.target, change.replacement)
            :insert -> insert_at_position(acc, change.replacement, change.location)
            :delete -> String.replace(acc, change.target, "")
          end
        end)

      {:ok, corrected}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp insert_at_position(content, text, %{position: :end}) do
    content <> text
  end

  defp insert_at_position(content, text, %{position: :beginning}) do
    text <> content
  end

  defp insert_at_position(content, text, %{line: line}) do
    lines = String.split(content, "\n")
    List.insert_at(lines, line - 1, text) |> Enum.join("\n")
  end

  defp insert_at_position(content, text, _), do: content <> text

  defp valid_syntax?(content, "elixir") do
    case Code.string_to_quoted(content) do
      {:ok, _} -> true
      _ -> false
    end
  end

  # Assume valid for other languages
  defp valid_syntax?(_content, _language), do: true

end
