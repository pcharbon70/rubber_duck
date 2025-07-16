defmodule RubberDuck.MCP.Server.Tools.CodeAnalyzer do
  @moduledoc """
  Analyzes Elixir code and provides insights through MCP.
  
  This tool leverages RubberDuck's code analysis capabilities to provide
  AI assistants with detailed information about code structure, dependencies,
  and potential issues.
  """
  
  use Hermes.Server.Component, type: :tool
  
  alias Hermes.Server.Frame
  
  schema do
    field :file_path, :string,
      description: "Path to the file to analyze (relative to project root)"
      
    field :module_name, :string,
      description: "Module name to analyze (alternative to file_path)"
      
    field :analysis_type, {:enum, ["structure", "dependencies", "complexity", "all"]},
      description: "Type of analysis to perform",
      default: "all"
      
    field :include_ast, :boolean,
      description: "Include the AST in the response",
      default: false
  end
  
  @impl true
  def execute(params, frame) do
    cond do
      params[:file_path] ->
        analyze_file(params.file_path, params.analysis_type, params.include_ast, frame)
        
      params[:module_name] ->
        analyze_module(params.module_name, params.analysis_type, params.include_ast, frame)
        
      true ->
        {:error, %{
          "code" => "invalid_params",
          "message" => "Either file_path or module_name must be provided"
        }}
    end
  end
  
  defp analyze_file(file_path, analysis_type, include_ast, frame) do
    full_path = Path.join(File.cwd!(), file_path)
    
    if File.exists?(full_path) do
      case File.read(full_path) do
        {:ok, content} ->
          perform_analysis(content, file_path, analysis_type, include_ast, frame)
          
        {:error, reason} ->
          {:error, %{
            "code" => "file_read_error",
            "message" => "Failed to read file: #{reason}"
          }}
      end
    else
      {:error, %{
        "code" => "file_not_found",
        "message" => "File not found: #{file_path}"
      }}
    end
  end
  
  defp analyze_module(module_name, analysis_type, include_ast, frame) do
    # TODO: Implement module-based analysis
    {:error, %{
      "code" => "not_implemented",
      "message" => "Module analysis not yet implemented"
    }}
  end
  
  defp perform_analysis(content, file_path, analysis_type, include_ast, frame) do
    case Code.string_to_quoted(content) do
      {:ok, ast} ->
        analysis = build_analysis(ast, file_path, analysis_type)
        
        result = if include_ast do
          Map.put(analysis, "ast", inspect(ast, pretty: true, limit: :infinity))
        else
          analysis
        end
        
        # Log analysis completion (logging is done at server level)
        
        {:ok, result, frame}
        
      {:error, {line, error_msg, _}} ->
        {:error, %{
          "code" => "syntax_error",
          "message" => "Syntax error at line #{line}: #{error_msg}"
        }}
    end
  end
  
  defp build_analysis(ast, file_path, analysis_type) do
    base_analysis = %{
      "file" => file_path,
      "analysis_type" => analysis_type
    }
    
    case analysis_type do
      "structure" -> analyze_structure(ast, base_analysis)
      "dependencies" -> analyze_dependencies(ast, base_analysis)
      "complexity" -> analyze_complexity(ast, base_analysis)
      "all" -> 
        base_analysis
        |> analyze_structure(ast)
        |> analyze_dependencies(ast)
        |> analyze_complexity(ast)
    end
  end
  
  defp analyze_structure(ast, analysis) do
    modules = extract_modules(ast)
    functions = extract_functions(ast)
    
    Map.merge(analysis, %{
      "modules" => modules,
      "functions" => functions,
      "line_count" => count_lines(ast)
    })
  end
  
  defp analyze_dependencies(ast, analysis) do
    imports = extract_imports(ast)
    aliases = extract_aliases(ast)
    
    Map.merge(analysis, %{
      "imports" => imports,
      "aliases" => aliases,
      "external_calls" => extract_external_calls(ast)
    })
  end
  
  defp analyze_complexity(ast, analysis) do
    Map.merge(analysis, %{
      "cyclomatic_complexity" => calculate_complexity(ast),
      "nesting_depth" => calculate_max_nesting(ast),
      "function_metrics" => analyze_function_metrics(ast)
    })
  end
  
  # AST traversal helpers
  
  defp extract_modules(ast) do
    ast
    |> Macro.postwalk(%{}, fn
      {:defmodule, _, [{:__aliases__, _, module_parts}, _]} = node, acc ->
        module_name = Enum.join(module_parts, ".")
        module_info = %{
          "name" => module_name,
          "line" => get_line(node)
        }
        {node, Map.put(acc, module_name, module_info)}
        
      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end
  
  defp extract_functions(ast) do
    ast
    |> Macro.postwalk([], fn
      {:def, meta, [{name, _, args}, _]} = node, acc ->
        func_info = %{
          "name" => to_string(name),
          "arity" => length(args || []),
          "line" => meta[:line],
          "type" => "public"
        }
        {node, [func_info | acc]}
        
      {:defp, meta, [{name, _, args}, _]} = node, acc ->
        func_info = %{
          "name" => to_string(name),
          "arity" => length(args || []),
          "line" => meta[:line],
          "type" => "private"
        }
        {node, [func_info | acc]}
        
      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end
  
  defp extract_imports(ast) do
    ast
    |> Macro.postwalk([], fn
      {:import, _, [{:__aliases__, _, module_parts} | _]} = node, acc ->
        {node, [Enum.join(module_parts, ".") | acc]}
        
      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.uniq()
  end
  
  defp extract_aliases(ast) do
    ast
    |> Macro.postwalk([], fn
      {:alias, _, [{:__aliases__, _, module_parts} | _]} = node, acc ->
        {node, [Enum.join(module_parts, ".") | acc]}
        
      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.uniq()
  end
  
  defp extract_external_calls(_ast) do
    # TODO: Implement external call extraction
    []
  end
  
  defp count_lines(ast) do
    {_, max_line} = Macro.postwalk(ast, 0, fn
      node, max_line ->
        case get_line(node) do
          nil -> {node, max_line}
          line -> {node, max(line, max_line)}
        end
    end)
    max_line
  end
  
  defp calculate_complexity(_ast) do
    # TODO: Implement cyclomatic complexity calculation
    1
  end
  
  defp calculate_max_nesting(_ast) do
    # TODO: Implement nesting depth calculation
    0
  end
  
  defp analyze_function_metrics(_ast) do
    # TODO: Implement per-function metrics
    %{}
  end
  
  defp get_line({_, meta, _}) when is_list(meta), do: meta[:line]
  defp get_line(_), do: nil
end