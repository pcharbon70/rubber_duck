defmodule RubberDuck.ErrorDetection.SourceDetector do
  @moduledoc """
  Source code error detection module for identifying various types of errors.
  
  Provides detection capabilities for:
  - Syntax errors in various languages
  - Logic errors and code smells
  - Runtime error patterns
  - Code quality issues
  - Security vulnerabilities
  """

  require Logger

  @doc """
  Detects syntax errors in source code.
  """
  def detect_syntax_errors(content, content_type, config) do
    case content_type do
      "elixir" ->
        detect_elixir_syntax_errors(content, config)
      
      "javascript" ->
        detect_javascript_syntax_errors(content, config)
      
      "python" ->
        detect_python_syntax_errors(content, config)
      
      "json" ->
        detect_json_syntax_errors(content, config)
      
      _ ->
        detect_generic_syntax_errors(content, config)
    end
  end

  @doc """
  Detects logic errors and code smells.
  """
  def detect_logic_errors(content, content_type, config) do
    case content_type do
      "elixir" ->
        detect_elixir_logic_errors(content, config)
      
      _ ->
        detect_generic_logic_errors(content, config)
    end
  end

  @doc """
  Detects runtime error patterns.
  """
  def detect_runtime_errors(content, content_type, config) do
    patterns = get_runtime_error_patterns(content_type)
    detect_pattern_matches(content, patterns, config)
  end

  @doc """
  Detects code quality issues.
  """
  def detect_quality_issues(content, content_type, config) do
    quality_checks = [
      check_line_length(content, config),
      check_complexity(content, content_type, config),
      check_naming_conventions(content, content_type, config),
      check_documentation(content, content_type, config),
      check_duplicated_code(content, config)
    ]
    
    {:ok, Enum.flat_map(quality_checks, fn {:ok, issues} -> issues end)}
  end

  @doc """
  Detects security vulnerabilities and issues.
  """
  def detect_security_issues(content, content_type, config) do
    security_checks = [
      check_hardcoded_secrets(content, config),
      check_sql_injection_patterns(content, config),
      check_xss_vulnerabilities(content, content_type, config),
      check_unsafe_functions(content, content_type, config),
      check_input_validation(content, content_type, config)
    ]
    
    {:ok, Enum.flat_map(security_checks, fn {:ok, issues} -> issues end)}
  end

  # Private Implementation Functions

  # Elixir Syntax Error Detection
  defp detect_elixir_syntax_errors(content, _config) do
    try do
      case Code.string_to_quoted(content) do
        {:ok, _ast} ->
          {:ok, []}
        
        {:error, {line, description, token}} ->
          error = %{
            type: :syntax_error,
            severity: 9,
            line: line,
            description: "#{description}#{if token, do: " (#{token})", else: ""}",
            category: :elixir_syntax,
            confidence: 1.0
          }
          {:ok, [error]}
      end
    rescue
      e ->
        error = %{
          type: :syntax_error,
          severity: 9,
          line: 1,
          description: "Parse error: #{Exception.message(e)}",
          category: :elixir_syntax,
          confidence: 1.0
        }
        {:ok, [error]}
    end
  end

  # JavaScript Syntax Error Detection
  defp detect_javascript_syntax_errors(content, _config) do
    # Basic JavaScript syntax patterns
    syntax_patterns = [
      {~r/\bmissing\s+[;}]\s*$/, "Missing semicolon or brace"},
      {~r/\bunexpected\s+token/, "Unexpected token"},
      {~r/\bundefined\s+variable/, "Undefined variable"},
      {~r/\bunmatched\s+[\(\[\{]/, "Unmatched opening bracket"}
    ]
    
    detect_pattern_matches(content, syntax_patterns, %{severity: 8, category: :javascript_syntax})
  end

  # Python Syntax Error Detection
  defp detect_python_syntax_errors(content, _config) do
    syntax_patterns = [
      {~r/^\s*File\s+"[^"]+",\s+line\s+(\d+)/, "Python syntax error"},
      {~r/IndentationError/, "Indentation error"},
      {~r/SyntaxError/, "Syntax error"},
      {~r/invalid\s+syntax/, "Invalid syntax"}
    ]
    
    detect_pattern_matches(content, syntax_patterns, %{severity: 9, category: :python_syntax})
  end

  # JSON Syntax Error Detection
  defp detect_json_syntax_errors(content, _config) do
    try do
      case Jason.decode(content) do
        {:ok, _} ->
          {:ok, []}
        
        {:error, %Jason.DecodeError{position: pos, data: data}} ->
          # Calculate line number from position
          line = calculate_line_from_position(content, pos)
          
          error = %{
            type: :syntax_error,
            severity: 8,
            line: line,
            description: "JSON decode error: #{data}",
            category: :json_syntax,
            confidence: 1.0
          }
          {:ok, [error]}
      end
    rescue
      e ->
        error = %{
          type: :syntax_error,
          severity: 8,
          line: 1,
          description: "JSON parse error: #{Exception.message(e)}",
          category: :json_syntax,
          confidence: 1.0
        }
        {:ok, [error]}
    end
  end

  # Generic Syntax Error Detection
  defp detect_generic_syntax_errors(content, _config) do
    generic_patterns = [
      {~r/error|Error|ERROR/, "Generic error pattern"},
      {~r/exception|Exception|EXCEPTION/, "Exception pattern"},
      {~r/fail|Fail|FAIL/, "Failure pattern"}
    ]
    
    detect_pattern_matches(content, generic_patterns, %{severity: 5, category: :generic_syntax})
  end

  # Elixir Logic Error Detection
  defp detect_elixir_logic_errors(content, _config) do
    logic_patterns = [
      {~r/if\s+true\s+do/, "Redundant if true condition"},
      {~r/if\s+false\s+do/, "Dead code - if false condition"},
      {~r/case\s+\w+\s+do\s+\w+\s+->\s+\w+\s+\w+\s+->\s+\w+/, "Possible missing case clauses"},
      {~r/def\s+\w+.*\n.*def\s+\w+/, "Possible duplicate function definitions"},
      {~r/==\s*true|true\s*==/, "Redundant boolean comparison"},
      {~r/==\s*false|false\s*==/, "Redundant boolean comparison"}
    ]
    
    detect_pattern_matches(content, logic_patterns, %{severity: 6, category: :elixir_logic})
  end

  # Generic Logic Error Detection
  defp detect_generic_logic_errors(content, _config) do
    logic_patterns = [
      {~r/while\s*\(\s*true\s*\)/, "Infinite loop detected"},
      {~r/for\s*\(\s*;\s*;\s*\)/, "Infinite loop detected"},
      {~r/if\s*\(\s*true\s*\)/, "Redundant if true condition"},
      {~r/if\s*\(\s*false\s*\)/, "Dead code - if false condition"}
    ]
    
    detect_pattern_matches(content, logic_patterns, %{severity: 7, category: :generic_logic})
  end

  # Runtime Error Pattern Detection
  defp get_runtime_error_patterns("elixir") do
    [
      {~r/\*\*\s*\(.*Error\)/, "Runtime exception pattern"},
      {~r/Process\.exit/, "Process exit call"},
      {~r/raise\s+/, "Explicit raise call"},
      {~r/throw\s+/, "Throw statement"},
      {~r/GenServer\.call.*timeout/, "GenServer timeout"}
    ]
  end

  defp get_runtime_error_patterns(_) do
    [
      {~r/throw\s+/, "Throw statement"},
      {~r/error\s*\(/, "Error function call"},
      {~r/exception\s*\(/, "Exception function call"}
    ]
  end

  # Quality Check Functions
  defp check_line_length(content, config) do
    max_length = Map.get(config, :max_line_length, 120)
    
    issues = content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _} -> String.length(line) > max_length end)
    |> Enum.map(fn {_line, line_num} ->
      %{
        type: :quality_issue,
        severity: 3,
        line: line_num,
        description: "Line exceeds maximum length of #{max_length} characters",
        category: :line_length,
        confidence: 1.0
      }
    end)
    
    {:ok, issues}
  end

  defp check_complexity(content, _content_type, _config) do
    # Simple complexity check based on nesting levels
    nesting_level = count_nesting_level(content)
    
    issues = if nesting_level > 5 do
      [%{
        type: :quality_issue,
        severity: 5,
        line: 1,
        description: "High cyclomatic complexity detected (nesting level: #{nesting_level})",
        category: :complexity,
        confidence: 0.7
      }]
    else
      []
    end
    
    {:ok, issues}
  end

  defp check_naming_conventions(content, "elixir", _config) do
    naming_patterns = [
      {~r/def\s+[A-Z]\w*/, "Function names should start with lowercase"},
      {~r/@[a-z]\w*[A-Z]/, "Module attributes should be snake_case"},
      {~r/defmodule\s+[a-z]/, "Module names should start with uppercase"}
    ]
    
    detect_pattern_matches(content, naming_patterns, %{severity: 4, category: :naming})
  end

  defp check_naming_conventions(_content, _content_type, _config) do
    {:ok, []}
  end

  defp check_documentation(content, "elixir", _config) do
    # Check for missing @doc or @moduledoc
    doc_patterns = [
      {~r/defmodule\s+\w+(?!\s*@moduledoc)/, "Missing @moduledoc"},
      {~r/def\s+\w+(?!\s*@doc)/, "Missing @doc for public function"}
    ]
    
    detect_pattern_matches(content, doc_patterns, %{severity: 3, category: :documentation})
  end

  defp check_documentation(_content, _content_type, _config) do
    {:ok, []}
  end

  defp check_duplicated_code(content, _config) do
    lines = String.split(content, "\n")
    
    # Simple duplicate line detection
    duplicates = lines
    |> Enum.with_index(1)
    |> Enum.group_by(fn {line, _} -> String.trim(line) end)
    |> Enum.filter(fn {line, occurrences} -> 
      String.length(String.trim(line)) > 10 && length(occurrences) > 1
    end)
    |> Enum.flat_map(fn {_line, occurrences} ->
      Enum.map(occurrences, fn {_line_content, line_num} ->
        %{
          type: :quality_issue,
          severity: 4,
          line: line_num,
          description: "Duplicated code detected",
          category: :duplication,
          confidence: 0.8
        }
      end)
    end)
    
    {:ok, duplicates}
  end

  # Security Check Functions
  defp check_hardcoded_secrets(content, _config) do
    secret_patterns = [
      {~r/password\s*=\s*["'][^"']+["']/, "Hardcoded password"},
      {~r/api_key\s*=\s*["'][^"']+["']/, "Hardcoded API key"},
      {~r/secret\s*=\s*["'][^"']+["']/, "Hardcoded secret"},
      {~r/token\s*=\s*["'][^"']+["']/, "Hardcoded token"},
      {~r/[a-zA-Z0-9]{32,}/, "Potential hardcoded hash or key"}
    ]
    
    detect_pattern_matches(content, secret_patterns, %{severity: 8, category: :security_secrets})
  end

  defp check_sql_injection_patterns(content, _config) do
    sql_patterns = [
      {~r/query\s*\+\s*/, "String concatenation in SQL query"},
      {~r/"SELECT.*"\s*\+/, "SQL injection risk - string concatenation"},
      {~r/execute\s*\(\s*".*"\s*\+/, "SQL execution with concatenation"}
    ]
    
    detect_pattern_matches(content, sql_patterns, %{severity: 9, category: :security_sql})
  end

  defp check_xss_vulnerabilities(content, _content_type, _config) do
    xss_patterns = [
      {~r/innerHTML\s*=/, "Potential XSS via innerHTML"},
      {~r/document\.write\s*\(/, "Potential XSS via document.write"},
      {~r/eval\s*\(/, "Dangerous eval usage"}
    ]
    
    detect_pattern_matches(content, xss_patterns, %{severity: 8, category: :security_xss})
  end

  defp check_unsafe_functions(content, "elixir", _config) do
    unsafe_patterns = [
      {~r/Code\.eval_string/, "Dangerous code evaluation"},
      {~r/System\.cmd/, "System command execution"},
      {~r/:os\.cmd/, "OS command execution"}
    ]
    
    detect_pattern_matches(content, unsafe_patterns, %{severity: 7, category: :security_unsafe})
  end

  defp check_unsafe_functions(_content, _content_type, _config) do
    {:ok, []}
  end

  defp check_input_validation(content, _content_type, _config) do
    validation_patterns = [
      {~r/params\[/, "Direct parameter access without validation"},
      {~r/request\./, "Direct request access without validation"}
    ]
    
    detect_pattern_matches(content, validation_patterns, %{severity: 6, category: :security_validation})
  end

  # Helper Functions
  defp detect_pattern_matches(content, patterns, options) do
    issues = patterns
    |> Enum.flat_map(fn {pattern, description} ->
      find_pattern_matches(content, pattern, description, options)
    end)
    
    {:ok, issues}
  end

  defp find_pattern_matches(content, pattern, description, options) do
    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_num} ->
      if Regex.match?(pattern, line) do
        [%{
          type: :pattern_match,
          severity: Map.get(options, :severity, 5),
          line: line_num,
          description: description,
          category: Map.get(options, :category, :unknown),
          confidence: Map.get(options, :confidence, 0.8)
        }]
      else
        []
      end
    end)
  end

  defp calculate_line_from_position(content, position) do
    content
    |> String.slice(0, position)
    |> String.split("\n")
    |> length()
  end

  defp count_nesting_level(content) do
    content
    |> String.split("\n")
    |> Enum.map(&count_line_nesting/1)
    |> Enum.max()
  end

  defp count_line_nesting(line) do
    # Count indentation level as a proxy for nesting
    leading_spaces = String.length(line) - String.length(String.trim_leading(line))
    div(leading_spaces, 2) # Assuming 2-space indentation
  end
end