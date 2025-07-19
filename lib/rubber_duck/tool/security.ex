defmodule RubberDuck.Tool.Security do
  @moduledoc """
  Represents tool security configuration.
  """

  defstruct [
    :sandbox,
    :capabilities,
    :rate_limit,
    :file_access,
    :network_access,
    :allowed_modules,
    :allowed_functions,
    :__identifier__
  ]

  @type t :: %__MODULE__{
          sandbox: :none | :strict | :balanced | :relaxed,
          capabilities: list(atom()),
          rate_limit: keyword() | nil,
          file_access: list(String.t()) | nil,
          network_access: boolean() | nil,
          allowed_modules: list(atom()) | nil,
          allowed_functions: list(atom()) | nil,
          __identifier__: term()
        }
end
