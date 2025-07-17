defmodule RubberDuck.Tool.Security do
  @moduledoc """
  Represents tool security configuration.
  """
  
  defstruct [
    :sandbox,
    :capabilities,
    :rate_limit,
    :__identifier__
  ]
  
  @type t :: %__MODULE__{
    sandbox: :none | :restricted | :isolated,
    capabilities: list(atom()),
    rate_limit: keyword() | nil,
    __identifier__: term()
  }
end