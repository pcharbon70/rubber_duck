defmodule RubberDuck.Tools.CodeComparer do
  @moduledoc """
  Compares two code versions and highlights semantic differences.
  
  This tool performs detailed comparison of Elixir code, identifying
  structural, semantic, and syntactic differences between versions.
  """
  
  use RubberDuck.Tool
  
  tool do
    name :code_comparer
    description "Compares two code versions and highlights semantic differences"
    category :analysis
    version "1.0.0"
    tags [:comparison, :diff, :analysis, :version]
    
    parameter :code_a do
      type :string
      required true
      description "First version of code to compare"
      constraints [
        min_length: 1,
        max_length: 50_000
      ]
    end
    
    parameter :code_b do
      type :string
      required true
      description "Second version of code to compare"
      constraints [
        min_length: 1,
        max_length: 50_000
      ]
    end
    
    parameter :comparison_type do
      type :string
      required false
      description "Type of comparison to perform"
      default "comprehensive"
      constraints [
        enum: [
          "comprehensive",  # Full analysis
          "semantic",      # Semantic differences only
          "structural",    # AST structure differences
          "textual",       # Line-by-line text diff
          "functional"     # Function signature changes
        ]
      ]
    end
    
    parameter :ignore_whitespace do
      type :boolean
      required false
      description "Ignore whitespace differences"
      default true
    end
    
    parameter :ignore_comments do
      type :boolean
      required false
      description "Ignore comment differences"
      default false
    end
    
    parameter :context_lines do
      type :integer
      required false
      description "Number of context lines around differences"
      default 3
      constraints [
        min: 0,
        max: 10
      ]
    end
    
    parameter :highlight_moves do
      type :boolean
      required false
      description "Detect and highlight moved code blocks"
      default true
    end
    
    parameter :similarity_threshold do
      type :float
      required false
      description "Threshold for considering code blocks similar (0.0-1.0)"
      default 0.8
      constraints [
        min: 0.0,
        max: 1.0
      ]
    end
    
    parameter :output_format do
      type :string
      required false
      description "Format for the comparison output"
      default "structured"
      constraints [
        enum: ["structured", "unified", "side_by_side", "json"]
      ]
    end
    
    execution do
      handler &__MODULE__.execute/2
      timeout 20_000
      async true
      retries 1
    end
    
    security do
      sandbox :strict
      capabilities [:code_analysis]
      rate_limit [max_requests: 50, window_seconds: 60]
    end
  end
  
  @doc """
  Executes code comparison based on the provided parameters.
  """
  def execute(params, context) do
    with {:ok, preprocessed} <- preprocess_code(params),
         {:ok, parsed} <- parse_both_versions(preprocessed),
         {:ok, differences} <- analyze_differences(parsed, params),
         {:ok, categorized} <- categorize_differences(differences, params),
         {:ok, formatted} <- format_output(categorized, params) do
      
      {:ok, %{
        comparison: formatted,
        summary: %{
          total_differences: count_differences(categorized),
          difference_types: get_difference_types(categorized),
          similarity_score: calculate_similarity_score(categorized),
          significant_changes: count_significant_changes(categorized)
        },
        statistics: calculate_statistics(parsed, categorized),
        metadata: %{
          comparison_type: params.comparison_type,
          ignored_whitespace: params.ignore_whitespace,
          ignored_comments: params.ignore_comments
        }
      }}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  defp preprocess_code(params) do
    code_a = if params.ignore_whitespace do
      normalize_whitespace(params.code_a)
    else
      params.code_a
    end
    
    code_b = if params.ignore_whitespace do
      normalize_whitespace(params.code_b)
    else
      params.code_b
    end
    
    code_a = if params.ignore_comments do
      remove_comments(code_a)
    else
      code_a
    end
    
    code_b = if params.ignore_comments do
      remove_comments(code_b)
    else
      code_b
    end
    
    {:ok, %{code_a: code_a, code_b: code_b}}
  end
  
  defp normalize_whitespace(code) do
    code
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.join("\n")
    |> String.replace(~r/\s+/, " ")
  end
  
  defp remove_comments(code) do
    code
    |> String.split("\n")
    |> Enum.map(fn line ->
      case String.split(line, "#", parts: 2) do
        [code_part, _comment] -> String.trim_trailing(code_part)
        [code_part] -> code_part
      end
    end)
    |> Enum.join("\n")
  end
  
  defp parse_both_versions(preprocessed) do
    with {:ok, ast_a} <- safe_parse(preprocessed.code_a),
         {:ok, ast_b} <- safe_parse(preprocessed.code_b) do
      
      {:ok, %{
        code_a: preprocessed.code_a,
        code_b: preprocessed.code_b,
        ast_a: ast_a,
        ast_b: ast_b,
        lines_a: String.split(preprocessed.code_a, "\n"),
        lines_b: String.split(preprocessed.code_b, "\n")
      }}
    else
      {:error, reason} -> {:error, "Failed to parse code: #{reason}"}
    end
  end
  
  defp safe_parse(code) do
    case Code.string_to_quoted(code) do
      {:ok, ast} -> {:ok, ast}
      {:error, {line, error, token}} ->
        {:error, "Parse error on line #{line}: #{error} #{inspect(token)}"}
    end
  end
  
  defp analyze_differences(parsed, params) do
    differences = case params.comparison_type do
      "comprehensive" -> perform_comprehensive_analysis(parsed, params)
      "semantic" -> analyze_semantic_differences(parsed, params)
      "structural" -> analyze_structural_differences(parsed, params)
      "textual" -> analyze_textual_differences(parsed, params)
      "functional" -> analyze_functional_differences(parsed, params)
    end
    
    {:ok, differences}
  end
  
  defp perform_comprehensive_analysis(parsed, params) do
    [
      analyze_textual_differences(parsed, params),
      analyze_structural_differences(parsed, params),
      analyze_semantic_differences(parsed, params),
      analyze_functional_differences(parsed, params)
    ]
    |> List.flatten()
    |> Enum.uniq_by(&{&1.type, &1.location})
  end
  
  defp analyze_textual_differences(parsed, params) do
    lines_a = parsed.lines_a
    lines_b = parsed.lines_b
    
    diff_ops = compute_diff(lines_a, lines_b)
    
    diff_ops
    |> Enum.with_index()
    |> Enum.flat_map(fn {op, index} ->
      case op do
        {:add, line, line_num} ->
          [%{
            type: :addition,
            location: %{line: line_num, column: 0},
            content: line,
            context: extract_context(lines_b, line_num - 1, params.context_lines),
            significance: assess_line_significance(line)
          }]
        
        {:delete, line, line_num} ->
          [%{
            type: :deletion,
            location: %{line: line_num, column: 0},
            content: line,
            context: extract_context(lines_a, line_num - 1, params.context_lines),
            significance: assess_line_significance(line)
          }]
        
        {:change, old_line, new_line, line_num} ->
          [%{
            type: :modification,
            location: %{line: line_num, column: 0},
            old_content: old_line,
            new_content: new_line,
            context: extract_context(lines_b, line_num - 1, params.context_lines),
            significance: assess_change_significance(old_line, new_line)
          }]
        
        {:equal, _, _} ->
          []
      end
    end)
  end
  
  defp compute_diff(lines_a, lines_b) do
    # Simple diff algorithm - in production would use Myers or similar
    max_len = max(length(lines_a), length(lines_b))
    
    0..(max_len - 1)
    |> Enum.map(fn i ->
      line_a = Enum.at(lines_a, i)
      line_b = Enum.at(lines_b, i)
      
      cond do
        line_a == line_b -> {:equal, line_a, i + 1}
        line_a == nil -> {:add, line_b, i + 1}
        line_b == nil -> {:delete, line_a, i + 1}
        true -> {:change, line_a, line_b, i + 1}
      end
    end)
  end
  
  defp extract_context(lines, center_index, context_lines) do
    start_idx = max(0, center_index - context_lines)
    end_idx = min(length(lines) - 1, center_index + context_lines)
    
    lines
    |> Enum.slice(start_idx..end_idx)
    |> Enum.with_index(start_idx)
    |> Enum.map(fn {line, idx} ->
      %{line_number: idx + 1, content: line, is_target: idx == center_index}
    end)
  end
  
  defp assess_line_significance(line) do
    cond do
      String.trim(line) == "" -> :trivial
      String.contains?(line, ["def ", "defp ", "defmodule"]) -> :critical
      String.contains?(line, ["@spec", "@doc", "@type"]) -> :important
      String.contains?(line, ["import", "alias", "use"]) -> :important
      String.match?(line, ~r/^\s*#/) -> :trivial
      true -> :normal
    end
  end
  
  defp assess_change_significance(old_line, new_line) do
    old_significance = assess_line_significance(old_line)
    new_significance = assess_line_significance(new_line)
    
    case {old_significance, new_significance} do
      {:critical, :critical} -> :critical
      {_, :critical} -> :critical
      {:critical, _} -> :critical
      {:important, :important} -> :important
      {_, :important} -> :important
      {:important, _} -> :important
      _ -> :normal
    end
  end
  
  defp analyze_structural_differences(parsed, _params) do
    structure_a = extract_ast_structure(parsed.ast_a)
    structure_b = extract_ast_structure(parsed.ast_b)
    
    compare_structures(structure_a, structure_b)
  end
  
  defp extract_ast_structure(ast) do
    {_, structure} = Macro.postwalk(ast, [], fn node, acc ->
      case node do
        {:defmodule, meta, [{:__aliases__, _, module_parts} | _]} ->
          module_name = Module.concat(module_parts)
          {node, [{:module, module_name, Keyword.get(meta, :line, 0)} | acc]}
        
        {:def, meta, [{name, _, args} | _]} when is_atom(name) ->
          arity = if args, do: length(args), else: 0
          {node, [{:function, name, arity, Keyword.get(meta, :line, 0)} | acc]}
        
        {:defp, meta, [{name, _, args} | _]} when is_atom(name) ->
          arity = if args, do: length(args), else: 0
          {node, [{:private_function, name, arity, Keyword.get(meta, :line, 0)} | acc]}
        
        {:@, meta, [{attr, _, _}]} when attr in [:spec, :type, :doc] ->
          {node, [{:attribute, attr, Keyword.get(meta, :line, 0)} | acc]}
        
        _ ->
          {node, acc}
      end
    end)
    
    Enum.reverse(structure)
  end
  
  defp compare_structures(structure_a, structure_b) do
    added = structure_b -- structure_a
    removed = structure_a -- structure_b
    
    additions = Enum.map(added, fn item ->
      %{
        type: :structural_addition,
        location: %{line: elem(item, 3), column: 0},
        content: format_structure_item(item),
        significance: assess_structural_significance(item)
      }
    end)
    
    deletions = Enum.map(removed, fn item ->
      %{
        type: :structural_deletion,
        location: %{line: elem(item, 3), column: 0},
        content: format_structure_item(item),
        significance: assess_structural_significance(item)
      }
    end)
    
    additions ++ deletions
  end
  
  defp format_structure_item({:module, name, _line}), do: "module #{name}"
  defp format_structure_item({:function, name, arity, _line}), do: "def #{name}/#{arity}"
  defp format_structure_item({:private_function, name, arity, _line}), do: "defp #{name}/#{arity}"
  defp format_structure_item({:attribute, attr, _line}), do: "@#{attr}"
  defp format_structure_item(item), do: inspect(item)
  
  defp assess_structural_significance({:module, _, _}), do: :critical
  defp assess_structural_significance({:function, _, _, _}), do: :important
  defp assess_structural_significance({:private_function, _, _, _}), do: :normal
  defp assess_structural_significance({:attribute, :spec, _}), do: :important
  defp assess_structural_significance({:attribute, :doc, _}), do: :normal
  defp assess_structural_significance(_), do: :trivial
  
  defp analyze_semantic_differences(parsed, _params) do
    # Analyze semantic meaning changes
    semantic_a = extract_semantic_info(parsed.ast_a)
    semantic_b = extract_semantic_info(parsed.ast_b)
    
    compare_semantics(semantic_a, semantic_b)
  end
  
  defp extract_semantic_info(ast) do
    {_, info} = Macro.postwalk(ast, %{functions: [], calls: [], imports: []}, fn node, acc ->
      case node do
        {:def, _, [{name, _, args} | [body]]} when is_atom(name) ->
          func_info = %{
            name: name,
            arity: if(args, do: length(args), else: 0),
            calls: extract_function_calls(body),
            complexity: estimate_complexity(body)
          }
          {node, update_in(acc.functions, &[func_info | &1])}
        
        {{:., _, [{:__aliases__, _, module_parts}, func_name]}, _, _} ->
          call_info = %{
            module: Module.concat(module_parts),
            function: func_name
          }
          {node, update_in(acc.calls, &[call_info | &1])}
        
        {:import, _, [{:__aliases__, _, module_parts} | _]} ->
          module = Module.concat(module_parts)
          {node, update_in(acc.imports, &[module | &1])}
        
        _ ->
          {node, acc}
      end
    end)
    
    info
  end
  
  defp extract_function_calls(ast) do
    {_, calls} = Macro.postwalk(ast, [], fn node, acc ->
      case node do
        {func_name, _, _} when is_atom(func_name) and func_name not in [:__aliases__, :., :when] ->
          {node, [func_name | acc]}
        _ ->
          {node, acc}
      end
    end)
    
    Enum.uniq(calls)
  end
  
  defp estimate_complexity(ast) do
    {_, complexity} = Macro.postwalk(ast, 0, fn
      {:if, _, _} = node, acc -> {node, acc + 1}
      {:case, _, _} = node, acc -> {node, acc + 2}
      {:cond, _, _} = node, acc -> {node, acc + 2}
      {:with, _, _} = node, acc -> {node, acc + 1}
      node, acc -> {node, acc}
    end)
    
    complexity
  end
  
  defp compare_semantics(semantic_a, semantic_b) do
    # Compare function signatures
    functions_a = Enum.map(semantic_a.functions, &{&1.name, &1.arity})
    functions_b = Enum.map(semantic_b.functions, &{&1.name, &1.arity})
    
    new_functions = functions_b -- functions_a
    removed_functions = functions_a -- functions_b
    
    # Compare complexity changes
    complexity_changes = compare_function_complexity(semantic_a.functions, semantic_b.functions)
    
    # Compare imports
    import_changes = compare_imports(semantic_a.imports, semantic_b.imports)
    
    new_functions ++ removed_functions ++ complexity_changes ++ import_changes
  end
  
  defp compare_function_complexity(functions_a, functions_b) do
    # Compare complexity of matching functions
    common_funcs = find_common_functions(functions_a, functions_b)
    
    Enum.flat_map(common_funcs, fn {func_a, func_b} ->
      if func_a.complexity != func_b.complexity do
        [%{
          type: :complexity_change,
          location: %{line: 0, column: 0},
          content: "#{func_a.name}/#{func_a.arity} complexity: #{func_a.complexity} -> #{func_b.complexity}",
          significance: :important
        }]
      else
        []
      end
    end)
  end
  
  defp find_common_functions(functions_a, functions_b) do
    Enum.flat_map(functions_a, fn func_a ->
      case Enum.find(functions_b, &(&1.name == func_a.name && &1.arity == func_a.arity)) do
        nil -> []
        func_b -> [{func_a, func_b}]
      end
    end)
  end
  
  defp compare_imports(imports_a, imports_b) do
    new_imports = imports_b -- imports_a
    removed_imports = imports_a -- imports_b
    
    additions = Enum.map(new_imports, fn import ->
      %{
        type: :import_addition,
        location: %{line: 0, column: 0},
        content: "import #{import}",
        significance: :normal
      }
    end)
    
    deletions = Enum.map(removed_imports, fn import ->
      %{
        type: :import_removal,
        location: %{line: 0, column: 0},
        content: "import #{import}",
        significance: :normal
      }
    end)
    
    additions ++ deletions
  end
  
  defp analyze_functional_differences(parsed, _params) do
    # Focus on function signature changes
    functions_a = extract_function_signatures(parsed.ast_a)
    functions_b = extract_function_signatures(parsed.ast_b)
    
    added_functions = functions_b -- functions_a
    removed_functions = functions_a -- functions_b
    
    additions = Enum.map(added_functions, fn func ->
      %{
        type: :function_addition,
        location: %{line: func.line, column: 0},
        content: "#{func.visibility} #{func.name}/#{func.arity}",
        significance: :important
      }
    end)
    
    deletions = Enum.map(removed_functions, fn func ->
      %{
        type: :function_removal,
        location: %{line: func.line, column: 0},
        content: "#{func.visibility} #{func.name}/#{func.arity}",
        significance: :important
      }
    end)
    
    additions ++ deletions
  end
  
  defp extract_function_signatures(ast) do
    {_, signatures} = Macro.postwalk(ast, [], fn node, acc ->
      case node do
        {:def, meta, [{name, _, args} | _]} when is_atom(name) ->
          sig = %{
            name: name,
            arity: if(args, do: length(args), else: 0),
            visibility: :public,
            line: Keyword.get(meta, :line, 0)
          }
          {node, [sig | acc]}
        
        {:defp, meta, [{name, _, args} | _]} when is_atom(name) ->
          sig = %{
            name: name,
            arity: if(args, do: length(args), else: 0),
            visibility: :private,
            line: Keyword.get(meta, :line, 0)
          }
          {node, [sig | acc]}
        
        _ ->
          {node, acc}
      end
    end)
    
    Enum.reverse(signatures)
  end
  
  defp categorize_differences(differences, params) do
    categorized = %{
      critical: [],
      important: [],
      normal: [],
      trivial: []
    }
    
    differences
    |> List.flatten()
    |> Enum.reduce(categorized, fn diff, acc ->
      significance = Map.get(diff, :significance, :normal)
      update_in(acc[significance], &[diff | &1])
    end)
    |> Enum.map(fn {key, diffs} -> {key, Enum.reverse(diffs)} end)
    |> Enum.into(%{})
    |> then(&{:ok, &1})
  end
  
  defp format_output(categorized, params) do
    case params.output_format do
      "structured" -> format_structured_output(categorized)
      "unified" -> format_unified_diff(categorized)
      "side_by_side" -> format_side_by_side(categorized)
      "json" -> format_json_output(categorized)
    end
  end
  
  defp format_structured_output(categorized) do
    {:ok, categorized}
  end
  
  defp format_unified_diff(categorized) do
    all_diffs = categorized
    |> Map.values()
    |> List.flatten()
    |> Enum.sort_by(&get_in(&1, [:location, :line]))
    
    unified = Enum.map(all_diffs, fn diff ->
      case diff.type do
        :addition -> "+ #{diff.content}"
        :deletion -> "- #{diff.content}"
        :modification -> "- #{diff.old_content}\n+ #{diff.new_content}"
        _ -> "  #{diff.content}"
      end
    end)
    
    {:ok, %{unified_diff: Enum.join(unified, "\n")}}
  end
  
  defp format_side_by_side(categorized) do
    # Simplified side-by-side format
    {:ok, %{side_by_side: "Side-by-side view not fully implemented"}}
  end
  
  defp format_json_output(categorized) do
    {:ok, Jason.encode!(categorized)}
  rescue
    _ -> {:ok, %{json: "Failed to encode as JSON"}}
  end
  
  defp count_differences(categorized) do
    categorized
    |> Map.values()
    |> List.flatten()
    |> length()
  end
  
  defp get_difference_types(categorized) do
    categorized
    |> Map.values()
    |> List.flatten()
    |> Enum.map(& &1.type)
    |> Enum.uniq()
  end
  
  defp calculate_similarity_score(categorized) do
    total_diffs = count_differences(categorized)
    critical_diffs = length(categorized.critical || [])
    important_diffs = length(categorized.important || [])
    
    # Simple similarity scoring
    penalty = critical_diffs * 10 + important_diffs * 5 + total_diffs
    max(0, 100 - penalty) / 100
  end
  
  defp count_significant_changes(categorized) do
    length(categorized.critical || []) + length(categorized.important || [])
  end
  
  defp calculate_statistics(parsed, categorized) do
    %{
      lines_compared: %{
        code_a: length(parsed.lines_a),
        code_b: length(parsed.lines_b)
      },
      differences_by_type: get_difference_type_counts(categorized),
      most_changed_areas: identify_change_hotspots(categorized),
      change_density: calculate_change_density(parsed, categorized)
    }
  end
  
  defp get_difference_type_counts(categorized) do
    categorized
    |> Map.values()
    |> List.flatten()
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, diffs} -> {type, length(diffs)} end)
    |> Enum.into(%{})
  end
  
  defp identify_change_hotspots(categorized) do
    all_diffs = categorized
    |> Map.values()
    |> List.flatten()
    
    # Group by line ranges
    all_diffs
    |> Enum.group_by(fn diff ->
      line = get_in(diff, [:location, :line]) || 0
      div(line, 10) * 10  # Group by 10-line blocks
    end)
    |> Enum.map(fn {line_block, diffs} ->
      {"lines #{line_block}-#{line_block + 9}", length(diffs)}
    end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(5)
    |> Enum.into(%{})
  end
  
  defp calculate_change_density(parsed, categorized) do
    total_lines = max(length(parsed.lines_a), length(parsed.lines_b))
    total_changes = count_differences(categorized)
    
    if total_lines > 0 do
      Float.round(total_changes / total_lines, 3)
    else
      0.0
    end
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end