defmodule RubberDuck.Tools.RepoSearch do
  @moduledoc """
  Searches project files by keyword, symbol, or pattern.
  
  This tool provides comprehensive search capabilities across a codebase,
  supporting various search types including text, regex, and AST-based searches.
  """
  
  use RubberDuck.Tool
  
  tool do
    name :repo_search
    description "Searches project files by keyword, symbol, or pattern"
    category :navigation
    version "1.0.0"
    tags [:search, :navigation, :discovery, :analysis]
    
    parameter :query do
      type :string
      required true
      description "Search query (text, regex pattern, or symbol name)"
      constraints [
        min_length: 1,
        max_length: 500
      ]
    end
    
    parameter :search_type do
      type :string
      required false
      description "Type of search to perform"
      default "text"
      constraints [
        enum: [
          "text",        # Simple text search
          "regex",       # Regular expression search
          "symbol",      # Function/module/variable names
          "definition",  # Function/module definitions
          "reference",   # Symbol references/calls
          "ast"         # AST-based structural search
        ]
      ]
    end
    
    parameter :file_pattern do
      type :string
      required false
      description "Glob pattern to filter files (e.g., '*.ex', 'lib/**/*.ex')"
      default "**/*.{ex,exs}"
    end
    
    parameter :case_sensitive do
      type :boolean
      required false
      description "Whether the search should be case sensitive"
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
      description "Number of context lines to include around matches"
      default 2
      constraints [
        min: 0,
        max: 10
      ]
    end
    
    parameter :exclude_patterns do
      type :list
      required false
      description "Patterns to exclude from search"
      default ["_build/**", "deps/**", ".git/**", "node_modules/**"]
      item_type :string
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
      rate_limit 200
    end
  end
  
  @doc """
  Executes the repository search based on the provided parameters.
  """
  def execute(params, context) do
    project_root = context[:project_root] || File.cwd!()
    
    with {:ok, files} <- find_matching_files(project_root, params),
         {:ok, results} <- search_files(files, params),
         {:ok, formatted} <- format_results(results, params) do
      
      {:ok, %{
        query: params.query,
        search_type: params.search_type,
        total_matches: formatted.total_matches,
        files_searched: length(files),
        results: Enum.take(formatted.results, params.max_results),
        truncated: formatted.total_matches > params.max_results
      }}
    else
      {:error, reason} -> {:error, format_error(reason)}
    end
  end
  
  defp find_matching_files(root, params) do
    try do
      files = Path.wildcard(Path.join(root, params.file_pattern))
      |> Enum.reject(&excluded?(&1, params.exclude_patterns))
      |> Enum.filter(&File.regular?/1)
      
      {:ok, files}
    rescue
      e -> {:error, "Failed to find files: #{inspect(e)}"}
    end
  end
  
  defp excluded?(path, exclude_patterns) do
    Enum.any?(exclude_patterns, fn pattern ->
      path_match?(path, pattern)
    end)
  end
  
  defp path_match?(path, pattern) do
    regex_pattern = pattern
    |> String.replace("**", ".*")
    |> String.replace("*", "[^/]*")
    |> Regex.compile!()
    
    Regex.match?(regex_pattern, path)
  end
  
  defp search_files(files, params) do
    results = files
    |> Task.async_stream(&search_file(&1, params), 
        timeout: 5000, 
        max_concurrency: System.schedulers_online())
    |> Enum.reduce([], fn
      {:ok, {:ok, file_results}}, acc when file_results != [] ->
        acc ++ file_results
      _, acc ->
        acc
    end)
    
    {:ok, results}
  end
  
  defp search_file(file_path, params) do
    case File.read(file_path) do
      {:ok, content} ->
        results = case params.search_type do
          "text" -> text_search(content, file_path, params)
          "regex" -> regex_search(content, file_path, params)
          "symbol" -> symbol_search(content, file_path, params)
          "definition" -> definition_search(content, file_path, params)
          "reference" -> reference_search(content, file_path, params)
          "ast" -> ast_search(content, file_path, params)
        end
        
        {:ok, results}
      
      {:error, _} ->
        {:ok, []}
    end
  end
  
  defp text_search(content, file_path, params) do
    lines = String.split(content, "\n")
    query = if params.case_sensitive, do: params.query, else: String.downcase(params.query)
    
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} ->
      search_line = if params.case_sensitive, do: line, else: String.downcase(line)
      String.contains?(search_line, query)
    end)
    |> Enum.map(fn {line, line_num} ->
      %{
        file: file_path,
        line: line_num,
        match: line,
        context: get_context(lines, line_num, params.context_lines),
        type: :text_match
      }
    end)
  end
  
  defp regex_search(content, file_path, params) do
    lines = String.split(content, "\n")
    
    case compile_regex(params.query, params.case_sensitive) do
      {:ok, regex} ->
        lines
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _} -> Regex.match?(regex, line) end)
        |> Enum.map(fn {line, line_num} ->
          %{
            file: file_path,
            line: line_num,
            match: line,
            context: get_context(lines, line_num, params.context_lines),
            type: :regex_match,
            captures: Regex.run(regex, line)
          }
        end)
      
      {:error, _} ->
        []
    end
  end
  
  defp symbol_search(content, file_path, params) do
    case Code.string_to_quoted(content) do
      {:ok, ast} ->
        symbols = extract_symbols(ast)
        
        symbols
        |> Enum.filter(fn symbol ->
          symbol_matches?(symbol, params.query, params.case_sensitive)
        end)
        |> Enum.map(fn symbol ->
          %{
            file: file_path,
            line: symbol.line,
            match: symbol.name,
            context: get_symbol_context(content, symbol.line),
            type: :symbol_match,
            symbol_type: symbol.type
          }
        end)
      
      {:error, _} ->
        []
    end
  end
  
  defp definition_search(content, file_path, params) do
    case Code.string_to_quoted(content) do
      {:ok, ast} ->
        definitions = extract_definitions(ast)
        
        definitions
        |> Enum.filter(fn def_info ->
          symbol_matches?(def_info, params.query, params.case_sensitive)
        end)
        |> Enum.map(fn def_info ->
          %{
            file: file_path,
            line: def_info.line,
            match: "#{def_info.type} #{def_info.name}/#{def_info.arity}",
            context: get_definition_context(content, def_info.line),
            type: :definition,
            definition_type: def_info.type,
            arity: def_info.arity
          }
        end)
      
      {:error, _} ->
        []
    end
  end
  
  defp reference_search(content, file_path, params) do
    case Code.string_to_quoted(content) do
      {:ok, ast} ->
        references = extract_references(ast, params.query)
        
        references
        |> Enum.map(fn ref ->
          %{
            file: file_path,
            line: ref.line,
            match: ref.context,
            context: get_reference_context(content, ref.line),
            type: :reference,
            reference_type: ref.type
          }
        end)
      
      {:error, _} ->
        []
    end
  end
  
  defp ast_search(content, file_path, params) do
    # For AST search, we would parse the query as a pattern
    # and match it against the AST structure
    # This is a simplified implementation
    case Code.string_to_quoted(content) do
      {:ok, ast} ->
        pattern = parse_ast_pattern(params.query)
        matches = find_ast_matches(ast, pattern)
        
        matches
        |> Enum.map(fn match ->
          %{
            file: file_path,
            line: match.line || 1,
            match: Macro.to_string(match.node),
            context: [],
            type: :ast_match
          }
        end)
      
      {:error, _} ->
        []
    end
  end
  
  defp compile_regex(pattern, case_sensitive) do
    options = if case_sensitive, do: [], else: [:caseless]
    Regex.compile(pattern, options)
  end
  
  defp extract_symbols(ast) do
    {_, symbols} = Macro.postwalk(ast, [], fn
      {:def, meta, [{name, _, args} | _]} = node, acc ->
        {node, [{:function, name, length(args || []), meta[:line]} | acc]}
      
      {:defp, meta, [{name, _, args} | _]} = node, acc ->
        {node, [{:function, name, length(args || []), meta[:line]} | acc]}
      
      {:defmodule, meta, [{:__aliases__, _, parts} | _]} = node, acc ->
        {node, [{:module, Module.concat(parts), 0, meta[:line]} | acc]}
      
      {name, meta, nil} = node, acc when is_atom(name) ->
        {node, [{:variable, name, 0, meta[:line]} | acc]}
      
      node, acc ->
        {node, acc}
    end)
    
    symbols
    |> Enum.map(fn {type, name, arity, line} ->
      %{type: type, name: to_string(name), arity: arity, line: line || 1}
    end)
    |> Enum.reverse()
  end
  
  defp extract_definitions(ast) do
    {_, defs} = Macro.postwalk(ast, [], fn
      {:def, meta, [{name, _, args} | _]} = node, acc ->
        {node, [%{type: :def, name: name, arity: length(args || []), line: meta[:line]} | acc]}
      
      {:defp, meta, [{name, _, args} | _]} = node, acc ->
        {node, [%{type: :defp, name: name, arity: length(args || []), line: meta[:line]} | acc]}
      
      {:defmacro, meta, [{name, _, args} | _]} = node, acc ->
        {node, [%{type: :defmacro, name: name, arity: length(args || []), line: meta[:line]} | acc]}
      
      {:defmodule, meta, [{:__aliases__, _, parts} | _]} = node, acc ->
        {node, [%{type: :defmodule, name: Module.concat(parts), arity: 0, line: meta[:line]} | acc]}
      
      node, acc ->
        {node, acc}
    end)
    
    Enum.reverse(defs)
  end
  
  defp extract_references(ast, query) do
    query_atom = String.to_atom(query)
    
    {_, refs} = Macro.postwalk(ast, [], fn
      {^query_atom, meta, args} = node, acc when is_list(args) ->
        context = "#{query}(#{Enum.count(args)} args)"
        {node, [%{type: :call, context: context, line: meta[:line]} | acc]}
      
      {{:., _, [{:__aliases__, _, mod_parts}, ^query_atom]}, meta, args} = node, acc ->
        module = Module.concat(mod_parts)
        context = "#{module}.#{query}(#{Enum.count(args || [])} args)"
        {node, [%{type: :remote_call, context: context, line: meta[:line]} | acc]}
      
      node, acc ->
        {node, acc}
    end)
    
    Enum.reverse(refs)
  end
  
  defp parse_ast_pattern(query) do
    # Simplified AST pattern parsing
    # In a real implementation, this would parse a pattern DSL
    case Code.string_to_quoted(query) do
      {:ok, pattern} -> pattern
      {:error, _} -> query
    end
  end
  
  defp find_ast_matches(ast, pattern) when is_binary(pattern) do
    # Simple string-based matching in AST
    {_, matches} = Macro.postwalk(ast, [], fn node, acc ->
      if Macro.to_string(node) =~ pattern do
        {node, [%{node: node} | acc]}
      else
        {node, acc}
      end
    end)
    
    Enum.reverse(matches)
  end
  
  defp find_ast_matches(ast, pattern) do
    # Pattern-based AST matching would go here
    []
  end
  
  defp symbol_matches?(%{name: name}, query, case_sensitive) do
    name_str = to_string(name)
    query_str = to_string(query)
    
    if case_sensitive do
      String.contains?(name_str, query_str)
    else
      String.contains?(String.downcase(name_str), String.downcase(query_str))
    end
  end
  
  defp get_context(lines, line_num, context_lines) do
    start_line = max(1, line_num - context_lines)
    end_line = min(length(lines), line_num + context_lines)
    
    start_line..end_line
    |> Enum.map(fn n ->
      %{
        line: n,
        content: Enum.at(lines, n - 1, ""),
        current: n == line_num
      }
    end)
  end
  
  defp get_symbol_context(content, line) do
    lines = String.split(content, "\n")
    get_context(lines, line || 1, 2)
  end
  
  defp get_definition_context(content, line) do
    lines = String.split(content, "\n")
    get_context(lines, line || 1, 3)
  end
  
  defp get_reference_context(content, line) do
    lines = String.split(content, "\n")
    get_context(lines, line || 1, 2)
  end
  
  defp format_results(results, _params) do
    grouped = Enum.group_by(results, & &1.file)
    
    formatted_results = Enum.flat_map(grouped, fn {file, matches} ->
      Enum.map(matches, fn match ->
        %{
          file: Path.relative_to(file, File.cwd!()),
          line: match.line,
          match: match.match,
          context: match.context,
          type: match.type,
          metadata: Map.drop(match, [:file, :line, :match, :context, :type])
        }
      end)
    end)
    |> Enum.sort_by(fn r -> {r.file, r.line} end)
    
    {:ok, %{
      results: formatted_results,
      total_matches: length(results)
    }}
  end
  
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end