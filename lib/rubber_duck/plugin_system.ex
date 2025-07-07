defmodule RubberDuck.PluginSystem do
  @moduledoc """
  DSL for defining plugin configurations using Spark.

  This module provides a declarative way to configure plugins
  in the RubberDuck system.

  ## Example

      defmodule MyApp.Plugins do
        use RubberDuck.PluginSystem
        
        plugins do
          plugin :text_enhancer do
            module TextEnhancerPlugin
            config [
              max_length: 1000,
              language: "en"
            ]
            enabled true
            priority 100
          end
          
          plugin :code_formatter do
            module CodeFormatterPlugin
            config [
              style: :elixir,
              line_length: 98
            ]
            enabled true
            priority 50
          end
        end
      end
  """

  use Spark.Dsl, default_extensions: [extensions: [RubberDuck.PluginSystem.Dsl]]

  @doc """
  Returns all configured plugins.
  """
  def plugins(module) do
    Spark.Dsl.Extension.get_entities(module, [:plugins])
  end

  @doc """
  Returns a specific plugin by name.
  """
  def get_plugin(module, name) when is_atom(name) do
    module
    |> plugins()
    |> Enum.find(&(&1.name == name))
  end

  @doc """
  Returns enabled plugins sorted by priority.
  """
  def enabled_plugins(module) do
    module
    |> plugins()
    |> Enum.filter(& &1.enabled)
    |> Enum.sort_by(& &1.priority, :desc)
  end

  @doc """
  Returns plugins that depend on a specific plugin.
  """
  def dependent_plugins(module, plugin_name) when is_atom(plugin_name) do
    module
    |> plugins()
    |> Enum.filter(fn plugin ->
      plugin_name in (plugin.dependencies || [])
    end)
  end

  @doc """
  Loads all enabled plugins into the PluginManager.
  """
  def load_plugins(module) do
    module
    |> enabled_plugins()
    |> Enum.map(fn plugin ->
      case RubberDuck.PluginManager.register_plugin(plugin.module, plugin.config) do
        {:ok, name} ->
          if plugin.auto_start do
            RubberDuck.PluginManager.start_plugin(name)
          end

          {:ok, name}

        error ->
          error
      end
    end)
  end
end
