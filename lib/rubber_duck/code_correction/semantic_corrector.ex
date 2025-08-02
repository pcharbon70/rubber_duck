defmodule RubberDuck.CodeCorrection.SemanticCorrector do
  @moduledoc """
  Semantic correction module for fixing semantic errors in code.
  
  Handles type corrections, import resolution, variable scope fixes,
  and code refactoring based on semantic analysis.
  """

  require Logger

  @doc """
  Fixes semantic errors based on rules and error information.
  """
  def fix_semantic_error(error_data, rules, strategy, options \\ %{}) do
    code = error_data["code"]
    error_type = error_data["error_type"]
    error_context = error_data["context"] || %{}
    
    # Find applicable rules
    applicable_rules = find_applicable_rules(error_type, error_context, rules)
    
    # Apply rules in priority order
    case apply_semantic_rules(code, error_data, applicable_rules, options) do
      {:ok, result} ->
        {:ok, result}
        
      :no_fix ->
        # Try strategy-specific fixes
        apply_strategy_fixes(code, error_data, strategy, options)
    end
  end

  @doc """
  Refactors code based on configuration.
  """
  def refactor_code(code, config) do
    refactoring_type = config["type"] || "general"
    
    case refactoring_type do
      "extract_function" ->
        extract_function_refactoring(code, config)
        
      "rename_variable" ->
        rename_variable_refactoring(code, config)
        
      "simplify_logic" ->
        simplify_logic_refactoring(code, config)
        
      "remove_duplication" ->
        remove_duplication_refactoring(code, config)
        
      _ ->
        general_refactoring(code, config)
    end
  end

  ## Private Functions - Rule Application

  defp find_applicable_rules(error_type, error_context, rules) do
    rules
    |> Enum.filter(fn {_rule_id, rule} ->
      rule_matches?(rule, error_type, error_context)
    end)
    |> Enum.sort_by(fn {_rule_id, rule} -> rule.priority end)
    |> Enum.map(fn {rule_id, rule} -> {rule_id, rule} end)
  end

  defp rule_matches?(rule, error_type, error_context) do
    condition = rule.condition
    
    # Check error type match
    type_matches = Map.get(condition, :error_type) == error_type
    
    # Check additional conditions
    context_matches = Enum.all?(Map.delete(condition, :error_type), fn {key, expected_value} ->
      Map.get(error_context, Atom.to_string(key)) == expected_value
    end)
    
    type_matches and context_matches
  end

  defp apply_semantic_rules(code, error_data, rules, options) do
    Enum.reduce_while(rules, :no_fix, fn {_rule_id, rule}, _acc ->
      case apply_single_rule(code, error_data, rule, options) do
        {:ok, result} ->
          {:halt, {:ok, result}}
          
        :no_fix ->
          {:cont, :no_fix}
      end
    end)
  end

  defp apply_single_rule(code, error_data, rule, _options) do
    action = rule.action
    
    case action.type do
      "define_variable" ->
        fix_undefined_variable(code, error_data, action)
        
      "convert_type" ->
        fix_type_mismatch(code, error_data, action)
        
      "add_import" ->
        fix_missing_import(code, error_data, action)
        
      _ ->
        :no_fix
    end
  end

  ## Private Functions - Specific Fixes

  defp fix_undefined_variable(code, error_data, action) do
    variable_name = error_data["variable_name"] || extract_variable_name(error_data)
    
    if variable_name do
      # Determine variable definition based on usage
      definition = infer_variable_definition(code, variable_name, action)
      
      # Find appropriate insertion point
      insertion_point = find_variable_insertion_point(code, variable_name)
      
      # Insert variable definition
      fixed_code = insert_at_line(code, insertion_point, definition)
      
      {:ok, %{
        corrected_code: fixed_code,
        semantic_changes: [%{
          type: :variable_definition,
          variable: variable_name,
          definition: definition,
          line: insertion_point
        }],
        imports_added: [],
        types_corrected: [],
        confidence: 0.8
      }}
    else
      :no_fix
    end
  end

  defp fix_type_mismatch(code, error_data, action) do
    expected_type = error_data["expected_type"]
    actual_type = error_data["actual_type"]
    expression = error_data["expression"]
    
    if expected_type && actual_type && expression do
      # Generate type conversion
      conversion = generate_type_conversion(expression, actual_type, expected_type, action)
      
      # Replace expression with converted version
      fixed_code = String.replace(code, expression, conversion)
      
      {:ok, %{
        corrected_code: fixed_code,
        semantic_changes: [%{
          type: :type_conversion,
          from: actual_type,
          to: expected_type,
          expression: expression,
          conversion: conversion
        }],
        imports_added: [],
        types_corrected: [{expression, expected_type}],
        confidence: 0.85
      }}
    else
      :no_fix
    end
  end

  defp fix_missing_import(code, error_data, action) do
    function_name = error_data["function_name"] || extract_function_name(error_data)
    
    if function_name do
      # Search for module containing the function
      case find_module_for_function(function_name, action) do
        {:ok, module_name} ->
          # Generate import statement
          import_statement = generate_import_statement(module_name, function_name)
          
          # Find insertion point for import
          insertion_line = find_import_insertion_point(code)
          
          # Insert import
          fixed_code = insert_at_line(code, insertion_line, import_statement)
          
          {:ok, %{
            corrected_code: fixed_code,
            semantic_changes: [%{
              type: :import_added,
              module: module_name,
              function: function_name,
              line: insertion_line
            }],
            imports_added: [module_name],
            types_corrected: [],
            confidence: 0.9
          }}
          
        :not_found ->
          :no_fix
      end
    else
      :no_fix
    end
  end

  ## Private Functions - Strategy-based Fixes

  defp apply_strategy_fixes(code, error_data, strategy, options) do
    strategy_type = strategy["type"] || "default"
    
    case strategy_type do
      "comprehensive" ->
        apply_comprehensive_fix(code, error_data, strategy, options)
        
      "minimal" ->
        apply_minimal_fix(code, error_data, strategy, options)
        
      _ ->
        {:error, "No semantic fix available"}
    end
  end

  defp apply_comprehensive_fix(code, error_data, _strategy, _options) do
    # Comprehensive fix that may involve multiple changes
    changes = []
    fixed_code = code
    
    # Fix all undefined variables
    undefined_vars = find_undefined_variables(code, error_data)
    {fixed_code, var_changes} = fix_all_undefined_variables(fixed_code, undefined_vars)
    changes = changes ++ var_changes
    
    # Fix all type mismatches
    type_errors = find_type_errors(code, error_data)
    {fixed_code, type_changes} = fix_all_type_errors(fixed_code, type_errors)
    changes = changes ++ type_changes
    
    if fixed_code != code do
      {:ok, %{
        corrected_code: fixed_code,
        semantic_changes: changes,
        imports_added: extract_imports_from_changes(changes),
        types_corrected: extract_type_corrections_from_changes(changes),
        confidence: 0.75
      }}
    else
      {:error, "No comprehensive fix could be applied"}
    end
  end

  defp apply_minimal_fix(code, error_data, _strategy, _options) do
    # Minimal fix that addresses only the specific error
    error_type = error_data["error_type"]
    
    minimal_fix = case error_type do
      "undefined_variable" ->
        var_name = extract_variable_name(error_data)
        add_minimal_variable_definition(code, var_name)
        
      "type_error" ->
        add_minimal_type_annotation(code, error_data)
        
      _ ->
        nil
    end
    
    if minimal_fix do
      {:ok, %{
        corrected_code: minimal_fix,
        semantic_changes: [%{type: :minimal_fix, error_type: error_type}],
        imports_added: [],
        types_corrected: [],
        confidence: 0.6
      }}
    else
      {:error, "No minimal fix available"}
    end
  end

  ## Private Functions - Refactoring

  defp extract_function_refactoring(code, config) do
    start_line = config["start_line"]
    end_line = config["end_line"]
    function_name = config["function_name"] || "extracted_function"
    
    # Extract code block
    lines = String.split(code, "\n")
    extracted_lines = Enum.slice(lines, (start_line - 1)..(end_line - 1))
    extracted_code = Enum.join(extracted_lines, "\n")
    
    # Analyze variables used
    variables = analyze_variable_usage(extracted_code)
    
    # Generate function
    new_function = generate_extracted_function(function_name, variables, extracted_code)
    
    # Replace with function call
    function_call = generate_function_call(function_name, variables)
    
    # Reconstruct code
    refactored_lines = 
      Enum.slice(lines, 0..(start_line - 2)) ++
      [function_call] ++
      Enum.slice(lines, end_line..-1) ++
      ["", new_function]
    
    refactored_code = Enum.join(refactored_lines, "\n")
    
    {:ok, %{
      code: refactored_code,
      type: :extract_function,
      improvements: ["Extracted #{end_line - start_line + 1} lines into function #{function_name}"],
      metrics_change: %{
        complexity: -0.3,
        maintainability: 0.5
      }
    }}
  end

  defp rename_variable_refactoring(code, config) do
    old_name = config["old_name"]
    new_name = config["new_name"]
    
    if old_name && new_name do
      # Use regex to rename only variable occurrences
      pattern = ~r/\b#{Regex.escape(old_name)}\b/
      refactored_code = Regex.replace(pattern, code, new_name)
      
      {:ok, %{
        code: refactored_code,
        type: :rename_variable,
        improvements: ["Renamed variable #{old_name} to #{new_name}"],
        metrics_change: %{
          readability: 0.2,
          consistency: 0.1
        }
      }}
    else
      {:error, "Missing variable names for refactoring"}
    end
  end

  defp simplify_logic_refactoring(code, _config) do
    simplifications = [
      # Simplify boolean expressions
      {~r/if\s+(.+?)\s*==\s*true\s+do/, "if \\1 do"},
      {~r/if\s+(.+?)\s*==\s*false\s+do/, "unless \\1 do"},
      {~r/not\s+not\s+(.+)/, "\\1"},
      
      # Simplify pattern matching
      {~r/case\s+(.+?)\s+do\s*\n\s*true\s*->\s*(.+?)\n\s*false\s*->\s*(.+?)\n\s*end/m,
       "if \\1 do\n  \\2\nelse\n  \\3\nend"}
    ]
    
    refactored_code = Enum.reduce(simplifications, code, fn {pattern, replacement}, acc ->
      Regex.replace(pattern, acc, replacement)
    end)
    
    if refactored_code != code do
      {:ok, %{
        code: refactored_code,
        type: :simplify_logic,
        improvements: ["Simplified boolean logic and pattern matching"],
        metrics_change: %{
          complexity: -0.2,
          readability: 0.3
        }
      }}
    else
      {:error, "No logic simplification applicable"}
    end
  end

  defp remove_duplication_refactoring(code, _config) do
    # Find duplicate code blocks
    lines = String.split(code, "\n")
    duplicates = find_duplicate_blocks(lines)
    
    if length(duplicates) > 0 do
      # Extract common code into functions
      {refactored_code, functions_created} = extract_duplicate_blocks(code, duplicates)
      
      {:ok, %{
        code: refactored_code,
        type: :remove_duplication,
        improvements: ["Removed #{length(duplicates)} duplicate blocks, created #{functions_created} functions"],
        metrics_change: %{
          duplication: -0.5,
          maintainability: 0.4
        }
      }}
    else
      {:error, "No code duplication found"}
    end
  end

  defp general_refactoring(code, config) do
    # Apply multiple small refactorings
    refactorings = []
    refactored_code = code
    
    # Add type specs if missing
    if config["add_typespecs"] do
      {updated_code, specs_added} = add_type_specs(refactored_code)
      _ = updated_code
      _ = ["Added #{specs_added} type specifications" | refactorings]
    end
    
    # Format code
    if config["format_code"] do
      formatted_code = format_code(refactored_code)
      _ = formatted_code
      _ = ["Formatted code for consistency" | refactorings]
    end
    
    if refactored_code != code do
      {:ok, %{
        code: refactored_code,
        type: :general,
        improvements: refactorings,
        metrics_change: %{
          quality: 0.2,
          consistency: 0.3
        }
      }}
    else
      {:error, "No general refactoring applicable"}
    end
  end

  ## Private Functions - Helpers

  defp extract_variable_name(error_data) do
    error_message = error_data["error_message"] || ""
    
    # Try to extract variable name from error message
    case Regex.run(~r/undefined.*variable.*[`']?(\w+)[`']?/, error_message) do
      [_, var_name] -> var_name
      _ -> nil
    end
  end

  defp extract_function_name(error_data) do
    error_message = error_data["error_message"] || ""
    
    # Try to extract function name from error message
    case Regex.run(~r/undefined.*function.*[`']?(\w+)[`']?/, error_message) do
      [_, func_name] -> func_name
      _ -> nil
    end
  end

  defp infer_variable_definition(code, variable_name, _action) do
    # Infer type from usage context
    cond do
      String.contains?(code, "#{variable_name} + ") or
      String.contains?(code, "#{variable_name} - ") ->
        "#{variable_name} = 0"
        
      String.contains?(code, "#{variable_name} <> ") ->
        "#{variable_name} = \"\""
        
      String.contains?(code, "[#{variable_name} | ") ->
        "#{variable_name} = []"
        
      String.contains?(code, "#{variable_name}.") ->
        "#{variable_name} = %{}"
        
      true ->
        "#{variable_name} = nil"
    end
  end

  defp find_variable_insertion_point(code, variable_name) do
    lines = String.split(code, "\n")
    
    # Find first usage of variable
    usage_line = Enum.find_index(lines, fn line ->
      String.contains?(line, variable_name)
    end) || 0
    
    # Insert before first usage
    max(0, usage_line - 1)
  end

  defp generate_type_conversion(expression, from_type, to_type, _action) do
    case {from_type, to_type} do
      {"string", "integer"} -> "String.to_integer(#{expression})"
      {"integer", "string"} -> "Integer.to_string(#{expression})"
      {"string", "atom"} -> "String.to_atom(#{expression})"
      {"atom", "string"} -> "Atom.to_string(#{expression})"
      {"list", "string"} -> "Enum.join(#{expression})"
      {"string", "list"} -> "String.split(#{expression})"
      _ -> expression  # No conversion available
    end
  end

  defp find_module_for_function(function_name, _action) do
    # Simplified module search - in practice would search project
    common_modules = %{
      "to_string" => "Kernel",
      "inspect" => "Kernel",
      "map" => "Enum",
      "reduce" => "Enum",
      "filter" => "Enum",
      "spawn" => "Kernel",
      "send" => "Kernel"
    }
    
    case Map.get(common_modules, function_name) do
      nil -> :not_found
      module_name -> {:ok, module_name}
    end
  end

  defp generate_import_statement(module_name, function_name) do
    "  import #{module_name}, only: [#{function_name}: 1]"
  end

  defp find_import_insertion_point(code) do
    lines = String.split(code, "\n")
    
    # Find after module definition
    module_line = Enum.find_index(lines, fn line ->
      String.starts_with?(String.trim(line), "defmodule")
    end) || 0
    
    # Find after existing imports/aliases
    last_import = Enum.reduce(Enum.with_index(lines), module_line + 1, fn {line, idx}, acc ->
      if String.starts_with?(String.trim(line), "import") or
         String.starts_with?(String.trim(line), "alias") or
         String.starts_with?(String.trim(line), "require") do
        idx + 1
      else
        acc
      end
    end)
    
    last_import
  end

  defp insert_at_line(code, line_number, content) do
    lines = String.split(code, "\n")
    
    {before_lines, after_lines} = Enum.split(lines, line_number)
    
    Enum.join(before_lines ++ [content] ++ after_lines, "\n")
  end

  defp find_undefined_variables(_code, _error_data) do
    # Simplified - would use proper AST analysis
    []
  end

  defp fix_all_undefined_variables(code, _undefined_vars) do
    {code, []}
  end

  defp find_type_errors(_code, _error_data) do
    []
  end

  defp fix_all_type_errors(code, _type_errors) do
    {code, []}
  end

  defp extract_imports_from_changes(changes) do
    changes
    |> Enum.filter(&(&1[:type] == :import_added))
    |> Enum.map(&(&1[:module]))
    |> Enum.uniq()
  end

  defp extract_type_corrections_from_changes(changes) do
    changes
    |> Enum.filter(&(&1[:type] == :type_conversion))
    |> Enum.map(fn change -> {change[:expression], change[:to]} end)
  end

  defp add_minimal_variable_definition(code, var_name) do
    definition = "#{var_name} = nil\n"
    definition <> code
  end

  defp add_minimal_type_annotation(code, _error_data) do
    # Add @spec annotation
    code
  end

  defp analyze_variable_usage(code) do
    # Extract variables used in code block
    variables = Regex.scan(~r/\b([a-z_]\w*)\b/, code)
    |> Enum.map(&List.last/1)
    |> Enum.uniq()
    |> Enum.filter(&(&1 not in ["def", "defp", "if", "else", "do", "end"]))
    
    variables
  end

  defp generate_extracted_function(name, variables, body) do
    params = Enum.join(variables, ", ")
    
    """
    defp #{name}(#{params}) do
    #{indent_code(body, 2)}
    end
    """
  end

  defp generate_function_call(name, variables) do
    params = Enum.join(variables, ", ")
    "  #{name}(#{params})"
  end

  defp find_duplicate_blocks(_lines) do
    # Simplified duplicate detection
    []
  end

  defp extract_duplicate_blocks(code, _duplicates) do
    {code, 0}
  end

  defp add_type_specs(code) do
    # Simplified - would analyze functions and add specs
    {code, 0}
  end

  defp format_code(code) do
    # Use Elixir formatter if available
    try do
      Code.format_string!(code) |> IO.iodata_to_binary()
    rescue
      _ -> code
    end
  end

  defp indent_code(code, spaces) do
    indent = String.duplicate(" ", spaces)
    
    code
    |> String.split("\n")
    |> Enum.map(&(indent <> &1))
    |> Enum.join("\n")
  end
end