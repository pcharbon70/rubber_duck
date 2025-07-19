defmodule RubberDuck.Analysis.Security do
  @moduledoc """
  Security analysis engine for detecting potential vulnerabilities and security issues.

  Focuses on:
  - SQL injection vulnerabilities
  - XSS (Cross-site scripting) risks
  - Hardcoded secrets and credentials
  - Unsafe operations (eval, dynamic atoms, etc.)
  - Input validation issues
  - Authentication/authorization problems
  """

  @behaviour RubberDuck.Analysis.Engine

  alias RubberDuck.Analysis.Engine

  @impl true
  def name, do: :security

  @impl true
  def description do
    "Analyzes code for security vulnerabilities and unsafe patterns"
  end

  @impl true
  def categories do
    [:security, :correctness]
  end

  @impl true
  def default_config do
    %{
      detect_sql_injection: true,
      detect_xss: true,
      detect_hardcoded_secrets: true,
      detect_unsafe_operations: true,
      detect_dynamic_atoms: true,
      detect_command_injection: true,
      secret_patterns: [
        ~r/password/i,
        ~r/secret/i,
        ~r/api[_-]?key/i,
        ~r/token/i,
        ~r/private[_-]?key/i
      ],
      analyze_call_chains: true,
      check_input_validation: true
    }
  end

  @impl true
  def analyze(ast_info, options \\ []) do
    config = Keyword.get(options, :config, default_config())
    issues = []

    # Run various security analyses
    issues =
      issues
      |> Enum.concat(analyze_dynamic_atoms(ast_info, config))
      |> Enum.concat(analyze_unsafe_operations(ast_info, config))
      |> Enum.concat(analyze_sql_injection_risks(ast_info, config))
      |> Enum.concat(analyze_potential_xss(ast_info, config))
      |> Enum.concat(analyze_process_spawning(ast_info, config))
      |> Enum.concat(analyze_call_chains(ast_info, config))
      |> Enum.concat(analyze_input_validation(ast_info, config))

    # Calculate security metrics
    metrics = calculate_security_metrics(ast_info, issues)

    # Generate security suggestions
    suggestions = generate_security_suggestions(issues)

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

    # Text-based security analysis
    lines = String.split(source, "\n")

    issues =
      issues
      |> Enum.concat(detect_hardcoded_secrets(lines, config))
      |> Enum.concat(detect_unsafe_patterns(lines, config))
      |> Enum.concat(detect_suspicious_comments(lines))

    {:ok,
     %{
       engine: name(),
       issues: issues,
       metrics: %{
         total_security_issues: length(issues),
         critical_issues: Enum.count(issues, &(&1.severity == :critical)),
         high_issues: Enum.count(issues, &(&1.severity == :high))
       },
       suggestions: %{},
       metadata: %{language: language, source_analysis: true}
     }}
  end

  # Dynamic atom creation detection
  defp analyze_dynamic_atoms(ast_info, config) do
    if !config.detect_dynamic_atoms do
      []
    else
      # Look for String.to_atom calls in both module-level and function-level calls
      all_calls = get_all_calls(ast_info)

      all_calls
      |> Enum.filter(fn call ->
        case call.to do
          {String, :to_atom, 1} -> true
          # This is safer
          {String, :to_existing_atom, 1} -> false
          {Kernel, :binary_to_atom, _} -> true
          _ -> false
        end
      end)
      |> Enum.map(fn call ->
        Engine.create_issue(
          :dynamic_atom_creation,
          :high,
          "Dynamic atom creation can lead to memory exhaustion attacks",
          %{file: "", line: call.line, column: nil, end_line: nil, end_column: nil},
          "security/dynamic_atoms",
          :security,
          %{function_called: elem(call.to, 1)}
        )
      end)
    end
  end

  # Unsafe operations detection
  defp analyze_unsafe_operations(ast_info, config) do
    if !config.detect_unsafe_operations do
      []
    else
      unsafe_functions = [
        {Code, :eval_string, :any},
        {Code, :eval_quoted, :any},
        {Kernel, :apply, 3},
        {System, :cmd, :any},
        {:os, :cmd, 1}
      ]

      all_calls = get_all_calls(ast_info)

      all_calls
      |> Enum.filter(fn call ->
        Enum.any?(unsafe_functions, fn
          {mod, fun, :any} ->
            match?({^mod, ^fun, _}, call.to)

          {mod, fun, arity} ->
            call.to == {mod, fun, arity}
        end)
      end)
      |> Enum.map(fn call ->
        {module, function, _arity} = call.to

        severity =
          case {module, function} do
            {Code, :eval_string} -> :critical
            {Code, :eval_quoted} -> :critical
            {System, :cmd} -> :high
            {:os, :cmd} -> :high
            _ -> :medium
          end

        Engine.create_issue(
          :unsafe_operation,
          severity,
          "Usage of potentially unsafe function #{module}.#{function}",
          %{file: "", line: call.line, column: nil, end_line: nil, end_column: nil},
          "security/unsafe_operation",
          :security,
          %{module: module, function: function}
        )
      end)
    end
  end

  # SQL injection risk detection
  defp analyze_sql_injection_risks(ast_info, config) do
    if !config.detect_sql_injection do
      []
    else
      # Look for Ecto query construction patterns
      sql_related_modules = [Ecto.Query, Ecto.Adapters.SQL]

      all_calls = get_all_calls(ast_info)

      all_calls
      |> Enum.filter(fn call ->
        {module, _fun, _arity} = call.to
        module in sql_related_modules
      end)
      |> Enum.map(fn call ->
        # Without full AST, we can only flag for manual review
        Engine.create_issue(
          :potential_sql_injection,
          :medium,
          "Review SQL query construction for injection vulnerabilities",
          %{file: "", line: call.line, column: nil, end_line: nil, end_column: nil},
          "security/sql_injection_risk",
          :security,
          %{call: call}
        )
      end)
    end
  end

  # XSS risk detection
  defp analyze_potential_xss(ast_info, config) do
    if !config.detect_xss do
      []
    else
      # Look for Phoenix.HTML.raw calls
      all_calls = get_all_calls(ast_info)

      all_calls
      |> Enum.filter(fn call ->
        case call.to do
          {Phoenix.HTML, :raw, _} -> true
          {Phoenix.HTML.Tag, :content_tag, _} -> true
          _ -> false
        end
      end)
      |> Enum.map(fn call ->
        Engine.create_issue(
          :potential_xss,
          :high,
          "Unescaped HTML output detected - ensure user input is sanitized",
          %{file: "", line: call.line, column: nil, end_line: nil, end_column: nil},
          "security/xss_risk",
          :security,
          %{function: elem(call.to, 1)}
        )
      end)
    end
  end

  # Process spawning security
  defp analyze_process_spawning(ast_info, _config) do
    # Look for unsupervised process spawning
    spawn_functions = [
      {Process, :spawn, :any},
      {Kernel, :spawn, :any},
      {Kernel, :spawn_link, :any},
      {Task, :async, :any}
    ]

    all_calls = get_all_calls(ast_info)

    all_calls
    |> Enum.filter(fn call ->
      Enum.any?(spawn_functions, fn
        {mod, fun, :any} ->
          {call_mod, call_fun, _} = call.to
          call_mod == mod && call_fun == fun
      end)
    end)
    |> Enum.map(fn call ->
      {module, function, _} = call.to

      # Task.async is supervised, so less severe
      severity = if module == Task, do: :low, else: :medium

      Engine.create_issue(
        :unsupervised_process,
        severity,
        "Process spawned without supervision tree",
        %{file: "", line: call.line, column: nil, end_line: nil, end_column: nil},
        "security/unsupervised_process",
        :security,
        %{spawn_function: "#{module}.#{function}"}
      )
    end)
  end

  # Text-based secret detection
  defp detect_hardcoded_secrets(lines, config) do
    if !config.detect_hardcoded_secrets do
      []
    else
      lines
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {line, line_num} ->
        # Check for patterns that look like secrets
        if contains_secret_pattern?(line, config.secret_patterns) do
          [
            Engine.create_issue(
              :hardcoded_secret,
              :critical,
              "Potential hardcoded secret or credential detected",
              %{file: "", line: line_num, column: nil, end_line: nil, end_column: nil},
              "security/hardcoded_secret",
              :security,
              %{pattern_matched: true}
            )
          ]
        else
          []
        end
      end)
    end
  end

  defp contains_secret_pattern?(line, patterns) do
    # Skip comments and empty lines
    trimmed = String.trim(line)

    if trimmed == "" || String.starts_with?(trimmed, "#") do
      false
    else
      # Check for assignment patterns with secret-like names
      Enum.any?(patterns, fn pattern ->
        # Look for variable assignments or map keys
        Regex.match?(pattern, line) &&
          (String.contains?(line, "=") || String.contains?(line, ":"))
      end)
    end
  end

  # Detect unsafe patterns in source
  defp detect_unsafe_patterns(lines, _config) do
    unsafe_patterns = [
      {~r/eval\s*\(/, :critical, "eval usage detected"},
      {~r/System\.cmd/, :high, "System command execution detected"},
      {~r/:os\.cmd/, :high, "OS command execution detected"},
      {~r/\.to_atom\s*\(/, :high, "Dynamic atom creation detected"}
    ]

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      unsafe_patterns
      |> Enum.filter(fn {pattern, _, _} -> Regex.match?(pattern, line) end)
      |> Enum.map(fn {_, severity, message} ->
        Engine.create_issue(
          :unsafe_pattern,
          severity,
          message,
          %{file: "", line: line_num, column: nil, end_line: nil, end_column: nil},
          "security/unsafe_pattern",
          :security,
          %{}
        )
      end)
    end)
  end

  # Detect suspicious comments
  defp detect_suspicious_comments(lines) do
    suspicious_patterns = [
      {~r/SECURITY|VULNERABILITY|HACK|INSECURE|UNSAFE/i, "Security-related comment found"},
      {~r/TODO.*security|FIXME.*security/i, "Security TODO found"}
    ]

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      if String.contains?(line, "#") do
        suspicious_patterns
        |> Enum.filter(fn {pattern, _} -> Regex.match?(pattern, line) end)
        |> Enum.map(fn {_, message} ->
          Engine.create_issue(
            :security_comment,
            :low,
            message,
            %{file: "", line: line_num, column: nil, end_line: nil, end_column: nil},
            "security/comment",
            :security,
            %{comment: String.trim(line)}
          )
        end)
      else
        []
      end
    end)
  end

  # Calculate security metrics
  defp calculate_security_metrics(ast_info, issues) do
    %{
      total_issues: length(issues),
      critical_issues: Enum.count(issues, &(&1.severity == :critical)),
      high_risk_calls: count_high_risk_calls(ast_info),
      security_score: calculate_security_score(issues),
      uses_unsafe_functions: detect_unsafe_function_usage(ast_info)
    }
  end

  defp count_high_risk_calls(ast_info) do
    high_risk_modules = [Code, System, :os, :erlang]

    ast_info.calls
    |> Enum.count(fn call ->
      elem(call.to, 0) in high_risk_modules
    end)
  end

  defp calculate_security_score(issues) do
    # Simple scoring: start at 100, deduct based on severity
    deductions = %{
      critical: 25,
      high: 15,
      medium: 10,
      low: 5,
      info: 1
    }

    score =
      Enum.reduce(issues, 100, fn issue, acc ->
        acc - Map.get(deductions, issue.severity, 0)
      end)

    max(0, score)
  end

  defp detect_unsafe_function_usage(ast_info) do
    unsafe_modules = [Code, :os]

    ast_info.calls
    |> Enum.any?(fn call ->
      elem(call.to, 0) in unsafe_modules
    end)
  end

  # Generate security suggestions
  defp generate_security_suggestions(issues) do
    issues
    |> Engine.group_by_type()
    |> Enum.map(fn {type, type_issues} ->
      {type, suggest_security_fixes(type, type_issues)}
    end)
    |> Map.new()
  end

  defp suggest_security_fixes(:dynamic_atom_creation, _) do
    [
      Engine.create_suggestion(
        "Use String.to_existing_atom/1 instead to prevent atom exhaustion",
        "String.to_existing_atom(user_input)",
        true
      ),
      Engine.create_suggestion(
        "Consider using a predefined map of allowed atoms",
        """
        @allowed_atoms %{
          "option1" => :option1,
          "option2" => :option2
        }

        Map.get(@allowed_atoms, user_input)
        """,
        false
      )
    ]
  end

  defp suggest_security_fixes(:unsafe_operation, issues) do
    if Enum.any?(issues, fn i -> i.metadata.function == :eval_string end) do
      [
        Engine.create_suggestion(
          "Avoid evaluating user input. Use pattern matching or predefined functions",
          nil,
          false
        )
      ]
    else
      [
        Engine.create_suggestion(
          "Validate and sanitize all inputs before using with system commands",
          nil,
          false
        ),
        Engine.create_suggestion(
          "Consider using application-level alternatives instead of system commands",
          nil,
          false
        )
      ]
    end
  end

  defp suggest_security_fixes(:hardcoded_secret, _) do
    [
      Engine.create_suggestion(
        "Move secrets to environment variables",
        """
        # In config/runtime.exs
        config :my_app, :secret_key,
          System.get_env("SECRET_KEY") || raise "SECRET_KEY not set"
        """,
        false
      ),
      Engine.create_suggestion(
        "Use a secrets management service or encrypted credentials",
        nil,
        false
      )
    ]
  end

  defp suggest_security_fixes(:potential_xss, _) do
    [
      Engine.create_suggestion(
        "Sanitize user input before rendering",
        "Phoenix.HTML.html_escape(user_input)",
        false
      ),
      Engine.create_suggestion(
        "Use Phoenix.HTML functions that auto-escape by default",
        nil,
        false
      )
    ]
  end

  defp suggest_security_fixes(:unsupervised_process, _) do
    [
      Engine.create_suggestion(
        "Use a supervised Task instead",
        """
        Task.Supervisor.start_child(MyApp.TaskSupervisor, fn ->
          # Process work
        end)
        """,
        false
      ),
      Engine.create_suggestion(
        "Add process to a supervision tree",
        nil,
        false
      )
    ]
  end

  defp suggest_security_fixes(_, _), do: []

  # Helper function to get all calls from module and function levels
  defp get_all_calls(ast_info) do
    function_calls =
      Enum.flat_map(ast_info.functions, fn func ->
        func.body_calls || []
      end)

    Enum.concat(ast_info.calls, function_calls)
  end

  # Enhanced call chain analysis for security vulnerabilities
  defp analyze_call_chains(ast_info, config) do
    if !config[:analyze_call_chains] do
      []
    else
      call_graph = build_security_call_graph(ast_info)

      # Find paths to dangerous functions
      dangerous_targets = [
        {System, :cmd, 2},
        {:os, :cmd, 1},
        {Code, :eval_string, 1},
        {Code, :eval_file, 1},
        {Code, :eval_quoted, 1},
        {:erlang, :binary_to_term, 1},
        {:erlang, :binary_to_term, 2}
      ]

      issues =
        Enum.flat_map(call_graph, fn {from, calls} ->
          dangerous_calls =
            Enum.filter(calls, fn call ->
              call in dangerous_targets
            end)

          Enum.map(dangerous_calls, fn dangerous ->
            func =
              Enum.find(ast_info.functions, fn f ->
                f.name == elem(from, 1) && f.arity == elem(from, 2)
              end)

            Engine.create_issue(
              :dangerous_call_chain,
              :high,
              "Function #{elem(from, 1)}/#{elem(from, 2)} calls potentially dangerous #{format_call(dangerous)}",
              %{file: "", line: (func && func.line) || 0, column: nil, end_line: nil, end_column: nil},
              "security/dangerous_call",
              :security,
              %{
                caller: from,
                dangerous_function: dangerous
              }
            )
          end)
        end)

      issues
    end
  end

  defp build_security_call_graph(ast_info) do
    all_calls = get_all_calls(ast_info)

    all_calls
    |> Enum.group_by(& &1.from)
    |> Map.new(fn {from, calls} ->
      {from, Enum.map(calls, & &1.to) |> Enum.uniq()}
    end)
  end

  defp format_call({module, function, arity}) do
    "#{inspect(module)}.#{function}/#{arity}"
  end

  # Enhanced input validation analysis
  defp analyze_input_validation(ast_info, config) do
    if !config[:check_input_validation] do
      []
    else
      # Find variables that might contain user input
      input_patterns = ~r/(params|input|data|request|body|args)/

      suspicious_vars =
        ast_info.variables
        |> Enum.filter(fn var ->
          var.type == :assignment &&
            Regex.match?(input_patterns, Atom.to_string(var.name))
        end)

      # Check if these variables are used in dangerous contexts
      issues =
        Enum.flat_map(suspicious_vars, fn var ->
          check_variable_usage(var, ast_info)
        end)

      # Also check for direct parameter usage in dangerous functions
      param_usage_issues = check_direct_param_usage(ast_info)

      issues ++ param_usage_issues
    end
  end

  defp check_variable_usage(var, ast_info) do
    # Find where this variable is used
    usages =
      ast_info.variables
      |> Enum.filter(fn v ->
        v.name == var.name && v.type == :usage && v.line > var.line
      end)

    # Check if any usage is in a dangerous context
    # This is simplified - real implementation would need data flow analysis
    if Enum.any?(usages) do
      [
        Engine.create_issue(
          :unvalidated_input,
          :medium,
          "Variable '#{var.name}' may contain user input - ensure proper validation",
          %{file: "", line: var.line, column: var.column, end_line: nil, end_column: nil},
          "security/input_validation",
          :security,
          %{
            variable: var.name,
            recommendation: "Validate and sanitize user input before use"
          }
        )
      ]
    else
      []
    end
  end

  defp check_direct_param_usage(ast_info) do
    # Check functions that might directly use parameters in dangerous ways
    Enum.flat_map(ast_info.functions, fn func ->
      # Look for patterns like SQL queries, shell commands, etc.
      dangerous_patterns = [
        ~r/Repo\.(query|execute)/,
        ~r/System\.cmd/,
        ~r/File\.(read|write)/,
        ~r/Code\.eval/
      ]

      # Simple heuristic: functions with "params" or "input" in parameters
      if Enum.any?(func.variables || [], fn v ->
           v.type == :pattern && Regex.match?(~r/(params|input)/, Atom.to_string(v.name))
         end) do
        # Check if function has calls to dangerous functions
        dangerous_calls =
          (func.body_calls || [])
          |> Enum.filter(fn call ->
            call_string = format_call(call.to)
            Enum.any?(dangerous_patterns, &Regex.match?(&1, call_string))
          end)

        Enum.map(dangerous_calls, fn call ->
          Engine.create_issue(
            :potential_injection,
            :high,
            "Function #{func.name}/#{func.arity} may pass user input to #{format_call(call.to)}",
            %{file: "", line: func.line, column: nil, end_line: nil, end_column: nil},
            "security/injection_risk",
            :security,
            %{
              function: func.name,
              dangerous_call: call.to,
              recommendation: "Ensure proper input validation and parameterization"
            }
          )
        end)
      else
        []
      end
    end)
  end
end
