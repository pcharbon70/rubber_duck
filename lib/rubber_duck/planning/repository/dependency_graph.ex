defmodule RubberDuck.Planning.Repository.DependencyGraph do
  @moduledoc """
  Builds and manages dependency graphs for repository-level analysis.
  
  This module creates directed graphs representing file dependencies based on
  module imports, aliases, and usage patterns. It provides operations for
  dependency analysis, topological sorting, and impact assessment.
  """

  defstruct [:graph, :nodes, :edges]

  @type t :: %__MODULE__{
    graph: :digraph.graph(),
    nodes: MapSet.t(String.t()),
    edges: [{String.t(), String.t()}]
  }

  @type file_analysis :: %{
    path: String.t(),
    modules: [module_info()],
    dependencies: [String.t()]
  }

  @type module_info :: %{
    name: String.t(),
    imports: [String.t()],
    aliases: [String.t()],
    uses: [String.t()]
  }

  require Logger

  @doc """
  Builds a dependency graph from file analysis results.
  """
  @spec build([file_analysis()]) :: {:ok, t()} | {:error, term()}
  def build(file_analyses) do
    Logger.debug("Building dependency graph from #{length(file_analyses)} files")
    
    try do
      graph = :digraph.new([:acyclic])
      
      # Create a mapping from module names to file paths
      module_to_file = build_module_mapping(file_analyses)
      
      # Add all files as vertices
      files = Enum.map(file_analyses, & &1.path)
      Enum.each(files, &:digraph.add_vertex(graph, &1))
      
      # Add edges based on dependencies
      edges = build_edges(file_analyses, module_to_file)
      Enum.each(edges, fn {from, to} ->
        :digraph.add_edge(graph, from, to)
      end)
      
      result = %__MODULE__{
        graph: graph,
        nodes: MapSet.new(files),
        edges: edges
      }
      
      Logger.debug("Dependency graph built with #{length(files)} nodes and #{length(edges)} edges")
      {:ok, result}
    rescue
      error ->
        Logger.error("Failed to build dependency graph: #{inspect(error)}")
        {:error, {:graph_build_error, error}}
    end
  end

  @doc """
  Gets all files that depend on the given files (transitively).
  """
  @spec get_dependent_files(t(), [String.t()]) :: [String.t()]
  def get_dependent_files(%__MODULE__{graph: graph}, files) do
    files
    |> Enum.flat_map(fn file ->
      case :digraph.vertices(graph) |> Enum.member?(file) do
        true -> get_reachable_from(graph, file)
        false -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.reject(&(&1 in files))  # Remove the original files
  end

  @doc """
  Gets all files that the given files depend on (transitively).
  """
  @spec get_dependency_files(t(), [String.t()]) :: [String.t()]
  def get_dependency_files(%__MODULE__{graph: graph}, files) do
    files
    |> Enum.flat_map(fn file ->
      case :digraph.vertices(graph) |> Enum.member?(file) do
        true -> get_reachable_to(graph, file)
        false -> []
      end
    end)
    |> Enum.uniq()
    |> Enum.reject(&(&1 in files))  # Remove the original files
  end

  @doc """
  Returns files in topological order (dependencies first).
  """
  @spec topological_sort(t()) :: {:ok, [String.t()]} | {:error, term()}
  def topological_sort(%__MODULE__{graph: graph}) do
    case :digraph_utils.topsort(graph) do
      false ->
        {:error, :cyclic_dependency}
      
      sorted_files ->
        {:ok, sorted_files}
    end
  end

  @doc """
  Detects cyclic dependencies in the graph.
  """
  @spec detect_cycles(t()) :: [cycle()]
  def detect_cycles(%__MODULE__{graph: graph}) do
    case :digraph_utils.cyclic_strong_components(graph) do
      [] -> []
      components ->
        components
        |> Enum.filter(&(length(&1) > 1))
        |> Enum.map(&%{files: &1, type: :cyclic_dependency})
    end
  end

  @type cycle :: %{
    files: [String.t()],
    type: :cyclic_dependency
  }

  @doc """
  Gets direct dependencies for a file.
  """
  @spec get_direct_dependencies(t(), String.t()) :: [String.t()]
  def get_direct_dependencies(%__MODULE__{graph: graph}, file) do
    case :digraph.vertices(graph) |> Enum.member?(file) do
      true ->
        :digraph.out_neighbours(graph, file)
      
      false ->
        []
    end
  end

  @doc """
  Gets direct dependents for a file.
  """
  @spec get_direct_dependents(t(), String.t()) :: [String.t()]
  def get_direct_dependents(%__MODULE__{graph: graph}, file) do
    case :digraph.vertices(graph) |> Enum.member?(file) do
      true ->
        :digraph.in_neighbours(graph, file)
      
      false ->
        []
    end
  end

  @doc """
  Calculates metrics for the dependency graph.
  """
  @spec calculate_metrics(t()) :: graph_metrics()
  def calculate_metrics(%__MODULE__{graph: graph, nodes: nodes, edges: edges}) do
    vertex_count = MapSet.size(nodes)
    edge_count = length(edges)
    
    # Calculate in-degree and out-degree statistics
    in_degrees = Enum.map(MapSet.to_list(nodes), fn node ->
      length(:digraph.in_neighbours(graph, node))
    end)
    
    out_degrees = Enum.map(MapSet.to_list(nodes), fn node ->
      length(:digraph.out_neighbours(graph, node))
    end)
    
    %{
      vertex_count: vertex_count,
      edge_count: edge_count,
      density: if(vertex_count > 1, do: edge_count / (vertex_count * (vertex_count - 1)), else: 0),
      max_in_degree: Enum.max(in_degrees, fn -> 0 end),
      max_out_degree: Enum.max(out_degrees, fn -> 0 end),
      avg_in_degree: if(vertex_count > 0, do: Enum.sum(in_degrees) / vertex_count, else: 0),
      avg_out_degree: if(vertex_count > 0, do: Enum.sum(out_degrees) / vertex_count, else: 0),
      strongly_connected_components: length(:digraph_utils.strong_components(graph))
    }
  end

  @type graph_metrics :: %{
    vertex_count: non_neg_integer(),
    edge_count: non_neg_integer(),
    density: float(),
    max_in_degree: non_neg_integer(),
    max_out_degree: non_neg_integer(),
    avg_in_degree: float(),
    avg_out_degree: float(),
    strongly_connected_components: non_neg_integer()
  }

  @doc """
  Finds the shortest path between two files.
  """
  @spec shortest_path(t(), String.t(), String.t()) :: {:ok, [String.t()]} | :no_path
  def shortest_path(%__MODULE__{graph: graph}, from, to) do
    case :digraph.get_short_path(graph, from, to) do
      false -> :no_path
      path -> {:ok, path}
    end
  end

  @doc """
  Exports the graph in DOT format for visualization.
  """
  @spec to_dot(t(), keyword()) :: String.t()
  def to_dot(%__MODULE__{nodes: nodes, edges: edges}, opts \\ []) do
    graph_name = Keyword.get(opts, :name, "dependency_graph")
    node_attrs = Keyword.get(opts, :node_attrs, "shape=box")
    edge_attrs = Keyword.get(opts, :edge_attrs, "")
    
    header = "digraph #{graph_name} {\n"
    footer = "}\n"
    
    # Add node declarations
    node_declarations = nodes
    |> MapSet.to_list()
    |> Enum.map(fn node ->
      safe_name = sanitize_node_name(node)
      label = Path.basename(node)
      "  \"#{safe_name}\" [label=\"#{label}\" #{node_attrs}];"
    end)
    |> Enum.join("\n")
    
    # Add edge declarations
    edge_declarations = edges
    |> Enum.map(fn {from, to} ->
      safe_from = sanitize_node_name(from)
      safe_to = sanitize_node_name(to)
      "  \"#{safe_from}\" -> \"#{safe_to}\" [#{edge_attrs}];"
    end)
    |> Enum.join("\n")
    
    header <> node_declarations <> "\n" <> edge_declarations <> "\n" <> footer
  end

  @doc """
  Destroys the internal digraph to free memory.
  """
  @spec destroy(t()) :: :ok
  def destroy(%__MODULE__{graph: graph}) do
    :digraph.delete(graph)
    :ok
  end

  # Private functions

  defp build_module_mapping(file_analyses) do
    file_analyses
    |> Enum.flat_map(fn file ->
      Enum.map(file.modules, fn module ->
        {module.name, file.path}
      end)
    end)
    |> Map.new()
  end

  defp build_edges(file_analyses, module_to_file) do
    file_analyses
    |> Enum.flat_map(fn file ->
      dependencies = get_file_dependencies(file, module_to_file)
      Enum.map(dependencies, &{file.path, &1})
    end)
    |> Enum.uniq()
    |> Enum.reject(fn {from, to} -> from == to end)  # Remove self-dependencies
  end

  defp get_file_dependencies(file, module_to_file) do
    file.modules
    |> Enum.flat_map(fn module ->
      all_deps = module.imports ++ module.aliases ++ module.uses
      
      all_deps
      |> Enum.map(&resolve_module_to_file(&1, module_to_file))
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == file.path))  # Remove self-references
    end)
    |> Enum.uniq()
  end

  defp resolve_module_to_file(module_name, module_to_file) do
    # Try exact match first
    case Map.get(module_to_file, module_name) do
      nil ->
        # Try to find partial matches for nested modules
        find_parent_module(module_name, module_to_file)
      
      file_path ->
        file_path
    end
  end

  defp find_parent_module(module_name, module_to_file) do
    parts = String.split(module_name, ".")
    
    # Try progressively shorter module paths
    1..(length(parts) - 1)
    |> Enum.map(fn take_count ->
      parts |> Enum.take(take_count) |> Enum.join(".")
    end)
    |> Enum.reverse()  # Try longer matches first
    |> Enum.find_value(fn parent_module ->
      Map.get(module_to_file, parent_module)
    end)
  end

  defp get_reachable_from(graph, start_vertex) do
    :digraph_utils.reachable([start_vertex], graph)
  end

  defp get_reachable_to(graph, end_vertex) do
    :digraph_utils.reachable_neighbours([end_vertex], graph)
  end

  defp sanitize_node_name(node) do
    node
    |> String.replace(~r/[^\w\/\.]/, "_")
    |> String.replace("/", "_")
    |> String.replace(".", "_")
  end
end