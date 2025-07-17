defmodule RubberDuck.Tool.Parameter do
  @moduledoc """
  Represents a tool parameter definition.
  """
  
  defstruct [
    :name,
    :type,
    :required,
    :default,
    :description,
    :constraints,
    :__identifier__
  ]
  
  @type t :: %__MODULE__{
    name: atom(),
    type: :string | :integer | :float | :boolean | :map | :list | :any,
    required: boolean(),
    default: any(),
    description: String.t() | nil,
    constraints: keyword(),
    __identifier__: term()
  }
end