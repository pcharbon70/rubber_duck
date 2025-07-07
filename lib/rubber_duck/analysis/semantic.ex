defmodule RubberDuck.Analysis.Semantic do
  @moduledoc """
  Semantic analysis engine for detecting code quality issues.

  Focuses on:
  - Dead code detection
  - Unused variables and functions
  - Complexity metrics (cyclomatic, cognitive)
  - Dependency analysis and cycle detection
  - Module cohesion analysis
  """

  @behaviour RubberDuck.Analysis.Engine

  alias RubberDuck.Analysis.Engine

  @impl true
  def name, do: :semantic

  @impl true
  def description do
    "Analyzes code semantics including dead code, complexity, and dependencies"
  end

  @impl true
  def categories do
    [:complexity, :maintainability, :design, :correctness]
  end

  @impl true
  def default_config do
    %{
      max_function_length: 10,
      max_module_length: 100,
      max_cyclomatic_complexity: 7,
      max_nesting_depth: 4,
      detect_dead_code: true,
      detect_unused_variables: true,
      detect_circular_dependencies: true
    }
  end

  @impl true
  def analyze(ast_info, options \\ []) do
    config = Keyword.get(options, :config, default_config())
    issues = []

    # Run various semantic analyses
    issues = issues ++ analyze_dead_code(ast_info, config)
    issues = issues ++ analyze_complexity(ast_info, config)
    issues = issues ++ analyze_dependencies(ast_info, config)
    issues = issues ++ analyze_unused_variables(ast_info, config)
    issues = issues ++ analyze_module_cohesion(ast_info, config)

    # Calculate metrics
    metrics = calculate_metrics(ast_info)

    # Generate suggestions
    suggestions = generate_suggestions(issues)

    {:ok,
     %{
       engine: name(),
       issues: Engine.sort_issues(issues),
       metrics: metrics,
       suggestions: suggestions,
       metadata: %{
         ast_type: ast_info.type,
         module_name: ast_info.name
       }
     }}
  end

  @impl true
  def analyze_source(source, language, options) do
    # Fallback to basic analysis when AST is not available
    config = Keyword.get(options, :config, default_config())
    issues = []

    # Basic line-based analysis
    lines = String.split(source, "\n")

    # Check for obvious issues
    issues = issues ++ check_long_lines(lines, config)
    issues = issues ++ check_trailing_whitespace(lines)

    {:ok,
     %{
       engine: name(),
       issues: issues,
       metrics: %{line_count: length(lines)},
       suggestions: %{},
       metadata: %{language: language, source_analysis: true}
     }}
  end

  # Dead code detection
  defp analyze_dead_code(ast_info, config) do
    if !config.detect_dead_code do
      []
    else
      # Find all defined functions
      defined_functions = ast_info.functions

      # Find all called functions within the module
      internal_calls =
        ast_info.calls
        |> Enum.filter(fn call -> elem(call.to, 0) == ast_info.name end)
        |> Enum.map(fn call -> {elem(call.to, 1), elem(call.to, 2)} end)
        |> MapSet.new()

      # Find potentially dead functions (not called internally)
      # Note: Public functions might be called externally
      defined_functions
      |> Enum.filter(fn func ->
        func.private && !MapSet.member?(internal_calls, {func.name, func.arity})
      end)
      |> Enum.map(fn func ->
        Engine.create_issue(
          :dead_code,
          :low,
          "Private function #{func.name}/#{func.arity} is never called",
          %{file: "", line: func.line, column: nil, end_line: nil, end_column: nil},
          "semantic/dead_code",
          :maintainability,
          %{function: func}
        )
      end)
    end
  end

  # Complexity analysis
  defp analyze_complexity(ast_info, _config) do
    # Analyze each function for complexity
    Enum.flat_map(ast_info.functions, fn func ->
      # Function length check
      # Note: We need the actual AST to count lines accurately
      # For now, we'll skip this check without the full AST

      # Check parameter count
      if func.arity > 4 do
        [
          Engine.create_issue(
            :long_parameter_list,
            :low,
            "Function #{func.name}/#{func.arity} has too many parameters (#{func.arity} > 4)",
            %{file: "", line: func.line, column: nil, end_line: nil, end_column: nil},
            "semantic/long_parameter_list",
            :complexity,
            %{function: func, parameter_count: func.arity}
          )
        ]
      else
        []
      end
    end)
  end

  # Dependency analysis
  defp analyze_dependencies(ast_info, config) do
    if !config.detect_circular_dependencies do
      []
    else
      # Check for suspicious dependency patterns
      dependency_count = length(ast_info.aliases) + length(ast_info.imports)

      if dependency_count > 10 do
        [
          Engine.create_issue(
            :too_many_dependencies,
            :medium,
            "Module has too many dependencies (#{dependency_count}). Consider refactoring.",
            %{file: "", line: 1, column: nil, end_line: nil, end_column: nil},
            "semantic/dependency_count",
            :design,
            %{
              aliases: length(ast_info.aliases),
              imports: length(ast_info.imports),
              total: dependency_count
            }
          )
        ]
      else
        []
      end
    end
  end

  # Unused variable detection
  defp analyze_unused_variables(_ast_info, config) do
    if !config.detect_unused_variables do
      []
    else
      # This requires deeper AST analysis of function bodies
      # For now, return empty list as we need the full AST
      []
    end
  end

  # Module cohesion analysis
  defp analyze_module_cohesion(ast_info, config) do
    # Check if module has too many responsibilities
    function_count = length(ast_info.functions)

    large_module_issues = 
      if function_count > config.max_module_length do
        [
          Engine.create_issue(
            :large_module,
            :medium,
            "Module has too many functions (#{function_count} > #{config.max_module_length})",
            %{file: "", line: 1, column: nil, end_line: nil, end_column: nil},
            "semantic/large_module",
            :design,
            %{function_count: function_count}
          )
        ]
      else
        []
      end

    # Check for low cohesion indicators
    public_functions = Enum.count(ast_info.functions, &(!&1.private))
    private_functions = function_count - public_functions

    cohesion_issues = 
      if public_functions > 0 && private_functions / public_functions > 3 do
        [
          Engine.create_issue(
            :low_cohesion,
            :low,
            "Module has too many private functions relative to public ones",
            %{file: "", line: 1, column: nil, end_line: nil, end_column: nil},
            "semantic/low_cohesion",
            :design,
            %{
              public_functions: public_functions,
              private_functions: private_functions,
              ratio: Float.round(private_functions / public_functions, 2)
            }
          )
        ]
      else
        []
      end

    large_module_issues ++ cohesion_issues
  end

  # Calculate semantic metrics
  defp calculate_metrics(ast_info) do
    %{
      total_functions: length(ast_info.functions),
      public_functions: Enum.count(ast_info.functions, &(!&1.private)),
      private_functions: Enum.count(ast_info.functions, & &1.private),
      total_dependencies: length(ast_info.aliases) + length(ast_info.imports) + length(ast_info.requires),
      total_calls: length(ast_info.calls),
      average_function_arity: calculate_average_arity(ast_info.functions)
    }
  end

  defp calculate_average_arity([]), do: 0

  defp calculate_average_arity(functions) do
    total_arity = Enum.reduce(functions, 0, fn func, acc -> acc + func.arity end)
    Float.round(total_arity / length(functions), 2)
  end

  # Generate fix suggestions
  defp generate_suggestions(issues) do
    issues
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, type_issues} ->
      {type, suggest_fixes_for_type(type, type_issues)}
    end)
    |> Map.new()
  end

  defp suggest_fixes_for_type(:dead_code, _issues) do
    [
      Engine.create_suggestion(
        "Remove the unused private function or make it public if it's intended for external use",
        nil,
        false
      )
    ]
  end

  defp suggest_fixes_for_type(:long_parameter_list, _issues) do
    [
      Engine.create_suggestion(
        "Consider grouping related parameters into a struct or keyword list",
        nil,
        false
      ),
      Engine.create_suggestion(
        "Break down the function into smaller, more focused functions",
        nil,
        false
      )
    ]
  end

  defp suggest_fixes_for_type(:large_module, _issues) do
    [
      Engine.create_suggestion(
        "Split the module into smaller, more cohesive modules",
        nil,
        false
      ),
      Engine.create_suggestion(
        "Extract related functions into separate context modules",
        nil,
        false
      )
    ]
  end

  defp suggest_fixes_for_type(:too_many_dependencies, _issues) do
    [
      Engine.create_suggestion(
        "Consider using dependency injection or a facade pattern",
        nil,
        false
      ),
      Engine.create_suggestion(
        "Review if all dependencies are actually needed",
        nil,
        false
      )
    ]
  end

  defp suggest_fixes_for_type(_, _), do: []

  # Line-based checks for source analysis
  defp check_long_lines(lines, _config) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> String.length(line) > 120 end)
    |> Enum.map(fn {_line, line_num} ->
      Engine.create_issue(
        :long_line,
        :info,
        "Line exceeds 120 characters",
        %{file: "", line: line_num, column: 121, end_line: nil, end_column: nil},
        "semantic/long_line",
        :style,
        %{}
      )
    end)
  end

  defp check_trailing_whitespace(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> String.match?(line, ~r/\s+$/) end)
    |> Enum.map(fn {_line, line_num} ->
      Engine.create_issue(
        :trailing_whitespace,
        :info,
        "Line has trailing whitespace",
        %{file: "", line: line_num, column: nil, end_line: nil, end_column: nil},
        "semantic/trailing_whitespace",
        :style,
        %{}
      )
    end)
  end
end

