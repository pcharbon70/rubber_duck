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
  """
  @spec validate_template(String.t(), keyword()) :: :ok | {:error, term()}
  def validate_template(template, opts \\ []) do
    with :ok <- check_template_size(template),
         :ok <- check_dangerous_patterns(template),
         :ok <- check_complexity(template, opts),
         :ok <- check_variable_names(template) do
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
      ~r/Process\.get/
    ]

    if Enum.any?(dangerous_patterns, &Regex.match?(&1, template)) do
      {:error, SecurityError.exception(reason: :injection_attempt)}
    else
      :ok
    end
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
    # Extract variable names from template
    variable_pattern = ~r/\{\{[\s]*(\w+)/
    
    matches = Regex.scan(variable_pattern, template)
    variable_names = Enum.map(matches, fn [_, name] -> name end)
    
    suspicious_names = [
      "system", "file", "io", "code", "kernel", "process",
      "eval", "exec", "spawn", "apply", "module", "env"
    ]
    
    if Enum.any?(variable_names, &(&1 in suspicious_names)) do
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
end