defmodule RubberDuck.Tool.ExternalAdapter do
  @moduledoc """
  Adapter for exposing internal tools to external services.
  
  This module provides functionality to:
  - Convert tool metadata to external formats
  - Transform parameters between internal and external schemas
  - Route execution calls through the tool system
  - Stream results back to external clients
  """
  
  alias RubberDuck.Tool
  alias RubberDuck.Tool.{Registry, Executor, Validator}
  # alias RubberDuck.Tool.SchemaGenerator
  
  require Logger
  
  @doc """
  Converts internal tool metadata to external format.
  
  Supports multiple output formats for different external services.
  """
  def convert_metadata(tool_module, format \\ :openapi) do
    metadata = Tool.metadata(tool_module)
    # In a real implementation, this would use SchemaGenerator
    # For now, we'll use a simple schema based on parameters
    schema = build_simple_schema(tool_module)
    
    case format do
      :openapi -> to_openapi_format(metadata, schema, tool_module)
      :anthropic -> to_anthropic_format(metadata, schema, tool_module)
      :openai -> to_openai_format(metadata, schema, tool_module)
      :langchain -> to_langchain_format(metadata, schema, tool_module)
      _ -> {:error, :unsupported_format}
    end
  end
  
  @doc """
  Generates tool descriptions suitable for LLM consumption.
  """
  def generate_description(tool_module) do
    metadata = Tool.metadata(tool_module)
    params = Tool.parameters(tool_module)
    
    %{
      name: metadata.name,
      description: build_detailed_description(metadata, params),
      parameters: build_parameter_descriptions(params),
      examples: get_tool_examples(tool_module)
    }
  end
  
  @doc """
  Maps external parameters to internal tool format.
  """
  def map_parameters(tool_module, external_params, source_format \\ :json) do
    params = Tool.parameters(tool_module)
    
    mapped = Enum.reduce(params, %{}, fn param, acc ->
      external_key = param[:external_name] || to_string(param.name)
      internal_key = param.name
      
      case Map.get(external_params, external_key) do
        nil -> 
          if param[:required] do
            throw {:missing_required_param, internal_key}
          else
            acc
          end
        value ->
          Map.put(acc, internal_key, transform_value(value, param, source_format))
      end
    end)
    
    {:ok, mapped}
  catch
    {:missing_required_param, param} ->
      {:error, "Missing required parameter: #{param}"}
  end
  
  @doc """
  Converts internal tool results to external response format.
  """
  def convert_result(result, _tool_module, format \\ :json) do
    case format do
      :json -> 
        Jason.encode(standardize_result(result))
      
      :xml ->
        to_xml(standardize_result(result))
        
      :protobuf ->
        {:error, :not_implemented}
        
      _ ->
        {:error, :unsupported_format}
    end
  end
  
  @doc """
  Routes external tool calls through the internal execution system.
  """
  def execute(tool_name, external_params, context, opts \\ []) do
    with {:ok, tool_module} <- Registry.get(tool_name),
         {:ok, params} <- map_parameters(tool_module, external_params),
         {:ok, validated_params} <- Validator.validate_parameters(tool_module, params),
         {:ok, result} <- Executor.execute(tool_module, validated_params, context, opts) do
      
      format = Keyword.get(opts, :response_format, :json)
      convert_result(result, tool_module, format)
    end
  end
  
  @doc """
  Executes a tool asynchronously with progress streaming.
  """
  def execute_async(tool_name, external_params, context, opts \\ []) do
    task = Task.async(fn ->
      execute(tool_name, external_params, context, opts)
    end)
    
    # Return task reference for tracking
    {:ok, task}
  end
  
  @doc """
  Lists all available tools in external format.
  """
  def list_tools(format \\ :summary) do
    tools = Registry.list()
    
    case format do
      :summary ->
        Enum.map(tools, &tool_summary/1)
      
      :detailed ->
        Enum.map(tools, fn tool_module ->
          case convert_metadata(tool_module, :openapi) do
            {:ok, metadata} -> metadata
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        
      :names ->
        Enum.map(tools, fn tool_module ->
          Tool.metadata(tool_module).name
        end)
    end
  end
  
  # Private functions
  
  defp to_openapi_format(metadata, schema, tool_module) do
    operation = %{
      "operationId" => to_string(metadata.name),
      "summary" => metadata.description,
      "description" => metadata.long_description || metadata.description,
      "tags" => [metadata.category || "tools"],
      "parameters" => build_openapi_parameters(tool_module),
      "requestBody" => build_openapi_request_body(schema),
      "responses" => build_openapi_responses(tool_module)
    }
    
    {:ok, operation}
  end
  
  defp to_anthropic_format(metadata, schema, _tool_module) do
    tool_spec = %{
      "name" => to_string(metadata.name),
      "description" => metadata.description,
      "input_schema" => schema
    }
    
    {:ok, tool_spec}
  end
  
  defp to_openai_format(metadata, schema, _tool_module) do
    function_spec = %{
      "name" => to_string(metadata.name),
      "description" => metadata.description,
      "parameters" => schema
    }
    
    {:ok, function_spec}
  end
  
  defp to_langchain_format(metadata, schema, tool_module) do
    tool_spec = %{
      "name" => to_string(metadata.name),
      "description" => metadata.description,
      "args_schema" => schema,
      "return_direct" => false,
      "verbose" => true,
      "callbacks" => nil,
      "tags" => [metadata.category || "general"],
      "metadata" => %{
        "module" => inspect(tool_module),
        "version" => metadata.version || "1.0.0"
      }
    }
    
    {:ok, tool_spec}
  end
  
  defp build_detailed_description(metadata, params) do
    param_descriptions = params
    |> Enum.map(fn param ->
      required = if param[:required], do: "required", else: "optional"
      "- #{param.name} (#{param.type}, #{required}): #{param.description}"
    end)
    |> Enum.join("\n")
    
    """
    #{metadata.description}
    
    Parameters:
    #{param_descriptions}
    """
  end
  
  defp build_parameter_descriptions(params) do
    Enum.map(params, fn param ->
      %{
        name: param.name,
        type: param.type,
        description: param.description,
        required: param[:required] || false,
        default: param[:default]
      }
    end)
  end
  
  defp transform_value(value, param, _source_format) do
    case param.type do
      :string -> to_string(value)
      :integer -> to_integer(value)
      :float -> to_float(value)
      :boolean -> to_boolean(value)
      :atom -> String.to_atom(to_string(value))
      {:array, type} -> Enum.map(value, &transform_value(&1, %{type: type}, :json))
      {:map, _} -> value
      _ -> value
    end
  end
  
  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_binary(value), do: String.to_integer(value)
  defp to_integer(value), do: round(to_float(value))
  
  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0
  defp to_float(value) when is_binary(value), do: String.to_float(value)
  
  defp to_boolean(true), do: true
  defp to_boolean(false), do: false
  defp to_boolean("true"), do: true
  defp to_boolean("false"), do: false
  defp to_boolean(1), do: true
  defp to_boolean(0), do: false
  defp to_boolean(_), do: false
  
  defp standardize_result(result) do
    %{
      success: true,
      data: result,
      metadata: %{
        timestamp: DateTime.utc_now(),
        version: "1.0"
      }
    }
  end
  
  defp to_xml(data) do
    # Simple XML conversion - in production use a proper XML library
    xml = build_xml_element("result", data)
    {:ok, xml}
  end
  
  defp build_xml_element(name, value) when is_map(value) do
    children = value
    |> Enum.map(fn {k, v} -> build_xml_element(to_string(k), v) end)
    |> Enum.join("\n")
    
    "<#{name}>\n#{children}\n</#{name}>"
  end
  
  defp build_xml_element(name, value) when is_list(value) do
    items = value
    |> Enum.map(&build_xml_element("item", &1))
    |> Enum.join("\n")
    
    "<#{name}>\n#{items}\n</#{name}>"
  end
  
  defp build_xml_element(name, value) do
    "<#{name}>#{escape_xml(to_string(value))}</#{name}>"
  end
  
  defp escape_xml(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
  
  defp build_openapi_parameters(tool_module) do
    Tool.parameters(tool_module)
    |> Enum.filter(& &1[:in_query])
    |> Enum.map(fn param ->
      %{
        "name" => to_string(param.name),
        "in" => "query",
        "required" => param[:required] || false,
        "description" => param.description,
        "schema" => %{
          "type" => openapi_type(param.type)
        }
      }
    end)
  end
  
  defp build_openapi_request_body(schema) do
    %{
      "required" => true,
      "content" => %{
        "application/json" => %{
          "schema" => schema
        }
      }
    }
  end
  
  defp build_openapi_responses(tool_module) do
    %{
      "200" => %{
        "description" => "Successful operation",
        "content" => %{
          "application/json" => %{
            "schema" => build_response_schema(tool_module)
          }
        }
      },
      "400" => %{
        "description" => "Invalid parameters"
      },
      "500" => %{
        "description" => "Internal error"
      }
    }
  end
  
  defp build_response_schema(_tool_module) do
    %{
      "type" => "object",
      "properties" => %{
        "success" => %{"type" => "boolean"},
        "data" => %{"type" => "object"},
        "metadata" => %{
          "type" => "object",
          "properties" => %{
            "timestamp" => %{"type" => "string", "format" => "date-time"},
            "version" => %{"type" => "string"}
          }
        }
      }
    }
  end
  
  defp openapi_type(:string), do: "string"
  defp openapi_type(:integer), do: "integer"
  defp openapi_type(:float), do: "number"
  defp openapi_type(:boolean), do: "boolean"
  defp openapi_type({:array, _type}), do: "array"
  defp openapi_type({:map, _}), do: "object"
  defp openapi_type(_), do: "string"
  
  defp tool_summary(tool_module) do
    metadata = Tool.metadata(tool_module)
    
    %{
      name: metadata.name,
      description: metadata.description,
      category: metadata[:category] || "general",
      version: metadata.version || "1.0.0"
    }
  end
  
  defp build_simple_schema(tool_module) do
    parameters = Tool.parameters(tool_module)
    
    properties = Enum.reduce(parameters, %{}, fn param, acc ->
      Map.put(acc, to_string(param.name), %{
        "type" => json_schema_type(param.type),
        "description" => param.description
      })
    end)
    
    required = parameters
    |> Enum.filter(& &1[:required])
    |> Enum.map(& to_string(&1.name))
    
    %{
      "type" => "object",
      "properties" => properties,
      "required" => required
    }
  end
  
  defp json_schema_type(:string), do: "string"
  defp json_schema_type(:integer), do: "integer"
  defp json_schema_type(:float), do: "number"
  defp json_schema_type(:boolean), do: "boolean"
  defp json_schema_type({:array, _}), do: "array"
  defp json_schema_type({:map, _}), do: "object"
  defp json_schema_type(_), do: "string"
  
  defp get_tool_examples(tool_module) do
    # Try to get examples, fallback to empty list
    try do
      if function_exported?(tool_module, :examples, 0) do
        tool_module.examples() || []
      else
        []
      end
    rescue
      _ -> []
    end
  end
end