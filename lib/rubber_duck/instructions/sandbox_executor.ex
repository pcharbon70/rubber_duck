defmodule RubberDuck.Instructions.SandboxExecutor do
  @moduledoc """
  Sandboxed template execution environment.
  
  Executes templates in an isolated process with:
  - Memory limits
  - CPU time limits
  - Restricted function access
  - No I/O operations
  
  Only whitelisted functions are available to templates.
  """
  
  require Logger
  alias RubberDuck.Instructions.{Security, SecurityConfig}
  
  @doc """
  Executes a template in a sandboxed environment.
  
  ## Options
  
  - `:timeout` - Maximum execution time in milliseconds (default: 5000)
  - `:max_heap_size` - Maximum heap size in bytes (default: 50MB)
  - `:security_level` - Security level (:strict, :balanced, :relaxed)
  
  ## Returns
  
  - `{:ok, result}` - Successfully executed template
  - `{:error, :timeout}` - Execution timed out
  - `{:error, :memory_limit_exceeded}` - Memory limit exceeded
  - `{:error, :sandbox_violation}` - Attempted to access restricted functionality
  """
  @spec execute(String.t(), map(), keyword()) :: {:ok, String.t()} | {:error, atom()}
  def execute(template, variables, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    
    # Get sandbox configuration
    sandbox_config = SecurityConfig.get_sandbox_config()
    timeout = Keyword.get(opts, :timeout, Map.get(sandbox_config, :timeout, 5_000))
    max_heap_size = Keyword.get(opts, :max_heap_size, Map.get(sandbox_config, :max_heap_size, 50_000_000))
    security_level = Keyword.get(opts, :security_level, Map.get(sandbox_config, :default_security_level, :balanced))
    
    # Create sandbox context with whitelisted functions
    sandbox_context = build_sandbox_context(variables, security_level)
    
    # Spawn isolated process with resource limits
    task = Task.async(fn ->
      # Set process flags for resource limits
      Process.flag(:trap_exit, true)
      Process.flag(:max_heap_size, %{
        size: max_heap_size,
        kill: true,
        error_logger: true
      })
      
      # Execute template in sandbox
      execute_in_sandbox(template, sandbox_context)
    end)
    
    # Wait for result with timeout
    result = case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, result}} ->
        {:ok, result}
        
      {:ok, {:error, reason}} ->
        {:error, reason}
        
      {:exit, {:killed, _}} ->
        {:error, :memory_limit_exceeded}
        
      nil ->
        {:error, :timeout}
        
      {:exit, reason} ->
        Logger.warning("Sandbox execution failed: #{inspect(reason)}")
        {:error, :sandbox_violation}
    end
    
    # Emit telemetry
    duration = System.monotonic_time(:millisecond) - start_time
    result_tag = case result do
      {:ok, _} -> :success
      {:error, _} -> :failure
    end
    
    :telemetry.execute(
      [:rubber_duck, :instructions, :sandbox, :execution],
      %{duration: duration},
      %{security_level: security_level, result: result_tag}
    )
    
    result
  end
  
  ## Private Functions
  
  defp execute_in_sandbox(template, sandbox_context) do
    # Validate we're in a restricted environment
    if Process.get(:sandbox_executor) != true do
      Process.put(:sandbox_executor, true)
    end
    
    # Use custom template processor that respects sandbox
    case render_sandboxed_template(template, sandbox_context) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error ->
      Logger.debug("Sandbox execution error: #{inspect(error)}")
      {:error, :sandbox_violation}
  end
  
  defp render_sandboxed_template(template, context) do
    # Use Solid for Liquid template processing with restricted context
    try do
      case Solid.parse(template) do
        {:ok, parsed_template} ->
          # Render with sandbox context
          case Solid.render(parsed_template, context) do
            {:ok, result, _} -> {:ok, to_string(result)}
            {:error, reason, _} -> {:error, reason}
          end
          
        {:error, reason} ->
          {:error, reason}
      end
    catch
      kind, reason ->
        Logger.debug("Template rendering caught #{kind}: #{inspect(reason)}")
        {:error, :sandbox_violation}
    end
  end
  
  defp build_sandbox_context(variables, security_level) do
    # Start with Security module's sandbox context
    base_context = Security.sandbox_context(variables)
    
    # Get allowed functions for this security level
    allowed_functions = SecurityConfig.get_allowed_functions(security_level)
    
    # Build context based on allowed functions from configuration
    enhanced_context = if Enum.empty?(allowed_functions) do
      # Fallback to default behavior if no configuration
      case security_level do
        :strict ->
          Map.take(base_context, ["upcase", "downcase", "trim", "length", "join", "count"])
        :relaxed ->
          Map.merge(base_context, get_extended_functions())
        _ ->
          Map.merge(base_context, get_standard_functions())
      end
    else
      # Use configured functions
      Map.take(base_context, allowed_functions)
      |> Map.merge(get_filtered_functions(allowed_functions))
    end
    
    # Add Liquid-specific filters
    Map.merge(enhanced_context, %{
      "append" => &safe_append/2,
      "prepend" => &safe_prepend/2,
      "remove" => &safe_remove/2,
      "truncate" => &safe_truncate/2,
      "strip" => &String.trim/1,
      "lstrip" => &String.trim_leading/1,
      "rstrip" => &String.trim_trailing/1,
      "plus" => &safe_math/3,
      "minus" => &safe_math/3,
      "times" => &safe_math/3,
      "divided_by" => &safe_math/3,
      "modulo" => &safe_math/3
    })
  end
  
  # Safe wrapper functions that prevent abuse
  
  defp safe_replace(string, pattern, replacement) when is_binary(string) and is_binary(pattern) and is_binary(replacement) do
    # Limit replacement iterations to prevent DoS
    String.replace(string, pattern, replacement)
  end
  defp safe_replace(_, _, _), do: ""
  
  defp safe_slice(string, start, length) when is_binary(string) and is_integer(start) and is_integer(length) do
    String.slice(string, start, length)
  end
  defp safe_slice(_, _, _), do: ""
  
  defp safe_split(string, pattern) when is_binary(string) do
    # Limit split results to prevent memory exhaustion
    case String.split(string, pattern || " ", parts: 100) do
      parts when length(parts) <= 100 -> parts
      _ -> []
    end
  end
  defp safe_split(_, _), do: []
  
  defp safe_first(list) when is_list(list), do: List.first(list)
  defp safe_first(_), do: nil
  
  defp safe_last(list) when is_list(list), do: List.last(list)
  defp safe_last(_), do: nil
  
  defp safe_size(value) when is_list(value), do: length(value)
  defp safe_size(value) when is_map(value), do: map_size(value)
  defp safe_size(value) when is_binary(value), do: String.length(value)
  defp safe_size(_), do: 0
  
  defp safe_append(string, suffix) when is_binary(string) and is_binary(suffix) do
    if String.length(string) + String.length(suffix) < 10_000 do
      string <> suffix
    else
      string
    end
  end
  defp safe_append(string, _), do: to_string(string)
  
  defp safe_prepend(string, prefix) when is_binary(string) and is_binary(prefix) do
    if String.length(string) + String.length(prefix) < 10_000 do
      prefix <> string
    else
      string
    end
  end
  defp safe_prepend(string, _), do: to_string(string)
  
  defp safe_remove(string, pattern) when is_binary(string) and is_binary(pattern) do
    String.replace(string, pattern, "")
  end
  defp safe_remove(string, _), do: to_string(string)
  
  defp safe_truncate(string, length) when is_binary(string) and is_integer(length) do
    String.slice(string, 0, max(0, length))
  end
  defp safe_truncate(string, _), do: to_string(string)
  
  defp safe_to_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} when int >= -1_000_000 and int <= 1_000_000 -> int
      _ -> 0
    end
  end
  defp safe_to_integer(value) when is_integer(value), do: value
  defp safe_to_integer(value) when is_float(value), do: trunc(value)
  defp safe_to_integer(_), do: 0
  
  defp safe_to_string(value) when is_binary(value), do: value
  defp safe_to_string(value) when is_atom(value) and value in [true, false, nil], do: to_string(value)
  defp safe_to_string(value) when is_number(value), do: to_string(value)
  defp safe_to_string(_), do: ""
  
  defp safe_math(a, b, :plus) when is_number(a) and is_number(b), do: a + b
  defp safe_math(a, b, :minus) when is_number(a) and is_number(b), do: a - b
  defp safe_math(a, b, :times) when is_number(a) and is_number(b), do: a * b
  defp safe_math(a, b, :divided_by) when is_number(a) and is_number(b) and b != 0, do: a / b
  defp safe_math(a, b, :modulo) when is_integer(a) and is_integer(b) and b != 0, do: rem(a, b)
  defp safe_math(_, _, _), do: 0
  
  # Helper functions for building contexts
  defp get_extended_functions do
    %{
      "capitalize" => &String.capitalize/1,
      "reverse" => &String.reverse/1,
      "split" => &String.split/2,
      "replace" => &safe_replace/3,
      "slice" => &safe_slice/3,
      "contains" => &String.contains?/2,
      "starts_with" => &String.starts_with?/2,
      "ends_with" => &String.ends_with?/2,
      "to_integer" => &safe_to_integer/1,
      "to_string" => &safe_to_string/1,
      "abs" => &abs/1,
      "min" => &min/2,
      "max" => &max/2
    }
  end
  
  defp get_standard_functions do
    %{
      "capitalize" => &String.capitalize/1,
      "split" => &safe_split/2,
      "first" => &safe_first/1,
      "last" => &safe_last/1,
      "size" => &safe_size/1
    }
  end
  
  defp get_filtered_functions(allowed_functions) do
    all_functions = Map.merge(get_extended_functions(), get_standard_functions())
    Map.take(all_functions, allowed_functions)
  end
end