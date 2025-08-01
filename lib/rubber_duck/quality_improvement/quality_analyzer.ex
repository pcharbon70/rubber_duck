defmodule RubberDuck.QualityImprovement.QualityAnalyzer do
  @moduledoc """
  Quality analysis module for comprehensive code quality assessment.
  
  Provides analysis capabilities including code metrics calculation,
  style checking, complexity analysis, maintainability assessment,
  and documentation evaluation.
  """

  require Logger

  @doc """
  Analyzes code metrics including complexity, maintainability, and technical debt.
  """
  def analyze_code_metrics(code, standards, options \\ %{}) do
    Logger.debug("QualityAnalyzer: Analyzing code metrics")
    
    try do
      case Code.string_to_quoted(code) do
        {:ok, ast} ->
          # Calculate various metrics
          cyclomatic_complexity = calculate_cyclomatic_complexity(ast)
          cognitive_complexity = calculate_cognitive_complexity(ast)
          maintainability_index = calculate_maintainability_index(ast)
          technical_debt = assess_technical_debt(ast, standards)
          code_smells = detect_code_smells(ast)
          
          # Calculate overall quality score
          quality_score = calculate_quality_score(%{
            cyclomatic: cyclomatic_complexity,
            cognitive: cognitive_complexity,
            maintainability: maintainability_index,
            debt: technical_debt,
            smells: length(code_smells)
          })
          
          result = %{
            cyclomatic_complexity: cyclomatic_complexity,
            cognitive_complexity: cognitive_complexity,
            maintainability_index: maintainability_index,
            technical_debt: technical_debt,
            code_smells: code_smells,
            quality_score: quality_score,
            confidence: 0.85
          }
          
          {:ok, result}
          
        {:error, {line, error_desc, token}} ->
          {:error, "Syntax error at line #{line}: #{format_error(error_desc)} near '#{token}'"}
      end
    catch
      kind, reason ->
        Logger.error("QualityAnalyzer: Metrics analysis failed: #{kind} - #{inspect(reason)}")
        {:error, "Metrics analysis failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Analyzes code style including formatting, naming conventions, and documentation.
  """
  def analyze_code_style(code, standards, options \\ %{}) do
    Logger.debug("QualityAnalyzer: Analyzing code style")
    
    try do
      case Code.string_to_quoted(code) do
        {:ok, ast} ->
          # Perform style analysis
          formatting_issues = check_formatting_issues(code, standards)
          naming_violations = check_naming_conventions(ast, standards)
          documentation_gaps = check_documentation_requirements(ast, standards)
          
          # Calculate style score
          style_score = calculate_style_score(%{
            formatting: length(formatting_issues),
            naming: length(naming_violations),
            documentation: length(documentation_gaps)
          })
          
          # Generate recommendations
          recommendations = generate_style_recommendations(formatting_issues, naming_violations, documentation_gaps)
          
          result = %{
            formatting_issues: formatting_issues,
            naming_violations: naming_violations,
            documentation_gaps: documentation_gaps,
            style_score: style_score,
            recommendations: recommendations,
            confidence: 0.80
          }
          
          {:ok, result}
          
        {:error, {line, error_desc, token}} ->
          {:error, "Syntax error at line #{line}: #{format_error(error_desc)} near '#{token}'"}
      end
    catch
      kind, reason ->
        Logger.error("QualityAnalyzer: Style analysis failed: #{kind} - #{inspect(reason)}")
        {:error, "Style analysis failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Analyzes code complexity including function complexity and nesting depth.
  """
  def analyze_complexity(code, options \\ %{}) do
    Logger.debug("QualityAnalyzer: Analyzing code complexity")
    
    try do
      case Code.string_to_quoted(code) do
        {:ok, ast} ->
          # Analyze complexity aspects
          function_complexity = analyze_function_complexity(ast)
          nesting_depth = calculate_max_nesting_depth(ast)
          method_length = analyze_method_lengths(ast)
          class_complexity = analyze_class_complexity(ast)
          
          # Identify complexity hotspots
          hotspots = identify_complexity_hotspots(%{
            functions: function_complexity,
            nesting: nesting_depth,
            methods: method_length,
            classes: class_complexity
          })
          
          # Generate simplification suggestions
          suggestions = generate_complexity_suggestions(hotspots)
          
          result = %{
            function_complexity: function_complexity,
            nesting_depth: nesting_depth,
            method_length: method_length,
            class_complexity: class_complexity,
            hotspots: hotspots,
            suggestions: suggestions,
            confidence: 0.82
          }
          
          {:ok, result}
          
        {:error, {line, error_desc, token}} ->
          {:error, "Syntax error at line #{line}: #{format_error(error_desc)} near '#{token}'"}
      end
    catch
      kind, reason ->
        Logger.error("QualityAnalyzer: Complexity analysis failed: #{kind} - #{inspect(reason)}")
        {:error, "Complexity analysis failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Analyzes code maintainability including design patterns and architectural issues.
  """
  def analyze_maintainability(code, practices, options \\ %{}) do
    Logger.debug("QualityAnalyzer: Analyzing maintainability")
    
    try do
      case Code.string_to_quoted(code) do
        {:ok, ast} ->
          # Analyze maintainability aspects
          design_patterns = detect_design_patterns(ast)
          code_smells = detect_maintainability_smells(ast)
          architectural_issues = assess_architectural_issues(ast, practices)
          
          # Calculate maintainability score
          maintainability_score = calculate_maintainability_score(%{
            patterns: length(design_patterns),
            smells: length(code_smells),
            architecture: length(architectural_issues)
          })
          
          # Identify improvement areas
          improvement_areas = identify_improvement_areas(code_smells, architectural_issues)
          
          result = %{
            design_patterns: design_patterns,
            code_smells: code_smells,
            architectural_issues: architectural_issues,
            maintainability_score: maintainability_score,
            improvement_areas: improvement_areas,
            confidence: 0.78
          }
          
          {:ok, result}
          
        {:error, {line, error_desc, token}} ->
          {:error, "Syntax error at line #{line}: #{format_error(error_desc)} near '#{token}'"}
      end
    catch
      kind, reason ->
        Logger.error("QualityAnalyzer: Maintainability analysis failed: #{kind} - #{inspect(reason)}")
        {:error, "Maintainability analysis failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Analyzes documentation coverage and quality.
  """
  def analyze_documentation(code, standards, options \\ %{}) do
    Logger.debug("QualityAnalyzer: Analyzing documentation")
    
    try do
      case Code.string_to_quoted(code) do
        {:ok, ast} ->
          # Analyze documentation aspects
          coverage_percentage = calculate_documentation_coverage(ast)
          missing_docs = identify_missing_documentation(ast)
          quality_score = assess_documentation_quality(ast)
          consistency_issues = check_documentation_consistency(ast, standards)
          
          # Generate documentation suggestions
          suggestions = generate_documentation_suggestions(missing_docs, consistency_issues)
          
          result = %{
            coverage_percentage: coverage_percentage,
            missing_docs: missing_docs,
            quality_score: quality_score,
            consistency_issues: consistency_issues,
            suggestions: suggestions,
            confidence: 0.75
          }
          
          {:ok, result}
          
        {:error, {line, error_desc, token}} ->
          {:error, "Syntax error at line #{line}: #{format_error(error_desc)} near '#{token}'"}
      end
    catch
      kind, reason ->
        Logger.error("QualityAnalyzer: Documentation analysis failed: #{kind} - #{inspect(reason)}")
        {:error, "Documentation analysis failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Checks code against best practices.
  """
  def check_best_practices(code, practices, practice_definitions, options \\ %{}) do
    Logger.debug("QualityAnalyzer: Checking best practices")
    
    try do
      case Code.string_to_quoted(code) do
        {:ok, ast} ->
          # Check each practice
          violations = []
          compliant = []
          
          {violations, compliant} = Enum.reduce(practices, {violations, compliant}, 
            fn practice, {v, c} ->
              practice_def = Map.get(practice_definitions, practice, %{})
              
              case check_single_practice(ast, practice, practice_def) do
                {:violation, violation_info} ->
                  {[violation_info | v], c}
                {:compliant, compliance_info} ->
                  {v, [compliance_info | c]}
              end
            end)
          
          # Calculate compliance score
          total_practices = length(practices)
          compliant_count = length(compliant)
          compliance_score = if total_practices > 0, do: compliant_count / total_practices, else: 1.0
          
          # Generate recommendations
          recommendations = generate_practice_recommendations(violations)
          
          result = %{
            violations: violations,
            compliant: compliant,
            compliance_score: compliance_score,
            recommendations: recommendations,
            confidence: 0.80
          }
          
          {:ok, result}
          
        {:error, {line, error_desc, token}} ->
          {:error, "Syntax error at line #{line}: #{format_error(error_desc)} near '#{token}'"}
      end
    catch
      kind, reason ->
        Logger.error("QualityAnalyzer: Best practices check failed: #{kind} - #{inspect(reason)}")
        {:error, "Best practices check failed: #{inspect(reason)}"}
    end
  end

  ## Private Functions - Metrics Calculation

  defp calculate_cyclomatic_complexity(ast) do
    # Count decision points that increase complexity
    {_ast, complexity} = Macro.prewalk(ast, 1, fn
      {:if, _, _} = node, acc -> {node, acc + 1}
      {:unless, _, _} = node, acc -> {node, acc + 1}
      {:case, _, _} = node, acc -> {node, acc + 1}
      {:cond, _, _} = node, acc -> {node, acc + 1}
      {:for, _, _} = node, acc -> {node, acc + 1}
      {:while, _, _} = node, acc -> {node, acc + 1}
      {:and, _, _} = node, acc -> {node, acc + 1}
      {:or, _, _} = node, acc -> {node, acc + 1}
      {:catch, _, _} = node, acc -> {node, acc + 1}
      node, acc -> {node, acc}
    end)
    
    complexity
  end

  defp calculate_cognitive_complexity(ast) do
    # Calculate cognitive complexity with nesting penalties
    {_ast, {complexity, _nesting}} = Macro.prewalk(ast, {0, 0}, fn
      {:if, _, _} = node, {acc, nesting} -> {node, {acc + 1 + nesting, nesting}}
      {:unless, _, _} = node, {acc, nesting} -> {node, {acc + 1 + nesting, nesting}}
      {:case, _, _} = node, {acc, nesting} -> {node, {acc + 1 + nesting, nesting + 1}}
      {:cond, _, _} = node, {acc, nesting} -> {node, {acc + 1 + nesting, nesting + 1}}
      {:for, _, _} = node, {acc, nesting} -> {node, {acc + 1 + nesting, nesting + 1}}
      {:while, _, _} = node, {acc, nesting} -> {node, {acc + 1 + nesting, nesting + 1}}
      {:and, _, _} = node, {acc, nesting} -> {node, {acc + 1, nesting}}
      {:or, _, _} = node, {acc, nesting} -> {node, {acc + 1, nesting}}
      node, acc -> {node, acc}
    end)
    
    complexity
  end

  defp calculate_maintainability_index(ast) do
    # Simplified maintainability index calculation
    cyclomatic = calculate_cyclomatic_complexity(ast)
    lines_of_code = count_lines_of_code(ast)
    
    # MI = 171 - 5.2 * ln(HV) - 0.23 * CC - 16.2 * ln(LOC)
    # Simplified version focusing on complexity and LOC
    base_index = 100
    complexity_penalty = cyclomatic * 2
    size_penalty = :math.log(max(1, lines_of_code)) * 5
    
    max(0, base_index - complexity_penalty - size_penalty)
  end

  defp assess_technical_debt(ast, standards) do
    # Identify areas contributing to technical debt
    debt_items = []
    
    # Check complexity violations
    complexity = calculate_cyclomatic_complexity(ast)
    complexity_standard = get_standard_value(standards, "cyclomatic_complexity", :max_value, 10)
    
    debt_items = if complexity > complexity_standard do
      [%{type: "complexity", severity: "high", description: "High cyclomatic complexity"} | debt_items]
    else
      debt_items
    end
    
    # Check method length violations
    method_lengths = analyze_method_lengths(ast)
    long_methods = Enum.filter(method_lengths, fn {_name, length} -> length > 30 end)
    
    debt_items = if length(long_methods) > 0 do
      [%{type: "method_length", severity: "medium", description: "Long methods detected"} | debt_items]
    else
      debt_items
    end
    
    # Check duplication (simplified)
    duplication_score = estimate_code_duplication(ast)
    
    debt_items = if duplication_score > 0.3 do
      [%{type: "duplication", severity: "medium", description: "Code duplication detected"} | debt_items]
    else
      debt_items
    end
    
    debt_items
  end

  defp detect_code_smells(ast) do
    smells = []
    
    # Long method smell
    method_lengths = analyze_method_lengths(ast)
    long_methods = Enum.filter(method_lengths, fn {_name, length} -> length > 25 end)
    
    smells = if length(long_methods) > 0 do
      [%{type: "long_method", locations: Enum.map(long_methods, &elem(&1, 0))} | smells]
    else
      smells
    end
    
    # Large class smell (simplified)
    class_sizes = analyze_class_sizes(ast)
    large_classes = Enum.filter(class_sizes, fn {_name, size} -> size > 200 end)
    
    smells = if length(large_classes) > 0 do
      [%{type: "large_class", locations: Enum.map(large_classes, &elem(&1, 0))} | smells]
    else
      smells
    end
    
    # Duplicate code smell
    duplication_score = estimate_code_duplication(ast)
    
    smells = if duplication_score > 0.2 do
      [%{type: "duplicate_code", severity: duplication_score} | smells]
    else
      smells
    end
    
    smells
  end

  defp calculate_quality_score(metrics) do
    # Calculate weighted quality score
    complexity_score = max(0, 1.0 - (metrics.cyclomatic / 20.0))
    cognitive_score = max(0, 1.0 - (metrics.cognitive / 30.0))
    maintainability_score = metrics.maintainability / 100.0
    debt_score = max(0, 1.0 - (length(metrics.debt) / 10.0))
    smell_score = max(0, 1.0 - (metrics.smells / 5.0))
    
    # Weighted average
    weights = %{
      complexity: 0.25,
      cognitive: 0.20,
      maintainability: 0.25,
      debt: 0.15,
      smell: 0.15
    }
    
    (complexity_score * weights.complexity +
     cognitive_score * weights.cognitive +
     maintainability_score * weights.maintainability +
     debt_score * weights.debt +
     smell_score * weights.smell)
  end

  ## Private Functions - Style Analysis

  defp check_formatting_issues(code, standards) do
    issues = []
    
    # Check line length (simplified)
    lines = String.split(code, "\n")
    long_lines = lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _num} -> String.length(line) > 120 end)
    |> Enum.map(fn {_line, num} -> %{type: "line_length", line: num} end)
    
    issues = issues ++ long_lines
    
    # Check indentation consistency (simplified)
    indentation_issues = check_indentation_consistency(lines)
    issues = issues ++ indentation_issues
    
    # Check trailing whitespace
    trailing_whitespace = lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _num} -> String.match?(line, ~r/\s+$/) end)
    |> Enum.map(fn {_line, num} -> %{type: "trailing_whitespace", line: num} end)
    
    issues ++ trailing_whitespace
  end

  defp check_naming_conventions(ast, standards) do
    violations = []
    
    # Check function naming (simplified)
    {_ast, function_violations} = Macro.prewalk(ast, [], fn
      {:def, _, [{name, _, _} | _]} = node, acc when is_atom(name) ->
        violation = if not valid_function_name?(name) do
          %{type: "function_naming", name: name, suggestion: "Use snake_case"}
        else
          nil
        end
        {node, if(violation, do: [violation | acc], else: acc)}
      
      {:defp, _, [{name, _, _} | _]} = node, acc when is_atom(name) ->
        violation = if not valid_function_name?(name) do
          %{type: "private_function_naming", name: name, suggestion: "Use snake_case"}
        else
          nil
        end
        {node, if(violation, do: [violation | acc], else: acc)}
      
      node, acc -> {node, acc}
    end)
    
    violations ++ function_violations
  end

  defp check_documentation_requirements(ast, standards) do
    gaps = []
    
    # Check for missing module docs
    has_moduledoc = has_module_documentation?(ast)
    gaps = if not has_moduledoc do
      [%{type: "missing_moduledoc", severity: "high"} | gaps]
    else
      gaps
    end
    
    # Check for missing function docs
    function_doc_gaps = find_undocumented_functions(ast)
    gaps ++ function_doc_gaps
  end

  defp calculate_style_score(style_metrics) do
    # Calculate style score based on violations
    formatting_penalty = min(0.4, style_metrics.formatting * 0.02)
    naming_penalty = min(0.3, style_metrics.naming * 0.05)
    documentation_penalty = min(0.3, style_metrics.documentation * 0.03)
    
    max(0.0, 1.0 - formatting_penalty - naming_penalty - documentation_penalty)
  end

  defp generate_style_recommendations(formatting_issues, naming_violations, documentation_gaps) do
    recommendations = []
    
    recommendations = if length(formatting_issues) > 0 do
      [%{priority: "medium", action: "Fix formatting issues", count: length(formatting_issues)} | recommendations]
    else
      recommendations
    end
    
    recommendations = if length(naming_violations) > 0 do
      [%{priority: "high", action: "Fix naming convention violations", count: length(naming_violations)} | recommendations]
    else
      recommendations
    end
    
    recommendations = if length(documentation_gaps) > 0 do
      [%{priority: "medium", action: "Add missing documentation", count: length(documentation_gaps)} | recommendations]
    else
      recommendations
    end
    
    recommendations
  end

  ## Private Functions - Complexity Analysis

  defp analyze_function_complexity(ast) do
    # Analyze complexity of each function
    {_ast, complexities} = Macro.prewalk(ast, [], fn
      {:def, _, [{name, _, _} | _]} = node, acc when is_atom(name) ->
        complexity = calculate_function_specific_complexity(node)
        {node, [{name, complexity} | acc]}
      
      {:defp, _, [{name, _, _} | _]} = node, acc when is_atom(name) ->
        complexity = calculate_function_specific_complexity(node)
        {node, [{name, complexity} | acc]}
      
      node, acc -> {node, acc}
    end)
    
    complexities
  end

  defp calculate_max_nesting_depth(ast) do
    # Calculate maximum nesting depth
    {_ast, max_depth} = Macro.prewalk(ast, 0, fn
      {:if, _, _} = node, depth -> {node, max(depth + 1, depth)}
      {:unless, _, _} = node, depth -> {node, max(depth + 1, depth)}
      {:case, _, _} = node, depth -> {node, max(depth + 1, depth)}
      {:cond, _, _} = node, depth -> {node, max(depth + 1, depth)}
      {:for, _, _} = node, depth -> {node, max(depth + 1, depth)}
      {:while, _, _} = node, depth -> {node, max(depth + 1, depth)}
      node, depth -> {node, depth}
    end)
    
    max_depth
  end

  defp analyze_method_lengths(ast) do
    # Count lines in each method
    {_ast, lengths} = Macro.prewalk(ast, [], fn
      {:def, _, [{name, _, _}, [do: body]]} = node, acc when is_atom(name) ->
        length = count_ast_nodes(body)
        {node, [{name, length} | acc]}
      
      {:defp, _, [{name, _, _}, [do: body]]} = node, acc when is_atom(name) ->
        length = count_ast_nodes(body)
        {node, [{name, length} | acc]}
      
      node, acc -> {node, acc}
    end)
    
    lengths
  end

  defp analyze_class_complexity(ast) do
    # Analyze module/class complexity (simplified for Elixir modules)
    {_ast, complexities} = Macro.prewalk(ast, [], fn
      {:defmodule, _, [{:__aliases__, _, module_path}, [do: body]]} = node, acc ->
        complexity = calculate_module_complexity(body)
        module_name = Enum.join(module_path, ".")
        {node, [{module_name, complexity} | acc]}
      
      node, acc -> {node, acc}
    end)
    
    complexities
  end

  defp identify_complexity_hotspots(complexity_data) do
    hotspots = []
    
    # Function complexity hotspots
    high_complexity_functions = complexity_data.functions
    |> Enum.filter(fn {_name, complexity} -> complexity > 10 end)
    |> Enum.map(fn {name, complexity} -> 
      %{type: "function", name: name, complexity: complexity, severity: "high"}
    end)
    
    hotspots = hotspots ++ high_complexity_functions
    
    # Deep nesting hotspots
    hotspots = if complexity_data.nesting > 4 do
      [%{type: "nesting", depth: complexity_data.nesting, severity: "medium"} | hotspots]
    else
      hotspots
    end
    
    # Long method hotspots
    long_methods = complexity_data.methods
    |> Enum.filter(fn {_name, length} -> length > 25 end)
    |> Enum.map(fn {name, length} -> 
      %{type: "method_length", name: name, length: length, severity: "medium"}
    end)
    
    hotspots ++ long_methods
  end

  defp generate_complexity_suggestions(hotspots) do
    hotspots
    |> Enum.map(fn hotspot ->
      case hotspot.type do
        "function" ->
          %{
            action: "Refactor function to reduce complexity",
            target: hotspot.name,
            priority: "high",
            technique: "extract_method"
          }
        
        "nesting" ->
          %{
            action: "Reduce nesting depth",
            priority: "medium",
            technique: "early_return"
          }
        
        "method_length" ->
          %{
            action: "Break down long method",
            target: hotspot.name,
            priority: "medium",
            technique: "extract_method"
          }
        
        _ ->
          %{
            action: "Review and refactor",
            priority: "low"
          }
      end
    end)
  end

  ## Private Functions - Maintainability Analysis

  defp detect_design_patterns(ast) do
    patterns = []
    
    # Detect common Elixir patterns
    patterns = if has_genserver_pattern?(ast) do
      [%{pattern: "genserver", confidence: 0.9} | patterns]
    else
      patterns
    end
    
    patterns = if has_supervisor_pattern?(ast) do
      [%{pattern: "supervisor", confidence: 0.8} | patterns]
    else
      patterns
    end
    
    patterns = if has_pipeline_pattern?(ast) do
      [%{pattern: "pipeline", confidence: 0.7} | patterns]
    else
      patterns
    end
    
    patterns
  end

  defp detect_maintainability_smells(ast) do
    smells = []
    
    # God module smell
    module_size = count_ast_nodes(ast)
    smells = if module_size > 500 do
      [%{type: "god_module", severity: "high", size: module_size} | smells]
    else
      smells
    end
    
    # Feature envy (simplified)
    external_calls = count_external_calls(ast)
    smells = if external_calls > 10 do
      [%{type: "feature_envy", severity: "medium", calls: external_calls} | smells]
    else
      smells
    end
    
    smells
  end

  defp assess_architectural_issues(ast, practices) do
    issues = []
    
    # Check for single responsibility violations
    if has_multiple_responsibilities?(ast) do
      issues = [%{type: "srp_violation", severity: "high", description: "Module has multiple responsibilities"} | issues]
    end
    
    # Check for tight coupling
    coupling_score = assess_coupling(ast)
    issues = if coupling_score > 0.7 do
      [%{type: "tight_coupling", severity: "medium", score: coupling_score} | issues]
    else
      issues
    end
    
    issues
  end

  defp calculate_maintainability_score(maintainability_data) do
    # Calculate maintainability score
    pattern_bonus = maintainability_data.patterns * 0.1
    smell_penalty = maintainability_data.smells * 0.15
    architecture_penalty = maintainability_data.architecture * 0.2
    
    base_score = 0.8
    final_score = base_score + pattern_bonus - smell_penalty - architecture_penalty
    
    max(0.0, min(1.0, final_score))
  end

  defp identify_improvement_areas(code_smells, architectural_issues) do
    areas = []
    
    # Group issues by type
    smell_types = Enum.group_by(code_smells, & &1.type)
    issue_types = Enum.group_by(architectural_issues, & &1.type)
    
    # Identify top improvement areas
    areas = if Map.has_key?(smell_types, "god_module") do
      [%{area: "module_decomposition", priority: "high", impact: "high"} | areas]
    else
      areas
    end
    
    areas = if Map.has_key?(issue_types, "tight_coupling") do
      [%{area: "decoupling", priority: "medium", impact: "medium"} | areas]
    else
      areas
    end
    
    areas
  end

  ## Private Functions - Documentation Analysis

  defp calculate_documentation_coverage(ast) do
    # Calculate documentation coverage percentage
    total_functions = count_public_functions(ast)
    documented_functions = count_documented_functions(ast)
    
    if total_functions > 0 do
      (documented_functions / total_functions) * 100
    else
      100.0
    end
  end

  defp identify_missing_documentation(ast) do
    # Find functions without documentation
    {_ast, missing} = Macro.prewalk(ast, [], fn
      {:def, _, [{name, _, _} | _]} = node, acc when is_atom(name) ->
        if has_function_doc?(node) do
          {node, acc}
        else
          {node, [%{type: "missing_function_doc", name: name} | acc]}
        end
      
      node, acc -> {node, acc}
    end)
    
    missing
  end

  defp assess_documentation_quality(ast) do
    # Assess quality of existing documentation (simplified)
    doc_nodes = extract_documentation_nodes(ast)
    
    if length(doc_nodes) == 0 do
      0.0
    else
      # Simple quality metrics
      avg_length = doc_nodes
      |> Enum.map(&String.length/1)
      |> Enum.sum()
      |> Kernel./(length(doc_nodes))
      
      # Quality score based on average length and presence
      min(1.0, avg_length / 100.0)
    end
  end

  defp check_documentation_consistency(ast, standards) do
    # Check for consistency issues in documentation
    issues = []
    
    # Check for consistent formatting (simplified)
    doc_nodes = extract_documentation_nodes(ast)
    inconsistent_formatting = Enum.filter(doc_nodes, fn doc ->
      not consistent_doc_format?(doc)
    end)
    
    issues = if length(inconsistent_formatting) > 0 do
      [%{type: "inconsistent_formatting", count: length(inconsistent_formatting)} | issues]
    else
      issues
    end
    
    issues
  end

  defp generate_documentation_suggestions(missing_docs, consistency_issues) do
    suggestions = []
    
    suggestions = if length(missing_docs) > 0 do
      [%{
        priority: "medium",
        action: "Add missing function documentation",
        count: length(missing_docs),
        functions: Enum.map(missing_docs, & &1.name)
      } | suggestions]
    else
      suggestions
    end
    
    suggestions = if length(consistency_issues) > 0 do
      [%{
        priority: "low",
        action: "Fix documentation formatting consistency",
        count: length(consistency_issues)
      } | suggestions]
    else
      suggestions
    end
    
    suggestions
  end

  ## Private Functions - Best Practices

  defp check_single_practice(ast, practice, practice_def) do
    case practice do
      "single_responsibility" ->
        if has_multiple_responsibilities?(ast) do
          {:violation, %{practice: practice, type: "srp_violation"}}
        else
          {:compliant, %{practice: practice, type: "srp_compliant"}}
        end
      
      "dry_principle" ->
        duplication_score = estimate_code_duplication(ast)
        if duplication_score > 0.3 do
          {:violation, %{practice: practice, type: "duplication", score: duplication_score}}
        else
          {:compliant, %{practice: practice, type: "dry_compliant"}}
        end
      
      "meaningful_names" ->
        naming_issues = count_poor_naming(ast)
        if naming_issues > 0 do
          {:violation, %{practice: practice, type: "poor_naming", count: naming_issues}}
        else
          {:compliant, %{practice: practice, type: "good_naming"}}
        end
      
      _ ->
        {:compliant, %{practice: practice, type: "generic_compliant"}}
    end
  end

  defp generate_practice_recommendations(violations) do
    violations
    |> Enum.map(fn violation ->
      case violation.type do
        "srp_violation" ->
          %{
            practice: violation.practice,
            action: "Split module into smaller, focused modules",
            priority: "high"
          }
        
        "duplication" ->
          %{
            practice: violation.practice,
            action: "Extract common code into shared functions",
            priority: "medium"
          }
        
        "poor_naming" ->
          %{
            practice: violation.practice,
            action: "Improve variable and function names for clarity",
            priority: "medium"
          }
        
        _ ->
          %{
            practice: violation.practice,
            action: "Review and improve code quality",
            priority: "low"
          }
      end
    end)
  end

  ## Private Functions - Helper Functions

  defp count_lines_of_code(ast) do
    # Count significant lines of code (simplified)
    ast_string = Macro.to_string(ast)
    lines = String.split(ast_string, "\n")
    
    lines
    |> Enum.filter(fn line ->
      trimmed = String.trim(line)
      trimmed != "" and not String.starts_with?(trimmed, "#")
    end)
    |> length()
  end

  defp count_ast_nodes(ast) do
    # Count AST nodes as a proxy for complexity
    {_ast, count} = Macro.prewalk(ast, 0, fn node, acc -> {node, acc + 1} end)
    count
  end

  defp calculate_function_specific_complexity(function_ast) do
    # Calculate complexity for a specific function
    calculate_cyclomatic_complexity(function_ast)
  end

  defp calculate_module_complexity(module_body) do
    # Calculate complexity of entire module
    calculate_cyclomatic_complexity(module_body)
  end

  defp analyze_class_sizes(ast) do
    # Analyze sizes of classes/modules
    {_ast, sizes} = Macro.prewalk(ast, [], fn
      {:defmodule, _, [{:__aliases__, _, module_path}, [do: body]]} = node, acc ->
        size = count_ast_nodes(body)
        module_name = Enum.join(module_path, ".")
        {node, [{module_name, size} | acc]}
      
      node, acc -> {node, acc}
    end)
    
    sizes
  end

  defp estimate_code_duplication(ast) do
    # Estimate code duplication (simplified)
    # This is a placeholder - real implementation would use more sophisticated analysis
    ast_string = Macro.to_string(ast)
    lines = String.split(ast_string, "\n")
    unique_lines = Enum.uniq(lines)
    
    if length(lines) > 0 do
      1.0 - (length(unique_lines) / length(lines))
    else
      0.0
    end
  end

  defp get_standard_value(standards, standard_name, key, default) do
    case Map.get(standards, standard_name) do
      %{definition: definition} -> Map.get(definition, key, default)
      _ -> default
    end
  end

  defp check_indentation_consistency(lines) do
    # Check for consistent indentation (simplified)
    inconsistent_lines = lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _num} ->
      # Simple check: lines starting with tabs vs spaces
      String.starts_with?(line, "\t") and String.contains?(line, "  ")
    end)
    |> Enum.map(fn {_line, num} -> %{type: "mixed_indentation", line: num} end)
    
    inconsistent_lines
  end

  defp valid_function_name?(name) do
    # Check if function name follows snake_case convention
    name_str = Atom.to_string(name)
    Regex.match?(~r/^[a-z][a-z0-9_]*[a-z0-9]?$/, name_str)
  end

  defp has_module_documentation?(ast) do
    # Check if module has @moduledoc
    {_ast, has_doc} = Macro.prewalk(ast, false, fn
      {:@, _, [{:moduledoc, _, _}]} = node, _acc -> {node, true}
      node, acc -> {node, acc}
    end)
    
    has_doc
  end

  defp find_undocumented_functions(ast) do
    # Find public functions without @doc
    {_ast, undocumented} = Macro.prewalk(ast, [], fn
      {:def, _, [{name, _, _} | _]} = node, acc when is_atom(name) ->
        if has_function_doc?(node) do
          {node, acc}
        else
          {node, [%{type: "missing_function_doc", name: name} | acc]}
        end
      
      node, acc -> {node, acc}
    end)
    
    undocumented
  end

  defp has_function_doc?(_function_ast) do
    # Simplified check for function documentation
    # In a real implementation, this would check for @doc attributes
    false
  end

  defp has_genserver_pattern?(ast) do
    # Check if code follows GenServer pattern
    {_ast, has_pattern} = Macro.prewalk(ast, false, fn
      {:use, _, [{:__aliases__, _, [:GenServer]}]} = node, _acc -> {node, true}
      node, acc -> {node, acc}
    end)
    
    has_pattern
  end

  defp has_supervisor_pattern?(ast) do
    # Check if code follows Supervisor pattern
    {_ast, has_pattern} = Macro.prewalk(ast, false, fn
      {:use, _, [{:__aliases__, _, [:Supervisor]}]} = node, _acc -> {node, true}
      node, acc -> {node, acc}
    end)
    
    has_pattern
  end

  defp has_pipeline_pattern?(ast) do
    # Check for pipeline operator usage
    {_ast, has_pattern} = Macro.prewalk(ast, false, fn
      {:|>, _, _} = node, _acc -> {node, true}
      node, acc -> {node, acc}
    end)
    
    has_pattern
  end

  defp count_external_calls(ast) do
    # Count calls to external modules (simplified)
    {_ast, count} = Macro.prewalk(ast, 0, fn
      {{:., _, [{:__aliases__, _, _module}, _function]}, _, _} = node, acc -> {node, acc + 1}
      node, acc -> {node, acc}
    end)
    
    count
  end

  defp has_multiple_responsibilities?(ast) do
    # Check if module has multiple responsibilities (simplified)
    function_count = count_public_functions(ast)
    function_count > 10  # Arbitrary threshold
  end

  defp assess_coupling(ast) do
    # Assess coupling level (simplified)
    external_calls = count_external_calls(ast)
    total_calls = count_all_function_calls(ast)
    
    if total_calls > 0 do
      external_calls / total_calls
    else
      0.0
    end
  end

  defp count_public_functions(ast) do
    # Count public functions
    {_ast, count} = Macro.prewalk(ast, 0, fn
      {:def, _, [{_name, _, _} | _]} = node, acc -> {node, acc + 1}
      node, acc -> {node, acc}
    end)
    
    count
  end

  defp count_documented_functions(ast) do
    # Count functions with documentation
    {_ast, count} = Macro.prewalk(ast, 0, fn
      {:def, _, [{_name, _, _} | _]} = node, acc ->
        if has_function_doc?(node) do
          {node, acc + 1}
        else
          {node, acc}
        end
      
      node, acc -> {node, acc}
    end)
    
    count
  end

  defp extract_documentation_nodes(ast) do
    # Extract documentation strings
    {_ast, docs} = Macro.prewalk(ast, [], fn
      {:@, _, [{:moduledoc, _, [doc]}]} = node, acc when is_binary(doc) -> {node, [doc | acc]}
      {:@, _, [{:doc, _, [doc]}]} = node, acc when is_binary(doc) -> {node, [doc | acc]}
      node, acc -> {node, acc}
    end)
    
    docs
  end

  defp consistent_doc_format?(doc) when is_binary(doc) do
    # Check if documentation follows consistent format (simplified)
    String.length(doc) > 10 and String.ends_with?(doc, ".")
  end

  defp consistent_doc_format?(_), do: false

  defp count_poor_naming(ast) do
    # Count poorly named variables and functions
    {_ast, count} = Macro.prewalk(ast, 0, fn
      {:def, _, [{name, _, _} | _]} = node, acc when is_atom(name) ->
        if poor_name?(name) do
          {node, acc + 1}
        else
          {node, acc}
        end
      
      {name, _, _} = node, acc when is_atom(name) ->
        if poor_name?(name) do
          {node, acc + 1}
        else
          {node, acc}
        end
      
      node, acc -> {node, acc}
    end)
    
    count
  end

  defp poor_name?(name) when is_atom(name) do
    name_str = Atom.to_string(name)
    # Check for poor naming patterns
    String.length(name_str) < 3 or 
    Regex.match?(~r/^[a-z]$/, name_str) or  # Single letter variables
    Regex.match?(~r/^(data|info|temp|tmp)$/, name_str)  # Generic names
  end

  defp count_all_function_calls(ast) do
    # Count all function calls
    {_ast, count} = Macro.prewalk(ast, 0, fn
      {function, _, args} = node, acc when is_atom(function) and is_list(args) -> {node, acc + 1}
      node, acc -> {node, acc}
    end)
    
    count
  end

  defp format_error(error_desc) when is_binary(error_desc), do: error_desc
  defp format_error(error_desc), do: inspect(error_desc)
end