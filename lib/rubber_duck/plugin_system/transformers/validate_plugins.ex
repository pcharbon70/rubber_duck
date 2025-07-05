defmodule RubberDuck.PluginSystem.Transformers.ValidatePlugins do
  @moduledoc """
  Validates plugin configurations at compile time.
  """
  
  use Spark.Dsl.Transformer
  alias Spark.Dsl.Transformer
  alias RubberDuck.Plugin
  
  def transform(dsl_state) do
    dsl_state
    |> Transformer.get_entities([:plugins])
    |> Enum.reduce({:ok, dsl_state}, fn plugin, acc ->
      case acc do
        {:error, _} = error -> error
        {:ok, state} -> validate_plugin(plugin, state)
      end
    end)
  end
  
  defp validate_plugin(plugin, dsl_state) do
    with :ok <- validate_priority(plugin),
         :ok <- validate_module_exists(plugin),
         :ok <- validate_plugin_behavior(plugin),
         :ok <- validate_unique_name(plugin, dsl_state) do
      {:ok, dsl_state}
    end
  end
  
  defp validate_priority(%{priority: priority} = plugin) when priority < 0 or priority > 100 do
    {:error,
     Spark.Error.DslError.exception(
       message: "Plugin #{plugin.name} has invalid priority #{priority}. Must be between 0 and 100.",
       path: [:plugins, plugin.name]
     )}
  end
  
  defp validate_priority(_), do: :ok
  
  defp validate_module_exists(%{module: module} = plugin) do
    if Code.ensure_loaded?(module) do
      :ok
    else
      {:error,
       Spark.Error.DslError.exception(
         message: "Plugin #{plugin.name} references module #{inspect(module)} which cannot be loaded.",
         path: [:plugins, plugin.name]
       )}
    end
  end
  
  defp validate_plugin_behavior(%{module: module} = plugin) do
    if Plugin.is_plugin?(module) do
      :ok
    else
      {:error,
       Spark.Error.DslError.exception(
         message: "Module #{inspect(module)} for plugin #{plugin.name} does not implement RubberDuck.Plugin behavior.",
         path: [:plugins, plugin.name]
       )}
    end
  end
  
  defp validate_unique_name(plugin, dsl_state) do
    all_plugins = Transformer.get_entities(dsl_state, [:plugins])
    
    duplicate_count = 
      all_plugins
      |> Enum.filter(&(&1.name == plugin.name))
      |> length()
    
    if duplicate_count > 1 do
      {:error,
       Spark.Error.DslError.exception(
         message: "Duplicate plugin name: #{plugin.name}",
         path: [:plugins, plugin.name]
       )}
    else
      :ok
    end
  end
end