defmodule RubberDuck.CodeCorrection.FixValidator do
  @moduledoc """
  Fix validation module for verifying code corrections.
  
  Provides comprehensive validation of code fixes including syntax checks,
  semantic validation, and behavioral verification.
  """

  require Logger

  @doc """
  Validates a code fix against the original error and context.
  """
  def validate_fix(fix_result, error_data, config \\ %{}) do
    validations = [
      validate_syntax(fix_result),
      validate_compilation(fix_result),
      validate_error_resolution(fix_result, error_data),
      validate_no_regressions(fix_result, error_data),
      validate_semantic_correctness(fix_result, error_data)
    ]
    
    # Run additional validations if configured
    validations = if config["strict_mode"] do
      validations ++ [
        validate_style_compliance(fix_result, config),
        validate_performance_impact(fix_result, error_data)
      ]
    else
      validations
    end
    
    # Aggregate results
    aggregate_validation_results(validations)
  end

  @doc """
  Performs quick validation for real-time feedback.
  """
  def quick_validate(fixed_code) do
    case validate_syntax(%{fixed_code: fixed_code}) do
      %{valid: true} ->
        %{valid: true, confidence: 0.8, quick_check: true}
        
      error ->
        Map.put(error, :quick_check, true)
    end
  end

  ## Private Functions - Individual Validations

  defp validate_syntax(fix_result) do
    code = fix_result.fixed_code || fix_result[:fixed_code]
    
    case Code.string_to_quoted(code) do
      {:ok, _ast} ->
        %{
          check: :syntax,
          valid: true,
          confidence: 1.0,
          details: "Syntax is valid"
        }
        
      {:error, {line, error_desc, _token}} ->
        %{
          check: :syntax,
          valid: false,
          confidence: 1.0,
          error: "Syntax error at line #{line}: #{inspect(error_desc)}",
          details: "Fixed code contains syntax errors"
        }
    end
  end

  defp validate_compilation(fix_result) do
    code = fix_result.fixed_code || fix_result[:fixed_code]
    
    try do
      # Try to compile the code
      case Code.compile_string(code) do
        [] ->
          %{
            check: :compilation,
            valid: false,
            confidence: 0.9,
            warning: "Code compiles but produces no modules"
          }
          
        compiled ->
          %{
            check: :compilation,
            valid: true,
            confidence: 0.95,
            details: "Successfully compiled #{length(compiled)} modules"
          }
      end
    rescue
      e ->
        %{
          check: :compilation,
          valid: false,
          confidence: 0.95,
          error: Exception.message(e),
          details: "Compilation failed"
        }
    end
  end

  defp validate_error_resolution(fix_result, error_data) do
    original_error_type = error_data["error_type"]
    fixed_code = fix_result.fixed_code || fix_result[:fixed_code]
    
    # Check if the original error would still occur
    case check_for_error(fixed_code, original_error_type) do
      :not_found ->
        %{
          check: :error_resolution,
          valid: true,
          confidence: 0.85,
          details: "Original error appears to be resolved"
        }
        
      {:found, error_info} ->
        %{
          check: :error_resolution,
          valid: false,
          confidence: 0.85,
          error: "Original error still present: #{inspect(error_info)}",
          details: "Fix did not resolve the original error"
        }
    end
  end

  defp validate_no_regressions(fix_result, error_data) do
    original_code = error_data["code"]
    fixed_code = fix_result.fixed_code || fix_result[:fixed_code]
    
    # Check for potential regressions
    regressions = check_for_regressions(original_code, fixed_code)
    
    if Enum.empty?(regressions) do
      %{
        check: :no_regressions,
        valid: true,
        confidence: 0.8,
        details: "No regressions detected"
      }
    else
      %{
        check: :no_regressions,
        valid: false,
        confidence: 0.8,
        warnings: regressions,
        details: "Potential regressions found"
      }
    end
  end

  defp validate_semantic_correctness(fix_result, _error_data) do
    fixed_code = fix_result.fixed_code || fix_result[:fixed_code]
    semantic_changes = fix_result[:semantic_changes] || []
    
    # Validate semantic changes
    issues = validate_semantic_changes(fixed_code, semantic_changes)
    
    if Enum.empty?(issues) do
      %{
        check: :semantic_correctness,
        valid: true,
        confidence: 0.75,
        details: "Semantic changes appear valid"
      }
    else
      %{
        check: :semantic_correctness,
        valid: false,
        confidence: 0.75,
        issues: issues,
        details: "Semantic validation found issues"
      }
    end
  end

  defp validate_style_compliance(fix_result, config) do
    fixed_code = fix_result.fixed_code || fix_result[:fixed_code]
    style_guide = config["style_guide"] || "default"
    
    violations = check_style_violations(fixed_code, style_guide)
    
    if Enum.empty?(violations) do
      %{
        check: :style_compliance,
        valid: true,
        confidence: 0.7,
        details: "Code follows style guidelines"
      }
    else
      %{
        check: :style_compliance,
        valid: false,
        confidence: 0.7,
        violations: violations,
        details: "Style violations found"
      }
    end
  end

  defp validate_performance_impact(fix_result, error_data) do
    original_code = error_data["code"]
    fixed_code = fix_result.fixed_code || fix_result[:fixed_code]
    
    # Simple performance analysis
    impact = analyze_performance_impact(original_code, fixed_code)
    
    if impact.degradation < 0.1 do
      %{
        check: :performance,
        valid: true,
        confidence: 0.6,
        impact: impact,
        details: "No significant performance degradation"
      }
    else
      %{
        check: :performance,
        valid: false,
        confidence: 0.6,
        impact: impact,
        warning: "Potential performance degradation: #{impact.degradation * 100}%"
      }
    end
  end

  ## Private Functions - Validation Helpers

  defp check_for_error(code, error_type) do
    # Simplified error checking
    case error_type do
      "undefined_variable" ->
        check_undefined_variables(code)
        
      "undefined_function" ->
        check_undefined_functions(code)
        
      "syntax_error" ->
        case Code.string_to_quoted(code) do
          {:ok, _} -> :not_found
          {:error, error} -> {:found, error}
        end
        
      _ ->
        :not_found
    end
  end

  defp check_undefined_variables(code) do
    # Simplified check - would use AST analysis in practice
    case Code.string_to_quoted(code) do
      {:ok, ast} ->
        undefined_vars = find_undefined_in_ast(ast)
        if Enum.empty?(undefined_vars) do
          :not_found
        else
          {:found, {:undefined_variables, undefined_vars}}
        end
        
      _ ->
        :not_found
    end
  end

  defp check_undefined_functions(_code) do
    # Simplified check
    :not_found
  end

  defp find_undefined_in_ast(_ast) do
    # Simplified - would traverse AST looking for undefined references
    []
  end

  defp check_for_regressions(original_code, fixed_code) do
    regressions = []
    
    # Check if any functions were removed
    original_functions = extract_function_names(original_code)
    fixed_functions = extract_function_names(fixed_code)
    removed_functions = original_functions -- fixed_functions
    
    regressions = if not Enum.empty?(removed_functions) do
      ["Functions removed: #{Enum.join(removed_functions, ", ")}" | regressions]
    else
      regressions
    end
    
    # Check if any module attributes were removed
    original_attrs = extract_module_attributes(original_code)
    fixed_attrs = extract_module_attributes(fixed_code)
    removed_attrs = original_attrs -- fixed_attrs
    
    regressions = if not Enum.empty?(removed_attrs) do
      ["Module attributes removed: #{Enum.join(removed_attrs, ", ")}" | regressions]
    else
      regressions
    end
    
    regressions
  end

  defp extract_function_names(code) do
    ~r/def(?:p?)\s+(\w+)/
    |> Regex.scan(code)
    |> Enum.map(&List.last/1)
    |> Enum.uniq()
  end

  defp extract_module_attributes(code) do
    ~r/@(\w+)/
    |> Regex.scan(code)
    |> Enum.map(&List.last/1)
    |> Enum.uniq()
  end

  defp validate_semantic_changes(code, semantic_changes) do
    Enum.flat_map(semantic_changes, fn change ->
      validate_single_semantic_change(code, change)
    end)
  end

  defp validate_single_semantic_change(code, change) do
    case change[:type] do
      :variable_definition ->
        if String.contains?(code, change[:definition]) do
          []
        else
          ["Variable definition not found in code: #{change[:variable]}"]
        end
        
      :type_conversion ->
        if String.contains?(code, change[:conversion]) do
          []
        else
          ["Type conversion not applied: #{change[:expression]}"]
        end
        
      :import_added ->
        if String.contains?(code, "import #{change[:module]}") or
           String.contains?(code, "alias #{change[:module]}") do
          []
        else
          ["Import not found in code: #{change[:module]}"]
        end
        
      _ ->
        []
    end
  end

  defp check_style_violations(code, _style_guide) do
    violations = []
    
    # Basic style checks
    lines = String.split(code, "\n")
    
    # Line length check
    long_lines = lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _idx} -> String.length(line) > 120 end)
    
    violations = if not Enum.empty?(long_lines) do
      line_numbers = Enum.map(long_lines, fn {_, idx} -> idx end)
      ["Lines too long (>120 chars): #{Enum.join(line_numbers, ", ")}" | violations]
    else
      violations
    end
    
    # Trailing whitespace
    trailing_ws = lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _idx} -> line =~ ~r/\s+$/ end)
    
    violations = if not Enum.empty?(trailing_ws) do
      line_numbers = Enum.map(trailing_ws, fn {_, idx} -> idx end)
      ["Trailing whitespace on lines: #{Enum.join(line_numbers, ", ")}" | violations]
    else
      violations
    end
    
    violations
  end

  defp analyze_performance_impact(original_code, fixed_code) do
    # Simplified performance analysis
    original_complexity = estimate_complexity(original_code)
    fixed_complexity = estimate_complexity(fixed_code)
    
    %{
      original_complexity: original_complexity,
      fixed_complexity: fixed_complexity,
      degradation: max(0, (fixed_complexity - original_complexity) / original_complexity)
    }
  end

  defp estimate_complexity(code) do
    # Very simplified complexity estimation
    lines = String.split(code, "\n")
    
    # Count various complexity indicators
    loops = Enum.count(lines, &String.contains?(&1, "for "))
    conditionals = Enum.count(lines, &(String.contains?(&1, "if ") or String.contains?(&1, "case ")))
    functions = Enum.count(lines, &String.contains?(&1, "def "))
    
    # Simple complexity score
    base_complexity = length(lines) * 0.1
    loop_complexity = loops * 2.0
    conditional_complexity = conditionals * 1.5
    function_complexity = functions * 1.0
    
    base_complexity + loop_complexity + conditional_complexity + function_complexity
  end

  ## Private Functions - Result Aggregation

  defp aggregate_validation_results(validations) do
    all_valid = Enum.all?(validations, & &1.valid)
    
    # Calculate overall confidence as weighted average
    total_confidence = validations
    |> Enum.map(& &1.confidence)
    |> Enum.sum()
    
    avg_confidence = total_confidence / length(validations)
    
    # Collect all errors and warnings
    errors = validations
    |> Enum.filter(&Map.has_key?(&1, :error))
    |> Enum.map(& &1.error)
    
    warnings = validations
    |> Enum.filter(&Map.has_key?(&1, :warning))
    |> Enum.map(& &1.warning)
    
    result = %{
      valid: all_valid,
      confidence: avg_confidence,
      checks_performed: length(validations),
      checks_passed: Enum.count(validations, & &1.valid),
      validation_details: validations
    }
    
    result = if not Enum.empty?(errors) do
      Map.put(result, :errors, errors)
    else
      result
    end
    
    result = if not Enum.empty?(warnings) do
      Map.put(result, :warnings, warnings)
    else
      result
    end
    
    result
  end
end