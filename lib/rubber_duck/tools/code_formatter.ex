defmodule RubberDuck.Tools.CodeFormatter do
  @moduledoc """
  Formats Elixir code using standard formatter rules.
  
  This tool applies Elixir's built-in code formatter with support
  for custom formatting options and project-specific configurations.
  """
  
  use RubberDuck.Tool
  
  tool do
    name :code_formatter
    description "Formats Elixir code using standard formatter rules"
    category :code_quality
    version "1.0.0"
    tags [:formatting, :style, :quality, :consistency]
    
    parameter :code do
      type :string
      required true
      description "The Elixir code to format"
      constraints [
        min_length: 1,
        max_length: 100_000
      ]
    end
    
    parameter :line_length do
      type :integer
      required false
      description "Maximum line length"
      default 98
      constraints [
        min: 40,
        max: 200
      ]
    end
    
    parameter :locals_without_parens do
      type :list
      required false
      description "Functions to format without parentheses"
      default []
      item_type :string
    end
    
    parameter :force_do_end_blocks do
      type :boolean
      required false
      description "Force do/end blocks instead of keywords"
      default false
    end
    
    parameter :normalize_bitstring_modifiers do
      type :boolean
      required false
      description "Normalize bitstring modifiers"
      default true
    end
    
    parameter :normalize_charlists do
      type :boolean
      required false
      description "Convert 'strings' to ~c'strings'"
      default true
    end
    
    parameter :check_equivalent do
      type :boolean
      required false
      description "Verify formatted code is semantically equivalent"
      default true
    end
    
    parameter :file_path do
      type :string
      required false
      description "File path for context (affects formatter config lookup)"
      default nil
    end
    
    parameter :use_project_formatter do
      type :boolean
      required false
      description "Use project's .formatter.exs if available"
      default true
    end
    
    execution do
      handler &__MODULE__.execute/2
      timeout 10_000
      async true
      retries 1
    end
    
    security do
      sandbox :restricted
      capabilities [:code_analysis]
      rate_limit 200
    end
  end
  
  @doc """
  Executes code formatting based on the provided parameters.
  """
  def execute(params, context) do
    with {:ok, validated} <- validate_code(params.code),
         {:ok, formatter_opts} <- build_formatter_options(params, context),
         {:ok, formatted} <- format_code(validated, formatter_opts),
         {:ok, verified} <- verify_formatting(params.code, formatted, params) do
      
      analysis = analyze_changes(params.code, formatted)
      
      {:ok, %{
        formatted_code: formatted,
        changed: params.code != formatted,
        analysis: analysis,
        options_used: formatter_opts,
        warnings: analysis.warnings
      }}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  defp validate_code(code) do
    case Code.string_to_quoted(code) do
      {:ok, _ast} -> 
        {:ok, code}
      {:error, {meta, message, token}} ->
        line = Keyword.get(meta, :line, 1)
        column = Keyword.get(meta, :column, 1)
        {:error, "Syntax error at line #{line}, column #{column}: #{message} #{inspect(token)}"}
    end
  end
  
  defp build_formatter_options(params, context) do
    # Start with default options
    opts = [
      line_length: params.line_length,
      normalize_bitstring_modifiers: params.normalize_bitstring_modifiers,
      normalize_charlists_as_sigils: params.normalize_charlists
    ]
    
    # Add locals_without_parens if provided
    opts = if params.locals_without_parens != [] do
      locals = params.locals_without_parens
      |> Enum.map(&parse_local_spec/1)
      |> Enum.reject(&is_nil/1)
      
      Keyword.put(opts, :locals_without_parens, locals)
    else
      opts
    end
    
    # Add force_do_end_blocks if enabled
    opts = if params.force_do_end_blocks do
      Keyword.put(opts, :force_do_end_blocks, true)
    else
      opts
    end
    
    # Try to load project formatter config
    opts = if params.use_project_formatter do
      merge_project_formatter_config(opts, params, context)
    else
      opts
    end
    
    {:ok, opts}
  end
  
  defp parse_local_spec(spec) when is_binary(spec) do
    case String.split(spec, ":") do
      [name, arity] ->
        case Integer.parse(arity) do
          {arity_int, ""} -> {String.to_atom(name), arity_int}
          _ -> nil
        end
      [name] ->
        {String.to_atom(name), :*}
      _ ->
        nil
    end
  end
  
  defp merge_project_formatter_config(opts, params, context) do
    formatter_path = find_formatter_config(params.file_path, context)
    
    if formatter_path && File.exists?(formatter_path) do
      case load_formatter_config(formatter_path) do
        {:ok, project_opts} ->
          # Merge options, with params taking precedence
          Keyword.merge(project_opts, opts)
        _ ->
          opts
      end
    else
      opts
    end
  end
  
  defp find_formatter_config(nil, context) do
    project_root = context[:project_root] || File.cwd!()
    Path.join(project_root, ".formatter.exs")
  end
  
  defp find_formatter_config(file_path, context) do
    # Search up the directory tree for .formatter.exs
    dir = Path.dirname(file_path)
    project_root = context[:project_root] || File.cwd!()
    
    find_formatter_in_ancestors(dir, project_root)
  end
  
  defp find_formatter_in_ancestors(dir, root) do
    formatter_path = Path.join(dir, ".formatter.exs")
    
    cond do
      File.exists?(formatter_path) ->
        formatter_path
      
      dir == root || dir == "/" ->
        Path.join(root, ".formatter.exs")
      
      true ->
        find_formatter_in_ancestors(Path.dirname(dir), root)
    end
  end
  
  defp load_formatter_config(path) do
    try do
      {config, _} = Code.eval_file(path)
      {:ok, config}
    rescue
      _ -> {:error, "Failed to load formatter config"}
    end
  end
  
  defp format_code(code, opts) do
    try do
      formatted = Code.format_string!(code, opts)
      |> IO.iodata_to_binary()
      
      {:ok, formatted}
    rescue
      e -> 
        {:error, "Formatting failed: #{inspect(e)}"}
    end
  end
  
  defp verify_formatting(original, formatted, params) do
    if params.check_equivalent do
      with {:ok, original_ast} <- Code.string_to_quoted(original, []),
           {:ok, formatted_ast} <- Code.string_to_quoted(formatted, []) do
        
        if equivalent_ast?(original_ast, formatted_ast) do
          {:ok, :verified}
        else
          {:error, "Formatted code is not semantically equivalent to original"}
        end
      else
        _ -> {:error, "Failed to verify formatting equivalence"}
      end
    else
      {:ok, :not_checked}
    end
  end
  
  defp equivalent_ast?(ast1, ast2) do
    # Normalize ASTs for comparison
    normalize_ast(ast1) == normalize_ast(ast2)
  end
  
  defp normalize_ast(ast) do
    Macro.postwalk(ast, fn
      # Remove line/column metadata
      {form, _meta, args} -> {form, [], args}
      # Normalize charlists
      {:sigil_c, _, [{:<<>>, _, _}, _]} = node -> node
      list when is_list(list) ->
        if List.ascii_printable?(list), do: list, else: list
      other -> other
    end)
  end
  
  defp analyze_changes(original, formatted) do
    original_lines = String.split(original, "\n")
    formatted_lines = String.split(formatted, "\n")
    
    analysis = %{
      lines_changed: count_changed_lines(original_lines, formatted_lines),
      original_line_count: length(original_lines),
      formatted_line_count: length(formatted_lines),
      formatting_issues: detect_formatting_issues(original),
      improvements: detect_improvements(original, formatted),
      warnings: []
    }
    
    # Add warnings
    warnings = []
    
    warnings = if analysis.lines_changed > length(original_lines) * 0.5 do
      ["More than 50% of lines changed - significant reformatting" | warnings]
    else
      warnings
    end
    
    warnings = if formatted == "" && original != "" do
      ["Formatted code is empty - possible formatting error" | warnings]
    else
      warnings
    end
    
    %{analysis | warnings: warnings}
  end
  
  defp count_changed_lines(original, formatted) do
    max_length = max(length(original), length(formatted))
    
    0..(max_length - 1)
    |> Enum.count(fn i ->
      Enum.at(original, i) != Enum.at(formatted, i)
    end)
  end
  
  defp detect_formatting_issues(code) do
    issues = []
    
    issues = if String.contains?(code, "\t") do
      [:tabs_used | issues]
    else
      issues
    end
    
    issues = if Regex.match?(~r/\s+$/, code) do
      [:trailing_whitespace | issues]
    else
      issues
    end
    
    issues = if String.contains?(code, "\r\n") do
      [:windows_line_endings | issues]
    else
      issues
    end
    
    lines = String.split(code, "\n")
    long_lines = Enum.count(lines, &(String.length(&1) > 98))
    
    issues = if long_lines > 0 do
      [{:long_lines, long_lines} | issues]
    else
      issues
    end
    
    # Check for inconsistent spacing
    issues = if Regex.match?(~r/\( \w|\w \)/, code) do
      [:inconsistent_parentheses_spacing | issues]
    else
      issues
    end
    
    issues = if Regex.match?(~r/\[ \w|\w \]/, code) do
      [:inconsistent_bracket_spacing | issues]
    else
      issues
    end
    
    Enum.reverse(issues)
  end
  
  defp detect_improvements(original, formatted) do
    improvements = []
    
    # Check if line count decreased (more compact)
    original_lines = String.split(original, "\n") |> length()
    formatted_lines = String.split(formatted, "\n") |> length()
    
    improvements = if formatted_lines < original_lines do
      [:more_compact | improvements]
    else
      improvements
    end
    
    # Check if trailing whitespace was removed
    improvements = if Regex.match?(~r/\s+$/, original) && !Regex.match?(~r/\s+$/, formatted) do
      [:removed_trailing_whitespace | improvements]
    else
      improvements
    end
    
    # Check if indentation is now consistent
    improvements = if has_inconsistent_indentation?(original) && !has_inconsistent_indentation?(formatted) do
      [:fixed_indentation | improvements]
    else
      improvements
    end
    
    # Check if parentheses were normalized
    improvements = if count_parentheses_styles(original) > count_parentheses_styles(formatted) do
      [:normalized_parentheses | improvements]
    else
      improvements
    end
    
    Enum.reverse(improvements)
  end
  
  defp has_inconsistent_indentation?(code) do
    lines = String.split(code, "\n")
    indentations = lines
    |> Enum.map(&get_indentation_level/1)
    |> Enum.reject(&(&1 == 0))
    
    # Check if there's a mix of different indentation multiples
    case indentations do
      [] -> false
      [_] -> false
      list ->
        gcd = Enum.reduce(list, &Integer.gcd/2)
        Enum.any?(list, &(rem(&1, 2) != rem(gcd, 2)))
    end
  end
  
  defp get_indentation_level(line) do
    case Regex.run(~r/^(\s*)/, line) do
      [_, spaces] -> String.length(spaces)
      _ -> 0
    end
  end
  
  defp count_parentheses_styles(code) do
    styles = 0
    styles = if Regex.match?(~r/\w\(/, code), do: styles + 1, else: styles
    styles = if Regex.match?(~r/\w \(/, code), do: styles + 1, else: styles
    styles
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end