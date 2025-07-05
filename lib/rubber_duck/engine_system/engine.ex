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
    :pool_size,
    :max_overflow,
    :checkout_timeout,
    :__identifier__
  ]
  
  @type t :: %__MODULE__{
    name: atom(),
    module: module(),
    description: String.t() | nil,
    priority: integer(),
    timeout: timeout(),
    config: keyword(),
    pool_size: pos_integer(),
    max_overflow: non_neg_integer(),
    checkout_timeout: timeout(),
    __identifier__: term()
  }
end