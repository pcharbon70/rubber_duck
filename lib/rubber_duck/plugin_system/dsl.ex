defmodule RubberDuck.PluginSystem.Dsl do
  @moduledoc """
  DSL extension for the PluginSystem.
  
  Provides the `plugins` section and `plugin` entity for
  declarative plugin configuration.
  """
  
  @plugin_schema [
    name: [
      type: :atom,
      required: true,
      doc: "Unique identifier for the plugin"
    ],
    module: [
      type: :atom,
      required: true,
      doc: "Module that implements the RubberDuck.Plugin behavior"
    ],
    config: [
      type: :keyword_list,
      required: false,
      default: [],
      doc: "Configuration to pass to the plugin"
    ],
    enabled: [
      type: :boolean,
      required: false,
      default: true,
      doc: "Whether the plugin is enabled"
    ],
    priority: [
      type: :integer,
      required: false,
      default: 50,
      doc: "Plugin priority (0-100, higher runs first)"
    ],
    dependencies: [
      type: {:list, :atom},
      required: false,
      default: [],
      doc: "List of plugin names this plugin depends on"
    ],
    auto_start: [
      type: :boolean,
      required: false,
      default: true,
      doc: "Whether to automatically start the plugin when loaded"
    ],
    description: [
      type: :string,
      required: false,
      doc: "Human-readable description of the plugin"
    ],
    tags: [
      type: {:list, :atom},
      required: false,
      default: [],
      doc: "Tags for categorizing plugins"
    ]
  ]
  
  @section %Spark.Dsl.Section{
    name: :plugins,
    top_level?: true,
    entities: [
      %Spark.Dsl.Entity{
        name: :plugin,
        target: RubberDuck.PluginSystem.Plugin,
        args: [:name],
        schema: @plugin_schema,
        identifier: :name
      }
    ]
  }
  
  use Spark.Dsl.Extension,
    sections: [@section],
    transformers: [
      RubberDuck.PluginSystem.Transformers.ValidatePlugins,
      RubberDuck.PluginSystem.Transformers.ResolveDependencies
    ]
end