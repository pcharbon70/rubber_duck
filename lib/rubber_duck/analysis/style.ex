defmodule RubberDuck.Analysis.Style do
  @moduledoc """
  Style analysis engine for detecting code style issues and Elixir-specific code smells.

  Focuses on:
  - Elixir-specific code smells (based on research)
  - Naming convention violations
  - Formatting issues
  - Best practice violations
  - Function and module organization
  """

  @behaviour RubberDuck.Analysis.Engine

  alias RubberDuck.Analysis.{Common, Engine}

  @impl true
  def name, do: :style

  @impl true
  def description do
    "Analyzes code style, naming conventions, and Elixir-specific code smells"
  end

  @impl true
  def categories do
    [:style, :maintainability, :design]
  end

  @impl true
  def default_config do
    %{
      check_naming_conventions: true,
      check_code_smells: true,
      check_formatting: true,
      max_line_length: 120,
      max_function_name_length: 30,
      detect_primitive_obsession: true,
      detect_complex_branching: true,
      detect_unnecessary_macros: true,
      max_imports: 10,
      enforce_import_order: true,
      detect_unused_imports: true,
      max_function_arity: 5,
      max_variables_per_function: 10
    }
  end

  @impl true
  def analyze(ast_info, options \\ []) do
    config = Keyword.get(options, :config, default_config())
    issues = []

    # Run various style analyses
    issues =
      issues
      |> Enum.concat(analyze_naming_conventions(ast_info, config))
      |> Enum.concat(analyze_elixir_code_smells(ast_info, config))
      |> Enum.concat(analyze_function_organization(ast_info, config))
      |> Enum.concat(analyze_module_structure(ast_info, config))
      |> Enum.concat(analyze_import_organization(ast_info, config))
      |> Enum.concat(analyze_function_complexity(ast_info, config))

    # Calculate metrics
    metrics = calculate_style_metrics(ast_info)

    # Generate suggestions
    suggestions = generate_style_suggestions(issues)

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
    config = Keyword.get(options, :config, default_config())
    issues = []

    # Line-based style analysis
    lines = String.split(source, "\n")

    issues =
      issues
      |> Enum.concat(check_line_length(lines, config))
      |> Enum.concat(check_todo_comments(lines))
      |> Enum.concat(check_commented_code(lines))

    {:ok,
     %{
       engine: name(),
       issues: issues,
       metrics: %{line_count: length(lines)},
       suggestions: %{},
       metadata: %{language: language, source_analysis: true}
     }}
  end

  # Naming convention analysis
  defp analyze_naming_conventions(ast_info, config) do
    if config.check_naming_conventions do
      # Check module naming
      module_issues =
        if ast_info.name && !Common.valid_module_name?(ast_info.name) do
          [
            Engine.create_issue(
              :invalid_module_name,
              :medium,
              "Module name '#{ast_info.name}' does not follow Elixir naming conventions",
              %{file: "", line: 1, column: nil, end_line: nil, end_column: nil},
              "style/invalid_module_name",
              :style,
              %{module_name: ast_info.name}
            )
          ]
        else
          []
        end

      # Check function naming
      function_issues =
        Enum.flat_map(ast_info.functions, fn func ->
          name_issues =
            if Common.valid_function_name?(func.name) do
              []
            else
              [
                Engine.create_issue(
                  :invalid_function_name,
                  :low,
                  "Function name '#{func.name}' does not follow snake_case convention",
                  %{file: "", line: func.line, column: nil, end_line: nil, end_column: nil},
                  "style/invalid_function_name",
                  :style,
                  %{function_name: func.name}
                )
              ]
            end

          length_issues =
            if String.length(Atom.to_string(func.name)) > config.max_function_name_length do
              [
                Engine.create_issue(
                  :long_function_name,
                  :info,
                  "Function name '#{func.name}' is too long",
                  %{file: "", line: func.line, column: nil, end_line: nil, end_column: nil},
                  "style/long_function_name",
                  :style,
                  %{function_name: func.name, length: String.length(Atom.to_string(func.name))}
                )
              ]
            else
              []
            end

          Enum.concat(name_issues, length_issues)
        end)

      Enum.concat(module_issues, function_issues)
    else
      []
    end
  end

  # Elixir-specific code smell detection
  defp analyze_elixir_code_smells(ast_info, config) do
    if config.check_code_smells do
      # Check for GenServer envy (using Task/Agent inappropriately)
      # This requires deeper analysis of the actual function implementations

      # Check for primitive obsession
      primitive_obsession_issues =
        if config.detect_primitive_obsession do
          detect_primitive_obsession(ast_info)
        else
          []
        end

      # Check for complex branching patterns
      complex_branching_issues =
        if config.detect_complex_branching do
          detect_complex_branching(ast_info)
        else
          []
        end

      # Check for large messages between processes
      large_message_issues = detect_large_messages(ast_info)

      Enum.concat([primitive_obsession_issues, complex_branching_issues, large_message_issues])
    else
      []
    end
  end

  # Detect primitive obsession
  defp detect_primitive_obsession(ast_info) do
    # Look for functions with many primitive parameters
    ast_info.functions
    |> Enum.filter(fn func -> func.arity > 3 end)
    |> Enum.map(fn func ->
      # Without full AST, we can only detect based on arity
      # In real implementation, we'd check parameter types
      Engine.create_issue(
        :primitive_obsession,
        :low,
        "Function #{func.name}/#{func.arity} might benefit from using a struct instead of multiple parameters",
        %{file: "", line: func.line, column: nil, end_line: nil, end_column: nil},
        "style/primitive_obsession",
        :design,
        %{function: func.name, arity: func.arity}
      )
    end)
  end

  # Detect complex branching
  defp detect_complex_branching(_ast_info) do
    # Look for patterns that indicate complex branching
    # This requires full AST analysis
    []
  end

  # Detect large messages
  defp detect_large_messages(ast_info) do
    # Look for GenServer calls with large data structures
    ast_info.calls
    |> Enum.filter(fn call ->
      {module, function, _arity} = call.to
      # Check for GenServer-related calls
      module == GenServer ||
        function in [:handle_call, :handle_cast, :handle_info]
    end)
    |> Enum.map(fn call ->
      Engine.create_issue(
        :potential_large_message,
        :low,
        "Check if large data structures are being passed in process messages",
        %{file: "", line: call.line, column: nil, end_line: nil, end_column: nil},
        "style/large_messages",
        :performance,
        %{call: call}
      )
    end)
  end

  # Function organization analysis
  defp analyze_function_organization(ast_info, _config) do
    # Check for functions that might be in wrong order
    # (public functions should generally come before private ones)
    functions_with_index = Enum.with_index(ast_info.functions)

    last_public_index =
      functions_with_index
      |> Enum.filter(fn {func, _} -> !func.private end)
      |> Enum.map(fn {_, idx} -> idx end)
      |> Enum.max(fn -> -1 end)

    first_private_index =
      functions_with_index
      |> Enum.filter(fn {func, _} -> func.private end)
      |> Enum.map(fn {_, idx} -> idx end)
      |> Enum.min(fn -> length(ast_info.functions) end)

    if last_public_index > first_private_index do
      [
        Engine.create_issue(
          :mixed_function_visibility,
          :info,
          "Public and private functions are mixed. Consider grouping by visibility",
          %{file: "", line: 1, column: nil, end_line: nil, end_column: nil},
          "style/function_organization",
          :style,
          %{}
        )
      ]
    else
      []
    end
  end

  # Module structure analysis
  defp analyze_module_structure(ast_info, _config) do
    # Check for modules that might be doing too much
    unique_call_modules =
      ast_info.calls
      |> Enum.map(fn call -> elem(call.to, 0) end)
      |> Enum.uniq()
      |> length()

    if unique_call_modules > 15 do
      [
        Engine.create_issue(
          :high_coupling,
          :medium,
          "Module interacts with too many other modules (#{unique_call_modules})",
          %{file: "", line: 1, column: nil, end_line: nil, end_column: nil},
          "style/high_coupling",
          :design,
          %{module_count: unique_call_modules}
        )
      ]
    else
      []
    end
  end

  # Calculate style metrics
  defp calculate_style_metrics(ast_info) do
    %{
      naming_consistency_score: calculate_naming_consistency(ast_info),
      function_organization_score: calculate_organization_score(ast_info),
      coupling_score: calculate_coupling_score(ast_info)
    }
  end

  defp calculate_naming_consistency(ast_info) do
    valid_names = Enum.count(ast_info.functions, &Common.valid_function_name?(&1.name))
    total = length(ast_info.functions)

    if total > 0 do
      Float.round(valid_names / total * 100, 2)
    else
      100.0
    end
  end

  defp calculate_organization_score(ast_info) do
    # Simple score based on function ordering
    {public_indices, private_indices} =
      ast_info.functions
      |> Enum.with_index()
      |> Enum.split_with(fn {func, _} -> !func.private end)

    if length(public_indices) > 0 && length(private_indices) > 0 do
      max_public = public_indices |> Enum.map(&elem(&1, 1)) |> Enum.max()
      min_private = private_indices |> Enum.map(&elem(&1, 1)) |> Enum.min()

      if max_public < min_private, do: 100.0, else: 50.0
    else
      100.0
    end
  end

  defp calculate_coupling_score(ast_info) do
    # Lower coupling is better
    unique_modules =
      Enum.concat([ast_info.aliases, ast_info.imports, ast_info.requires])
      |> Enum.uniq()
      |> length()

    cond do
      unique_modules in 0..5 -> 100.0
      unique_modules in 6..10 -> 80.0
      unique_modules in 11..15 -> 60.0
      true -> 40.0
    end
  end

  # Generate style suggestions
  defp generate_style_suggestions(issues) do
    issues
    |> Engine.group_by_type()
    |> Enum.map(fn {type, type_issues} ->
      {type, suggest_style_fixes(type, type_issues)}
    end)
    |> Map.new()
  end

  defp suggest_style_fixes(:invalid_function_name, _) do
    [
      Engine.create_suggestion(
        "Rename function to use snake_case (e.g., my_function_name)",
        nil,
        false
      )
    ]
  end

  defp suggest_style_fixes(:primitive_obsession, _) do
    [
      Engine.create_suggestion(
        "Create a struct to group related parameters",
        """
        defmodule MyContext.MyStruct do
          defstruct [:field1, :field2, :field3]
        end
        """,
        false
      )
    ]
  end

  defp suggest_style_fixes(:high_coupling, _) do
    [
      Engine.create_suggestion(
        "Consider introducing a facade or context module to reduce coupling",
        nil,
        false
      ),
      Engine.create_suggestion(
        "Review module responsibilities and consider splitting",
        nil,
        false
      )
    ]
  end

  defp suggest_style_fixes(_, _), do: []

  # Line-based checks
  defp check_line_length(lines, config) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> String.length(line) > config.max_line_length end)
    |> Enum.map(fn {line, line_num} ->
      Engine.create_issue(
        :line_too_long,
        :info,
        "Line exceeds #{config.max_line_length} characters",
        %{file: "", line: line_num, column: config.max_line_length + 1, end_line: nil, end_column: nil},
        "style/line_length",
        :style,
        %{length: String.length(line)}
      )
    end)
  end

  defp check_todo_comments(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> String.match?(line, ~r/\b(TODO|FIXME|HACK|XXX)\b/i) end)
    |> Enum.map(fn {line, line_num} ->
      Engine.create_issue(
        :todo_comment,
        :info,
        "TODO/FIXME comment found",
        %{file: "", line: line_num, column: nil, end_line: nil, end_column: nil},
        "style/todo_comment",
        :maintainability,
        %{comment: String.trim(line)}
      )
    end)
  end

  defp check_commented_code(lines) do
    lines
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} ->
      # Simple heuristic: comments that look like code
      String.match?(line, ~r/^\s*#\s*(def|defp|defmodule|if|case|cond)\s+/)
    end)
    |> Enum.map(fn {_line, line_num} ->
      Engine.create_issue(
        :commented_code,
        :low,
        "Commented code detected",
        %{file: "", line: line_num, column: nil, end_line: nil, end_column: nil},
        "style/commented_code",
        :maintainability,
        %{}
      )
    end)
  end

  # Enhanced import organization analysis
  defp analyze_import_organization(ast_info, config) do
    issues = []

    # Check for excessive imports
    max_imports = Map.get(config, :max_imports, 10)

    issues =
      if length(ast_info.imports) > max_imports do
        [
          Engine.create_issue(
            :excessive_imports,
            :medium,
            "Module has #{length(ast_info.imports)} imports, consider reducing",
            %{file: "", line: 1, column: nil, end_line: nil, end_column: nil},
            "style/excessive_imports",
            :maintainability,
            %{
              import_count: length(ast_info.imports),
              threshold: max_imports
            }
          )
          | issues
        ]
      else
        issues
      end

    # Check for import order (alphabetical)
    sorted_imports = Enum.sort_by(ast_info.imports, &to_string/1)

    issues =
      if ast_info.imports != sorted_imports && config[:enforce_import_order] do
        [
          Engine.create_issue(
            :import_order,
            :low,
            "Imports are not in alphabetical order",
            %{file: "", line: 1, column: nil, end_line: nil, end_column: nil},
            "style/import_order",
            :style,
            %{}
          )
          | issues
        ]
      else
        issues
      end

    # Check for unused imports (simplified version)
    if config[:detect_unused_imports] do
      used_modules =
        ast_info.calls
        |> Enum.map(fn call -> elem(call.to, 0) end)
        |> Enum.uniq()

      potentially_unused = ast_info.imports -- used_modules

      unused_issues =
        Enum.map(potentially_unused, fn import ->
          Engine.create_issue(
            :potentially_unused_import,
            :low,
            "Import #{inspect(import)} might be unused",
            %{file: "", line: 1, column: nil, end_line: nil, end_column: nil},
            "style/unused_import",
            :maintainability,
            %{module: import}
          )
        end)

      issues ++ unused_issues
    else
      issues
    end
  end

  # Enhanced function complexity analysis  
  defp analyze_function_complexity(ast_info, config) do
    Enum.flat_map(ast_info.functions, fn func ->
      issues = []

      # Check function name length
      name_length = func.name |> Atom.to_string() |> String.length()
      max_name_length = Map.get(config, :max_function_name_length, 30)

      issues =
        if name_length > max_name_length do
          [
            Engine.create_issue(
              :long_function_name,
              :low,
              "Function name '#{func.name}' is #{name_length} characters long",
              %{file: "", line: func.line, column: nil, end_line: nil, end_column: nil},
              "style/long_function_name",
              :style,
              %{
                function: func.name,
                length: name_length,
                threshold: max_name_length
              }
            )
            | issues
          ]
        else
          issues
        end

      # Check arity
      max_arity = Map.get(config, :max_function_arity, 5)

      issues =
        if func.arity > max_arity do
          [
            Engine.create_issue(
              :high_arity,
              :medium,
              "Function #{func.name}/#{func.arity} has too many parameters",
              %{file: "", line: func.line, column: nil, end_line: nil, end_column: nil},
              "style/high_arity",
              :maintainability,
              %{
                function: func.name,
                arity: func.arity,
                threshold: max_arity
              }
            )
            | issues
          ]
        else
          issues
        end

      # Check variable count in function
      var_count = length(func.variables || [])
      max_vars = Map.get(config, :max_variables_per_function, 10)

      issues =
        if var_count > max_vars do
          [
            Engine.create_issue(
              :too_many_variables,
              :medium,
              "Function #{func.name}/#{func.arity} has #{var_count} variables",
              %{file: "", line: func.line, column: nil, end_line: nil, end_column: nil},
              "style/too_many_variables",
              :complexity,
              %{
                function: func.name,
                variable_count: var_count,
                threshold: max_vars
              }
            )
            | issues
          ]
        else
          issues
        end

      issues
    end)
  end
end
