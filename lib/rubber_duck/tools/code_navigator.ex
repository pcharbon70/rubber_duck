defmodule RubberDuck.Tools.CodeNavigator do
  @moduledoc """
  Locates symbols within a codebase and maps them to file and line number.
  
  This tool provides code navigation capabilities, helping developers
  find definitions, references, and usages of symbols across the codebase.
  """
  
  use RubberDuck.Tool
  
  tool do
    name :code_navigator
    description "Locates symbols within a codebase and maps them to file and line number"
    category :navigation
    version "1.0.0"
    tags [:navigation, :search, :symbols, :references]
    
    parameter :symbol do
      type :string
      required true
      description "Symbol to locate (module, function, variable, etc.)"
      constraints [
        min_length: 1,
        max_length: 200
      ]
    end
    
    parameter :search_type do
      type :string
      required false
      description "Type of search to perform"
      default "comprehensive"
      constraints [
        enum: [
          "comprehensive",  # All occurrences
          "definitions",    # Only definitions
          "references",     # Only references/usages
          "declarations",   # Only declarations (@spec, @type, etc.)
          "calls"          # Only function calls
        ]
      ]
    end
    
    parameter :scope do
      type :string
      required false
      description "Search scope"
      default "project"
      constraints [
        enum: ["project", "file", "module", "function"]
      ]
    end
    
    parameter :file_pattern do
      type :string
      required false
      description "File pattern to limit search (glob pattern)"
      default "**/*.{ex,exs}"
    end
    
    parameter :case_sensitive do
      type :boolean
      required false
      description "Case sensitive search"
      default true
    end
    
    parameter :include_tests do
      type :boolean
      required false
      description "Include test files in search"
      default true
    end
    
    parameter :include_deps do
      type :boolean
      required false
      description "Include dependency files"
      default false
    end
    
    parameter :max_results do
      type :integer
      required false
      description "Maximum number of results to return"
      default 100
      constraints [
        min: 1,
        max: 1000
      ]
    end
    
    parameter :context_lines do
      type :integer
      required false
      description "Number of context lines around matches"
      default 2
      constraints [
        min: 0,
        max: 10
      ]
    end
    
    execution do
      handler &__MODULE__.execute/2
      timeout 30_000
      async true
      retries 1
    end
    
    security do
      sandbox :restricted
      capabilities [:file_read]
      rate_limit 100
    end
  end
  
  @doc """
  Executes symbol navigation and location within the codebase.
  """
  def execute(params, context) do
    with {:ok, search_paths} <- determine_search_paths(params, context),
         {:ok, files_to_search} <- collect_files(search_paths, params),
         {:ok, matches} <- search_symbol(params.symbol, files_to_search, params),
         {:ok, categorized} <- categorize_matches(matches, params),
         {:ok, ranked} <- rank_results(categorized, params) do
      
      {:ok, %{
        results: ranked,
        summary: %{
          total_matches: length(matches),
          files_searched: length(files_to_search),
          definition_count: count_by_type(categorized, :definition),
          reference_count: count_by_type(categorized, :reference),
          call_count: count_by_type(categorized, :call)
        },
        navigation: %{
          primary_definition: find_primary_definition(categorized),
          related_symbols: find_related_symbols(matches, params),
          usage_patterns: analyze_usage_patterns(matches)
        },
        metadata: %{
          search_type: params.search_type,
          scope: params.scope,
          files_searched: length(files_to_search)
        }
      }}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  defp determine_search_paths(params, context) do
    base_path = context[:project_root] || File.cwd!()
    
    paths = case params.scope do
      "project" -> [base_path]
      "file" -> 
        # Would need specific file from context
        if context[:current_file] do
          [context[:current_file]]
        else
          [base_path]
        end
      "module" ->
        # Would need current module context
        [base_path]
      "function" ->
        # Would need current function context
        [base_path]
    end
    
    {:ok, paths}
  end
  
  defp collect_files(search_paths, params) do
    files = search_paths
    |> Enum.flat_map(fn path ->
      if File.regular?(path) do
        [path]
      else
        collect_files_in_directory(path, params)
      end
    end)
    |> Enum.uniq()
    |> filter_files_by_pattern(params.file_pattern)
    |> filter_test_files(params.include_tests)
    |> filter_dependency_files(params.include_deps)
    
    {:ok, files}
  end
  
  defp collect_files_in_directory(directory, params) do
    pattern = Path.join(directory, params.file_pattern)
    Path.wildcard(pattern)
  end
  
  defp filter_files_by_pattern(files, pattern) do
    # Pattern already applied in collect_files_in_directory
    files
  end
  
  defp filter_test_files(files, include_tests) do
    if include_tests do
      files
    else
      Enum.reject(files, &String.contains?(&1, "test"))
    end
  end
  
  defp filter_dependency_files(files, include_deps) do
    if include_deps do
      files
    else
      Enum.reject(files, &String.contains?(&1, "deps"))
    end
  end
  
  defp search_symbol(symbol, files, params) do
    matches = files
    |> Enum.flat_map(fn file ->
      case File.read(file) do
        {:ok, content} ->
          search_in_content(symbol, content, file, params)
        {:error, _} ->
          []
      end
    end)
    |> Enum.take(params.max_results)
    
    {:ok, matches}
  end
  
  defp search_in_content(symbol, content, file, params) do
    lines = String.split(content, "\n")
    
    # Try to parse as AST for better symbol detection
    ast_matches = case Code.string_to_quoted(content) do
      {:ok, ast} -> search_in_ast(symbol, ast, file, params)
      {:error, _} -> []
    end
    
    # Fallback to text-based search
    text_matches = search_in_text(symbol, lines, file, params)
    
    # Combine and deduplicate
    (ast_matches ++ text_matches)
    |> Enum.uniq_by(&{&1.file, &1.line, &1.type})
  end
  
  defp search_in_ast(symbol, ast, file, params) do
    symbol_atom = safe_to_atom(symbol)
    
    {_, matches} = Macro.postwalk(ast, [], fn node, acc ->
      case extract_symbol_info(node, symbol, symbol_atom, file, params) do
        nil -> {node, acc}
        match -> {node, [match | acc]}
      end
    end)
    
    Enum.reverse(matches)
  end
  
  defp safe_to_atom(string) do
    try do
      String.to_atom(string)
    rescue
      _ -> nil
    end
  end
  
  defp extract_symbol_info(node, symbol, symbol_atom, file, params) do
    case node do
      # Module definition
      {:defmodule, meta, [{:__aliases__, _, parts} | _]} ->
        module_name = Module.concat(parts) |> to_string()
        if matches_symbol?(module_name, symbol, params) do
          create_match(:definition, :module, module_name, file, Keyword.get(meta, :line, 0), node)
        end
      
      # Function definition
      {:def, meta, [{name, _, args} | _]} when is_atom(name) ->
        if matches_symbol?(to_string(name), symbol, params) or name == symbol_atom do
          arity = if args, do: length(args), else: 0
          signature = "#{name}/#{arity}"
          create_match(:definition, :function, signature, file, Keyword.get(meta, :line, 0), node)
        end
      
      # Private function definition
      {:defp, meta, [{name, _, args} | _]} when is_atom(name) ->
        if matches_symbol?(to_string(name), symbol, params) or name == symbol_atom do
          arity = if args, do: length(args), else: 0
          signature = "#{name}/#{arity}"
          create_match(:definition, :private_function, signature, file, Keyword.get(meta, :line, 0), node)
        end
      
      # Function call
      {name, meta, _} when is_atom(name) ->
        if matches_symbol?(to_string(name), symbol, params) or name == symbol_atom do
          create_match(:call, :function, to_string(name), file, Keyword.get(meta, :line, 0), node)
        end
      
      # Module.function call
      {{:., meta, [{:__aliases__, _, parts}, func_name]}, _, _} when is_atom(func_name) ->
        module_name = Module.concat(parts) |> to_string()
        full_name = "#{module_name}.#{func_name}"
        
        cond do
          matches_symbol?(module_name, symbol, params) ->
            create_match(:reference, :module, module_name, file, Keyword.get(meta, :line, 0), node)
          
          matches_symbol?(to_string(func_name), symbol, params) or func_name == symbol_atom ->
            create_match(:call, :function, full_name, file, Keyword.get(meta, :line, 0), node)
          
          matches_symbol?(full_name, symbol, params) ->
            create_match(:call, :qualified_function, full_name, file, Keyword.get(meta, :line, 0), node)
          
          true -> nil
        end
      
      # Variable or parameter
      {name, meta, context} when is_atom(name) and is_atom(context) ->
        if matches_symbol?(to_string(name), symbol, params) or name == symbol_atom do
          create_match(:reference, :variable, to_string(name), file, Keyword.get(meta, :line, 0), node)
        end
      
      # Alias
      {:alias, meta, [{:__aliases__, _, parts} | _]} ->
        module_name = Module.concat(parts) |> to_string()
        if matches_symbol?(module_name, symbol, params) do
          create_match(:reference, :alias, module_name, file, Keyword.get(meta, :line, 0), node)
        end
      
      # Import
      {:import, meta, [{:__aliases__, _, parts} | _]} ->
        module_name = Module.concat(parts) |> to_string()
        if matches_symbol?(module_name, symbol, params) do
          create_match(:reference, :import, module_name, file, Keyword.get(meta, :line, 0), node)
        end
      
      # Use
      {:use, meta, [{:__aliases__, _, parts} | _]} ->
        module_name = Module.concat(parts) |> to_string()
        if matches_symbol?(module_name, symbol, params) do
          create_match(:reference, :use, module_name, file, Keyword.get(meta, :line, 0), node)
        end
      
      # @spec, @type, etc.
      {:@, meta, [{attr, _, _}]} when attr in [:spec, :type, :typep] ->
        if matches_symbol?(to_string(attr), symbol, params) do
          create_match(:declaration, :attribute, "@#{attr}", file, Keyword.get(meta, :line, 0), node)
        end
      
      _ ->
        nil
    end
  end
  
  defp matches_symbol?(candidate, symbol, params) do
    if params.case_sensitive do
      candidate == symbol
    else
      String.downcase(candidate) == String.downcase(symbol)
    end
  end
  
  defp create_match(match_type, symbol_type, name, file, line, ast_node) do
    %{
      type: match_type,
      symbol_type: symbol_type,
      name: name,
      file: file,
      line: line,
      column: 0,  # Could extract from AST meta if needed
      ast_node: ast_node,
      confidence: calculate_confidence(match_type, symbol_type)
    }
  end
  
  defp calculate_confidence(:definition, _), do: 1.0
  defp calculate_confidence(:declaration, _), do: 0.9
  defp calculate_confidence(:call, :qualified_function), do: 0.8
  defp calculate_confidence(:call, _), do: 0.7
  defp calculate_confidence(:reference, :alias), do: 0.8
  defp calculate_confidence(:reference, :import), do: 0.8
  defp calculate_confidence(:reference, _), do: 0.6
  
  defp search_in_text(symbol, lines, file, params) do
    # Regex-based search as fallback
    regex_pattern = if params.case_sensitive do
      ~r/\b#{Regex.escape(symbol)}\b/
    else
      ~r/\b#{Regex.escape(symbol)}\b/i
    end
    
    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      case Regex.run(regex_pattern, line, return: :index) do
        nil -> []
        [{start, _length}] ->
          [%{
            type: :text_match,
            symbol_type: :unknown,
            name: symbol,
            file: file,
            line: line_num,
            column: start,
            content: String.trim(line),
            confidence: 0.5
          }]
      end
    end)
  end
  
  defp categorize_matches(matches, params) do
    case params.search_type do
      "definitions" ->
        {:ok, Enum.filter(matches, &(&1.type == :definition))}
      
      "references" ->
        {:ok, Enum.filter(matches, &(&1.type in [:reference, :text_match]))}
      
      "declarations" ->
        {:ok, Enum.filter(matches, &(&1.type == :declaration))}
      
      "calls" ->
        {:ok, Enum.filter(matches, &(&1.type == :call))}
      
      "comprehensive" ->
        {:ok, matches}
    end
  end
  
  defp rank_results(matches, _params) do
    # Sort by confidence, then by type importance, then by file
    ranked = matches
    |> Enum.sort_by(&{-&1.confidence, type_priority(&1.type), &1.file, &1.line})
    |> add_context_to_matches(_params)
    
    {:ok, ranked}
  end
  
  defp type_priority(:definition), do: 1
  defp type_priority(:declaration), do: 2
  defp type_priority(:call), do: 3
  defp type_priority(:reference), do: 4
  defp type_priority(:text_match), do: 5
  
  defp add_context_to_matches(matches, params) do
    if params.context_lines > 0 do
      Enum.map(matches, &add_context_to_match(&1, params.context_lines))
    else
      matches
    end
  end
  
  defp add_context_to_match(match, context_lines) do
    case File.read(match.file) do
      {:ok, content} ->
        lines = String.split(content, "\n")
        context = extract_context_lines(lines, match.line - 1, context_lines)
        Map.put(match, :context, context)
      
      {:error, _} ->
        match
    end
  end
  
  defp extract_context_lines(lines, center_index, context_lines) do
    start_idx = max(0, center_index - context_lines)
    end_idx = min(length(lines) - 1, center_index + context_lines)
    
    lines
    |> Enum.slice(start_idx..end_idx)
    |> Enum.with_index(start_idx + 1)
    |> Enum.map(fn {line, line_num} ->
      %{
        line_number: line_num,
        content: line,
        is_match: line_num == center_index + 1
      }
    end)
  end
  
  defp count_by_type(matches, type) do
    Enum.count(matches, &(&1.type == type))
  end
  
  defp find_primary_definition(matches) do
    matches
    |> Enum.filter(&(&1.type == :definition))
    |> Enum.max_by(& &1.confidence, fn -> nil end)
  end
  
  defp find_related_symbols(matches, params) do
    # Find symbols that commonly appear together
    symbol_names = matches
    |> Enum.map(& &1.name)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == params.symbol))
    |> Enum.take(10)
    
    symbol_names
  end
  
  defp analyze_usage_patterns(matches) do
    # Analyze how the symbol is used
    usage_by_file = matches
    |> Enum.group_by(& &1.file)
    |> Enum.map(fn {file, file_matches} ->
      {Path.basename(file), length(file_matches)}
    end)
    |> Enum.sort_by(fn {_, count} -> count end, :desc)
    |> Enum.take(10)
    
    usage_by_type = matches
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, type_matches} ->
      {type, length(type_matches)}
    end)
    |> Enum.into(%{})
    
    %{
      most_used_files: usage_by_file,
      usage_distribution: usage_by_type,
      total_files: matches |> Enum.map(& &1.file) |> Enum.uniq() |> length()
    }
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end