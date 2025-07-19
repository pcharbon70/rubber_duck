defmodule RubberDuck.MCP.ToolAdapter do
  @moduledoc """
  Enhanced adapter for bridging RubberDuck's tool system with MCP protocol.

  Provides comprehensive tool metadata conversion, parameter transformation,
  progress reporting, error translation, and resource discovery capabilities
  for exposing internal tools through the MCP interface.
  """

  alias RubberDuck.Tool.{Registry, Executor}
  alias RubberDuck.MCP.Protocol
  alias Phoenix.PubSub

  require Logger

  @doc """
  Converts a tool module to comprehensive MCP tool format.

  Extracts all metadata including parameters, constraints, capabilities,
  and generates appropriate JSON Schema for the input specification.
  """
  def convert_tool_to_mcp(tool_module) when is_atom(tool_module) do
    metadata = tool_module.__tool__(:all)
    tool_name = metadata[:name] || metadata.name

    %{
      "name" => to_string(tool_name),
      "description" => metadata[:description] || metadata.description || "No description available",
      "inputSchema" => parameter_schema_to_mcp(metadata[:parameters] || metadata.parameters || []),
      "capabilities" => capability_descriptor(metadata),
      "metadata" => %{
        "version" => metadata[:version] || metadata.version || "1.0.0",
        "category" => metadata[:category] || metadata.category,
        "tags" => metadata[:tags] || metadata.tags || [],
        "async" => get_in(metadata, [:execution, :async]) || false,
        "timeout" => get_in(metadata, [:execution, :timeout]) || 30_000
      }
    }
  rescue
    _ ->
      # Fallback for tools without proper metadata
      %{
        "name" => inspect(tool_module),
        "description" => "Tool module: #{inspect(tool_module)}",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{}
        }
      }
  end

  @doc """
  Converts tool parameters to MCP JSON Schema format.
  """
  def parameter_schema_to_mcp(parameters) when is_list(parameters) do
    properties =
      Enum.reduce(parameters, %{}, fn param, acc ->
        name = if is_atom(param.name), do: to_string(param.name), else: param.name
        Map.put(acc, name, parameter_to_json_schema(param))
      end)

    required =
      parameters
      |> Enum.filter(fn param -> param[:required] || param.required end)
      |> Enum.map(fn param ->
        if is_atom(param.name), do: to_string(param.name), else: param.name
      end)

    %{
      "type" => "object",
      "properties" => properties,
      "required" => required,
      "additionalProperties" => false
    }
  end

  def parameter_schema_to_mcp(_), do: %{"type" => "object", "properties" => %{}}

  @doc """
  Maps an MCP tool call to internal execution.

  Handles parameter transformation, context setup, and execution routing.
  """
  def map_mcp_call(tool_name, mcp_params, mcp_context) do
    with {:ok, tool_module} <- get_tool_module(tool_name),
         {:ok, transformed_params} <- transform_parameters(tool_module, mcp_params, :from_mcp),
         {:ok, execution_context} <- build_execution_context(mcp_context) do
      # Set up progress reporting if requested
      progress_reporter =
        if mcp_context[:enable_progress] do
          setup_progress_reporter(mcp_context[:session_id], tool_name)
        end

      # Execute with enhanced context
      enhanced_context =
        Map.merge(execution_context, %{
          mcp_session_id: mcp_context[:session_id],
          progress_reporter: progress_reporter
        })

      case Executor.execute(tool_module, transformed_params, enhanced_context) do
        {:ok, result} ->
          {:ok, format_execution_result(result, tool_module)}

        {:error, reason} ->
          {:error, error_to_mcp(reason, tool_module)}

        {:error, reason, details} ->
          {:error, error_to_mcp({reason, details}, tool_module)}
      end
    end
  end

  @doc """
  Transforms parameters between MCP and internal formats.

  Direction can be :to_mcp or :from_mcp.
  """
  def transform_parameters(tool_module, params, direction) do
    metadata = tool_module.__tool__(:all)
    param_defs = metadata[:parameters] || metadata.parameters || []

    case direction do
      :from_mcp ->
        transform_from_mcp(params, param_defs)

      :to_mcp ->
        transform_to_mcp(params, param_defs)

      _ ->
        {:error, "Invalid transformation direction"}
    end
  rescue
    error ->
      Logger.error("Parameter transformation failed: #{inspect(error)}")
      {:error, "Parameter transformation failed"}
  end

  @doc """
  Formats tool execution results for MCP.

  Converts internal result format to MCP content specification.
  """
  def format_execution_result(result, tool_module) do
    metadata = tool_module.__tool__(:all)

    content =
      case result do
        binary when is_binary(binary) ->
          [%{"type" => "text", "text" => binary}]

        %{output: output, format: :json} ->
          [
            %{
              "type" => "text",
              "text" => Jason.encode!(output, pretty: true),
              "mimeType" => "application/json"
            }
          ]

        %{output: output, format: :markdown} ->
          [
            %{
              "type" => "text",
              "text" => output,
              "mimeType" => "text/markdown"
            }
          ]

        %{output: output} when is_binary(output) ->
          [%{"type" => "text", "text" => output}]

        map when is_map(map) ->
          [
            %{
              "type" => "text",
              "text" => Jason.encode!(map, pretty: true),
              "mimeType" => "application/json"
            }
          ]

        list when is_list(list) ->
          [
            %{
              "type" => "text",
              "text" => Jason.encode!(list, pretty: true),
              "mimeType" => "application/json"
            }
          ]

        other ->
          [%{"type" => "text", "text" => inspect(other)}]
      end

    result_map = if is_map(result), do: result, else: %{}

    %{
      "content" => content,
      "metadata" => %{
        "tool" => to_string(metadata.name),
        "executionTime" => Map.get(result_map, :execution_time),
        "resourceUsage" => Map.get(result_map, :resource_usage)
      }
    }
  end

  @doc """
  Sets up progress reporting for long-running tools.

  Returns a function that can be called to report progress.
  """
  def setup_progress_reporter(session_id, tool_name) do
    request_id = generate_request_id()

    # Subscribe session to progress updates
    PubSub.subscribe(RubberDuck.PubSub, "tool:progress:#{request_id}")

    # Return reporter function
    fn progress_update ->
      notification =
        Protocol.build_notification(
          "tool/progress",
          %{
            "toolName" => tool_name,
            "requestId" => request_id,
            "progress" => progress_update
          }
        )

      # Publish to session
      PubSub.broadcast(
        RubberDuck.PubSub,
        "mcp:session:#{session_id}",
        {:mcp_notification, notification}
      )
    end
  end

  @doc """
  Translates internal errors to MCP error format.

  Sanitizes error information to prevent leaking sensitive details.
  """
  def error_to_mcp(error, tool_module) do
    metadata = tool_module.__tool__(:all)
    tool_name = to_string(metadata.name)

    {code, message} =
      case error do
        {:validation_error, details} ->
          {-32602, "Invalid parameters: #{sanitize_error(details)}"}

        {:authorization_error, _} ->
          {-32603, "Not authorized to use tool: #{tool_name}"}

        {:timeout, _} ->
          {-32603, "Tool execution timed out"}

        {:resource_limit, type} ->
          {-32603, "Resource limit exceeded: #{type}"}

        {:tool_error, reason} ->
          {-32603, "Tool execution failed: #{sanitize_error(reason)}"}

        _ ->
          {-32603, "Internal tool error"}
      end

    %{
      "code" => code,
      "message" => message,
      "data" => %{
        "tool" => tool_name,
        "type" => error_type(error)
      }
    }
  end

  @doc """
  Discovers resources related to a tool.

  Returns URIs for documentation, examples, schemas, etc.
  """
  def discover_tool_resources(tool_module) do
    metadata = tool_module.__tool__(:all)
    tool_name = to_string(metadata.name)

    resources = []

    # Documentation resource
    resources =
      if metadata[:description] || metadata.description do
        resources ++
          [
            %{
              "uri" => "tool://#{tool_name}/documentation",
              "name" => "#{tool_name} Documentation",
              "description" => "Detailed documentation for #{tool_name}",
              "mimeType" => "text/markdown"
            }
          ]
      else
        resources
      end

    # Examples resource
    resources =
      if metadata[:examples] || metadata.examples do
        resources ++
          [
            %{
              "uri" => "tool://#{tool_name}/examples",
              "name" => "#{tool_name} Examples",
              "description" => "Usage examples for #{tool_name}",
              "mimeType" => "application/json"
            }
          ]
      else
        resources
      end

    # Schema resource
    resources ++
      [
        %{
          "uri" => "tool://#{tool_name}/schema",
          "name" => "#{tool_name} Input Schema",
          "description" => "JSON Schema for #{tool_name} parameters",
          "mimeType" => "application/schema+json"
        }
      ]
  end

  @doc """
  Generates prompt templates for common tool usage patterns.
  """
  def prompt_templates(tool_module) do
    metadata = tool_module.__tool__(:all)
    tool_name = to_string(metadata.name)

    base_templates = [
      %{
        "name" => "#{tool_name}_basic",
        "description" => "Basic usage of #{tool_name}",
        "arguments" => build_template_arguments(metadata[:parameters] || metadata.parameters || []),
        "template" => build_basic_template(metadata)
      }
    ]

    # Add custom templates if defined
    custom_templates =
      if metadata[:templates] || metadata.templates do
        templates = metadata[:templates] || metadata.templates
        Enum.map(templates, &convert_template_to_mcp/1)
      else
        []
      end

    base_templates ++ custom_templates
  end

  @doc """
  Generates capability descriptor for a tool.

  Describes what the tool can and cannot do, including constraints.
  """
  def capability_descriptor(metadata) do
    execution = metadata[:execution] || metadata.execution || %{}

    %{
      "supportsAsync" => execution[:async] || false,
      "supportsStreaming" => execution[:streaming] || false,
      "supportsCancellation" => execution[:cancellable] || false,
      "maxExecutionTime" => execution[:timeout] || 30_000,
      "resourceLimits" => extract_resource_limits(metadata),
      "securityConstraints" => extract_security_constraints(metadata)
    }
  end

  # Private helper functions

  defp get_tool_module(tool_name) when is_binary(tool_name) do
    case Registry.get(String.to_atom(tool_name)) do
      {:ok, tool_info} ->
        # Extract the module from the tool info
        module = tool_info[:module] || tool_info.module
        {:ok, module}

      {:error, :not_found} ->
        {:error, :tool_not_found}
    end
  end

  defp parameter_to_json_schema(param) do
    param_type = param[:type] || param.type
    param_description = param[:description] || param.description || ""

    base_schema = %{
      "type" => type_to_json_type(param_type),
      "description" => param_description
    }

    # Add constraints
    constraints = param[:constraints] || Map.get(param, :constraints)

    schema =
      if constraints do
        apply_constraints_to_schema(base_schema, constraints)
      else
        base_schema
      end

    # Add default value
    default_value = param[:default] || Map.get(param, :default)

    if default_value do
      Map.put(schema, "default", default_value)
    else
      schema
    end
  end

  defp type_to_json_type(:string), do: "string"
  defp type_to_json_type(:integer), do: "integer"
  defp type_to_json_type(:float), do: "number"
  defp type_to_json_type(:boolean), do: "boolean"
  defp type_to_json_type(:map), do: "object"
  defp type_to_json_type(:list), do: "array"
  defp type_to_json_type(:any), do: ["string", "number", "boolean", "object", "array"]
  defp type_to_json_type(_), do: "string"

  defp apply_constraints_to_schema(schema, constraints) do
    Enum.reduce(constraints, schema, fn
      {:min, value}, acc -> Map.put(acc, "minimum", value)
      {:max, value}, acc -> Map.put(acc, "maximum", value)
      {:min_length, value}, acc -> Map.put(acc, "minLength", value)
      {:max_length, value}, acc -> Map.put(acc, "maxLength", value)
      {:pattern, regex}, acc -> Map.put(acc, "pattern", regex)
      {:enum, values}, acc -> Map.put(acc, "enum", values)
      _, acc -> acc
    end)
  end

  defp transform_from_mcp(mcp_params, param_defs) do
    transformed =
      Enum.reduce(param_defs, %{}, fn param_def, acc ->
        param_name = param_def[:name] || param_def.name
        key = to_string(param_name)
        atom_key = if is_atom(param_name), do: param_name, else: String.to_atom(param_name)

        value = Map.get(mcp_params, key) || Map.get(mcp_params, atom_key)

        if value != nil do
          param_type = param_def[:type] || param_def.type

          case transform_value(value, param_type, :from_mcp) do
            {:ok, transformed} -> Map.put(acc, atom_key, transformed)
            _ -> acc
          end
        else
          default_value = param_def[:default] || Map.get(param_def, :default)

          if default_value do
            Map.put(acc, atom_key, default_value)
          else
            acc
          end
        end
      end)

    {:ok, transformed}
  end

  defp transform_to_mcp(internal_params, param_defs) do
    transformed =
      Enum.reduce(param_defs, %{}, fn param_def, acc ->
        param_name = param_def[:name] || param_def.name
        atom_key = if is_atom(param_name), do: param_name, else: String.to_atom(param_name)
        string_key = to_string(param_name)

        if Map.has_key?(internal_params, atom_key) do
          value = Map.get(internal_params, atom_key)
          param_type = param_def[:type] || param_def.type

          case transform_value(value, param_type, :to_mcp) do
            {:ok, transformed} -> Map.put(acc, string_key, transformed)
            _ -> acc
          end
        else
          acc
        end
      end)

    {:ok, transformed}
  end

  defp transform_value(value, _type, _direction) do
    # For now, most values pass through unchanged
    # Add specific transformations as needed
    {:ok, value}
  end

  defp build_execution_context(mcp_context) do
    {:ok,
     %{
       user: mcp_context[:user] || %{id: "mcp_user"},
       session_id: mcp_context[:session_id],
       request_id: generate_request_id(),
       source: :mcp
     }}
  end

  defp sanitize_error(error) when is_binary(error) do
    # Remove sensitive patterns
    error
    # Hide paths
    |> String.replace(~r/\/[^\/\s]+\/[^\/\s]+/, "/***")
    # Hide IPs
    |> String.replace(~r/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/, "*.*.*.*")
    # Limit length
    |> String.slice(0, 200)
  end

  defp sanitize_error(error), do: inspect(error) |> sanitize_error()

  defp error_type({type, _}), do: to_string(type)
  defp error_type(_), do: "unknown"

  defp generate_request_id do
    "req_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp build_template_arguments(parameters) do
    Enum.map(parameters, fn param ->
      param_name = param[:name] || param.name
      param_desc = param[:description] || param.description || ""
      param_required = param[:required] || param.required || false

      %{
        "name" => to_string(param_name),
        "description" => param_desc,
        "required" => param_required
      }
    end)
  end

  defp build_basic_template(metadata) do
    parameters = metadata[:parameters] || metadata.parameters || []

    param_refs =
      parameters
      |> Enum.map(fn p ->
        name = p[:name] || p.name
        "{{#{name}}}"
      end)
      |> Enum.join(", ")

    "Use #{metadata.name} with parameters: #{param_refs}"
  end

  defp convert_template_to_mcp(template) do
    %{
      "name" => template[:name] || template.name,
      "description" => template[:description] || template.description,
      "template" => template[:content] || template.content,
      "arguments" => template[:arguments] || Map.get(template, :arguments) || []
    }
  end

  defp extract_resource_limits(metadata) do
    security = metadata[:security] || metadata.security || %{}
    execution = metadata[:execution] || metadata.execution || %{}

    %{
      "maxMemory" => security[:max_memory],
      "maxCpu" => security[:max_cpu],
      "maxTime" => execution[:timeout],
      "maxFileSize" => security[:max_file_size]
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp extract_security_constraints(metadata) do
    security = metadata[:security] || metadata.security || %{}

    %{
      "requiresAuthentication" => security[:requires_auth] || false,
      "requiresAuthorization" => security[:requires_auth] || false,
      "allowedRoles" => security[:allowed_roles] || [],
      "deniedRoles" => security[:denied_roles] || [],
      "rateLimit" => security[:rate_limit]
    }
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end
end
