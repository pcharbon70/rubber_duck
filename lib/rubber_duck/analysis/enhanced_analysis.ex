defmodule RubberDuck.Analysis.SourcerorIntegration do
  @moduledoc """
  Integration module showing how to use SourcerorParser with the existing
  RubberDuck analysis engines (Semantic, Style, Security).
  
  This demonstrates how the advanced AST parsing capabilities can enhance
  the existing analysis infrastructure.
  """
  
  alias RubberDuck.Analysis.AST.SourcerorParser
  alias RubberDuck.Analysis.{Semantic, Style, Security}
  
  @doc """
  Performs enhanced semantic analysis using Sourceror's advanced AST parsing.
  
  This provides more detailed analysis than the basic AST parser by:
  - Tracking variable usage across scopes
  - Building comprehensive call graphs
  - Detecting more complex patterns
  """
  def enhanced_semantic_analysis(code_file) do
    with {:ok, ast_data} <- SourcerorParser.parse(code_file.content),
         {:ok, basic_analysis} <- Semantic.analyze(code_file) do
      
      enhanced_results = 
        basic_analysis
        |> enhance_with_variable_analysis(ast_data)
        |> enhance_with_call_graph(ast_data)
        |> enhance_with_pattern_detection(ast_data)
      
      {:ok, enhanced_results}
    end
  end
  
  @doc """
  Performs enhanced style analysis with detailed AST information.
  """
  def enhanced_style_analysis(code_file) do
    with {:ok, ast_data} <- SourcerorParser.parse(code_file.content),
         {:ok, basic_analysis} <- Style.analyze(code_file) do
      
      enhanced_results =
        basic_analysis
        |> enhance_with_naming_analysis(ast_data)
        |> enhance_with_module_structure(ast_data)
        |> enhance_with_import_analysis(ast_data)
      
      {:ok, enhanced_results}
    end
  end
  
  @doc """
  Performs enhanced security analysis using comprehensive AST data.
  """
  def enhanced_security_analysis(code_file) do
    with {:ok, ast_data} <- SourcerorParser.parse(code_file.content),
         {:ok, basic_analysis} <- Security.analyze(code_file) do
      
      enhanced_results =
        basic_analysis
        |> enhance_with_call_chain_analysis(ast_data)
        |> enhance_with_variable_flow_analysis(ast_data)
        |> enhance_with_pattern_security_check(ast_data)
      
      {:ok, enhanced_results}
    end
  end
  
  # Enhanced variable analysis
  defp enhance_with_variable_analysis(results, ast_data) do
    unused_vars = find_unused_variables(ast_data)
    shadowed_vars = find_shadowed_variables(ast_data)
    
    new_issues = 
      Enum.map(unused_vars, fn var ->
        %{
          type: :unused_variable,
          severity: :warning,
          message: "Variable '#{var.name}' is assigned but never used",
          line: var.line,
          enhanced: true
        }
      end) ++
      Enum.map(shadowed_vars, fn {outer, inner} ->
        %{
          type: :variable_shadowing,
          severity: :warning,
          message: "Variable '#{inner.name}' shadows outer variable defined at line #{outer.line}",
          line: inner.line,
          enhanced: true
        }
      end)
    
    Map.update(results, :issues, new_issues, &(&1 ++ new_issues))
  end
  
  # Enhanced call graph analysis
  defp enhance_with_call_graph(results, ast_data) do
    call_graph = SourcerorParser.build_call_graph(ast_data)
    
    # Find functions that are never called (potential dead code)
    all_functions = Enum.map(ast_data.functions, fn f ->
      {f.module, f.name, f.arity}
    end)
    
    called_functions = 
      call_graph
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()
    
    uncalled = all_functions -- called_functions
    
    # Filter out common entry points
    uncalled = Enum.reject(uncalled, fn {_mod, name, _arity} ->
      name in [:init, :start_link, :child_spec, :handle_call, :handle_cast, :handle_info]
    end)
    
    new_issues = Enum.map(uncalled, fn {mod, fun, arity} ->
      function = Enum.find(ast_data.functions, fn f ->
        f.module == mod && f.name == fun && f.arity == arity
      end)
      
      %{
        type: :potentially_dead_code,
        severity: :info,
        message: "Function #{fun}/#{arity} is never called within this module",
        line: function.line,
        enhanced: true
      }
    end)
    
    results
    |> Map.put(:call_graph, call_graph)
    |> Map.update(:issues, new_issues, &(&1 ++ new_issues))
  end
  
  # Pattern detection
  defp enhance_with_pattern_detection(results, ast_data) do
    # Detect common patterns and anti-patterns
    patterns = detect_patterns(ast_data)
    
    pattern_feedback = Enum.map(patterns, fn
      {:callback_hell, location} ->
        %{
          type: :pattern_detected,
          severity: :info,
          message: "Deep nesting detected - consider refactoring",
          line: location,
          enhanced: true
        }
      
      {:guard_overuse, function} ->
        %{
          type: :pattern_detected,
          severity: :info,
          message: "Complex guards in #{function.name}/#{function.arity} - consider pattern matching",
          line: function.line,
          enhanced: true
        }
    end)
    
    Map.update(results, :issues, pattern_feedback, &(&1 ++ pattern_feedback))
  end
  
  # Helper functions
  
  defp find_unused_variables(ast_data) do
    # Group variables by function
    vars_by_function = Enum.group_by(ast_data.variables, & &1.scope)
    
    Enum.flat_map(vars_by_function, fn {_scope, vars} ->
      assignments = Enum.filter(vars, &(&1.type == :assignment))
      usages = Enum.filter(vars, &(&1.type == :usage))
      used_names = MapSet.new(usages, & &1.name)
      
      Enum.reject(assignments, &MapSet.member?(used_names, &1.name))
    end)
  end
  
  defp find_shadowed_variables(ast_data) do
    # Simple shadowing detection - would need more sophisticated scope tracking
    vars_by_name = Enum.group_by(ast_data.variables, & &1.name)
    
    Enum.flat_map(vars_by_name, fn {_name, vars} ->
      assignments = Enum.filter(vars, &(&1.type == :assignment))
      
      if length(assignments) > 1 do
        # Create pairs of potentially shadowed variables
        for outer <- assignments,
            inner <- assignments,
            outer.line < inner.line do
          {outer, inner}
        end
      else
        []
      end
    end)
  end
  
  defp enhance_with_naming_analysis(results, ast_data) do
    naming_issues = 
      ast_data.functions
      |> Enum.flat_map(fn function ->
        cond do
          # Check for non-snake_case function names
          !snake_case?(Atom.to_string(function.name)) ->
            [%{
              type: :naming_convention,
              severity: :warning,
              message: "Function name '#{function.name}' should be in snake_case",
              line: function.line,
              enhanced: true
            }]
          
          # Check for overly long function names
          String.length(Atom.to_string(function.name)) > 30 ->
            [%{
              type: :naming_convention,
              severity: :info,
              message: "Function name '#{function.name}' is very long",
              line: function.line,
              enhanced: true
            }]
          
          true ->
            []
        end
      end)
    
    Map.update(results, :issues, naming_issues, &(&1 ++ naming_issues))
  end
  
  defp enhance_with_module_structure(results, ast_data) do
    # Check module organization
    structure_issues = []
    
    # Check for too many functions in a module
    structure_issues = if length(ast_data.functions) > 30 do
      [%{
        type: :module_complexity,
        severity: :info,
        message: "Module has #{length(ast_data.functions)} functions - consider splitting",
        line: 1,
        enhanced: true
      } | structure_issues]
    else
      structure_issues
    end
    
    # Check import/alias organization
    structure_issues = if length(ast_data.imports) > 10 do
      [%{
        type: :import_complexity,
        severity: :info,
        message: "Module has #{length(ast_data.imports)} imports - consider reducing",
        line: 1,
        enhanced: true
      } | structure_issues]
    else
      structure_issues
    end
    
    Map.update(results, :issues, structure_issues, &(&1 ++ structure_issues))
  end
  
  defp enhance_with_import_analysis(results, ast_data) do
    # Check for unused imports
    imported_functions = 
      ast_data.imports
      |> Enum.flat_map(fn import ->
        case import.only do
          nil -> []  # Import all - can't check usage
          only -> Enum.map(only, fn {fun, arity} -> {import.module, fun, arity} end)
        end
      end)
    
    used_calls = 
      ast_data.calls
      |> Enum.filter(&(&1.type == :remote))
      |> Enum.map(& &1.to)
      |> MapSet.new()
    
    unused_imports = 
      imported_functions
      |> Enum.reject(&MapSet.member?(used_calls, &1))
      |> Enum.map(fn {module, fun, arity} ->
        import = Enum.find(ast_data.imports, &(&1.module == module))
        %{
          type: :unused_import,
          severity: :info,
          message: "Imported function #{module}.#{fun}/#{arity} is never used",
          line: import.line,
          enhanced: true
        }
      end)
    
    Map.update(results, :issues, unused_imports, &(&1 ++ unused_imports))
  end
  
  defp enhance_with_call_chain_analysis(results, ast_data) do
    # Analyze call chains for security issues
    call_graph = SourcerorParser.build_call_graph(ast_data)
    
    # Find paths to dangerous functions
    dangerous_functions = [
      {System, :cmd, 2},
      {:os, :cmd, 1},
      {Code, :eval_string, 1},
      {Code, :eval_file, 1}
    ]
    
    security_issues = 
      Enum.flat_map(call_graph, fn {from, calls} ->
        dangerous_calls = Enum.filter(calls, &(&1 in dangerous_functions))
        
        Enum.map(dangerous_calls, fn dangerous ->
          %{
            type: :dangerous_call_chain,
            severity: :warning,
            message: "Function #{elem(from, 1)}/#{elem(from, 2)} calls potentially dangerous #{elem(dangerous, 0)}.#{elem(dangerous, 1)}/#{elem(dangerous, 2)}",
            line: 0,  # Would need to track this better
            enhanced: true
          }
        end)
      end)
    
    Map.update(results, :issues, security_issues, &(&1 ++ security_issues))
  end
  
  defp enhance_with_variable_flow_analysis(results, ast_data) do
    # Track variable flow for taint analysis
    # This is a simplified version - real taint analysis would be more complex
    
    # Find variables that might contain user input
    user_input_patterns = ~w(params input data request body)a
    
    tainted_vars = 
      ast_data.variables
      |> Enum.filter(fn var ->
        var.type == :assignment && 
        Enum.any?(user_input_patterns, &String.contains?(Atom.to_string(var.name), Atom.to_string(&1)))
      end)
    
    # Find where these variables are used
    taint_issues = 
      Enum.flat_map(tainted_vars, fn tainted ->
        # Find calls that might use this variable
        # This is simplified - would need proper data flow analysis
        [%{
          type: :potential_injection,
          severity: :info,
          message: "Variable '#{tainted.name}' might contain user input - ensure proper validation",
          line: tainted.line,
          enhanced: true
        }]
      end)
    
    Map.update(results, :issues, taint_issues, &(&1 ++ taint_issues))
  end
  
  defp enhance_with_pattern_security_check(results, ast_data) do
    # Check for insecure patterns
    pattern_issues = []
    
    # Check for atom creation from user input
    # This would need more sophisticated analysis
    atom_creation = 
      ast_data.calls
      |> Enum.filter(fn call ->
        call.to in [{String, :to_atom, 1}, {String, :to_existing_atom, 1}]
      end)
      |> Enum.map(fn call ->
        %{
          type: :atom_creation,
          severity: :warning,
          message: "Creating atoms from strings can lead to atom exhaustion",
          line: call.line,
          enhanced: true
        }
      end)
    
    Map.update(results, :issues, pattern_issues ++ atom_creation, &(&1 ++ pattern_issues ++ atom_creation))
  end
  
  defp detect_patterns(ast_data) do
    patterns = []
    
    # Detect callback hell (deep nesting)
    # Would need to analyze actual AST structure for real implementation
    
    # Detect guard overuse
    complex_guards = 
      ast_data.functions
      |> Enum.filter(fn f -> 
        f.guards != nil && is_complex_guard?(f.guards)
      end)
      |> Enum.map(&{:guard_overuse, &1})
    
    patterns ++ complex_guards
  end
  
  defp snake_case?(string) do
    Regex.match?(~r/^[a-z_][a-z0-9_]*[!?]?$/, string)
  end
  
  defp is_complex_guard?(guards) when is_list(guards) do
    length(guards) > 3
  end
  defp is_complex_guard?(_), do: false
end

# Example usage module
defmodule RubberDuck.Analysis.SourcerorExample do
  @moduledoc """
  Example showing how to use the Sourceror parser in practice.
  """
  
  alias RubberDuck.Analysis.AST.SourcerorParser
  alias RubberDuck.Analysis.SourcerorIntegration
  alias RubberDuck.Workspace
  
  def analyze_project(project_id) do
    with {:ok, project} <- Workspace.get_project(project_id),
         {:ok, files} <- Workspace.list_code_files(project_id) do
      
      results = Enum.map(files, &analyze_file/1)
      
      %{
        project: project,
        files_analyzed: length(files),
        total_issues: count_issues(results),
        results_by_file: results
      }
    end
  end
  
  defp analyze_file(code_file) do
    # Perform all three types of enhanced analysis
    with {:ok, semantic} <- SourcerorIntegration.enhanced_semantic_analysis(code_file),
         {:ok, style} <- SourcerorIntegration.enhanced_style_analysis(code_file),
         {:ok, security} <- SourcerorIntegration.enhanced_security_analysis(code_file) do
      
      %{
        file: code_file.file_path,
        semantic_issues: semantic.issues,
        style_issues: style.issues,
        security_issues: security.issues,
        metrics: extract_metrics(code_file)
      }
    end
  end
  
  defp extract_metrics(code_file) do
    case SourcerorParser.parse(code_file.content) do
      {:ok, ast_data} ->
        %{
          total_functions: length(ast_data.functions),
          public_functions: Enum.count(ast_data.functions, &(&1.type == :def)),
          private_functions: Enum.count(ast_data.functions, &(&1.type == :defp)),
          total_modules: length(ast_data.modules),
          total_calls: length(ast_data.calls),
          imports: length(ast_data.imports),
          aliases: length(ast_data.aliases)
        }
      _ ->
        %{}
    end
  end
  
  defp count_issues(results) do
    Enum.reduce(results, 0, fn result, acc ->
      acc + 
        length(result.semantic_issues) +
        length(result.style_issues) +
        length(result.security_issues)
    end)
  end
end
