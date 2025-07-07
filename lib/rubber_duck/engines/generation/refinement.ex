defmodule RubberDuck.Engines.Generation.Refinement do
  @moduledoc """
  Iterative refinement for generated code.

  This module handles the iterative improvement of generated code based on:
  - User feedback
  - Validation results
  - Test execution outcomes
  - Style preferences

  ## Features

  - Multi-iteration refinement
  - Feedback incorporation
  - Incremental improvements
  - Quality tracking
  - Convergence detection
  """

  require Logger

  @type refinement_request :: %{
          required(:code) => String.t(),
          required(:feedback) => feedback(),
          required(:language) => atom(),
          required(:original_prompt) => String.t(),
          required(:iteration) => integer(),
          required(:context) => map()
        }

  @type feedback :: %{
          required(:type) => feedback_type(),
          required(:message) => String.t(),
          optional(:specific_issues) => [issue()],
          optional(:suggestions) => [String.t()]
        }

  @type feedback_type :: :error | :improvement | :style | :performance | :clarity

  @type issue :: %{
          required(:line) => integer() | nil,
          required(:description) => String.t(),
          required(:severity) => :error | :warning | :info
        }

  @type refinement_result :: %{
          required(:refined_code) => String.t(),
          required(:changes_made) => [change()],
          required(:iteration) => integer(),
          required(:converged) => boolean(),
          required(:confidence) => float()
        }

  @type change :: %{
          required(:type) => change_type(),
          required(:description) => String.t(),
          required(:before) => String.t() | nil,
          required(:after) => String.t() | nil
        }

  @type change_type :: :fix | :enhancement | :refactor | :style | :documentation

  @max_iterations 5
  @convergence_threshold 0.95

  @doc """
  Refine generated code based on feedback.

  Iteratively improves the code until:
  - Maximum iterations reached
  - Convergence detected
  - No more improvements possible
  """
  @spec refine_code(refinement_request()) :: {:ok, refinement_result()} | {:error, term()}
  def refine_code(request) do
    if request.iteration >= @max_iterations do
      {:ok, build_final_result(request.code, request.iteration, false)}
    else
      {:ok, refined_code, changes} = apply_refinement(request)

      if converged?(request.code, refined_code, changes) do
        {:ok, build_final_result(refined_code, request.iteration + 1, true)}
      else
        # Continue refinement if needed
        new_request = %{request | code: refined_code, iteration: request.iteration + 1}

        if auto_refinement_needed?(changes) do
          refine_code(new_request)
        else
          {:ok, build_result(refined_code, changes, request.iteration + 1, false)}
        end
      end
    end
  end

  @doc """
  Apply a single refinement iteration.
  """
  @spec apply_refinement(refinement_request()) :: {:ok, String.t(), [change()]} | {:error, term()}
  def apply_refinement(request) do
    refined_code = request.code

    # Apply refinements based on feedback type
    {refined_code, changes} =
      case request.feedback.type do
        :error ->
          fix_errors(refined_code, request.feedback, request.language)

        :improvement ->
          apply_improvements(refined_code, request.feedback, request.language)

        :style ->
          apply_style_fixes(refined_code, request.feedback, request.language)

        :performance ->
          optimize_performance(refined_code, request.feedback, request.language)

        :clarity ->
          improve_clarity(refined_code, request.feedback, request.language)
      end

    # Apply general refinements
    {refined_code, additional_changes} =
      apply_general_refinements(
        refined_code,
        request.language,
        request.context
      )

    all_changes = changes ++ additional_changes

    {:ok, refined_code, all_changes}
  end

  @doc """
  Check if refinement has converged.
  """
  @spec converged?(String.t(), String.t(), [change()]) :: boolean()
  def converged?(original_code, refined_code, changes) do
    # Check if changes are minimal
    if original_code == refined_code do
      true
    else
      # Calculate change ratio
      change_ratio = calculate_change_ratio(original_code, refined_code)

      # Check if only minor changes were made
      minor_changes_only = Enum.all?(changes, &minor_change?/1)

      change_ratio < 0.05 and minor_changes_only
    end
  end

  # Private functions

  defp fix_errors(code, feedback, language) do
    issues = Map.get(feedback, :specific_issues, [])

    {fixed_code, changes} =
      Enum.reduce(issues, {code, []}, fn issue, {current_code, changes_acc} ->
        case fix_issue(current_code, issue, language) do
          {:ok, fixed, change} ->
            {fixed, [change | changes_acc]}

          {:error, _} ->
            {current_code, changes_acc}
        end
      end)

    {fixed_code, Enum.reverse(changes)}
  end

  defp fix_issue(code, issue, :elixir) do
    case issue.description do
      "Unbalanced" <> _ ->
        fixed = fix_unbalanced_delimiters(code)

        change = %{
          type: :fix,
          description: "Fixed unbalanced delimiters",
          before: nil,
          after: nil
        }

        {:ok, fixed, change}

      "Undefined function" <> rest ->
        function_name = extract_function_name(rest)
        fixed = add_function_definition(code, function_name)

        change = %{
          type: :fix,
          description: "Added missing function: #{function_name}",
          before: nil,
          after: "def #{function_name}"
        }

        {:ok, fixed, change}

      _ ->
        {:error, :unknown_issue}
    end
  end

  defp fix_issue(_code, _issue, _language) do
    {:error, :unsupported_language}
  end

  defp fix_unbalanced_delimiters(code) do
    # Count delimiters
    delimiters = [
      {"(", ")"}
    ]

    Enum.reduce(delimiters, code, fn {open, close}, current_code ->
      open_count = count_occurrences(current_code, open)
      close_count = count_occurrences(current_code, close)

      cond do
        open_count > close_count ->
          # Add missing closing delimiters
          missing = open_count - close_count
          current_code <> String.duplicate(")", missing)

        close_count > open_count ->
          # Remove extra closing delimiters (harder, so just log)
          Logger.warning("Extra closing delimiter: #{close}")
          current_code

        true ->
          current_code
      end
    end)
  end

  defp count_occurrences(string, substring) do
    string
    |> String.split(substring)
    |> length()
    |> Kernel.-(1)
  end

  defp extract_function_name(description) do
    case Regex.run(~r/`(\w+)`/, description) do
      [_, name] -> name
      _ -> "undefined_function"
    end
  end

  defp add_function_definition(code, function_name) do
    # Add a stub function definition
    function_def = """

    def #{function_name}(args) do
      # TODO: Implement #{function_name}
      {:ok, args}
    end
    """

    # Add before the last 'end' if it's a module
    if String.contains?(code, "defmodule") do
      parts = String.split(code, ~r/\nend\s*$/)

      case parts do
        [module_body] -> module_body <> function_def <> "\nend"
        [module_body, rest] -> module_body <> function_def <> "\nend" <> rest
        _ -> code <> function_def
      end
    else
      code <> function_def
    end
  end

  defp apply_improvements(code, feedback, language) do
    suggestions = Map.get(feedback, :suggestions, [])

    {improved_code, changes} =
      Enum.reduce(suggestions, {code, []}, fn suggestion, {current_code, changes_acc} ->
        case apply_suggestion(current_code, suggestion, language) do
          {:ok, improved, change} ->
            {improved, [change | changes_acc]}

          {:error, _} ->
            {current_code, changes_acc}
        end
      end)

    {improved_code, Enum.reverse(changes)}
  end

  defp apply_suggestion(code, suggestion, :elixir) do
    cond do
      String.contains?(suggestion, "pattern matching") ->
        improved = improve_pattern_matching(code)

        change = %{
          type: :enhancement,
          description: "Improved pattern matching",
          before: nil,
          after: nil
        }

        {:ok, improved, change}

      String.contains?(suggestion, "error handling") ->
        improved = improve_error_handling(code)

        change = %{
          type: :enhancement,
          description: "Enhanced error handling",
          before: nil,
          after: nil
        }

        {:ok, improved, change}

      true ->
        {:error, :unknown_suggestion}
    end
  end

  defp apply_suggestion(_code, _suggestion, _language) do
    {:error, :unsupported_language}
  end

  defp improve_pattern_matching(code) do
    # Replace if-else with pattern matching where possible
    code
    |> String.replace(~r/if\s+(.+?)\s+do\s+(.+?)\s+else\s+(.+?)\s+end/s, fn [
                                                                              _full_match,
                                                                              condition,
                                                                              true_branch,
                                                                              false_branch
                                                                            ] ->
      # Simple conversion to case
      """
      case #{condition} do
        true -> #{true_branch}
        false -> #{false_branch}
      end
      """
    end)
  end

  defp improve_error_handling(code) do
    # Add error handling to functions that don't have it
    code
    |> String.replace(~r/def\s+(\w+)\((.+?)\)\s+do\s+([^}]+?)end/m, fn [full_match, name, args, body] ->
      if String.contains?(body, "{:ok") or String.contains?(body, "{:error") do
        # Already has error handling
        full_match
      else
        # Wrap in error handling
        """
        def #{name}(#{args}) do
          try do
            result = #{String.trim(body)}
            {:ok, result}
          rescue
            e -> {:error, Exception.message(e)}
          end
        end
        """
      end
    end)
  end

  defp apply_style_fixes(code, _feedback, :elixir) do
    # changes will be computed below

    # Apply Elixir style conventions
    styled_code =
      code
      |> fix_indentation()
      |> fix_line_length()
      |> fix_naming_conventions()
      |> add_moduledoc_if_missing()

    changes =
      if styled_code != code do
        [
          %{
            type: :style,
            description: "Applied Elixir style conventions",
            before: nil,
            after: nil
          }
        ]
      else
        []
      end

    {styled_code, changes}
  end

  defp apply_style_fixes(code, _feedback, _language) do
    {code, []}
  end

  defp fix_indentation(code) do
    # Simple indentation fix - 2 spaces per level
    lines = String.split(code, "\n")
    indent_level = 0

    fixed_lines =
      Enum.map(lines, fn line ->
        trimmed = String.trim_leading(line)

        # Decrease indent for end, else, rescue, catch
        indent_level =
          if Regex.match?(~r/^\s*(end|else|rescue|catch)/, line) do
            max(0, indent_level - 1)
          else
            indent_level
          end

        # Apply indentation
        indented = String.duplicate("  ", indent_level) <> trimmed

        # Increase indent after do, ->, else, rescue, catch
        _indent_level =
          if Regex.match?(~r/(do|->|else|rescue|catch)\s*$/, trimmed) do
            indent_level + 1
          else
            indent_level
          end

        indented
      end)

    Enum.join(fixed_lines, "\n")
  end

  defp fix_line_length(code) do
    # Break long lines (> 98 chars) at appropriate points
    lines = String.split(code, "\n")

    Enum.map(lines, fn line ->
      if String.length(line) > 98 do
        break_long_line(line)
      else
        line
      end
    end)
    |> Enum.join("\n")
  end

  defp break_long_line(line) do
    # Simple breaking at commas or pipes
    cond do
      String.contains?(line, "|>") ->
        parts = String.split(line, "|>")
        indent = get_indent(line)

        parts
        |> Enum.with_index()
        |> Enum.map(fn {part, i} ->
          if i == 0 do
            String.trim_trailing(part)
          else
            indent <> "  |> " <> String.trim(part)
          end
        end)
        |> Enum.join("\n")

      String.contains?(line, ",") ->
        # Break at last comma that keeps line under limit
        # TODO: Implement smart comma breaking
        line

      true ->
        line
    end
  end

  defp get_indent(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, spaces] -> spaces
      _ -> ""
    end
  end

  defp fix_naming_conventions(code) do
    # Fix common naming issues
    code
    # No CamelCase functions
    |> String.replace(~r/def\s+([A-Z]\w*)/, "def \\1")
    |> String.replace(~r/defmodule\s+([a-z]\w*)/, fn [_, name] ->
      "defmodule " <> Macro.camelize(name)
    end)
  end

  defp add_moduledoc_if_missing(code) do
    if String.contains?(code, "defmodule") and not String.contains?(code, "@moduledoc") do
      String.replace(
        code,
        ~r/(defmodule\s+[\w.]+\s+do)\n/,
        "\\1\n  @moduledoc \"\"\"\n  TODO: Add module documentation\n  \"\"\"\n\n"
      )
    else
      code
    end
  end

  defp optimize_performance(code, _feedback, :elixir) do
    # changes will be computed below

    optimized =
      code
      |> optimize_enum_operations()
      |> optimize_string_operations()
      |> optimize_list_operations()

    changes =
      if optimized != code do
        [
          %{
            type: :performance,
            description: "Applied performance optimizations",
            before: nil,
            after: nil
          }
        ]
      else
        []
      end

    {optimized, changes}
  end

  defp optimize_performance(code, _feedback, _language) do
    {code, []}
  end

  defp optimize_enum_operations(code) do
    # Replace multiple Enum operations with single pass
    code
    |> String.replace(
      ~r/Enum\.map\((.+?),\s*(.+?)\)\s*\|>\s*Enum\.filter\((.+?)\)/,
      "Enum.filter_map(\\1, \\3, \\2)"
    )
    |> String.replace(
      ~r/Enum\.map\((.+?),\s*(.+?)\)\s*\|>\s*Enum\.map\((.+?)\)/,
      "Enum.map(\\1, fn x -> x |> \\2 |> \\3 end)"
    )
  end

  defp optimize_string_operations(code) do
    # Use iolist for string building
    code
    |> String.replace(
      ~r/Enum\.reduce\((.+?),\s*"",\s*fn\s*(.+?),\s*acc\s*->\s*acc\s*<>\s*(.+?)\s*end\)/,
      "Enum.map(\\1, fn \\2 -> \\3 end) |> Enum.join()"
    )
  end

  defp optimize_list_operations(code) do
    # Replace ++ with [elem | list] where appropriate
    # TODO: Implement list optimization
    code
  end

  defp improve_clarity(code, _feedback, language) do
    # changes will be computed below

    clarified =
      code
      |> add_type_specs(language)
      |> improve_variable_names()
      |> add_inline_documentation()

    changes =
      if clarified != code do
        [
          %{
            type: :clarity,
            description: "Improved code clarity",
            before: nil,
            after: nil
          }
        ]
      else
        []
      end

    {clarified, changes}
  end

  defp add_type_specs(code, :elixir) do
    # Add @spec annotations to public functions
    code
    |> String.replace(~r/(\n\s*)def\s+(\w+)\((.*?)\)\s+do/, fn [full, indent, name, args] ->
      if String.contains?(full, "@spec") do
        # Already has spec
        full
      else
        # Generate simple spec
        arg_count =
          if args == "" do
            0
          else
            length(String.split(args, ","))
          end

        arg_types = List.duplicate("any()", arg_count) |> Enum.join(", ")

        spec =
          if arg_count > 0 do
            "#{indent}@spec #{name}(#{arg_types}) :: any()\n"
          else
            "#{indent}@spec #{name}() :: any()\n"
          end

        spec <> full
      end
    end)
  end

  defp add_type_specs(_language, code), do: code

  defp improve_variable_names(code) do
    # Replace single letter variables with descriptive names
    code
    |> String.replace(~r/\b([a-z])\s*=\s*/, fn [full, var] ->
      if var in ["i", "j", "k"] do
        "index ="
      else
        full
      end
    end)
  end

  defp add_inline_documentation(code) do
    # Add comments for complex operations
    code
    |> String.replace(~r/(Enum\.reduce\(.+?\))/m, fn [_full, expr] ->
      "# Aggregate values\n    " <> expr
    end)
  end

  defp apply_general_refinements(code, language, context) do
    # changes will be computed below

    # Apply language-specific general improvements
    refined =
      case language do
        :elixir -> apply_elixir_refinements(code, context)
        _ -> code
      end

    changes =
      if refined != code do
        [
          %{
            type: :refactor,
            description: "Applied general refinements",
            before: nil,
            after: nil
          }
        ]
      else
        []
      end

    {refined, changes}
  end

  defp apply_elixir_refinements(code, _context) do
    code
    |> prefer_pattern_matching()
    |> use_pipe_operator()
    |> extract_constants()
  end

  defp prefer_pattern_matching(code) do
    # Convert certain if statements to pattern matching
    code
    |> String.replace(~r/if\s+is_nil\((.+?)\)\s+do\s+(.+?)\s+else\s+(.+?)\s+end/s, fn
      [_full_match, var, nil_case, else_case] ->
        """
        case #{var} do
          nil -> #{nil_case}
          value -> #{else_case}
        end
        """

      match when is_binary(match) ->
        # If the regex didn't match properly, return the original
        match
    end)
  end

  defp use_pipe_operator(code) do
    # Convert nested function calls to pipe operator
    # This is complex, so just a simple example
    code
    |> String.replace(~r/(\w+)\((\w+)\((.+?)\)\)/, "\\3 |> \\2() |> \\1()")
  end

  defp extract_constants(code) do
    # Extract magic numbers to module attributes
    numbers =
      Regex.scan(~r/\b(\d{2,})\b/, code)
      |> Enum.map(&List.first/1)
      |> Enum.uniq()

    if length(numbers) > 0 and String.contains?(code, "defmodule") do
      # Add module attributes
      attributes =
        numbers
        |> Enum.map(fn num ->
          "@default_#{num} #{num}"
        end)
        |> Enum.join("\n  ")

      code
      |> String.replace(~r/(defmodule\s+.+\s+do)\n/, "\\g{1}\n  #{attributes}\n\n")
      |> then(fn updated ->
        # Replace numbers with attributes
        Enum.reduce(numbers, updated, fn num, acc ->
          String.replace(acc, ~r/\b#{num}\b/, "@default_#{num}")
        end)
      end)
    else
      code
    end
  end

  defp calculate_change_ratio(original, refined) do
    original_lines = String.split(original, "\n")
    refined_lines = String.split(refined, "\n")

    # Simple line-based diff
    total_lines = max(length(original_lines), length(refined_lines))
    changed_lines = calculate_line_diff(original_lines, refined_lines)

    if total_lines == 0 do
      0.0
    else
      changed_lines / total_lines
    end
  end

  defp calculate_line_diff(lines1, lines2) do
    # Count different lines
    max_len = max(length(lines1), length(lines2))

    0..(max_len - 1)
    |> Enum.count(fn i ->
      line1 = Enum.at(lines1, i, "")
      line2 = Enum.at(lines2, i, "")
      line1 != line2
    end)
  end

  defp minor_change?(%{type: type}) do
    type in [:style, :documentation]
  end

  defp auto_refinement_needed?(changes) do
    # Check if automatic refinement should continue
    Enum.any?(changes, fn change ->
      change.type in [:error, :fix]
    end)
  end

  defp build_result(code, changes, iteration, converged) do
    %{
      refined_code: code,
      changes_made: changes,
      iteration: iteration,
      converged: converged,
      confidence: calculate_confidence(changes, iteration)
    }
  end

  defp build_final_result(code, iteration, converged) do
    %{
      refined_code: code,
      changes_made: [],
      iteration: iteration,
      converged: converged,
      confidence: if(converged, do: @convergence_threshold, else: 0.8)
    }
  end

  defp calculate_confidence(changes, iteration) do
    # Confidence decreases with more changes and iterations
    base_confidence = 0.9
    change_penalty = length(changes) * 0.05
    iteration_penalty = iteration * 0.1

    max(0.5, base_confidence - change_penalty - iteration_penalty)
  end
end
