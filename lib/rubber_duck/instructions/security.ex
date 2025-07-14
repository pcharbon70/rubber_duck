defmodule RubberDuck.Instructions.Security do
  @moduledoc """
  Security validation and sandboxing for template processing.
  
  Provides comprehensive security measures including:
  - Input validation and sanitization
  - Template size and complexity limits
  - Dangerous pattern detection
  - Sandbox isolation for template execution
  - Path traversal prevention
  - Injection attack prevention
  """

  alias RubberDuck.Instructions.SecurityError

  @max_template_size 50_000
  @max_nesting_depth 10
  @max_variables 100

  @doc """
  Validates a template for security concerns before processing.
  
  Checks for:
  - Template size limits
  - Dangerous patterns
  - Excessive complexity
  - Suspicious variable names
  - AST-based attack patterns
  """
  @spec validate_template(String.t(), keyword()) :: :ok | {:error, term()}
  def validate_template(template, opts \\ []) do
    with :ok <- check_template_size(template),
         :ok <- check_dangerous_patterns(template),
         :ok <- check_complexity(template, opts),
         :ok <- check_variable_names(template),
         :ok <- check_advanced_patterns(template) do
      :ok
    end
  end

  @doc """
  Performs advanced security validation with AST analysis.
  """
  @spec validate_template_advanced(String.t(), keyword()) :: :ok | {:error, term()}
  def validate_template_advanced(template, opts \\ []) do
    with :ok <- validate_template(template, opts),
         :ok <- analyze_template_ast(template),
         :ok <- check_template_entropy(template) do
      :ok
    end
  end

  @doc """
  Validates variables before template processing.
  
  Ensures variables don't contain:
  - System access attempts
  - Code injection patterns
  - Excessive data
  """
  @spec validate_variables(map()) :: :ok | {:error, term()}
  def validate_variables(variables) when is_map(variables) do
    with :ok <- check_variable_count(variables),
         :ok <- check_variable_content(variables) do
      :ok
    end
  end
  def validate_variables(_), do: {:error, :invalid_variables}

  @doc """
  Validates a file path to prevent traversal attacks.
  """
  @spec validate_path(String.t(), String.t()) :: :ok | {:error, term()}
  def validate_path(path, allowed_root) do
    normalized_path = Path.expand(path)
    normalized_root = Path.expand(allowed_root)

    if String.starts_with?(normalized_path, normalized_root) do
      :ok
    else
      {:error, SecurityError.exception(reason: :path_traversal)}
    end
  end

  @doc """
  Checks if a template include/extend path is safe.
  """
  @spec validate_include_path(String.t()) :: :ok | {:error, term()}
  def validate_include_path(path) do
    cond do
      String.contains?(path, "..") ->
        {:error, SecurityError.exception(reason: :path_traversal)}
        
      String.contains?(path, "~") ->
        {:error, SecurityError.exception(reason: :path_traversal)}
        
      String.starts_with?(path, "/") ->
        {:error, SecurityError.exception(reason: :unauthorized_access)}
        
      true ->
        :ok
    end
  end

  @doc """
  Sanitizes a template path by removing dangerous characters.
  """
  @spec sanitize_path(String.t()) :: String.t()
  def sanitize_path(path) do
    path
    |> String.replace(~r/\.\.+/, "")
    |> String.replace(~r/\/\.\//, "/")
    |> String.replace(~r/^\.\//, "")
    |> String.replace(~r/[^\w\-\.\/]/, "")
    |> String.trim("/")
  end

  @doc """
  Creates a sandbox context for template execution.
  
  Limits available functions and modules to safe subset.
  """
  @spec sandbox_context(map()) :: map()
  def sandbox_context(variables) do
    %{
      # Only allow safe string functions
      "upcase" => &String.upcase/1,
      "downcase" => &String.downcase/1,
      "trim" => &String.trim/1,
      "length" => &String.length/1,
      # Safe list functions
      "join" => &Enum.join/2,
      "count" => &Enum.count/1,
      # Safe date/time functions
      "now" => fn -> DateTime.utc_now() |> DateTime.to_iso8601() end,
      "today" => fn -> Date.utc_today() |> Date.to_iso8601() end
    }
    |> Map.merge(variables)
  end

  # Private functions

  defp check_template_size(template) do
    if String.length(template) > @max_template_size do
      {:error, SecurityError.exception(reason: :template_too_large)}
    else
      :ok
    end
  end

  defp check_dangerous_patterns(template) do
    dangerous_patterns = [
      # System access
      ~r/\bSystem\./,
      ~r/\bFile\./,
      ~r/\bIO\./,
      ~r/\bCode\./,
      ~r/\bKernel\./,
      ~r/\bProcess\./,
      # Code execution
      ~r/\beval\b/i,
      ~r/\bexec\b/i,
      ~r/\bspawn\b/i,
      ~r/\bapply\b/i,
      # Module access
      ~r/__MODULE__/,
      ~r/__ENV__/,
      # Atom creation
      ~r/String\.to_atom/,
      ~r/:\w+\s*=>/,
      # Process dictionary
      ~r/Process\.put/,
      ~r/Process\.get/,
      # Advanced patterns - string concatenation bypass
      ~r/['"]Sys['"]\s*(<>|\\+)\s*['"]tem['"]/,
      ~r/\|>\s*to_atom/,
      # Command injection patterns
      ~r/\b(sh|bash|cmd|powershell)\b/i,
      ~r/`.*`/,  # Backticks
      ~r/\$\(.*\)/,  # Command substitution
      # Network access
      ~r/\b(HTTPoison|Tesla|Req|:httpc)\b/,
      ~r/\bSocket\./,
      # Erlang functions
      ~r/:os\./,
      ~r/:erlang\./,
      ~r/:ets\./,
      # GenServer/Process manipulation
      ~r/GenServer\./,
      ~r/Task\./,
      ~r/Agent\./,
      ~r/send\s*\(/
    ]

    # Also check for obfuscation attempts
    if contains_obfuscation?(template) do
      {:error, SecurityError.exception(reason: :injection_attempt)}
    else
      if Enum.any?(dangerous_patterns, &Regex.match?(&1, template)) do
        {:error, SecurityError.exception(reason: :injection_attempt)}
      else
        :ok
      end
    end
  end

  # Check for common obfuscation techniques
  defp contains_obfuscation?(template) do
    # Check for excessive string concatenation
    concat_count = length(Regex.scan(~r/<>|\+/, template))
    
    # Check for base64 encoded content
    has_base64 = Regex.match?(~r/Base\.decode64|:base64\.decode/, template)
    
    # Check for hex encoding
    has_hex = Regex.match?(~r/\b0x[0-9a-fA-F]+\b/, template)
    
    # Check for unicode escape sequences
    has_unicode = Regex.match?(~r/\\u[0-9a-fA-F]{4}/, template)
    
    concat_count > 5 or has_base64 or (has_hex and has_unicode)
  end

  defp check_complexity(template, opts) do
    max_nesting = Keyword.get(opts, :max_nesting, @max_nesting_depth)
    
    nesting_level = calculate_nesting_depth(template)
    
    if nesting_level > max_nesting do
      {:error, SecurityError.exception(reason: :excessive_nesting)}
    else
      :ok
    end
  end

  defp calculate_nesting_depth(template) do
    # Count maximum nesting of control structures
    control_patterns = [
      ~r/\{%\s*if\s+/,
      ~r/\{%\s*for\s+/,
      ~r/\{%\s*unless\s+/,
      ~r/\{%\s*case\s+/
    ]
    
    # Find all opening and closing tags
    open_tags = Enum.flat_map(control_patterns, &Regex.scan(&1, template))
    close_tags = Regex.scan(~r/\{%\s*end\w*\s*%\}/, template)
    
    max(length(open_tags), length(close_tags))
  end

  defp check_variable_names(template) do
    # Extract variable names from template - handle nested access
    variable_patterns = [
      ~r/\{\{[\s]*(\w+(?:\.\w+)*)/,  # {{ user.name }}
      ~r/\{%\s*assign\s+(\w+)/,       # {% assign var = value %}
      ~r/\{%\s*for\s+\w+\s+in\s+(\w+)/ # {% for item in items %}
    ]
    
    all_variables = variable_patterns
    |> Enum.flat_map(fn pattern -> 
      Regex.scan(pattern, template) |> Enum.map(fn [_, name] -> name end)
    end)
    |> Enum.uniq()
    
    suspicious_names = [
      "system", "file", "io", "code", "kernel", "process",
      "eval", "exec", "spawn", "apply", "module", "env",
      "__proto__", "constructor", "prototype", "__dirname",
      "require", "import", "global", "window", "document"
    ]
    
    # Check for suspicious patterns in variable paths
    suspicious_patterns = [
      ~r/\b(system|file|process|code)\./i,
      ~r/__[A-Z]+__/,  # __MODULE__, __ENV__, etc
      ~r/\.\.\//       # Path traversal in object access
    ]
    
    has_suspicious_name = Enum.any?(all_variables, fn var ->
      String.downcase(var) in suspicious_names or
      Enum.any?(suspicious_patterns, &Regex.match?(&1, var))
    end)
    
    if has_suspicious_name do
      {:error, SecurityError.exception(reason: :injection_attempt)}
    else
      :ok
    end
  end

  defp check_variable_count(variables) do
    if map_size(variables) > @max_variables do
      {:error, SecurityError.exception(reason: :too_many_variables)}
    else
      :ok
    end
  end

  defp check_variable_content(variables) do
    Enum.reduce_while(variables, :ok, fn {_key, value}, _acc ->
      case validate_value(value) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_value(value) when is_binary(value) do
    if String.length(value) > 10_000 do
      {:error, SecurityError.exception(reason: :value_too_large)}
    else
      check_dangerous_patterns(value)
    end
  end
  
  defp validate_value(value) when is_number(value), do: :ok
  defp validate_value(value) when is_boolean(value), do: :ok
  defp validate_value(nil), do: :ok
  
  defp validate_value(value) when is_list(value) do
    if length(value) > 1000 do
      {:error, SecurityError.exception(reason: :list_too_large)}
    else
      Enum.reduce_while(value, :ok, fn item, _acc ->
        case validate_value(item) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end
  
  defp validate_value(value) when is_map(value) do
    if map_size(value) > 100 do
      {:error, SecurityError.exception(reason: :map_too_large)}
    else
      check_variable_content(value)
    end
  end
  
  defp validate_value(_), do: {:error, SecurityError.exception(reason: :invalid_value_type)}

  # Advanced pattern checking
  defp check_advanced_patterns(template) do
    # Check for suspicious filter chains
    filter_chain_pattern = ~r/\|\s*\w+\s*:\s*['"][^'"]*['"]\s*\|\s*\w+/
    
    if Regex.match?(filter_chain_pattern, template) do
      # Analyze filter chains for dangerous combinations
      check_filter_chain_safety(template)
    else
      :ok
    end
  end

  defp check_filter_chain_safety(template) do
    # Extract filter chains
    chains = Regex.scan(~r/\{\{[^}]+\}\}/, template)
    
    dangerous_filter_combinations = [
      ["to_atom"],
      ["eval", "execute"],
      ["decode", "apply"],
      ["parse", "call"]
    ]
    
    has_dangerous_chain = Enum.any?(chains, fn [chain] ->
      filters = extract_filters(chain)
      Enum.any?(dangerous_filter_combinations, fn combo ->
        Enum.all?(combo, fn filter -> filter in filters end)
      end)
    end)
    
    if has_dangerous_chain do
      {:error, SecurityError.exception(reason: :injection_attempt)}
    else
      :ok
    end
  end

  defp extract_filters(chain) do
    chain
    |> String.split("|")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.filter(&(&1 != ""))
  end

  # AST-based analysis for Liquid templates
  defp analyze_template_ast(template) do
    # Parse template structure
    case parse_template_structure(template) do
      {:ok, ast} -> validate_ast_safety(ast)
      {:error, _} -> :ok  # If we can't parse, let normal validation handle it
    end
  end

  defp parse_template_structure(template) do
    # Simple AST parser for Liquid templates
    try do
      nodes = parse_liquid_nodes(template)
      {:ok, nodes}
    rescue
      _ -> {:error, :parse_failed}
    end
  end

  defp parse_liquid_nodes(template) do
    # Extract all Liquid tags and objects
    tag_pattern = ~r/\{%\s*(\w+)([^%]*?)%\}/
    obj_pattern = ~r/\{\{([^}]+)\}\}/
    
    tags = Regex.scan(tag_pattern, template, capture: :all_but_first)
    objects = Regex.scan(obj_pattern, template, capture: :all_but_first)
    
    %{
      tags: Enum.map(tags, fn [tag, content] -> {tag, String.trim(content)} end),
      objects: Enum.map(objects, &List.first/1)
    }
  end

  defp validate_ast_safety(ast) do
    # Check for dangerous tag usage patterns
    dangerous_tag_patterns = [
      {"include", ~r/\.\./},  # Path traversal in includes
      {"raw", ~r/\{%|%\}/},   # Nested tags in raw blocks
      {"capture", ~r/system|file|process/i}  # Capturing dangerous content
    ]
    
    has_dangerous_pattern = Enum.any?(ast.tags, fn {tag, content} ->
      Enum.any?(dangerous_tag_patterns, fn {danger_tag, pattern} ->
        tag == danger_tag and Regex.match?(pattern, content)
      end)
    end)
    
    if has_dangerous_pattern do
      {:error, SecurityError.exception(reason: :injection_attempt)}
    else
      :ok
    end
  end

  # Entropy analysis to detect obfuscated/encoded payloads
  defp check_template_entropy(template) do
    # Skip entropy check for small templates
    if String.length(template) < 100 do
      :ok
    else
      entropy = calculate_shannon_entropy(template)
      
      # High entropy might indicate encoded/obfuscated content
      if entropy > 4.5 do
        {:error, SecurityError.exception(reason: :suspicious_content)}
      else
        :ok
      end
    end
  end

  defp calculate_shannon_entropy(string) do
    # Calculate Shannon entropy
    chars = String.graphemes(string)
    total = length(chars)
    
    if total == 0 do
      0.0
    else
      char_counts = Enum.frequencies(chars)
      
      char_counts
      |> Map.values()
      |> Enum.reduce(0.0, fn count, entropy ->
        probability = count / total
        entropy - (probability * :math.log2(probability))
      end)
    end
  end
end