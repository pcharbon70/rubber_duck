defmodule RubberDuck.Tool.Discovery do
  @moduledoc """
  Provides functionality to discover and load tools from the codebase.

  This module helps automatically find tool modules and register them
  with the tool registry.
  """

  require Logger

  alias RubberDuck.Tool.Registry

  @doc """
  Discovers tools in a specific module.

  Returns a list containing the module if it's a valid tool, empty list otherwise.
  """
  @spec discover_in_module(module()) :: [module()]
  def discover_in_module(module) do
    if valid_tool?(module) do
      [module]
    else
      []
    end
  end

  @doc """
  Discovers all tools in a given namespace.

  Scans all loaded modules that start with the given namespace prefix.
  """
  @spec discover_in_namespace(module()) :: [module()]
  def discover_in_namespace(namespace) do
    namespace_string = to_string(namespace)

    :code.all_loaded()
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(&String.starts_with?(to_string(&1), namespace_string))
    |> Enum.filter(&valid_tool?/1)
  end

  @doc """
  Discovers all tools in all loaded modules.

  This scans the entire loaded module space - use with caution in large applications.
  """
  @spec discover_all() :: [module()]
  def discover_all do
    :code.all_loaded()
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(&valid_tool?/1)
  end

  @doc """
  Loads a list of tool modules into the registry.

  Invalid tools are skipped with a warning.
  """
  @spec load_tools([module()]) :: :ok
  def load_tools(modules) when is_list(modules) do
    Enum.each(modules, fn module ->
      case Registry.register(module) do
        :ok ->
          Logger.debug("Loaded tool: #{module}")

        {:error, reason} ->
          Logger.warning("Failed to load tool #{module}: #{inspect(reason)}")
      end
    end)
  end

  @doc """
  Loads tools from a namespace with optional filtering.

  ## Options

  - `:filter` - A function that receives a module and returns true/false
  - `:category` - Only load tools with this category
  - `:tag` - Only load tools with this tag
  """
  @spec load_from_namespace(module(), keyword()) :: :ok
  def load_from_namespace(namespace, opts \\ []) do
    namespace
    |> discover_in_namespace()
    |> apply_filters(opts)
    |> load_tools()
  end

  @doc """
  Loads all available tools with optional filtering.

  ## Options

  - `:filter` - A function that receives a module and returns true/false
  - `:category` - Only load tools with this category
  - `:tag` - Only load tools with this tag
  """
  @spec load_all(keyword()) :: :ok
  def load_all(opts \\ []) do
    discover_all()
    |> apply_filters(opts)
    |> load_tools()
  end

  @doc """
  Checks if a module is a valid tool.

  A valid tool must:
  1. Be a loaded module
  2. Use the RubberDuck.Tool DSL
  3. Have the __tool__/1 function
  """
  @spec valid_tool?(module()) :: boolean()
  def valid_tool?(module) do
    RubberDuck.Tool.is_tool?(module)
  end

  @doc """
  Reloads all tools from a namespace.

  This will unregister existing tools and reload them, useful for development.
  """
  @spec reload_from_namespace(module()) :: :ok
  def reload_from_namespace(namespace) do
    # Get existing tools from this namespace
    existing_tools = discover_in_namespace(namespace)

    # Unregister existing tools
    Enum.each(existing_tools, fn module ->
      if valid_tool?(module) do
        metadata = RubberDuck.Tool.metadata(module)
        Registry.unregister(metadata.name)
      end
    end)

    # Reload the namespace
    load_from_namespace(namespace)
  end

  @doc """
  Gets statistics about discovered tools.

  Returns a map with counts by category, total tools, etc.
  """
  @spec get_discovery_stats() :: map()
  def get_discovery_stats do
    tools = discover_all()

    stats = %{
      total_tools: length(tools),
      by_category: %{},
      by_tag: %{}
    }

    Enum.reduce(tools, stats, fn module, acc ->
      metadata = RubberDuck.Tool.metadata(module)

      # Count by category
      category_count = Map.get(acc.by_category, metadata.category, 0)
      acc = put_in(acc.by_category[metadata.category], category_count + 1)

      # Count by tags
      tags = metadata.tags || []

      tag_counts =
        Enum.reduce(tags, acc.by_tag, fn tag, tag_acc ->
          Map.update(tag_acc, tag, 1, &(&1 + 1))
        end)

      %{acc | by_tag: tag_counts}
    end)
  end

  # Private functions

  defp apply_filters(modules, opts) do
    modules
    |> apply_filter_function(opts[:filter])
    |> apply_category_filter(opts[:category])
    |> apply_tag_filter(opts[:tag])
  end

  defp apply_filter_function(modules, nil), do: modules

  defp apply_filter_function(modules, filter_fn) when is_function(filter_fn) do
    Enum.filter(modules, filter_fn)
  end

  defp apply_category_filter(modules, nil), do: modules

  defp apply_category_filter(modules, category) do
    Enum.filter(modules, fn module ->
      metadata = RubberDuck.Tool.metadata(module)
      metadata.category == category
    end)
  end

  defp apply_tag_filter(modules, nil), do: modules

  defp apply_tag_filter(modules, tag) do
    Enum.filter(modules, fn module ->
      metadata = RubberDuck.Tool.metadata(module)
      tag in (metadata.tags || [])
    end)
  end
end
