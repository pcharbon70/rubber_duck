defmodule RubberDuck.PluginSystem.Plugin do
  @moduledoc """
  Represents a plugin configuration in the PluginSystem DSL.
  """

  defstruct [
    :name,
    :module,
    :config,
    :enabled,
    :priority,
    :dependencies,
    :auto_start,
    :description,
    :tags,
    :__identifier__
  ]

  @type t :: %__MODULE__{
          name: atom(),
          module: module(),
          config: keyword(),
          enabled: boolean(),
          priority: integer(),
          dependencies: [atom()],
          auto_start: boolean(),
          description: String.t() | nil,
          tags: [atom()],
          __identifier__: any()
        }
end
