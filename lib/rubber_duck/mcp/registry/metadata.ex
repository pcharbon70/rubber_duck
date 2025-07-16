defmodule RubberDuck.MCP.Registry.Metadata do
  @moduledoc """
  Handles metadata extraction and management for MCP tools.
  
  This module provides functions to extract metadata from tool modules,
  including schema information, capabilities, and additional attributes.
  """
  
  alias Hermes.Server.Component
  
  @type t :: %__MODULE__{
    module: module(),
    name: String.t(),
    description: String.t(),
    category: atom(),
    tags: [atom()],
    capabilities: [atom()],
    version: String.t(),
    schema: map(),
    examples: [map()],
    performance: map(),
    dependencies: [module()],
    source: atom(),
    registered_at: DateTime.t()
  }
  
  defstruct [
    :module,
    :name,
    :description,
    :category,
    :tags,
    :capabilities,
    :version,
    :schema,
    :examples,
    :performance,
    :dependencies,
    :source,
    :registered_at
  ]
  
  @doc """
  Extracts metadata from a tool module.
  """
  def extract_from_module(module, opts \\ []) do
    # Get basic module info
    module_info = module.module_info(:attributes)
    
    # Extract metadata from attributes
    name = get_tool_name(module, module_info)
    description = get_description(module, module_info)
    category = get_category(module_info, opts)
    tags = get_tags(module_info, opts)
    capabilities = get_capabilities(module, module_info, opts)
    version = get_version(module_info, opts)
    examples = get_examples(module_info, opts)
    performance = get_performance(module_info, opts)
    dependencies = get_dependencies(module_info, opts)
    
    # Extract schema if available
    schema = extract_schema(module)
    
    %__MODULE__{
      module: module,
      name: name,
      description: description,
      category: category,
      tags: tags,
      capabilities: capabilities,
      version: version,
      schema: schema,
      examples: examples,
      performance: performance,
      dependencies: dependencies,
      source: opts[:source] || :internal,
      registered_at: DateTime.utc_now()
    }
  end
  
  @doc """
  Updates metadata with new information.
  """
  def update(metadata, updates) do
    struct(metadata, updates)
  end
  
  @doc """
  Converts metadata to a map suitable for JSON encoding.
  """
  def to_map(metadata) do
    %{
      module: inspect(metadata.module),
      name: metadata.name,
      description: metadata.description,
      category: metadata.category,
      tags: metadata.tags,
      capabilities: metadata.capabilities,
      version: metadata.version,
      schema: metadata.schema,
      examples: metadata.examples,
      performance: metadata.performance,
      dependencies: Enum.map(metadata.dependencies, &inspect/1),
      source: metadata.source,
      registered_at: DateTime.to_iso8601(metadata.registered_at)
    }
  end
  
  # Private functions
  
  defp get_tool_name(module, module_info) do
    # Try to get from @tool_name attribute
    case Keyword.get(module_info, :tool_name) do
      [name] when is_binary(name) -> name
      _ ->
        # Fall back to module name
        module
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
        |> String.replace("_", " ")
        |> String.capitalize()
    end
  end
  
  defp get_description(module, module_info) do
    # Try @moduledoc first
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, %{"en" => moduledoc}, _, _} when is_binary(moduledoc) ->
        # Take first paragraph
        moduledoc
        |> String.split("\n\n")
        |> List.first()
        |> String.trim()
        
      _ ->
        # Try @description attribute
        case Keyword.get(module_info, :description) do
          [desc] when is_binary(desc) -> desc
          _ -> "No description available"
        end
    end
  end
  
  defp get_category(module_info, opts) do
    # Check module attribute first
    case Keyword.get(module_info, :category) do
      [category] when is_atom(category) -> category
      _ ->
        # Fall back to opts or default
        opts[:category] || :general
    end
  end
  
  defp get_tags(module_info, opts) do
    # Combine attribute tags with opts tags
    attr_tags = case Keyword.get(module_info, :tags) do
      [tags] when is_list(tags) -> tags
      _ -> []
    end
    
    opts_tags = opts[:tags] || []
    
    (attr_tags ++ opts_tags)
    |> Enum.uniq()
    |> Enum.filter(&is_atom/1)
  end
  
  defp get_capabilities(module, module_info, opts) do
    # Start with explicit capabilities
    explicit = case Keyword.get(module_info, :capabilities) do
      [caps] when is_list(caps) -> caps
      _ -> []
    end
    
    # Add inferred capabilities
    inferred = infer_capabilities(module)
    
    # Add opts capabilities
    opts_caps = opts[:capabilities] || []
    
    (explicit ++ inferred ++ opts_caps)
    |> Enum.uniq()
    |> Enum.filter(&is_atom/1)
  end
  
  defp infer_capabilities(module) do
    capabilities = []
    
    # Check for streaming support
    capabilities = if function_exported?(module, :stream, 2) do
      [:streaming | capabilities]
    else
      capabilities
    end
    
    # Check for async support
    schema = extract_schema(module)
    capabilities = if schema && Map.has_key?(schema["properties"], "async") do
      [:async | capabilities]
    else
      capabilities
    end
    
    capabilities
  end
  
  defp get_version(module_info, opts) do
    case Keyword.get(module_info, :version) do
      [version] when is_binary(version) -> version
      _ -> opts[:version] || "1.0.0"
    end
  end
  
  defp get_examples(module_info, opts) do
    attr_examples = case Keyword.get(module_info, :examples) do
      [examples] when is_list(examples) -> examples
      _ -> []
    end
    
    opts_examples = opts[:examples] || []
    
    (attr_examples ++ opts_examples)
    |> Enum.filter(&is_map/1)
  end
  
  defp get_performance(module_info, opts) do
    default_perf = %{
      avg_latency_ms: nil,
      max_concurrent: 10,
      timeout_ms: 30_000
    }
    
    attr_perf = case Keyword.get(module_info, :performance) do
      [perf] when is_map(perf) -> perf
      _ -> %{}
    end
    
    opts_perf = opts[:performance] || %{}
    
    Map.merge(default_perf, Map.merge(attr_perf, opts_perf))
  end
  
  defp get_dependencies(module_info, opts) do
    attr_deps = case Keyword.get(module_info, :dependencies) do
      [deps] when is_list(deps) -> deps
      _ -> []
    end
    
    opts_deps = opts[:dependencies] || []
    
    (attr_deps ++ opts_deps)
    |> Enum.uniq()
    |> Enum.filter(&is_atom/1)
  end
  
  defp extract_schema(module) do
    # Try to get the input schema from the module
    if function_exported?(module, :input_schema, 0) do
      try do
        module.input_schema()
      rescue
        _ -> nil
      end
    else
      nil
    end
  end
end