defmodule RubberDuck.EngineSystem.Engine do
  @moduledoc """
  Represents an engine configuration in the engine system.
  
  This struct is created by the Spark DSL when defining engines.
  """
  
  defstruct [
    :name,
    :module,
    :description,
    :priority,
    :timeout,
    :config,
    :__identifier__
  ]
  
  @type t :: %__MODULE__{
    name: atom(),
    module: module(),
    description: String.t() | nil,
    priority: integer(),
    timeout: timeout(),
    config: keyword(),
    __identifier__: term()
  }
end