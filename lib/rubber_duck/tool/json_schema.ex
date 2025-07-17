defmodule RubberDuck.Tool.JsonSchema do
  @moduledoc """
  Generates JSON Schema definitions from tool DSL definitions.
  
  This module can generate JSON Schema (draft-07) compatible schemas
  that can be used for validation, documentation, and API integration.
  """
  
  @doc """
  Generates a JSON Schema for a tool module.
  
  Returns a map representing the JSON Schema that can be used to validate
  parameters for the tool.
  """
  @spec generate(module()) :: map()
  def generate(module) do
    unless RubberDuck.Tool.is_tool?(module) do
      raise ArgumentError, "#{module} is not a valid tool module"
    end
    
    metadata = RubberDuck.Tool.metadata(module)
    parameters = RubberDuck.Tool.parameters(module)
    execution = RubberDuck.Tool.execution(module)
    security = RubberDuck.Tool.security(module)
    
    %{
      "$schema" => "http://json-schema.org/draft-07/schema#",
      "type" => "object",
      "title" => format_title(metadata.name),
      "description" => metadata.description,
      "version" => metadata.version,
      "properties" => build_properties(parameters),
      "required" => build_required(parameters),
      "metadata" => build_metadata(metadata, execution, security)
    }
  end
  
  @doc """
  Converts a tool schema to a JSON string.
  """
  @spec to_json(module()) :: String.t()
  def to_json(module) do
    module
    |> generate()
    |> Jason.encode!(pretty: true)
  end
  
  @doc """
  Exports a tool schema to a JSON file.
  """
  @spec to_file(module(), Path.t()) :: :ok | {:error, term()}
  def to_file(module, path) do
    json_content = to_json(module)
    File.write(path, json_content)
  end
  
  @doc """
  Generates schemas for multiple tools and exports them to a directory.
  """
  @spec export_all(Path.t(), [module()]) :: :ok | {:error, term()}
  def export_all(directory, modules) do
    with :ok <- File.mkdir_p(directory) do
      Enum.each(modules, fn module ->
        if RubberDuck.Tool.is_tool?(module) do
          metadata = RubberDuck.Tool.metadata(module)
          filename = "#{metadata.name}_v#{metadata.version}.json"
          path = Path.join(directory, filename)
          
          case to_file(module, path) do
            :ok -> :ok
            {:error, reason} -> 
              IO.puts("Failed to export #{module}: #{reason}")
          end
        end
      end)
    end
  end
  
  # Private functions
  
  defp format_title(name) do
    name
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
    |> Kernel.<>(" Tool")
  end
  
  defp build_properties(parameters) do
    parameters
    |> Enum.into(%{}, fn param ->
      {to_string(param.name), build_parameter_schema(param)}
    end)
  end
  
  defp build_parameter_schema(param) do
    base_schema = %{
      "description" => param.description
    }
    
    base_schema
    |> add_type(param.type)
    |> add_default(param.default)
    |> add_constraints(param.constraints || [])
  end
  
  defp add_type(schema, :string), do: Map.put(schema, "type", "string")
  defp add_type(schema, :integer), do: Map.put(schema, "type", "integer")
  defp add_type(schema, :float), do: Map.put(schema, "type", "number")
  defp add_type(schema, :boolean), do: Map.put(schema, "type", "boolean")
  defp add_type(schema, :list), do: Map.put(schema, "type", "array")
  defp add_type(schema, :map), do: Map.put(schema, "type", "object")
  defp add_type(schema, :any), do: schema  # No type restriction for 'any'
  
  defp add_default(schema, nil), do: schema
  defp add_default(schema, default), do: Map.put(schema, "default", default)
  
  defp add_constraints(schema, []), do: schema
  defp add_constraints(schema, constraints) do
    Enum.reduce(constraints, schema, fn {key, value}, acc ->
      add_constraint(acc, key, value, Map.get(schema, "type"))
    end)
  end
  
  # String constraints
  defp add_constraint(schema, :min_length, value, "string"), do: Map.put(schema, "minLength", value)
  defp add_constraint(schema, :max_length, value, "string"), do: Map.put(schema, "maxLength", value)
  defp add_constraint(schema, :pattern, value, _type), do: Map.put(schema, "pattern", value)
  defp add_constraint(schema, :enum, value, _type), do: Map.put(schema, "enum", value)
  
  # Numeric constraints
  defp add_constraint(schema, :min, value, _type), do: Map.put(schema, "minimum", value)
  defp add_constraint(schema, :max, value, _type), do: Map.put(schema, "maximum", value)
  defp add_constraint(schema, :exclusive_min, value, _type), do: Map.put(schema, "exclusiveMinimum", value)
  defp add_constraint(schema, :exclusive_max, value, _type), do: Map.put(schema, "exclusiveMaximum", value)
  
  # Array constraints - handle min_length/max_length for arrays
  defp add_constraint(schema, :min_items, value, _type), do: Map.put(schema, "minItems", value)
  defp add_constraint(schema, :max_items, value, _type), do: Map.put(schema, "maxItems", value)
  defp add_constraint(schema, :min_length, value, "array"), do: Map.put(schema, "minItems", value)
  defp add_constraint(schema, :max_length, value, "array"), do: Map.put(schema, "maxItems", value)
  defp add_constraint(schema, :unique_items, value, _type), do: Map.put(schema, "uniqueItems", value)
  
  # Object constraints
  defp add_constraint(schema, :min_properties, value, _type), do: Map.put(schema, "minProperties", value)
  defp add_constraint(schema, :max_properties, value, _type), do: Map.put(schema, "maxProperties", value)
  
  # Custom or unknown constraints - store as-is
  defp add_constraint(schema, key, value, _type) do
    Map.put(schema, to_string(key), value)
  end
  
  defp build_required(parameters) do
    parameters
    |> Enum.filter(& &1.required)
    |> Enum.map(&to_string(&1.name))
  end
  
  defp build_metadata(metadata, execution, security) do
    base_metadata = %{
      "name" => to_string(metadata.name),
      "category" => to_string(metadata.category),
      "version" => metadata.version,
      "tags" => Enum.map(metadata.tags || [], &to_string/1)
    }
    
    base_metadata
    |> add_execution_metadata(execution)
    |> add_security_metadata(security)
  end
  
  defp add_execution_metadata(metadata, nil), do: metadata
  defp add_execution_metadata(metadata, execution) do
    execution_data = %{
      "timeout" => execution.timeout,
      "async" => execution.async,
      "retries" => execution.retries
    }
    
    Map.put(metadata, "execution", execution_data)
  end
  
  defp add_security_metadata(metadata, nil), do: metadata
  defp add_security_metadata(metadata, security) do
    security_data = %{
      "sandbox" => to_string(security.sandbox),
      "capabilities" => Enum.map(security.capabilities || [], &to_string/1)
    }
    
    security_data = if security.rate_limit do
      Map.put(security_data, "rate_limit", security.rate_limit)
    else
      security_data
    end
    
    Map.put(metadata, "security", security_data)
  end
end