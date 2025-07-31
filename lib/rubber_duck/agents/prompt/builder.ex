defmodule RubberDuck.Agents.Prompt.Builder do
  @moduledoc """
  Dynamic prompt construction engine.
  
  This module handles the construction of prompts from templates by:
  - Substituting variables with actual values
  - Applying conditional logic
  - Formatting for specific LLM providers
  - Optimizing for token efficiency
  - Injecting context-aware information
  """

  alias RubberDuck.Agents.Prompt.Template
  require Logger

  @type build_context :: %{
    provider: :openai | :anthropic | :local | nil,
    model: String.t() | nil,
    max_tokens: integer() | nil,
    context: map(),
    user_data: map(),
    system_info: map()
  }

  @type build_options :: %{
    optimize_tokens: boolean(),
    include_metadata: boolean(),
    strict_validation: boolean(),
    format_for_provider: boolean()
  }

  @doc """
  Builds a prompt from a template and context.
  
  ## Examples
  
      iex> template = %Template{
      ...>   content: "Analyze this {{language}} code: {{code}}",
      ...>   variables: [
      ...>     %{name: "language", type: :string, required: true},
      ...>     %{name: "code", type: :string, required: true}
      ...>   ]
      ...> }
      iex> context = %{
      ...>   provider: :openai,
      ...>   context: %{"language" => "Python", "code" => "print('hello')"}
      ...> }
      iex> RubberDuck.Agents.Prompt.Builder.build(template, context)
      {:ok, "Analyze this Python code: print('hello')"}
  """
  def build(%Template{} = template, context, opts \\ %{}) do
    opts = merge_default_options(opts)
    
    with {:ok, validated_context} <- validate_context(template, context, opts),
         {:ok, substituted_content} <- substitute_variables(template, validated_context),
         {:ok, processed_content} <- apply_conditionals(substituted_content, validated_context),
         {:ok, formatted_content} <- format_for_provider(processed_content, context, opts),
         {:ok, optimized_content} <- optimize_tokens(formatted_content, context, opts) do
      
      result = if opts.include_metadata do
        %{
          content: optimized_content,
          metadata: build_metadata(template, context, optimized_content)
        }
      else
        optimized_content
      end
      
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Validates that all required variables are provided in the context.
  """
  def validate_context(%Template{variables: variables}, context, opts) do
    context_vars = get_context_variables(context)
    
    missing_required = variables
    |> Enum.filter(& &1.required)
    |> Enum.map(& &1.name)
    |> Enum.reject(&Map.has_key?(context_vars, &1))
    
    if Enum.empty?(missing_required) do
      validated_context = if opts.strict_validation do
        validate_variable_types(variables, context_vars)
      else
        {:ok, context_vars}
      end
      
      case validated_context do
        {:ok, vars} -> {:ok, Map.put(context, :validated_vars, vars)}
        error -> error
      end
    else
      {:error, "Missing required variables: #{Enum.join(missing_required, ", ")}"}
    end
  end

  @doc """
  Substitutes template variables with actual values.
  
  Supports:
  - Simple substitution: {{variable}}
  - Default values: {{variable|default_value}}
  - Nested variables: {{user.name}}
  """
  def substitute_variables(%Template{content: content}, %{validated_vars: vars} = _context) do
    try do
      result = Regex.replace(~r/\{\{([^}]+)\}\}/, content, fn _, var_expr ->
        process_variable_expression(var_expr, vars)
      end)
      
      {:ok, result}
    rescue
      error ->
        Logger.error("Variable substitution failed: #{inspect(error)}")
        {:error, "Variable substitution failed: #{Exception.message(error)}"}
    end
  end

  @doc """
  Applies conditional logic in prompts.
  
  Supports:
  - If statements: {%if condition%}content{%endif%}
  - Unless statements: {%unless condition%}content{%endunless%}
  - For loops: {%for item in list%}{{item}}{%endfor%}
  """
  def apply_conditionals(content, context) do
    content
    |> process_if_statements(context)
    |> process_unless_statements(context)
    |> process_for_loops(context)
    |> case do
      {:ok, processed} -> {:ok, processed}
      {:error, reason} -> {:error, reason}
      processed when is_binary(processed) -> {:ok, processed}
    end
  end

  @doc """
  Formats prompt content for specific LLM providers.
  """
  def format_for_provider(content, %{provider: provider} = context, %{format_for_provider: true}) do
    case provider do
      :openai ->
        format_for_openai(content, context)
      :anthropic ->
        format_for_anthropic(content, context)
      :local ->
        format_for_local(content, context)
      _ ->
        {:ok, content}
    end
  end

  def format_for_provider(content, _context, _opts), do: {:ok, content}

  @doc """
  Optimizes prompt for token efficiency.
  """
  def optimize_tokens(content, context, %{optimize_tokens: true}) do
    content
    |> remove_excessive_whitespace()
    |> compress_repetitive_phrases()
    |> optimize_for_token_limit(context)
    |> case do
      {:ok, optimized} -> {:ok, optimized}
      optimized when is_binary(optimized) -> {:ok, optimized}
      error -> error
    end
  end

  def optimize_tokens(content, _context, _opts), do: {:ok, content}

  @doc """
  Estimates token count for the built prompt.
  """
  def estimate_tokens(content, provider \\ :openai) do
    # Simple estimation based on character count
    # In production, would use provider-specific tokenizers
    char_count = String.length(content)
    
    tokens = case provider do
      :openai -> div(char_count, 4)  # ~4 chars per token for GPT
      :anthropic -> div(char_count, 4)  # Similar to OpenAI
      :local -> div(char_count, 3)  # Local models might be less efficient
      _ -> div(char_count, 4)
    end
    
    {:ok, tokens}
  end

  # Private functions

  defp merge_default_options(opts) do
    defaults = %{
      optimize_tokens: false,
      include_metadata: false,
      strict_validation: true,
      format_for_provider: true
    }
    
    Map.merge(defaults, opts)
  end

  defp get_context_variables(%{context: context}) when is_map(context), do: context
  defp get_context_variables(%{validated_vars: vars}) when is_map(vars), do: vars
  defp get_context_variables(_), do: %{}

  defp validate_variable_types(variables, context_vars) do
    Enum.reduce_while(variables, {:ok, context_vars}, fn var, {:ok, acc} ->
      case Map.get(context_vars, var.name) do
        nil ->
          if var.required do
            {:halt, {:error, "Missing required variable: #{var.name}"}}
          else
            {:cont, {:ok, Map.put(acc, var.name, Map.get(var, :default))}}
          end
        value ->
          if valid_variable_type?(value, var.type) do
            {:cont, {:ok, acc}}
          else
            {:halt, {:error, "Invalid type for variable #{var.name}: expected #{var.type}, got #{typeof(value)}"}}
          end
      end
    end)
  end

  defp valid_variable_type?(value, :string), do: is_binary(value)
  defp valid_variable_type?(value, :integer), do: is_integer(value)
  defp valid_variable_type?(value, :float), do: is_float(value) or is_integer(value)
  defp valid_variable_type?(value, :boolean), do: is_boolean(value)
  defp valid_variable_type?(value, :list), do: is_list(value)
  defp valid_variable_type?(value, :map), do: is_map(value)
  defp valid_variable_type?(_value, _type), do: true

  defp typeof(value) when is_binary(value), do: :string
  defp typeof(value) when is_integer(value), do: :integer
  defp typeof(value) when is_float(value), do: :float
  defp typeof(value) when is_boolean(value), do: :boolean
  defp typeof(value) when is_list(value), do: :list
  defp typeof(value) when is_map(value), do: :map
  defp typeof(_value), do: :unknown

  defp process_variable_expression(var_expr, vars) do
    case String.split(var_expr, "|", parts: 2) do
      [var_name] ->
        var_name = String.trim(var_name)
        get_nested_value(vars, var_name) |> to_string()
      
      [var_name, default] ->
        var_name = String.trim(var_name)
        case get_nested_value(vars, var_name) do
          nil -> String.trim(default)
          value -> to_string(value)
        end
    end
  end

  defp get_nested_value(vars, var_name) do
    case String.split(var_name, ".") do
      [single_key] -> Map.get(vars, single_key)
      keys -> get_in(vars, keys)
    end
  end

  defp process_if_statements(content, context) do
    Regex.replace(~r/\{%\s*if\s+([^%]+)\s*%\}(.*?)\{%\s*endif\s*%\}/s, content, fn _, condition, content_block ->
      if evaluate_condition(condition, context) do
        content_block
      else
        ""
      end
    end)
  end

  defp process_unless_statements(content, context) do
    Regex.replace(~r/\{%\s*unless\s+([^%]+)\s*%\}(.*?)\{%\s*endunless\s*%\}/s, content, fn _, condition, content_block ->
      if evaluate_condition(condition, context) do
        ""
      else
        content_block
      end
    end)
  end

  defp process_for_loops(content, context) do
    Regex.replace(~r/\{%\s*for\s+(\w+)\s+in\s+([^%]+)\s*%\}(.*?)\{%\s*endfor\s*%\}/s, content, fn _, item_var, list_expr, content_block ->
      case get_nested_value(get_context_variables(context), String.trim(list_expr)) do
        items when is_list(items) ->
          Enum.map_join(items, "", fn item ->
            String.replace(content_block, "{{#{item_var}}}", to_string(item))
          end)
        _ ->
          ""
      end
    end)
  end

  defp evaluate_condition(condition, context) do
    vars = get_context_variables(context)
    condition = String.trim(condition)
    
    # Simple condition evaluation
    # In production, would use a proper expression parser
    cond do
      String.contains?(condition, "==") ->
        [left, right] = String.split(condition, "==", parts: 2)
        get_nested_value(vars, String.trim(left)) == String.trim(right, ~s("))
        
      String.contains?(condition, "!=") ->
        [left, right] = String.split(condition, "!=", parts: 2)
        get_nested_value(vars, String.trim(left)) != String.trim(right, ~s("))
        
      true ->
        # Treat as boolean variable
        case get_nested_value(vars, condition) do
          nil -> false
          false -> false
          "" -> false
          0 -> false
          _ -> true
        end
    end
  end

  defp format_for_openai(content, _context) do
    # OpenAI-specific formatting
    # Add system message formatting, handle function calls, etc.
    {:ok, content}
  end

  defp format_for_anthropic(content, _context) do
    # Anthropic-specific formatting
    # Handle Claude's specific formatting requirements
    {:ok, content}
  end

  defp format_for_local(content, _context) do
    # Local model formatting
    # Might need simpler formatting for local models
    {:ok, content}
  end

  defp remove_excessive_whitespace(content) do
    content
    |> String.replace(~r/\n\s*\n\s*\n/, "\n\n")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp compress_repetitive_phrases(content) do
    # Identify and compress repetitive phrases
    # This is a simplified implementation
    content
  end

  defp optimize_for_token_limit(content, %{max_tokens: max_tokens}) when is_integer(max_tokens) do
    case estimate_tokens(content) do
      {:ok, estimated_tokens} when estimated_tokens > max_tokens ->
        # Truncate content to fit within token limit
        # This is a simple implementation - in production would be more sophisticated
        char_limit = max_tokens * 4  # Rough estimation
        truncated = String.slice(content, 0, char_limit)
        {:ok, truncated <> "..."}
      
      {:ok, _} ->
        {:ok, content}
      
      error ->
        error
    end
  end

  defp optimize_for_token_limit(content, _context), do: {:ok, content}

  defp build_metadata(template, context, content) do
    %{
      template_id: template.id,
      template_version: template.version,
      provider: Map.get(context, :provider),
      model: Map.get(context, :model),
      content_length: String.length(content),
      estimated_tokens: case estimate_tokens(content, Map.get(context, :provider)) do
        {:ok, tokens} -> tokens
        _ -> nil
      end,
      built_at: DateTime.utc_now(),
      context_variables: Map.keys(get_context_variables(context))
    }
  end
end