defmodule RubberDuck.Tool.Security.Sanitizer do
  @moduledoc """
  Input sanitization for tool parameters.

  Provides comprehensive sanitization to prevent various injection attacks:
  - Path traversal prevention
  - Command injection protection
  - SQL injection prevention
  - Template injection protection
  """

  require Logger

  # Path traversal patterns to block
  @path_traversal_patterns [
    # Parent directory
    ~r/\.\./,
    # URL encoded parent directory
    ~r/\.\.%2[fF]/,
    # Alternative encoding
    ~r/\.\.%5[cC]/,
    # Windows path traversal
    ~r/\.\.\\/,
    # URL encoded dot
    ~r/%2[eE]\./,
    # Double encoded
    ~r/%2[eE]%2[eE]/,
    # Null byte injection
    ~r/\x00/
  ]

  # Command injection patterns
  @command_injection_patterns [
    # Shell metacharacters
    ~r/[;&|`$(){}[\]<>]/,
    # Newlines
    ~r/\n|\r/,
    # Command substitution
    ~r/\$\(/,
    # Variable substitution
    ~r/\$\{/,
    # Redirection
    ~r/>/,
    # Pipe
    ~r/\|/,
    # Command separator
    ~r/;/,
    # Background execution
    ~r/&/,
    # Backticks
    ~r/`/
  ]

  # SQL injection patterns (basic)
  @sql_injection_patterns [
    ~r/(\s|^)(union)(\s|$)/i,
    ~r/(\s|^)(select)(\s|$)/i,
    ~r/(\s|^)(insert)(\s|$)/i,
    ~r/(\s|^)(update)(\s|$)/i,
    ~r/(\s|^)(delete)(\s|$)/i,
    ~r/(\s|^)(drop)(\s|$)/i,
    # SQL comment
    ~r/--/,
    # Multi-line comment start
    ~r/\/\*/,
    # Multi-line comment end
    ~r/\*\//,
    # Statement terminator
    ~r/;/,
    # Single quote
    ~r/'/,
    # Double quote
    ~r/"/,
    # Escape character
    ~r/\\/
  ]

  # Template injection patterns
  @template_injection_patterns [
    # Mustache/Handlebars
    ~r/\{\{/,
    ~r/\}\}/,
    # ERB/EJS
    ~r/<%/,
    ~r/%>/,
    # Template literals
    ~r/\${/,
    # Ruby interpolation
    ~r/#\{/,
    # PHP tags
    ~r/<\?/,
    ~r/\?>/,
    # Alternative syntax
    ~r/\[\[/,
    ~r/\]\]/
  ]

  @doc """
  Sanitizes a file path to prevent directory traversal attacks.

  Returns {:ok, sanitized_path} or {:error, reason}
  """
  def sanitize_path(path) when is_binary(path) do
    # Check for path traversal patterns
    if Enum.any?(@path_traversal_patterns, &Regex.match?(&1, path)) do
      {:error, "Path contains traversal patterns"}
    else
      # Normalize and expand the path
      normalized = Path.expand(path)

      # Additional checks
      cond do
        # Check for absolute paths that might escape the sandbox
        String.starts_with?(normalized, "/") and not allowed_absolute_path?(normalized) ->
          {:error, "Absolute paths not allowed"}

        # Check for special files
        is_special_file?(normalized) ->
          {:error, "Access to special files not allowed"}

        true ->
          {:ok, normalized}
      end
    end
  end

  def sanitize_path(_), do: {:error, "Path must be a string"}

  @doc """
  Sanitizes command arguments to prevent command injection.

  Returns {:ok, sanitized_args} or {:error, reason}
  """
  def sanitize_command(command) when is_binary(command) do
    if Enum.any?(@command_injection_patterns, &Regex.match?(&1, command)) do
      {:error, "Command contains dangerous characters"}
    else
      # Additional validation
      sanitized =
        command
        |> String.trim()
        |> validate_command_length()

      case sanitized do
        {:error, _} = error -> error
        cmd -> {:ok, cmd}
      end
    end
  end

  def sanitize_command(args) when is_list(args) do
    # Sanitize each argument individually
    results =
      Enum.map(args, fn arg ->
        if is_binary(arg) do
          sanitize_command(arg)
        else
          {:ok, to_string(arg)}
        end
      end)

    # Check if any failed
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        sanitized_args = Enum.map(results, fn {:ok, arg} -> arg end)
        {:ok, sanitized_args}

      error ->
        error
    end
  end

  def sanitize_command(_), do: {:error, "Command must be a string or list"}

  @doc """
  Sanitizes SQL parameters to prevent SQL injection.

  This is basic sanitization - prefer parameterized queries!
  """
  def sanitize_sql(value) when is_binary(value) do
    if Enum.any?(@sql_injection_patterns, &Regex.match?(&1, value)) do
      {:error, "Value contains SQL injection patterns"}
    else
      # Escape special characters
      sanitized =
        value
        # Escape single quotes
        |> String.replace("'", "''")
        # Escape backslashes
        |> String.replace("\\", "\\\\")

      {:ok, sanitized}
    end
  end

  def sanitize_sql(value) when is_number(value) do
    {:ok, value}
  end

  def sanitize_sql(value) when is_boolean(value) do
    {:ok, value}
  end

  def sanitize_sql(nil), do: {:ok, nil}
  def sanitize_sql(_), do: {:error, "Unsupported SQL value type"}

  @doc """
  Sanitizes template parameters to prevent template injection.

  Returns {:ok, sanitized_value} or {:error, reason}
  """
  def sanitize_template(value) when is_binary(value) do
    if Enum.any?(@template_injection_patterns, &Regex.match?(&1, value)) do
      {:error, "Value contains template injection patterns"}
    else
      # HTML escape as additional protection
      sanitized = html_escape(value)
      {:ok, sanitized}
    end
  end

  def sanitize_template(value) when is_number(value) or is_boolean(value) do
    {:ok, value}
  end

  def sanitize_template(nil), do: {:ok, nil}
  def sanitize_template(_), do: {:error, "Unsupported template value type"}

  @doc """
  Sanitizes all parameters based on their expected types.

  Accepts a map of param_name => {:type, value} and returns
  {:ok, sanitized_params} or {:error, {param_name, reason}}
  """
  def sanitize_params(params) when is_map(params) do
    results =
      Enum.map(params, fn {name, {type, value}} ->
        result =
          case type do
            :path -> sanitize_path(value)
            :command -> sanitize_command(value)
            :sql -> sanitize_sql(value)
            :template -> sanitize_template(value)
            :string -> sanitize_string(value)
            :number -> sanitize_number(value)
            :boolean -> sanitize_boolean(value)
            # Unknown types pass through
            _ -> {:ok, value}
          end

        case result do
          {:ok, sanitized} -> {name, sanitized}
          {:error, reason} -> {:error, {name, reason}}
        end
      end)

    # Check for errors
    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        sanitized_params = Map.new(results)
        {:ok, sanitized_params}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Validates that a string doesn't contain any dangerous patterns.

  This is a general-purpose sanitizer for string inputs.
  """
  def sanitize_string(value) when is_binary(value) do
    # Check length
    if String.length(value) > 10_000 do
      {:error, "String too long"}
    else
      # Remove null bytes and control characters
      sanitized =
        value
        |> String.replace(~r/\x00/, "")
        |> String.replace(~r/[\x01-\x08\x0B-\x0C\x0E-\x1F\x7F]/, "")

      {:ok, sanitized}
    end
  end

  def sanitize_string(value) do
    sanitize_string(to_string(value))
  end

  @doc """
  Validates and sanitizes numeric inputs.
  """
  def sanitize_number(value) when is_number(value) do
    # Check for infinity or NaN
    cond do
      is_float(value) and (value == :infinity or value == :neg_infinity or value != value) ->
        {:error, "Invalid numeric value"}

      true ->
        {:ok, value}
    end
  end

  def sanitize_number(value) when is_binary(value) do
    # Try to parse as number
    case Float.parse(value) do
      {num, ""} ->
        sanitize_number(num)

      _ ->
        case Integer.parse(value) do
          {num, ""} -> sanitize_number(num)
          _ -> {:error, "Invalid numeric value"}
        end
    end
  end

  def sanitize_number(_), do: {:error, "Value must be numeric"}

  @doc """
  Validates and sanitizes boolean inputs.
  """
  def sanitize_boolean(true), do: {:ok, true}
  def sanitize_boolean(false), do: {:ok, false}
  def sanitize_boolean("true"), do: {:ok, true}
  def sanitize_boolean("false"), do: {:ok, false}
  def sanitize_boolean("1"), do: {:ok, true}
  def sanitize_boolean("0"), do: {:ok, false}
  def sanitize_boolean(1), do: {:ok, true}
  def sanitize_boolean(0), do: {:ok, false}
  def sanitize_boolean(_), do: {:error, "Invalid boolean value"}

  # Helper functions

  defp allowed_absolute_path?(path) do
    # Define allowed absolute paths (e.g., /tmp, /var/tmp)
    allowed_prefixes = ["/tmp/", "/var/tmp/"]
    Enum.any?(allowed_prefixes, &String.starts_with?(path, &1))
  end

  defp is_special_file?(path) do
    # Check for special files that should never be accessed
    special_files = [
      "/etc/passwd",
      "/etc/shadow",
      "/proc/",
      "/sys/",
      "/dev/",
      ".bashrc",
      ".profile",
      ".ssh/",
      ".aws/",
      ".env"
    ]

    Enum.any?(special_files, fn special ->
      String.contains?(path, special)
    end)
  end

  defp validate_command_length(command) do
    if String.length(command) > 1000 do
      {:error, "Command too long"}
    else
      command
    end
  end

  defp html_escape(string) do
    string
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  @doc """
  Deep sanitization of nested data structures.

  Recursively sanitizes maps and lists.
  """
  def deep_sanitize(data, type \\ :string)

  def deep_sanitize(data, type) when is_map(data) do
    results =
      Enum.map(data, fn {k, v} ->
        case deep_sanitize(v, type) do
          {:ok, sanitized} -> {:ok, {k, sanitized}}
          error -> error
        end
      end)

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        sanitized_map = Map.new(Enum.map(results, fn {:ok, {k, v}} -> {k, v} end))
        {:ok, sanitized_map}

      error ->
        error
    end
  end

  def deep_sanitize(data, type) when is_list(data) do
    results = Enum.map(data, &deep_sanitize(&1, type))

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        sanitized_list = Enum.map(results, fn {:ok, v} -> v end)
        {:ok, sanitized_list}

      error ->
        error
    end
  end

  def deep_sanitize(data, type) do
    case type do
      :string -> sanitize_string(data)
      :path -> sanitize_path(data)
      :command -> sanitize_command(data)
      :sql -> sanitize_sql(data)
      :template -> sanitize_template(data)
      _ -> {:ok, data}
    end
  end
end
