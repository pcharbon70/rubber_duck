defmodule RubberDuck.PluginSystem.Transformers.ResolveDependencies do
  @moduledoc """
  Resolves and validates plugin dependencies at compile time.
  """
  
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer
  
  def transform(dsl_state) do
    plugins = Transformer.get_entities(dsl_state, [:plugins])
    
    with :ok <- validate_dependencies_exist(plugins),
         :ok <- check_circular_dependencies(plugins) do
      {:ok, dsl_state}
    end
  end
  
  defp validate_dependencies_exist(plugins) do
    plugin_names = MapSet.new(plugins, & &1.name)
    
    Enum.reduce_while(plugins, :ok, fn plugin, :ok ->
      missing = 
        plugin.dependencies
        |> Enum.reject(&MapSet.member?(plugin_names, &1))
      
      case missing do
        [] -> 
          {:cont, :ok}
          
        deps ->
          error = Spark.Error.DslError.exception(
            message: "Plugin #{plugin.name} depends on missing plugins: #{inspect(deps)}",
            path: [:plugins, plugin.name]
          )
          {:halt, {:error, error}}
      end
    end)
  end
  
  defp check_circular_dependencies(plugins) do
    graph = build_dependency_graph(plugins)
    
    case detect_cycles(graph) do
      [] -> 
        :ok
        
      cycles ->
        cycle_desc = Enum.map_join(cycles, ", ", fn cycle ->
          Enum.join(cycle, " -> ")
        end)
        
        {:error,
         Spark.Error.DslError.exception(
           message: "Circular dependencies detected: #{cycle_desc}",
           path: [:plugins]
         )}
    end
  end
  
  defp build_dependency_graph(plugins) do
    Enum.reduce(plugins, %{}, fn plugin, graph ->
      Map.put(graph, plugin.name, plugin.dependencies || [])
    end)
  end
  
  defp detect_cycles(graph) do
    graph
    |> Map.keys()
    |> Enum.flat_map(fn node ->
      case find_cycle_from(node, graph, []) do
        {:cycle, path} -> [Enum.reverse(path)]
        :no_cycle -> []
      end
    end)
    |> Enum.uniq()
  end
  
  defp find_cycle_from(node, graph, path) do
    cond do
      node in path ->
        {:cycle, [node | Enum.take_while(path, &(&1 != node))]}
        
      true ->
        deps = Map.get(graph, node, [])
        
        Enum.reduce_while(deps, :no_cycle, fn dep, :no_cycle ->
          case find_cycle_from(dep, graph, [node | path]) do
            {:cycle, _} = cycle -> {:halt, cycle}
            :no_cycle -> {:cont, :no_cycle}
          end
        end)
    end
  end
end