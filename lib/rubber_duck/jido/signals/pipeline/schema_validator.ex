defmodule RubberDuck.Jido.Signals.Pipeline.SchemaValidator do
  @moduledoc """
  Validates signals against defined schemas.
  
  This transformer enforces schema compliance for signal data,
  ensuring type safety and structural consistency. Supports
  versioned schemas and custom validation rules.
  """
  
  use RubberDuck.Jido.Signals.Pipeline.SignalTransformer,
    name: "SchemaValidator",
    priority: 80  # Run after enricher
  
  @impl true
  def transform(signal, opts) do
    schema_registry = Keyword.get(opts, :schema_registry, default_schemas())
    strict_mode = Keyword.get(opts, :strict, false)
    
    with {:ok, schema} <- find_schema(signal, schema_registry),
         {:ok, validated} <- validate_against_schema(signal, schema, strict_mode) do
      {:ok, mark_as_validated(validated, schema)}
    else
      {:error, :no_schema} when not strict_mode ->
        # In non-strict mode, pass through without validation
        {:ok, signal}
      error ->
        error
    end
  end
  
  @impl true
  def should_transform?(signal, opts) do
    # Skip if already validated
    not Map.get(signal, :_schema_validated, false) or
      Keyword.get(opts, :force_validation, false)
  end
  
  # Private functions
  
  defp find_schema(signal, registry) do
    signal_type = Map.get(signal, :type)
    schema_version = get_in(signal, [:extensions, "schemaversion"]) || "1.0"
    
    schema_key = {signal_type, schema_version}
    
    case Map.get(registry, schema_key) || Map.get(registry, {signal_type, "*"}) do
      nil -> {:error, :no_schema}
      schema -> {:ok, schema}
    end
  end
  
  defp validate_against_schema(signal, schema, strict_mode) do
    errors = []
      |> validate_required_fields(signal, schema)
      |> validate_field_types(signal, schema)
      |> validate_field_constraints(signal, schema)
      |> validate_data_schema(signal, schema)
    
    if Enum.empty?(errors) do
      {:ok, signal}
    else
      if strict_mode do
        {:error, {:validation_failed, errors}}
      else
        # Log warnings but continue
        Logger.warning("Schema validation warnings: #{inspect(errors)}")
        {:ok, add_validation_warnings(signal, errors)}
      end
    end
  end
  
  defp validate_required_fields(errors, signal, schema) do
    required = Map.get(schema, :required_fields, [])
    
    missing = Enum.filter(required, fn field ->
      not has_field?(signal, field)
    end)
    
    if Enum.empty?(missing) do
      errors
    else
      [{:missing_required_fields, missing} | errors]
    end
  end
  
  defp validate_field_types(errors, signal, schema) do
    field_types = Map.get(schema, :field_types, %{})
    
    type_errors = Enum.reduce(field_types, [], fn {field, expected_type}, acc ->
      case get_field(signal, field) do
        nil -> acc
        value ->
          if matches_type?(value, expected_type) do
            acc
          else
            [{:type_mismatch, field, expected_type, type_of(value)} | acc]
          end
      end
    end)
    
    errors ++ type_errors
  end
  
  defp validate_field_constraints(errors, signal, schema) do
    constraints = Map.get(schema, :field_constraints, %{})
    
    constraint_errors = Enum.reduce(constraints, [], fn {field, constraint}, acc ->
      case get_field(signal, field) do
        nil -> acc
        value ->
          case validate_constraint(value, constraint) do
            :ok -> acc
            {:error, reason} -> [{:constraint_violation, field, reason} | acc]
          end
      end
    end)
    
    errors ++ constraint_errors
  end
  
  defp validate_data_schema(errors, signal, schema) do
    data_schema = Map.get(schema, :data_schema)
    
    if data_schema && Map.has_key?(signal, :data) do
      validate_nested_schema(errors, signal.data, data_schema, "data")
    else
      errors
    end
  end
  
  defp validate_nested_schema(errors, data, schema, path) when is_map(data) and is_map(schema) do
    Enum.reduce(schema, errors, fn {key, spec}, acc ->
      value = Map.get(data, key) || Map.get(data, to_string(key))
      field_path = "#{path}.#{key}"
      
      cond do
        is_map(spec) && Map.has_key?(spec, :type) ->
          # Field specification
          validate_field_spec(acc, value, spec, field_path)
          
        is_map(spec) && is_map(value) ->
          # Nested object
          validate_nested_schema(acc, value, spec, field_path)
          
        true ->
          acc
      end
    end)
  end
  defp validate_nested_schema(errors, _, _, _), do: errors
  
  defp validate_field_spec(errors, value, spec, path) do
    # Check required
    if Map.get(spec, :required, false) && is_nil(value) do
      [{:missing_required, path} | errors]
    else
      # Check type
      expected_type = Map.get(spec, :type)
      if not is_nil(value) && not matches_type?(value, expected_type) do
        [{:type_mismatch, path, expected_type, type_of(value)} | errors]
      else
        # Check constraints
        case Map.get(spec, :constraint) do
          nil -> errors
          constraint ->
            case validate_constraint(value, constraint) do
              :ok -> errors
              {:error, reason} -> [{:constraint_violation, path, reason} | errors]
            end
        end
      end
    end
  end
  
  defp has_field?(signal, field) when is_atom(field) do
    Map.has_key?(signal, field) || Map.has_key?(signal, Atom.to_string(field))
  end
  defp has_field?(signal, field) when is_binary(field) do
    Map.has_key?(signal, field) || Map.has_key?(signal, String.to_atom(field))
  end
  
  defp get_field(signal, field) when is_atom(field) do
    Map.get(signal, field) || Map.get(signal, Atom.to_string(field))
  end
  defp get_field(signal, field) when is_binary(field) do
    Map.get(signal, field) || Map.get(signal, String.to_atom(field))
  end
  
  defp matches_type?(value, :string), do: is_binary(value)
  defp matches_type?(value, :integer), do: is_integer(value)
  defp matches_type?(value, :float), do: is_float(value)
  defp matches_type?(value, :number), do: is_number(value)
  defp matches_type?(value, :boolean), do: is_boolean(value)
  defp matches_type?(value, :map), do: is_map(value)
  defp matches_type?(value, :list), do: is_list(value)
  defp matches_type?(value, :atom), do: is_atom(value)
  defp matches_type?(value, :any), do: true
  defp matches_type?(value, {:list, item_type}) do
    is_list(value) && Enum.all?(value, &matches_type?(&1, item_type))
  end
  defp matches_type?(_, _), do: false
  
  defp type_of(value) when is_binary(value), do: :string
  defp type_of(value) when is_integer(value), do: :integer
  defp type_of(value) when is_float(value), do: :float
  defp type_of(value) when is_boolean(value), do: :boolean
  defp type_of(value) when is_map(value), do: :map
  defp type_of(value) when is_list(value), do: :list
  defp type_of(value) when is_atom(value), do: :atom
  defp type_of(_), do: :unknown
  
  defp validate_constraint(value, {:min_length, min}) when is_binary(value) do
    if String.length(value) >= min, do: :ok, else: {:error, "too short"}
  end
  defp validate_constraint(value, {:max_length, max}) when is_binary(value) do
    if String.length(value) <= max, do: :ok, else: {:error, "too long"}
  end
  defp validate_constraint(value, {:min, min}) when is_number(value) do
    if value >= min, do: :ok, else: {:error, "below minimum"}
  end
  defp validate_constraint(value, {:max, max}) when is_number(value) do
    if value <= max, do: :ok, else: {:error, "above maximum"}
  end
  defp validate_constraint(value, {:regex, pattern}) when is_binary(value) do
    if Regex.match?(pattern, value), do: :ok, else: {:error, "pattern mismatch"}
  end
  defp validate_constraint(value, {:in, values}) do
    if value in values, do: :ok, else: {:error, "not in allowed values"}
  end
  defp validate_constraint(_, _), do: :ok
  
  defp mark_as_validated(signal, schema) do
    signal
    |> Map.put(:_schema_validated, true)
    |> Map.put(:_schema_version, Map.get(schema, :version, "1.0"))
    |> Map.put(:_validated_at, DateTime.utc_now())
  end
  
  defp add_validation_warnings(signal, warnings) do
    Map.put(signal, :_validation_warnings, warnings)
  end
  
  defp default_schemas do
    %{
      # Example schemas for common signal types
      {"user.created", "1.0"} => %{
        required_fields: [:type, :source, :data],
        field_types: %{
          type: :string,
          source: :string,
          data: :map
        },
        data_schema: %{
          user_id: %{type: :string, required: true},
          email: %{type: :string, required: true, constraint: {:regex, ~r/@/}},
          name: %{type: :string, required: false, constraint: {:min_length, 1}}
        }
      },
      {"analysis.request", "1.0"} => %{
        required_fields: [:type, :source, :data],
        field_types: %{
          type: :string,
          source: :string,
          data: :map
        },
        data_schema: %{
          file_path: %{type: :string, required: true},
          analysis_types: %{type: {:list, :string}, required: false}
        }
      }
    }
  end
end