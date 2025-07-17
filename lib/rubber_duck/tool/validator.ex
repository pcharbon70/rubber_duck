defmodule RubberDuck.Tool.Validator do
  @moduledoc """
  Validates tool parameters using JSON Schema and custom validation rules.
  
  This module provides comprehensive parameter validation for tools defined
  with the RubberDuck.Tool DSL, including JSON Schema validation and custom
  constraint validation.
  """
  
  @doc """
  Validates parameters against a tool's parameter definitions.
  
  ## Options
  
  - `:partial` - If true, only validates provided fields and ignores missing required fields
  
  ## Examples
  
      iex> Validator.validate_parameters(MyTool, %{name: "john", age: 25})
      {:ok, %{name: "john", age: 25}}
      
      iex> Validator.validate_parameters(MyTool, %{name: "a"})
      {:error, [%{field: :name, type: :min_length, message: "...", suggestion: "..."}]}
  """
  @spec validate_parameters(module(), map(), keyword()) :: {:ok, map()} | {:error, [map()]}
  def validate_parameters(tool_module, params, opts \\ []) do
    partial = Keyword.get(opts, :partial, false)
    
    # Do custom validation first (handles partial mode properly)
    case validate_custom_constraints(tool_module, params, partial) do
      {:ok, validated_params} ->
        # If custom validation passes, optionally run schema validation
        # Skip schema validation in partial mode since it doesn't handle it well
        if partial do
          {:ok, validated_params}
        else
          case get_validation_schema(tool_module) do
            {:ok, schema} ->
              case validate_against_schema(validated_params, schema) do
                {:ok, _} -> {:ok, validated_params}
                {:error, schema_errors} -> {:error, schema_errors}
              end
            {:error, _} ->
              # If schema generation fails, fall back to custom validation only
              {:ok, validated_params}
          end
        end
      
      {:error, errors} ->
        {:error, errors}
    end
  end
  
  @doc """
  Validates parameters against a JSON Schema.
  
  ## Examples
  
      iex> schema = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}
      iex> Validator.validate_against_schema(%{"name" => "john"}, schema)
      {:ok, %{"name" => "john"}}
  """
  @spec validate_against_schema(map(), map()) :: {:ok, map()} | {:error, term()}
  def validate_against_schema(params, schema) do
    # Convert atom keys to strings for JSON Schema validation
    string_params = convert_keys_to_strings(params)
    
    case ExJsonSchema.Validator.validate(schema, string_params) do
      :ok ->
        {:ok, params}
      {:error, errors} ->
        validation_errors = Enum.map(errors, &format_schema_error/1)
        {:error, validation_errors}
    end
  end
  
  @doc """
  Gets the validation schema for a tool module.
  
  This combines the JSON Schema generated from the tool DSL with any
  additional validation rules.
  """
  @spec get_validation_schema(module()) :: {:ok, map()} | {:error, term()}
  def get_validation_schema(tool_module) do
    unless RubberDuck.Tool.is_tool?(tool_module) do
      {:error, :invalid_tool}
    else
      try do
        schema = RubberDuck.Tool.JsonSchema.generate(tool_module)
        {:ok, schema}
      rescue
        error ->
          {:error, {:schema_generation_failed, error}}
      end
    end
  end
  
  # Private functions
  
  defp validate_custom_constraints(tool_module, params, partial) do
    parameters = RubberDuck.Tool.parameters(tool_module)
    errors = []
    
    # Validate each parameter
    errors = Enum.reduce(parameters, errors, fn param, acc ->
      case validate_parameter(param, params, partial) do
        :ok -> acc
        {:error, error} -> [error | acc]
      end
    end)
    
    if Enum.empty?(errors) do
      {:ok, params}
    else
      {:error, Enum.reverse(errors)}
    end
  end
  
  defp validate_parameter(param, params, partial) do
    param_name = param.name
    param_value = Map.get(params, param_name)
    
    cond do
      # Required parameter missing
      param.required and is_nil(param_value) and not partial ->
        {:error, build_error(param_name, :required, "is required", "provide a value for #{param_name}")}
      
      # Parameter not provided (optional or partial mode)
      is_nil(param_value) ->
        :ok
      
      # Parameter provided, validate it
      true ->
        validate_parameter_value(param, param_value)
    end
  end
  
  defp validate_parameter_value(param, value) do
    with :ok <- validate_type(param, value),
         :ok <- validate_constraints(param, value) do
      :ok
    else
      {:error, error} -> {:error, error}
    end
  end
  
  defp validate_type(param, value) do
    case {param.type, value} do
      {:string, value} when is_binary(value) -> :ok
      {:integer, value} when is_integer(value) -> :ok
      {:float, value} when is_float(value) -> :ok
      {:boolean, value} when is_boolean(value) -> :ok
      {:list, value} when is_list(value) -> :ok
      {:map, value} when is_map(value) -> :ok
      {:any, _value} -> :ok
      _ ->
        expected_type = param.type |> to_string() |> String.capitalize()
        {:error, build_error(param.name, :type_mismatch, 
                           "must be of type #{expected_type}", 
                           "provide a valid #{expected_type} value")}
    end
  end
  
  defp validate_constraints(param, value) do
    constraints = param.constraints || []
    
    Enum.reduce_while(constraints, :ok, fn {constraint, constraint_value}, _acc ->
      case validate_constraint(param, value, constraint, constraint_value) do
        :ok -> {:cont, :ok}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
  
  defp validate_constraint(param, value, constraint, constraint_value) do
    case {constraint, param.type, value} do
      # String constraints
      {:min_length, :string, value} when byte_size(value) < constraint_value ->
        {:error, build_error(param.name, :min_length, 
                           "must be at least #{constraint_value} characters", 
                           "provide a name with at least #{constraint_value} characters")}
      
      {:max_length, :string, value} when byte_size(value) > constraint_value ->
        {:error, build_error(param.name, :max_length, 
                           "must be at most #{constraint_value} characters", 
                           "provide a name with at most #{constraint_value} characters")}
      
      {:pattern, :string, value} ->
        case Regex.compile(constraint_value) do
          {:ok, regex} ->
            if Regex.match?(regex, value) do
              :ok
            else
              {:error, build_error(param.name, :pattern, 
                                 "does not match the required pattern", 
                                 "provide a value matching the pattern: #{constraint_value}")}
            end
          {:error, _} ->
            {:error, build_error(param.name, :invalid_pattern, 
                               "invalid pattern constraint", 
                               "contact support about invalid pattern")}
        end
      
      # Numeric constraints
      {:min, type, value} when type in [:integer, :float] and value < constraint_value ->
        {:error, build_error(param.name, :min, 
                           "must be at least #{constraint_value}", 
                           "provide an #{param.name} between #{constraint_value} and #{get_max_constraint(param)}")}
      
      {:max, type, value} when type in [:integer, :float] and value > constraint_value ->
        {:error, build_error(param.name, :max, 
                           "must be at most #{constraint_value}", 
                           "provide an #{param.name} between #{get_min_constraint(param)} and #{constraint_value}")}
      
      # List constraints
      {:min_length, :list, value} when length(value) < constraint_value ->
        {:error, build_error(param.name, :min_length, 
                           "must contain at least #{constraint_value} items", 
                           "provide a list with at least #{constraint_value} items")}
      
      {:max_length, :list, value} when length(value) > constraint_value ->
        {:error, build_error(param.name, :max_length, 
                           "must contain at most #{constraint_value} items", 
                           "provide a list with at most #{constraint_value} items")}
      
      # Enum constraints
      {:enum, _type, value} ->
        if value in constraint_value do
          :ok
        else
          enum_options = Enum.join(constraint_value, ", ")
          {:error, build_error(param.name, :enum, 
                             "must be one of: #{enum_options}", 
                             "Use one of: #{enum_options}")}
        end
      
      # Unknown or valid constraints
      _ ->
        :ok
    end
  end
  
  defp build_error(field, type, message, suggestion) do
    %{
      field: field,
      type: type,
      message: "#{field} #{message}",
      suggestion: suggestion
    }
  end
  
  defp get_min_constraint(param) do
    param.constraints
    |> Enum.find_value(fn {key, value} -> 
      if key == :min, do: value, else: nil 
    end) || 0
  end
  
  defp get_max_constraint(param) do
    param.constraints
    |> Enum.find_value(fn {key, value} -> 
      if key == :max, do: value, else: nil 
    end) || "∞"
  end
  
  defp convert_keys_to_strings(map) when is_map(map) do
    map
    |> Enum.into(%{}, fn {k, v} -> {to_string(k), v} end)
  end
  
  defp format_schema_error(error) do
    # Format ExJsonSchema errors into our error format
    # ExJsonSchema returns errors as {message, path} tuples
    {message, path} = if is_tuple(error) do
      error
    else
      {error, "#"}
    end
    
    # Extract field name from path (e.g., "#/name" -> "name")
    field = case path do
      "#/" <> field_name -> String.to_atom(field_name)
      "#" -> :root
      _ -> :unknown
    end
    
    %{
      field: field,
      type: :schema_validation,
      message: message || "validation failed",
      suggestion: "check the parameter format and try again"
    }
  end
end