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
      detect_unnecessary_macros: true
    }
  end

  @impl true
  def analyze(ast_info, options \\ []) do
    config = Keyword.get(options, :config, default_config())
    issues = []

    # Run various style analyses
    issues = issues ++ analyze_naming_conventions(ast_info, config)
    issues = issues ++ analyze_elixir_code_smells(ast_info, config)
    issues = issues ++ analyze_function_organization(ast_info, config)
    issues = issues ++ analyze_module_structure(ast_info, config)

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

    issues = issues ++ check_line_length(lines, config)
    issues = issues ++ check_todo_comments(lines)
    issues = issues ++ check_commented_code(lines)

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
    if !config.check_naming_conventions do
      []
    else
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
      function_issues = Enum.flat_map(ast_info.functions, fn func ->
        name_issues = 
          unless Common.valid_function_name?(func.name) do
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
          else
            []
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

        name_issues ++ length_issues
      end)

      module_issues ++ function_issues
    end
  end

  # Elixir-specific code smell detection
  defp analyze_elixir_code_smells(ast_info, config) do
    if !config.check_code_smells do
      []
    else
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

      primitive_obsession_issues ++ complex_branching_issues ++ large_message_issues
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
      (ast_info.aliases ++ ast_info.imports ++ ast_info.requires)
      |> Enum.uniq()
      |> length()

    case unique_modules do
      0..5 -> 100.0
      6..10 -> 80.0
      11..15 -> 60.0
      _ -> 40.0
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
end

